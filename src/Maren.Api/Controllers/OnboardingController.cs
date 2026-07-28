using Maren.Application.Abstractions;
using Maren.Application.Onboarding;
using Maren.Application.Wlos;
using Maren.Contracts;
using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Maren.Api.Controllers;

/// <summary>
/// Adaptive onboarding: what the platform offers, and what she tells it.
/// </summary>
/// <remarks>
/// <para>
/// The whole platform adapts to a woman's life stage and roles, and this is the
/// only way it learns either. Until these endpoints existed the schema could
/// describe who she is and no client could ask.
/// </para>
/// <para>
/// Every route here acts on the caller and takes the user id from the token,
/// never from the body or the route. That is the security decision in this
/// file: an endpoint that accepted a user id would let any signed-in account
/// rewrite anyone's profile and life history, and no permission check would
/// catch it because a woman editing her own profile is not an administrative
/// action.
/// </para>
/// <para>
/// No <c>IRequirePermission</c> for the same reason. Permissions govern
/// operators acting on the platform; these are a woman acting on herself, and
/// authentication is the whole boundary.
/// </para>
/// </remarks>
[ApiController]
[Route("api/v1/me")]
[Authorize]
public sealed class OnboardingController(ISender sender, ICurrentUser currentUser)
    : MarenControllerBase
{
    /// <summary>The life stages, roles and domains onboarding can offer.</summary>
    /// <remarks>
    /// Server-driven so wording, translations and new stages ship without a
    /// store release. Cached for ten minutes — it is read by every new account
    /// and changes monthly at most.
    /// </remarks>
    [HttpGet("onboarding/options")]
    [ProducesResponseType(typeof(ApiResponse<OnboardingOptionsResponse>), 200)]
    public async Task<IActionResult> Options(CancellationToken ct)
        => FromResult(await sender.Send(new GetOnboardingOptionsQuery(), ct));

    /// <summary>Her profile, current life stage and roles.</summary>
    [HttpGet("profile")]
    [ProducesResponseType(typeof(ApiResponse<ProfileDto>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 404)]
    public async Task<IActionResult> GetProfile(CancellationToken ct)
    {
        if (currentUser.UserId is not { } userId) return Unauthenticated();
        return FromResult(await sender.Send(new GetMyProfileQuery(userId), ct));
    }

    /// <summary>Updates the details she controls.</summary>
    /// <remarks>
    /// Omitted fields are left alone rather than cleared, so onboarding can
    /// save each answer as she gives it without discarding the previous ones.
    /// </remarks>
    [HttpPut("profile")]
    [ProducesResponseType(typeof(ApiResponse<object>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 400)]
    public async Task<IActionResult> SaveProfile(
        [FromBody] SaveProfileRequest request, CancellationToken ct)
    {
        if (currentUser.UserId is not { } userId) return Unauthenticated();
        return FromResult(await sender.Send(new SaveMyProfileCommand(userId, request), ct));
    }

    /// <summary>Moves her to a life stage, keeping the previous one in her history.</summary>
    /// <remarks>
    /// Setting the stage she is already in succeeds and changes nothing, so a
    /// client may retry and onboarding may be re-run without littering her
    /// journey with one-day entries.
    /// </remarks>
    [HttpPut("life-stage")]
    [ProducesResponseType(typeof(ApiResponse<object>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 400)]
    public async Task<IActionResult> SetLifeStage(
        [FromBody] SetLifeStageRequest request, CancellationToken ct)
    {
        if (currentUser.UserId is not { } userId) return Unauthenticated();
        return FromResult(await sender.Send(new SetMyLifeStageCommand(userId, request), ct));
    }

    /// <summary>Replaces her roles with the given set. An empty list clears them.</summary>
    [HttpPut("role-modes")]
    [ProducesResponseType(typeof(ApiResponse<object>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 400)]
    public async Task<IActionResult> SetRoleModes(
        [FromBody] SetRoleModesRequest request, CancellationToken ct)
    {
        if (currentUser.UserId is not { } userId) return Unauthenticated();
        return FromResult(await sender.Send(new SetMyRoleModesCommand(userId, request), ct));
    }

    /// <summary>Every stage she has been through, newest first.</summary>
    [HttpGet("life-stage/history")]
    [ProducesResponseType(typeof(ApiResponse<IReadOnlyList<LifeStageHistoryEntry>>), 200)]
    public async Task<IActionResult> LifeStageHistory(CancellationToken ct)
    {
        if (currentUser.UserId is not { } userId) return Unauthenticated();
        return FromResult(await sender.Send(new GetMyLifeStageHistoryQuery(userId), ct));
    }

    /// <summary>What the platform thinks she should see right now.</summary>
    /// <remarks>
    /// <para>
    /// The one question every surface asks. A dashboard, a widget, a
    /// notification scheduler and eventually an AI companion all call this and
    /// render what comes back; none of them decides anything, because a client
    /// that decided would be a second copy of rules that live in the database.
    /// </para>
    /// <para>
    /// Every decision carries its reason, evidence, confidence and source, and
    /// the response includes the engine trace — including stages whose engines
    /// do not exist yet, which report themselves rather than returning silence
    /// that could be mistaken for a considered answer.
    /// </para>
    /// </remarks>
    [HttpGet("today")]
    [ProducesResponseType(typeof(ApiResponse<LifeOsResponse>), 200)]
    public async Task<IActionResult> Today(CancellationToken ct)
    {
        if (currentUser.UserId is not { } userId) return Unauthenticated();
        return FromResult(await sender.Send(new ResolveLifeOsQuery(userId), ct));
    }

    /*  A token that passed authentication but carries no usable subject claim.
        Should not happen, and returning 401 rather than throwing means a
        malformed token produces a sign-in prompt instead of a 500. */
    private IActionResult Unauthenticated() =>
        StatusCode(401, ApiResponse<object>.Fail(
            "UNAUTHENTICATED", "Please sign in again."));
}
