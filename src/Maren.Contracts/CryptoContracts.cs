namespace Maren.Contracts;

/*  Contracts for the client-derived credential scheme and encrypted records.

    Binary fields are `byte[]`, which System.Text.Json renders as base64. That
    is deliberate rather than hand-rolled base64 strings: one conversion, done
    by the serialiser, in one direction each way. Hand-encoding would put a
    second place where padding or URL-safe alphabets could differ between the
    client and this server, and the whole point of the canonical encoding work
    is to have no such places.

    Nothing here carries a password. There is no field that could, on any of
    these records, and an assertion over every procedure in the database says
    the same thing one layer down.
*/

/// <summary>
/// What a device needs before it can derive anything.
/// </summary>
/// <remarks>
/// <para>
/// Returned for <b>any</b> address, registered or not. An endpoint that
/// answered only for real accounts would be an account enumeration oracle, and
/// this is necessarily unauthenticated — the caller cannot prove anything yet,
/// because proving anything requires the key these parameters produce.
/// </para>
/// <para>
/// The salt for an unknown address is derived deterministically from the
/// address under a server-held key, so it is stable across calls (a salt that
/// changed per request would be as good as a "no such account" reply) and
/// indistinguishable from a real one.
/// </para>
/// </remarks>
public sealed record KdfParametersResponse(
    // The profile a new credential should be written with. For a known
    // account this is the profile its credential already uses; for an unknown
    // one it is the current profile, which is what a registration would use
    // anyway. Neither answer tells a caller which of the two it got.
    int KdfProfileId,
    string Algorithm,
    int MemoryKiB,
    int Iterations,
    int Parallelism,
    int OutputBytes,
    byte[] Salt);

/// <summary>Register an account whose credential was derived on the device.</summary>
/// <remarks>
/// Everything here was computed on her phone. <b>There is no password field,
/// and there must never be one</b> — the key that opens her journal is derived
/// from the same master secret as <see cref="AuthSecret"/> under a different
/// HKDF label, so a server that saw the password could derive it too.
/// </remarks>
public sealed record RegisterClientDerivedRequest(
    string Email,
    DateOnly DateOfBirth,
    // Chosen by the client, because both wrappers are sealed against it
    // before this request is sent. See usp_User_RegisterClientDerived.
    Guid GenerationId,
    byte[] AuthSecret,
    byte[] AuthSecretSalt,
    int KdfProfileId,
    byte[] PasswordWrapper,
    byte[] RecoveryWrapper,
    byte[] RecoveryPublicKey,
    string? CountryIso,
    string? LanguageCode);

/// <summary>Sign in with a secret derived on the device.</summary>
public sealed record LoginClientDerivedRequest(string Email, byte[] AuthSecret);

/// <summary>One wrapped copy of a data key.</summary>
/// <remarks>
/// The server stores these and cannot open any of them. Handing one back to
/// the account it belongs to gives away nothing it did not already hold.
/// </remarks>
public sealed record WrapperResponse(string Kind, Guid? DeviceId, byte[] Envelope);

/// <summary>The generation new records are written under, and how to open it.</summary>
public sealed record GenerationResponse(
    Guid GenerationId,
    int GenerationNumber,
    string State,
    IReadOnlyList<WrapperResponse> Wrappers);

/// <summary>Write an encrypted record.</summary>
/// <remarks>
/// <para>
/// <see cref="Version"/> is supplied by the client because the envelope was
/// sealed with it bound into the associated data. The client therefore has to
/// know which version it is writing <i>before</i> it seals, and the server
/// accepts the write only if that version is exactly one past what it holds.
/// The concurrency check and the cryptographic binding are the same check.
/// </para>
/// <para>
/// There is no generation field. The server resolves the active generation
/// itself — a client that could name one could write into a retired key.
/// </para>
/// </remarks>
public sealed record SaveRecordRequest(
    Guid RecordId,
    string RecordKind,
    int SchemaVersion,
    int Version,
    byte[] Envelope);

public sealed record SaveRecordResponse(Guid RecordId, int Version);

