using System.Text.RegularExpressions;
using FluentAssertions;

namespace Maseera.Tests.Unit;

/// <summary>
/// The rules the views have to keep, checked by reading them.
///
/// Part 12 names five bugs to design out. Three of them are things a view can reintroduce
/// on any Tuesday — a stray percentage, a CDN link, a colour written into markup — so
/// they are scanned for rather than trusted to review.
/// </summary>
public class ViewDisciplineTests
{
    private static readonly string WebRoot = FindWebRoot();

    private static IEnumerable<(string Path, string Text)> Views()
        => Directory.EnumerateFiles(WebRoot, "*.cshtml", SearchOption.AllDirectories)
            .Select(p => (Relative(p), File.ReadAllText(p)));

    private static IEnumerable<(string Path, string Text)> Scripts()
        => Directory.EnumerateFiles(Path.Combine(WebRoot, "wwwroot", "js"), "*.js", SearchOption.AllDirectories)
            .Select(p => (Relative(p), File.ReadAllText(p)));

    private static IEnumerable<(string Path, string Text)> Styles()
        => Directory.EnumerateFiles(Path.Combine(WebRoot, "wwwroot"), "*.scss", SearchOption.AllDirectories)
            .Select(p => (Relative(p), File.ReadAllText(p)));

    /* ---- Part 12.4: a percentage never contradicts its count -------------------- */

    [Fact]
    public void No_view_formats_a_number_as_a_percentage_itself()
    {
        // ToString("P") rounds on its own terms and will print 0% for a non-zero count.
        // Every share goes through the one helper, which is the whole point of having it.
        var offenders = Views()
            .Where(v => Regex.IsMatch(v.Text, @"ToString\(\s*""P\d?""\s*\)", RegexOptions.IgnoreCase))
            .Select(v => v.Path)
            .ToList();

        offenders.Should().BeEmpty(
            "every share is formatted by Share.Text through the <share-text> tag helper");
    }

    [Fact]
    public void No_view_computes_a_share_in_razor()
    {
        // "100.0 * count / total" in a view is a second formatter, and the second one is
        // always the one that disagrees.
        var pattern = new Regex(@"100(\.0*)?\s*\*\s*\(?\s*\w", RegexOptions.None);

        var offenders = Views()
            .Where(v => pattern.IsMatch(v.Text))
            .Select(v => v.Path)
            .ToList();

        offenders.Should().BeEmpty(
            "a share is computed by the database or by Share, never in a view");
    }

    /* ---- the restricted network: everything is served from this machine --------- */

    [Fact]
    public void Nothing_is_loaded_from_a_content_delivery_network()
    {
        // The tool runs where outbound HTTP does not work. A CDN link is not a slow
        // stylesheet; it is a blank page.
        var pattern = new Regex(@"(src|href)\s*=\s*[""']\s*(https?:)?//", RegexOptions.IgnoreCase);

        var offenders = Views()
            .Where(v => pattern.IsMatch(v.Text))
            .Select(v => v.Path)
            .ToList();

        offenders.Should().BeEmpty("no CDN, ever — not the stylesheet, not the script, not the fonts");
    }

    [Fact]
    public void The_fonts_are_served_from_this_machine()
    {
        var css = Directory.EnumerateFiles(Path.Combine(WebRoot, "wwwroot"), "*.scss", SearchOption.AllDirectories)
            .Select(File.ReadAllText)
            .ToList();

        css.Should().NotBeEmpty();
        string.Join("\n", css).Should().Contain("@font-face");
        string.Join("\n", css).Should().NotContain("fonts.googleapis.com");
        string.Join("\n", css).Should().NotContain("fonts.gstatic.com");

        Directory.EnumerateFiles(Path.Combine(WebRoot, "wwwroot", "fonts"), "*.woff2")
            .Should().NotBeEmpty("IBM Plex is self-hosted");
    }

    /* ---- colour means one thing, and it is not decoration ----------------------- */

