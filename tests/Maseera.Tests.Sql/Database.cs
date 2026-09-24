using System.Data;
using Microsoft.Data.SqlClient;

namespace Maseera.Tests.Sql;

/// <summary>
/// The connection these tests use.
///
/// They run against a real DB02 because the whole product is in it: an engine test
/// against a mock proves nothing about the statement the engine will actually run. The
/// string comes from MASEERA_TEST_DB02 so a developer can point them at their own
/// instance; when it is not set the whole class is skipped rather than failing, because
/// "no database here" is not the same finding as "the engine is wrong".
/// </summary>
public static class Database
{
    public const string EnvironmentVariable = "MASEERA_TEST_DB02";

    public static string? ConnectionString =>
        Environment.GetEnvironmentVariable(EnvironmentVariable);

    public static bool IsAvailable => !string.IsNullOrWhiteSpace(ConnectionString);

    public static SqlConnection Open()
    {
        if (!IsAvailable)
            throw new InvalidOperationException(
                $"{EnvironmentVariable} is not set. These tests need a DB02 to read.");

        var connection = new SqlConnection(ConnectionString);
        connection.Open();
        return connection;
    }

    /// <summary>The login the read-only role is seeded under.</summary>
    public const string Auditor = "maseera.auditor";

    /// <summary>Granted the whole company.</summary>
    public const string Hrbp = "maseera.hrbp";

    /// <summary>Granted one division, so the same cycle reads differently.</summary>
    public const string Svp = "maseera.svp";

    public const string Administrator = "maseera.admin";
}

/// <summary>
/// Marks a fact that needs the database. Without MASEERA_TEST_DB02 it is skipped with a
/// sentence, so a run on a machine with no SQL Server is honest about what it did not do.
/// </summary>
public sealed class DatabaseFactAttribute : FactAttribute
{
    public DatabaseFactAttribute()
    {
        if (!Database.IsAvailable)
            Skip = $"Set {Database.EnvironmentVariable} to run the database tests.";
    }
}

public sealed class DatabaseTheoryAttribute : TheoryAttribute
{
    public DatabaseTheoryAttribute()
    {
        if (!Database.IsAvailable)
            Skip = $"Set {Database.EnvironmentVariable} to run the database tests.";
    }
}
