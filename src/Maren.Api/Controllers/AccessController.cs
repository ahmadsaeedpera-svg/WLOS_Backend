using System.Globalization;
using FluentValidation;
using Maren.Application.Access;
using Maren.Contracts;
using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Maren.Api.Controllers;

/// <summary>
/// User administration.
/// </summary>
/// <remarks>
/// Permissions are enforced by the MediatR pipeline via
/// <c>IRequirePermission</c>, and the escalation and self-demotion rules are
/// enforced again in the stored procedures. <c>[Authorize]</c> here only
/// establishes that there is an authenticated caller.
///
/// <para>
/// Nothing on this controller returns password material. The procedures behind
/// it name their result columns, and a test asserts across the whole database
/// that no procedure outside the login path so much as mentions
/// <c>PasswordHash</c>.
/// </para>
/// </remarks>
[ApiController]
[Route("api/v1/admin/users")]
[Authorize]
[Produces("application/json")]
public sealed class UsersController(ISender sender) : MarenControllerBase
{
    /// <summary>Searches accounts with paging and filtering.</summary>
    [HttpGet]
    [ProducesResponseType(typeof(ApiResponse<PagedResult<UserListItemDto>>), 200)]
    public async Task<IActionResult> Search(
        [FromQuery] string? query,
        [FromQuery] int? roleId,
        [FromQuery] string status = "any",
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 25,
        [FromQuery] string sortBy = "created",
        [FromQuery] bool sortDescending = true,
        CancellationToken ct = default)
    {
        var result = await sender.Send(new SearchUsersQuery(
            new UserSearchQuery(query, roleId, status, page, pageSize,
                sortBy, sortDescending)), ct);

        if (result.Succeeded)
        {
            Response.Headers["X-Total-Count"] =
                result.Value!.TotalCount.ToString(CultureInfo.InvariantCulture);
            Response.Headers["X-Total-Pages"] =
                result.Value.TotalPages.ToString(CultureInfo.InvariantCulture);
        }

        return FromResult(result);
    }

