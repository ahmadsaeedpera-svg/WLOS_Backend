using System.Security.Cryptography;
using System.Text;
using FluentValidation;
using Maren.Application.Abstractions;
using Maren.Contracts;
using Maren.Shared;
using MediatR;

namespace Maren.Application.Crypto;

/*  Path R: getting back in with the recovery phrase.

    One failure code
    ----------------
    Every refusal on this path returns RECOVERY_FAILED. Unknown address,
    unknown challenge, expired challenge, already-spent challenge, bad
    signature, rate-limited account, expired grant -- all of them, identically.

    That is not laziness about error messages. Each of those distinctions is a
    question an attacker would like answered, and several of them ("this
    address has an account", "that phrase was close") are the whole thing this
    path exists to keep private. The woman who is actually locked out is told
    the same sentence whichever it was, and the sentence has to be written for
    her: it says try again and check the words, because those are the two
    things she can do.

    The password never arrives
    --------------------------
    Nothing here takes a phrase, the entropy behind it, or a password. At
    completion what arrives is an authentication secret and a wrapper, both
    produced on her device, and the platform stores a salted HMAC of the first
    and cannot open the second.
*/

/// <summary>The grant token, and the hash the platform actually keeps.</summary>
/// <remarks>
/// Opaque random, hashed at rest, exactly like a refresh token. A grant
/// readable from the table would be a five-minute password reset for anyone
/// who could read the table.
/// </remarks>
internal static class RecoveryGrantToken
{
    internal static (string Token, byte[] Hash) Create()
    {
        var token = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));
        return (token, Hash(token));
    }

    internal static byte[] Hash(string token) =>
        SHA256.HashData(Encoding.UTF8.GetBytes(token));
}

// ---------------------------------------------------------------------------
// R0 — the challenge
// ---------------------------------------------------------------------------

public sealed record RecoveryChallengeCommand(RecoveryChallengeRequest Request)
    : IRequest<Result<RecoveryChallengeResponse>>;

public sealed class RecoveryChallengeValidator
    : AbstractValidator<RecoveryChallengeCommand>
{
    public RecoveryChallengeValidator()
    {
        RuleFor(x => x.Request.Email).NotEmpty().EmailAddress().MaximumLength(256);
    }
}

/// <summary>
/// Issues a nonce for any address, whether or not it has an account.
/// </summary>
/// <remarks>
/// It has to answer for every address: this cannot be authenticated, because
/// the thing she would authenticate with is what she has lost. So the defence
/// against enumeration is that the answer is the same shape, and the same
/// work, either way.
/// </remarks>
public sealed class RecoveryChallengeHandler(
    IRecoveryRepository repository, ICurrentUser currentUser)
    : IRequestHandler<RecoveryChallengeCommand, Result<RecoveryChallengeResponse>>
{
    public async Task<Result<RecoveryChallengeResponse>> Handle(
        RecoveryChallengeCommand command, CancellationToken ct)
    {
        /*  Generated here rather than in the database. T-SQL's random sources
            are not cryptographic, and a predictable nonce would let an
            attacker precompute a signature for a challenge not yet issued. */
        var nonce = RandomNumberGenerator.GetBytes(32);

        var challenge = await repository.IssueChallengeAsync(
            command.Request.Email, nonce, currentUser.IpAddress, ct);

        return Result<RecoveryChallengeResponse>.Success(
            new RecoveryChallengeResponse(
                challenge.ChallengeId, challenge.Nonce, challenge.ExpiresOn));
    }
}

// ---------------------------------------------------------------------------
// R1 — the proof
// ---------------------------------------------------------------------------

public sealed record RecoveryVerifyCommand(RecoveryVerifyRequest Request)
    : IRequest<Result<RecoveryVerifyResponse>>;

public sealed class RecoveryVerifyValidator : AbstractValidator<RecoveryVerifyCommand>
{
    public RecoveryVerifyValidator()
    {
        RuleFor(x => x.Request.ChallengeId).NotEmpty();
        RuleFor(x => x.Request.Signature)
            .NotNull().Must(s => s.Length == 64)
            .WithMessage("That is not a signature.");
    }
}

/// <summary>
/// Checks the signature, and on success releases the wrapper and a grant.
/// </summary>
/// <remarks>
/// <para>
/// The challenge is spent before the signature is checked, which looks like
/// the wrong order and is the right one: a challenge that survived a failed
/// attempt would let an attacker grind guesses against a single nonce.
/// </para>
/// <para>
/// The wrapper comes out here and not a step earlier. It is the target of any
/// offline attack on the phrase, so handing it to whoever knows an email
/// address would be an oracle; handing it to someone who has just proved
/// possession costs nothing, because she can already open it.
/// </para>
/// </remarks>
public sealed class RecoveryVerifyHandler(
    IRecoveryRepository repository, IRecoveryProof proof)
    : IRequestHandler<RecoveryVerifyCommand, Result<RecoveryVerifyResponse>>
{
    public async Task<Result<RecoveryVerifyResponse>> Handle(
        RecoveryVerifyCommand command, CancellationToken ct)
    {
        var attempt = await repository.ConsumeChallengeAsync(
            command.Request.ChallengeId, ct);

        if (attempt is null)
            return Result<RecoveryVerifyResponse>.Failure(FailureCodes.RecoveryFailed);

        var context = proof.BuildContext(command.Request.ChallengeId, attempt.Nonce);

        if (!proof.Verify(attempt.PublicKey, context, command.Request.Signature))
            return Result<RecoveryVerifyResponse>.Failure(FailureCodes.RecoveryFailed);

        var (token, hash) = RecoveryGrantToken.Create();

        var granted = await repository.IssueGrantAsync(
            command.Request.ChallengeId, hash, ct);

        if (granted is null)
            return Result<RecoveryVerifyResponse>.Failure(FailureCodes.RecoveryFailed);

        /*  A missing wrapper is not reported differently. She finds out by
            trying to open it, and a generation with no recovery wrapper ends
            in the same place as one whose wrapper will not decrypt: the
            unrecoverable completion. Telling her earlier would only mean
            telling an attacker earlier too. */
        return Result<RecoveryVerifyResponse>.Success(new RecoveryVerifyResponse(
            token,
            granted.RecoveryWrapper ?? Array.Empty<byte>(),
            granted.GenerationId,
            granted.GenerationNumber,
            DateTime.UtcNow.AddMinutes(5)));
    }
}

