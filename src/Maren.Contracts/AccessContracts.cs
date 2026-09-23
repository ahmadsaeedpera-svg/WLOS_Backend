namespace Maren.Contracts;

// ---------------------------------------------------------------------------
// Users
// ---------------------------------------------------------------------------

/// <summary>One row of the admin user grid.</summary>
/// <remarks>
/// Carries no password material. <c>Identity.User</c> holds
/// <c>PasswordHash</c>, <c>PasswordSalt</c> and <c>PasswordIterations</c>; the
/// procedures behind this DTO name their columns so those cannot leak into a
/// browser response by accident.
/// </remarks>
public sealed record UserListItemDto(
    Guid UserId,
    string? Email,
    string LanguageCode,
    bool IsEmailConfirmed,
    bool IsLockedOut,
    DateTime? LockoutEndUtc,
    int FailedLoginCount,
    bool IsDeleted,
    DateTime CreatedOn,
    string? CountryIso,
    /// <summary>Comma-separated for display. Ids come from the detail view.</summary>
    string RoleNames);

public sealed record UserDetailDto(
    Guid UserId,
    string? Email,
    string LanguageCode,
    bool IsEmailConfirmed,
    bool IsLockedOut,
    DateTime? LockoutEndUtc,
    int FailedLoginCount,
    bool IsDeleted,
    DateTime? DeletedOn,
    DateTime CreatedOn,
    DateTime ModifiedOn,
    string? CountryIso,

    /// <summary>Whether a date of birth is on file and clears the launch age.</summary>
    /// <remarks>
    /// The date itself is deliberately absent. An operator supporting an
    /// account needs to know the gate was satisfied; they have no business
    /// knowing her birthday, and a support screen that displays one leaks it
    /// every time somebody glances at a shared monitor.
    /// </remarks>
    bool IsAgeVerified,

    /// <summary>Sessions that could still be used right now.</summary>
    /// <remarks>
    /// Refresh tokens that are neither revoked nor expired — as opposed to
    /// <see cref="Devices"/>, which is every device that ever registered. This
    /// is the number actually being asked for when someone reports that they
    /// think another person is in their account.
    /// </remarks>
    int ActiveSessionCount,

    IReadOnlyList<UserRoleDto> Roles,
    IReadOnlyList<UserDeviceDto> Devices,
    IReadOnlyList<UserActivityDto> RecentActivity);

public sealed record UserRoleDto(
    int RoleId, string Name, string? Description, bool IsSystem,
    DateTime AssignedUtc, Guid? AssignedBy);

/// <summary>
/// A registered device. No FCM token — it is a push credential and an operator
/// needs to know the device exists, not how to send to it.
/// </summary>
public sealed record UserDeviceDto(
    Guid DeviceId, string Platform, string? OsVersion, string? AppVersion,
    string? Model, bool IsActive, DateTime LastSeenUtc);

public sealed record UserActivityDto(
    long AuditLogId, DateTime OccurredUtc, string Action,
    string? EntityType, string? EntityId, string? IpAddress);

public sealed record UserSearchQuery(
    string? Query = null,
    int? RoleId = null,
    string Status = "any",
    int Page = 1,
    int PageSize = 25,
    string SortBy = "created",
    bool SortDescending = true);

public sealed record SetLockoutRequest(
    bool IsLocked,
    string? Reason,
    DateTime? LockoutEndUtc);

public sealed record AssignRoleRequest(int RoleId);

public sealed record RevokeSessionsRequest(string? Reason);

// ---------------------------------------------------------------------------
// Roles and permissions
// ---------------------------------------------------------------------------

public sealed record RoleDto(
    int RoleId,
    string Name,
    string? Description,
    bool IsSystem,
    int PermissionCount,
    int MemberCount,
    /// <summary>Populated from the grant matrix returned alongside the roles.</summary>
    IReadOnlyList<string> PermissionCodes);

public sealed record PermissionDto(
    int PermissionId, string Code, string? Description, string Category);

public sealed record SaveRoleRequest(
    int? RoleId, string Name, string? Description);

public sealed record SetRolePermissionsRequest(
    IReadOnlyList<string> PermissionCodes);

// ---------------------------------------------------------------------------
// Audit
// ---------------------------------------------------------------------------

public sealed record AuditEntryDto(
    long AuditLogId,
    DateTime OccurredUtc,
    Guid? ActorUserId,
    string? ActorEmail,
    string ActorKind,
    string Action,
    string? EntityType,
    string? EntityId,
    string? BeforeJson,
    string? AfterJson,
    string? IpAddress,
    Guid? CorrelationId);

public sealed record AuditSearchQuery(
    Guid? ActorUserId = null,
    string? EntityType = null,
    string? EntityId = null,
    string? Action = null,
    DateTime? FromUtc = null,
    DateTime? ToUtc = null,
    int Page = 1,
    int PageSize = 50);
