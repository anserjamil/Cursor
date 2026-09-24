using System.Text.Json;
using Maseera.Core;
using Maseera.Data;
using Microsoft.AspNetCore.Mvc;

namespace Maseera.Web.Controllers;

/// <summary>
/// What every controller in Maseera shares: a toast for every write, a refusal rendered
/// as a sentence, and post-redirect-get so a refresh never repeats a decision.
///
/// Controllers are thin. They read arguments, call a procedure, map the result to a view
/// model and return a view. No controller contains an `if` about the domain.
/// </summary>
public abstract class MaseeraController : Controller
{
    protected const string ToastKey = "MaseeraToasts";

    protected IUserContext User_ => HttpContext.RequestServices.GetRequiredService<IUserContext>();
    protected IConfigCache Config => HttpContext.RequestServices.GetRequiredService<IConfigCache>();

    /// <summary>Whether this request's screen was granted write, decided by the handler.</summary>
    protected bool CanWrite => HttpContext.Items.TryGetValue("MaseeraCanWrite", out var v) && v is true;

    protected string? ScreenCode
        => HttpContext.Items.TryGetValue("MaseeraScreenCode", out var v) ? v as string : null;

    /// <summary>Whether the browser asked for a partial rather than a whole page.</summary>
    protected bool IsAjax
        => string.Equals(Request.Headers["X-Requested-With"], "fetch", StringComparison.OrdinalIgnoreCase)
           || string.Equals(Request.Headers["X-Requested-With"], "XMLHttpRequest", StringComparison.OrdinalIgnoreCase);

    /* ---- toasts ----------------------------------------------------------------- */

    protected void ToastOk(string message) => AddToast("ok", message);
    protected void ToastWarn(string message) => AddToast("warn", message);

    /// <summary>
    /// Every write produces a toast, including every refusal, with its reason. The
    /// refusal is the procedure's own sentence — nothing here composes one.
    /// </summary>
    protected void Toast(ProcResult result, string okMessage)
    {
        if (result.Ok) ToastOk(okMessage);
        else ToastWarn(result.Problem ?? "Nothing was changed.");
    }

    private void AddToast(string kind, string message)
    {
        var toasts = ReadToasts();
        toasts.Add(new ToastMessage(kind, message));
        TempData[ToastKey] = JsonSerializer.Serialize(toasts);
    }

    private List<ToastMessage> ReadToasts()
    {
        if (TempData.TryGetValue(ToastKey, out var raw) && raw is string json && json.Length > 0)
        {
            TempData.Keep(ToastKey);
            return JsonSerializer.Deserialize<List<ToastMessage>>(json) ?? [];
        }
        return [];
    }

    /* ---- write endpoints -------------------------------------------------------- */

    /// <summary>
    /// The shape every write takes: run it, toast the outcome, and either answer the
    /// AJAX caller with the sentence or redirect so a refresh cannot repeat it.
    /// </summary>
    protected async Task<IActionResult> WriteAsync(
        Func<Task<ProcResult>> write, string okMessage, Func<IActionResult> redirect)
    {
        var result = await write();
        Toast(result, okMessage);

        if (IsAjax)
        {
            return Json(new
            {
                ok = result.Ok,
                problem = result.Problem,
                message = result.Ok ? okMessage : result.Problem,
                affected = result.Affected
            });
        }

        return redirect();
    }

    /// <summary>
    /// A read that could not be asked at all. It is rendered as a sentence on a panel,
    /// never as an empty table and never as a zero.
    /// </summary>
    protected IActionResult Refusal(string sentence, string? title = null)
    {
        ViewData["RefusalTitle"] = title ?? "This could not be shown";
        ViewData["RefusalSentence"] = sentence;
        Response.StatusCode = StatusCodes.Status200OK;
        return View("~/Views/Shared/_Refusal.cshtml");
    }

    public sealed record ToastMessage(string Kind, string Message);
}
