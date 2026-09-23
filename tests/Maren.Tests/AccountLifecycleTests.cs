using Dapper;
using FluentAssertions;
using Maren.Application.Abstractions;
using Maren.Application.Auth;
using Maren.Contracts;
using Maren.Shared;
using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.Extensions.DependencyInjection;

namespace Maren.Tests;

/// <summary>
/// Registration behind the age gate, signing out, and leaving for good.
/// </summary>
/// <remarks>
/// <para>
/// Slice 1 of WLOS. Everything here goes through the real handlers and the real
/// procedures: the age gate lives in <c>Identity.usp_User_Register</c> and the
/// erasure in <c>Identity.usp_User_DeleteAccount</c>, and a suite that mocked
/// <c>IAuthRepository</c> would prove only that the mocks agree with each other.
/// </para>
/// <para>
/// Every account created here carries <see cref="Prefix"/> in its email so the
/// class can clean up after itself on the way in and be re-run in any order.
/// </para>
/// </remarks>
[Collection("database")]
public sealed class AccountLifecycleTests(DatabaseFixture fixture) : IAsyncLifetime
{
    private const string Prefix = "slice1-test-";
    private const string GoodPassword = "a long enough passphrase";

    public async Task InitializeAsync() => await CleanupAsync();

    public Task DisposeAsync() => Task.CompletedTask;

    private static string NewEmail() => Prefix + Guid.NewGuid().ToString("N") + "@example.com";

    private static DateOnly Aged(int years) =>
        DateOnly.FromDateTime(DateTime.UtcNow.AddYears(-years));

    private ISender Sender(IServiceScope scope) =>
        scope.ServiceProvider.GetRequiredService<ISender>();

    /// <summary>
    /// Removes every account this class has ever made, and everything behind it.
    /// </summary>
    /// <remarks>
    /// Deliberately does not call <c>usp_User_DeleteAccount</c>. Tearing down
    /// with the procedure under test would mean a broken erasure cleaned up
    /// after itself and left the next run looking green.
    /// </remarks>
    private static async Task CleanupAsync()
    {
        using var connection = DatabaseFixture.Open();
        await connection.ExecuteAsync(
            """
            DECLARE @ids TABLE (UserId UNIQUEIDENTIFIER PRIMARY KEY);
            INSERT @ids SELECT UserId FROM [Identity].[User] WHERE Email LIKE @p;

            DELETE FROM [Identity].[SecurityStampRevocation] WHERE UserId IN (SELECT UserId FROM @ids);

            /*  And the tombstone revocations left by earlier runs.

                Those belong to accounts this class deleted, so the user row
                they name is already gone and the @ids lookup above — which
                reads Identity.User by email — cannot see them. The procedure
                prunes them after a day; a test suite should not wait a day.
                Scoped to orphans so a real revocation on a live account is
                never touched. */
            DELETE r
            FROM [Identity].[SecurityStampRevocation] r
            WHERE r.Reason = 'Account deleted'
              AND NOT EXISTS (SELECT 1 FROM [Identity].[User] u
                              WHERE u.UserId = r.UserId);
            DELETE FROM [Identity].[RefreshToken]            WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Identity].[Device]                  WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Identity].[UserRoleMode]            WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Identity].[UserLifeStage]           WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Identity].[UserRole]                WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Identity].[Profile]                 WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Audit].[AuditLog]                   WHERE ActorUserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Identity].[User]                    WHERE UserId IN (SELECT UserId FROM @ids);
            """,
            new { p = Prefix + "%" });
    }

    private async Task<(Guid UserId, AuthResponse Session, string Email)> RegisterAsync(
        int age = 30)
    {
        var email = NewEmail();
        await using var scope = fixture.Provider.CreateAsyncScope();
        var result = await Sender(scope).Send(new RegisterCommand(
            new RegisterRequest(email, GoodPassword, Aged(age), "GB", "en-GB")));

        result.Succeeded.Should().BeTrue(
            "registration of an adult with a valid address must succeed");
        return (result.Value!.UserId, result.Value, email);
    }

    // -----------------------------------------------------------------------
    // The age gate
    // -----------------------------------------------------------------------

