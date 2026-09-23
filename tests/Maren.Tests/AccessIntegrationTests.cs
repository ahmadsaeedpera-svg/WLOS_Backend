using Dapper;
using FluentAssertions;
using Maren.Application.Access;
using Maren.Application.Behaviors;
using Maren.Contracts;
using Maren.Domain;
using MediatR;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Maren.Tests;

/// <summary>
/// Fixtures for the access slice: three accounts and two roles of deliberately
/// different strength.
/// </summary>
/// <remarks>
/// Created directly in SQL rather than through the registration endpoint. These
/// need specific permission sets, and going through registration would mean
/// granting them by the very API under test.
/// </remarks>
public sealed class AccessFixture
{
    public const string Prefix = "xtest-access-";

    public Guid StrongUserId { get; } = Guid.NewGuid();
    public Guid WeakUserId { get; } = Guid.NewGuid();
    public Guid TargetUserId { get; } = Guid.NewGuid();
    public int StrongRoleId { get; private set; }
    public int WeakRoleId { get; private set; }

    public IReadOnlyList<string> AllPermissions { get; private set; } = [];

    public AccessFixture()
    {
        using var connection = DatabaseFixture.Open();
        CleanUp(connection);

        connection.Execute("""
            INSERT INTO [Identity].[User]
                (UserId, Email, NormalisedEmail, SecurityStamp, LanguageCode,
                 IsEmailConfirmed, IsLockedOut, FailedLoginCount, IsDeleted)
            VALUES
                (@Strong, @StrongEmail, UPPER(@StrongEmail), NEWID(), 'en-GB', 1, 0, 0, 0),
                (@Weak,   @WeakEmail,   UPPER(@WeakEmail),   NEWID(), 'en-GB', 1, 0, 0, 0),
                (@Target, @TargetEmail, UPPER(@TargetEmail), NEWID(), 'en-GB', 1, 0, 0, 0);
            """, new
        {
            Strong = StrongUserId, StrongEmail = Prefix + "strong@test",
            Weak = WeakUserId, WeakEmail = Prefix + "weak@test",
            Target = TargetUserId, TargetEmail = Prefix + "target@test"
        });

        StrongRoleId = connection.QuerySingle<int>("""
            INSERT INTO [Identity].[Role] (Name, Description, IsSystem)
            OUTPUT INSERTED.RoleId VALUES (@Name, 'Fixture', 0);
            """, new { Name = Prefix + "strong" });

        WeakRoleId = connection.QuerySingle<int>("""
            INSERT INTO [Identity].[Role] (Name, Description, IsSystem)
            OUTPUT INSERTED.RoleId VALUES (@Name, 'Fixture', 0);
            """, new { Name = Prefix + "weak" });

        connection.Execute("""
            INSERT INTO [Identity].[RolePermission] (RoleId, PermissionId)
            SELECT @Strong, PermissionId FROM [Identity].[Permission];

            INSERT INTO [Identity].[RolePermission] (RoleId, PermissionId)
            SELECT @Weak, PermissionId FROM [Identity].[Permission]
            WHERE Code IN ('content.read', 'users.read', 'roles.read',
                           'roles.write', 'users.write', 'audit.read');

            INSERT INTO [Identity].[UserRole] (UserId, RoleId)
            VALUES (@StrongUser, @Strong), (@WeakUser, @Weak);
            """, new
        {
            Strong = StrongRoleId, Weak = WeakRoleId,
            StrongUser = StrongUserId, WeakUser = WeakUserId
        });

        AllPermissions = connection
            .Query<string>("SELECT Code FROM [Identity].[Permission]").ToList();
    }

    /// <summary>
    /// The weak fixture deliberately holds roles.write and users.write.
    /// </summary>
    /// <remarks>
    /// That is the whole point: it can reach every endpoint in the slice, so
    /// what stops it escalating is the permission-superset rule rather than the
    /// endpoint gate. Testing with an account that cannot call the endpoint at
    /// all would prove nothing about escalation.
    /// </remarks>
    public IReadOnlyList<string> WeakPermissions =>
    [
        "content.read", "users.read", "roles.read",
        "roles.write", "users.write", "audit.read"
    ];

