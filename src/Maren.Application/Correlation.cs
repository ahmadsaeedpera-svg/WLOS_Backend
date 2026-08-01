using Maren.Application.Abstractions;

namespace Maren.Application;

/// <summary>
/// An ambient correlation id for work that has no HTTP request behind it.
/// </summary>
/// <remarks>
/// <para>
/// The HTTP path establishes correlation in middleware, which covers every
/// request a woman's client makes. This exists for the rest: integration tests,
/// and eventually background work such as a scheduled resolve or an import.
/// </para>
/// <para>
/// <see cref="AsyncLocal{T}"/> rather than a field, because the operation being
/// correlated is asynchronous and opens more than one connection. A plain static
/// would bleed between concurrent operations, which is the exact defect this
/// whole slice exists to prevent.
/// </para>
/// </remarks>
public static class CorrelationScope
{
    private static readonly AsyncLocal<Guid?> Current = new();

    public static Guid? Ambient => Current.Value;

    /// <summary>Correlates everything inside the returned scope.</summary>
    public static IDisposable Begin(Guid correlationId)
    {
        var previous = Current.Value;
        Current.Value = correlationId;
        return new Restore(previous);
    }

    private sealed class Restore(Guid? previous) : IDisposable
    {
        public void Dispose() => Current.Value = previous;
    }
}

/// <summary>How a web host offers the current request's correlation id.</summary>
/// <remarks>
/// The indirection exists so this assembly — and therefore
/// <c>SqlConnectionFactory</c>, which consumes the context — needs no dependency
/// on ASP.NET to answer a question about a GUID.
/// </remarks>
public interface IHttpCorrelationSource
{
    /// <summary>Null when there is no request in flight on this thread.</summary>
    Guid? CorrelationId { get; }
}

/// <summary>The default outside a web host: there is no request.</summary>
/// <remarks>
/// A null object rather than an optional dependency, because the container does
/// not honour default constructor parameters. Registered by
/// <c>AddMarenPersistence</c> so any host able to construct a connection factory
/// automatically has what the factory needs; a web host replaces it.
/// </remarks>
public sealed class NoHttpCorrelationSource : IHttpCorrelationSource
{
    public Guid? CorrelationId => null;
}

/// <summary>
/// Reads the correlation id for the work in flight.
/// </summary>
/// <remarks>
/// Registered as a singleton so it can be consumed by
/// <c>SqlConnectionFactory</c>, which is itself a singleton. Both sources it
/// reads are ambient and per-operation, so there is no captured state here and
/// nothing to make it unsafe to share.
/// </remarks>
public sealed class CorrelationContext(IHttpCorrelationSource http)
    : ICorrelationContext
{
    public Guid CorrelationId =>
        http.CorrelationId
        ?? CorrelationScope.Ambient
        ?? Guid.Empty;
}
