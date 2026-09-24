using FluentValidation;
using Maren.Application.Abstractions;
using Maren.Contracts;
using Maren.Shared;
using MediatR;

namespace Maren.Application.Auth;

// ---------------------------------------------------------------------------
// Register
// ---------------------------------------------------------------------------

public sealed record RegisterCommand(RegisterRequest Request)
    : IRequest<Result<AuthResponse>>;

public sealed class RegisterValidator : AbstractValidator<RegisterCommand>
{
    public RegisterValidator()
    {
        RuleFor(x => x.Request.Email)
            .NotEmpty().EmailAddress().MaximumLength(256);

        /*  Length only, no composition rules.
            Forced symbol-and-digit rules push people toward predictable
            substitutions and a written-down password; length is the property
            that actually resists guessing. */
        RuleFor(x => x.Request.Password)
            .NotEmpty()
            .MinimumLength(10)
            .WithMessage("Use at least 10 characters. A short phrase works well.")
            .MaximumLength(256);

        RuleFor(x => x.Request.CountryIso)
            .Length(2).When(x => !string.IsNullOrEmpty(x.Request.CountryIso));

        /*  Shape only, not the gate.

            This catches a date nobody could have meant — next year, or the
            nineteenth century — so the caller gets a specific message instead
            of a generic refusal. The launch age itself is checked in
            Identity.usp_User_Register and nowhere else that matters: a rule
            enforced in a validator is a rule that an import job, an admin
            script or a future service does not have to obey. */
        RuleFor(x => x.Request.DateOfBirth)
            .NotEqual(default(DateOnly))
            .WithMessage("Your date of birth is needed to continue.")
            .Must(d => d <= DateOnly.FromDateTime(DateTime.UtcNow))
            .WithMessage("That date is in the future.")
            .Must(d => d >= DateOnly.FromDateTime(DateTime.UtcNow.AddYears(-120)))
            .WithMessage("Please check that date.");
    }
}

public sealed class RegisterHandler(
    IAuthRepository repository,
    IPasswordHasher hasher,
    ITokenService tokens,
    ICurrentUser currentUser)
    : IRequestHandler<RegisterCommand, Result<AuthResponse>>
{
    public async Task<Result<AuthResponse>> Handle(
        RegisterCommand command, CancellationToken ct)
    {
        var request = command.Request;
        var (hash, salt, iterations) = hasher.Hash(request.Password);

        var created = await repository.RegisterAsync(
            request.Email, hash, salt, iterations, request.DateOfBirth,
            request.CountryIso, request.LanguageCode ?? "en-GB",
            currentUser.IpAddress, ct);

        if (!created.Succeeded)
            return Result<AuthResponse>.Failure(created.FailureCode!);

        var userId = created.Value;
        var permissions = await repository.GetPermissionsAsync(userId, ct);
        return await IssueAsync(repository, tokens, currentUser, userId,
            permissions, null, ct);
    }

    internal static async Task<Result<AuthResponse>> IssueAsync(
        IAuthRepository repository,
        ITokenService tokens,
        ICurrentUser currentUser,
        Guid userId,
        IReadOnlyList<string> permissions,
        Guid? deviceId,
        CancellationToken ct)
    {
        var stamp = await repository.GetSecurityStampAsync(userId, ct);
        var access = tokens.CreateAccessToken(userId, permissions, stamp);
        var refresh = tokens.CreateRefreshToken();

        await repository.IssueRefreshTokenAsync(
            userId, deviceId, refresh.Hash, refresh.ExpiresUtc,
            currentUser.IpAddress, ct);

        return Result<AuthResponse>.Success(new AuthResponse(
            userId, access.Token, access.ExpiresUtc,
            refresh.Token, refresh.ExpiresUtc, permissions));
    }
}

// ---------------------------------------------------------------------------
// Login
// ---------------------------------------------------------------------------

public sealed record LoginCommand(LoginRequest Request)
    : IRequest<Result<AuthResponse>>;

public sealed class LoginValidator : AbstractValidator<LoginCommand>
{
    public LoginValidator()
    {
        RuleFor(x => x.Request.Email).NotEmpty().MaximumLength(256);
        RuleFor(x => x.Request.Password).NotEmpty().MaximumLength(256);
        RuleFor(x => x.Request.Device!.Platform)
            .Must(p => p is "android" or "ios" or "web")
            .When(x => x.Request.Device is not null)
            .WithMessage("Platform must be android, ios or web.");
    }
}

