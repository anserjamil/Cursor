using Maseera.Core.Dtos;
using Maseera.Data.Repositories;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace Maseera.Data;

/// <summary>
/// The cfg.* tables, held in memory and invalidated on a CONTENT stamp.
///
/// Part 12.3: editing a rule changes no row count, so a length-based or count-based cache
/// key serves a STALE answer after the edit. The stamp is a hash of the content of every
/// cfg table, and it is set BEFORE the content is read — set it after and the cache clears
/// on every call and thrashes.
/// </summary>
public interface IConfigCache
{
    Task<string> StampAsync(CancellationToken ct = default);
    Task<IReadOnlyList<SettingRow>> SettingsAsync(CancellationToken ct = default);
    Task<IReadOnlyList<MessageRow>> MessagesAsync(CancellationToken ct = default);

    /// <summary>A setting's number, or the fallback when it is not configured.</summary>
    Task<decimal> NumberAsync(string key, decimal fallback, CancellationToken ct = default);

    /// <summary>A setting's text, or null.</summary>
    Task<string?> TextAsync(string key, CancellationToken ct = default);

    /// <summary>
    /// A user-visible sentence by key. A missing row renders as [KEY] on screen rather
    /// than as a blank, so it is noticed and fixed.
    /// </summary>
    Task<string> MessageAsync(string key, CancellationToken ct = default);

    /// <summary>Drops the cache, so the next read reloads. Called after a configuration write.</summary>
    void Invalidate();
}

public sealed class ConfigCache : IConfigCache
{
    private readonly IServiceProvider _services;
    private readonly ILogger<ConfigCache> _log;
    private readonly SemaphoreSlim _gate = new(1, 1);

    private Snapshot? _snapshot;

    public ConfigCache(IServiceProvider services, ILogger<ConfigCache> log)
    {
        _services = services;
        _log = log;
    }

    public void Invalidate() => _snapshot = null;

    public async Task<string> StampAsync(CancellationToken ct = default)
        => (await LoadAsync(ct)).Stamp;

    public async Task<IReadOnlyList<SettingRow>> SettingsAsync(CancellationToken ct = default)
        => (await LoadAsync(ct)).Settings;

    public async Task<IReadOnlyList<MessageRow>> MessagesAsync(CancellationToken ct = default)
        => (await LoadAsync(ct)).Messages;

    public async Task<decimal> NumberAsync(string key, decimal fallback, CancellationToken ct = default)
    {
        var snap = await LoadAsync(ct);
        return snap.SettingsByKey.TryGetValue(key, out var row) && row.NumValue.HasValue
            ? row.NumValue.Value
            : fallback;
    }

    public async Task<string?> TextAsync(string key, CancellationToken ct = default)
    {
        var snap = await LoadAsync(ct);
        return snap.SettingsByKey.TryGetValue(key, out var row) ? row.TextValue : null;
    }

    public async Task<string> MessageAsync(string key, CancellationToken ct = default)
    {
        var snap = await LoadAsync(ct);
        return snap.MessagesByKey.TryGetValue(key, out var row) ? row.MessageText : $"[{key}]";
    }

    private async Task<Snapshot> LoadAsync(CancellationToken ct)
    {
        var current = _snapshot;
        if (current is not null) return current;

        await _gate.WaitAsync(ct);
        try
        {
            if (_snapshot is not null) return _snapshot;

            // A scope of its own, because the runner and the user context are scoped and
            // this cache is a singleton.
            using var scope = _services.CreateScope();
            var repo = scope.ServiceProvider.GetRequiredService<ConfigRepository>();

            // The stamp is read FIRST. Reading it last would mean any edit that landed
            // between the two reads is already in the content but not in the key, and the
            // cache would look fresh while holding the old answer.
            var stamp = await repo.StampAsync(ct);
            var settings = await repo.SettingsAsync(ct);
            var messages = await repo.MessagesAsync(ct);

            _snapshot = new Snapshot(
                stamp?.Stamp ?? string.Empty,
                settings,
                messages,
                settings.ToDictionary(s => s.SettingKey, StringComparer.OrdinalIgnoreCase),
                messages.ToDictionary(m => m.MessageKey, StringComparer.OrdinalIgnoreCase));

            _log.LogInformation(
                "Configuration cache loaded at stamp {Stamp}: {Settings} settings, {Messages} messages.",
                _snapshot.Stamp[..Math.Min(8, _snapshot.Stamp.Length)], settings.Count, messages.Count);

            return _snapshot;
        }
        finally
        {
            _gate.Release();
        }
    }

    private sealed record Snapshot(
        string Stamp,
        IReadOnlyList<SettingRow> Settings,
        IReadOnlyList<MessageRow> Messages,
        IReadOnlyDictionary<string, SettingRow> SettingsByKey,
        IReadOnlyDictionary<string, MessageRow> MessagesByKey);
}

/// <summary>Message keys the application refers to by name. The text lives in cfg.Message.</summary>
public static class MessageKeys
{
    public const string ReadOnlyRefusal = "READONLY_REFUSAL";
    public const string ClosedCycle = "CLOSED_CYCLE";
    public const string SourceUnmapped = "SOURCE_UNMAPPED";
    public const string SampledFigures = "SAMPLED_FIGURES";
    public const string ShareUnderOne = "SHARE_UNDER_ONE";
    public const string ShareOverNinetyNine = "SHARE_OVER_NINETY_NINE";
    public const string PoolEmpty = "POOL_EMPTY";
    public const string NoCycles = "NO_CYCLES";
    public const string SensitiveFilter = "SENSITIVE_FILTER";
    public const string SuggestionsAdvisory = "SUGGESTIONS_ADVISORY";
    public const string TestModeOn = "TEST_MODE_ON";
    public const string IdpCoverageManual = "IDP_COVERAGE_MANUAL";
    public const string IdpNotReady = "IDP_NOT_READY";
    public const string RosterUnmapped = "ROSTER_UNMAPPED";
}

/// <summary>Setting keys, likewise. The values live in cfg.Setting.</summary>
public static class SettingKeys
{
    public const string AttainmentSampleCap = "ATTAINMENT_SAMPLE_CAP";
    public const string PageSizeDefault = "PAGE_SIZE_DEFAULT";
    public const string PageSizeMax = "PAGE_SIZE_MAX";
    public const string WeightTotalTarget = "WEIGHT_TOTAL_TARGET";
    public const string ContentMaxWidthPx = "CONTENT_MAX_WIDTH_PX";
    public const string CompareMax = "COMPARE_MAX";
    public const string ValidationMaxShown = "VALIDATION_MAX_SHOWN";
    public const string StageListMaxDraw = "STAGE_LIST_MAX_DRAW";
    public const string AsOfOverride = "AS_OF_OVERRIDE";
}
