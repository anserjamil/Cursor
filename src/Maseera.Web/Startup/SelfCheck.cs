using Maseera.Core.Dtos;
using Maseera.Data.Repositories;
using Microsoft.AspNetCore.Mvc.Controllers;
using Microsoft.AspNetCore.Mvc.Infrastructure;

namespace Maseera.Web.Startup;

/// <summary>
/// Fail loudly at startup, not on the screen that needs the row.
///
/// Four questions: is the database reachable, is every configuration and reference table
/// populated, is every evidence source mapped, and does every registered screen resolve
/// to a controller action that actually exists. The first two are fatal — an application
/// that starts without its configuration will fail later, further from the cause. The
/// last two are reported and shown on /Admin/Health, because a half-mapped installation
/// is a real state somebody has to work in.
/// </summary>
public sealed class SelfCheck
{
    private readonly IServiceProvider _services;
    private readonly ILogger<SelfCheck> _log;

    public SelfCheck(IServiceProvider services, ILogger<SelfCheck> log)
    {
        _services = services;
        _log = log;
    }

    public async Task<SelfCheckReport> RunAsync(bool throwOnFatal, CancellationToken ct = default)
    {
        var lines = new List<SelfCheckLine>();

        using var scope = _services.CreateScope();
        var config = scope.ServiceProvider.GetRequiredService<ConfigRepository>();
        var framework = scope.ServiceProvider.GetRequiredService<FrameworkRepository>();

        // 1 — the database, asked through a procedure like everything else.
        IReadOnlyList<HealthRow> health;
        try
        {
            health = await config.HealthAsync(ct);
            lines.Add(new SelfCheckLine("Database", "Reachable", true, "DB02 answered."));
        }
        catch (Exception ex)
        {
            lines.Add(new SelfCheckLine("Database", "Reachable", false,
                "DB02 could not be reached: " + ex.Message));

            var fatal = new SelfCheckReport(lines, HasFatal: true);
            Report(fatal);
            if (throwOnFatal)
                throw new InvalidOperationException(
                    "Maseera cannot start: DB02 could not be reached. " + ex.Message, ex);
            return fatal;
        }

        // 2 and 3 — the counts and the mapped sources, as cfg.usp_Health_Check reports them.
        foreach (var row in health)
        {
            lines.Add(new SelfCheckLine(
                row.Group, row.CheckName, row.IsOk ?? true,
                row.Note ?? $"{row.Actual:N0}"));
        }

        // A source with items pointing at it and no table mapped is called out by name,
        // because "requirements can never be met" is not something to discover later.
        try
        {
            var (sources, _) = await framework.EvidenceSourcesAsync(ct);
            foreach (var s in sources.Where(s => !s.IsMapped))
            {
                lines.Add(new SelfCheckLine("Evidence", s.KindName, false,
                    s.Warning ?? "No table is mapped for this kind."));
            }
        }
        catch (Exception ex)
        {
            lines.Add(new SelfCheckLine("Evidence", "Sources", false,
                "The evidence sources could not be read: " + ex.Message));
        }

        // 4 — every registered screen resolves to a controller action that exists.
        lines.AddRange(await CheckScreensAsync(scope.ServiceProvider, config, ct));

        var report = new SelfCheckReport(
            lines,
            HasFatal: lines.Any(l => !l.IsOk && l.Group is "Database" or "Configuration"));

        Report(report);

        if (report.HasFatal && throwOnFatal)
        {
            var problems = string.Join("; ", report.Lines.Where(l => !l.IsOk).Select(l => l.Note));
            throw new InvalidOperationException("Maseera cannot start: " + problems);
        }

        return report;
    }

    private static async Task<List<SelfCheckLine>> CheckScreensAsync(
        IServiceProvider services, ConfigRepository config, CancellationToken ct)
    {
        var lines = new List<SelfCheckLine>();

        var screens = await config.AllScreensAsync(ct);
        var actions = services.GetRequiredService<IActionDescriptorCollectionProvider>()
            .ActionDescriptors.Items
            .OfType<ControllerActionDescriptor>()
            .Select(a => Key(
                a.RouteValues.TryGetValue("area", out var area) ? area : null,
                a.ControllerName, a.ActionName))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        var missing = screens
            .Where(s => s.IsActive)
            .Where(s => !actions.Contains(Key(s.AreaName, s.ControllerName, s.ActionName)))
            .ToList();

        lines.Add(new SelfCheckLine(
            "Screens", "Registered screens resolve to an action",
            missing.Count == 0,
            missing.Count == 0
                ? $"{screens.Count(s => s.IsActive):N0} screens, all resolvable."
                : "Not resolvable: " + string.Join(", ",
                    missing.Select(m => $"{m.ScreenCode} → {m.AreaName}/{m.ControllerName}.{m.ActionName}"))));

        return lines;

        static string Key(string? area, string controller, string action)
            => $"{area}|{controller}|{action}";
    }

    private void Report(SelfCheckReport report)
    {
        foreach (var line in report.Lines)
        {
            if (line.IsOk)
                _log.LogInformation("Self-check {Group}/{Check}: {Note}", line.Group, line.CheckName, line.Note);
            else
                _log.LogError("Self-check {Group}/{Check} FAILED: {Note}", line.Group, line.CheckName, line.Note);
        }
    }
}

public sealed record SelfCheckLine(string Group, string CheckName, bool IsOk, string? Note);

public sealed record SelfCheckReport(IReadOnlyList<SelfCheckLine> Lines, bool HasFatal)
{
    public bool AllGreen => Lines.All(l => l.IsOk);
}
