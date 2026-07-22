using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Maren.Application.Abstractions;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;

namespace Maren.Infrastructure;

public sealed class JwtOptions
{
    public const string SectionName = "Jwt";

    public string Issuer { get; set; } = "maren.platform";
    public string Audience { get; set; } = "maren.app";

    /// <summary>Signing key. Must come from a secret store in production.</summary>
    public string SigningKey { get; set; } = "";

    /// <summary>
    /// Short by design.
    /// </summary>
    /// <remarks>
    /// An access token cannot be revoked once issued — that is the trade for
    /// not hitting the database on every request. Fifteen minutes bounds how
    /// long a stolen token stays useful, and the refresh token carries the
    /// revocable long-lived session instead.
    /// </remarks>
    public int AccessTokenMinutes { get; set; } = 15;

    public int RefreshTokenDays { get; set; } = 30;
}

/// <summary>PBKDF2-HMAC-SHA256.</summary>
/// <remarks>
/// Not Argon2 or bcrypt, both of which are stronger per unit of work. PBKDF2
/// is in the framework with no native dependency, which matters for a service
/// that has to run identically on a developer laptop, a Linux container and
/// Azure App Service. The iteration count is stored per row so it can be
/// raised without invalidating existing accounts.
/// </remarks>
public sealed class Pbkdf2PasswordHasher : IPasswordHasher
{
    private const int SaltBytes = 16;
    private const int HashBytes = 32;
    private const int CurrentIterations = 210_000;

    public (byte[] Hash, byte[] Salt, int Iterations) Hash(string password)
    {
        var salt = RandomNumberGenerator.GetBytes(SaltBytes);
        var hash = Derive(password, salt, CurrentIterations);
        return (hash, salt, CurrentIterations);
    }

    public (bool Verified, bool NeedsRehash) Verify(
        string password, byte[] hash, byte[] salt, int iterations)
    {
        var candidate = Derive(password, salt, iterations);

        /*  Fixed-time comparison. A byte-by-byte equality check leaks how much
            of the hash matched through timing, which is enough to reconstruct
            it given enough attempts. */
        var verified = CryptographicOperations.FixedTimeEquals(candidate, hash);
        return (verified, verified && iterations < CurrentIterations);
    }

    private static byte[] Derive(string password, byte[] salt, int iterations) =>
        Rfc2898DeriveBytes.Pbkdf2(
            Encoding.UTF8.GetBytes(password), salt, iterations,
            HashAlgorithmName.SHA256, HashBytes);
}

public sealed class JwtTokenService(IOptions<JwtOptions> options) : ITokenService
{
    private readonly JwtOptions _options = options.Value;

    public (string Token, DateTime ExpiresUtc) CreateAccessToken(
        Guid userId, IReadOnlyList<string> permissions, Guid securityStamp)
    {
        var expires = DateTime.UtcNow.AddMinutes(_options.AccessTokenMinutes);

        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, userId.ToString()),
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),

            /*  The revocation handle. Locking an account, changing its roles or
                forcing a sign-out rotates the stored stamp, and the API refuses
                any token still carrying the previous value — which is what
                turns those actions from "applies within fifteen minutes" into
                "applies within thirty seconds". */
            new("stamp", securityStamp.ToString())
        };

        /*  Permissions travel in the token so authorisation does not need a
            database round trip per request. The cost is staleness: a permission
            revoked mid-session applies at the next refresh, not immediately.
            Acceptable at a 15-minute access token; it would not be at a day.

            For revocation that must be faster than that — a locked account, a
            removed role — see the stamp claim above. */
        claims.AddRange(permissions.Select(p => new Claim("perm", p)));

        var credentials = new SigningCredentials(
            new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_options.SigningKey)),
            SecurityAlgorithms.HmacSha256);

        var token = new JwtSecurityToken(
            _options.Issuer, _options.Audience, claims,
            expires: expires, signingCredentials: credentials);

        return (new JwtSecurityTokenHandler().WriteToken(token), expires);
    }

    public (string Token, byte[] Hash, DateTime ExpiresUtc) CreateRefreshToken()
    {
        /*  Opaque random, not a JWT. There is nothing to read inside a refresh
            token, and making it unreadable means a leaked one reveals nothing
            about the user it belongs to. */
        var token = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));
        return (token, HashRefreshToken(token),
            DateTime.UtcNow.AddDays(_options.RefreshTokenDays));
    }

    public byte[] HashRefreshToken(string token) =>
        SHA256.HashData(Encoding.UTF8.GetBytes(token));
}

public static class InfrastructureRegistration
{
    public static IServiceCollection AddMarenInfrastructure(
        this IServiceCollection services)
    {
        services.AddSingleton<IPasswordHasher, Pbkdf2PasswordHasher>();
        services.AddSingleton<ITokenService, JwtTokenService>();
        return services;
    }
}
