using System.Globalization;

namespace Maren.Api;

/// <summary>
/// The container health probe: <c>dotnet Maren.Api.dll --healthcheck</c>.
/// </summary>
/// <remarks>
/// <para>
/// The Dockerfile has always declared this probe. Nothing implemented it, so
/// the argument was silently swallowed by the host builder and the "probe"
/// started a <em>second complete copy of the API</em> inside the container
/// every thirty seconds. That second copy tried to bind the port the real one
/// already held, failed, and exited non-zero — so the health check reported
/// failure forever, for a process that was serving traffic correctly.
/// </para>
/// <para>
/// The probe deliberately calls the same <c>/health/live</c> endpoint an
/// orchestrator would call, over the loopback interface, rather than checking
/// some internal flag. A probe that tests a different thing from the load
/// balancer is a probe that disagrees with it, and the disagreement only ever
/// surfaces during an incident.
/// </para>
/// <para>
/// Liveness, never readiness. Readiness touches the database, and a container
/// runtime that kills instances because SQL Server blinked takes the platform
/// down harder than the blink did.
/// </para>
/// <para>
/// It is written with no dependency on <c>curl</c> or <c>wget</c> on purpose:
/// the ASP.NET runtime image contains neither, which is why the original
/// author reached for <c>dotnet</c> here. That instinct was right; only the
/// implementation was missing.
/// </para>
/// </remarks>
public static class HealthProbe
{
    public const string Flag = "--healthcheck";

    /// <summary>Exit code 0 when the process is alive, 1 otherwise.</summary>
    public static async Task<int> RunAsync(string[] args)
    {
        var url = $"{ResolveBaseAddress(args)}/health/live";

        try
        {
            /*  Four seconds: under the Dockerfile's HEALTHCHECK --timeout of
                five, so this returns a verdict rather than being killed halfway
                and reported as a generic failure — but not so tight that a cold
                first request fails.

                That second half is measured, not theoretical. At three seconds
                the very first probe against a freshly started API timed out
                while curl answered the same URL in 11ms immediately afterwards:
                the probe was paying the JIT cost of the whole request pipeline
                and everything after it was warm. The Dockerfile's
                --start-period exists precisely so that early failure does not
                count against the container, but a probe that only works once
                something else has warmed the pipeline is a probe that lies
                about the one moment anybody is watching. */
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(4) };

            using var response = await http.GetAsync(url);

            if (response.IsSuccessStatusCode)
                return 0;

            await Console.Error.WriteLineAsync(string.Format(
                CultureInfo.InvariantCulture,
                "healthcheck: {0} returned {1}", url, (int)response.StatusCode));
            return 1;
        }
        catch (Exception ex)
        {
            // The message matters: an operator reading `docker inspect` output
            // needs to tell "the app is down" from "the probe is pointed at the
            // wrong port", and those look identical without it.
            await Console.Error.WriteLineAsync(string.Format(
                CultureInfo.InvariantCulture,
                "healthcheck: {0} unreachable — {1}", url, ex.Message));
            return 1;
        }
    }

    /// <summary>
    /// Where the API is listening, from the same configuration the host uses.
    /// </summary>
    /// <remarks>
    /// Always over loopback. <c>ASPNETCORE_URLS</c> is typically
    /// <c>http://+:8080</c>, and the wildcard host is a binding instruction
    /// rather than an address anything can connect to.
    /// </remarks>
    internal static string ResolveBaseAddress(string[] args)
    {
        var explicitUrl = args
            .SkipWhile(a => !string.Equals(a, Flag, StringComparison.Ordinal))
            .Skip(1)
            .FirstOrDefault(a => a.StartsWith("http", StringComparison.OrdinalIgnoreCase));

        var configured = explicitUrl
            ?? Environment.GetEnvironmentVariable("ASPNETCORE_URLS")
            ?? "http://localhost:8080";

        // Several URLs may be configured; the first is enough to prove the
        // process is answering.
        var first = configured.Split(';', StringSplitOptions.RemoveEmptyEntries)[0].Trim();

        var scheme = first.StartsWith("https", StringComparison.OrdinalIgnoreCase)
            ? "https" : "http";

        var port = 8080;
        var lastColon = first.LastIndexOf(':');
        if (lastColon > -1 &&
            int.TryParse(
                first[(lastColon + 1)..].TrimEnd('/'),
                NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed))
        {
            port = parsed;
        }

        return string.Format(CultureInfo.InvariantCulture, "{0}://127.0.0.1:{1}", scheme, port);
    }
}
