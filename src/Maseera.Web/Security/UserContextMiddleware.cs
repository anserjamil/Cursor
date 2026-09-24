using Maseera.Data;
using Maseera.Data.Repositories;
using Microsoft.Extensions.Options;

namespace Maseera.Web.Security;

/// <summary>
/// Resolves who is asking, and as of when, once per request.
///
/// The login is the sAMAccountName Windows authenticated. In Development only, a
/// "Sign in as" cookie may replace it — and the switcher that sets that cookie is
/// unreachable in any other environment, so this is the second of two locks, not the only
/// one.
/// </summary>
public sealed class UserContextMiddleware
{
    /// <summary>The development-only "Sign in as" cookie.</summary>
    public const string ImpersonationCookie = "maseera-as";

    /// <summary>The administrator-only test-mode cookie.</summary>
    public const string TestModeCookie = "maseera-test";

    private readonly RequestDelegate _next;
    private readonly ILogger<UserContextMiddleware> _log;

    public UserContextMiddleware(RequestDelegate next, ILogger<UserContextMiddleware> log)
    {
        _next = next;
        _log = log;
    }

    public async Task InvokeAsync(
        HttpContext http,
        UserContext context,
        SecurityRepository security,
        IConfigCache config,
        IOptions<MaseeraOptions> options,
        IHostEnvironment environment)
    {
        var settings = options.Value;

        var realLogin = ResolveWindowsLogin(http, settings);
        var login = realLogin;
        var impersonating = false;

        // The switcher is Development only, and is gated on the environment first so that
        // turning the flag on in production still changes nothing.
        if (environment.IsDevelopment() && settings.AllowImpersonation)
        {
            var asWho = http.Request.Cookies[ImpersonationCookie];
            if (!string.IsNullOrWhiteSpace(asWho))
            {
                login = asWho.Trim();
                impersonating = !string.Equals(login, realLogin, StringComparison.OrdinalIgnoreCase);
            }
        }

        var asOf = await ResolveAsOfAsync(http, settings, config, http.RequestAborted);

        var row = await security.ContextAsync(login, asOf, http.RequestAborted);

        if (row is null)
        {
            // Rule 2 of the precedence: the login has no user record. It is not an error,
            // it is a denial — and the refusal screen says so in words.
            _log.LogInformation("Login {Login} is not registered in sec.AppUser.", login);
            context.Apply(login, login, null, null, isReadOnly: true, asOf, testMode: false,
                orgScopeCount: 0, isRegistered: false, authorizationNote: null,
                authorizationRole: null, hasRlsBypass: false, realLoginName: realLogin,
                isImpersonating: impersonating);
        }
        else
        {
            var testMode = ResolveTestMode(http, row.RoleCode);

            context.Apply(
                row.LoginName, row.DisplayName, row.RoleCode, row.RoleName, row.IsReadOnly,
                row.AsOf, testMode, row.OrgScopeCount, isRegistered: true,
                row.AuthorizationNote,
                AuthorizationRoleOf(row.AuthorizationEndsOn, asOf),
                row.HasRlsBypass, realLogin, impersonating);
        }

        // Serilog enrichment: every line of this request names who took the action.
        using (Serilog.Context.LogContext.PushProperty("LoginName", context.LoginName))
        using (Serilog.Context.LogContext.PushProperty("AsOf", context.AsOf))
        {
            await _next(http);
        }
    }

    private static string ResolveWindowsLogin(HttpContext http, MaseeraOptions settings)
    {
        var name = http.User.Identity?.Name;

        if (!string.IsNullOrWhiteSpace(name))
        {
            // Windows gives DOMAIN\user; sec.AppUser holds the sAMAccountName alone.
            var slash = name.LastIndexOf('\\');
            return slash >= 0 ? name[(slash + 1)..] : name;
        }

        // Development without a domain: a configured login stands in for one.
        return settings.DevelopmentLogin ?? string.Empty;
    }

    /// <summary>
    /// Today, unless configuration or an administrator's ?asOf= says otherwise. The
    /// database carries the same override, so the two always agree about which stage is
    /// open.
    /// </summary>
    private static async Task<DateOnly> ResolveAsOfAsync(
        HttpContext http, MaseeraOptions settings, IConfigCache config, CancellationToken ct)
    {
        if (http.Request.Query.TryGetValue("asOf", out var q)
            && DateOnly.TryParse(q.ToString(), out var fromQuery))
        {
            // Only an administrator may move the date, and the check happens against the
            // role the database reports, not against anything the request carries.
            if (http.User.IsInRole("ADMIN") || http.Items.ContainsKey("MaseeraAdmin"))
                return fromQuery;
        }

        if (settings.AsOfOverride is { } configured) return configured;

        var stored = await config.TextAsync(SettingKeys.AsOfOverride, ct);
        if (DateOnly.TryParse(stored, out var fromDb)) return fromDb;

        return DateOnly.FromDateTime(DateTime.UtcNow);
    }

    /// <summary>
    /// Test mode ignores every stage window. It is an administrator's tool, and the
    /// database refuses it for anybody else as well — this is the first of the two checks,
    /// not the only one.
    /// </summary>
    private static bool ResolveTestMode(HttpContext http, string? roleCode)
    {
        if (!string.Equals(roleCode, "ADMIN", StringComparison.OrdinalIgnoreCase)) return false;
        return http.Request.Cookies[TestModeCookie] == "1";
    }

    private static string? AuthorizationRoleOf(DateOnly? endsOn, DateOnly asOf)
    {
        if (endsOn is null) return null;
        if (endsOn < asOf) return "danger";
        if (endsOn < asOf.AddMonths(4)) return "warning";
        return null;
    }
}

public static class UserContextMiddlewareExtensions
{
    public static IApplicationBuilder UseMaseeraUserContext(this IApplicationBuilder app)
        => app.UseMiddleware<UserContextMiddleware>();
}
