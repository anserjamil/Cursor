namespace Maseera.Core.Dtos;

/// <summary>A closed set the application must not hardcode.</summary>
public sealed record DomainRow(
    int DomainId, string DomainCode, string Name, string? Description,
    bool IsSystem, int SortOrder, int ValueCount, int ActiveCount);

public sealed record DomainValueRow(
    int DomainValueId, int DomainId, string? DomainCode, string ValueCode, string Name,
    string? Description, string? SemanticRole, int SortOrder, bool IsActive, bool IsSystem,
    bool DomainIsSystem);

/// <summary>A comparison, with the SQL shape and the arity that belong to it.</summary>
public sealed record OperatorRow(
    int OperatorId, string OperatorCode, string Name, string SqlTemplate,
    string AppliesTo, byte Arity, int SortOrder)
{
    /// <summary>Whether this operator may be offered for a field of the given data type.</summary>
    public bool AppliesToType(string dataType)
        => ("," + AppliesTo + ",").Contains("," + dataType + ",", StringComparison.OrdinalIgnoreCase);
}

public sealed record SettingRow(int SettingId, string SettingKey, string? TextValue,
    decimal? NumValue, string? Description);

public sealed record MessageRow(int MessageId, string MessageKey, string MessageText, string? Description);

public sealed record MenuGroupRow(int MenuGroupId, string GroupCode, string Caption,
    string? Subtitle, int SortOrder);

/// <summary>A registered screen. ScreenCode is the shipped route path.</summary>
public sealed record ScreenRow(
    int ScreenId, string ScreenCode, string Name, string AreaName, string ControllerName,
    string ActionName, int? MenuGroupId, string? GroupCaption, bool IsInMenu, int SortOrder,
    bool IsActive, short? GrantValue)
{
    public bool CanRead => GrantValue is >= 1;
    public bool CanWrite => GrantValue is >= 2;
}

public sealed record HealthRow(string Group, string CheckName, long Actual, bool? IsOk, string? Note);

/// <summary>
/// The hash of the configuration's CONTENT, and how much content went into it. A cache
/// keyed on a row count would miss a rename that changed nothing but the words, which is
/// exactly the change a reader notices. ContentLength is a long because LEN() over
/// nvarchar(max) is a bigint.
/// </summary>
public sealed record ConfigStamp(string Stamp, long ContentLength);

/// <summary>Every table the application reads, and what breaks when it is absent.</summary>
public sealed record TableMappingRow(
    int TableMappingId, string SourceKey, string Caption, string SchemaName, string TableName,
    string? KeyColumn, string? ItemColumn, string? ReadBy, string? BreaksWhenUnmapped,
    bool IsMapped, bool IsRequired, long? RowCountCached, DateTime? LastSyncUtc,
    DateTime? LastCheckedUtc, int SortOrder, int ColumnCount,
    bool? KeyColumnPresent, bool? ItemColumnPresent);

public sealed record TableMappingColumnRow(
    int TableMappingColumnId, int TableMappingId, string SourceKey, string ColumnName,
    string SqlType, string DataType, bool IsNullable, int OrdinalPos);

/// <summary>
/// A roster column. Enabled means usable in criteria; sensitive means readable on a
/// profile and refused as a filter. The two are different questions.
/// </summary>
public sealed record RosterFieldRow(
    int RosterFieldId, string FieldName, string Caption, string DataType, string? SqlType,
    string SourceKind, bool IsEnabled, bool IsSensitive, string? GroupName, int SortOrder,
    int UsageCount, DateTime DiscoveredOnUtc, DateTime? LastSeenOnUtc, bool IsPresent);

public sealed record RosterFieldSummary(int TotalFields, int EnabledCount, int SensitiveCount, int MissingCount);

public sealed record LoadExceptionRow(
    long LoadExceptionId, string SourceKey, string? SourceTable, string? KeyText,
    string ReasonCode, string ReasonText, Guid? BatchId, bool IsResolved,
    DateTime? ResolvedOnUtc, string? ResolvedByLogin, DateTime CreatedOnUtc);

public sealed record ColumnCatalogRow(
    int ColumnCatalogId, string ColumnName, string Caption, string GroupName, string DataType,
    bool IsSensitive, bool IsDefault, int SortOrder, bool IsPresent);

public sealed record SavedViewRow(
    int SavedViewId, string? LoginName, string ScreenCode, string ViewName, string ColumnList,
    string? SortBy, string? SortDir, bool IsPreset, DateTime SavedOnUtc);
