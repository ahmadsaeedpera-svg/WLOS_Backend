using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FluentAssertions;
using Maren.Infrastructure;

namespace Maren.Tests;

/// <summary>
/// The .NET half of the cross-language crypto vectors.
/// </summary>
/// <remarks>
/// <para>
/// The Flutter client generates <c>wlos_crypto_vectors.json</c> and verifies
/// it too. This file reads the identical bytes and reproduces the surfaces
/// where both sides participate.
/// </para>
/// <para>
/// <b>Why this exists at all.</b> Two implementations passing their own tests
/// can agree with themselves and disagree with each other, indefinitely,
/// without anything going red. The failures that produces are the expensive
/// ones — a GUID byte order, an HKDF label, an integer width — and they
/// surface at account recovery, when a woman is already locked out. These are
/// the only tests in the repository that can catch them.
/// </para>
/// <para>
/// Argon2id and the record envelope are deliberately not reproduced here. The
/// server never runs Argon2id and never opens an envelope, so a .NET
/// implementation of either would exist only to be tested — and would be
/// production code carrying keys it must never handle. Those vectors are
/// pinned on the client side, where they are used.
/// </para>
/// </remarks>
public sealed class CryptoVectorTests
{
    /// <summary>
    /// Both repositories assert this digest. A copy edited on one side fails
    /// there; a deliberate regeneration changes it in both, visibly, in review.
    /// </summary>
    private const string ExpectedDigest =
        "695a38564b795f76b05019b55d18433042da2f6f6b1b57e0d43f9987dffb4dd4";

    private static readonly JsonDocument Vectors = Load();

