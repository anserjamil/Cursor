using Maseera.Core.Dtos;
using Maseera.Data.Repositories;
using Maseera.Web.Startup;

namespace Maseera.Web.Models;

/* ---- stages -------------------------------------------------------------------- */

public sealed record StageViewModel
{
    public required StageStateRow State { get; init; }
    public required IReadOnlyList<StageTabRow> Tabs { get; init; }
    public required StagePage Page { get; init; }
    public IReadOnlyList<ColumnCatalogRow> Columns { get; init; } = [];
    public IReadOnlyList<SavedViewRow> SavedViews { get; init; } = [];
    public IReadOnlyList<string> ActiveColumns { get; init; } = [];
    public string? ActivePill { get; init; }
    public string? Search { get; init; }
    public string? SortBy { get; init; }
    public string? SortDir { get; init; }
    public string? FilterJson { get; init; }
    public int PageNo { get; init; } = 1;
    public bool CanWrite { get; init; }
    public string? TestModeNote { get; init; }

    /// <summary>The outcome pill, which is solid ink and sits on its own.</summary>
    public FunnelPillRow? Outcome => Page.Pills.FirstOrDefault(p => p.IsOutcome);

    /// <summary>The pills, grouped, with thin dividers between the groups.</summary>
    public IEnumerable<IGrouping<int, FunnelPillRow>> PillGroups
        => Page.Pills.Where(p => !p.IsOutcome).GroupBy(p => p.GroupNo).OrderBy(g => g.Key);

    /// <summary>"240 shown of 12,480."</summary>
    public string ShownOfTotal => $"{Page.Rows.Count:N0} shown of {Page.Totals.TotalRows:N0}";

    /// <summary>Too many to draw: the table offers an export rather than trying.</summary>
    public bool TooManyToDraw
        => Page.Totals.MaxDraw is { } max && Page.Totals.TotalRows > max;
}

public sealed record FocusPaneViewModel
{
    public required ProfilePage Profile { get; init; }
    public int CycleStageId { get; init; }

    /// <summary>
    /// The cycle the stage belongs to. The ladder is measured against a cycle's readiness
    /// levels, so the link out to the full profile has to carry it or the rungs vanish.
    /// </summary>
    public int? CycleId { get; init; }
    public bool CanWrite { get; init; }
}

public sealed record SuccessionViewModel
{
    public required StageStateRow State { get; init; }
    public required IReadOnlyList<StageTabRow> Tabs { get; init; }
    public required SuccessionPlans Plans { get; init; }
    public bool CanWrite { get; init; }
    public string? Search { get; init; }
    public string? Department { get; init; }
}

public sealed record ByPositionViewModel
{
    public required StageStateRow State { get; init; }
    public required IReadOnlyList<StageTabRow> Tabs { get; init; }
    public required SuccessionPositions Positions { get; init; }
    public bool CanWrite { get; init; }
    public string? Search { get; init; }
}

/* ---- the individual development plan ------------------------------------------- */

public sealed record IdpViewModel
{
    public required StageStateRow State { get; init; }
    public required IReadOnlyList<StageTabRow> Tabs { get; init; }
    public string ActiveTab { get; init; } = "overview";
    public bool CanWrite { get; init; }
    public string? Search { get; init; }
    public string? PersonnelNo { get; init; }
    public int? DevEventId { get; init; }
    public string? TestModeNote { get; init; }

    public IdpBoard? Board { get; init; }
    public IdpPersonPlan? Person { get; init; }
    public IReadOnlyList<IdpRequirementRow> Requirements { get; init; } = [];
    public int RequirementTotal { get; init; }
    public IReadOnlyList<IdpSessionRow> Sessions { get; init; } = [];
    public IReadOnlyList<IdpCoverageBoardRow> CoverageAssignments { get; init; } = [];
    public IReadOnlyList<IdpSuccessorRow> Successors { get; init; } = [];
    public IReadOnlyList<IdpConflictRow> Conflicts { get; init; } = [];
    public IReadOnlyList<IdpRiskRow> Risk { get; init; } = [];

    /// <summary>
    /// Flag filters appear only when there is something to filter, so an empty board is
    /// not covered in controls that would each select nothing.
    /// </summary>
    public bool ShowOverdueFilter => (Board?.Summary?.Overdue ?? 0) > 0;
    public bool ShowApproveAll => (Board?.Summary?.ReadyToApprove ?? 0) > 0;
}

