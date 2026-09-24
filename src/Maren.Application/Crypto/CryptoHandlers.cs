using FluentValidation;
using Maren.Application.Abstractions;
using Maren.Application.Auth;
using Maren.Application.Behaviors;
using Maren.Contracts;
using Maren.Shared;
using MediatR;

namespace Maren.Application.Crypto;

/*  The client-derived credential path, and encrypted records.

    Two rules run through every handler here:

      * **The password never arrives.** No request in this file has a field
        that could carry one, and no handler could do anything with it. What
        arrives is an authentication secret her device derived, which is a
        different HKDF output from the key that opens her journal.

      * **The caller never names a generation, a user or a record it does not
        own.** Every authenticated handler takes the subject from the token,
        never from the request body, and the procedures beneath scope every
        read and write by it again.
*/

// ---------------------------------------------------------------------------
// Key derivation parameters
// ---------------------------------------------------------------------------

public sealed record GetKdfParametersQuery(string Email)
    : IRequest<Result<KdfParametersResponse>>;

public sealed class GetKdfParametersValidator : AbstractValidator<GetKdfParametersQuery>
{
    public GetKdfParametersValidator()
    {
        RuleFor(x => x.Email).NotEmpty().EmailAddress().MaximumLength(256);
    }
}

/// <summary>
/// Answers for every address, registered or not.
/// </summary>
/// <remarks>
/// <para>
/// This has to be unauthenticated — a device cannot prove anything before it
/// has derived a key, and it cannot derive a key without these parameters. So
/// the only defence against it becoming an account enumeration oracle is that
/// the answer is the same shape either way.
/// </para>
/// <para>
/// An unregistered address gets a salt derived from the address under a
/// server-held key: stable across calls, unpredictable without the key, and
/// the right length. The current profile supplies the cost parameters, so a
/// decoy is indistinguishable from a real answer for an account registered
/// under the current profile.
/// </para>
/// <para>
/// <b>What this does not hide.</b> An address registered under an older
/// profile returns that older profile's parameters, which differ from the
/// decoy's. That is a genuine residual leak and it is recorded rather than
/// papered over: it appears only after a parameter change, it says nothing
/// about who she is, and closing it would mean lying about the cost her own
/// credential was written with, which would lock her out.
/// </para>
/// </remarks>
public sealed class GetKdfParametersHandler(
    ICryptoRepository repository, IKdfDecoy decoy)
    : IRequestHandler<GetKdfParametersQuery, Result<KdfParametersResponse>>
{
    public async Task<Result<KdfParametersResponse>> Handle(
        GetKdfParametersQuery query, CancellationToken ct)
    {
        var known = await repository.GetKdfParametersAsync(query.Email, ct);
        if (known is { } real)
        {
            return Result<KdfParametersResponse>.Success(new KdfParametersResponse(
                real.Profile.KdfProfileId,
                real.Profile.Algorithm, real.Profile.MemoryKiB, real.Profile.Iterations,
                real.Profile.Parallelism, real.Profile.OutputBytes, real.Salt));
        }

        var current = await repository.GetCurrentKdfProfileAsync(ct);
        if (current is null)
            return Result<KdfParametersResponse>.Failure(FailureCodes.NotFound);

        return Result<KdfParametersResponse>.Success(new KdfParametersResponse(
            current.KdfProfileId,
            current.Algorithm, current.MemoryKiB, current.Iterations,
            current.Parallelism, current.OutputBytes,
            decoy.SaltFor(query.Email, current.SaltBytes)));
    }
}

// ---------------------------------------------------------------------------
// Registration
// ---------------------------------------------------------------------------

public sealed record RegisterClientDerivedCommand(RegisterClientDerivedRequest Request)
    : IRequest<Result<AuthResponse>>;

