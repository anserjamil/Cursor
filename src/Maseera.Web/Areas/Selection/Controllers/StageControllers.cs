using Maseera.Data.Repositories;
using Maseera.Web.Security;
using Microsoft.AspNetCore.Mvc;

namespace Maseera.Web.Areas.Selection.Controllers;

/*
   The three talent-review stages, and their succession counterparts.

   They are separate controllers because the shipped route paths are the access engine's
   screen codes and the legacy policy rows are keyed on them — so the paths are data, not
   a naming convention we are free to collapse. What they do is identical, which is why
   it lives once in StageControllerBase.
*/

[Area("Selection")]
public sealed class IdentifyController : StageControllerBase
{
    public const string Screen = "/Selection/Identify/";

    public IdentifyController(StageRepository stages, RosterRepository roster) : base(stages, roster) { }

    protected override string StageViewName => "Index";

    [HttpGet]
    [ScreenAccess(Screen)]
    public Task<IActionResult> Index(
        int cycleStageId, string? pill = null, string? q = null, string? columns = null,
        string? filters = null, string? sort = null, string? dir = null,
        int page = 1, int? size = null, CancellationToken ct = default)
        => RenderStageAsync(cycleStageId, pill, q, columns, filters, sort, dir, page, size, ct);
}

[Area("Selection")]
public sealed class ReviewController : StageControllerBase
{
    public const string Screen = "/Selection/Review/";

    public ReviewController(StageRepository stages, RosterRepository roster) : base(stages, roster) { }

    protected override string StageViewName => "Index";

    [HttpGet]
    [ScreenAccess(Screen)]
    public Task<IActionResult> Index(
        int cycleStageId, string? pill = null, string? q = null, string? columns = null,
        string? filters = null, string? sort = null, string? dir = null,
        int page = 1, int? size = null, CancellationToken ct = default)
        => RenderStageAsync(cycleStageId, pill, q, columns, filters, sort, dir, page, size, ct);
}

[Area("Selection")]
public sealed class CalibrateController : StageControllerBase
{
    public const string Screen = "/Selection/Calibrate/";

    public CalibrateController(StageRepository stages, RosterRepository roster) : base(stages, roster) { }

    protected override string StageViewName => "Index";

    [HttpGet]
    [ScreenAccess(Screen)]
    public Task<IActionResult> Index(
        int cycleStageId, string? pill = null, string? q = null, string? columns = null,
        string? filters = null, string? sort = null, string? dir = null,
        int page = 1, int? size = null, CancellationToken ct = default)
        => RenderStageAsync(cycleStageId, pill, q, columns, filters, sort, dir, page, size, ct);
}
