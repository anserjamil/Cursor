using Dapper;
using Maseera.Core.Dtos;

namespace Maseera.Data.Repositories;

public sealed class ReportRepository
{
    private readonly IProcRunner _run;

    public ReportRepository(IProcRunner run) => _run = run;

    public Task<IReadOnlyList<ReportDefinitionRow>> ListAsync(CancellationToken ct = default)
        => _run.ListAsync<ReportDefinitionRow>("sel.usp_Report_List", ct: ct);

    /// <summary>
    /// One door for every report, so the controller holds no switch.
    ///
    /// Each report comes back as its columns, its rows and its note. The rows are loose
    /// dictionaries because every report has a different shape and a record per report
    /// would be six more places for a column rename to break.
    /// </summary>
    public async Task<ReportResult> RunAsync(
        string reportKey, int? cycleId = null, CancellationToken ct = default)
    {
        var (value, problem) = await _run.MultiWithProblemAsync("sel.usp_Report_Run", async g =>
        {
            var columns = (await g.ReadAsync<ReportColumnRow>()).AsList();
            var rows = (await g.ReadAsync()).Cast<IDictionary<string, object?>>().ToList();
            var note = await g.ReadFirstOrDefaultAsync<ReportNoteRow>();
            return (columns, rows, note);
        }, new { ReportKey = reportKey, CycleId = cycleId }, ct);

        return new ReportResult(value.columns, value.rows, value.note?.Note, problem);
    }
}

public sealed record ReportDefinitionRow(
    int ReportDefinitionId, string ReportKey, string Name, string? Description,
    string ProcedureName, bool NeedsCycle, int SortOrder);

/// <summary>
/// A report column. DataType "share" means the value is a count and a total, and the
/// formatter turns it into words — never a raw percentage.
/// </summary>
public sealed record ReportColumnRow(
    string ColumnKey, string Caption, string DataType, string Align, int SortOrder);

public sealed record ReportNoteRow(string Note);

public sealed record ReportResult(
    IReadOnlyList<ReportColumnRow> Columns,
    IReadOnlyList<IDictionary<string, object?>> Rows,
    string? Note,
    string? Problem);
