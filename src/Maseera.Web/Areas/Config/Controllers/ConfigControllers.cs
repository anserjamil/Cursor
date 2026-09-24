using Maseera.Data.Repositories;
using Maseera.Web.Controllers;
using Maseera.Web.Models;
using Maseera.Web.Security;
using Microsoft.AspNetCore.Mvc;

namespace Maseera.Web.Areas.Config.Controllers;

/// <summary>
/// The development framework: events, frameworks, the mixture model, the data sources,
/// and the rule editor.
///
/// The list's rule column renders sel.fn_EventRuleShort. Nothing here composes a sentence
/// about a rule — that is how a list and its rule drift apart.
/// </summary>
[Area("Config")]
public sealed class DevFrameworkController : MaseeraController
{
    public const string Screen = "/Selection/Setup/";

    private readonly FrameworkRepository _frameworks;
    private readonly ConfigRepository _config;

    public DevFrameworkController(FrameworkRepository frameworks, ConfigRepository config)
    {
        _frameworks = frameworks;
        _config = config;
    }

    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> Index(
        string tab = "events", string? q = null, string? part = null, string? type = null,
        int? id = null, CancellationToken ct = default)
    {
        var vm = new DevFrameworkViewModel
        {
            ActiveTab = tab, Search = q, PartCode = part, TypeCode = type,
            CanWrite = CanWrite, SelectedId = id
        };

        switch (tab)
        {
            case "frameworks":
                vm = vm with
                {
                    Frameworks = await _frameworks.ListAsync(q, ct: ct),
                    Editor = id is not null ? await _frameworks.DetailAsync(id.Value, ct) : null,
                    Events = id is not null ? await _frameworks.EventsAsync(activeOnly: true, ct: ct) : [],
                    MixtureModels = (await _frameworks.MixtureModelsAsync(ct)).Models
                };
                break;

            case "mixture":
                var (models, parts) = await _frameworks.MixtureModelsAsync(ct);
                vm = vm with
                {
                    MixtureModels = models,
                    MixtureParts = parts,
                    Parts = await _config.DomainValuesAsync("PART", ct)
                };
                break;

            case "sources":
                var (sources, columns) = await _frameworks.EvidenceSourcesAsync(ct);
                vm = vm with { Sources = sources, SourceColumns = columns };
                break;

            default:
                vm = vm with
                {
                    Events = await _frameworks.EventsAsync(q, part, type, ct: ct),
                    Rule = id is not null ? await _frameworks.EventDetailAsync(id.Value, ct) : null,
                    Parts = await _config.DomainValuesAsync("PART", ct),
                    EventTypes = await _config.DomainValuesAsync("EVENT_TYPE", ct),
                    Measures = await _config.DomainValuesAsync("MEASURE", ct),
                    Phases = await _config.DomainValuesAsync("PHASE", ct),
                    SetModes = await _config.DomainValuesAsync("SET_MODE", ct),
                    SetJoins = await _config.DomainValuesAsync("SET_JOIN", ct),
                    Operators = await _config.OperatorsAsync(ct: ct)
                };
                break;
        }

        return IsAjax ? PartialView("_Tab" + char.ToUpperInvariant(tab[0]) + tab[1..], vm) : View(vm);
    }

