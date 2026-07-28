using Maren.Application.Inspector;
using Maren.Contracts;
using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Maren.Api.Controllers;

/// <summary>
/// The decision inspector: what the engines would do for a hypothetical woman.
/// </summary>
/// <remarks>
/// <para>
/// The platform decides what a woman sees from her life stage, her roles and
/// what her timeline says. This lets an operator check that configuration
/// before it reaches anyone, by describing a woman rather than opening one.
/// </para>
/// <para>
/// There is deliberately no endpoint that inspects a real account. Resolving a
/// named user's pipeline would show an operator her life stage, her raised
/// signals and the timeline evidence behind them — impersonation under another
/// label, which CLAUDE.md §8 forbids until there is a consent model, a time
/// limit, a visible banner and legal review. A SQL assertion fails the build
/// if an inspector procedure ever references a user id or the timeline.
/// </para>
/// </remarks>
[ApiController]
[Route("api/v1/admin/inspector")]
[Authorize]
public sealed class InspectorController(ISender sender) : MarenControllerBase
{
    /// <summary>What the dashboard engine would produce for this hypothetical.</summary>
    /// <remarks>
    /// Suppressed cards come back flagged rather than omitted. On the live path
    /// they simply vanish, which makes "why is my card missing" unanswerable;
    /// here an operator sees that it was eligible and then driven below zero,
    /// and which signal did it.
    /// </remarks>
    [HttpPost("simulate")]
    [ProducesResponseType(typeof(ApiResponse<SimulateResponse>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 400)]
    [ProducesResponseType(typeof(ApiResponse<object>), 403)]
    public async Task<IActionResult> Simulate(
        [FromBody] SimulateRequest request, CancellationToken ct)
        => FromResult(await sender.Send(new SimulateDashboardQuery(request), ct));

    /// <summary>Every rule and adjustment governing one card, with pass or fail.</summary>
    /// <remarks>
    /// Failing rules are returned alongside passing ones. A list of only what
    /// matched explains a card's presence and never its absence, and absence is
    /// what an operator is usually investigating.
    /// </remarks>
    [HttpPost("cards/{cardTypeCode}/explain")]
    [ProducesResponseType(typeof(ApiResponse<ExplainCardResponse>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 404)]
    public async Task<IActionResult> Explain(
        string cardTypeCode,
        [FromBody] SimulateRequest request,
        CancellationToken ct)
        => FromResult(await sender.Send(new ExplainCardQuery(cardTypeCode, request), ct));
}