/* ---- reads --------------------------------------------------------------------- */

public sealed record CompareViewModel
{
    public IReadOnlyList<CompareRow> People { get; init; } = [];
    public string? Problem { get; init; }
    public int Max { get; init; } = 6;
    public int? CycleId { get; init; }
}

public sealed record RosterViewModel
{
    public IReadOnlyList<PoolPersonRow> Rows { get; init; } = [];
    public int TotalRows { get; init; }
    public string? Problem { get; init; }
    public string? Search { get; init; }
    public string? OrgCode { get; init; }
    public string? SortBy { get; init; }
    public string? SortDir { get; init; }
    public int PageNo { get; init; } = 1;
    public int PageSize { get; init; } = 50;

    public string ShownOfTotal => $"{Rows.Count:N0} shown of {TotalRows:N0}";
    public int PageCount => PageSize <= 0 ? 1 : (int)Math.Ceiling(TotalRows / (double)PageSize);
}

public sealed record ProfileViewModel
{
    public required ProfilePage Profile { get; init; }
    public int? CycleId { get; init; }
}

public sealed record ReportsViewModel
{
    public IReadOnlyList<ReportDefinitionRow> Definitions { get; init; } = [];
    public IReadOnlyList<CycleRow> Cycles { get; init; } = [];
    public string? ActiveKey { get; init; }
    public int? CycleId { get; init; }
    public ReportResult? Result { get; init; }

    public ReportDefinitionRow? Active
        => Definitions.FirstOrDefault(d => d.ReportKey == ActiveKey);

    /// <summary>
    /// A report's rows arrive as dictionaries because the columns are rows in
    /// sel.ReportDefinition, not a compiled shape. This reads one cell by key.
    /// </summary>
    public static object? Cell(IDictionary<string, object?> row, string key)
        => row.TryGetValue(key, out var value) ? value : null;

    /// <summary>
    /// A share column never carries a percentage. The procedure returns the numerator and
    /// the denominator — ShareCount where the report distinguishes it from the headline
    /// count, Cnt otherwise — and the one formatter turns them into words. That is what
    /// keeps "0 of 300" from ever reading as a bare 0% beside a non-zero count.
    /// </summary>
    public static (long Count, long Total) Share(IDictionary<string, object?> row)
        => (ToLong(Cell(row, "ShareCount") ?? Cell(row, "Cnt")), ToLong(Cell(row, "ShareOf")));

    private static long ToLong(object? value)
        => value is null || value is DBNull ? 0L : Convert.ToInt64(value);
}

public sealed record DecisionLogViewModel
{
    public required DecisionLog Log { get; init; }
    public IReadOnlyList<CycleRow> Cycles { get; init; } = [];
    public int? CycleId { get; init; }
    public string? ActiveDecision { get; init; }
    public string? Search { get; init; }
    public bool? TestOnly { get; init; }
    public int PageNo { get; init; } = 1;
    public int PageSize { get; init; } = 50;

    public int PageCount => PageSize <= 0 ? 1 : (int)Math.Ceiling(Log.TotalRows / (double)PageSize);
}

/* ---- configuration ------------------------------------------------------------- */

public sealed record DevFrameworkViewModel
{
    public string ActiveTab { get; init; } = "events";
    public string? Search { get; init; }
    public string? PartCode { get; init; }
    public string? TypeCode { get; init; }
    public int? SelectedId { get; init; }
    public bool CanWrite { get; init; }

    public IReadOnlyList<DevEventRow> Events { get; init; } = [];
    public EventRuleDetail? Rule { get; init; }
    public IReadOnlyList<FrameworkRow> Frameworks { get; init; } = [];
    public FrameworkEditor? Editor { get; init; }
    public IReadOnlyList<MixtureModelRow> MixtureModels { get; init; } = [];
    public IReadOnlyList<MixturePartRow> MixtureParts { get; init; } = [];
    public IReadOnlyList<EvidenceSourceRow> Sources { get; init; } = [];
    public IReadOnlyList<EvidenceSourceColumnRow> SourceColumns { get; init; } = [];

