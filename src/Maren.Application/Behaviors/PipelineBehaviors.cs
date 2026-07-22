using System.Diagnostics;
using FluentValidation;
using Maren.Application.Abstractions;
using Maren.Shared;
using MediatR;
using Microsoft.Extensions.Logging;

namespace Maren.Application.Behaviors;

// ---------------------------------------------------------------------------
// Marker interfaces
// ---------------------------------------------------------------------------

/// <summary>A request the caller must hold a permission to make.</summary>
/// <remarks>
/// Declared on the request rather than checked inside the handler. A handler
/// that checks its own permission can be called from another handler that
/// forgot to, and the check then silently does not run. Putting it in the
/// pipeline means it cannot be bypassed by any caller.
/// </remarks>
public interface IRequirePermission
{
    string Permission { get; }
}

/// <summary>A request whose whole execution belongs in one transaction.</summary>
public interface ITransactional;

/// <summary>A request gated on a feature flag being on.</summary>
public interface IRequireFeature
{
    string FeatureKey { get; }
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

/// <summary>
/// Runs every validator registered for the request before the handler.
/// </summary>
/// <remarks>
/// Throws rather than returning a Result: the API translates the exception
/// into a 400 with field-level errors, and threading a validation Result
/// through every handler signature would mean every handler has to remember to
/// check it.
/// </remarks>
public sealed class ValidationBehavior<TRequest, TResponse>(
    IEnumerable<IValidator<TRequest>> validators)
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    public async Task<TResponse> Handle(
        TRequest request, RequestHandlerDelegate<TResponse> next,
        CancellationToken ct)
    {
        var applicable = validators.ToList();
        if (applicable.Count == 0) return await next();

        var results = await Task.WhenAll(applicable.Select(v =>
            v.ValidateAsync(new ValidationContext<TRequest>(request), ct)));

        var failures = results
            .SelectMany(r => r.Errors)
            .Where(f => f is not null)
            .ToList();

        if (failures.Count > 0) throw new ValidationException(failures);

        return await next();
    }
}

// ---------------------------------------------------------------------------
// Authorization
// ---------------------------------------------------------------------------

public sealed class UnauthorizedRequestException(string permission)
    : Exception($"This action requires the '{permission}' permission.")
{
    public string Permission { get; } = permission;
}

public sealed class FeatureDisabledException(string featureKey)
    : Exception($"The '{featureKey}' feature is not enabled.")
{
    public string FeatureKey { get; } = featureKey;
}

public sealed class AuthorizationBehavior<TRequest, TResponse>(
    ICurrentUser currentUser)
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    public Task<TResponse> Handle(
        TRequest request, RequestHandlerDelegate<TResponse> next,
        CancellationToken ct)
    {
        if (request is IRequirePermission gate)
        {
            if (currentUser.UserId is null)
                throw new UnauthorizedRequestException(gate.Permission);

            if (!currentUser.Has(gate.Permission))
                throw new UnauthorizedRequestException(gate.Permission);
        }

        return next();
    }
}

// ---------------------------------------------------------------------------
// Feature flags
// ---------------------------------------------------------------------------

/// <summary>
/// Refuses a request whose feature is switched off.
/// </summary>
/// <remarks>
/// Evaluated server-side, not trusted from the client. A flag that only hides
/// a button in the admin UI is a suggestion; a flag checked here is a control.
/// </remarks>
public sealed class FeatureFlagBehavior<TRequest, TResponse>(
    IFeatureFlagEvaluator evaluator, ICurrentUser currentUser)
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    public async Task<TResponse> Handle(
        TRequest request, RequestHandlerDelegate<TResponse> next,
        CancellationToken ct)
    {
        if (request is IRequireFeature gate)
        {
            var enabled = await evaluator.IsEnabledAsync(
                gate.FeatureKey, currentUser.UserId, ct);

            if (!enabled) throw new FeatureDisabledException(gate.FeatureKey);
        }

        return await next();
    }
}

// ---------------------------------------------------------------------------
// Transactions
// ---------------------------------------------------------------------------