    public static void CleanUp(System.Data.IDbConnection connection)
    {
        connection.Execute("""
            DELETE FROM [Identity].[SecurityStampRevocation]
            WHERE UserId IN (SELECT UserId FROM [Identity].[User]
                             WHERE Email LIKE @Pattern);

            DELETE FROM [Identity].[RefreshToken]
            WHERE UserId IN (SELECT UserId FROM [Identity].[User]
                             WHERE Email LIKE @Pattern);

            DELETE FROM [Identity].[UserRole]
            WHERE UserId IN (SELECT UserId FROM [Identity].[User]
                             WHERE Email LIKE @Pattern);

            DELETE FROM [Audit].[AuditLog]
            WHERE ActorUserId IN (SELECT UserId FROM [Identity].[User]
                                  WHERE Email LIKE @Pattern);

            DELETE FROM [Identity].[User] WHERE Email LIKE @Pattern;

            DELETE FROM [Identity].[RolePermission]
            WHERE RoleId IN (SELECT RoleId FROM [Identity].[Role]
                             WHERE Name LIKE @Pattern);

            DELETE FROM [Identity].[Role] WHERE Name LIKE @Pattern;
            """, new { Pattern = Prefix + "%" });
    }
}

[Collection("database")]
public sealed class AccessEscalationTests : IAsyncLifetime
{
    private readonly DatabaseFixture _fixture;
    private AccessFixture _access = null!;

    public AccessEscalationTests(DatabaseFixture fixture) => _fixture = fixture;

    public Task InitializeAsync()
    {
        _access = new AccessFixture();
        return Task.CompletedTask;
    }

    public Task DisposeAsync()
    {
        using var connection = DatabaseFixture.Open();
        AccessFixture.CleanUp(connection);
        _fixture.CurrentUser.WithAllPermissions();
        _fixture.CurrentUser.UserId =
            Guid.Parse("11111111-1111-1111-1111-111111111111");
        return Task.CompletedTask;
    }

    private ISender Sender => _fixture.Provider.GetRequiredService<ISender>();

    private void ActAsWeak()
    {
        _fixture.CurrentUser.UserId = _access.WeakUserId;
        _fixture.CurrentUser.Permissions = _access.WeakPermissions.ToList();
    }

    private void ActAsStrong()
    {
        _fixture.CurrentUser.UserId = _access.StrongUserId;
        _fixture.CurrentUser.Permissions = _access.AllPermissions.ToList();
    }

    // -----------------------------------------------------------------------

    [Fact]
    public async Task An_actor_cannot_assign_a_role_stronger_than_their_own()
    {
        // The single most important test in the slice. Without this rule,
        // holding roles.write is holding every permission: assign yourself the
        // strongest role and the check meant to stop you is the one you used.
        ActAsWeak();

        var result = await Sender.Send(new AssignRoleCommand(
            _access.TargetUserId, _access.StrongRoleId));

        result.Succeeded.Should().BeFalse();
        result.FailureCode.Should().Be(AccessFailureCodes.PrivilegeEscalation);

        // The message names what is missing, so an operator knows what to ask
        // for rather than filing a support ticket saying "forbidden".
        result.Message.Should().Contain("users.delete");

        using var connection = DatabaseFixture.Open();
        connection.QuerySingle<int>(
            "SELECT COUNT(*) FROM [Identity].[UserRole] WHERE UserId=@U AND RoleId=@R",
            new { U = _access.TargetUserId, R = _access.StrongRoleId })
            .Should().Be(0, "the refused grant must not have landed");
    }

    [Fact]
    public async Task An_actor_can_assign_a_role_they_fully_hold()
    {
        ActAsWeak();

        var result = await Sender.Send(new AssignRoleCommand(
            _access.TargetUserId, _access.WeakRoleId));

        result.Succeeded.Should().BeTrue(result.Message);
    }

    [Fact]
    public async Task An_actor_cannot_grant_permissions_they_lack_via_a_role()
    {
        // The indirect route to the same escalation: rather than assigning a
        // strong role, edit a weak one to contain strong permissions.
        ActAsWeak();

        var result = await Sender.Send(new SetRolePermissionsCommand(
            _access.WeakRoleId,
            new SetRolePermissionsRequest(["users.delete", "content.publish"])));

        result.Succeeded.Should().BeFalse();
        result.FailureCode.Should().Be(AccessFailureCodes.PrivilegeEscalation);
    }