public sealed class RegisterClientDerivedValidator
    : AbstractValidator<RegisterClientDerivedCommand>
{
    public RegisterClientDerivedValidator()
    {
        RuleFor(x => x.Request.Email).NotEmpty().EmailAddress().MaximumLength(256);

        /*  Lengths, not contents. Everything here is opaque to this server, so
            the only thing it can honestly check is that a field is the size
            the protocol says. A wrong-sized key is a client bug worth a clear
            message; a wrong-valued one is undetectable here by design. */
        RuleFor(x => x.Request.AuthSecret)
            .NotNull().Must(b => b.Length == 32)
            .WithMessage("The authentication secret must be 32 bytes.");

        RuleFor(x => x.Request.AuthSecretSalt)
            .NotNull().Must(b => b.Length is >= 16 and <= 32)
            .WithMessage("The salt must be between 16 and 32 bytes.");

        RuleFor(x => x.Request.RecoveryPublicKey)
            .NotNull().Must(b => b.Length == 32)
            .WithMessage("The recovery public key must be 32 bytes.");

        /*  48 is the envelope floor: a 32-byte header and a 16-byte tag before
            any ciphertext. The database enforces the same number, which is
            where it actually matters. */
        RuleFor(x => x.Request.PasswordWrapper)
            .NotNull().Must(b => b.Length >= 48)
            .WithMessage("The password wrapper is not a valid envelope.");

        RuleFor(x => x.Request.RecoveryWrapper)
            .NotNull().Must(b => b.Length >= 48)
            .WithMessage("The recovery wrapper is not a valid envelope.");

        RuleFor(x => x.Request.CountryIso)
            .Length(2).When(x => !string.IsNullOrEmpty(x.Request.CountryIso));

        /*  Shape only, never the gate. The launch age is checked in the
            database, on the same side of the boundary as the insert, because
            a rule enforced in a validator is a rule an import job does not
            have to obey. */
        RuleFor(x => x.Request.DateOfBirth)
            .NotEqual(default(DateOnly))
            .WithMessage("Your date of birth is needed to continue.")
            .Must(d => d <= DateOnly.FromDateTime(DateTime.UtcNow))
            .WithMessage("That date is in the future.")
            .Must(d => d >= DateOnly.FromDateTime(DateTime.UtcNow.AddYears(-120)))
            .WithMessage("Please check that date.");
    }
}

public sealed class RegisterClientDerivedHandler(
    ICryptoRepository repository,
    IAuthRepository authRepository,
    IAuthSecretVerifier verifier,
    ITokenService tokens,
    ICurrentUser currentUser)
    : IRequestHandler<RegisterClientDerivedCommand, Result<AuthResponse>>
{
    public async Task<Result<AuthResponse>> Handle(
        RegisterClientDerivedCommand command, CancellationToken ct)
    {
        var request = command.Request;

        /*  The stored verifier, not the secret. What she sent is already a
            32-byte Argon2id-derived value; this keys an HMAC with the salt she
            also sent, so the row never holds the thing that authenticates. */
        var stored = verifier.Compute(request.AuthSecret, request.AuthSecretSalt);

        var created = await repository.RegisterClientDerivedAsync(
            request, stored, currentUser.IpAddress, ct);

        if (!created.Succeeded)
            return Result<AuthResponse>.Failure(created.FailureCode!);

        var permissions = await authRepository.GetPermissionsAsync(created.Value, ct);
        return await RegisterHandler.IssueAsync(
            authRepository, tokens, currentUser, created.Value, permissions, null, ct);
    }
}

// ---------------------------------------------------------------------------
// Sign in
// ---------------------------------------------------------------------------

public sealed record LoginClientDerivedCommand(LoginClientDerivedRequest Request)
    : IRequest<Result<AuthResponse>>;

public sealed class LoginClientDerivedValidator
    : AbstractValidator<LoginClientDerivedCommand>
{
    public LoginClientDerivedValidator()
    {
        RuleFor(x => x.Request.Email).NotEmpty().EmailAddress().MaximumLength(256);
        RuleFor(x => x.Request.AuthSecret)
            .NotNull().Must(b => b.Length == 32)
            .WithMessage("The authentication secret must be 32 bytes.");
    }
}

public sealed class LoginClientDerivedHandler(
    ICryptoRepository repository,
    IAuthRepository authRepository,
    IAuthSecretVerifier verifier,
    ITokenService tokens,
    ICurrentUser currentUser)
    : IRequestHandler<LoginClientDerivedCommand, Result<AuthResponse>>
{
    public async Task<Result<AuthResponse>> Handle(
        LoginClientDerivedCommand command, CancellationToken ct)
    {
        var request = command.Request;
        var material = await repository.GetForLoginAsync(request.Email, ct);

        /*  An unknown address, and an address that exists but is still on the
            version 1 credential, both do the verification work anyway before
            returning the same failure. Returning early would make those cases
            measurably faster than a wrong secret, which is a timing oracle for
            whether an address is registered and for which scheme it uses. */
        if (material is null || material.CredentialVersion != 2 ||
            material.AuthSecretHash is null || material.AuthSecretSalt is null)
        {
            verifier.Compute(request.AuthSecret, new byte[32]);
            return Result<AuthResponse>.Failure(FailureCodes.InvalidCredentials);
        }

        if (material.IsLockedOut &&
            material.LockoutEndUtc is { } until && until > DateTime.UtcNow)
        {
            return Result<AuthResponse>.Failure(FailureCodes.AccountLocked);
        }

        var verified = verifier.Verify(
            request.AuthSecret, material.AuthSecretSalt, material.AuthSecretHash);

        await authRepository.RecordLoginAsync(
            material.UserId, verified, currentUser.IpAddress, ct);

        if (!verified)
            return Result<AuthResponse>.Failure(FailureCodes.InvalidCredentials);

        var permissions = await authRepository.GetPermissionsAsync(material.UserId, ct);
        return await RegisterHandler.IssueAsync(
            authRepository, tokens, currentUser, material.UserId, permissions, null, ct);
    }
}

