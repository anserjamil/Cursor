using System.Security.Claims;
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

        // The as-of date is settled in two steps, because the two halves depend on each
        // other: the role decides whether ?asOf= is allowed, and the role is read as of a
        // date. So the standing date is resolved first, the context is read against it,
        // and only an administrator who actually asked for a different date pays for a
        // second read.
        var asOf = ResolveStandingAsOf(settings, await config.TextAsync(SettingKeys.AsOfOverride, http.RequestAborted));

        var row = await security.ContextAsync(login, asOf, http.RequestAborted);

        if (RequestedAsOf(http) is { } requested && requested != asOf
            && string.Equals(row?.RoleCode, AdministratorRole, StringComparison.OrdinalIgnoreCase))
        {
            asOf = requested;
            row = await security.ContextAsync(login, asOf, http.RequestAborted);
        }

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

        // Give the request a principal that agrees with the context just resolved.
        //
        // It grants nothing: every screen is still decided by sec.usp_ScreenAccess_Check
        // against the six rules, and this carries only the login the middleware already
        // resolved and the role the DATABASE reported for it. What it fixes is two things
        // the pipeline gets wrong without it.
        //
        // First, a denied request. ASP.NET Core turns a failed authorization into a 403
        // when there is an identity and a 401 challenge when there is not. Without a
        // principal, somebody who is perfectly well signed in but not granted a screen
        // gets a blank 401 and a re-authentication prompt instead of the sentence that
        // explains the refusal.
        //
        // Second, the as-of override. With Negotiate, User.IsInRole reflects Windows
        // groups, which have nothing to say about a Maseera role — so the administrator
        // check below could never pass on a real deployment either.
        ApplyPrincipal(http, context);

        // Serilog enrichment: every line of this request names who took the action.
        using (Serilog.Context.LogContext.PushProperty("LoginName", context.LoginName))
        using (Serilog.Context.LogContext.PushProperty("AsOf", context.AsOf))
        {
            await _next(http);
        }
    }

    /// <summary>
    /// The identity the rest of the pipeline sees: the resolved login, plus the role the
    /// database reports. Windows stays the authenticator — this only restates what it
    /// authenticated in terms the authorization pipeline can read.
    /// </summary>
    private static void ApplyPrincipal(HttpContext http, UserContext context)
    {
        if (string.IsNullOrWhiteSpace(context.LoginName)) return;

        var claims = new List<Claim>
        {
            new(ClaimTypes.Name, context.LoginName),
            new(ClaimTypes.NameIdentifier, context.LoginName),
        };

        if (context.RoleCode is { Length: > 0 } role)
            claims.Add(new Claim(ClaimTypes.Role, role));

        // "maseera" as the authentication type, so nothing downstream mistakes this for
        // a second authentication scheme it could challenge against.
        var identity = new ClaimsIdentity(claims, authenticationType: "maseera",
            nameType: ClaimTypes.Name, roleType: ClaimTypes.Role);

        // Added alongside whatever Windows established rather than replacing it, so the
        // real Windows identity is still there to be read and logged.
        if (http.User.Identity?.IsAuthenticated == true)
            http.User.AddIdentity(identity);
        else
            http.User = new ClaimsPrincipal(identity);
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

    /// <summary>The role code the as-of override is reserved to.</summary>
    private const string AdministratorRole = "ADMIN";

    /// <summary>
    /// Today, unless configuration says otherwise. The database carries the same
    /// override, so the application and the database always agree about which stage is
    /// open — and if they ever did not, every screen would be arguing with its own data.
    /// </summary>
    private static DateOnly ResolveStandingAsOf(MaseeraOptions settings, string? storedOverride)
    {
        if (settings.AsOfOverride is { } configured) return configured;
        if (DateOnly.TryParse(storedOverride, out var fromDb)) return fromDb;
        return DateOnly.FromDateTime(DateTime.UtcNow);
    }

    /// <summary>
    /// The date this request asked to be read as of, if it asked for one. Whether it is
    /// allowed is decided by the caller against the role the DATABASE reports — never
    /// against anything the request itself carries.
    /// </summary>
    private static DateOnly? RequestedAsOf(HttpContext http)
        => http.Request.Query.TryGetValue("asOf", out var q)
           && DateOnly.TryParse(q.ToString(), out var asked)
            ? asked
            : null;

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
