namespace Maseera.Core.Dtos;

/// <summary>The Overview tab's counts, and the days left in the stage window.</summary>
public sealed record IdpBoardSummary(
    int PeopleTotal, int NoPlan, int InProgress, int Complete, int Approved,
    int Overdue, int ReadyToApprove,
    DateOnly? WindowStart, DateOnly? WindowEnd, int? DaysLeft,
    string StageState, bool CanWrite);

public sealed record IdpByLevelRow(string LevelCode, string Name, int SortOrder, int People, int OpenItems);

public sealed record IdpByOrgRow(string OrgCode, string? OrgName, int People, int OpenItems);

public sealed record IdpByEventRow(
    int DevEventId, string EventCode, string EventName, string KindCode,
    int PeopleOpen, int Booked, int Pencilled, int SessionCount);

/// <summary>
/// A person the board is asking about. ProgressPct drives the small bar on the row, and
/// Reason says in words why they are on this list.
/// </summary>
public sealed record IdpAttentionRow(
    string PersonnelNo, string FullName, string OrgCode, string? OrgName, string? JobTitle,
    int OpenCount, int PlannedCount, string PlanState, DateOnly? TargetDate, bool IsOverdue,
    decimal ProgressPct, string Reason);

public sealed record IdpPersonHeader(
    string PersonnelNo, string FullName, string OrgCode, string? OrgName, string? JobTitle,
    string? GradeCode, int OpenCount, int PlannedCount, int MetCount, string PlanState,
    DateOnly? TargetDate, bool TargetIsOverridden, bool IsOverdue, string? LevelCode,
    string? ApprovedByLogin, DateTime? ApprovedOnUtc, bool CanWrite);

/// <summary>
/// One requirement in one person's plan. Met ones are included and greyed, so the plan
/// reads whole. NameIsAmbiguous is why the item code is shown: two requirements with the
/// same name from different sources must not be confused.
/// </summary>
public sealed record IdpPersonItemRow(
    int DevEventId, string ItemCode, string EventCode, string EventName, string KindCode,
    int IsMust, int IsMet, string? Why, string? Sources, int? LevelNo, bool NameIsAmbiguous,
    long? IdpItemId, int? DevSessionId, DateOnly? PencilledDate,
    string? StatusCode, string? StatusName, string? StatusRole,
    string? SessionCode, DateOnly? SessionStart, DateOnly? SessionEnd, string? SessionLocation,
    decimal? CoverageDays, int SessionCount, string? RuleShort);

/// <summary>
/// A session option. SeatsLeft null means the session has no limit; the dropdown's last
/// option is always "pencil in a date", which the view adds rather than the database.
/// </summary>
public sealed record IdpSessionOptionRow(
    int DevSessionId, int DevEventId, string SessionCode, DateOnly? StartDate, DateOnly? EndDate,
    int? Seats, string? Location, int Booked, int? SeatsLeft, bool IsAfterTarget);

public sealed record IdpSessionRow(
    int DevSessionId, int DevEventId, string EventCode, string EventName, string SessionCode,
    DateOnly? StartDate, DateOnly? EndDate, int? Seats, string? Location, bool IsCancelled,
    int Booked, int? SeatsLeft);

public sealed record IdpCoverageRow(
    long IdpCoverageId, int? DevEventId, string? Department, string? PositionCode,
    string? IncumbentPersonnelNo, DateOnly StartDate, DateOnly EndDate, int Days,
    string ActorLogin, DateTime AddedOnUtc, string? IncumbentName, string? EventName);

public sealed record IdpCoverageBoardRow(
    long IdpCoverageId, string PersonnelNo, string FullName, string? Department,
    string? PositionCode, string? IncumbentPersonnelNo, DateOnly StartDate, DateOnly EndDate,
    int Days, string ActorLogin, DateTime AddedOnUtc, string? IncumbentName,
    string? EventName, string? OrgName);

public sealed record IdpSuccessorRow(
    string PersonnelNo, string FullName, string OrgCode, string? OrgName, string? JobTitle,
    decimal DaysPlanned, decimal DaysRecorded);

public sealed record IdpNoteRow(long IdpNoteId, string NoteText, string ActorLogin, DateTime AddedOnUtc);

public sealed record IdpRequirementRow(
    string PersonnelNo, string FullName, string OrgCode, string? OrgName, string? JobTitle,
    int DevEventId, string ItemCode, string EventCode, string EventName, string KindCode,
    int IsMust, int IsMet, string? Why, string? Sources,
    long? IdpItemId, int? DevSessionId, DateOnly? PencilledDate, string StatusCode,
    string? SessionCode, DateOnly? SessionStart, decimal? CoverageDays);

/// <summary>What Suggest actually did, one sentence per action.</summary>
public sealed record IdpSuggestionSentence(string Sentence, int SortOrder);

public sealed record IdpConflictRow(
    string ConflictKind, string PersonnelNo, string FullName,
    string? FirstWhat, DateOnly? FirstFrom, DateOnly? FirstTo,
    string? SecondWhat, DateOnly? SecondFrom, DateOnly? SecondTo,
    string Sentence);

/// <summary>Days owed against successors available, banded.</summary>
public sealed record IdpRiskRow(
    string OrgCode, string? OrgName, int DaysOwed, int PeopleOwing,
    int SuccessorsAvailable, string Band, string BandRole);

public sealed record IdpBooked(
    string PersonnelNo, string FullName, string SessionCode, int DevSessionId, int? SeatsLeft);

public sealed record IdpApproved(
    string PersonnelNo, string FullName, DateTime ApprovedOnUtc, string ApprovedByLogin);

/// <summary>
/// The plan states the board counts. They are strings rather than an enum on purpose:
/// sel.fn_IdpPlanState decides them, and a C# enum mirroring it is the failure mode the
/// whole product is designed to avoid.
/// </summary>
public static class IdpPlanStates
{
    public const string NoPlan = "NO_PLAN";
    public const string InProgress = "IN_PROGRESS";
    public const string Complete = "COMPLETE";
    public const string Approved = "APPROVED";
}