// ---------------------------------------------------------------------------
// The key hierarchy she signs in to
// ---------------------------------------------------------------------------

public sealed record GetActiveGenerationQuery : IRequest<Result<GenerationResponse>>;

/// <summary>
/// The generation her records are written under, with the wrapped keys that
/// open it.
/// </summary>
/// <remarks>
/// Handing back her own wrappers gives away nothing: they are ciphertext under
/// keys this server has never held. The subject comes from the token, so there
/// is no parameter that could name someone else's.
/// </remarks>
public sealed class GetActiveGenerationHandler(
    ICryptoRepository repository, ICurrentUser currentUser)
    : IRequestHandler<GetActiveGenerationQuery, Result<GenerationResponse>>
{
    public async Task<Result<GenerationResponse>> Handle(
        GetActiveGenerationQuery query, CancellationToken ct)
    {
        if (currentUser.UserId is not { } userId)
            return Result<GenerationResponse>.Failure(FailureCodes.Forbidden);

        var generation = await repository.GetActiveGenerationAsync(userId, ct);
        if (generation is null)
            return Result<GenerationResponse>.Failure(FailureCodes.NotFound);

        var wrappers = await repository.GetWrappersAsync(
            userId, generation.GenerationId, ct);

        return Result<GenerationResponse>.Success(new GenerationResponse(
            generation.GenerationId, generation.GenerationNumber, generation.State,
            wrappers.Select(w => new WrapperResponse(w.WrapperKind, w.DeviceId, w.Envelope))
                    .ToList()));
    }
}

// ---------------------------------------------------------------------------
// Records
// ---------------------------------------------------------------------------

public sealed record SaveRecordCommand(SaveRecordRequest Request)
    : IRequest<Result<SaveRecordResponse>>;

public sealed class SaveRecordValidator : AbstractValidator<SaveRecordCommand>
{
    /// <summary>65,484 — the capacity of the largest envelope v1 carries.</summary>
    /// <remarks>
    /// The envelope is 64 KiB; the payload inside it is that minus 48 bytes of
    /// header and tag and 4 bytes of length prefix. Calling the limit 64 KiB
    /// would be wrong by 52 bytes. v1 does not chunk, and attachments are a
    /// separate capability that does not exist yet.
    /// </remarks>
    public const int MaxEnvelopeBytes = 65536;

    public SaveRecordValidator()
    {
        RuleFor(x => x.Request.RecordId).NotEmpty();

        RuleFor(x => x.Request.RecordKind)
            .NotEmpty().MaximumLength(32)
            .Matches("^[a-z][a-z0-9.]*$")
            .WithMessage("A record kind is lower-case and dotted, such as journal.entry.");

        RuleFor(x => x.Request.SchemaVersion).GreaterThan(0);
        RuleFor(x => x.Request.Version).GreaterThan(0);

        RuleFor(x => x.Request.Envelope)
            .NotNull()
            .Must(b => b.Length >= 48)
            .WithMessage("That is not a valid envelope.")
            .Must(b => b.Length <= MaxEnvelopeBytes)
            .WithMessage("That entry is too long to save.");
    }
}

public sealed class SaveRecordHandler(
    ICryptoRepository repository, ICurrentUser currentUser)
    : IRequestHandler<SaveRecordCommand, Result<SaveRecordResponse>>
{
    public async Task<Result<SaveRecordResponse>> Handle(
        SaveRecordCommand command, CancellationToken ct)
    {
        if (currentUser.UserId is not { } userId)
            return Result<SaveRecordResponse>.Failure(FailureCodes.Forbidden);

        var saved = await repository.SaveRecordAsync(userId, command.Request, ct);

        return saved.Succeeded
            ? Result<SaveRecordResponse>.Success(
                new SaveRecordResponse(command.Request.RecordId, saved.Value))
            : Result<SaveRecordResponse>.Failure(saved.FailureCode!);
    }
}