    [Fact]
    public async Task An_actor_cannot_remove_their_own_access()
    {
        // An availability rule. It stops the only administrator removing their
        // own role and leaving raw SQL as the recovery path.
        ActAsStrong();

        var result = await Sender.Send(new RemoveRoleCommand(
            _access.StrongUserId, _access.StrongRoleId));

        result.Succeeded.Should().BeFalse();
        result.FailureCode.Should().Be(AccessFailureCodes.SelfDemotion);
    }

    [Fact]
    public async Task An_actor_cannot_lock_themselves_out()
    {
        ActAsStrong();

        var result = await Sender.Send(new SetLockoutCommand(
            _access.StrongUserId,
            new SetLockoutRequest(true, "Testing", null)));

        result.Succeeded.Should().BeFalse();
        result.FailureCode.Should().Be(AccessFailureCodes.SelfDemotion);
    }

    [Fact]
    public async Task A_built_in_role_cannot_be_deleted()
    {
        ActAsStrong();

        using var connection = DatabaseFixture.Open();
        var superAdminId = connection.QuerySingle<int>(
            "SELECT RoleId FROM [Identity].[Role] WHERE Name = 'SuperAdmin'");

        var result = await Sender.Send(new DeleteRoleCommand(superAdminId));

        result.Succeeded.Should().BeFalse();
        result.FailureCode.Should().Be(AccessFailureCodes.SystemRole);
    }

    [Fact]
    public async Task A_role_with_members_cannot_be_deleted()
    {
        // Deleting it would silently strip access from everyone holding it.
        ActAsStrong();

        var result = await Sender.Send(new DeleteRoleCommand(_access.WeakRoleId));

        result.Succeeded.Should().BeFalse();
        result.FailureCode.Should().Be(AccessFailureCodes.RoleInUse);
    }

    [Fact]
    public async Task An_unknown_permission_code_is_refused()
    {
        // Silently dropping it would leave the operator believing they granted
        // something they did not.
        ActAsStrong();

        var result = await Sender.Send(new SetRolePermissionsCommand(
            _access.WeakRoleId,
            new SetRolePermissionsRequest(["content.read", "not.a.permission"])));

        result.Succeeded.Should().BeFalse();
        result.FailureCode.Should().Be(AccessFailureCodes.UnknownPermission);
    }

    [Fact]
    public async Task A_refused_escalation_is_audited()
    {
        // Auditing only successes means somebody probing for a way to escalate
        // is invisible until they find one.
        ActAsWeak();

        await Sender.Send(new AssignRoleCommand(
            _access.TargetUserId, _access.StrongRoleId));

        using var connection = DatabaseFixture.Open();
        connection.QuerySingle<int>("""
            SELECT COUNT(*) FROM [Audit].[AuditLog]
            WHERE ActorUserId = @Actor AND [Action] = 'Security.EscalationRefused'
            """, new { Actor = _access.WeakUserId })
            .Should().BeGreaterThan(0);
    }
}

// ---------------------------------------------------------------------------

[Collection("database")]
public sealed class AccessAdministrationTests : IAsyncLifetime
{
    private readonly DatabaseFixture _fixture;
    private AccessFixture _access = null!;

    public AccessAdministrationTests(DatabaseFixture fixture) => _fixture = fixture;

    public Task InitializeAsync()
    {
        _access = new AccessFixture();
        _fixture.CurrentUser.UserId = _access.StrongUserId;
        _fixture.CurrentUser.Permissions = _access.AllPermissions.ToList();
        return Task.CompletedTask;
    }

    public Task DisposeAsync()
    {
        using var connection = DatabaseFixture.Open();
        AccessFixture.CleanUp(connection);
        _fixture.CurrentUser.WithAllPermissions();
        _fixture.CurrentUser.UserId =
            Guid.Parse("11111111-1111-1111-1111-111111111111");
        return Task.CompletedTask;
    }

    private ISender Sender => _fixture.Provider.GetRequiredService<ISender>();