    [Fact]
    public async Task An_adult_can_register_and_her_date_of_birth_is_kept()
    {
        var (userId, session, _) = await RegisterAsync(age: 30);

        session.AccessToken.Should().NotBeNullOrWhiteSpace();
        session.RefreshToken.Should().NotBeNullOrWhiteSpace();

        using var connection = DatabaseFixture.Open();
        var stored = await connection.QuerySingleAsync<DateTime?>(
            "SELECT DateOfBirth FROM [Identity].[Profile] WHERE UserId = @userId",
            new { userId });

        stored.Should().NotBeNull(
            "the date of birth is collected at registration, not left for "
            + "onboarding to ask for later");
    }

    [Fact]
    public async Task Someone_under_the_launch_age_is_refused()
    {
        await using var scope = fixture.Provider.CreateAsyncScope();
        var result = await Sender(scope).Send(new RegisterCommand(
            new RegisterRequest(NewEmail(), GoodPassword, Aged(15), "GB", "en-GB")));

        result.Succeeded.Should().BeFalse();
        result.FailureCode.Should().Be(FailureCodes.UnderMinimumAge);
    }

    [Fact]
    public async Task A_refused_registration_leaves_nothing_behind()
    {
        var email = NewEmail();
        await using var scope = fixture.Provider.CreateAsyncScope();
        await Sender(scope).Send(new RegisterCommand(
            new RegisterRequest(email, GoodPassword, Aged(14), "GB", "en-GB")));

        using var connection = DatabaseFixture.Open();

        var users = await connection.QuerySingleAsync<int>(
            "SELECT COUNT(*) FROM [Identity].[User] WHERE Email = @email",
            new { email });
        users.Should().Be(0);

        /*  And no audit row naming her either. Recording a refused under-age
            attempt would mean keeping a child's email address and date of
            birth as the permanent record of having turned her away, which is
            the opposite of what the gate is for. */
        var audit = await connection.QuerySingleAsync<int>(
            """
            SELECT COUNT(*) FROM [Audit].[AuditLog]
            WHERE EntityId LIKE '%' AND [Action] = 'User.Register'
              AND ActorUserId NOT IN (SELECT UserId FROM [Identity].[User])
            """);
        audit.Should().Be(0,
            "a refused registration must not leave an orphan audit row");
    }

    [Fact]
    public async Task The_gate_holds_on_the_day_before_her_birthday()
    {
        // 18 years old tomorrow. DATEDIFF(YEAR, ...) counts year boundaries
        // crossed rather than birthdays reached, and would let this through.
        var dayBefore = DateOnly.FromDateTime(
            DateTime.UtcNow.Date.AddYears(-18).AddDays(1));

        await using var scope = fixture.Provider.CreateAsyncScope();
        var result = await Sender(scope).Send(new RegisterCommand(
            new RegisterRequest(NewEmail(), GoodPassword, dayBefore, "GB", "en-GB")));

        result.Succeeded.Should().BeFalse();
        result.FailureCode.Should().Be(FailureCodes.UnderMinimumAge);
    }

    [Fact]
    public async Task The_gate_lets_her_in_on_her_eighteenth_birthday()
    {
        var birthday = DateOnly.FromDateTime(DateTime.UtcNow.Date.AddYears(-18));

        await using var scope = fixture.Provider.CreateAsyncScope();
        var result = await Sender(scope).Send(new RegisterCommand(
            new RegisterRequest(NewEmail(), GoodPassword, birthday, "GB", "en-GB")));

        result.Succeeded.Should().BeTrue(
            "the gate is 18 and over, and on the day itself she is 18");
    }

    [Fact]
    public async Task She_cannot_lower_her_age_past_the_gate_afterwards()
    {
        /*  Registration is not the only door. Without the same check in
            usp_Profile_Save the gate is defeated by registering at a date that
            clears it and then saving a real one. */
        var (userId, _, _) = await RegisterAsync();

        using var connection = DatabaseFixture.Open();
        var outcome = await connection.QuerySingleAsync<string?>(
            """
            DECLARE @out TABLE (Succeeded BIT, FailureCode VARCHAR(50));
            INSERT @out EXEC [Identity].[usp_Profile_Save]
                @UserId = @userId, @DateOfBirth = @dob;
            SELECT FailureCode FROM @out;
            """,
            new { userId, dob = Aged(13).ToDateTime(TimeOnly.MinValue) });

        outcome.Should().Be(FailureCodes.UnderMinimumAge);
    }

    // -----------------------------------------------------------------------
    // Signing out
    // -----------------------------------------------------------------------