    public IReadOnlyList<DomainValueRow> Parts { get; init; } = [];
    public IReadOnlyList<DomainValueRow> EventTypes { get; init; } = [];
    public IReadOnlyList<DomainValueRow> Measures { get; init; } = [];
    public IReadOnlyList<DomainValueRow> Phases { get; init; } = [];
    public IReadOnlyList<DomainValueRow> SetModes { get; init; } = [];
    public IReadOnlyList<DomainValueRow> SetJoins { get; init; } = [];
    public IReadOnlyList<OperatorRow> Operators { get; init; } = [];
}

public sealed record ItemDetailViewModel
{
    public IReadOnlyList<ItemMetPersonRow> People { get; init; } = [];
    public required ItemMetTotals Totals { get; init; }
    public string ItemCode { get; init; } = string.Empty;
    public bool MetOnly { get; init; }
    public int PageNo { get; init; } = 1;
}

public sealed record RosterFieldsViewModel
{
    public IReadOnlyList<RosterFieldRow> Fields { get; init; } = [];
    public required RosterFieldSummary Summary { get; init; }
    public string? Search { get; init; }
    public bool EnabledOnly { get; init; }
    public bool CanWrite { get; init; }
}

public sealed record TableMappingViewModel
{
    public IReadOnlyList<TableMappingRow> Tables { get; init; } = [];
    public IReadOnlyDictionary<string, IReadOnlyList<TableMappingColumnRow>> ColumnsBySource { get; init; }
        = new Dictionary<string, IReadOnlyList<TableMappingColumnRow>>();
    public bool CanWrite { get; init; }

    public int UnmappedCount => Tables.Count(t => !t.IsMapped);
    public int RequiredUnmapped => Tables.Count(t => !t.IsMapped && t.IsRequired);
}

public sealed record RefDataViewModel
{
    public IReadOnlyList<DomainRow> Domains { get; init; } = [];
    public string? ActiveDomain { get; init; }
    public IReadOnlyList<DomainValueRow> Values { get; init; } = [];
    public IReadOnlyList<CatalogItemRow> Catalog { get; init; } = [];
    public bool CanWrite { get; init; }
}

/* ---- access -------------------------------------------------------------------- */

public sealed record PolicyViewModel
{
    public IReadOnlyList<RoleRow> Roles { get; init; } = [];
    public IReadOnlyList<PolicyScreenRow> Screens { get; init; } = [];
    public IReadOnlyDictionary<(int RoleId, int ScreenId), short?> Grants { get; init; }
        = new Dictionary<(int, int), short?>();
    public IReadOnlyList<AppUserRow> Users { get; init; } = [];
    public IReadOnlyList<UserOverrideRow> Overrides { get; init; } = [];
    public string? ExplainLogin { get; init; }
    public IReadOnlyList<ScreenAccessExplainRow> Explanation { get; init; } = [];
    public string? Search { get; init; }
    public bool CanWrite { get; init; }

    public short? Grant(int roleId, int screenId)
        => Grants.TryGetValue((roleId, screenId), out var g) ? g : null;
}

public sealed record RlsViewModel
{
    public IReadOnlyList<OrgTreeRow> Tree { get; init; } = [];
    public IReadOnlyList<AppUserRow> Users { get; init; } = [];
    public string Viewer { get; init; } = string.Empty;
    public string? CompareWith { get; init; }
    public IReadOnlyList<RlsCompareRow> Comparison { get; init; } = [];

    public int GrantedCount => Tree.Count(t => t.IsGranted);
    public int TotalCount => Tree.Count;
}

public sealed record LoadExceptionsViewModel
{
    public IReadOnlyList<LoadExceptionRow> Rows { get; init; } = [];
    public int TotalRows { get; init; }
    public IReadOnlyList<(string SourceKey, int Unresolved)> BySource { get; init; } = [];
    public string? SourceKey { get; init; }
    public bool IncludeResolved { get; init; }
    public string? Search { get; init; }
    public int PageNo { get; init; } = 1;
    public int PageSize { get; init; } = 50;
    public bool CanWrite { get; init; }

    public int PageCount => PageSize <= 0 ? 1 : (int)Math.Ceiling(TotalRows / (double)PageSize);
}

public sealed record HealthViewModel
{
    public required SelfCheckReport Report { get; init; }
    public required ChangeLogPage RecentChanges { get; init; }
}
