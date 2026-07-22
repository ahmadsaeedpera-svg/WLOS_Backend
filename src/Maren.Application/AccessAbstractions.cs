using Maren.Contracts;

namespace Maren.Application.Access;

/// <summary>Data access for users, roles, permissions and audit.</summary>
public interface IAccessRepository
{
    Task<PagedResult<UserListItemDto>> SearchUsersAsync(
        UserSearchQuery criteria, CancellationToken ct);

    Task<UserDetailDto?> GetUserAsync(Guid userId, CancellationToken ct);

    Task<(bool Succeeded, string? FailureCode)> SetLockoutAsync(
        Guid userId, bool isLocked, string? reason, DateTime? lockoutEndUtc,
        Guid? actorUserId, CancellationToken ct);

    Task<(bool Succeeded, string? FailureCode)> AssignRoleAsync(
        Guid userId, int roleId, Guid? actorUserId, CancellationToken ct);

    Task<(bool Succeeded, string? FailureCode)> RemoveRoleAsync(
        Guid userId, int roleId, Guid? actorUserId, CancellationToken ct);

    Task<(bool Succeeded, string? FailureCode)> RevokeSessionsAsync(
        Guid userId, string? reason, Guid? actorUserId, CancellationToken ct);

    Task<IReadOnlyList<RoleDto>> ListRolesAsync(CancellationToken ct);

    Task<IReadOnlyList<PermissionDto>> ListPermissionsAsync(CancellationToken ct);

    Task<(bool Succeeded, string? FailureCode, int? RoleId)> SaveRoleAsync(
        int? roleId, string name, string? description, Guid? actorUserId,
        CancellationToken ct);

    Task<(bool Succeeded, string? FailureCode)> DeleteRoleAsync(
        int roleId, Guid? actorUserId, CancellationToken ct);

    Task<(bool Succeeded, string? FailureCode)> SetRolePermissionsAsync(
        int roleId, string permissionCodesJson, Guid? actorUserId,
        CancellationToken ct);

    Task<PagedResult<AuditEntryDto>> SearchAuditAsync(
        AuditSearchQuery criteria, CancellationToken ct);

    /// <summary>
    /// Every user whose sessions have been revoked, with the stamp that is now
    /// current.
    /// </summary>
    /// <remarks>
    /// Feeds the API's revocation cache. Small by construction — one row per
    /// revoked user — so it is loaded whole rather than queried per request.
    /// </remarks>
    Task<IReadOnlyList<(Guid UserId, Guid SecurityStamp)>> GetRevocationsAsync(
        CancellationToken ct);

    /// <summary>Records a security event from the application layer.</summary>
    /// <remarks>
    /// The API refuses an escalation before it reaches the procedure that would
    /// have audited it, because the handler checks first so it can name which
    /// permissions are missing. Without this, that refusal is invisible on the
    /// only path anybody uses.
    /// </remarks>
    Task RecordSecurityEventAsync(
        Guid? actorUserId, string action, string? entityType, string? entityId,
        string? detailJson, string? ipAddress, CancellationToken ct);
}

/// <summary>
/// Decides whether a token that was valid when issued is still valid now.
/// </summary>
/// <remarks>
/// Permissions travel as claims in a 15-minute access token. Locking an account
/// or removing a role would otherwise leave the holder fully privileged for the
/// remainder of that window — which is exactly the window the action was taken
/// to close.
/// </remarks>
public interface ISecurityStampValidator
{
    /// <summary>
    /// False when the token's stamp is stale and the request must be refused.
    /// </summary>
    Task<bool> IsCurrentAsync(Guid userId, Guid tokenStamp, CancellationToken ct);
}
