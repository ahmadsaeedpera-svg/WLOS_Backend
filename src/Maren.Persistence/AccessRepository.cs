using System.Data;
using Dapper;
using Maren.Application.Abstractions;
using Maren.Application.Access;
using Maren.Contracts;

namespace Maren.Persistence;

/// <summary>
/// Users, roles, permissions and audit.
/// </summary>
/// <remarks>
/// On the ambient connection so it enlists in whatever transaction the pipeline
/// opened, exactly like <see cref="ContentRepository"/>.
///
/// <para>
/// Every call names a stored procedure. Nothing here composes SQL, and nothing
/// selects password material — the procedures enforce that, and a test asserts
/// it across the whole database.
/// </para>
/// </remarks>
public sealed class AccessRepository(
    IAmbientConnection ambient, IDbConnectionFactory factory) : IAccessRepository
{
    // -----------------------------------------------------------------------
    // Users
    // -----------------------------------------------------------------------

    public async Task<PagedResult<UserListItemDto>> SearchUsersAsync(
        UserSearchQuery criteria, CancellationToken ct)
    {
        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            var rows = (await connection.QueryAsync<UserSearchRow>(
                new CommandDefinition(
                    "[Identity].[usp_User_Search]",
                    new
                    {
                        criteria.Query,
                        criteria.RoleId,
                        criteria.Status,
                        criteria.Page,
                        criteria.PageSize,
                        criteria.SortBy,
                        criteria.SortDescending
                    },
                    transaction, commandType: CommandType.StoredProcedure,
                    cancellationToken: ct))).ToList();

            // TotalCount rides along on every row from COUNT(*) OVER(). An
            // empty page means zero, not "unknown".
            var total = rows.Count == 0 ? 0 : rows[0].TotalCount;

            var items = rows.Select(r => new UserListItemDto(
                r.UserId, r.Email, r.LanguageCode, r.IsEmailConfirmed,
                r.IsLockedOut, r.LockoutEndUtc, r.FailedLoginCount,
                r.IsDeleted, r.CreatedUtc, r.CountryIso, r.RoleNames)).ToList();

            return new PagedResult<UserListItemDto>(
                items, criteria.Page, criteria.PageSize, total);
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    public async Task<UserDetailDto?> GetUserAsync(Guid userId, CancellationToken ct)
    {
        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            using var grid = await connection.QueryMultipleAsync(
                new CommandDefinition(
                    "[Identity].[usp_User_GetDetail]",
                    new { UserId = userId },
                    transaction, commandType: CommandType.StoredProcedure,
                    cancellationToken: ct));

            var header = await grid.ReadSingleOrDefaultAsync<UserHeaderRow>();
            if (header is null) return null;

            var roles = (await grid.ReadAsync<UserRoleDto>()).ToList();
            var devices = (await grid.ReadAsync<UserDeviceDto>()).ToList();
            var activity = (await grid.ReadAsync<UserActivityDto>()).ToList();

            return new UserDetailDto(
                header.UserId, header.Email, header.LanguageCode,
                header.IsEmailConfirmed, header.IsLockedOut, header.LockoutEndUtc,
                header.FailedLoginCount, header.IsDeleted, header.DeletedUtc,
                header.CreatedUtc, header.ModifiedUtc, header.CountryIso,
                roles, devices, activity);
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    public Task<(bool Succeeded, string? FailureCode)> SetLockoutAsync(
        Guid userId, bool isLocked, string? reason, DateTime? lockoutEndUtc,
        Guid? actorUserId, CancellationToken ct) =>
        ExecuteOutcomeAsync("[Identity].[usp_User_SetLockout]", new
        {
            UserId = userId,
            IsLocked = isLocked,
            Reason = reason,
            LockoutEndUtc = lockoutEndUtc,
            ActorUserId = actorUserId
        }, ct);

    public Task<(bool Succeeded, string? FailureCode)> AssignRoleAsync(
        Guid userId, int roleId, Guid? actorUserId, CancellationToken ct) =>
        ExecuteOutcomeAsync("[Identity].[usp_User_AssignRole]", new
        {
            UserId = userId, RoleId = roleId, ActorUserId = actorUserId
        }, ct);

    public Task<(bool Succeeded, string? FailureCode)> RemoveRoleAsync(
        Guid userId, int roleId, Guid? actorUserId, CancellationToken ct) =>
        ExecuteOutcomeAsync("[Identity].[usp_User_RemoveRole]", new
        {
            UserId = userId, RoleId = roleId, ActorUserId = actorUserId
        }, ct);

    public Task<(bool Succeeded, string? FailureCode)> RevokeSessionsAsync(
        Guid userId, string? reason, Guid? actorUserId, CancellationToken ct) =>
        ExecuteOutcomeAsync("[Identity].[usp_User_RevokeSessions]", new
        {
            UserId = userId, Reason = reason, ActorUserId = actorUserId
        }, ct);

    // -----------------------------------------------------------------------
    // Roles
    // -----------------------------------------------------------------------

    public async Task<IReadOnlyList<RoleDto>> ListRolesAsync(CancellationToken ct)
    {
        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            using var grid = await connection.QueryMultipleAsync(
                new CommandDefinition(
                    "[Identity].[usp_Role_List]", null,
                    transaction, commandType: CommandType.StoredProcedure,
                    cancellationToken: ct));

            var roles = (await grid.ReadAsync<RoleHeaderRow>()).ToList();
            var grants = (await grid.ReadAsync<RoleGrantRow>()).ToList();

            // One pass over the grant matrix rather than a lookup per role.
            var byRole = grants
                .GroupBy(g => g.RoleId)
                .ToDictionary(g => g.Key, g => (IReadOnlyList<string>)
                    g.Select(x => x.Code).ToList());

            return roles.Select(r => new RoleDto(
                r.RoleId, r.Name, r.Description, r.IsSystem,
                r.PermissionCount, r.MemberCount,
                byRole.TryGetValue(r.RoleId, out var codes) ? codes : [])).ToList();
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    public async Task<IReadOnlyList<PermissionDto>> ListPermissionsAsync(
        CancellationToken ct)
    {
        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            return (await connection.QueryAsync<PermissionDto>(
                new CommandDefinition(
                    "[Identity].[usp_Permission_List]", null,
                    transaction, commandType: CommandType.StoredProcedure,
                    cancellationToken: ct))).ToList();
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    public async Task<(bool Succeeded, string? FailureCode, int? RoleId)> SaveRoleAsync(
        int? roleId, string name, string? description, Guid? actorUserId,
        CancellationToken ct)
    {
        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            var row = await connection.QuerySingleAsync<RoleSaveOutcomeRow>(
                new CommandDefinition(
                    "[Identity].[usp_Role_Save]",
                    new
                    {
                        RoleId = roleId,
                        Name = name,
                        Description = description,
                        ActorUserId = actorUserId
                    },
                    transaction, commandType: CommandType.StoredProcedure,
                    cancellationToken: ct));

            return (row.Succeeded, row.FailureCode, row.RoleId);
        }
        catch (Microsoft.Data.SqlClient.SqlException ex)
        {
            return (false, SqlErrorMapper.Map(ex).FailureCode, null);
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    public Task<(bool Succeeded, string? FailureCode)> DeleteRoleAsync(
        int roleId, Guid? actorUserId, CancellationToken ct) =>
        ExecuteOutcomeAsync("[Identity].[usp_Role_Delete]", new
        {
            RoleId = roleId, ActorUserId = actorUserId
        }, ct);

    public Task<(bool Succeeded, string? FailureCode)> SetRolePermissionsAsync(
        int roleId, string permissionCodesJson, Guid? actorUserId,
        CancellationToken ct) =>
        ExecuteOutcomeAsync("[Identity].[usp_Role_SetPermissions]", new
        {
            RoleId = roleId,
            PermissionCodes = permissionCodesJson,
            ActorUserId = actorUserId
        }, ct);

    // -----------------------------------------------------------------------
    // Audit
    // -----------------------------------------------------------------------

    public async Task<PagedResult<AuditEntryDto>> SearchAuditAsync(
        AuditSearchQuery criteria, CancellationToken ct)
    {
        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            var rows = (await connection.QueryAsync<AuditRow>(
                new CommandDefinition(
                    "[Audit].[usp_Audit_Search]",
                    new
                    {
                        criteria.ActorUserId,
                        criteria.EntityType,
                        criteria.EntityId,
                        criteria.Action,
                        criteria.FromUtc,
                        criteria.ToUtc,
                        criteria.Page,
                        criteria.PageSize
                    },
                    transaction, commandType: CommandType.StoredProcedure,
                    cancellationToken: ct))).ToList();

            var total = rows.Count == 0 ? 0 : rows[0].TotalCount;

            var items = rows.Select(r => new AuditEntryDto(
                r.AuditLogId, r.OccurredUtc, r.ActorUserId, r.ActorEmail,
                r.ActorKind, r.Action, r.EntityType, r.EntityId,
                r.BeforeJson, r.AfterJson, r.IpAddress, r.CorrelationId)).ToList();

            return new PagedResult<AuditEntryDto>(
                items, criteria.Page, criteria.PageSize, total);
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    public async Task<IReadOnlyList<(Guid UserId, Guid SecurityStamp)>>
        GetRevocationsAsync(CancellationToken ct)
    {
        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            var rows = await connection.QueryAsync<RevocationRow>(
                new CommandDefinition(
                    "[Identity].[usp_Access_GetRevocations]", null,
                    transaction, commandType: CommandType.StoredProcedure,
                    cancellationToken: ct));

            return rows.Select(r => (r.UserId, r.SecurityStamp)).ToList();
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    /// <summary>
    /// Writes a security event on its OWN connection, outside any ambient
    /// transaction.
    /// </summary>
    /// <remarks>
    /// This is the one place in the platform that deliberately escapes the unit
    /// of work, and it has to.
    ///
    /// <para>
    /// These events are written on the refusal path — an escalation attempt
    /// that was denied. The commands are <c>ITransactional</c>, so the pipeline
    /// rolls back when the handler returns a failure. Enlisting this write in
    /// that transaction means the record of the attempt is erased by the very
    /// rollback the attempt caused, and the probing that most needs to be
    /// visible is the only thing guaranteed not to be.
    /// </para>
    ///
    /// <para>
    /// The cost is that a security event can be recorded for an operation that
    /// then fails for an unrelated reason. That is the right way round: a
    /// spurious record of a denied attempt is noise, a missing one is a blind
    /// spot.
    /// </para>
    /// </remarks>
    public async Task RecordSecurityEventAsync(
        Guid? actorUserId, string action, string? entityType, string? entityId,
        string? detailJson, string? ipAddress, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        await connection.ExecuteAsync(new CommandDefinition(
            "[Identity].[usp_Access_RecordSecurityEvent]",
            new
            {
                ActorUserId = actorUserId,
                Action = action,
                EntityType = entityType,
                EntityId = entityId,
                DetailJson = detailJson,
                IpAddress = ipAddress
            },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));
    }

    // -----------------------------------------------------------------------

    private async Task<(bool Succeeded, string? FailureCode)> ExecuteOutcomeAsync(
        string procedure, object parameters, CancellationToken ct)
    {
        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            var row = await connection.QuerySingleOrDefaultAsync<OutcomeRow>(
                new CommandDefinition(
                    procedure, parameters, transaction,
                    commandType: CommandType.StoredProcedure,
                    cancellationToken: ct));

            return row is null ? (true, null) : (row.Succeeded, row.FailureCode);
        }
        catch (Microsoft.Data.SqlClient.SqlException ex)
        {
            return (false, SqlErrorMapper.Map(ex).FailureCode);
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    // Materialisation rows. Separate from the DTOs because the procedures
    // return paging and outcome columns the contracts deliberately omit.
    private sealed record UserSearchRow(
        Guid UserId, string? Email, string LanguageCode, bool IsEmailConfirmed,
        bool IsLockedOut, DateTime? LockoutEndUtc, int FailedLoginCount,
        bool IsDeleted, DateTime CreatedUtc, string? CountryIso,
        string RoleNames, int TotalCount);

    private sealed record UserHeaderRow(
        Guid UserId, string? Email, string LanguageCode, bool IsEmailConfirmed,
        bool IsLockedOut, DateTime? LockoutEndUtc, int FailedLoginCount,
        bool IsDeleted, DateTime? DeletedUtc, DateTime CreatedUtc,
        DateTime ModifiedUtc, string? CountryIso);

    private sealed record RoleHeaderRow(
        int RoleId, string Name, string? Description, bool IsSystem,
        int PermissionCount, int MemberCount);

    private sealed record RoleGrantRow(int RoleId, string Code);

    private sealed record RoleSaveOutcomeRow(
        bool Succeeded, string? FailureCode, int? RoleId);

    private sealed record AuditRow(
        long AuditLogId, DateTime OccurredUtc, Guid? ActorUserId,
        string? ActorEmail, string ActorKind, string Action, string? EntityType,
        string? EntityId, string? BeforeJson, string? AfterJson,
        string? IpAddress, Guid? CorrelationId, int TotalCount);

    private sealed record RevocationRow(Guid UserId, Guid SecurityStamp);

    private sealed record OutcomeRow(bool Succeeded, string? FailureCode);
}
