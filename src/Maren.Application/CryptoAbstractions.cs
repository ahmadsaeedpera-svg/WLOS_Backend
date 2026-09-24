using Maren.Contracts;
using Maren.Shared;

namespace Maren.Application.Abstractions;

/// <summary>Credential material for the client-derived login path.</summary>
/// <remarks>
/// The verifier and its salt travel to the application layer so the comparison
/// can be constant-time, exactly as the version 1 path does. A procedure that
/// compared inside the database would have to receive the secret, and would
/// lose the timing property on the way.
/// </remarks>
public sealed record ClientDerivedLoginMaterial(
    Guid UserId,
    byte CredentialVersion,
    byte[]? AuthSecretHash,
    byte[]? AuthSecretSalt,
    int? KdfProfileId,
    bool IsLockedOut,
    DateTime? LockoutEndUtc);

/// <summary>The Argon2id parameters a credential was written with.</summary>
public sealed record StoredKdfProfile(
    int KdfProfileId,
    string Algorithm,
    int MemoryKiB,
    int Iterations,
    int Parallelism,
    int SaltBytes,
    int OutputBytes,
    bool IsProvisional);

public sealed record StoredGeneration(
    Guid GenerationId, int GenerationNumber, string State, DateTime CreatedOn);

public sealed record StoredWrapper(string WrapperKind, Guid? DeviceId, byte[] Envelope);

/// <summary>
/// The key hierarchy and the encrypted records, as this server sees them:
/// ciphertext, public keys, and just enough routing to hand the right bytes
/// back to the right account.
/// </summary>
/// <remarks>
/// Every method here is scoped by user id, and none of them takes a
/// generation from the caller. A client that could name a generation could
/// ask for one belonging to someone else, or write new records under a key
/// that has been retired.
/// </remarks>
public interface ICryptoRepository
{
    Task<StoredKdfProfile?> GetCurrentKdfProfileAsync(CancellationToken ct);

    /// <summary>The salt and parameters for an account, or null if there is none.</summary>
    /// <remarks>
    /// <b>Null must never reach a caller as "no such account".</b> The
    /// application layer substitutes a deterministic decoy, because this is an
    /// unauthenticated lookup by email address and anything that distinguishes
    /// a registered address from an unregistered one is an enumeration oracle.
    /// </remarks>
    Task<(byte[] Salt, StoredKdfProfile Profile)?> GetKdfParametersAsync(
        string email, CancellationToken ct);

    Task<Result<Guid>> RegisterClientDerivedAsync(
        RegisterClientDerivedRequest request, byte[] authSecretVerifier,
        string? ip, CancellationToken ct);

    Task<ClientDerivedLoginMaterial?> GetForLoginAsync(string email, CancellationToken ct);

    Task<StoredGeneration?> GetActiveGenerationAsync(Guid userId, CancellationToken ct);

    Task<IReadOnlyList<StoredWrapper>> GetWrappersAsync(
        Guid userId, Guid generationId, CancellationToken ct);

    Task<Result<int>> SaveRecordAsync(
        Guid userId, SaveRecordRequest request, CancellationToken ct);

    Task<RecordResponse?> GetRecordAsync(Guid userId, Guid recordId, CancellationToken ct);

    Task<IReadOnlyList<RecordResponse>> GetRecordPageAsync(
        Guid userId, string? recordKind, int skip, int take, CancellationToken ct);

    Task<bool> DeleteRecordAsync(Guid userId, Guid recordId, CancellationToken ct);

    /// <summary>Counts and states for an operator. Never content.</summary>
    Task<CryptoAccountSummary?> GetAccountSummaryAsync(Guid userId, CancellationToken ct);

    /// <summary>
    /// The verification material for an account the caller has already
    /// authenticated as, so it can be asked to prove the password again.
    /// </summary>
    /// <remarks>
    /// By user id, never by address. An authenticated endpoint that accepted
    /// an email address to name the account would be offering a second and
    /// weaker way of saying who is being acted on than the token it already
    /// holds. The version 1 path keeps <c>usp_User_GetLoginMaterial</c> for
    /// the same reason.
    /// </remarks>
    Task<ReauthMaterial?> GetReauthMaterialAsync(Guid userId, CancellationToken ct);

    /// <summary>
    /// Replaces the credential and reseals the data key, in one transaction.
    /// </summary>
    /// <remarks>
    /// Both or neither. A new password derives a new key-encryption key, and
    /// the stored wrapper was sealed under the old one; writing the credential
    /// alone would leave an account whose new password signs in and opens
    /// nothing, with the old password already gone.
    /// </remarks>
    Task<bool> ChangePasswordAsync(
        Guid userId, byte[] authSecretVerifier, byte[] authSecretSalt,
        int kdfProfileId, byte[] passwordWrapper, CancellationToken ct);

    /// <summary>New twelve words for the generation she is writing into.</summary>
    /// <remarks>
    /// The old wrapper and the old public key are both replaced, so the
    /// retired phrase stops opening anything and stops proving anything. The
    /// data key itself is untouched — this changes which words open her
    /// journal, not what they open.
    /// </remarks>
    Task<bool> ReplaceRecoveryKeyAsync(
        Guid userId, byte[] recoveryWrapper, byte[] recoveryPublicKey,
        CancellationToken ct);
}