    [Fact]
    public async Task Locking_an_account_rotates_its_security_stamp()
    {
        // An account locked while its owner is signed in must not stay usable
        // for the life of their access token.
        using var connection = DatabaseFixture.Open();
        var before = connection.QuerySingle<Guid>(
            "SELECT SecurityStamp FROM [Identity].[User] WHERE UserId = @U",
            new { U = _access.TargetUserId });

        var result = await Sender.Send(new SetLockoutCommand(
            _access.TargetUserId,
            new SetLockoutRequest(true, "Compromised credentials", null)));

        result.Succeeded.Should().BeTrue(result.Message);

        var after = connection.QuerySingle<Guid>(
            "SELECT SecurityStamp FROM [Identity].[User] WHERE UserId = @U",
            new { U = _access.TargetUserId });

        after.Should().NotBe(before);

        connection.QuerySingle<int>(
            "SELECT COUNT(*) FROM [Identity].[SecurityStampRevocation] WHERE UserId=@U",
            new { U = _access.TargetUserId })
            .Should().Be(1);
    }

    [Fact]
    public async Task A_lock_requires_a_reason()
    {
        // The first question after the fact is always why, and nobody
        // remembers.
        var validator = new SetLockoutValidator();

        var result = await validator.ValidateAsync(new SetLockoutCommand(
            _access.TargetUserId, new SetLockoutRequest(true, null, null)));

        result.IsValid.Should().BeFalse();
    }

    [Fact]
    public async Task Unlocking_clears_the_failed_login_counter()
    {
        // Leaving it would re-lock the account on the next single mistyped
        // password.
        using var connection = DatabaseFixture.Open();
        connection.Execute(
            "UPDATE [Identity].[User] SET FailedLoginCount = 9 WHERE UserId = @U",
            new { U = _access.TargetUserId });

        await Sender.Send(new SetLockoutCommand(
            _access.TargetUserId, new SetLockoutRequest(false, null, null)));

        connection.QuerySingle<int>(
            "SELECT FailedLoginCount FROM [Identity].[User] WHERE UserId = @U",
            new { U = _access.TargetUserId })
            .Should().Be(0);
    }

    [Fact]
    public async Task User_search_never_returns_password_material()
    {
        // Identity.User holds PasswordHash, PasswordSalt and
        // PasswordIterations. A SELECT * in any of these procedures would put
        // them on the wire to a browser.
        var result = await Sender.Send(new SearchUsersQuery(
            new UserSearchQuery(Query: AccessFixture.Prefix, PageSize: 50)));

        result.Succeeded.Should().BeTrue();
        result.Value!.Items.Should().HaveCount(3);

        var properties = typeof(UserListItemDto).GetProperties()
            .Select(p => p.Name).ToList();

        properties.Should().NotContain(n => n.Contains("Password"));
        properties.Should().NotContain("SecurityStamp");
    }

    [Fact]
    public void No_procedure_outside_the_login_path_touches_password_material()
    {
        // The static backstop. Catches somebody "fixing" a procedure with
        // SELECT * on Identity.User.
        //
        // The list is the login path, not a convenience allow-list, and every
        // name on it has to be a procedure whose whole job is a credential:
        //
        //   usp_User_GetForLogin       verify a password by email (sign in)
        //   usp_User_Register          set the first password
        //   usp_User_GetLoginMaterial  verify a password by user id, for an
        //                              already-authenticated caller confirming
        //                              an irreversible action. Exists because
        //                              the alternative was an authenticated
        //                              endpoint asking a client for an email
        //                              address to identify an account the
        //                              token already names.
        //   usp_User_SetPassword       replace stored material — the rehash-on-
        //                              login upgrade, and password change later
        //
        // Anything else appearing here is the defect this test was written for.
        using var connection = DatabaseFixture.Open();

        var offenders = connection.Query<string>("""
            SELECT o.name
            FROM sys.sql_modules m
            JOIN sys.objects o ON o.object_id = m.object_id
            WHERE o.type = 'P'
              AND o.name NOT IN (
                  'usp_User_GetForLogin', 'usp_User_Register',
                  'usp_User_GetLoginMaterial', 'usp_User_SetPassword')
              AND (m.definition LIKE '%PasswordHash%'
                OR m.definition LIKE '%PasswordSalt%')
            """).ToList();

        offenders.Should().BeEmpty();
    }

