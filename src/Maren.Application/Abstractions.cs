using System.Data;
using Maren.Contracts;
using Maren.Shared;

namespace Maren.Application.Abstractions;

/// <summary>
/// Hands out connections to the platform database.
/// </summary>
/// <remarks>
/// A factory rather than an injected connection: Dapper calls are short and a
/// connection held for the lifetime of a scoped service would pin one pool
/// entry per in-flight request, which is how a busy API exhausts the pool
/// under load rather than queuing on it.
/// </remarks>
public interface IDbConnectionFactory
{
    Task<IDbConnection> CreateAsync(CancellationToken ct = default);
}

/// <summary>The id that ties everything one request did together.</summary>
/// <remarks>
/// <para>
/// One request may write audit rows, a security event and a safety event, from
/// more than one connection — the security path deliberately opens its own so a
/// rollback cannot erase the record of the attempt that caused it. Before this
/// existed, nothing said those rows were one action, so "what happened when she
/// reported this?" was answered by reading timestamps and guessing.
/// </para>
/// <para>
/// Carries no personal data. It is a random value minted per request and
/// identifies a request, never a person — which is what makes it safe to put in
/// a log line, a response header and a support ticket.
/// </para>
/// <para>
/// Returns <see cref="Guid.Empty"/> when there is no ambient request, and the
/// connection is then explicitly cleared rather than left carrying whatever the
/// last request put there. An uncorrelated audit row is honest; one stamped with
/// another request's id is worse than no correlation at all, because it would be
/// believed.
/// </para>
/// </remarks>
public interface ICorrelationContext
{
    /// <summary><see cref="Guid.Empty"/> when nothing established one.</summary>
    Guid CorrelationId { get; }
}

/// <summary>Everything the request knows about who is calling.</summary>
public interface ICurrentUser
{
    Guid? UserId { get; }
    string? IpAddress { get; }
    string? UserAgent { get; }
    IReadOnlyList<string> Permissions { get; }
    bool Has(string permission);
}

public interface IPasswordHasher
{
    (byte[] Hash, byte[] Salt, int Iterations) Hash(string password);

    /// <summary>Verifies, and reports whether the stored hash is stale.</summary>
    /// <remarks>
    /// The iteration count is raised over time. Returning
    /// <c>NeedsRehash</c> lets the login path transparently upgrade a hash on
    /// the next successful sign-in, rather than leaving old accounts on an
    /// old cost forever.
    /// </remarks>
    (bool Verified, bool NeedsRehash) Verify(
        string password, byte[] hash, byte[] salt, int iterations);
}

public interface ITokenService
{
    /// <param name="securityStamp">
    /// Written into the token so a revocation can invalidate it mid-life.
    /// Locking an account or removing a role rotates the stamp; the API refuses
    /// any token still carrying the old one.
    /// </param>
    (string Token, DateTime ExpiresUtc) CreateAccessToken(
        Guid userId, IReadOnlyList<string> permissions, Guid securityStamp);

    /// <summary>Mints an opaque refresh token and its storage hash.</summary>
    /// <remarks>
    /// The plaintext goes to the client and is never persisted; only the hash
    /// is stored, so a leaked database cannot be replayed for access.
    /// </remarks>
    (string Token, byte[] Hash, DateTime ExpiresUtc) CreateRefreshToken();

    byte[] HashRefreshToken(string token);
}

public interface IAuthRepository
{
    Task<Result<Guid>> RegisterAsync(
        string email, byte[] hash, byte[] salt, int iterations,
        string? countryIso, string languageCode, string? ip,
        CancellationToken ct);

    Task<LoginMaterial?> GetForLoginAsync(string email, CancellationToken ct);

    Task RecordLoginAsync(Guid userId, bool succeeded, string? ip,
        CancellationToken ct);

    Task<IReadOnlyList<string>> GetPermissionsAsync(Guid userId,
        CancellationToken ct);

    /// <summary>The user's current security stamp, for minting a token.</summary>
    Task<Guid> GetSecurityStampAsync(Guid userId, CancellationToken ct);

    Task IssueRefreshTokenAsync(Guid userId, Guid? deviceId, byte[] hash,
        DateTime expiresUtc, string? ip, CancellationToken ct);

    Task<Result<Guid>> RedeemRefreshTokenAsync(byte[] currentHash,
        byte[] newHash, DateTime expiresUtc, string? ip, CancellationToken ct);

    Task RegisterDeviceAsync(Guid deviceId, Guid userId, string platform,
        string? osVersion, string? appVersion, string? model, string? fcmToken,
        CancellationToken ct);
}

public sealed record LoginMaterial(
    Guid UserId,
    byte[]? PasswordHash,
    byte[]? PasswordSalt,
    int? PasswordIterations,
    bool IsLockedOut,
    DateTime? LockoutEndUtc);

public interface IConfigurationRepository
{
    Task<IReadOnlyList<FeatureFlagDto>> EvaluateFlagsAsync(
        Guid? userId, int? appVersionCode, string? countryIso,
        bool isPremium, bool isBeta, CancellationToken ct);

    Task<IReadOnlyList<SettingDto>> GetClientSettingsAsync(CancellationToken ct);

    Task<AppVersionCheckDto> CheckVersionAsync(string platform,
        int versionCode, CancellationToken ct);

    Task<IReadOnlyList<FeatureFlagAdminDto>> ListFlagsAsync(CancellationToken ct);

    Task<FeatureFlagAdminDto> UpsertFlagAsync(
        UpsertFeatureFlagRequest request, Guid? actorUserId,
        CancellationToken ct);
}

/// <summary>
/// Turns a semantic version into the integer the database compares on.
/// </summary>
/// <remarks>
/// Mirrors <c>Administration.fn_VersionToCode</c> exactly. Duplicated
/// deliberately: the client sends a version string, and converting it in the
/// API means the stored procedure receives a number it can index on rather
/// than parsing text per row.
/// </remarks>
public static class VersionCode
{
    public static int Parse(string? version)
    {
        if (string.IsNullOrWhiteSpace(version)) return 0;

        var parts = version.Split('.');
        var major = SafeInt(parts.ElementAtOrDefault(0));
        var minor = SafeInt(parts.ElementAtOrDefault(1));
        var patch = SafeInt(parts.ElementAtOrDefault(2));
        return major * 1_000_000 + minor * 1_000 + patch;

        static int SafeInt(string? s) =>
            int.TryParse(s, out var value) ? value : 0;
    }
}
