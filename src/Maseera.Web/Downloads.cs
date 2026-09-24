using System.Text;
using ClosedXML.Excel;
using Microsoft.AspNetCore.Mvc;

namespace Maseera.Web;

/// <summary>
/// CSV and XLSX, in one place.
///
/// An export always streams from the same procedure the screen reads with paging off,
/// never from what happens to be on screen — so what is exported is what the database
/// says, not what fitted on a page.
/// </summary>
public static class Downloads
{
    public const string CsvContentType = "text/csv";
    public const string XlsxContentType =
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

    public static FileContentResult Csv(IReadOnlyList<IDictionary<string, object?>> rows, string fileName)
    {
        var sb = new StringBuilder();

        if (rows.Count > 0)
            sb.AppendLine(string.Join(",", rows[0].Keys.Select(Escape)));

        foreach (var row in rows)
            sb.AppendLine(string.Join(",", row.Values.Select(v => Escape(Format(v)))));

        // A byte-order mark, so Excel opens it as UTF-8 rather than guessing.
        var bytes = Encoding.UTF8.GetPreamble()
            .Concat(Encoding.UTF8.GetBytes(sb.ToString()))
            .ToArray();

        return new FileContentResult(bytes, CsvContentType) { FileDownloadName = fileName + ".csv" };
    }

    public static FileContentResult Xlsx(
        IReadOnlyList<IDictionary<string, object?>> rows, string fileName, string sheetName)
    {
        using var wb = new XLWorkbook();
        var ws = wb.Worksheets.Add(Sanitise(sheetName));

        if (rows.Count > 0)
        {
            var headers = rows[0].Keys.ToList();

            for (var c = 0; c < headers.Count; c++)
                ws.Cell(1, c + 1).Value = headers[c];
            ws.Row(1).Style.Font.Bold = true;

            for (var r = 0; r < rows.Count; r++)
            {
                var values = rows[r];
                for (var c = 0; c < headers.Count; c++)
                    ws.Cell(r + 2, c + 1).Value = Format(values[headers[c]]);
            }

            ws.SheetView.FreezeRows(1);
            ws.Columns().AdjustToContents();
        }

        using var ms = new MemoryStream();
        wb.SaveAs(ms);
        return new FileContentResult(ms.ToArray(), XlsxContentType) { FileDownloadName = fileName + ".xlsx" };
    }

    private static string Format(object? value) => value switch
    {
        null => string.Empty,
        DateTime dt => dt.ToString("yyyy-MM-dd"),
        DateOnly d => d.ToString("yyyy-MM-dd"),
        bool b => b ? "Yes" : "No",
        _ => value.ToString() ?? string.Empty
    };

    private static string Escape(string value)
        => value.Contains(',') || value.Contains('"') || value.Contains('\n')
            ? "\"" + value.Replace("\"", "\"\"") + "\""
            : value;

    /// <summary>A worksheet name may not carry certain characters, or exceed 31.</summary>
    private static string Sanitise(string name)
    {
        var clean = new string(name.Where(c => !"[]:*?/\\".Contains(c)).ToArray());
        return clean.Length <= 31 ? clean : clean[..31];
    }
}