    [Fact]
    public async Task User_detail_returns_roles_devices_and_activity()
    {
        await Sender.Send(new AssignRoleCommand(
            _access.TargetUserId, _access.WeakRoleId));

        var result = await Sender.Send(new GetUserQuery(_access.TargetUserId));

        result.Succeeded.Should().BeTrue(result.Message);
        result.Value!.Roles.Should().ContainSingle();
        result.Value.Email.Should().StartWith(AccessFixture.Prefix);
    }

    [Fact]
    public async Task Roles_come_back_with_their_permission_grants()
    {
        // The portal renders a matrix. Fetching grants per role would be one
        // request per row of the grid.
        var result = await Sender.Send(new ListRolesQuery());

        result.Succeeded.Should().BeTrue();

        var strong = result.Value!.Single(r => r.RoleId == _access.StrongRoleId);
        strong.PermissionCodes.Should().Contain("users.delete");
        strong.PermissionCount.Should().Be(strong.PermissionCodes.Count);
    }

    [Fact]
    public async Task A_role_can_be_created_renamed_and_emptied()
    {
        var created = await Sender.Send(new SaveRoleCommand(
            new SaveRoleRequest(null, AccessFixture.Prefix + "temp", "Fixture")));

        created.Succeeded.Should().BeTrue(created.Message);

        var renamed = await Sender.Send(new SaveRoleCommand(
            new SaveRoleRequest(created.Value, AccessFixture.Prefix + "temp2", null)));

        renamed.Succeeded.Should().BeTrue(renamed.Message);

        // An empty permission set is legitimate — it is how a role is emptied
        // before deletion.
        var emptied = await Sender.Send(new SetRolePermissionsCommand(
            created.Value, new SetRolePermissionsRequest([])));

        emptied.Succeeded.Should().BeTrue(emptied.Message);

        var deleted = await Sender.Send(new DeleteRoleCommand(created.Value));
        deleted.Succeeded.Should().BeTrue(deleted.Message);
    }

    [Fact]
    public async Task Every_administrative_command_is_audited()
    {
        await Sender.Send(new SetLockoutCommand(
            _access.TargetUserId, new SetLockoutRequest(true, "Audit test", null)));

        await Sender.Send(new AssignRoleCommand(
            _access.TargetUserId, _access.WeakRoleId));

        var audit = await Sender.Send(new SearchAuditQuery(
            new AuditSearchQuery(ActorUserId: _access.StrongUserId, PageSize: 50)));

        audit.Succeeded.Should().BeTrue();

        var actions = audit.Value!.Items.Select(a => a.Action).ToList();
        actions.Should().Contain("User.Lock");
        actions.Should().Contain("User.RoleAssigned");

        // The actor's email is resolved so the trail is readable without a
        // second lookup per row.
        audit.Value.Items.Should().AllSatisfy(
            a => a.ActorEmail.Should().StartWith(AccessFixture.Prefix));
    }

    [Fact]
    public async Task Audit_search_rejects_a_backwards_date_range()
    {
        var validator = new SearchAuditValidator();

        var result = await validator.ValidateAsync(new SearchAuditQuery(
            new AuditSearchQuery(
                FromUtc: DateTime.UtcNow,
                ToUtc: DateTime.UtcNow.AddDays(-1))));

        result.IsValid.Should().BeFalse();
    }

    [Fact]
    public async Task Revoking_sessions_records_the_current_stamp()
    {
        await Sender.Send(new RevokeSessionsCommand(
            _access.TargetUserId, new RevokeSessionsRequest("Left the company")));

        using var connection = DatabaseFixture.Open();

        var (stored, current) = connection.QuerySingle<(Guid, Guid)>("""
            SELECT r.SecurityStamp, u.SecurityStamp
            FROM [Identity].[SecurityStampRevocation] r
            JOIN [Identity].[User] u ON u.UserId = r.UserId
            WHERE r.UserId = @U
            """, new { U = _access.TargetUserId });

        stored.Should().Be(current,
            "the revocation must name the stamp that is now current, or every "
            + "freshly issued token would be refused as stale");
    }
}