    /* ---- events and their rules ------------------------------------------------- */

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> SaveEvent(
        int? devEventId, string eventCode, string name, string? description, string kindCode,
        string? itemCode, string? eventTypeCode, string? partCode, string? measureCode,
        string? phaseCode, string? passValue, decimal? sumFloor, int? validityMonths,
        DateOnly? retiredFrom, bool isActive = true, CancellationToken ct = default)
        => WriteAsync(
            () => _frameworks.SaveEventAsync(devEventId, eventCode, name, description, kindCode,
                itemCode, eventTypeCode, partCode, measureCode, phaseCode, passValue, sumFloor,
                validityMonths, retiredFrom, isActive, ct),
            $"{eventCode} was saved.",
            () => RedirectToAction(nameof(Index), new { tab = "events", id = devEventId }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> DeleteEvent(int devEventId, CancellationToken ct = default)
        => WriteAsync(
            () => _frameworks.DeleteEventAsync(devEventId, ct),
            "The event was deleted.",
            () => RedirectToAction(nameof(Index), new { tab = "events" }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> SaveConditionSet(
        int devEventId, int? setId, string setModeCode, string? setJoinCode, CancellationToken ct = default)
        => WriteAsync(
            () => _frameworks.SaveConditionSetAsync(devEventId, setId, setModeCode, setJoinCode, ct),
            "The set was saved.",
            () => RedirectToAction(nameof(Index), new { tab = "events", id = devEventId }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> DeleteConditionSet(int devEventId, int setId, CancellationToken ct = default)
        => WriteAsync(
            () => _frameworks.DeleteConditionSetAsync(setId, ct),
            "The set was removed.",
            () => RedirectToAction(nameof(Index), new { tab = "events", id = devEventId }));

    /// <summary>
    /// A field typed here is learned into the source's column list and offered to every
    /// event after, so the next author picks from a list instead of guessing a spelling.
    /// </summary>
    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> SaveCondition(
        int devEventId, int setId, int? conditionId, string? fieldName, string? operatorCode,
        string? value1, string? value2, CancellationToken ct = default)
        => WriteAsync(
            () => _frameworks.SaveConditionAsync(setId, conditionId, fieldName, operatorCode, value1, value2, ct),
            "The condition was saved.",
            () => RedirectToAction(nameof(Index), new { tab = "events", id = devEventId }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> DeleteCondition(int devEventId, int conditionId, CancellationToken ct = default)
        => WriteAsync(
            () => _frameworks.DeleteConditionAsync(conditionId, ct),
            "The condition was removed.",
            () => RedirectToAction(nameof(Index), new { tab = "events", id = devEventId }));

    /// <summary>The one-click revert back to the kind's default.</summary>
    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> RevertRule(int devEventId, CancellationToken ct = default)
        => WriteAsync(
            () => _frameworks.RevertRuleAsync(devEventId, ct),
            "This event follows its kind's default again.",
            () => RedirectToAction(nameof(Index), new { tab = "events", id = devEventId }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> AddEquivalence(
        int devEventId, string mainItemCode, string equivalentItemCode, string? note,
        CancellationToken ct = default)
        => WriteAsync(
            () => _frameworks.AddEquivalenceAsync(mainItemCode, equivalentItemCode, note, ct),
            $"{equivalentItemCode} now counts for {mainItemCode}.",
            () => RedirectToAction(nameof(Index), new { tab = "events", id = devEventId }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> RemoveEquivalence(int devEventId, int devEquivalenceId, CancellationToken ct = default)
        => WriteAsync(
            () => _frameworks.RemoveEquivalenceAsync(devEquivalenceId, ct),
            "The equivalence was removed.",
            () => RedirectToAction(nameof(Index), new { tab = "events", id = devEventId }));

    /// <summary>"Applies to N of the pool", live, clickable through to the people.</summary>
    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> AppliesTo(
        int cycleId, string itemCode, bool metOnly = true, int page = 1, CancellationToken ct = default)
    {
        var (people, totals) = await _frameworks.ItemDetailAsync(cycleId, itemCode, metOnly, page, ct: ct);
        return PartialView("_ItemDetail", new ItemDetailViewModel
        {
            People = people, Totals = totals, ItemCode = itemCode, MetOnly = metOnly, PageNo = page
        });
    }

    /* ---- frameworks ------------------------------------------------------------- */

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> SaveFramework(
        int? devFrameworkId, string frameworkCode, string name, string? description,
        string statusCode, bool usesLevels, int? mixtureModelId, CancellationToken ct = default)
        => WriteAsync(
            () => _frameworks.SaveAsync(devFrameworkId, frameworkCode, name, description,
                statusCode, usesLevels, mixtureModelId, ct),
            $"{name} was saved.",
            () => RedirectToAction(nameof(Index), new { tab = "frameworks", id = devFrameworkId }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> SaveFrameworkItem(
        int devFrameworkId, int? devFrameworkItemId, int devEventId, int levelNo,
        string? levelName, decimal weight, bool isMust, CancellationToken ct = default)
        => WriteAsync(
            () => _frameworks.SaveItemAsync(devFrameworkId, devFrameworkItemId, devEventId,
                levelNo, levelName, weight, isMust, null, ct),
            "The requirement was saved.",
            () => RedirectToAction(nameof(Index), new { tab = "frameworks", id = devFrameworkId }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> DeleteFrameworkItem(
        int devFrameworkId, int devFrameworkItemId, CancellationToken ct = default)
        => WriteAsync(
            () => _frameworks.DeleteItemAsync(devFrameworkItemId, ct),
            "The requirement was removed.",
            () => RedirectToAction(nameof(Index), new { tab = "frameworks", id = devFrameworkId }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> RemoveLevel(int devFrameworkId, int levelNo, CancellationToken ct = default)
        => WriteAsync(
            () => _frameworks.RemoveLevelAsync(devFrameworkId, levelNo, ct),
            "The level was removed, and its requirements moved to the first.",
            () => RedirectToAction(nameof(Index), new { tab = "frameworks", id = devFrameworkId }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> DuplicateFramework(
        int devFrameworkId, string newCode, string newName, CancellationToken ct = default)
        => WriteAsync(
            () => _frameworks.DuplicateAsync(devFrameworkId, newCode, newName, ct),
            $"{newName} was created as a draft.",
            () => RedirectToAction(nameof(Index), new { tab = "frameworks" }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> RetireFramework(int devFrameworkId, CancellationToken ct = default)
        => WriteAsync(
            () => _frameworks.RetireAsync(devFrameworkId, null, ct),
            "The framework was retired.",
            () => RedirectToAction(nameof(Index), new { tab = "frameworks" }));

    /* ---- mixture and sources ---------------------------------------------------- */

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> SaveMixtureModel(
        int? mixtureModelId, string modelCode, string name, string? description,
        decimal tolerancePct, CancellationToken ct = default)
        => WriteAsync(
            () => _frameworks.SaveMixtureModelAsync(mixtureModelId, modelCode, name, description, tolerancePct, ct),
            "The model was saved.",
            () => RedirectToAction(nameof(Index), new { tab = "mixture" }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> SaveMixturePart(
        int mixtureModelId, string partCode, decimal targetPct, CancellationToken ct = default)
        => WriteAsync(
            () => _frameworks.SaveMixturePartAsync(mixtureModelId, partCode, targetPct, ct),
            "The target was saved.",
            () => RedirectToAction(nameof(Index), new { tab = "mixture" }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> SaveSource(
        string kindCode, string? sourceKey, string? itemColumn, string? statusColumn,
        string? passValue, string? measureColumn, CancellationToken ct = default)
        => WriteAsync(
            () => _frameworks.SaveEvidenceSourceAsync(kindCode, sourceKey, itemColumn,
                statusColumn, passValue, measureColumn, ct),
            "The source was saved.",
            () => RedirectToAction(nameof(Index), new { tab = "sources" }));

    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> Download(string? q = null, CancellationToken ct = default)
    {
        var events = await _frameworks.EventsAsync(q, ct: ct);
        var rows = events.Select(e => (IDictionary<string, object?>)new Dictionary<string, object?>
        {
            ["Code"] = e.EventCode,
            ["Name"] = e.Name,
            ["Kind"] = e.KindName,
            ["Type"] = e.EventTypeName,
            ["Part"] = e.PartName,
            ["Measure"] = e.MeasureName,
            ["Phase"] = e.PhaseName,
            ["Item code"] = e.ItemCode,
            ["Pass value"] = e.PassValue,
            ["Floor"] = e.SumFloor,
            ["Rule"] = e.RuleShort,
            ["Equivalents"] = e.EquivalentCount,
            ["In frameworks"] = e.FrameworkCount,
            ["Active"] = e.IsActive
        }).ToList();

        return Downloads.Csv(rows, $"maseera-events-{User_.AsOf:yyyy-MM-dd}");
    }
}

/// <summary>
/// Every roster column, discovered switched off. Enabled means usable in criteria;
/// sensitive means readable on a profile and refused as a filter. The screen has to make
/// that distinction visible.
/// </summary>
[Area("Config")]
public sealed class RosterFieldsController : MaseeraController
{
    public const string Screen = "/Config/RosterFields/";

    private readonly RosterRepository _roster;

    public RosterFieldsController(RosterRepository roster) => _roster = roster;

    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> Index(string? q = null, bool enabledOnly = false, CancellationToken ct = default)
    {
        var (fields, summary) = await _roster.FieldsAsync(q, enabledOnly, ct);
        return View(new RosterFieldsViewModel
        {
            Fields = fields, Summary = summary, Search = q,
            EnabledOnly = enabledOnly, CanWrite = CanWrite
        });
    }

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> Save(
        int rosterFieldId, string? caption, bool? isEnabled, bool? isSensitive,
        string? groupName, CancellationToken ct = default)
        => WriteAsync(
            () => _roster.SaveFieldAsync(rosterFieldId, caption, isEnabled, isSensitive, groupName, ct),
            "The field was saved.",
            () => RedirectToAction(nameof(Index)));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> Sync(CancellationToken ct = default)
        => WriteAsync(
            () => _roster.SyncFieldsAsync(ct),
            "The roster's columns were re-read. New ones arrive switched off.",
            () => RedirectToAction(nameof(Index)));
}

/// <summary>
/// Every table the application reads is named here, with what reads it and what breaks if
/// it is unmapped. A missing source is never a silent zero.
/// </summary>
[Area("Config")]
public sealed class TableMappingController : MaseeraController
{
    public const string Screen = "/Config/TableMapping/";

    private readonly RosterRepository _roster;

    public TableMappingController(RosterRepository roster) => _roster = roster;

    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> Index(CancellationToken ct = default)
    {
        var (tables, columns) = await _roster.MappingAsync(ct);
        return View(new TableMappingViewModel
        {
            Tables = tables,
            ColumnsBySource = columns.GroupBy(c => c.SourceKey)
                .ToDictionary(g => g.Key, g => (IReadOnlyList<Maseera.Core.Dtos.TableMappingColumnRow>)g.ToList()),
            CanWrite = CanWrite
        });
    }

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> Save(
        string sourceKey, string schemaName, string tableName, string? keyColumn,
        string? itemColumn, CancellationToken ct = default)
        => WriteAsync(
            () => _roster.SaveMappingAsync(sourceKey, schemaName, tableName, keyColumn, itemColumn, ct),
            $"{sourceKey} was remapped, and its columns re-read.",
            () => RedirectToAction(nameof(Index)));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> Discover(string? sourceKey = null, CancellationToken ct = default)
        => WriteAsync(
            () => _roster.DiscoverMappingAsync(sourceKey, ct),
            "The mapped tables were re-read from the database.",
            () => RedirectToAction(nameof(Index)));
}

/// <summary>
/// Browse the reference lists and edit their values. A system list refuses deletion of a
/// code and says why.
/// </summary>
[Area("Config")]
public sealed class RefDataController : MaseeraController
{
    public const string Screen = "/Config/RefData/";

    private readonly ConfigRepository _config;

    public RefDataController(ConfigRepository config) => _config = config;

    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> Index(string? domain = null, CancellationToken ct = default)
    {
        var domains = await _config.DomainsAsync(ct);
        var chosen = domain ?? domains.FirstOrDefault()?.DomainCode;

        return View(new RefDataViewModel
        {
            Domains = domains,
            ActiveDomain = chosen,
            Values = chosen is null ? [] : await _config.DomainValuesAsync(chosen, ct),
            Catalog = await _config.CatalogAsync(ct: ct),
            CanWrite = CanWrite
        });
    }

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> SaveValue(
        string domainCode, int? domainValueId, string valueCode, string name,
        string? description, string? semanticRole, int? sortOrder, bool isActive = true,
        CancellationToken ct = default)
        => WriteAsync(
            () => _config.SaveDomainValueAsync(domainCode, domainValueId, valueCode, name,
                description, semanticRole, sortOrder, isActive, ct),
            $"{name} was saved.",
            () => RedirectToAction(nameof(Index), new { domain = domainCode }));

    [HttpPost]
    [ScreenAccess(Screen, Write = true)]
    public Task<IActionResult> DeleteValue(string domainCode, int domainValueId, CancellationToken ct = default)
        => WriteAsync(
            () => _config.DeleteDomainValueAsync(domainValueId, ct),
            "The value was removed.",
            () => RedirectToAction(nameof(Index), new { domain = domainCode }));
}
