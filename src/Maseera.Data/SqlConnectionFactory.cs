using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

namespace Maseera.Data;

public interface ISqlConnectionFactory
{
    SqlConnection Create();
}

/// <summary>
/// There is one database and its name is DB02.
///
/// The connection string is taken verbatim from configuration and never built in code,
/// never logged, and never joined by a second one. The only thing this does is read it
/// and refuse loudly if it is missing, because a startup that fails here is far cheaper
/// than a screen that fails later.
/// </summary>
public sealed class SqlConnectionFactory : ISqlConnectionFactory
{
    public const string ConnectionName = "Db02";

    private readonly string _connectionString;

    public SqlConnectionFactory(IConfiguration configuration)
    {
        var cs = configuration.GetConnectionString(ConnectionName);

        if (string.IsNullOrWhiteSpace(cs))
        {
            throw new InvalidOperationException(
                $"No connection string called '{ConnectionName}' is configured. " +
                "Maseera reads one database, DB02, and cannot start without it.");
        }

        _connectionString = cs;
    }

    public SqlConnection Create() => new(_connectionString);
}
