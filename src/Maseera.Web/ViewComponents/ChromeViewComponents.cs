using Maseera.Core;
using Maseera.Core.Dtos;
using Maseera.Data;
using Maseera.Data.Repositories;
using Microsoft.AspNetCore.Mvc;

namespace Maseera.Web.ViewComponents;

/// <summary>
/// How many organisations this viewer may read. Two people looking at the same cycle
/// legitimately see different people in it, and the pill is where that stops being a
/// surprise.
/// </summary>
public sealed class ScopePillViewComponent : ViewComponent
{
    private readonly IUserContext _user;

    public ScopePillViewComponent(IUserContext user) => _user = user;

    public IViewComponentResult Invoke() => View(_user);
}

/// <summary>
/// The as-of date all date logic reads against. It is in the top bar because a screen
/// silently running as a different day is the kind of thing that costs an afternoon.
/// </summary>
public sealed class AsOfPillViewComponent : ViewComponent
{
    private readonly IUserContext _user;

    public AsOfPillViewComponent(IUserContext user) => _user = user;

    public IViewComponentResult Invoke() => View(_user);
}

/// <summary>
/// Test mode ignores every stage window and stamps each decision TEST. It is an
/// administrator's tool, and the pill says so while it is on.
/// </summary>
public sealed class ModePillViewComponent : ViewComponent
{
    private readonly IUserContext _user;
    private readonly IConfigCache _config;

    public ModePillViewComponent(IUserContext user, IConfigCache config)
    {
        _user = user;
        _config = config;
    }

    public async Task<IViewComponentResult> InvokeAsync()
    {
        var isAdmin = string.Equals(_user.RoleCode, "ADMIN", StringComparison.OrdinalIgnoreCase);

        return View(new ModePillModel
        {
            IsAdministrator = isAdmin,
            TestMode = _user.TestMode,
            Note = _user.TestMode ? await _config.MessageAsync(MessageKeys.TestModeOn) : null
        });
    }
}

public sealed record ModePillModel
{
    public bool IsAdministrator { get; init; }
    public bool TestMode { get; init; }
    public string? Note { get; init; }
}

/// <summary>
/// One row of pills shared by Identify, Review and Calibration. Which pills, what they
/// are called and how they group is data, so the three cannot drift apart.
/// </summary>
public sealed class FunnelViewComponent : ViewComponent
{
    public IViewComponentResult Invoke(IReadOnlyList<FunnelPillRow> pills, string? activePill)
        => View(new FunnelModel { Pills = pills, ActivePill = activePill });
}

public sealed record FunnelModel
{
    public IReadOnlyList<FunnelPillRow> Pills { get; init; } = [];
    public string? ActivePill { get; init; }

    public FunnelPillRow? Outcome => Pills.FirstOrDefault(p => p.IsOutcome);

    public IEnumerable<IGrouping<int, FunnelPillRow>> Groups
        => Pills.Where(p => !p.IsOutcome).GroupBy(p => p.GroupNo).OrderBy(g => g.Key);
}

/// <summary>
/// The process and stage tab strip. The process label sits above its stages, not on
/// every tab, and each tab carries its window and its state.
/// </summary>
public sealed class StageTabsViewComponent : ViewComponent
{
    public IViewComponentResult Invoke(IReadOnlyList<StageTabRow> tabs, StageStateRow state)
        => View(new StageTabsModel { Tabs = tabs, State = state });
}

public sealed record StageTabsModel
{
    public IReadOnlyList<StageTabRow> Tabs { get; init; } = [];
    public required StageStateRow State { get; init; }

    public IEnumerable<IGrouping<(int Id, string Name), StageTabRow>> ByProcess
        => Tabs.GroupBy(t => (t.CycleProcessId, t.ProcessName)).OrderBy(g => g.First().ProcessSort);
}

/// <summary>
/// The numbered step pills and the progress meter: "3 of 5 set · 1 skipped · still to do:
/// Eligible pool."
/// </summary>
public sealed class StepMeterViewComponent : ViewComponent
{
    public IViewComponentResult Invoke(
        IReadOnlyList<WizardStepRow> steps, int currentStep, int cycleId,
        IReadOnlyList<ValidationTodoRow> todos, string meter)
        => View(new StepMeterModel
        {
            Steps = steps,
            CurrentStep = currentStep,
            CycleId = cycleId,
            StepsWithTodos = todos.Where(t => t.StepNo is not null).Select(t => t.StepNo!.Value).ToHashSet(),
            Meter = meter
        });
}

public sealed record StepMeterModel
{
    public IReadOnlyList<WizardStepRow> Steps { get; init; } = [];
    public int CurrentStep { get; init; }
    public int CycleId { get; init; }
    public IReadOnlySet<int> StepsWithTodos { get; init; } = new HashSet<int>();
    public string Meter { get; init; } = string.Empty;

    /// <summary>
    /// A step is done when nothing blocking still points at it and it is not the one
    /// being worked on. Skipped is its own state, and reads as "–" rather than a tick.
    /// </summary>
    public string StateOf(WizardStepRow step)
    {
        if (step.IsSkipped) return "is-skipped";
        if (step.StepNo == CurrentStep) return "is-current";
        return StepsWithTodos.Contains(step.StepNo) ? string.Empty : "is-done";
    }
}

/// <summary>The toasts the server left in TempData, handed to site.js to render.</summary>
public sealed class ToastsViewComponent : ViewComponent
{
    public IViewComponentResult Invoke(string? json) => View("Default", json ?? "[]");
}
