using Maseera.Core;
using Maseera.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc.Filters;

namespace Maseera.Web.Security;

/// <summary>
/// Every action carries this. There is exactly one policy, and no role literal anywhere:
/// the decision is the database's, taken by sec.fn_ScreenAccess through
/// sec.usp_ScreenAccess_Check, and applied in the shipped six-rule precedence.
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = false)]
public sealed class ScreenAccessAttribute : AuthorizeAttribute, IScreenAccessMetadata
{
    public const string PolicyName = "ScreenAccess";

    public ScreenAccessAttribute(string screenCode)
    {
        ScreenCode = screenCode;
        Policy = PolicyName;
    }

    /// <summary>The shipped route path this screen is keyed on.</summary>
    public string ScreenCode { get; }

    /// <summary>
    /// Whether the action writes. Read and write are separate grants, so an action that
    /// only shows a screen asks for read and an action that changes something asks for
    /// write — and a viewer with read alone gets the screen in its read-only state rather
    /// than a refusal.
    /// </summary>
    public bool Write { get; set; }
}

public interface IScreenAccessMetadata
{
    string ScreenCode { get; }
    bool Write { get; }
}

public sealed class ScreenAccessRequirement : IAuthorizationRequirement;

/// <summary>
/// The handler. It reads the screen code from the endpoint's own metadata, asks the
/// database, and records the refusal sentence so the refusal page can render it.
/// </summary>
public sealed class ScreenAccessHandler : AuthorizationHandler<ScreenAccessRequirement>
{
    /// <summary>Where the refusal sentence is left for the status-code pages to find.</summary>
    public const string RefusalItemKey = "MaseeraRefusal";

    private readonly IHttpContextAccessor _http;
    private readonly IServiceScopeFactory _scopes;
    private readonly ILogger<ScreenAccessHandler> _log;

    public ScreenAccessHandler(
        IHttpContextAccessor http, IServiceScopeFactory scopes, ILogger<ScreenAccessHandler> log)
    {
        _http = http;
        _scopes = scopes;
        _log = log;
    }

    protected override async Task HandleRequirementAsync(
        AuthorizationHandlerContext context, ScreenAccessRequirement requirement)
    {
        var http = _http.HttpContext;
        if (http is null) return;

        var metadata = http.GetEndpoint()?.Metadata.GetMetadata<IScreenAccessMetadata>();
        if (metadata is null)
        {
            // An action that asked for this policy without saying which screen is a
            // programming error, and failing closed is the only safe answer.
            _log.LogError("An endpoint requires ScreenAccess but declares no screen code.");
            context.Fail();
            return;
        }

        var user = http.RequestServices.GetRequiredService<IUserContext>();
        var runner = http.RequestServices.GetRequiredService<IProcRunner>();

        var row = await runner.OneAsync<ScreenAccessRow>("sec.usp_ScreenAccess_Check", new
        {
            LoginName = user.LoginName,
            ScreenCode = metadata.ScreenCode,
            AsOf = user.AsOf,
            NeedsWrite = metadata.Write
        }, http.RequestAborted);

        if (row is { IsAllowed: true })
        {
            http.Items["MaseeraCanWrite"] = row.CanWrite;
            http.Items["MaseeraScreenCode"] = metadata.ScreenCode;
            context.Succeed(requirement);
            return;
        }

        // A refusal is a designed state: it comes with a sentence, not a blank 403.
        http.Items[RefusalItemKey] = row?.Refusal ?? "Nothing grants you this screen.";
        http.Items["MaseeraScreenCode"] = metadata.ScreenCode;
        http.Items["MaseeraScreenName"] = row?.ScreenName;

        _log.LogInformation(
            "{Login} refused {Screen} ({Rule}, needs write: {NeedsWrite}).",
            user.LoginName, metadata.ScreenCode, row?.RuleCode ?? "UNKNOWN", metadata.Write);

        context.Fail();
    }

    private sealed record ScreenAccessRow(
        short GrantValue, string RuleCode, bool CanRead, bool CanWrite, bool IsAllowed,
        string? ScreenName, string? Refusal);
}

/// <summary>
/// The last line of defence for a read-only viewer.
///
/// Every write action already asks for a write grant, and every procedure refuses again
/// on its own. This filter turns the attempt into the prototype's sentence before either
/// of those is reached, so an auditor who finds a form gets the toast rather than a 403.
/// </summary>
public sealed class ReadOnlyGuardFilter : IAsyncActionFilter
{
    private readonly IUserContext _user;
    private readonly IConfigCache _config;

    public ReadOnlyGuardFilter(IUserContext user, IConfigCache config)
    {
        _user = user;
        _config = config;
    }

    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        var isWrite = !HttpMethods.IsGet(context.HttpContext.Request.Method)
                      && !HttpMethods.IsHead(context.HttpContext.Request.Method);

        if (isWrite && _user.IsReadOnly)
        {
            var sentence = await _config.MessageAsync(MessageKeys.ReadOnlyRefusal, context.HttpContext.RequestAborted);
            context.HttpContext.Items[ScreenAccessHandler.RefusalItemKey] = sentence;
            context.Result = new Microsoft.AspNetCore.Mvc.ObjectResult(new { problem = sentence })
            {
                StatusCode = StatusCodes.Status403Forbidden
            };
            return;
        }

        await next();
    }
}
