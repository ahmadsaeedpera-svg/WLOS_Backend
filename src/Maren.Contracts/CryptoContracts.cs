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
