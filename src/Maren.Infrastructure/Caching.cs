using System.Collections.Concurrent;
using Maren.Application.Abstractions;
using Maren.Application.Behaviors;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.DependencyInjection;

namespace Maren.Infrastructure;

/// <summary>
/// In-process query cache with prefix invalidation.
/// </summary>
/// <remarks>
/// <see cref="IMemoryCache"/> alone cannot enumerate or clear by prefix, and
/// content invalidation is inherently "drop everything under content:". The
/// key set is tracked alongside so a prefix sweep is possible.
///
/// <para>
/// In-process, so each API instance keeps its own copy. Behind a load balancer
/// that means an editor's change can take up to the TTL to appear on an
/// instance that did not serve the write. Acceptable at a five-minute client
/// TTL and a thirty-second admin TTL; when the platform scales past one
/// instance this wants replacing with Redis, which is why it sits behind
/// <see cref="IQueryCache"/> rather than being called directly.
/// </para>
/// </remarks>
public sealed class MemoryQueryCache(IMemoryCache cache) : IQueryCache
{
    private readonly ConcurrentDictionary<string, byte> _keys = new();

    public bool TryGet<T>(string key, out T? value)
    {
        if (cache.TryGetValue(key, out var stored) && stored is T typed)
        {
            value = typed;
            return true;
        }
        value = default;
        return false;
    }

    public void Set<T>(string key, T value, TimeSpan duration)
    {
        _keys[key] = 0;

        cache.Set(key, value, new MemoryCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = duration
        }.RegisterPostEvictionCallback((evicted, _, _, _) =>
        {
            // Keeps the key set from growing without bound as entries expire
            // naturally rather than through an explicit removal.
            if (evicted is string s) _keys.TryRemove(s, out _);
        }));
    }

    public void Remove(string key)
    {
        cache.Remove(key);
        _keys.TryRemove(key, out _);
    }

    public void RemoveByPrefix(string prefix)
    {
        foreach (var key in _keys.Keys.Where(k => k.StartsWith(prefix,
                     StringComparison.Ordinal)).ToList())
        {
            Remove(key);
        }
    }
}

/// <summary>
/// Evaluates a single flag for the pipeline.
/// </summary>
/// <remarks>
/// Cached briefly. Flag evaluation runs on the authorization path of every
/// gated request, and hitting the database each time would put a query in
/// front of every content operation. Thirty seconds bounds how long a
/// kill-switch takes to bite, which is short enough for the "turn it off at
/// 3am" case the flag exists for.
/// </remarks>
public sealed class CachedFeatureFlagEvaluator(
    IConfigurationRepository repository, IQueryCache cache)
    : IFeatureFlagEvaluator
{
    private static readonly TimeSpan Ttl = TimeSpan.FromSeconds(30);

    public async Task<bool> IsEnabledAsync(
        string key, Guid? userId, CancellationToken ct)
    {
        var cacheKey = $"flags:{userId?.ToString() ?? "anon"}";

        if (!cache.TryGet<Dictionary<string, bool>>(cacheKey, out var flags) ||
            flags is null)
        {
            var evaluated = await repository.EvaluateFlagsAsync(
                userId, null, null, false, false, ct);

            flags = evaluated.ToDictionary(f => f.Key, f => f.IsEnabled);
            cache.Set(cacheKey, flags, Ttl);
        }

        // A flag nobody has defined is on.
        //
        // The alternative — default off — means adding a new IRequireFeature
        // gate to a handler silently disables that endpoint on every
        // environment until somebody remembers to insert a row. Defaulting on
        // makes the flag an off-switch for something that already works, which
        // is how the rest of the platform treats them.
        return !flags.TryGetValue(key, out var enabled) || enabled;
    }
}

public static class CachingRegistration
{
    public static IServiceCollection AddMarenCaching(
        this IServiceCollection services)
    {
        services.AddMemoryCache();
        services.AddSingleton<IQueryCache, MemoryQueryCache>();
        services.AddScoped<IFeatureFlagEvaluator, CachedFeatureFlagEvaluator>();
        return services;
    }
}
