using System.Globalization;
using System.Text.Json;
using FluentValidation;
using Maren.Application.Abstractions;
using Maren.Application.Behaviors;
using Maren.Contracts;
using Maren.Domain;
using Maren.Shared;
using MediatR;

namespace Maren.Application.Access;

/// <summary>Permission codes this slice's requests gate on.</summary>
public static class AccessPermissions
{
    public const string UsersRead = "users.read";
    public const string UsersWrite = "users.write";
    public const string RolesRead = "roles.read";
    public const string RolesWrite = "roles.write";
    public const string AuditRead = "audit.read";
}

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

public sealed record SearchUsersQuery(UserSearchQuery Criteria)
    : IRequest<Result<PagedResult<UserListItemDto>>>, IRequirePermission
{
    public string Permission => AccessPermissions.UsersRead;
}

public sealed class SearchUsersHandler(IAccessRepository repository)
    : IRequestHandler<SearchUsersQuery, Result<PagedResult<UserListItemDto>>>
{
    public async Task<Result<PagedResult<UserListItemDto>>> Handle(
        SearchUsersQuery request, CancellationToken ct) =>
        Result<PagedResult<UserListItemDto>>.Success(
            await repository.SearchUsersAsync(request.Criteria, ct));
}

public sealed class SearchUsersValidator : AbstractValidator<SearchUsersQuery>
{
    private static readonly string[] Statuses =
        ["any", "active", "locked", "unconfirmed", "deleted"];

    private static readonly string[] SortKeys = ["created", "email"];

    public SearchUsersValidator()
    {
        RuleFor(x => x.Criteria.Page).GreaterThan(0);

        // Unbounded page sizes are a denial-of-service vector: one request for
        // a million rows holds a connection and a lot of memory.
        RuleFor(x => x.Criteria.PageSize).InclusiveBetween(1, 200);

        RuleFor(x => x.Criteria.Status).Must(s => Statuses.Contains(s))
            .WithMessage("Status must be one of: " + string.Join(", ", Statuses));

        RuleFor(x => x.Criteria.SortBy).Must(s => SortKeys.Contains(s))
            .WithMessage("Sort must be one of: " + string.Join(", ", SortKeys));
    }
}

public sealed record GetUserQuery(Guid UserId)
    : IRequest<Result<UserDetailDto>>, IRequirePermission
{
    public string Permission => AccessPermissions.UsersRead;
}

public sealed class GetUserHandler(IAccessRepository repository)
    : IRequestHandler<GetUserQuery, Result<UserDetailDto>>
{
    public async Task<Result<UserDetailDto>> Handle(
        GetUserQuery request, CancellationToken ct)
    {
        var user = await repository.GetUserAsync(request.UserId, ct);

        return user is null
            ? Result<UserDetailDto>.Failure(FailureCodes.NotFound, "No such user.")
            : Result<UserDetailDto>.Success(user);
    }
}

public sealed record ListRolesQuery
    : IRequest<Result<IReadOnlyList<RoleDto>>>, IRequirePermission
{
    public string Permission => AccessPermissions.RolesRead;
}

public sealed class ListRolesHandler(IAccessRepository repository)
    : IRequestHandler<ListRolesQuery, Result<IReadOnlyList<RoleDto>>>
{
    public async Task<Result<IReadOnlyList<RoleDto>>> Handle(
        ListRolesQuery request, CancellationToken ct) =>
        Result<IReadOnlyList<RoleDto>>.Success(await repository.ListRolesAsync(ct));
}

public sealed record ListPermissionsQuery
    : IRequest<Result<IReadOnlyList<PermissionDto>>>, IRequirePermission
{
    public string Permission => AccessPermissions.RolesRead;
}

public sealed class ListPermissionsHandler(IAccessRepository repository)
    : IRequestHandler<ListPermissionsQuery, Result<IReadOnlyList<PermissionDto>>>
{
    public async Task<Result<IReadOnlyList<PermissionDto>>> Handle(
        ListPermissionsQuery request, CancellationToken ct) =>
        Result<IReadOnlyList<PermissionDto>>.Success(
            await repository.ListPermissionsAsync(ct));
}

public sealed record SearchAuditQuery(AuditSearchQuery Criteria)
    : IRequest<Result<PagedResult<AuditEntryDto>>>, IRequirePermission
{
    public string Permission => AccessPermissions.AuditRead;
}