// ---------------------------------------------------------------------------

/// <summary>
/// The revocation check itself.
/// </summary>
[Collection("database")]
public sealed class SecurityStampValidatorTests : IAsyncLifetime
{
    private readonly DatabaseFixture _fixture;
    private AccessFixture _access = null!;

    public SecurityStampValidatorTests(DatabaseFixture fixture) => _fixture = fixture;

    public Task InitializeAsync()
    {
        _access = new AccessFixture();
        return Task.CompletedTask;
    }

    public Task DisposeAsync()
    {
        using var connection = DatabaseFixture.Open();
        AccessFixture.CleanUp(connection);
        return Task.CompletedTask;
    }

    [Fact]
    public async Task A_user_who_was_never_revoked_is_always_current()
    {
        // The common path. Most accounts have no revocation row at all, and
        // the check must not cost them anything or refuse them.
        // AsyncServiceScope, not IServiceScope: SqlUnitOfWork is
        // IAsyncDisposable only, and a synchronous Dispose on the scope throws.
        await using var scope = _fixture.Provider.CreateAsyncScope();
        var validator = scope.ServiceProvider
            .GetRequiredService<Maren.Application.Access.ISecurityStampValidator>();

        var result = await validator.IsCurrentAsync(
            _access.TargetUserId, Guid.NewGuid(), CancellationToken.None);

        result.Should().BeTrue();
    }

    [Fact]
    public async Task A_stale_stamp_is_refused_after_revocation()
    {
        using var connection = DatabaseFixture.Open();

        var staleStamp = connection.QuerySingle<Guid>(
            "SELECT SecurityStamp FROM [Identity].[User] WHERE UserId = @U",
            new { U = _access.TargetUserId });

        connection.Execute(
            "[Identity].[usp_Access_RotateSecurityStamp]",
            new { UserId = _access.TargetUserId, ActorUserId = (Guid?)null,
                  Reason = "Test" },
            commandType: System.Data.CommandType.StoredProcedure);

        // A fresh scope, because the previous one's cache would still hold the
        // pre-revocation snapshot — which is the documented 30-second window.
        // AsyncServiceScope, not IServiceScope: SqlUnitOfWork is
        // IAsyncDisposable only, and a synchronous Dispose on the scope throws.
        await using var scope = _fixture.Provider.CreateAsyncScope();
        var cache = scope.ServiceProvider.GetRequiredService<IQueryCache>();
        cache.Remove("security:revocations");

        var validator = scope.ServiceProvider
            .GetRequiredService<Maren.Application.Access.ISecurityStampValidator>();

        (await validator.IsCurrentAsync(
            _access.TargetUserId, staleStamp, CancellationToken.None))
            .Should().BeFalse("the token predates the revocation");

        var currentStamp = connection.QuerySingle<Guid>(
            "SELECT SecurityStamp FROM [Identity].[User] WHERE UserId = @U",
            new { U = _access.TargetUserId });

        (await validator.IsCurrentAsync(
            _access.TargetUserId, currentStamp, CancellationToken.None))
            .Should().BeTrue("a token issued after the revocation is fine");
    }
}

// ---------------------------------------------------------------------------

public sealed class AccessRulesTests
{
    [Fact]
    public void CanGrant_is_a_superset_check()
    {
        AccessRules.CanGrant(["a", "b", "c"], ["a", "b"]).Should().BeTrue();
        AccessRules.CanGrant(["a"], ["a", "b"]).Should().BeFalse();
        AccessRules.CanGrant([], []).Should().BeTrue();
    }

    [Fact]
    public void MissingToGrant_names_what_is_absent()
    {
        // The message an operator sees. "You cannot grant users.delete" tells
        // them what to ask for; "forbidden" starts a support ticket.
        AccessRules.MissingToGrant(["a"], ["a", "c", "b"])
            .Should().BeEquivalentTo(["b", "c"], o => o.WithStrictOrdering());
    }

    [Fact]
    public void CanActOnSelf_is_always_false()
    {
        var id = Guid.NewGuid();
        AccessRules.CanActOnSelf(id, id).Should().BeFalse();
        AccessRules.CanActOnSelf(id, Guid.NewGuid()).Should().BeTrue();
    }
}
