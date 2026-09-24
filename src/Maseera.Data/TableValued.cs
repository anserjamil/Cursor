using System.Data;
using Dapper;

namespace Maseera.Data;

/// <summary>
/// Bulk writes pass a table-valued parameter, never a loop of single calls and never a
/// comma-joined string. Two shapes cover everything the application needs.
/// </summary>
public static class TableValued
{
    public const string IdListType = "dbo.IdList";
    public const string KeyValueListType = "dbo.KeyValueList";

    /// <summary>A list of identifiers — personnel numbers, mostly.</summary>
    public static SqlMapper.ICustomQueryParameter Ids(IEnumerable<string>? values)
    {
        var table = new DataTable();
        table.Columns.Add("Id", typeof(string));

        if (values is not null)
        {
            // A duplicate in the selection is a double-click, not a second decision.
            foreach (var v in values.Where(v => !string.IsNullOrWhiteSpace(v))
                                    .Select(v => v.Trim())
                                    .Distinct(StringComparer.OrdinalIgnoreCase))
            {
                table.Rows.Add(v);
            }
        }

        return table.AsTableValuedParameter(IdListType);
    }

    /// <summary>A list of key/value pairs, in the order they were given.</summary>
    public static SqlMapper.ICustomQueryParameter KeyValues(IEnumerable<KeyValuePair<string, string?>>? values)
    {
        var table = new DataTable();
        table.Columns.Add("Key", typeof(string));
        table.Columns.Add("Value", typeof(string));

        if (values is not null)
        {
            foreach (var kv in values.Where(kv => !string.IsNullOrWhiteSpace(kv.Key)))
                table.Rows.Add(kv.Key.Trim(), kv.Value);
        }

        return table.AsTableValuedParameter(KeyValueListType);
    }
}