public sealed record GetRecordQuery(Guid RecordId) : IRequest<Result<RecordResponse>>;

public sealed class GetRecordHandler(
    ICryptoRepository repository, ICurrentUser currentUser)
    : IRequestHandler<GetRecordQuery, Result<RecordResponse>>
{
    public async Task<Result<RecordResponse>> Handle(
        GetRecordQuery query, CancellationToken ct)
    {
        if (currentUser.UserId is not { } userId)
            return Result<RecordResponse>.Failure(FailureCodes.Forbidden);

        var record = await repository.GetRecordAsync(userId, query.RecordId, ct);

        /*  Not-found and not-yours are the same answer. Distinguishing them
            would confirm that a record id exists, and there is no legitimate
            way for a caller to have guessed one. */
        return record is null
            ? Result<RecordResponse>.Failure(FailureCodes.NotFound)
            : Result<RecordResponse>.Success(record);
    }
}

public sealed record GetRecordsQuery(string? RecordKind, int Skip, int Take)
    : IRequest<Result<IReadOnlyList<RecordResponse>>>;

public sealed class GetRecordsValidator : AbstractValidator<GetRecordsQuery>
{
    public GetRecordsValidator()
    {
        RuleFor(x => x.Skip).GreaterThanOrEqualTo(0);

        // Bounded here and again in the procedure. An unbounded page over a
        // table of encrypted blobs is a denial-of-service vector, and also the
        // easiest way to pull an entire journal across a wire by accident.
        RuleFor(x => x.Take).InclusiveBetween(1, 200);
    }
}

public sealed class GetRecordsHandler(
    ICryptoRepository repository, ICurrentUser currentUser)
    : IRequestHandler<GetRecordsQuery, Result<IReadOnlyList<RecordResponse>>>
{
    public async Task<Result<IReadOnlyList<RecordResponse>>> Handle(
        GetRecordsQuery query, CancellationToken ct)
    {
        if (currentUser.UserId is not { } userId)
            return Result<IReadOnlyList<RecordResponse>>.Failure(FailureCodes.Forbidden);

        var records = await repository.GetRecordPageAsync(
            userId, query.RecordKind, query.Skip, query.Take, ct);

        return Result<IReadOnlyList<RecordResponse>>.Success(records);
    }
}

public sealed record DeleteRecordCommand(Guid RecordId) : IRequest<Result>;

public sealed class DeleteRecordHandler(
    ICryptoRepository repository, ICurrentUser currentUser)
    : IRequestHandler<DeleteRecordCommand, Result>
{
    public async Task<Result> Handle(DeleteRecordCommand command, CancellationToken ct)
    {
        if (currentUser.UserId is not { } userId)
            return Result.Failure(FailureCodes.Forbidden);

        var deleted = await repository.DeleteRecordAsync(userId, command.RecordId, ct);

        return deleted ? Result.Success() : Result.Failure(FailureCodes.NotFound);
    }
}

// ---------------------------------------------------------------------------
// What an operator may see
// ---------------------------------------------------------------------------

public sealed record GetCryptoAccountSummaryQuery(Guid UserId)
    : IRequest<Result<CryptoAccountSummary>>, IRequirePermission
{
    /// <remarks>
    /// Reuses <c>users.read</c> rather than inventing a permission. This is
    /// account state — how many generations, how many records — and an
    /// operator who may read an account may see that it has records. A new
    /// code would have to mean something the existing one does not, and this
    /// does not.
    /// </remarks>
    public string Permission => PlatformPermissions.UsersRead;
}

public sealed class GetCryptoAccountSummaryHandler(ICryptoRepository repository)
    : IRequestHandler<GetCryptoAccountSummaryQuery, Result<CryptoAccountSummary>>
{
    public async Task<Result<CryptoAccountSummary>> Handle(
        GetCryptoAccountSummaryQuery query, CancellationToken ct)
    {
        var summary = await repository.GetAccountSummaryAsync(query.UserId, ct);

        return summary is null
            ? Result<CryptoAccountSummary>.Failure(FailureCodes.NotFound)
            : Result<CryptoAccountSummary>.Success(summary);
    }
}
