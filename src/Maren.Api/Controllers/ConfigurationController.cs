using FluentValidation;
using Maren.Application.Abstractions;
using Maren.Application.Configuration;
using Maren.Contracts;
using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Maren.Api.Controllers;

/// <summary>
/// What the mobile app asks for on launch.
/// </summary>
/// <remarks>
/// Anonymous on purpose. A client that has not signed in still needs the
/// version gate and the maintenance flag, and requiring a token first would
/// mean a broken build could not be told it is broken. Personalised rollout
/// simply falls back to the non-user path when there is no token.
/// </remarks>
[ApiController]
[Route("api/v1/config")]
public sealed class ConfigurationController(ISender sender, ICurrentUser currentUser)
    : MarenControllerBase
{
    /// <summary>Flags, client settings and the version check in one call.</summary>
    [HttpGet("bootstrap")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(ApiResponse<BootstrapResponse>), 200)]
    public async Task<IActionResult> Bootstrap(
        [FromQuery] string platform = "android",
        [FromQuery] string? appVersion = null,
        [FromQuery] string? country = null,
        [FromQuery] bool isPremium = false,
        [FromQuery] bool isBeta = false,
        CancellationToken ct = default)
    {
        var result = await sender.Send(new BootstrapQuery(
            currentUser.UserId, platform, appVersion, country,
            isPremium, isBeta), ct);

        return FromResult(result);
    }
}

/// <summary>Feature flag administration.</summary>
[ApiController]
[Route("api/v1/admin/flags")]
[Authorize]
public sealed class FeatureFlagAdminController(ISender sender)
    : MarenControllerBase
{
    [HttpGet]
    [ProducesResponseType(typeof(ApiResponse<IReadOnlyList<FeatureFlagAdminDto>>), 200)]
    public async Task<IActionResult> List(CancellationToken ct) =>
        FromResult(await sender.Send(new ListFeatureFlagsQuery(), ct));

    /// <summary>Creates or updates a flag. Requires <c>flags.write</c>.</summary>
    [HttpPut]
    [ProducesResponseType(typeof(ApiResponse<FeatureFlagAdminDto>), 200)]
    [ProducesResponseType(typeof(ApiResponse<FeatureFlagAdminDto>), 403)]
    public Task<IActionResult> Upsert(
        [FromBody] UpsertFeatureFlagRequest request,
        [FromServices] IValidator<UpsertFeatureFlagCommand> validator,
        CancellationToken ct) =>
        ValidateThen<UpsertFeatureFlagCommand, FeatureFlagAdminDto>(
            new UpsertFeatureFlagCommand(request), validator, sender, ct);
}
