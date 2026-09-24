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
}

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