// ---------------------------------------------------------------------------
// R2 — the wrapper opened
// ---------------------------------------------------------------------------

public sealed record RecoveryCompleteCommand(RecoveryCompleteRequest Request)
    : IRequest<Result>;

public sealed class RecoveryCompleteValidator : AbstractValidator<RecoveryCompleteCommand>
{
    public RecoveryCompleteValidator()
    {
        RuleFor(x => x.Request.Grant).NotEmpty().MaximumLength(128);

        RuleFor(x => x.Request.AuthSecret)
            .NotNull().Must(b => b.Length == 32)
            .WithMessage("The authentication secret must be 32 bytes.");

        RuleFor(x => x.Request.AuthSecretSalt)
            .NotNull().Must(b => b.Length is >= 16 and <= 32)
            .WithMessage("The salt must be between 16 and 32 bytes.");

        RuleFor(x => x.Request.PasswordWrapper)
            .NotNull().Must(b => b.Length >= 48)
            .WithMessage("That is not a valid envelope.");
    }
}

/// <summary>
/// She opened the wrapper and chose a new password.
/// </summary>
/// <remarks>
/// Her generation does not change and her old journal is still hers: the data
/// key never moved, only the key that wraps it. That is the entire difference
/// between this path and an email reset, and it is why the twelve words are
/// worth writing down.
/// </remarks>
public sealed class RecoveryCompleteHandler(
    IRecoveryRepository repository, IAuthSecretVerifier verifier)
    : IRequestHandler<RecoveryCompleteCommand, Result>
{
    public async Task<Result> Handle(
        RecoveryCompleteCommand command, CancellationToken ct)
    {
        var request = command.Request;

        var done = await repository.CompleteAsync(
            RecoveryGrantToken.Hash(request.Grant),
            verifier.Compute(request.AuthSecret, request.AuthSecretSalt),
            request.AuthSecretSalt,
            request.KdfProfileId,
            request.PasswordWrapper,
            ct);

        return done ? Result.Success() : Result.Failure(FailureCodes.RecoveryFailed);
    }
}

// ---------------------------------------------------------------------------
// R3 — the wrapper did not open
// ---------------------------------------------------------------------------

public sealed record RecoveryCompleteUnrecoverableCommand(
    RecoveryCompleteUnrecoverableRequest Request) : IRequest<Result<int>>;

public sealed class RecoveryCompleteUnrecoverableValidator
    : AbstractValidator<RecoveryCompleteUnrecoverableCommand>
{
    public RecoveryCompleteUnrecoverableValidator()
    {
        RuleFor(x => x.Request.Grant).NotEmpty().MaximumLength(128);
        RuleFor(x => x.Request.NewGenerationId).NotEmpty();

        RuleFor(x => x.Request.AuthSecret)
            .NotNull().Must(b => b.Length == 32);
        RuleFor(x => x.Request.AuthSecretSalt)
            .NotNull().Must(b => b.Length is >= 16 and <= 32);
        RuleFor(x => x.Request.RecoveryPublicKey)
            .NotNull().Must(b => b.Length == 32);
        RuleFor(x => x.Request.PasswordWrapper)
            .NotNull().Must(b => b.Length >= 48);
        RuleFor(x => x.Request.RecoveryWrapper)
            .NotNull().Must(b => b.Length >= 48);
    }
}

/// <summary>
/// The signature verified and the wrapper did not open.
/// </summary>
/// <remarks>
/// <b>Cryptographic data loss for that generation.</b> The entropy was right,
/// so the phrase is hers; the wrapper that held the data key is absent or
/// corrupt and nobody can derive that key again. She gets her account back and
/// a new generation to write into, and her old records stay where they are as
/// ciphertext — a device somewhere may still hold the key, and deleting the
/// only remaining copy of what she wrote because one unwrap failed would be
/// the worst possible response.
/// </remarks>
public sealed class RecoveryCompleteUnrecoverableHandler(
    IRecoveryRepository repository, IAuthSecretVerifier verifier)
    : IRequestHandler<RecoveryCompleteUnrecoverableCommand, Result<int>>
{
    public async Task<Result<int>> Handle(
        RecoveryCompleteUnrecoverableCommand command, CancellationToken ct)
    {
        var request = command.Request;

        var generationNumber = await repository.CompleteUnrecoverableAsync(
            RecoveryGrantToken.Hash(request.Grant),
            verifier.Compute(request.AuthSecret, request.AuthSecretSalt),
            request.AuthSecretSalt,
            request.KdfProfileId,
            request.NewGenerationId,
            request.PasswordWrapper,
            request.RecoveryWrapper,
            request.RecoveryPublicKey,
            ct);

        return generationNumber is { } number
            ? Result<int>.Success(number)
            : Result<int>.Failure(FailureCodes.RecoveryFailed);
    }
}
