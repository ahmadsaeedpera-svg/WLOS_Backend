using Maren.Application.Abstractions;
using Maren.Application.Recommend;
using Maren.Contracts;
using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Maren.Api.Controllers;

/// <summary>
/// What the platform is suggesting to her, and why each thing.
/// </summary>
/// <remarks>
/// <para>
/// Every recommendation is assembled from observations she logged. None is
/// inferred, so each one carries the sentences of the observations that
/// produced it — "why am I being told this" resolves to her own timeline
/// rather than to a description of an algorithm.
/// </para>
/// <para>
/// There is deliberately no accept or dismiss endpoint. What she does about a
/// suggestion is a timeline event like everything else the platform observes,
/// and a separate acceptance store would be a second record of her behaviour
/// that Behaviour Intelligence could not see.
/// </para>
/// </remarks>
[ApiController]
[Route("api/v1/me/recommendations")]
[Authorize]
public sealed class RecommendationController(ISender sender, ICurrentUser currentUser)
    : MarenControllerBase
{
    /// <summary>Today's suggestions, highest priority first.</summary>
    /// <remarks>
    /// Expired ones are excluded on read as well as at assembly, so a client
    /// that opened the app at 23:58 and again at 00:02 is not shown a
    /// suggestion about yesterday evening.
    /// </remarks>
    [HttpGet]
    [ProducesResponseType(typeof(ApiResponse<IReadOnlyList<Recommendation>>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 401)]
    public async Task<IActionResult> GetMyRecommendations(
        [FromQuery] DateOnly? asOfDate, CancellationToken ct)
    {
        if (currentUser.UserId is not { } userId) return Unauthenticated();

        return FromResult(await sender.Send(
            new GetMyRecommendationsQuery(userId, asOfDate), ct));
    }
}

/// <summary>The recommendation catalogue and its simulator, for operators.</summary>
/// <remarks>
/// Configuration, not anybody's data. The simulator takes evidence an operator
/// described and never a user id — a SQL assertion fails if any inspector
/// procedure gains one.
/// </remarks>
[ApiController]
[Route("api/v1/admin/recommendations")]
[Authorize]
public sealed class RecommendationAdminController(ISender sender) : MarenControllerBase
{
    /// <summary>Every recommendation, with what it is assembled from.</summary>
    /// <remarks>
    /// Carries the required-input count, because a recommendation with none
    /// fires the moment any optional input matches — almost never what somebody
    /// meant, and invisible without the number.
    /// </remarks>
    [HttpGet]
    [ProducesResponseType(typeof(ApiResponse<IReadOnlyList<RecommendationSummary>>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 403)]
    public async Task<IActionResult> List(CancellationToken ct)
        => FromResult(await sender.Send(new ListRecommendationsQuery(), ct));

    /// <summary>What the platform would suggest, given evidence you describe.</summary>
    /// <remarks>
    /// <para>
    /// Evidence uses a shorthand an operator can type:
    /// <c>behaviour:hydration.consistency=40, signal:low_hydration</c>. It runs
    /// the same assembly as the live path, because there is only one copy of it.
    /// </para>
    /// <para>
    /// Returns every configured input alongside what assembled, matched or not.
    /// A list of only what fired explains a recommendation's presence and never
    /// its absence, and absence is what an operator is usually investigating.
    /// </para>
    /// </remarks>
    [HttpPost("simulate")]
    [ProducesResponseType(typeof(ApiResponse<SimulateRecommendationsResponse>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 400)]
    [ProducesResponseType(typeof(ApiResponse<object>), 403)]
    public async Task<IActionResult> Simulate(
        [FromBody] SimulateRecommendationsRequest request, CancellationToken ct)
        => FromResult(await sender.Send(new SimulateRecommendationsQuery(request), ct));
}
