using Maren.Application.Abstractions;
using Maren.Application.Predicting;
using Maren.Contracts;
using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Maren.Api.Controllers;

/// <summary>
/// What the platform says about her behaviour going forward.
/// </summary>
/// <remarks>
/// <para>
/// Behavioural only, and never clinical. A prediction is about whether she does
/// a thing — not about a condition, an outcome of one, or a cause.
/// </para>
/// <para>
/// It computes nothing. Behaviour observes three probabilities from her logged
/// history; this attaches a window to one of them. A prediction type may only
/// name a measure the behaviour engine publishes as a probability, enforced by
/// a foreign key rather than by review, so there is no configuration and no
/// code path that states a likelihood the platform never observed.
/// </para>
/// <para>
/// Every statement carries the chance, the window and the support behind it,
/// because a database constraint refuses a framing that drops any of them. Under
/// either floor the prediction is withheld entirely rather than hedged — a
/// statement built on nine days is not a weaker statement of the same kind.
/// </para>
/// </remarks>
[ApiController]
[Route("api/v1/me/predictions")]
[Authorize]
public sealed class PredictionController(ISender sender, ICurrentUser currentUser)
    : MarenControllerBase
{
    /// <summary>Today's statements, most likely first.</summary>
    /// <remarks>
    /// Expired ones are excluded on read as well as at framing, so a statement
    /// about tomorrow is not still on screen the day after.
    /// </remarks>
    [HttpGet]
    [ProducesResponseType(typeof(ApiResponse<IReadOnlyList<Prediction>>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 401)]
    public async Task<IActionResult> GetMyPredictions(
        [FromQuery] DateOnly? asOfDate, CancellationToken ct)
    {
        if (currentUser.UserId is not { } userId) return Unauthenticated();

        return FromResult(await sender.Send(
            new GetMyPredictionsQuery(userId, asOfDate), ct));
    }
}

/// <summary>The prediction catalogue and its simulator, for operators.</summary>
/// <remarks>
/// Configuration, not anybody's data. The simulator takes observations an
/// operator described and never a user id — a SQL assertion fails if any
/// inspector procedure gains one.
/// </remarks>
[ApiController]
[Route("api/v1/admin/predictions")]
[Authorize]
public sealed class PredictionAdminController(ISender sender) : MarenControllerBase
{
    /// <summary>Every prediction, and the behaviour measure it frames.</summary>
    /// <remarks>
    /// Carries the source measure and whether it is still active, because a
    /// prediction whose measure has been switched off can never fire and looks
    /// identical to one nobody qualifies for.
    /// </remarks>
    [HttpGet]
    [ProducesResponseType(typeof(ApiResponse<IReadOnlyList<PredictionTypeSummary>>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 403)]
    public async Task<IActionResult> List(CancellationToken ct)
        => FromResult(await sender.Send(new ListPredictionTypesQuery(), ct));

    /// <summary>What the platform would predict, given observations you describe.</summary>
    /// <remarks>
    /// <para>
    /// Observations use a shorthand an operator can type:
    /// <c>hydration.completion_probability=0.7@21</c>, where the suffix is the
    /// days of history behind the number. It runs the same framing as the live
    /// path, because there is only one copy of it.
    /// </para>
    /// <para>
    /// Returns every prediction type alongside what fired, with a stated reason
    /// for each that did not. This engine withholds deliberately and often, and
    /// "nothing appeared" is indistinguishable from a bug without the reason —
    /// an operator who cannot tell them apart eventually lowers a floor to make
    /// the screen look busier, which is the one change here that would make the
    /// platform overstate what it knows.
    /// </para>
    /// </remarks>
    [HttpPost("simulate")]
    [ProducesResponseType(typeof(ApiResponse<SimulatePredictionResponse>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 400)]
    [ProducesResponseType(typeof(ApiResponse<object>), 403)]
    public async Task<IActionResult> Simulate(
        [FromBody] SimulatePredictionRequest request, CancellationToken ct)
        => FromResult(await sender.Send(new SimulatePredictionQuery(request), ct));
}
