using Maren.Application.Abstractions;
using Maren.Application.Behaviour;
using Maren.Contracts;
using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Maren.Api.Controllers;

/// <summary>
/// Behaviour Intelligence: what the platform has observed about how she lives.
/// </summary>
/// <remarks>
/// <para>
/// Her own behaviour, on her own account. The user id comes from the token and
/// never from the route, so there is no shape of request that reads somebody
/// else's — the same boundary the rest of <c>/api/v1/me</c> holds.
/// </para>
/// <para>
/// Every number returned here originates in <c>Behaviour.fn_Observe</c> and is
/// derived from her timeline alone. Nothing is assumed, defaulted or inferred
/// from who she is, and a measure with too little history behind it is absent
/// rather than reported as zero.
/// </para>
/// </remarks>
[ApiController]
[Route("api/v1/me")]
[Authorize]
public sealed class BehaviourController(ISender sender, ICurrentUser currentUser)
    : MarenControllerBase
{
    /// <summary>Everything observed about how she lives, as of a day.</summary>
    /// <remarks>
    /// Reads the last snapshot rather than recomputing. Resolution happens once
    /// per request inside the intelligence pipeline; a read that resolved would
    /// observe the same woman again on every screen that asked.
    /// </remarks>
    [HttpGet("behaviour")]
    [ProducesResponseType(typeof(ApiResponse<BehaviourProfile>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 401)]
    public async Task<IActionResult> GetBehaviour(
        [FromQuery] DateOnly? asOfDate, CancellationToken ct)
    {
        if (currentUser.UserId is not { } userId) return Unauthenticated();

        return FromResult(await sender.Send(
            new GetMyBehaviourQuery(userId, asOfDate), ct));
    }

    /// <summary>One measure over time.</summary>
    /// <remarks>
    /// Each point carries the engine version that produced it, so a change in
    /// the line can be told apart from a change in the definition. Without
    /// that, a coach saying "you have improved since March" cannot be trusted.
    /// </remarks>
    [HttpGet("behaviour/{subjectKey}/{measureCode}/history")]
    [ProducesResponseType(typeof(ApiResponse<IReadOnlyList<BehaviourHistoryPoint>>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 400)]
    [ProducesResponseType(typeof(ApiResponse<object>), 401)]
    public async Task<IActionResult> GetBehaviourHistory(
        string subjectKey, string measureCode,
        [FromQuery] int days, CancellationToken ct)
    {
        if (currentUser.UserId is not { } userId) return Unauthenticated();

        return FromResult(await sender.Send(
            new GetMyBehaviourHistoryQuery(
                userId, subjectKey, measureCode, days == 0 ? 30 : days), ct));
    }
}

/// <summary>The behaviour catalogue, for operators.</summary>
/// <remarks>
/// Configuration, not anybody's data: which timeline events compose which
/// behaviour, and how many parts make a day count. No woman's observations are
/// reachable through this controller.
/// </remarks>
[ApiController]
[Route("api/v1/admin/behaviour")]
[Authorize]
public sealed class BehaviourAdminController(ISender sender) : MarenControllerBase
{
    /// <summary>What the platform is configured to observe.</summary>
    [HttpGet("subjects")]
    [ProducesResponseType(typeof(ApiResponse<IReadOnlyList<BehaviourSubject>>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 403)]
    public async Task<IActionResult> ListSubjects(CancellationToken ct)
        => FromResult(await sender.Send(new ListBehaviourSubjectsQuery(), ct));
}