public sealed class LoginHandler(
    IAuthRepository repository,
    IPasswordHasher hasher,
    ITokenService tokens,
    ICurrentUser currentUser)
    : IRequestHandler<LoginCommand, Result<AuthResponse>>
{
    public async Task<Result<AuthResponse>> Handle(
        LoginCommand command, CancellationToken ct)
    {
        var request = command.Request;
        var material = await repository.GetForLoginAsync(request.Email, ct);

        /*  An unknown account still costs a hash computation before the same
            failure comes back. Returning early would make "no such user"
            measurably faster than "wrong password", which is a timing oracle
            for whether an address is registered. */
        if (material is null)
        {
            hasher.Hash(request.Password);
            return Result<AuthResponse>.Failure(FailureCodes.InvalidCredentials);
        }

        if (material.IsLockedOut &&
            material.LockoutEndUtc is { } until && until > DateTime.UtcNow)
        {
            return Result<AuthResponse>.Failure(FailureCodes.AccountLocked);
        }

        if (material.PasswordHash is null || material.PasswordSalt is null ||
            material.PasswordIterations is null)
        {
            return Result<AuthResponse>.Failure(FailureCodes.InvalidCredentials);
        }

        var (verified, needsRehash) = hasher.Verify(
            request.Password, material.PasswordHash, material.PasswordSalt,
            material.PasswordIterations.Value);

        await repository.RecordLoginAsync(
            material.UserId, verified, currentUser.IpAddress, ct);

        if (!verified)
            return Result<AuthResponse>.Failure(FailureCodes.InvalidCredentials);

        if (needsRehash)
        {
            /*  Upgrading the stored cost happens on the one occasion the
                plaintext is legitimately in hand.

                This called RegisterAsync until now, which found the address
                already registered, returned EMAIL_IN_USE and changed nothing —
                so no stored hash has ever actually been upgraded, and every
                account predating the last iteration increase is still at the
                old work factor. SetPasswordAsync writes the material and
                leaves the security stamp alone, because the same password at
                a higher cost is not a credential change and must not sign her
                out mid-login. */
            var (hash, salt, iterations) = hasher.Hash(request.Password);
            await repository.SetPasswordAsync(
                material.UserId, hash, salt, iterations, ct);
        }

        if (request.Device is { } device)
        {
            await repository.RegisterDeviceAsync(
                device.DeviceId, material.UserId, device.Platform,
                device.OsVersion, device.AppVersion, device.Model,
                device.FcmToken, ct);
        }

        var permissions = await repository.GetPermissionsAsync(material.UserId, ct);
        return await RegisterHandler.IssueAsync(
            repository, tokens, currentUser, material.UserId, permissions,
            request.Device?.DeviceId, ct);
    }
}

// ---------------------------------------------------------------------------
// Refresh
// ---------------------------------------------------------------------------

public sealed record RefreshCommand(RefreshRequest Request)
    : IRequest<Result<AuthResponse>>;

public sealed class RefreshValidator : AbstractValidator<RefreshCommand>
{
    public RefreshValidator() =>
        RuleFor(x => x.Request.RefreshToken).NotEmpty().MaximumLength(512);
}

public sealed class RefreshHandler(
    IAuthRepository repository,
    ITokenService tokens,
    ICurrentUser currentUser)
    : IRequestHandler<RefreshCommand, Result<AuthResponse>>
{
    public async Task<Result<AuthResponse>> Handle(
        RefreshCommand command, CancellationToken ct)
    {
        var currentHash = tokens.HashRefreshToken(command.Request.RefreshToken);
        var replacement = tokens.CreateRefreshToken();

        var redeemed = await repository.RedeemRefreshTokenAsync(
            currentHash, replacement.Hash, replacement.ExpiresUtc,
            currentUser.IpAddress, ct);

        if (!redeemed.Succeeded)
            return Result<AuthResponse>.Failure(redeemed.FailureCode!);

        var userId = redeemed.Value;
        var permissions = await repository.GetPermissionsAsync(userId, ct);
        var stamp = await repository.GetSecurityStampAsync(userId, ct);
        var access = tokens.CreateAccessToken(userId, permissions, stamp);

        return Result<AuthResponse>.Success(new AuthResponse(
            userId, access.Token, access.ExpiresUtc,
            replacement.Token, replacement.ExpiresUtc, permissions));
    }
}

// ---------------------------------------------------------------------------
// Logout
// ---------------------------------------------------------------------------

/// <param name="UserId">
/// From the access token, resolved in the controller. Never from the request
/// body: a logout that trusted a client-supplied identifier would be a way to
/// sign any account out by guessing a GUID.
/// </param>
public sealed record LogoutCommand(Guid UserId, LogoutRequest Request)
    : IRequest<Result>;

public sealed class LogoutValidator : AbstractValidator<LogoutCommand>
{
    public LogoutValidator() =>
        RuleFor(x => x.Request.RefreshToken)
            .MaximumLength(512)
            .When(x => x.Request.RefreshToken is not null);
}

