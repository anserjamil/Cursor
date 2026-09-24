using Maseera.Core;
using Maseera.Data;
using Maseera.Web.Security;
using Maseera.Web.Startup;
using Microsoft.AspNetCore.Authentication.Negotiate;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Net.Http.Headers;
using Serilog;
using Serilog.Events;

// ---------------------------------------------------------------------------------------
// 1 — Serilog, before anything else, so a failure during wiring is still recorded.
//     Enriched with the login, the screen code and the cycle id by the middleware and the
//     controllers, so a line in the log says who did what, where.
// ---------------------------------------------------------------------------------------
Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Information()
    .MinimumLevel.Override("Microsoft.AspNetCore", LogEventLevel.Warning)
    .Enrich.FromLogContext()
    .WriteTo.Console()
    .WriteTo.File("logs/maseera-.log", rollingInterval: RollingInterval.Day, retainedFileCountLimit: 30)
    .CreateLogger();

try
{
    var builder = WebApplication.CreateBuilder(args);
    builder.Host.UseSerilog();

    // -----------------------------------------------------------------------------------
    // 2 — MVC, with anti-forgery on every write by default rather than by remembering.
    // -----------------------------------------------------------------------------------
    builder.Services.AddControllersWithViews(options =>
    {
        options.Filters.Add(new AutoValidateAntiforgeryTokenAttribute());

        // An auditor who finds a form gets the prototype's sentence, not a bare 403.
        options.Filters.Add<ReadOnlyGuardFilter>();
    });

    builder.Services.AddHttpContextAccessor();

    // -----------------------------------------------------------------------------------
    // 3 — Windows authentication, and a single authorization policy. There is no role
    //     literal anywhere in this application: the decision belongs to sec.fn_ScreenAccess.
    // -----------------------------------------------------------------------------------
    builder.Services.AddAuthentication(NegotiateDefaults.AuthenticationScheme).AddNegotiate();

    builder.Services.AddAuthorization(options =>
    {
        options.AddPolicy(ScreenAccessAttribute.PolicyName, policy =>
            policy.Requirements.Add(new ScreenAccessRequirement()));
    });
    builder.Services.AddSingleton<IAuthorizationHandler, ScreenAccessHandler>();

    // -----------------------------------------------------------------------------------
    // 4 — The request's user context, resolved once from sec.AppUser / sec.UserRole.
    // -----------------------------------------------------------------------------------
    builder.Services.AddScoped<UserContext>();
    builder.Services.AddScoped<IUserContext>(sp => sp.GetRequiredService<UserContext>());

    // -----------------------------------------------------------------------------------
    // 5 and 6 — The connection factory, the runner, the repositories, and the
    //           configuration cache keyed on a content stamp.
    // -----------------------------------------------------------------------------------
    builder.Services.AddMaseeraData(builder.Configuration);

    // It creates its own scope when it runs, so it is a singleton: the check happens
    // once at startup and again whenever /Admin/Health is opened.
    builder.Services.AddSingleton<SelfCheck>();

    // -----------------------------------------------------------------------------------
    // 7 — Compression, static files, and the refusal pages.
    // -----------------------------------------------------------------------------------
    builder.Services.AddResponseCompression(o => o.EnableForHttps = true);

    var app = builder.Build();

    if (!app.Environment.IsDevelopment())
    {
        app.UseExceptionHandler("/Selection/Cycles/Error");
        app.UseHsts();
    }

    app.UseResponseCompression();

    app.UseStaticFiles(new StaticFileOptions
    {
        OnPrepareResponse = ctx =>
        {
            // Self-hosted fonts never change under a given name, so they are cached hard.
            // The tool runs on a restricted network: there is no CDN, ever.
            var path = ctx.File.Name;
            var isFont = path.EndsWith(".woff2", StringComparison.OrdinalIgnoreCase)
                      || path.EndsWith(".woff", StringComparison.OrdinalIgnoreCase);

            ctx.Context.Response.GetTypedHeaders().CacheControl = new CacheControlHeaderValue
            {
                Public = true,
                MaxAge = isFont ? TimeSpan.FromDays(30) : TimeSpan.FromHours(1)
            };
        }
    });

    app.UseRouting();
    app.UseAuthentication();

    // Between authentication and authorization: the ScreenAccess handler needs to know
    // who is asking, and as of when, before it can decide anything.
    app.UseMaseeraUserContext();

    app.UseAuthorization();

    // A refusal is a designed state and gets a page that says why, in words.
    app.UseStatusCodePagesWithReExecute("/Selection/Cycles/Refused", "?code={0}");

    // -----------------------------------------------------------------------------------
    // 8 — Areas first, then the default route redirecting into Selection.
    // -----------------------------------------------------------------------------------
    app.MapControllerRoute(
        name: "areas",
        pattern: "{area:exists}/{controller=Cycles}/{action=Index}/{id?}");

    app.MapControllerRoute(
        name: "default",
        pattern: "{controller=Cycles}/{action=Index}/{id?}",
        defaults: new { area = "Selection" });

    // -----------------------------------------------------------------------------------
    // 9 — The startup self-check. Fail loudly here, not on the screen that needs the row.
    // -----------------------------------------------------------------------------------
    var selfCheck = app.Services.GetRequiredService<SelfCheck>();
    await selfCheck.RunAsync(throwOnFatal: !app.Environment.IsDevelopment());

    app.Run();
}
catch (Exception ex) when (ex is not HostAbortedException)
{
    Log.Fatal(ex, "Maseera did not start.");
    throw;
}
finally
{
    Log.CloseAndFlush();
}

/// <summary>Exposed so the test host can reach the application's composition.</summary>
public partial class Program;
