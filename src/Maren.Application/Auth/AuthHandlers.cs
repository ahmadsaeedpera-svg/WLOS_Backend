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
            request.Email, hash, salt, iterations,
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
                plaintext is legitimately in hand. */
            var (hash, salt, iterations) = hasher.Hash(request.Password);
            await repository.RegisterAsync(
                request.Email, hash, salt, iterations, null, "en-GB",
                currentUser.IpAddress, ct);
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