/// <summary>Ends this session, or every session.</summary>
/// <remarks>
/// Succeeds for a token that is unknown, already revoked or already expired.
/// There is no useful recovery from a failed sign-out — the client has
/// discarded the token either way — and an error here would strand someone on
/// a screen whose only purpose is to let them leave. The one refusal is a
/// token belonging to somebody else, which the procedure reports because the
/// only ways to reach it are a client bug and an attempt.
/// </remarks>
public sealed class LogoutHandler(
    IAuthRepository repository,
    ITokenService tokens,
    ICurrentUser currentUser)
    : IRequestHandler<LogoutCommand, Result>
{
    public async Task<Result> Handle(LogoutCommand command, CancellationToken ct)
    {
        var hash = string.IsNullOrEmpty(command.Request.RefreshToken)
            ? null
            : tokens.HashRefreshToken(command.Request.RefreshToken);

        /*  Nothing to revoke and not asked to clear everything. The access
            token still has its remaining minutes to run either way — that is
            what a short expiry is for — so this is not a silent failure. */
        if (hash is null && !command.Request.AllDevices)
            return Result.Success();

        return await repository.RevokeRefreshTokenAsync(
            command.UserId, hash, command.Request.AllDevices,
            currentUser.IpAddress, ct);
    }
}

// ---------------------------------------------------------------------------
// Delete account
// ---------------------------------------------------------------------------

/// <param name="UserId">From the access token. See <see cref="LogoutCommand"/>.</param>
public sealed record DeleteAccountCommand(Guid UserId, DeleteAccountRequest Request)
    : IRequest<Result>;

public sealed class DeleteAccountValidator : AbstractValidator<DeleteAccountCommand>
{
    /*  One or the other, not both and not neither. Which one is right depends
        on the account, and the validator cannot see the account -- so it only
        checks that something arrived to confirm with, and the handler decides
        whether it is the kind this account accepts. */
    public DeleteAccountValidator()
    {
        RuleFor(x => x.Request)
            .Must(r => !string.IsNullOrEmpty(r.Password) || r.AuthSecret is not null)
            .WithMessage("Your password is needed to confirm this.");

        RuleFor(x => x.Request.Password)
            .MaximumLength(256)
            .When(x => !string.IsNullOrEmpty(x.Request.Password));

        RuleFor(x => x.Request.AuthSecret!)
            .Must(b => b.Length == 32)
            .WithMessage("The authentication secret must be 32 bytes.")
            .When(x => x.Request.AuthSecret is not null);
    }
}

/// <summary>Erases the account and everything behind it.</summary>
/// <remarks>
/// <para>
/// The password is re-verified here rather than taken on trust from a valid
/// access token. A token proves the session was hers when it started; it does
/// not prove she is the one holding the phone now, and this is the one action
/// with no undo behind it.
/// </para>
/// <para>
/// Re-reading the login material by <em>email</em> would mean the handler
/// needed an address it has no business asking a client for. It reads by user
/// id instead, so the only thing crossing the boundary is the confirmation
/// she has just produced.
/// </para>
/// <para>
/// <b>Two credential schemes, and the account decides which one applies.</b>
/// A client-derived account holds no server-side password at all, so this
/// handler used to refuse every one of them: "deletion means deletion" was
/// true for version 1 accounts and quietly false for encrypted ones. The
/// client-derived branch is tried first because it is the scheme an account
/// is migrated <em>to</em> — an account that has both has moved on from the
/// version 1 material, which <c>usp_UserCredential_SetAuthoritative</c>
/// deliberately leaves in place.
/// </para>
/// </remarks>
public sealed class DeleteAccountHandler(
    IAuthRepository repository,
    ICryptoRepository cryptoRepository,
    IAuthSecretVerifier authSecretVerifier,
    IPasswordHasher hasher)
    : IRequestHandler<DeleteAccountCommand, Result>
{
    public async Task<Result> Handle(
        DeleteAccountCommand command, CancellationToken ct)
    {
        var confirmed = await ConfirmAsync(command, ct);

        if (!confirmed)
            return Result.Failure(FailureCodes.InvalidCredentials);

        return await repository.DeleteAccountAsync(command.UserId, ct);
    }

    private async Task<bool> ConfirmAsync(
        DeleteAccountCommand command, CancellationToken ct)
    {
        var clientDerived = await cryptoRepository.GetReauthMaterialAsync(
            command.UserId, ct);

        if (clientDerived is not null)
        {
            /*  Her account is on the client-derived scheme, so a password is
                not something this server can check and must not be accepted
                as if it were. Sending one here is a client that has not
                noticed the account was migrated. */
            return command.Request.AuthSecret is { } secret
                && authSecretVerifier.Verify(
                    secret, clientDerived.AuthSecretSalt, clientDerived.AuthSecretHash);
        }

        if (command.Request.Password is not { Length: > 0 } password)
            return false;

        var material = await repository.GetLoginMaterialAsync(command.UserId, ct);

        if (material?.PasswordHash is null || material.PasswordSalt is null ||
            material.PasswordIterations is null)
        {
            return false;
        }

        var (verified, _) = hasher.Verify(
            password, material.PasswordHash,
            material.PasswordSalt, material.PasswordIterations.Value);

        return verified;
    }
}