    [Fact]
    public async Task Signing_out_revokes_the_refresh_token_she_presented()
    {
        var (userId, session, _) = await RegisterAsync();

        await using var scope = fixture.Provider.CreateAsyncScope();
        var result = await Sender(scope).Send(new LogoutCommand(
            userId, new LogoutRequest(session.RefreshToken)));

        result.Succeeded.Should().BeTrue();

        using var connection = DatabaseFixture.Open();
        var live = await connection.QuerySingleAsync<int>(
            "SELECT COUNT(*) FROM [Identity].[RefreshToken] "
            + "WHERE UserId = @userId AND RevokedUtc IS NULL",
            new { userId });

        live.Should().Be(0, "the session she ended must not still be usable");
    }

    [Fact]
    public async Task A_revoked_token_cannot_be_refreshed()
    {
        var (userId, session, _) = await RegisterAsync();

        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            await Sender(scope).Send(new LogoutCommand(
                userId, new LogoutRequest(session.RefreshToken)));
        }

        await using var second = fixture.Provider.CreateAsyncScope();
        var refreshed = await Sender(second).Send(
            new RefreshCommand(new RefreshRequest(session.RefreshToken)));

        refreshed.Succeeded.Should().BeFalse(
            "signing out has to actually end the session, not merely say so");