/// <summary>
/// Wraps an <see cref="ITransactional"/> request in one database transaction.
/// </summary>
/// <remarks>
/// Commits only when the handler returns a successful <see cref="Result"/>.
/// A handler that returns a failure has decided the operation did not happen,
/// and committing its partial writes anyway is how a "failed" bulk publish
/// leaves half the items live.
/// </remarks>
public sealed class TransactionBehavior<TRequest, TResponse>(
    IUnitOfWork unitOfWork, ILogger<TransactionBehavior<TRequest, TResponse>> logger)
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    public async Task<TResponse> Handle(
        TRequest request, RequestHandlerDelegate<TResponse> next,
        CancellationToken ct)
    {
        if (request is not ITransactional) return await next();

        await unitOfWork.BeginAsync(ct);
        try
        {
            var response = await next();

            if (IsFailure(response))
            {
                await unitOfWork.RollbackAsync(ct);
                logger.LogInformation(
                    "Rolled back {Request}: handler returned a failure.",
                    typeof(TRequest).Name);
            }
            else
            {
                await unitOfWork.CommitAsync(ct);
            }

            return response;
        }
        catch
        {
            await unitOfWork.RollbackAsync(ct);
            throw;
        }
    }

    private static bool IsFailure(TResponse response) => response switch
    {
        Result r => !r.Succeeded,
        // Result<T> is a struct with a Succeeded property; reflection is the
        // only way to read it generically, and it runs once per request rather
        // than per row.
        not null when response.GetType().IsGenericType &&
                      response.GetType().GetGenericTypeDefinition() == typeof(Result<>) =>
            response.GetType().GetProperty(nameof(Result.Succeeded))
                ?.GetValue(response) is false,
        _ => false
    };
}

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

public sealed class LoggingBehavior<TRequest, TResponse>(
    ILogger<LoggingBehavior<TRequest, TResponse>> logger, ICurrentUser currentUser)
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    /// <summary>Anything slower than this is logged as a warning.</summary>
    private const int SlowRequestMs = 500;

    public async Task<TResponse> Handle(
        TRequest request, RequestHandlerDelegate<TResponse> next,
        CancellationToken ct)
    {
        var name = typeof(TRequest).Name;
        var stopwatch = Stopwatch.StartNew();

        // The request name and the actor, never the request body. A content
        // command carries health-adjacent editorial copy and a save carries
        // the whole payload; neither belongs in a log that ships to an
        // aggregator.
        logger.LogInformation("Handling {Request} for {Actor}",
            name, currentUser.UserId?.ToString() ?? "anonymous");

        try
        {
            var response = await next();
            stopwatch.Stop();

            if (stopwatch.ElapsedMilliseconds > SlowRequestMs)
            {
                logger.LogWarning("{Request} took {Elapsed}ms",
                    name, stopwatch.ElapsedMilliseconds);
            }
            else
            {
                logger.LogInformation("{Request} completed in {Elapsed}ms",
                    name, stopwatch.ElapsedMilliseconds);
            }

            return response;
        }
        catch (Exception ex)
        {
            stopwatch.Stop();
            logger.LogError(ex, "{Request} failed after {Elapsed}ms",
                name, stopwatch.ElapsedMilliseconds);
            throw;
        }
    }
}

// ---------------------------------------------------------------------------
// Caching
// ---------------------------------------------------------------------------

/// <summary>A query whose result may be served from cache.</summary>
public interface ICacheableQuery
{
    string CacheKey { get; }
    TimeSpan CacheDuration { get; }
}

public sealed class CachingBehavior<TRequest, TResponse>(
    IQueryCache cache, ILogger<CachingBehavior<TRequest, TResponse>> logger)
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    public async Task<TResponse> Handle(
        TRequest request, RequestHandlerDelegate<TResponse> next,
        CancellationToken ct)
    {
        if (request is not ICacheableQuery cacheable) return await next();

        if (cache.TryGet<TResponse>(cacheable.CacheKey, out var hit))
        {
            logger.LogDebug("Cache hit for {Key}", cacheable.CacheKey);
            return hit!;
        }

        var response = await next();

        // Failures are never cached. A transient storage error would otherwise
        // be served to every caller until the entry expired.
        if (!IsFailure(response))
            cache.Set(cacheable.CacheKey, response, cacheable.CacheDuration);

        return response;
    }

    private static bool IsFailure(TResponse response) => response switch
    {
        Result r => !r.Succeeded,
        not null when response.GetType().IsGenericType &&
                      response.GetType().GetGenericTypeDefinition() == typeof(Result<>) =>
            response.GetType().GetProperty(nameof(Result.Succeeded))
                ?.GetValue(response) is false,
        _ => false
    };
}

public interface IQueryCache
{
    bool TryGet<T>(string key, out T? value);
    void Set<T>(string key, T value, TimeSpan duration);
    void Remove(string key);

    /// <summary>Drops every entry whose key starts with the prefix.</summary>
    void RemoveByPrefix(string prefix);
}

public interface IFeatureFlagEvaluator
{
    Task<bool> IsEnabledAsync(string key, Guid? userId, CancellationToken ct);
}