/// <summary>An encrypted record, exactly as it was stored.</summary>
/// <remarks>
/// <see cref="Envelope"/> is ciphertext. This server has never seen its
/// contents and cannot; the timestamps and the kind are what it routes on.
/// </remarks>
public sealed record RecordResponse(
    Guid RecordId,
    string RecordKind,
    int SchemaVersion,
    int Version,
    byte[] Envelope,
    int GenerationNumber,
    DateTime CreatedOn,
    DateTime ModifiedOn);

/// <summary>
/// What an operator may see about a woman's encrypted records: that they
/// exist, and nothing else.
/// </summary>
/// <remarks>
/// Deliberately counts and states. No kinds broken down by day, no sizes, no
/// timestamps of individual records — a shape that starts as "how much is
/// there" and grows into a behavioural profile is the thing to refuse at the
/// contract, not later in a screen.
/// </remarks>
public sealed record CryptoAccountSummary(
    Guid UserId,
    string? Email,
    int GenerationCount,
    int ActiveGenerationNumber,
    int RecordCount,
    bool HasRecoveryWrapper,
    DateTime? FirstRecordOn,
    DateTime? LastRecordOn);

/*  Path R — getting back in with the recovery phrase.

    Three steps, and the order is the security:

      challenge  a nonce, issued for any address in constant time
      verify     a signature over it; on success, the wrapper and a grant
      complete   the new credential, and the wrapper resealed under it

    **Nothing here carries the phrase, the entropy behind it, or a password.**
    There is no field that could, on any of these records.
*/

/// <summary>Ask for something to sign. Answered for any address.</summary>
public sealed record RecoveryChallengeRequest(string Email);

/// <summary>
/// The nonce to sign, and how long it lives.
/// </summary>
/// <remarks>
/// Returned for an address with no account too, with the same shape and the
/// same timing. A challenge that came back only for real accounts would answer
/// the question this endpoint must not answer, and it cannot be authenticated
/// — she has nothing to authenticate with, which is why she is here.
/// </remarks>
public sealed record RecoveryChallengeResponse(
    Guid ChallengeId, byte[] Nonce, DateTime ExpiresOn);

/// <summary>The proof.</summary>
/// <remarks>
/// An Ed25519 signature over
/// <c>"WLOS/v1/recovery-reset" ‖ challengeId ‖ nonce</c>, made with a key
/// derived from her recovery entropy under its own HKDF label. The platform
/// holds the public half and nothing else.
/// </remarks>
public sealed record RecoveryVerifyRequest(Guid ChallengeId, byte[] Signature);

/// <summary>
/// The wrapped data key, and a grant that can complete one reset.
/// </summary>
/// <remarks>
/// The wrapper is released here and not a step earlier. It is the target of
/// any offline attack on the phrase, so handing it to whoever knows an email
/// address would be an oracle; handing it to someone who has just proved
/// possession costs nothing, because she can already open it.
/// </remarks>
public sealed record RecoveryVerifyResponse(
    string Grant,
    byte[] RecoveryWrapper,
    Guid GenerationId,
    int GenerationNumber,
    DateTime GrantExpiresOn);

/// <summary>The wrapper opened. A new password, and the key resealed under it.</summary>
/// <remarks>
/// Her generation does not change and her old journal is still hers — the data
/// key never moved, only the key that wraps it. That is the whole difference
/// between this path and an email reset.
/// </remarks>
public sealed record RecoveryCompleteRequest(
    string Grant,
    byte[] AuthSecret,
    byte[] AuthSecretSalt,
    int KdfProfileId,
    byte[] PasswordWrapper);

/// <summary>The wrapper did not open. She gets the account and a new key.</summary>
/// <remarks>
/// <b>This is cryptographic data loss for that generation</b>, and the name
/// says so rather than calling it degraded. The signature verified, so the
/// phrase is hers; the wrapper that held the data key is gone or corrupt, and
/// nobody can derive that key again. Her old records are kept as ciphertext —
/// a device somewhere may still hold the key, and deleting the only remaining
/// copy of what she wrote on the strength of one failed unwrap would be the
/// worst possible answer to it.
/// </remarks>
public sealed record RecoveryCompleteUnrecoverableRequest(
    string Grant,
    byte[] AuthSecret,
    byte[] AuthSecretSalt,
    int KdfProfileId,
    Guid NewGenerationId,
    byte[] PasswordWrapper,
    byte[] RecoveryWrapper,
    byte[] RecoveryPublicKey);
