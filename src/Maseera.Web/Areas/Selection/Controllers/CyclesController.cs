using Maseera.Core.Dtos;
using Maseera.Data;
using Maseera.Data.Repositories;
using Maseera.Web.Controllers;
using Maseera.Web.Models;
using Maseera.Web.Security;
using Microsoft.AspNetCore.Mvc;

namespace Maseera.Web.Areas.Selection.Controllers;

/// <summary>
/// The operational home: every cycle, its stage strip, its figures, and ONE primary
/// action into the stage it is waiting on.
/// </summary>
[Area("Selection")]
public sealed class CyclesController : MaseeraController
{
    public const string Screen = "/Selection/Cycles/";

    private readonly CycleRepository _cycles;

    public CyclesController(CycleRepository cycles) => _cycles = cycles;

    [HttpGet]
    [ScreenAccess(Screen)]
    public async Task<IActionResult> Index(string? status, string? q, bool mine = false, CancellationToken ct = default)
    {
        var (cycles, tracks) = await _cycles.ListAsync(status, q, mine, ct);
        var (stages, waiting) = await _cycles.SpineAsync(null, ct);

        var vm = new CyclesIndexViewModel
        {
            Cycles = cycles,
            TracksByCycle = tracks.GroupBy(t => t.CycleId)
                .ToDictionary(g => g.Key, g => (IReadOnlyList<CycleTrackRow>)g.OrderBy(t => t.SortOrder).ToList()),
            StagesByCycle = stages.Where(s => s.CycleStageId is not null).GroupBy(s => s.CycleId)
                .ToDictionary(g => g.Key, g => (IReadOnlyList<CycleSpineRow>)g
                    .OrderBy(s => s.ProcessSort).ThenBy(s => s.StageSort).ToList()),
            WaitingByCycle = waiting.ToDictionary(w => w.CycleId),
            StatusFilter = status,
            Search = q,
            MineOnly = mine,
            CanWrite = CanWrite,
            EmptyMessage = await Config.MessageAsync(MessageKeys.NoCycles, ct)
        };

        return View(vm);
    }

    /// <summary>
    /// The refusal page. It is reached by re-execution from the status-code middleware,
    /// so the sentence the handler left behind is still on the request.
    /// </summary>
    /* No ScreenAccess here on purpose: the refusal page has to be reachable by somebody
       who has just been refused, and it shows no data of its own. */
    [HttpGet]
    public IActionResult Refused(int? code)
    {
        var sentence = HttpContext.Items.TryGetValue(ScreenAccessHandler.RefusalItemKey, out var v)
            ? v as string
            : null;

        var vm = new RefusalViewModel
        {
            StatusCode = code ?? StatusCodes.Status403Forbidden,
            ScreenName = HttpContext.Items.TryGetValue("MaseeraScreenName", out var n) ? n as string : null,
            Sentence = sentence ?? (code switch
            {
                404 => "There is nothing at that address.",
                403 => "Nothing grants you this screen.",
                _ => "This could not be shown."
            }),
            IsRegistered = User_.IsRegistered,
            LoginName = User_.LoginName
        };

        Response.StatusCode = vm.StatusCode;
        return View("Refused", vm);
    }

    [HttpGet]
    public IActionResult Error() => View("Refused", new RefusalViewModel
    {
        StatusCode = 500,
        Sentence = "Something went wrong and the action was not completed. It has been written to the log.",
        IsRegistered = User_.IsRegistered,
        LoginName = User_.LoginName
    });
}