        /*  TOKEN_REUSED rather than UNKNOWN_TOKEN: the row is still there and
            still revoked, and the redeem path treats presenting a revoked
            token as a compromised chain. That is the correct reading — the
            client that signed out should have discarded it. */
        refreshed.FailureCode.Should().Be(FailureCodes.TokenReused);
    }

    [Fact]
    public async Task Signing_out_everywhere_ends_every_session()
    {
        var (userId, first, email) = await RegisterAsync();

        // A second and third session, as though from other devices.
        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            await Sender(scope).Send(new LoginCommand(
                new LoginRequest(email, GoodPassword, null)));
            await Sender(scope).Send(new LoginCommand(
                new LoginRequest(email, GoodPassword, null)));
        }

        using var connection = DatabaseFixture.Open();
        var before = await connection.QuerySingleAsync<int>(
            "SELECT COUNT(*) FROM [Identity].[RefreshToken] "
            + "WHERE UserId = @userId AND RevokedUtc IS NULL",
            new { userId });
        before.Should().Be(3, "three sign-ins, three live sessions");

        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            var result = await Sender(scope).Send(new LogoutCommand(
                userId, new LogoutRequest(first.RefreshToken, AllDevices: true)));
            result.Succeeded.Should().BeTrue();
        }

        var after = await connection.QuerySingleAsync<int>(
            "SELECT COUNT(*) FROM [Identity].[RefreshToken] "
            + "WHERE UserId = @userId AND RevokedUtc IS NULL",
            new { userId });
        after.Should().Be(0);
    }

    [Fact]
    public async Task Signing_out_with_a_token_that_is_already_gone_still_succeeds()
    {
        var (userId, session, _) = await RegisterAsync();

        await using var scope = fixture.Provider.CreateAsyncScope();
        await Sender(scope).Send(new LogoutCommand(
            userId, new LogoutRequest(session.RefreshToken)));

        var again = await Sender(scope).Send(new LogoutCommand(
            userId, new LogoutRequest(session.RefreshToken)));

        again.Succeeded.Should().BeTrue(
            "there is no useful recovery from a failed sign-out, and an error "
            + "here strands someone on a screen whose only job is to let her leave");
    }

    [Fact]
    public async Task She_cannot_sign_somebody_else_out()
    {
        var (_, hers, _) = await RegisterAsync();
        var (otherId, _, _) = await RegisterAsync();

        await using var scope = fixture.Provider.CreateAsyncScope();
        var result = await Sender(scope).Send(new LogoutCommand(
            otherId, new LogoutRequest(hers.RefreshToken)));

        result.Succeeded.Should().BeFalse(
            "the token hash alone finds the row; without the ownership check "
            + "anyone holding a stolen hash could sign its owner out");
        result.FailureCode.Should().Be(FailureCodes.Forbidden);
    }

    // -----------------------------------------------------------------------
    // Leaving
    // -----------------------------------------------------------------------

    [Fact]
    public async Task Deleting_her_account_requires_her_password()
    {
        var (userId, _, _) = await RegisterAsync();

        await using var scope = fixture.Provider.CreateAsyncScope();
        var result = await Sender(scope).Send(new DeleteAccountCommand(
            userId, new DeleteAccountRequest("not the right passphrase")));

        result.Succeeded.Should().BeFalse();
        result.FailureCode.Should().Be(FailureCodes.InvalidCredentials);

        using var connection = DatabaseFixture.Open();
        var stillThere = await connection.QuerySingleAsync<int>(
            "SELECT COUNT(*) FROM [Identity].[User] WHERE UserId = @userId",
            new { userId });
        stillThere.Should().Be(1, "a wrong password must not erase anything");
    }

    [Fact]
    public async Task Deletion_removes_every_row_that_names_her()
    {
        var (userId, _, _) = await RegisterAsync();

        // Give her rows in more than one schema first, so the test is about
        // the cascade rather than about an empty account.
        using var connection = DatabaseFixture.Open();
        await connection.ExecuteAsync(
            """
            INSERT INTO [Identity].[UserLifeStage] (UserId, LifeStageCode, StartedOn)
            SELECT TOP 1 @userId, LifeStageCode, CAST(SYSUTCDATETIME() AS DATE)
            FROM [Identity].[LifeStage] WHERE IsSelectable = 1;

            INSERT INTO [Identity].[Device] (DeviceId, UserId, Platform)
            VALUES (NEWID(), @userId, 'android');
            """,
            new { userId });

        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            var result = await Sender(scope).Send(new DeleteAccountCommand(
                userId, new DeleteAccountRequest(GoodPassword)));
            result.Succeeded.Should().BeTrue();
        }

        /*  Asserted across every table carrying a UserId column rather than
            against the list inside the procedure. A table added later and
            forgotten in the cascade fails here instead of quietly surviving
            an erasure — which is the failure nobody would ever notice.

            One table is excluded, and only one: SecurityStampRevocation keeps
            a tombstone so the access token she is still holding dies now
            rather than in fifteen minutes. It is a user id and a random GUID,
            it refers to nothing once the account is gone, and the next test
            asserts it is there. Adding anything else to this exclusion is
            almost certainly a bug being hidden. */
        var residue = await connection.QueryAsync<string>(
            """
            DECLARE @sql NVARCHAR(MAX) = N'';
            SELECT @sql = @sql + N' UNION ALL SELECT ''' +
                   QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name) +
                   N''' AS TableName FROM ' +
                   QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name) +
                   N' WHERE UserId = @u'
            FROM sys.tables t
            JOIN sys.columns c ON c.object_id = t.object_id
            WHERE c.name = 'UserId'
              AND NOT (SCHEMA_NAME(t.schema_id) = 'Identity'
                       AND t.name = 'SecurityStampRevocation');

            SET @sql = STUFF(@sql, 1, 11, N'');
            EXEC sp_executesql @sql, N'@u UNIQUEIDENTIFIER', @u = @userId;
            """,
            new { userId });

        residue.Should().BeEmpty(
            "deletion means deletion — every table naming her must be empty");
    }

    [Fact]
    public async Task Deletion_kills_the_access_token_she_is_still_holding()
    {
        /*  Refresh tokens going away stops her getting a NEW access token. It
            does nothing about the one already on a second device, which stays
            correctly signed for up to fifteen minutes. The stamp validator
            treats "no revocation row" as "nothing has invalidated this user",
            so erasing her rows was what let that token through — it reached a
            handler and came back PROFILE_NOT_FOUND with a 400, which tells a
            client to stay where it is rather than to sign out. */
        var (userId, _, _) = await RegisterAsync();

        using var connection = DatabaseFixture.Open();
        var stampBefore = await connection.QuerySingleAsync<Guid>(
            "SELECT SecurityStamp FROM [Identity].[User] WHERE UserId = @userId",
            new { userId });

        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            var result = await Sender(scope).Send(new DeleteAccountCommand(
                userId, new DeleteAccountRequest(GoodPassword)));
            result.Succeeded.Should().BeTrue();
        }

        var revocation = await connection.QuerySingleOrDefaultAsync<Guid?>(
            "SELECT SecurityStamp FROM [Identity].[SecurityStampRevocation] "
            + "WHERE UserId = @userId",
            new { userId });

        revocation.Should().NotBeNull(
            "a revocation has to outlive the account it revokes, which is why "
            + "the foreign key to Identity.User was dropped");

        revocation.Should().NotBe(stampBefore,
            "a replacement that matched the stamp her token carries would "
            + "revoke nothing at all");
    }

    [Fact]
    public async Task Deletion_takes_her_audit_history_and_leaves_a_tombstone()
    {
        var (userId, _, _) = await RegisterAsync();

        using var connection = DatabaseFixture.Open();
        var before = await connection.QuerySingleAsync<int>(
            "SELECT COUNT(*) FROM [Audit].[AuditLog] WHERE ActorUserId = @userId",
            new { userId });
        before.Should().BeGreaterThan(0, "registering writes an audit row");

        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            await Sender(scope).Send(new DeleteAccountCommand(
                userId, new DeleteAccountRequest(GoodPassword)));
        }

        var hers = await connection.QuerySingleAsync<int>(
            "SELECT COUNT(*) FROM [Audit].[AuditLog] WHERE ActorUserId = @userId",
            new { userId });
        hers.Should().Be(0,
            "a log of everything she did is still a record of everything she did");

        var tombstone = await connection.QuerySingleAsync<int>(
            """
            SELECT COUNT(*) FROM [Audit].[AuditLog]
            WHERE [Action] = 'User.DeleteAccount'
              AND EntityId = CONVERT(NVARCHAR(50), @userId)
              AND ActorUserId IS NULL
              AND IpAddress IS NULL
            """,
            new { userId });
        tombstone.Should().Be(1,
            "the fact of an erasure has to outlive the account, and carry no "
            + "address belonging to someone who has asked to stop being a user");
    }

    [Fact]
    public async Task An_operator_cannot_erase_herself_through_this_door()
    {
        var (userId, _, _) = await RegisterAsync();

        using var connection = DatabaseFixture.Open();
        await connection.ExecuteAsync(
            """
            INSERT INTO [Identity].[UserRole] (UserId, RoleId)
            SELECT TOP 1 @userId, RoleId FROM [Identity].[Role]
            WHERE Name <> 'Member';
            """,
            new { userId });

        await using var scope = fixture.Provider.CreateAsyncScope();
        var result = await Sender(scope).Send(new DeleteAccountCommand(
            userId, new DeleteAccountRequest(GoodPassword)));

        result.Succeeded.Should().BeFalse();
        result.FailureCode.Should().Be(FailureCodes.OperatorAccount);

        var stillThere = await connection.QuerySingleAsync<int>(
            "SELECT COUNT(*) FROM [Identity].[User] WHERE UserId = @userId",
            new { userId });
        stillThere.Should().Be(1);
    }

    [Fact]
    public async Task Her_email_is_free_to_use_again_afterwards()
    {
        var (userId, _, email) = await RegisterAsync();

        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            await Sender(scope).Send(new DeleteAccountCommand(
                userId, new DeleteAccountRequest(GoodPassword)));
        }

        /*  The difference between deletion and a flag, from her side. Soft
            deletion leaves NormalisedEmail occupied, so coming back means
            being told the address is in use by an account she was assured no
            longer exists. */
        await using var second = fixture.Provider.CreateAsyncScope();
        var again = await Sender(second).Send(new RegisterCommand(
            new RegisterRequest(email, GoodPassword, Aged(30), "GB", "en-GB")));

        again.Succeeded.Should().BeTrue();
        again.Value!.UserId.Should().NotBe(userId, "it is a new account, not the old one");
    }

    // -----------------------------------------------------------------------
    // Ownership
    // -----------------------------------------------------------------------

    [Fact]
    public async Task One_womans_deletion_does_not_touch_another_account()
    {
        var (mine, _, _) = await RegisterAsync();
        var (hers, _, _) = await RegisterAsync();

        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            await Sender(scope).Send(new DeleteAccountCommand(
                mine, new DeleteAccountRequest(GoodPassword)));
        }

        using var connection = DatabaseFixture.Open();
        var survivor = await connection.QuerySingleAsync<int>(
            "SELECT COUNT(*) FROM [Identity].[User] WHERE UserId = @hers",
            new { hers });
        survivor.Should().Be(1);

        var herProfile = await connection.QuerySingleAsync<int>(
            "SELECT COUNT(*) FROM [Identity].[Profile] WHERE UserId = @hers",
            new { hers });
        herProfile.Should().Be(1);
    }

    // -----------------------------------------------------------------------
    // The rehash path
    // -----------------------------------------------------------------------

    [Fact]
    public async Task A_stored_hash_below_the_current_cost_is_upgraded_on_login()
    {
        /*  This never worked. The handler called usp_User_Register to save the
            upgraded material, which found the address already registered,
            returned EMAIL_IN_USE and changed nothing — so the iteration count
            has been frozen at whatever each account was created with. */
        var (userId, _, email) = await RegisterAsync();

        using var connection = DatabaseFixture.Open();

        // Re-hash the same password at a deliberately low cost, as an account
        // created before the last increase would have been stored.
        var hasher = fixture.Provider.GetRequiredService<IPasswordHasher>();
        var (hash, salt, _) = hasher.Hash(GoodPassword);

        await connection.ExecuteAsync(
            """
            UPDATE [Identity].[User]
            SET PasswordIterations = 1000
            WHERE UserId = @userId
            """,
            new { userId });

        // The stored hash must match the stored iteration count, or the
        // verification fails for the wrong reason.
        var low = System.Security.Cryptography.Rfc2898DeriveBytes.Pbkdf2(
            System.Text.Encoding.UTF8.GetBytes(GoodPassword), salt, 1000,
            System.Security.Cryptography.HashAlgorithmName.SHA256, hash.Length);

        await connection.ExecuteAsync(
            """
            UPDATE [Identity].[User]
            SET PasswordHash = @low, PasswordSalt = @salt
            WHERE UserId = @userId
            """,
            new { userId, low, salt });

        await using var scope = fixture.Provider.CreateAsyncScope();
        var signedIn = await Sender(scope).Send(new LoginCommand(
            new LoginRequest(email, GoodPassword, null)));

        signedIn.Succeeded.Should().BeTrue("the password is still correct");

        var iterations = await connection.QuerySingleAsync<int>(
            "SELECT PasswordIterations FROM [Identity].[User] WHERE UserId = @userId",
            new { userId });

        iterations.Should().BeGreaterThan(1000,
            "a successful sign-in is the one moment the plaintext is "
            + "legitimately in hand, and the only chance to raise the cost");
    }
}

