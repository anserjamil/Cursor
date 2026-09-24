using Maseera.Data.Repositories;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace Maseera.Data;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// The data layer: a connection factory, the runner everything goes through, the
    /// procedure contract, the configuration cache, and one repository per aggregate.
    ///
    /// Maseera.Web never opens a SqlConnection; it asks a repository, which asks the
    /// runner, which calls a procedure.
    /// </summary>
    public static IServiceCollection AddMaseeraData(this IServiceCollection services, IConfiguration configuration)
    {
        services.Configure<MaseeraOptions>(configuration.GetSection(MaseeraOptions.SectionName));

        // Every date in this application is a calendar day, and the records say so.
        // Dapper needs telling how to read one back from a SQL date; see the handlers.
        RegisterTypeHandlers();

        services.AddSingleton<ISqlConnectionFactory, SqlConnectionFactory>();

        // The contract is read once and shared: the parameter list of a procedure does
        // not change between requests.
        services.AddSingleton<IProcContract, ProcContract>();

        // Keyed on a content stamp, never on a row count.
        services.AddSingleton<IConfigCache, ConfigCache>();

        // Scoped, because it carries the request's user context into every call.
        services.AddScoped<IProcRunner, ProcRunner>();

        services.AddScoped<ConfigRepository>();
        services.AddScoped<SecurityRepository>();
        services.AddScoped<RosterRepository>();
        services.AddScoped<CycleRepository>();
        services.AddScoped<PoolRepository>();
        services.AddScoped<FrameworkRepository>();
        services.AddScoped<StageRepository>();
        services.AddScoped<IdpRepository>();
        services.AddScoped<ReportRepository>();
        services.AddScoped<AuditRepository>();

        return services;
    }

    private static bool _handlersRegistered;
    private static readonly object HandlerLock = new();

    /// <summary>
    /// Dapper's handler table is process-wide, so this is done once and guarded. Adding
    /// the same handler twice is harmless, but a test host that builds several service
    /// providers would otherwise do it on every one.
    /// </summary>
    private static void RegisterTypeHandlers()
    {
        if (_handlersRegistered) return;
        lock (HandlerLock)
        {
            if (_handlersRegistered) return;
            Dapper.SqlMapper.AddTypeHandler(new DateOnlyTypeHandler());
            Dapper.SqlMapper.AddTypeHandler(new TimeOnlyTypeHandler());
            _handlersRegistered = true;
        }
    }
}
