using Maren.Application;
using Serilog.Context;

namespace Maren.Api;

/// <summary>
/// Establishes the correlation id for a request, once, before anything else runs.
/// </summary>
/// <remarks>
/// <para>
/// Registered first in the pipeline. Everything downstream — the authorization
/// behaviour, the audit rows a handler writes, the security event a refusal
/// writes on its own connection, and the log lines all of them emit — reads the
/// value this sets.
/// </para>
/// <para>
/// The id is echoed in <c>X-Correlation-Id</c> so a woman reporting a problem, or
/// a developer reading a failed response, can quote one value that finds every
/// row and every log line for that request.
/// </para>
/// </remarks>
public sealed class CorrelationMiddleware(RequestDelegate next)
{
    public const string HeaderName = "X-Correlation-Id";
    internal const string ItemKey = "Maren.CorrelationId";

    public async Task InvokeAsync(HttpContext context)
    {
        var correlationId = ResolveIncoming(context) ?? Guid.NewGuid();

        context.Items[ItemKey] = correlationId;

        /*  Set before the response starts. A header added after the first byte
            is written is silently dropped, and the value would then exist in the
            audit trail and the logs but not in the thing the caller can see —
            which is the one copy a support conversation starts from. */
        context.Response.OnStarting(() =>
        {
            context.Response.Headers[HeaderName] = correlationId.ToString();
            return Task.CompletedTask;
        });

        /*  Every log line for this request carries it, so a log aggregator can
            answer the same question the audit trail can. This is what makes the
            two joinable: until now the logs and the audit rows had no shared
            key at all. */
        using (LogContext.PushProperty("CorrelationId", correlationId))
        {
            await next(context);
        }
    }

    /// <summary>
    /// A caller-supplied id, when it is one — otherwise nothing.
    /// </summary>
    /// <remarks>
    /// <para>
    /// Honouring an inbound id is what lets a request be traced from the mobile
    /// client through the API, which is the point of having one.
    /// </para>
    /// <para>
    /// It is accepted only if it parses as a GUID. That is not a security
    /// boundary — a correlation id authorises nothing and identifies nobody — but
    /// an unvalidated header would let a caller write arbitrary text into a
    /// column typed <c>UNIQUEIDENTIFIER</c>, and the write that failed would be
    /// the audit row rather than the request. Refusing the junk and minting a
    /// fresh id keeps the trail intact.
    /// </para>
    /// </remarks>
    private static Guid? ResolveIncoming(HttpContext context)
    {
        if (!context.Request.Headers.TryGetValue(HeaderName, out var values))
            return null;

        var candidate = values.ToString();

        return Guid.TryParse(candidate, out var parsed) && parsed != Guid.Empty
            ? parsed
            : null;
    }
}

/// <summary>Reads the current request's correlation id for the infrastructure layer.</summary>
/// <remarks>
/// The indirection exists so <c>Maren.Infrastructure</c> — and therefore
/// <c>SqlConnectionFactory</c> — needs no dependency on ASP.NET to answer a
/// question about a GUID.
/// </remarks>
internal sealed class HttpCorrelationSource(IHttpContextAccessor accessor)
    : IHttpCorrelationSource
{
    public Guid? CorrelationId =>
        accessor.HttpContext?.Items.TryGetValue(
            CorrelationMiddleware.ItemKey, out var value) == true
            && value is Guid id
            ? id
            : null;
}
