using System.Text.RegularExpressions;

namespace Maseera.Tests.Sql;

/// <summary>
/// The procedure names the repositories actually pass to the runner, read out of the
/// source.
///
/// Generating the list this way is the point: a hand-written list is a second place to
/// forget something, and the test would then pass while the screen fell over.
/// </summary>
public static class RepositorySource
{
    private static readonly Regex Call = new(
        @"""(?<proc>(sel|cfg|sec|audit)\.usp_[A-Za-z0-9_]+)""", RegexOptions.Compiled);

    public static IReadOnlyList<string> ProcedureNames()
    {
        var root = FindRepositoriesFolder();

        var names = Directory.EnumerateFiles(root, "*.cs", SearchOption.AllDirectories)
            .SelectMany(f => Call.Matches(File.ReadAllText(f)))
            .Select(m => m.Groups["proc"].Value)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(n => n, StringComparer.OrdinalIgnoreCase)
            .ToList();

        if (names.Count == 0)
            throw new InvalidOperationException(
                "No procedure names were found under " + root +
                ". The scan is how this test stays honest, so an empty result is a failure.");

        return names;
    }

    private static string FindRepositoriesFolder()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            var candidate = Path.Combine(dir.FullName, "src", "Maseera.Data");
            if (Directory.Exists(candidate)) return candidate;
            dir = dir.Parent;
        }

        throw new DirectoryNotFoundException(
            "src/Maseera.Data was not found above " + AppContext.BaseDirectory);
    }
}
