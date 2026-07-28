using Maren.Application.Abstractions;
using Maren.Application.Growth;
using Maren.Contracts;
using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Maren.Api.Controllers;

/// <summary>
/// Her goals: what she is working towards, and how far she has come.
/// </summary>
/// <remarks>
/// <para>
/// The user id comes from the token and never from the route, so there is no
/// shape of request that reads or changes somebody else's goals. The procedures
/// scope on it as well — without that predicate,
/// <c>usp_Goal_SetStatus</c> would be a one-parameter way to abandon a
/// stranger's goal.
/// </para>
/// <para>
/// There is deliberately no endpoint that marks a goal achieved. Achievement is
/// decided by the engine from what she logged; an endpoint that declared it
/// would turn the one number in the platform that has to be earned into one
/// that can be asked for.
/// </para>
/// </remarks>
[ApiController]
[Route("api/v1/me/goals")]
[Authorize]
public sealed class GoalController(ISender sender, ICurrentUser currentUser)
    : MarenControllerBase
{
    /// <summary>Where she stands on every goal she is holding.</summary>
    /// <remarks>
    /// Progress is the distance between what Behaviour Intelligence observed
    /// and what the goal asks for. A goal with too little logged behind it
    /// returns null progress rather than zero — a zero ring says she has made
    /// no progress, and the truth is the platform cannot yet say.
    /// </remarks>
    [HttpGet]
    [ProducesResponseType(typeof(ApiResponse<IReadOnlyList<GoalProgress>>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 401)]
    public async Task<IActionResult> GetMyGoals(
        [FromQuery] DateOnly? asOfDate, CancellationToken ct)
    {
        if (currentUser.UserId is not { } userId) return Unauthenticated();

        return FromResult(await sender.Send(new GetMyGoalsQuery(userId, asOfDate), ct));
    }

    /// <summary>The goals worth offering her.</summary>
    /// <remarks>
    /// Applicability comes from the platform's one rule matcher, so a goal that
    /// only makes sense in pregnancy is a rule row like every other targeting
    /// decision. Goals she already holds are excluded — offering somebody a goal
    /// they are three weeks into is the platform admitting it does not know her.
    /// </remarks>
    [HttpGet("offers")]
    [ProducesResponseType(typeof(ApiResponse<IReadOnlyList<GoalOffer>>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 401)]
    public async Task<IActionResult> GetOffers(CancellationToken ct)
    {
        if (currentUser.UserId is not { } userId) return Unauthenticated();

        /*  The targeting context is derived server-side by the pipeline, never
            accepted from the client. A client that supplied it could ask for
            pregnancy goals by claiming to be pregnant. */
        return FromResult(await sender.Send(new GetGoalOffersQuery(userId, null), ct));
    }

    /// <summary>She takes a goal on, in her own words.</summary>
    /// <remarks>
    /// Idempotent: adopting one she already holds updates her reason and
    /// priority rather than failing. An offline client retries, and a woman who
    /// taps twice should not see an error about a goal she just set.
    /// </remarks>
    [HttpPost]
    [ProducesResponseType(typeof(ApiResponse<Guid>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 400)]
    [ProducesResponseType(typeof(ApiResponse<object>), 404)]
    public async Task<IActionResult> Adopt(
        [FromBody] AdoptGoalRequest request, CancellationToken ct)
    {
        if (currentUser.UserId is not { } userId) return Unauthenticated();

        return FromResult(await sender.Send(new AdoptGoalCommand(userId, request), ct));
    }

    /// <summary>Resume, pause or let a goal go.</summary>
    /// <remarks>
    /// <c>achieved</c> is refused, by the validator and by the procedure.
    /// </remarks>
    [HttpPut("{userGoalId:guid}/status")]
    [ProducesResponseType(typeof(ApiResponse<object>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 400)]
    [ProducesResponseType(typeof(ApiResponse<object>), 404)]
    public async Task<IActionResult> SetStatus(
        Guid userGoalId, [FromBody] SetGoalStatusBody body, CancellationToken ct)
    {
        if (currentUser.UserId is not { } userId) return Unauthenticated();

        return FromResult(await sender.Send(
            new SetGoalStatusCommand(userId, userGoalId, body.Status), ct));
    }
}

/// <summary>The body of a status change.</summary>
public sealed record SetGoalStatusBody(string Status);

/// <summary>The goal library, for operators.</summary>
/// <remarks>
/// Configuration, not anybody's data: what the platform offers and what each
/// goal is measured by. No woman's goals or progress are reachable here.
/// </remarks>
[ApiController]
[Route("api/v1/admin/goals")]
[Authorize]
public sealed class GoalAdminController(ISender sender) : MarenControllerBase
{
    /// <summary>Every goal template, with its measures and how many rules narrow it.</summary>
    [HttpGet("templates")]
    [ProducesResponseType(typeof(ApiResponse<IReadOnlyList<GoalTemplateSummary>>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 403)]
    public async Task<IActionResult> ListTemplates(CancellationToken ct)
        => FromResult(await sender.Send(new ListGoalTemplatesQuery(), ct));
}

/// <summary>
/// Her routines: several behaviours done together, and where she is up to today.
/// </summary>
/// <remarks>
/// <para>
/// There is deliberately no endpoint that marks a routine complete. Completion
/// is derived from logged events every time it is asked for — a "mark done"
/// endpoint would be a second definition of done, and the first time it
/// disagreed with the timeline she would see a completed routine beside a
/// broken streak.
/// </para>
/// <para>
/// To finish a routine she logs its steps, through the timeline, like
/// everything else the platform observes.
/// </para>
/// </remarks>
[ApiController]
[Route("api/v1/me/routines")]
[Authorize]
public sealed class RoutineController(ISender sender, ICurrentUser currentUser)
    : MarenControllerBase
{
    /// <summary>Today's routines, in the order they belong to the day.</summary>
    /// <remarks>
    /// Ordered by the clock rather than by priority: a morning routine listed
    /// under an evening one because it scores lower would be the platform
    /// arguing with the day. Each carries its steps, optional ones included and
    /// flagged.
    /// </remarks>
    [HttpGet]
    [ProducesResponseType(typeof(ApiResponse<IReadOnlyList<RoutineToday>>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 401)]
    public async Task<IActionResult> GetMyRoutines(
        [FromQuery] DateOnly? asOfDate, CancellationToken ct)
    {
        if (currentUser.UserId is not { } userId) return Unauthenticated();

        return FromResult(await sender.Send(new GetMyRoutinesQuery(userId, asOfDate), ct));
    }
}

/// <summary>The routine library, for operators.</summary>
[ApiController]
[Route("api/v1/admin/routines")]
[Authorize]
public sealed class RoutineAdminController(ISender sender) : MarenControllerBase
{
    /// <summary>Every routine, with the Behaviour subject that observes it.</summary>
    /// <remarks>
    /// Carries the subject's target and required-part count, because the
    /// commonest routine misconfiguration is a target higher than the number of
    /// required parts — a routine that can never be completed, which looks
    /// identical to one nobody has done.
    /// </remarks>
    [HttpGet]
    [ProducesResponseType(typeof(ApiResponse<IReadOnlyList<RoutineSummary>>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 403)]
    public async Task<IActionResult> ListRoutines(CancellationToken ct)
        => FromResult(await sender.Send(new ListRoutinesQuery(), ct));
}
