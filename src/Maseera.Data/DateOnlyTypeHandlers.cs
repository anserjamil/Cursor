using System.Data;
using Dapper;

namespace Maseera.Data;

/// <summary>
/// Dapper reads a SQL <c>date</c> back as a <see cref="DateTime"/>, because that is what
/// Microsoft.Data.SqlClient hands it. Every date in this application is a calendar day —
/// an as-of date, a stage window, a completion, an expiry — and none of them has a time
/// of day, so the records are written with <see cref="DateOnly"/> and these two handlers
/// do the translation in one place.
///
/// Without them Dapper cannot match a constructor that takes a DateOnly and fails at
/// materialization with a message about a parameterless constructor, which is a long way
/// from the actual cause. Registering them once, at start-up, keeps every DTO honest
/// about what it holds rather than each one carrying a DateTime it then has to truncate.
/// </summary>
public sealed class DateOnlyTypeHandler : SqlMapper.TypeHandler<DateOnly>
{
    public override DateOnly Parse(object value) => value switch
    {
        DateOnly d => d,
        DateTime dt => DateOnly.FromDateTime(dt),
        string s => DateOnly.Parse(s),
        _ => DateOnly.FromDateTime(Convert.ToDateTime(value)),
    };

    public override void SetValue(IDbDataParameter parameter, DateOnly value)
    {
        parameter.DbType = DbType.Date;
        parameter.Value = value.ToDateTime(TimeOnly.MinValue);
    }
}

/// <summary>The same, for a SQL <c>time</c>. Sessions carry one; nothing else does.</summary>
public sealed class TimeOnlyTypeHandler : SqlMapper.TypeHandler<TimeOnly>
{
    public override TimeOnly Parse(object value) => value switch
    {
        TimeOnly t => t,
        TimeSpan ts => TimeOnly.FromTimeSpan(ts),
        DateTime dt => TimeOnly.FromDateTime(dt),
        string s => TimeOnly.Parse(s),
        _ => TimeOnly.FromTimeSpan((TimeSpan)value),
    };

    public override void SetValue(IDbDataParameter parameter, TimeOnly value)
    {
        parameter.DbType = DbType.Time;
        parameter.Value = value.ToTimeSpan();
    }
}
