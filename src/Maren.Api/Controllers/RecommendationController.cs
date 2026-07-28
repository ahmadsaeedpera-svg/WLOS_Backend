using Maren.Application.Abstractions;
using Maren.Application.Coaching;
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

/// <summary>
/// The coach: how the platform says what it is already suggesting.
/// </summary>
/// <remarks>
/// <para>
/// The coach invents nothing. A message is filled in from a tone pattern whose
/// placeholders are the recommendation and the observations behind it, and a
/// database constraint refuses a pattern that drops either — so every fact she
/// reads came from her own timeline.
/// </para>
/// <para>
/// It never reassembles. A coach that did would be a second opinion about the
/// same woman, and the two could disagree the moment a threshold changed.
/// </para>
/// </remarks>
[ApiController]
[Route("api/v1/me/coach")]
[Authorize]
public sealed class CoachController(ISender sender, ICurrentUser currentUser)
    : MarenControllerBase
{
    /// <summary>What the platform is saying to her today, and why in that voice.</summary>
    [HttpGet]
    [ProducesResponseType(typeof(ApiResponse<IReadOnlyList<CoachMessage>>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 401)]
    public async Task<IActionResult> GetMyCoach(
        [FromQuery] DateOnly? asOfDate, CancellationToken ct)
    {
        if (currentUser.UserId is not { } userId) return Unauthenticated();

        return FromResult(await sender.Send(new GetMyCoachQuery(userId, asOfDate), ct));
    }
}

/// <summary>The tone library and its simulator, for operators.</summary>
[ApiController]
[Route("api/v1/admin/coach")]
[Authorize]
public sealed class CoachAdminController(ISender sender) : MarenControllerBase
{
    /// <summary>Every tone, its pattern and when it applies.</summary>
    /// <remarks>
    /// Carries the rule count, because a non-default tone with no rules can
    /// never be selected — a voice the platform will never use, indistinguishable
    /// from one nobody qualifies for.
    /// </remarks>
    [HttpGet("tones")]
    [ProducesResponseType(typeof(ApiResponse<IReadOnlyList<CoachToneSummary>>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 403)]
    public async Task<IActionResult> ListTones(CancellationToken ct)
        => FromResult(await sender.Send(new ListCoachTonesQuery(), ct));

    /// <summary>What the platform would say, given evidence you describe.</summary>
    /// <remarks>
    /// Assembles with the only copy of the assembly and explains with the only
    /// copy of the explanation, so what you hear is what she would be told.
    /// Returns every tone alongside the messages, with whether this evidence
    /// selected it — which answers "why is it not being gentle".
    /// </remarks>
    [HttpPost("simulate")]
    [ProducesResponseType(typeof(ApiResponse<SimulateCoachResponse>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 400)]
    [ProducesResponseType(typeof(ApiResponse<object>), 403)]
    public async Task<IActionResult> Simulate(
        [FromBody] SimulateRecommendationsRequest request, CancellationToken ct)
        => FromResult(await sender.Send(new SimulateCoachQuery(request), ct));
}
