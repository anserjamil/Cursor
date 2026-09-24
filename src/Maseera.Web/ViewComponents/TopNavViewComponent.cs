using Maseera.Core.Dtos;
using Maseera.Data.Repositories;
using Microsoft.AspNetCore.Mvc;

namespace Maseera.Web.ViewComponents;

/// <summary>
/// The navigation, from cfg.MenuGroup and cfg.Screen.
///
/// There is no markup for it in _Layout.cshtml: the groups, their captions and their
/// one-line subtitles are rows, and a screen the viewer cannot read never appears at all
/// because the procedure filters on sec.fn_ScreenAccess.
/// </summary>
public sealed class TopNavViewComponent : ViewComponent
{
    private readonly ConfigRepository _config;

    public TopNavViewComponent(ConfigRepository config) => _config = config;

    public async Task<IViewComponentResult> InvokeAsync()
    {
        var (groups, screens) = await _config.MenuAsync();

        return View(new TopNavModel
        {
            Groups = groups,
            ScreensByGroup = screens
                .Where(s => s.MenuGroupId is not null)
                .GroupBy(s => s.MenuGroupId!.Value)
                .ToDictionary(g => g.Key, g => (IReadOnlyList<ScreenRow>)g.ToList()),
            CurrentPath = HttpContext.Request.Path.Value ?? "/"
        });
    }
}

/// <summary>
/// The jump-to-anything palette, over the same registry as the navigation — including
/// the stage screens, which are not in the menu because they are faces of a cycle.
/// It only navigates; it never acts.
/// </summary>
public sealed class PaletteViewComponent : ViewComponent
{
    private readonly ConfigRepository _config;

    public PaletteViewComponent(ConfigRepository config) => _config = config;

    public async Task<IViewComponentResult> InvokeAsync()
        => View(await _config.ScreensAsync());
}

public sealed record TopNavModel
{
    public IReadOnlyList<MenuGroupRow> Groups { get; init; } = [];
    public IReadOnlyDictionary<int, IReadOnlyList<ScreenRow>> ScreensByGroup { get; init; }
        = new Dictionary<int, IReadOnlyList<ScreenRow>>();
    public string CurrentPath { get; init; } = "/";

    /// <summary>
    /// Which group the viewer is in. Matched on the area and controller rather than on
    /// the whole path, so a drilldown stays under its own heading.
    /// </summary>
    public bool IsCurrentGroup(int menuGroupId)
        => ScreensByGroup.TryGetValue(menuGroupId, out var screens)
           && screens.Any(s => CurrentPath.StartsWith($"/{s.AreaName}/{s.ControllerName}",
               StringComparison.OrdinalIgnoreCase));

    public bool IsCurrentScreen(ScreenRow screen)
        => CurrentPath.StartsWith($"/{screen.AreaName}/{screen.ControllerName}",
            StringComparison.OrdinalIgnoreCase);
}