/// <summary>What is needed to re-verify a password for an authenticated caller.</summary>
/// <remarks>
/// No user id: the caller already knows which account it asked about, and
/// carrying one here would invite passing it on to something that should have
/// taken it from the token instead.
/// </remarks>
public sealed record ReauthMaterial(
    byte[] AuthSecretHash, byte[] AuthSecretSalt, int KdfProfileId);

/// <summary>
/// Produces a stable, unpredictable salt for an address that has no account.
/// </summary>
/// <remarks>
/// <para>
/// The KDF parameter lookup is unauthenticated and keyed by email address,
/// which makes it an account enumeration oracle unless every address gets an
/// answer. The answer for an unknown address has to be:
/// </para>
/// <list type="bullet">
/// <item>the same every time — a salt that changed per request would say "no
/// account" as loudly as an error;</item>
/// <item>unpredictable — a salt anybody could compute from the address would
/// be equally distinguishable;</item>
/// <item>indistinguishable in shape from a real one.</item>
/// </list>
/// <para>
/// So it is keyed, and the key lives with the other server secrets rather than
/// in a stored procedure. A secret in a procedure is a secret in source
/// control.
/// </para>
/// </remarks>
public interface IKdfDecoy
{
    byte[] SaltFor(string email, int saltBytes);
}

/// <summary>
/// Turns the authentication secret a device derived into the value this server
/// stores, and compares the two.
/// </summary>
/// <remarks>
/// <para>
/// Salted HMAC-SHA256, and deliberately nothing more. The input is already a
/// 32-byte Argon2id output computed on her phone, so an attacker holding the
/// verifier table still has to run Argon2id once per password guess — a cost
/// that dwarfs anything this side could add.
/// </para>
/// <para>
/// An interface rather than a static call because the comparison is a security
/// decision and the layering rules put it behind an abstraction like every
/// other one. <b>It never sees a password.</b> There is no overload that
/// could.
/// </para>
/// </remarks>
public interface IAuthSecretVerifier
{
    byte[] Compute(byte[] authSecret, byte[] salt);

    /// <summary>Constant-time. A short-circuiting compare leaks how much matched.</summary>
    bool Verify(byte[] authSecret, byte[] salt, byte[] expected);
}

/// <summary>A nonce to sign, issued for any address.</summary>
public sealed record RecoveryChallenge(Guid ChallengeId, byte[] Nonce, DateTime ExpiresOn);

/// <summary>What a spent challenge yields, for checking a signature.</summary>
public sealed record RecoveryAttempt(
    Guid UserId, Guid GenerationId, byte[] Nonce, byte[] PublicKey, int GenerationNumber);

/// <summary>A verified challenge: the wrapped key, and what it belongs to.</summary>
/// <remarks>
/// <see cref="RecoveryWrapper"/> is null when the generation has no recovery
/// wrapper at all. That is not an error to report differently — it is exactly
/// the case the caller discovers by trying to open it, and it ends in the same
/// place as a wrapper that will not decrypt.
/// </remarks>
public sealed record RecoveryGrant(
    Guid UserId, Guid GenerationId, int GenerationNumber, byte[]? RecoveryWrapper);

/// <summary>
/// Path R: getting back in with the recovery phrase.
/// </summary>
/// <remarks>
/// <b>No method here takes a phrase, the entropy behind it, a derived key or a
/// password.</b> What travels is a signature and, at completion, material the
/// device produced. The same is true one layer down, where an assertion scans
/// every procedure in the database by parameter name.
/// </remarks>
public interface IRecoveryRepository
{
    Task<RecoveryChallenge> IssueChallengeAsync(
        string email, byte[] nonce, string? ip, CancellationToken ct);

    /// <summary>
    /// Spends a challenge and returns what is needed to verify a signature.
    /// </summary>
    /// <remarks>
    /// <b>Spent on any attempt, valid or not.</b> The signature has not been
    /// checked when this runs, and a challenge that survived a failure would
    /// let an attacker grind guesses against one nonce.
    /// </remarks>
    Task<RecoveryAttempt?> ConsumeChallengeAsync(Guid challengeId, CancellationToken ct);

    Task<RecoveryGrant?> IssueGrantAsync(
        Guid challengeId, byte[] grantHash, CancellationToken ct);

    Task<bool> CompleteAsync(
        byte[] grantHash, byte[] authSecretVerifier, byte[] authSecretSalt,
        int kdfProfileId, byte[] passwordWrapper, CancellationToken ct);

    /// <summary>Returns the new generation number, or null if refused.</summary>
    Task<int?> CompleteUnrecoverableAsync(
        byte[] grantHash, byte[] authSecretVerifier, byte[] authSecretSalt,
        int kdfProfileId, Guid newGenerationId, byte[] passwordWrapper,
        byte[] recoveryWrapper, byte[] recoveryPublicKey, CancellationToken ct);
}

/// <summary>Verifies an Ed25519 signature, and builds the bytes it covers.</summary>
/// <remarks>
/// Verification only. This platform holds a public key derived from her
/// recovery entropy and nothing else; it cannot sign, and the key that opens
/// her journal comes from the same entropy under a different label.
/// </remarks>
public interface IRecoveryProof
{
    byte[] BuildContext(Guid challengeId, byte[] nonce);

    bool Verify(byte[] publicKey, byte[] context, byte[] signature);
}