/// <summary>
/// Authorization attributes, checked by reflection rather than over HTTP.
/// </summary>
/// <remarks>
/// <para>
/// The integration tests above go through MediatR and never touch the
/// authorization filter, so they cannot see an <c>[Authorize]</c> that does
/// nothing. This class can.
/// </para>
/// <para>
/// It exists because <c>[AllowAnonymous]</c> sat on <c>AuthController</c> and
/// silently overrode the <c>[Authorize]</c> on sign-out — an attribute farther
/// away wins. The endpoint answered 401 anyway, because the action re-reads the
/// subject claim itself, so nothing looked wrong from outside; the only signal
/// was an ASP0026 build warning that a quiet verbosity flag was hiding.
/// </para>
/// </remarks>
public sealed class AuthorizationAttributeTests
{
    [Fact]
    public void Signing_out_requires_authentication_at_the_framework_level()
    {
        var action = typeof(Maren.Api.Controllers.AuthController)
            .GetMethod(nameof(Maren.Api.Controllers.AuthController.Logout))!;

        action.GetCustomAttributes(typeof(AuthorizeAttribute), true)
            .Should().NotBeEmpty("sign-out acts on a known account");

        /*  The part that actually broke. An [AllowAnonymous] anywhere above the
            action defeats the [Authorize] on it, and nothing in the response
            gives that away. */
        typeof(Maren.Api.Controllers.AuthController)
            .GetCustomAttributes(typeof(AllowAnonymousAttribute), true)
            .Should().BeEmpty(
                "a class-level [AllowAnonymous] silently overrides [Authorize] "
                + "on every action beneath it — declare it per action instead");
    }