public sealed class SearchAuditHandler(IAccessRepository repository)
    : IRequestHandler<SearchAuditQuery, Result<PagedResult<AuditEntryDto>>>
{
    public async Task<Result<PagedResult<AuditEntryDto>>> Handle(
        SearchAuditQuery request, CancellationToken ct) =>
        Result<PagedResult<AuditEntryDto>>.Success(
            await repository.SearchAuditAsync(request.Criteria, ct));
}

public sealed class SearchAuditValidator : AbstractValidator<SearchAuditQuery>
{
    public SearchAuditValidator()
    {
        RuleFor(x => x.Criteria.Page).GreaterThan(0);
        RuleFor(x => x.Criteria.PageSize).InclusiveBetween(1, 200);

        RuleFor(x => x.Criteria)
            .Must(c => c.FromUtc is null || c.ToUtc is null || c.FromUtc <= c.ToUtc)
            .WithMessage("The start of the range must not be after the end.");
    }
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

public sealed record SetLockoutCommand(Guid UserId, SetLockoutRequest Request)
    : IRequest<Result>, IRequirePermission, ITransactional
{
    public string Permission => AccessPermissions.UsersWrite;
}

public sealed class SetLockoutHandler(
    IAccessRepository repository, ICurrentUser currentUser)
    : IRequestHandler<SetLockoutCommand, Result>
{
    public async Task<Result> Handle(SetLockoutCommand request, CancellationToken ct)
    {
        // Refused here as well as in the procedure so the operator gets a
        // useful message rather than a bare failure code. The procedure is what
        // actually guarantees it.
        if (currentUser.UserId is { } actor &&
            !AccessRules.CanActOnSelf(actor, request.UserId) &&
            request.Request.IsLocked)
        {
            return Result.Failure(
                AccessFailureCodes.SelfDemotion,
                "You cannot lock your own account. Ask another administrator.");
        }

        var (succeeded, failureCode) = await repository.SetLockoutAsync(
            request.UserId, request.Request.IsLocked, request.Request.Reason,
            request.Request.LockoutEndUtc, currentUser.UserId, ct);

        return succeeded
            ? Result.Success()
            : Result.Failure(failureCode!, MessageFor(failureCode!));
    }

    private static string MessageFor(string code) => code switch
    {
        AccessFailureCodes.SelfDemotion =>
            "You cannot lock your own account. Ask another administrator.",
        FailureCodes.NotFound => "No such user.",
        _ => "The account could not be updated."
    };
}

public sealed class SetLockoutValidator : AbstractValidator<SetLockoutCommand>
{
    public SetLockoutValidator()
    {
        // A lock without a reason is unauditable — the first question after the
        // fact is always why, and nobody remembers.
        RuleFor(x => x.Request.Reason)
            .NotEmpty().When(x => x.Request.IsLocked)
            .WithMessage("Give a reason for locking this account.")
            .MaximumLength(300);

        RuleFor(x => x.Request.LockoutEndUtc)
            .GreaterThan(_ => DateTime.UtcNow)
            .When(x => x.Request.LockoutEndUtc is not null)
            .WithMessage("A lockout that has already expired does nothing.");
    }
}

public sealed record AssignRoleCommand(Guid UserId, int RoleId)
    : IRequest<Result>, IRequirePermission, ITransactional
{
    public string Permission => AccessPermissions.RolesWrite;
}

public sealed class AssignRoleHandler(
    IAccessRepository repository, ICurrentUser currentUser)
    : IRequestHandler<AssignRoleCommand, Result>
{
    public async Task<Result> Handle(AssignRoleCommand request, CancellationToken ct)
    {
        // Checked here to produce a message naming what is missing, and checked
        // again in the procedure because that is the boundary a support script
        // cannot go around.
        var roles = await repository.ListRolesAsync(ct);
        var target = roles.FirstOrDefault(r => r.RoleId == request.RoleId);

        if (target is null)
            return Result.Failure(FailureCodes.NotFound, "No such role.");

        var missing = AccessRules.MissingToGrant(
            currentUser.Permissions, target.PermissionCodes);

        if (missing.Count > 0)
        {
            // Recorded here because this refusal never reaches the procedure
            // that would otherwise audit it. Somebody probing for a way to
            // escalate must not be invisible until they succeed.
            await repository.RecordSecurityEventAsync(
                currentUser.UserId, "Security.EscalationRefused", "User",
                request.UserId.ToString(),
                JsonSerializer.Serialize(new
                {
                    AttemptedRoleId = request.RoleId,
                    AttemptedRole = target.Name,
                    Operation = "AssignRole",
                    Missing = missing
                }),
                currentUser.IpAddress, ct);

            return Result.Failure(
                AccessFailureCodes.PrivilegeEscalation,
                $"You cannot grant \"{target.Name}\" because it includes "
                + $"permissions you do not hold: {string.Join(", ", missing)}.");
        }

        var (succeeded, failureCode) = await repository.AssignRoleAsync(
            request.UserId, request.RoleId, currentUser.UserId, ct);

        return succeeded
            ? Result.Success()
            : Result.Failure(failureCode!, MessageFor(failureCode!));
    }

    internal static string MessageFor(string code) => code switch
    {
        AccessFailureCodes.PrivilegeEscalation =>
            "You cannot grant access you do not hold yourself.",
        AccessFailureCodes.SelfDemotion =>
            "You cannot change your own access. Ask another administrator.",
        AccessFailureCodes.LastAdministrator =>
            "This is the last administrator. Grant somebody else the role first.",
        FailureCodes.NotFound => "No such user or role.",
        _ => "The role could not be changed."
    };
}

public sealed record RemoveRoleCommand(Guid UserId, int RoleId)
    : IRequest<Result>, IRequirePermission, ITransactional
{
    public string Permission => AccessPermissions.RolesWrite;
}

public sealed class RemoveRoleHandler(
    IAccessRepository repository, ICurrentUser currentUser)
    : IRequestHandler<RemoveRoleCommand, Result>
{
    public async Task<Result> Handle(RemoveRoleCommand request, CancellationToken ct)
    {
        if (currentUser.UserId is { } actor &&
            !AccessRules.CanActOnSelf(actor, request.UserId))
        {
            return Result.Failure(
                AccessFailureCodes.SelfDemotion,
                "You cannot remove your own access. Ask another administrator.");
        }

        var (succeeded, failureCode) = await repository.RemoveRoleAsync(
            request.UserId, request.RoleId, currentUser.UserId, ct);

        return succeeded
            ? Result.Success()
            : Result.Failure(failureCode!, AssignRoleHandler.MessageFor(failureCode!));
    }
}

public sealed record RevokeSessionsCommand(Guid UserId, RevokeSessionsRequest Request)
    : IRequest<Result>, IRequirePermission, ITransactional
{
    public string Permission => AccessPermissions.UsersWrite;
}

public sealed class RevokeSessionsHandler(
    IAccessRepository repository, ICurrentUser currentUser)
    : IRequestHandler<RevokeSessionsCommand, Result>
{
    public async Task<Result> Handle(
        RevokeSessionsCommand request, CancellationToken ct)
    {
        var (succeeded, failureCode) = await repository.RevokeSessionsAsync(
            request.UserId, request.Request.Reason, currentUser.UserId, ct);

        return succeeded
            ? Result.Success()
            : Result.Failure(failureCode!, "The sessions could not be revoked.");
    }
}

public sealed record SaveRoleCommand(SaveRoleRequest Request)
    : IRequest<Result<int>>, IRequirePermission, ITransactional
{
    public string Permission => AccessPermissions.RolesWrite;
}

public sealed class SaveRoleHandler(
    IAccessRepository repository, ICurrentUser currentUser)
    : IRequestHandler<SaveRoleCommand, Result<int>>
{
    public async Task<Result<int>> Handle(SaveRoleCommand request, CancellationToken ct)
    {
        var (succeeded, failureCode, roleId) = await repository.SaveRoleAsync(
            request.Request.RoleId, request.Request.Name,
            request.Request.Description, currentUser.UserId, ct);

        return succeeded
            ? Result<int>.Success(roleId!.Value)
            : Result<int>.Failure(failureCode!, failureCode switch
            {
                AccessFailureCodes.SystemRole =>
                    "A built-in role cannot be renamed.",
                ContentFailureCodes.DuplicateKey =>
                    "A role with that name already exists.",
                _ => "The role could not be saved."
            });
    }
}

public sealed class SaveRoleValidator : AbstractValidator<SaveRoleCommand>
{
    public SaveRoleValidator()
    {
        RuleFor(x => x.Request.Name)
            .NotEmpty().MaximumLength(100)
            .Matches("^[A-Za-z][A-Za-z0-9 _-]*$")
            .WithMessage(
                "A role name starts with a letter and uses only letters, "
                + "digits, spaces, dashes and underscores.");

        RuleFor(x => x.Request.Description).MaximumLength(400);
    }
}

public sealed record DeleteRoleCommand(int RoleId)
    : IRequest<Result>, IRequirePermission, ITransactional
{
    public string Permission => AccessPermissions.RolesWrite;
}

public sealed class DeleteRoleHandler(
    IAccessRepository repository, ICurrentUser currentUser)
    : IRequestHandler<DeleteRoleCommand, Result>
{
    public async Task<Result> Handle(DeleteRoleCommand request, CancellationToken ct)
    {
        var (succeeded, failureCode) = await repository.DeleteRoleAsync(
            request.RoleId, currentUser.UserId, ct);

        return succeeded
            ? Result.Success()
            : Result.Failure(failureCode!, failureCode switch
            {
                AccessFailureCodes.SystemRole =>
                    "A built-in role cannot be deleted.",
                AccessFailureCodes.RoleInUse =>
                    "This role still has members. Remove them first so you can "
                    + "see whose access changes.",
                _ => "The role could not be deleted."
            });
    }
}

public sealed record SetRolePermissionsCommand(
    int RoleId, SetRolePermissionsRequest Request)
    : IRequest<Result>, IRequirePermission, ITransactional
{
    public string Permission => AccessPermissions.RolesWrite;
}

public sealed class SetRolePermissionsHandler(
    IAccessRepository repository, ICurrentUser currentUser)
    : IRequestHandler<SetRolePermissionsCommand, Result>
{
    public async Task<Result> Handle(
        SetRolePermissionsCommand request, CancellationToken ct)
    {
        // Unknown codes are checked BEFORE escalation. A typo would otherwise
        // look exactly like an attempt to grant something the caller lacks —
        // reported to the operator as a privilege escalation and filed as a
        // false security event, for what is really a misspelling.
        var known = (await repository.ListPermissionsAsync(ct))
            .Select(p => p.Code).ToHashSet(StringComparer.Ordinal);

        var unknown = request.Request.PermissionCodes
            .Where(c => !known.Contains(c)).ToList();

        if (unknown.Count > 0)
        {
            return Result.Failure(
                AccessFailureCodes.UnknownPermission,
                "No such permission: " + string.Join(", ", unknown) + ".");
        }

        // Editing a role is the indirect route to granting yourself anything.
        // It has to be closed in the same place as the direct route.
        var missing = AccessRules.MissingToGrant(
            currentUser.Permissions, request.Request.PermissionCodes);

        if (missing.Count > 0)
        {
            await repository.RecordSecurityEventAsync(
                currentUser.UserId, "Security.EscalationRefused", "Role",
                request.RoleId.ToString(CultureInfo.InvariantCulture),
                JsonSerializer.Serialize(new
                {
                    Operation = "SetRolePermissions",
                    Missing = missing
                }),
                currentUser.IpAddress, ct);

            return Result.Failure(
                AccessFailureCodes.PrivilegeEscalation,
                "You cannot grant permissions you do not hold yourself: "
                + string.Join(", ", missing) + ".");
        }

        var json = JsonSerializer.Serialize(request.Request.PermissionCodes);

        var (succeeded, failureCode) = await repository.SetRolePermissionsAsync(
            request.RoleId, json, currentUser.UserId, ct);

        return succeeded
            ? Result.Success()
            : Result.Failure(failureCode!, failureCode switch
            {
                AccessFailureCodes.PrivilegeEscalation =>
                    "You cannot grant permissions you do not hold yourself.",
                AccessFailureCodes.UnknownPermission =>
                    "One of those permission codes does not exist.",
                _ => "The permissions could not be saved."
            });
    }
}

public sealed class SetRolePermissionsValidator
    : AbstractValidator<SetRolePermissionsCommand>
{
    public SetRolePermissionsValidator()
    {
        RuleFor(x => x.Request.PermissionCodes)
            .NotNull()
            // An empty set is legitimate — it is how a role is emptied before
            // deletion — but duplicates mean the caller built the list wrong.
            .Must(codes => codes.Distinct().Count() == codes.Count)
            .WithMessage("The same permission appears more than once.");
    }
}
