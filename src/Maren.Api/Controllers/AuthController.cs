using FluentValidation;
using Maren.Application.Auth;
using Maren.Contracts;
using Maren.Shared;
using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Maren.Api.Controllers;

/// <summary>
/// Base for controllers that translate a <see cref="Result{T}"/> into HTTP.
/// </summary>
/// <remarks>
/// The mapping lives here so a failure code cannot come back as 200 in one
/// controller and 400 in another. The client switches on the failure code, but
/// the status code still has to be honest for proxies, logs and anything else
/// that only reads the envelope.
/// </remarks>
[ApiController]
public abstract class MarenControllerBase : ControllerBase
{
    protected IActionResult FromResult<T>(Result<T> result) =>
        result.Succeeded
            ? Ok(ApiResponse<T>.Ok(result.Value!))
            : StatusCode(StatusFor(result.FailureCode),
                ApiResponse<T>.Fail(result.FailureCode!, result.Message));

    /// <summary>
    /// For commands that carry no payload.
    /// </summary>
    /// <remarks>
    /// Still returns the envelope with a null body rather than a bare 204, so
    /// a client has one response shape to parse across every endpoint.
    /// </remarks>
    protected IActionResult FromResult(Result result) =>
        result.Succeeded
            ? Ok(ApiResponse<object>.Ok(new { }))
            : StatusCode(StatusFor(result.FailureCode),
                ApiResponse<object>.Fail(result.FailureCode!, result.Message));

    private static int StatusFor(string? code) => code switch
    {
        FailureCodes.InvalidCredentials => StatusCodes.Status401Unauthorized,
        FailureCodes.AccountLocked => StatusCodes.Status423Locked,
        FailureCodes.UnknownToken or
        FailureCodes.TokenExpired or
        FailureCodes.TokenReused => StatusCodes.Status401Unauthorized,
        FailureCodes.Forbidden => StatusCodes.Status403Forbidden,
        FailureCodes.NotFound => StatusCodes.Status404NotFound,
        FailureCodes.EmailInUse => StatusCodes.Status409Conflict,

        // A stale edit and a duplicate key are both conflicts, not bad
        // requests: the payload was well formed and the caller can retry after
        // refetching. A 400 would tell a client to stop rather than reload.
        ContentFailureCodes.VersionConflict or
        ContentFailureCodes.DuplicateKey => StatusCodes.Status409Conflict,

        // Refusing to publish something unapproved is a rule about state, not
        // about the request.
        ContentFailureCodes.NotApproved => StatusCodes.Status409Conflict,

        ContentFailureCodes.NoVersion => StatusCodes.Status404NotFound,

        // Transient. 503 with a Retry-After is what a client should back off
        // on; 500 invites a bug report instead of a retry.
        ContentFailureCodes.Deadlock or
        ContentFailureCodes.Timeout => StatusCodes.Status503ServiceUnavailable,

        ContentFailureCodes.StorageFailure =>
            StatusCodes.Status500InternalServerError,

        _ => StatusCodes.Status400BadRequest
    };

    protected async Task<IActionResult> ValidateThen<TCommand, TData>(
        TCommand command,
        IValidator<TCommand> validator,
        ISender sender,
        CancellationToken ct)
    {
        var validation = await validator.ValidateAsync(command, ct);
        if (!validation.IsValid)
        {
            var errors = validation.Errors
                .GroupBy(e => e.PropertyName)
                .ToDictionary(g => g.Key, g => g.Select(e => e.ErrorMessage).ToArray());
            return BadRequest(ApiResponse<TData>.Invalid(errors));
        }

        var result = await sender.Send(command!, ct);
        return FromResult((Result<TData>)result!);
    }
}

[Route("api/v1/auth")]
[AllowAnonymous]
public sealed class AuthController(ISender sender) : MarenControllerBase
{
    /// <summary>Creates an account and returns a session.</summary>
    [HttpPost("register")]
    [ProducesResponseType(typeof(ApiResponse<AuthResponse>), 200)]
    [ProducesResponseType(typeof(ApiResponse<AuthResponse>), 409)]
    public Task<IActionResult> Register(
        [FromBody] RegisterRequest request,
        [FromServices] IValidator<RegisterCommand> validator,
        CancellationToken ct) =>
        ValidateThen<RegisterCommand, AuthResponse>(
            new RegisterCommand(request), validator, sender, ct);

    /// <summary>Exchanges credentials for a session.</summary>
    [HttpPost("login")]
    [ProducesResponseType(typeof(ApiResponse<AuthResponse>), 200)]
    [ProducesResponseType(typeof(ApiResponse<AuthResponse>), 401)]
    public Task<IActionResult> Login(
        [FromBody] LoginRequest request,
        [FromServices] IValidator<LoginCommand> validator,
        CancellationToken ct) =>
        ValidateThen<LoginCommand, AuthResponse>(
            new LoginCommand(request), validator, sender, ct);

    /// <summary>Rotates a refresh token for a new session.</summary>
    [HttpPost("refresh")]
    [ProducesResponseType(typeof(ApiResponse<AuthResponse>), 200)]
    [ProducesResponseType(typeof(ApiResponse<AuthResponse>), 401)]
    public Task<IActionResult> Refresh(
        [FromBody] RefreshRequest request,
        [FromServices] IValidator<RefreshCommand> validator,
        CancellationToken ct) =>
        ValidateThen<RefreshCommand, AuthResponse>(
            new RefreshCommand(request), validator, sender, ct);
}
