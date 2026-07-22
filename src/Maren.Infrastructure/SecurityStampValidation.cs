using System.Collections.Concurrent;
using Maren.Application.Access;
using Maren.Application.Behaviors;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace Maren.Infrastructure;

/// <summary>
/// Refuses access tokens that were valid when issued but have since been
/// revoked.
/// </summary>
/// <remarks>
/// Permissions travel as claims in a 15-minute access token so authorization
/// needs no database round trip per request. The cost is staleness: locking a
/// compromised account or removing an administrator's role would otherwise
/// leave the holder fully privileged for the rest of that window — which is
/// exactly the window the action was taken to close.
///
/// <para>
/// The compromise: the token carries the user's security stamp, and this
/// compares it against a cached snapshot of every current stamp, refreshed
/// every 30 seconds. Checking the database per request would put a query in
/// front of the entire API to defend against a 30-second exposure; not checking
/// at all leaves fifteen minutes. Thirty seconds is short enough for the
/// "lock this account now" case the feature exists for.
/// </para>
///
/// <para>
/// Only revoked users are cached. A user who has never been locked, had a role
/// changed, or been signed out has no row, and the common path is a dictionary
/// miss returning "current".
/// </para>
/// </remarks>
public sealed class CachedSecurityStampValidator(
    IAccessRepository repository,
    IQueryCache cache,
    ILogger<CachedSecurityStampValidator> logger)
    : ISecurityStampValidator
{
    private const string CacheKey = "security:revocations";
    private static readonly TimeSpan Ttl = TimeSpan.FromSeconds(30);

    public async Task<bool> IsCurrentAsync(
        Guid userId, Guid tokenStamp, CancellationToken ct)
    {
        if (!cache.TryGet<ConcurrentDictionary<Guid, Guid>>(CacheKey, out var map)
            || map is null)
        {
            var rows = await repository.GetRevocationsAsync(ct);

            map = new ConcurrentDictionary<Guid, Guid>(
                rows.ToDictionary(r => r.UserId, r => r.SecurityStamp));

            cache.Set(CacheKey, map, Ttl);
        }

        // No revocation on record: nothing has ever invalidated this user's
        // sessions, so any correctly signed token for them is current.
        if (!map.TryGetValue(userId, out var currentStamp)) return true;

        if (currentStamp == tokenStamp) return true;

        logger.LogInformation(
            "Refused a stale token for {UserId}: sessions were revoked.", userId);

        return false;
    }
}

/// <summary>
/// A validator for hosts that have no access repository wired up.
/// </summary>
/// <remarks>
/// Deliberately fails closed on nothing — it accepts every token — and exists
/// only so a host that does not expose administrative endpoints does not need
/// the access slice registered. It is never used by the API.
/// </remarks>
public sealed class AlwaysCurrentSecurityStampValidator : ISecurityStampValidator
{
    public Task<bool> IsCurrentAsync(
        Guid userId, Guid tokenStamp, CancellationToken ct) =>
        Task.FromResult(true);
}

public static class SecurityStampRegistration
{
    public static IServiceCollection AddMarenSecurityStamps(
        this IServiceCollection services)
    {
        services.AddScoped<ISecurityStampValidator, CachedSecurityStampValidator>();
        return services;
    }
}