    [Theory]
    [InlineData(nameof(Maren.Api.Controllers.AuthController.Register))]
    [InlineData(nameof(Maren.Api.Controllers.AuthController.Login))]
    [InlineData(nameof(Maren.Api.Controllers.AuthController.Refresh))]
    public void The_three_endpoints_that_cannot_require_a_token_say_so(string name)
    {
        // Moving [AllowAnonymous] off the class has to leave these reachable.
        // Without a token there is no way to register or sign in, and a
        // refresh is authenticated by the refresh token in its body rather
        // than by an access token in a header.
        typeof(Maren.Api.Controllers.AuthController)
            .GetMethod(name)!
            .GetCustomAttributes(typeof(AllowAnonymousAttribute), true)
            .Should().NotBeEmpty($"{name} cannot require an access token");
    }

    [Fact]
    public void Everything_under_api_v1_me_requires_authentication()
    {
        // These act on the caller and read her id from the token. One of them
        // erases her account.
        typeof(Maren.Api.Controllers.OnboardingController)
            .GetCustomAttributes(typeof(AuthorizeAttribute), true)
            .Should().NotBeEmpty();

        typeof(Maren.Api.Controllers.OnboardingController)
            .GetCustomAttributes(typeof(AllowAnonymousAttribute), true)
            .Should().BeEmpty();
    }
}
