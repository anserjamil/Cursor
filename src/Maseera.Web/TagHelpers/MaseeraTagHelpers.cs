using Maseera.Core;
using Maseera.Core.Presentation;
using Maseera.Data;
using Microsoft.AspNetCore.Razor.TagHelpers;

namespace Maseera.Web.TagHelpers;

/// <summary>
/// &lt;share-text count="41" total="300" /&gt;
///
/// Every share in the application goes through this, and through the one formatter
/// behind it. A non-zero count that rounds to nothing reads "under 1%"; a count short of
/// the total that rounds to everything reads "over 99%". The two sentences come from
/// cfg.Message, so an administrator can reword them.
/// </summary>
[HtmlTargetElement("share-text")]
public sealed class ShareTextTagHelper : TagHelper
{
    private readonly IConfigCache _config;

    public ShareTextTagHelper(IConfigCache config) => _config = config;

    public long Count { get; set; }
    public long Total { get; set; }

    /// <summary>Renders "41 of 300 · 14%" rather than the share alone.</summary>
    public bool WithCount { get; set; }

    public override async Task ProcessAsync(TagHelperContext context, TagHelperOutput output)
    {
        var under = await _config.MessageAsync(MessageKeys.ShareUnderOne);
        var over = await _config.MessageAsync(MessageKeys.ShareOverNinetyNine);

        output.TagName = "span";
        output.Attributes.SetAttribute("class", "ms-num");
        output.Attributes.SetAttribute("title", $"{Count:N0} of {Total:N0}");
        output.Content.SetContent(WithCount
            ? Share.CountAndShare(Count, Total, under, over)
            : Share.Text(Count, Total, under, over));
    }
}

/// <summary>
/// &lt;state-chip role="warning" label="Watch list" /&gt;
///
/// The role is cfg.DomainValue.SemanticRole. The stylesheet decides what it looks like,
/// and the glyph in the chip means the state never depends on hue alone.
/// </summary>
[HtmlTargetElement("state-chip")]
public sealed class StateChipTagHelper : TagHelper
{
    public string? Role { get; set; }
    public string? Label { get; set; }

    public override void Process(TagHelperContext context, TagHelperOutput output)
    {
        output.TagName = "span";
        output.Attributes.SetAttribute("class", "ms-state " + SemanticRoles.CssClass(Role));
        output.Content.SetContent(Label ?? string.Empty);
    }
}

/// <summary>
/// &lt;ms-code&gt;CRS-CAP-02&lt;/ms-code&gt; — every identifier in IBM Plex Mono.
/// </summary>
[HtmlTargetElement("ms-code")]
public sealed class CodeTagHelper : TagHelper
{
    public override void Process(TagHelperContext context, TagHelperOutput output)
    {
        output.TagName = "span";
        output.Attributes.SetAttribute("class", "ms-code");
    }
}

/// <summary>
/// &lt;as-of-date value="@date" /&gt; — a date read against the as-of date, never against
/// today, with how it sits relative to it as the tooltip.
/// </summary>
[HtmlTargetElement("as-of-date")]
public sealed class AsOfDateTagHelper : TagHelper
{
    private readonly IUserContext _user;

    public AsOfDateTagHelper(IUserContext user) => _user = user;

    public DateOnly? Value { get; set; }

    /// <summary>Shows "in 12 days" instead of the date itself.</summary>
    public bool Relative { get; set; }

    public override void Process(TagHelperContext context, TagHelperOutput output)
    {
        output.TagName = "time";

        if (Value is null)
        {
            output.Attributes.SetAttribute("class", "ms-table__recessive");
            output.Content.SetContent("—");
            return;
        }

        output.Attributes.SetAttribute("datetime", Value.Value.ToString("yyyy-MM-dd"));
        output.Attributes.SetAttribute("title", AsOf.Relative(Value, _user.AsOf));

        // A date that has already passed is a state, and the class says so.
        if (AsOf.IsPast(Value, _user.AsOf))
            output.Attributes.SetAttribute("class", "ms-date ms-date--past");

        output.Content.SetContent(Relative ? AsOf.Relative(Value, _user.AsOf) : AsOf.Date(Value));
    }
}

/// <summary>
/// &lt;ms-bar value="56" tick="75" /&gt; — a bar with the threshold tick the readiness
/// ladder needs. The value is a share the server computed; this draws it.
/// </summary>
[HtmlTargetElement("ms-bar")]
public sealed class BarTagHelper : TagHelper
{
    public double Value { get; set; }
    public double? Tick { get; set; }
    public bool Small { get; set; }
    public string? Label { get; set; }

    public override void Process(TagHelperContext context, TagHelperOutput output)
    {
        var width = Math.Clamp(Value, 0, 100).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture);

        output.TagName = "div";
        output.Attributes.SetAttribute("class", Small ? "ms-bar ms-bar--sm" : "ms-bar");
        output.Attributes.SetAttribute("role", "img");
        output.Attributes.SetAttribute("aria-label", Label ?? $"{width}%");

        var html = $"""<div class="ms-bar__fill" style="width:{width}%"></div>""";

        if (Tick is { } tick)
        {
            var at = Math.Clamp(tick, 0, 100).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture);
            html += $"""<div class="ms-bar__tick" style="left:{at}%"></div>""";
        }

        output.Content.SetHtmlContent(html);
    }
}
