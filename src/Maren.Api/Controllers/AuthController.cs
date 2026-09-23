using FluentValidation;
using Maren.Application.Abstractions;
using Maren.Application.Auth;
using Maren.Contracts;
using Maren.Domain;
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

    /// <summary>A token that authenticated but carries no usable subject claim.</summary>
    /// <remarks>
    /// Should not happen. Returning 401 rather than throwing means a malformed
    /// token produces a sign-in prompt instead of a 500.
    ///
    /// Lives on the base because every <c>/api/v1/me</c> controller needs it,
    /// and a second private copy would be a second chance to return the wrong
    /// status for the same condition.
    /// </remarks>
    protected IActionResult Unauthenticated() =>
        StatusCode(StatusCodes.Status401Unauthorized, ApiResponse<object>.Fail(
            "UNAUTHENTICATED", "Please sign in again."));

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

        /*  422, not 400. The payload was well formed and the date parsed — the
            request is being refused on what it says, not on how it was
            written, and a client that treats 400 as "I sent malformed JSON"
            would report the wrong thing to the wrong person. */
        FailureCodes.UnderMinimumAge => StatusCodes.Status422UnprocessableEntity,

        // A typo, so a plain 400: the value really is unusable.
        FailureCodes.InvalidDateOfBirth => StatusCodes.Status400BadRequest,

        /*  A refusal about what this account is, not about the request or the
            caller's permissions. She is authenticated and allowed to call the
            endpoint; the platform declines to erase this particular account
            through this particular door. */
        FailureCodes.OperatorAccount => StatusCodes.Status409Conflict,

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

        // Refusals about state, not about the request. The caller is
        // authenticated and permitted to call the endpoint; the platform is
        // declining this particular change, and 403 would wrongly suggest they
        // need a different permission.
        AccessFailureCodes.PrivilegeEscalation or
        AccessFailureCodes.SelfDemotion or
        AccessFailureCodes.SystemRole or
        AccessFailureCodes.RoleInUse or
        AccessFailureCodes.LastAdministrator =>
            StatusCodes.Status409Conflict,

        AccessFailureCodes.UnknownPermission or
        AccessFailureCodes.InvalidPayload =>
            StatusCodes.Status400BadRequest,

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

/// <summary>Getting in, and getting out.</summary>
/// <remarks>
/// <para>
/// <c>[AllowAnonymous]</c> is declared per action rather than on the class.
/// It used to sit here, and it silently overrode the <c>[Authorize]</c> on
/// sign-out — an attribute farther away wins, so the one endpoint here that
/// must be authenticated was not. ASP0026 says so at build time and the
/// warning was being missed.
/// </para>
/// <para>
/// Sign-out still answered 401 because the action re-checks the subject claim
/// itself, but that is defence in depth doing the primary job, which is
/// precisely the arrangement that stops holding the first time somebody
/// refactors the handler. Three endpoints genuinely cannot require a token;
/// they say so individually, and anything added to this controller is
/// authenticated unless it opts out in its own right.
/// </para>
/// </remarks>
[Route("api/v1/auth")]
public sealed class AuthController(ISender sender, ICurrentUser currentUser)
    : MarenControllerBase
{
    /// <summary>Creates an account and returns a session.</summary>
    [AllowAnonymous]
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
    [AllowAnonymous]
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
    [AllowAnonymous]
    [HttpPost("refresh")]
    [ProducesResponseType(typeof(ApiResponse<AuthResponse>), 200)]
    [ProducesResponseType(typeof(ApiResponse<AuthResponse>), 401)]
    public Task<IActionResult> Refresh(
        [FromBody] RefreshRequest request,
        [FromServices] IValidator<RefreshCommand> validator,
        CancellationToken ct) =>
        ValidateThen<RefreshCommand, AuthResponse>(
            new RefreshCommand(request), validator, sender, ct);

    /// <summary>Ends this session, or every session.</summary>
    /// <remarks>
    /// <para>
    /// The one authenticated endpoint on this controller, and the reason
    /// <c>[AllowAnonymous]</c> is declared per action rather than on the class
    /// — see the note there. The account being signed out is read from the
    /// access token and never from the body, which is why the body has no user
    /// identifier to send.
    /// </para>
    /// <para>
    /// Succeeds for a token that is unknown, already revoked or already
    /// expired. There is no useful recovery from a failed sign-out, and the
    /// client has discarded the token either way.
    /// </para>
    /// </remarks>
    [HttpPost("logout")]
    [Authorize]
    [ProducesResponseType(typeof(ApiResponse<object>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 401)]
    public async Task<IActionResult> Logout(
        [FromBody] LogoutRequest request,
        [FromServices] IValidator<LogoutCommand> validator,
        CancellationToken ct)
    {
        if (currentUser.UserId is not { } userId) return Unauthenticated();

        var command = new LogoutCommand(userId, request);
        var validation = await validator.ValidateAsync(command, ct);
        if (!validation.IsValid)
        {
            return BadRequest(ApiResponse<object>.Invalid(
                validation.Errors
                    .GroupBy(e => e.PropertyName)
                    .ToDictionary(g => g.Key, g => g.Select(e => e.ErrorMessage).ToArray())));
        }

        return FromResult(await sender.Send(command, ct));
    }
}