    /// <summary>One account with its roles, devices and recent activity.</summary>
    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(ApiResponse<UserDetailDto>), 200)]
    [ProducesResponseType(typeof(ApiResponse<UserDetailDto>), 404)]
    public async Task<IActionResult> Get(Guid id, CancellationToken ct) =>
        FromResult(await sender.Send(new GetUserQuery(id), ct));

    /// <summary>Locks or unlocks an account.</summary>
    /// <remarks>
    /// Locking ends every live session immediately. Without that, an account
    /// locked while its owner is signed in stays usable until their access
    /// token expires, which defeats the point of locking it.
    /// </remarks>
    [HttpPost("{id:guid}/lock")]
    [ProducesResponseType(typeof(ApiResponse<object>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 409)]
    public async Task<IActionResult> SetLockout(
        Guid id, [FromBody] SetLockoutRequest request, CancellationToken ct) =>
        FromResult(await sender.Send(new SetLockoutCommand(id, request), ct));

    /// <summary>Grants a role.</summary>
    /// <remarks>
    /// Refused with <c>PRIVILEGE_ESCALATION</c> when the role includes any
    /// permission the caller does not hold. Otherwise <c>roles.write</c> would
    /// be equivalent to full administrative access.
    /// </remarks>
    [HttpPost("{id:guid}/roles")]
    [ProducesResponseType(typeof(ApiResponse<object>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 409)]
    public async Task<IActionResult> AssignRole(
        Guid id, [FromBody] AssignRoleRequest request, CancellationToken ct) =>
        FromResult(await sender.Send(new AssignRoleCommand(id, request.RoleId), ct));

    [HttpDelete("{id:guid}/roles/{roleId:int}")]
    [ProducesResponseType(typeof(ApiResponse<object>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 409)]
    public async Task<IActionResult> RemoveRole(
        Guid id, int roleId, CancellationToken ct) =>
        FromResult(await sender.Send(new RemoveRoleCommand(id, roleId), ct));

    /// <summary>Signs the account out of every device.</summary>
    [HttpPost("{id:guid}/revoke-sessions")]
    [ProducesResponseType(typeof(ApiResponse<object>), 200)]
    public async Task<IActionResult> RevokeSessions(
        Guid id, [FromBody] RevokeSessionsRequest request, CancellationToken ct) =>
        FromResult(await sender.Send(new RevokeSessionsCommand(id, request), ct));
}

/// <summary>Role and permission administration.</summary>
[ApiController]
[Route("api/v1/admin/roles")]
[Authorize]
[Produces("application/json")]
public sealed class RolesController(ISender sender) : MarenControllerBase
{
    /// <summary>Roles with their permission grants and member counts.</summary>
    [HttpGet]
    [ProducesResponseType(typeof(ApiResponse<IReadOnlyList<RoleDto>>), 200)]
    public async Task<IActionResult> List(CancellationToken ct) =>
        FromResult(await sender.Send(new ListRolesQuery(), ct));

    /// <summary>The permission catalogue, for building the matrix.</summary>
    [HttpGet("permissions")]
    [ProducesResponseType(typeof(ApiResponse<IReadOnlyList<PermissionDto>>), 200)]
    public async Task<IActionResult> Permissions(CancellationToken ct) =>
        FromResult(await sender.Send(new ListPermissionsQuery(), ct));

    /// <summary>Creates or renames a role.</summary>
    [HttpPut]
    [ProducesResponseType(typeof(ApiResponse<int>), 200)]
    [ProducesResponseType(typeof(ApiResponse<int>), 409)]
    public Task<IActionResult> Save(
        [FromBody] SaveRoleRequest request,
        [FromServices] IValidator<SaveRoleCommand> validator,
        CancellationToken ct) =>
        ValidateThen<SaveRoleCommand, int>(
            new SaveRoleCommand(request), validator, sender, ct);

    [HttpDelete("{id:int}")]
    [ProducesResponseType(typeof(ApiResponse<object>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 409)]
    public async Task<IActionResult> Delete(int id, CancellationToken ct) =>
        FromResult(await sender.Send(new DeleteRoleCommand(id), ct));

    /// <summary>Replaces a role's permission set.</summary>
    /// <remarks>
    /// Replace-all rather than add/remove: an operator ticking boxes in a
    /// matrix is describing the end state, and a partial update makes an
    /// unticked box ambiguous between "leave it" and "remove it".
    /// </remarks>
    [HttpPut("{id:int}/permissions")]
    [ProducesResponseType(typeof(ApiResponse<object>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 409)]
    public async Task<IActionResult> SetPermissions(
        int id, [FromBody] SetRolePermissionsRequest request,
        CancellationToken ct) =>
        FromResult(await sender.Send(
            new SetRolePermissionsCommand(id, request), ct));
}

/// <summary>The audit trail.</summary>
/// <remarks>
/// Read-only, and there is no write endpoint anywhere in the platform. An
/// audit trail somebody can edit is not one.
/// </remarks>
[ApiController]
[Route("api/v1/admin/audit")]
[Authorize]
[Produces("application/json")]
public sealed class AuditController(ISender sender) : MarenControllerBase
{
    [HttpGet]
    [ProducesResponseType(typeof(ApiResponse<PagedResult<AuditEntryDto>>), 200)]
    public async Task<IActionResult> Search(
        [FromQuery] Guid? actorUserId,
        [FromQuery] string? entityType,
        [FromQuery] string? entityId,
        [FromQuery] string? action,
        [FromQuery] DateTime? fromUtc,
        [FromQuery] DateTime? toUtc,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        CancellationToken ct = default)
    {
        var result = await sender.Send(new SearchAuditQuery(
            new AuditSearchQuery(actorUserId, entityType, entityId, action,
                fromUtc, toUtc, page, pageSize)), ct);

        if (result.Succeeded)
        {
            Response.Headers["X-Total-Count"] =
                result.Value!.TotalCount.ToString(CultureInfo.InvariantCulture);
            Response.Headers["X-Total-Pages"] =
                result.Value.TotalPages.ToString(CultureInfo.InvariantCulture);
        }

        return FromResult(result);
    }
}