    private static JsonDocument Load()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "wlos_crypto_vectors.json");
        var raw = File.ReadAllText(path);

        var digest = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(raw)));
        digest.Should().Be(ExpectedDigest,
            "the vector file changed. If that was deliberate, regenerate it, " +
            "update the digest in BOTH repositories, and expect review to ask " +
            "which keys and records it invalidates");

        return JsonDocument.Parse(raw);
    }

    private static JsonElement Section(string name) => Vectors.RootElement.GetProperty(name);

    private static byte[] Unhex(string hex) => Convert.FromHexString(hex);

    private static string Hex(byte[] bytes) => Convert.ToHexStringLower(bytes);

    [Fact]
    public void Guid_bytes_are_rfc4122_order_not_dotnet_mixed_endian()
    {
        var vector = Section("canonicalEncoding").GetProperty("uuid");
        var value = Guid.Parse(vector.GetProperty("input").GetString()!);

        Hex(WlosCanonicalBytes.Uuid(value))
            .Should().Be(vector.GetProperty("expected").GetString());

        /*  The mistake this is really guarding. Guid.ToByteArray() with no
            argument writes the first three fields little-endian, so it
            disagrees with the client on the first four bytes of every
            identifier — and every signature over an identifier. Asserting the
            wrong answer is wrong makes the trap visible to whoever reads this
            next. */
        Hex(value.ToByteArray())
            .Should().NotBe(vector.GetProperty("expected").GetString(),
                "the no-argument overload is mixed-endian and must never be used here");
    }

    [Fact]
    public void Integers_are_fixed_width_big_endian()
    {
        foreach (var c in Section("canonicalEncoding").GetProperty("uint16").EnumerateArray())
        {
            Hex(WlosCanonicalBytes.UInt16BigEndian(c.GetProperty("input").GetInt32()))
                .Should().Be(c.GetProperty("expected").GetString());
        }

        foreach (var c in Section("canonicalEncoding").GetProperty("uint32").EnumerateArray())
        {
            Hex(WlosCanonicalBytes.UInt32BigEndian(c.GetProperty("input").GetInt64()))
                .Should().Be(c.GetProperty("expected").GetString());
        }
    }

    [Fact]
    public void Labels_are_utf8()
    {
        var vector = Section("canonicalEncoding").GetProperty("label");
        Hex(WlosCanonicalBytes.Label(vector.GetProperty("input").GetString()!))
            .Should().Be(vector.GetProperty("expected").GetString());
    }

    [Fact]
    public void Hkdf_reproduces_every_key_the_client_derived()
    {
        /*  .NET's built-in HKDF and the client's must agree exactly. If they
            did not, auth_secret computed on her device would not match what
            this server expects, and nobody could sign in at all — which is at
            least a loud failure. The quiet one is the pair below. */
        AssertDerivations(Section("hkdfSha256").GetProperty("fromMaster"));
        AssertDerivations(Section("hkdfSha256").GetProperty("fromRecoveryEntropy"));

        static void AssertDerivations(JsonElement group)
        {
            var ikm = Unhex(group.GetProperty("ikmHex").GetString()!);

            foreach (var d in group.GetProperty("derivations").EnumerateArray())
            {
                var label = d.GetProperty("label").GetString()!;
                var derived = HKDF.DeriveKey(
                    HashAlgorithmName.SHA256,
                    ikm,
                    outputLength: 32,
                    salt: Array.Empty<byte>(),
                    info: WlosCanonicalBytes.Label(label));

                Hex(derived).Should().Be(d.GetProperty("expected").GetString(),
                    $"HKDF under '{label}' must match the client byte for byte");
            }
        }
    }

    [Fact]
    public void Auth_secret_and_journal_key_are_never_the_same_value()
    {
        /*  The one assertion this whole architecture rests on, asserted from
            the server side as well as the client side.

            auth_secret is what this server stores a verifier for.
            KEK_password is what opens her journal. They are different HKDF
            outputs of one master, separated only by an info string. If those
            labels were ever made equal — a copy-paste, a tidy-up of the
            constants — this server would be holding the key to every journal
            it stores, and nothing else here would notice.

            It is asserted on both sides deliberately: a client-only test would
            still pass if someone "fixed" the server to expect the other
            value. */
        var derivations = Section("hkdfSha256")
            .GetProperty("fromMaster")
            .GetProperty("derivations")
            .EnumerateArray()
            .ToDictionary(
                d => d.GetProperty("label").GetString()!,
                d => d.GetProperty("expected").GetString()!);

        derivations.Should().ContainKey(WlosKdfLabels.Auth);
        derivations.Should().ContainKey(WlosKdfLabels.KekPassword);

        derivations[WlosKdfLabels.Auth]
            .Should().NotBe(derivations[WlosKdfLabels.KekPassword],
                "if these ever matched, the server would hold the key to her journal");
    }

    [Fact]
    public void Auth_secret_verifier_matches_what_the_client_expects()
    {
        var vector = Section("authSecretVerifier");
        var salt = Unhex(vector.GetProperty("saltHex").GetString()!);
        var authSecret = Unhex(vector.GetProperty("authSecretHex").GetString()!);

        Hex(AuthSecretVerifier.Compute(authSecret, salt))
            .Should().Be(vector.GetProperty("expectedHex").GetString());

        AuthSecretVerifier
            .Verify(authSecret, salt, Unhex(vector.GetProperty("expectedHex").GetString()!))
            .Should().BeTrue();
    }

    [Fact]
    public void Auth_secret_verifier_rejects_a_wrong_secret()
    {
        var vector = Section("authSecretVerifier");
        var salt = Unhex(vector.GetProperty("saltHex").GetString()!);
        var authSecret = Unhex(vector.GetProperty("authSecretHex").GetString()!);
        var expected = Unhex(vector.GetProperty("expectedHex").GetString()!);

        var tampered = (byte[])authSecret.Clone();
        tampered[0] ^= 0x01;

        AuthSecretVerifier.Verify(tampered, salt, expected).Should().BeFalse();
    }

    [Fact]
    public void A_signature_made_by_the_client_verifies_here()
    {
        /*  The client signed this with a key derived from recovery entropy.
            This is the whole recovery proof-of-possession in miniature: she
            proves she holds the phrase, and the server learns nothing that
            opens anything. */
        var vector = Section("ed25519");

        RecoverySignatureVerifier.Verify(
                Unhex(vector.GetProperty("publicKeyHex").GetString()!),
                Unhex(vector.GetProperty("messageHex").GetString()!),
                Unhex(vector.GetProperty("signatureHex").GetString()!))
            .Should().BeTrue("Dart signed it and .NET must accept it");
    }

    [Fact]
    public void A_tampered_signature_does_not_verify()
    {
        var vector = Section("ed25519");
        var signature = Unhex(vector.GetProperty("signatureHex").GetString()!);
        signature[0] ^= 0x01;

        RecoverySignatureVerifier.Verify(
                Unhex(vector.GetProperty("publicKeyHex").GetString()!),
                Unhex(vector.GetProperty("messageHex").GetString()!),
                signature)
            .Should().BeFalse();
    }

    [Fact]
    public void A_signature_over_a_different_message_does_not_verify()
    {
        var vector = Section("ed25519");

        RecoverySignatureVerifier.Verify(
                Unhex(vector.GetProperty("publicKeyHex").GetString()!),
                Encoding.UTF8.GetBytes("WLOS/v1/vector/other"),
                Unhex(vector.GetProperty("signatureHex").GetString()!))
            .Should().BeFalse();
    }

    [Theory]
    [InlineData(31)]
    [InlineData(33)]
    public void A_malformed_public_key_is_refused_rather_than_throwing(int length)
    {
        var vector = Section("ed25519");

        RecoverySignatureVerifier.Verify(
                new byte[length],
                Unhex(vector.GetProperty("messageHex").GetString()!),
                Unhex(vector.GetProperty("signatureHex").GetString()!))
            .Should().BeFalse("every failure on the reset path is one generic no");
    }

    [Fact]
    public void The_recovery_context_reproduces_and_its_signature_verifies()
    {
        /*  Path R, and the moment it matters: she is locked out, she has
            twelve words, and this is the byte string her device signs. This
            server builds the identical bytes to check it. A one-byte
            disagreement fails at exactly the point she has nothing else. */
        var vector = Section("recoveryContext");

        var context = WlosRecoveryContext.Build(
            Guid.Parse(vector.GetProperty("challengeId").GetString()!),
            Unhex(vector.GetProperty("nonceHex").GetString()!));

        Hex(context).Should().Be(vector.GetProperty("expectedContextHex").GetString(),
            "the client built these bytes and this server must build the same ones");

        RecoverySignatureVerifier.Verify(
                Unhex(vector.GetProperty("publicKeyHex").GetString()!),
                context,
                Unhex(vector.GetProperty("signatureHex").GetString()!))
            .Should().BeTrue("Dart signed it and .NET must accept it");
    }

    [Fact]
    public void A_recovery_signature_does_not_verify_over_a_different_challenge()
    {
        /*  The binding that makes the challenge single-use mean something. A
            captured signature must not be replayable against the next
            challenge the platform issues. */
        var vector = Section("recoveryContext");

        var otherContext = WlosRecoveryContext.Build(
            Guid.NewGuid(),
            Unhex(vector.GetProperty("nonceHex").GetString()!));

        RecoverySignatureVerifier.Verify(
                Unhex(vector.GetProperty("publicKeyHex").GetString()!),
                otherContext,
                Unhex(vector.GetProperty("signatureHex").GetString()!))
            .Should().BeFalse();
    }
}