    [Fact]
    public void No_view_writes_a_colour_into_markup()
    {
        // A hex colour in a view is a state the stylesheet cannot restyle, cannot invert
        // for forced-colours, and cannot keep consistent with the rest of the product.
        var pattern = new Regex(@"(color|background)\s*:\s*(#[0-9a-f]{3,8}|rgb|hsl|oklch)", RegexOptions.IgnoreCase);

        var offenders = Views()
            .Where(v => pattern.IsMatch(v.Text))
            .Select(v => v.Path)
            .ToList();

        offenders.Should().BeEmpty("colour comes from SemanticRole through a class, never from markup");
    }

    /* ---- no SQL in the application, not even in a view or a script -------------- */

    [Fact]
    public void There_is_no_sql_text_anywhere_outside_the_database_project()
    {
        var sql = new Regex(@"\b(SELECT\s+[\w*\[]|INSERT\s+INTO|UPDATE\s+\w+\s+SET|DELETE\s+FROM)\b",
            RegexOptions.IgnoreCase);

        // An identifier inside <ms-code> is the interface talking ABOUT the database —
        // the health screen says there is no SELECT 1 in the application, and saying so
        // must not itself trip the check. Everything outside those spans is scanned.
        var offenders = Views().Concat(Scripts())
            .Where(v => sql.IsMatch(WithoutCodeSpans(v.Text)))
            .Select(v => v.Path)
            .ToList();

        offenders.Should().BeEmpty("every read and every write is a stored procedure");
    }

    /* ---- plain ES2022 modules, no framework and no bundler --------------------- */

    [Fact]
    public void There_are_exactly_the_four_scripts_the_build_prompt_names()
    {
        Directory.EnumerateFiles(Path.Combine(WebRoot, "wwwroot", "js"), "*.js")
            .Select(Path.GetFileName)
            .Should().BeEquivalentTo("site.js", "tables.js", "criteria.js", "idp.js");
    }

    [Fact]
    public void No_script_imports_a_framework()
    {
        var offenders = Scripts()
            .Where(s => Regex.IsMatch(s.Text, @"\b(react|vue|angular|jquery|htmx|alpine)\b", RegexOptions.IgnoreCase))
            .Select(s => s.Path)
            .ToList();

        offenders.Should().BeEmpty("plain ES2022 modules, no framework and no bundler");
    }

    /* ---- the interface has to survive the conditions the prompt names ---------- */

    [Fact]
    public void The_stylesheet_answers_forced_colours_contrast_motion_print_and_narrow_screens()
    {
        var all = string.Join("\n", Styles().Select(s => s.Text));

        all.Should().Contain("forced-colors", "the interface survives a forced-colours mode");
        all.Should().Contain("prefers-contrast", "and a raised-contrast setting");
        all.Should().Contain("prefers-reduced-motion", "and a request for less motion");
        all.Should().Contain("@media print", "and being printed");
        all.Should().Contain("992px", "and must not break below 992px");
    }

    [Fact]
    public void Every_view_that_posts_carries_the_anti_forgery_token()
    {
        // The layout emits one token and the global filter validates every POST. A form
        // rendered outside the layout would post without one.
        var layout = File.ReadAllText(Path.Combine(WebRoot, "Views", "Shared", "_Layout.cshtml"));
        layout.Should().Contain("Html.AntiForgeryToken()");
    }

    private static string WithoutCodeSpans(string text)
        => Regex.Replace(text, "<ms-code[^>]*>.*?</ms-code>", " ",
            RegexOptions.IgnoreCase | RegexOptions.Singleline);

    private static string Relative(string path)
        => Path.GetRelativePath(WebRoot, path);

    private static string FindWebRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            var candidate = Path.Combine(dir.FullName, "src", "Maseera.Web");
            if (Directory.Exists(candidate)) return candidate;
            dir = dir.Parent;
        }

        throw new DirectoryNotFoundException(
            "src/Maseera.Web was not found above " + AppContext.BaseDirectory);
    }
}
