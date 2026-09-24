using System.Security.Cryptography;
using System.Text;
using Maren.Application.Abstractions;
using Microsoft.Extensions.Options;

namespace Maren.Infrastructure;

/// <summary>
/// A stable, unpredictable salt for an address that has no account.
/// </summary>
/// <remarks>
/// <para>
/// Before a device can derive anything it has to ask this server for a salt,
/// by email address, without having authenticated — it cannot authenticate
/// yet, because authenticating requires the key that salt produces. So the
/// endpoint answers for every address, and the answer for an address with no
/// account has to be indistinguishable from the answer for one that has.
/// </para>
/// <para>
/// Keyed HMAC gives all three properties at once: stable across calls,
/// unpredictable without the key, and the right shape. Hashing the address
/// alone would fail the second — anyone could compute it and compare.
/// </para>
/// <para>
/// <b>What this does not do.</b> It hides which addresses are registered from
/// someone probing this endpoint. It does not hide registration from someone
/// who can attempt a sign-in and watch what comes back, which is a separate
/// surface with its own rate limiting and its own generic failures. A decoy
/// salt is a narrow fix for a narrow leak, and claiming more of it would be
/// wrong.
/// </para>
/// </remarks>
public sealed class HmacKdfDecoy : IKdfDecoy
{
    private readonly byte[] _key;

    public HmacKdfDecoy(IOptions<JwtOptions> options)
    {
        /*  Derived from the signing key rather than being the signing key.

            One secret doing two jobs is how a compromise in one place becomes
            a compromise in another, and it costs one HKDF call to avoid.
            The label is what separates them, exactly as it does everywhere
            else in this protocol. */
        _key = HKDF.DeriveKey(
            HashAlgorithmName.SHA256,
            Encoding.UTF8.GetBytes(options.Value.SigningKey),
            outputLength: 32,
            salt: Array.Empty<byte>(),
            info: Encoding.UTF8.GetBytes("WLOS/v1/kdf-decoy"));
    }

    public byte[] SaltFor(string email, int saltBytes)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(saltBytes, 1);

        /*  Normalised the same way the lookup normalises, so that
            "Ada@Example.com" and "ada@example.com" get the same decoy. If they
            did not, asking twice with different capitalisation would reveal
            that no real salt was being returned. */
        var normalised = email.Trim().ToUpperInvariant();

        var mac = HMACSHA256.HashData(_key, Encoding.UTF8.GetBytes(normalised));

        if (saltBytes <= mac.Length)
            return mac[..saltBytes];

        /*  Longer salts than one HMAC block, should a profile ever ask for
            one. Expanded rather than repeated, so the extra bytes are not a
            copy of the first. */
        return HKDF.Expand(HashAlgorithmName.SHA256, mac, saltBytes,
            info: Encoding.UTF8.GetBytes("WLOS/v1/kdf-decoy/expand"));
    }
}

/// <summary>
/// The injectable face of <see cref="AuthSecretVerifier"/>.
/// </summary>
/// <remarks>
/// The algorithm lives in a static class so the cross-language vector test can
/// call it without a container; this adapter is what the handlers depend on,
/// because a security comparison belongs behind an abstraction like every
/// other one. Both are the same three lines of HMAC.
/// </remarks>
public sealed class HmacAuthSecretVerifier : IAuthSecretVerifier
{
    public byte[] Compute(byte[] authSecret, byte[] salt)
        => AuthSecretVerifier.Compute(authSecret, salt);

    public bool Verify(byte[] authSecret, byte[] salt, byte[] expected)
        => AuthSecretVerifier.Verify(authSecret, salt, expected);
}
