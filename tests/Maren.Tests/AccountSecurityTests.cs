using System.Security.Cryptography;
using Dapper;
using FluentAssertions;
using Maren.Application.Abstractions;
using Maren.Application.Auth;
using Maren.Application.Crypto;
using Maren.Contracts;
using MediatR;
using Microsoft.Extensions.DependencyInjection;

namespace Maren.Tests;

/// <summary>
/// The three things a woman does to her own account once it is encrypted:
/// change the password, replace the twelve words, and close it.
/// </summary>
/// <remarks>
/// <para>
/// Every one of these can strand her. A password change that writes the
/// credential without resealing the data key leaves an account whose new
/// password signs in and opens nothing. A phrase replacement that writes the
/// wrapper without the public key leaves words that open a key they can no
/// longer prove possession of. And closing an account has to actually work,
/// which for a client-derived account it did not until this slice — the
/// handler checked a password that such an account does not have.
/// </para>
/// <para>
/// None of these is recoverable by an operator afterwards, because no
/// operator on this platform can read the key either. So they are asserted
/// here against the real procedures rather than reasoned about.
/// </para>
/// </remarks>
[Collection("database")]
public sealed class AccountSecurityTests(DatabaseFixture fixture) : IAsyncLifetime
{
    private const string Prefix = "account-security-test-";

    public async Task InitializeAsync() => await CleanupAsync();

    public Task DisposeAsync() => Task.CompletedTask;

    private ISender Sender(IServiceScope scope) =>
        scope.ServiceProvider.GetRequiredService<ISender>();

    private static string NewEmail() => Prefix + Guid.NewGuid().ToString("N") + "@example.com";

    private static byte[] Bytes(int length, byte seed) =>
        Enumerable.Range(0, length).Select(i => (byte)(seed + i)).ToArray();

    private static byte[] Envelope(int length = 256, byte seed = 0x40)
    {
        var buffer = Bytes(length, seed);
        buffer[0] = 0x57; buffer[1] = 0x4C; buffer[2] = 0x4F; buffer[3] = 0x53; // 'WLOS'
        return buffer;
    }

    private static async Task CleanupAsync()
    {
        using var connection = DatabaseFixture.Open();
        await connection.ExecuteAsync(
            """
            DECLARE @ids TABLE (UserId UNIQUEIDENTIFIER PRIMARY KEY);
            INSERT @ids SELECT UserId FROM [Identity].[User] WHERE Email LIKE @p;

            DELETE FROM [Crypto].[RecoveryChallenge] WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Crypto].[Record]            WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Crypto].[RecoveryVerifier]  WHERE GenerationId IN
                   (SELECT GenerationId FROM [Crypto].[Generation]
                     WHERE UserId IN (SELECT UserId FROM @ids));
            DELETE FROM [Crypto].[Wrapper]           WHERE GenerationId IN
                   (SELECT GenerationId FROM [Crypto].[Generation]
                     WHERE UserId IN (SELECT UserId FROM @ids));
            DELETE FROM [Crypto].[Generation]        WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Identity].[UserCredential]  WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Identity].[RefreshToken]    WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Identity].[UserRole]        WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Identity].[Profile]         WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Audit].[AuditLog]           WHERE ActorUserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Identity].[User]            WHERE UserId IN (SELECT UserId FROM @ids);
            """,
            new { p = Prefix + "%" });
    }

    private sealed record Account(
        Guid UserId, string Email, byte[] AuthSecret, byte[] AuthSecretSalt,
        int KdfProfileId);

    private async Task<Account> RegisterAsync()
    {
        var email = NewEmail();
        var authSecret = RandomNumberGenerator.GetBytes(32);
        var salt = Bytes(16, 0x10);

        await using var scope = fixture.Provider.CreateAsyncScope();
        var profile = await scope.ServiceProvider
            .GetRequiredService<ICryptoRepository>()
            .GetCurrentKdfProfileAsync(default);

        var result = await Sender(scope).Send(new RegisterClientDerivedCommand(
            new RegisterClientDerivedRequest(
                email, DateOnly.FromDateTime(DateTime.UtcNow.AddYears(-30)),
                Guid.NewGuid(), authSecret, salt, profile!.KdfProfileId,
                Envelope(seed: 0x50), Envelope(seed: 0x60), Bytes(32, 0x70),
                "GB", "en-GB")));

        result.Succeeded.Should().BeTrue(result.FailureCode);
        return new Account(
            result.Value!.UserId, email, authSecret, salt, profile.KdfProfileId);
    }

    private static async Task<byte[]?> WrapperAsync(Guid userId, string kind)
    {
        using var connection = DatabaseFixture.Open();
        return await connection.QuerySingleOrDefaultAsync<byte[]?>(
            """
            SELECT w.Envelope FROM [Crypto].[Wrapper] w
            JOIN [Crypto].[Generation] g ON g.GenerationId = w.GenerationId
            WHERE g.UserId = @userId AND g.[State] = 'ACTIVE' AND w.WrapperKind = @kind;
            """,
            new { userId, kind });
    }

    // -----------------------------------------------------------------------
    // Changing a password
    // -----------------------------------------------------------------------

    /// <summary>
    /// The one that decides whether she can still open her journal afterwards.
    /// </summary>
    /// <remarks>
    /// A new password derives a new key-encryption key, and the wrapper on
    /// disk was sealed under the old one. Both writes land or neither does.
    /// </remarks>
    [Fact]
    public async Task A_password_change_reseals_the_data_key()
    {
        var account = await RegisterAsync();
        fixture.CurrentUser.UserId = account.UserId;

        var newSecret = RandomNumberGenerator.GetBytes(32);
        var newSalt = Bytes(16, 0x90);
        var resealed = Envelope(seed: 0x21);

        await using var scope = fixture.Provider.CreateAsyncScope();
        var changed = await Sender(scope).Send(new ChangePasswordCommand(
            new ChangePasswordRequest(
                account.AuthSecret, newSecret, newSalt,
                account.KdfProfileId, resealed)));

        changed.Succeeded.Should().BeTrue(changed.FailureCode);

        (await WrapperAsync(account.UserId, "PASSWORD")).Should().Equal(resealed,
            "the key she opens her journal with is resealed under the new password");
    }

    [Fact]
    public async Task The_old_password_stops_working_and_the_new_one_signs_her_in()
    {
        var account = await RegisterAsync();
        fixture.CurrentUser.UserId = account.UserId;

        var newSecret = RandomNumberGenerator.GetBytes(32);

        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            var changed = await Sender(scope).Send(new ChangePasswordCommand(
                new ChangePasswordRequest(
                    account.AuthSecret, newSecret, Bytes(16, 0x91),
                    account.KdfProfileId, Envelope(seed: 0x22))));
            changed.Succeeded.Should().BeTrue(changed.FailureCode);
        }

        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            var old = await Sender(scope).Send(new LoginClientDerivedCommand(
                new LoginClientDerivedRequest(account.Email, account.AuthSecret)));
            old.Succeeded.Should().BeFalse("the password she replaced is gone");
        }

        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            var fresh = await Sender(scope).Send(new LoginClientDerivedCommand(
                new LoginClientDerivedRequest(account.Email, newSecret)));
            fresh.Succeeded.Should().BeTrue(fresh.FailureCode);
        }
    }

    /// <summary>
    /// She is not signed out of the phone she is holding.
    /// </summary>
    /// <remarks>
    /// The change revokes every session, which is right — but without a fresh
    /// token pair in the response, changing a password would be
    /// indistinguishable from being kicked out.
    /// </remarks>
    [Fact]
    public async Task A_password_change_hands_back_a_working_session()
    {
        var account = await RegisterAsync();
        fixture.CurrentUser.UserId = account.UserId;

        await using var scope = fixture.Provider.CreateAsyncScope();
        var changed = await Sender(scope).Send(new ChangePasswordCommand(
            new ChangePasswordRequest(
                account.AuthSecret, RandomNumberGenerator.GetBytes(32),
                Bytes(16, 0x92), account.KdfProfileId, Envelope(seed: 0x23))));

        changed.Succeeded.Should().BeTrue(changed.FailureCode);
        changed.Value!.AccessToken.Should().NotBeNullOrEmpty();
        changed.Value.RefreshToken.Should().NotBeNullOrEmpty();

        using var connection = DatabaseFixture.Open();
        var tokens = await connection.ExecuteScalarAsync<int>(
            "SELECT COUNT(*) FROM [Identity].[RefreshToken] WHERE UserId = @userId;",
            new { account.UserId });

        tokens.Should().Be(1,
            "every session before the change is revoked, and exactly one is issued");
    }

    [Fact]
    public async Task A_wrong_password_changes_nothing()
    {
        var account = await RegisterAsync();
        fixture.CurrentUser.UserId = account.UserId;

        await using var scope = fixture.Provider.CreateAsyncScope();
        var refused = await Sender(scope).Send(new ChangePasswordCommand(
            new ChangePasswordRequest(
                RandomNumberGenerator.GetBytes(32), RandomNumberGenerator.GetBytes(32),
                Bytes(16, 0x93), account.KdfProfileId, Envelope(seed: 0x24))));

        refused.Succeeded.Should().BeFalse();

        (await WrapperAsync(account.UserId, "PASSWORD")).Should().Equal(Envelope(seed: 0x50),
            "a refused change does not touch the key she can still open");
    }

    /// <summary>
    /// A wrong answer here must not count towards lockout.
    /// </summary>
    /// <remarks>
    /// This is a confirmation step inside an authenticated session. Counting
    /// failures would hand an attacker holding a stolen session a way to lock
    /// the real owner out of her own account by guessing wrong a few times —
    /// turning a safeguard into a denial-of-service lever.
    /// </remarks>
    [Fact]
    public async Task A_wrong_password_here_cannot_lock_her_out()
    {
        var account = await RegisterAsync();
        fixture.CurrentUser.UserId = account.UserId;

        for (var attempt = 0; attempt < 6; attempt++)
        {
            await using var scope = fixture.Provider.CreateAsyncScope();
            var refused = await Sender(scope).Send(new ChangePasswordCommand(
                new ChangePasswordRequest(
                    RandomNumberGenerator.GetBytes(32),
                    RandomNumberGenerator.GetBytes(32),
                    Bytes(16, 0x94), account.KdfProfileId, Envelope(seed: 0x25))));
            refused.Succeeded.Should().BeFalse();
        }

        await using var login = fixture.Provider.CreateAsyncScope();
        var signedIn = await Sender(login).Send(new LoginClientDerivedCommand(
            new LoginClientDerivedRequest(account.Email, account.AuthSecret)));

        signedIn.Succeeded.Should().BeTrue(
            "six wrong confirmations must not cost her the account");
    }

    // -----------------------------------------------------------------------
    // Replacing the twelve words
    // -----------------------------------------------------------------------

    [Fact]
    public async Task New_words_replace_both_what_they_open_and_what_they_prove()
    {
        var account = await RegisterAsync();
        fixture.CurrentUser.UserId = account.UserId;

        var newWrapper = Envelope(seed: 0x31);
        var newPublicKey = Bytes(32, 0x81);

        await using var scope = fixture.Provider.CreateAsyncScope();
        var replaced = await Sender(scope).Send(new ReplaceRecoveryPhraseCommand(
            new ReplaceRecoveryPhraseRequest(
                account.AuthSecret, newWrapper, newPublicKey)));

        replaced.Succeeded.Should().BeTrue(replaced.FailureCode);

        (await WrapperAsync(account.UserId, "RECOVERY")).Should().Equal(newWrapper);

        using var connection = DatabaseFixture.Open();
        var keys = await connection.QueryAsync<byte[]>(
            """
            SELECT v.PublicKey FROM [Crypto].[RecoveryVerifier] v
            JOIN [Crypto].[Generation] g ON g.GenerationId = v.GenerationId
            WHERE g.UserId = @userId;
            """,
            new { account.UserId });

        keys.Should().ContainSingle().Which.Should().Equal(newPublicKey,
            "the old words stop proving anything as well as stop opening anything");
    }

    /// <summary>
    /// The claim the screen makes to her: new words, same journal.
    /// </summary>
    [Fact]
    public async Task New_words_leave_her_journal_where_it_was()
    {
        var account = await RegisterAsync();
        fixture.CurrentUser.UserId = account.UserId;

        var recordId = Guid.NewGuid();
        var entry = Envelope(1024, 0x11);

        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            var saved = await Sender(scope).Send(new SaveRecordCommand(
                new SaveRecordRequest(recordId, "journal.entry", 1, 1, entry)));
            saved.Succeeded.Should().BeTrue(saved.FailureCode);
        }

        Guid generationBefore;
        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            var before = await Sender(scope).Send(new GetActiveGenerationQuery());
            generationBefore = before.Value!.GenerationId;

            var replaced = await Sender(scope).Send(new ReplaceRecoveryPhraseCommand(
                new ReplaceRecoveryPhraseRequest(
                    account.AuthSecret, Envelope(seed: 0x32), Bytes(32, 0x82))));
            replaced.Succeeded.Should().BeTrue(replaced.FailureCode);
        }

        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            var after = await Sender(scope).Send(new GetActiveGenerationQuery());
            after.Value!.GenerationId.Should().Be(generationBefore,
                "the data key does not move when the words that open it change");

            var read = await Sender(scope).Send(new GetRecordQuery(recordId));
            read.Succeeded.Should().BeTrue(read.FailureCode);
            read.Value!.Envelope.Should().Equal(entry);

            (await WrapperAsync(account.UserId, "PASSWORD"))
                .Should().Equal(Envelope(seed: 0x50),
                    "and her password still opens it");
        }
    }

    [Fact]
    public async Task A_wrong_password_cannot_retire_her_phrase()
    {
        var account = await RegisterAsync();
        fixture.CurrentUser.UserId = account.UserId;

        await using var scope = fixture.Provider.CreateAsyncScope();
        var refused = await Sender(scope).Send(new ReplaceRecoveryPhraseCommand(
            new ReplaceRecoveryPhraseRequest(
                RandomNumberGenerator.GetBytes(32), Envelope(seed: 0x33), Bytes(32, 0x83))));

        refused.Succeeded.Should().BeFalse(
            "a stolen session must not be able to destroy the way back in");

        (await WrapperAsync(account.UserId, "RECOVERY")).Should().Equal(Envelope(seed: 0x60));
    }

    // -----------------------------------------------------------------------
    // Closing an encrypted account
    // -----------------------------------------------------------------------

    /// <summary>
    /// The defect this slice found: deletion did not mean deletion for an
    /// encrypted account.
    /// </summary>
    /// <remarks>
    /// <c>DeleteAccountHandler</c> re-verified a password against
    /// <c>Identity.User</c>, and a client-derived account holds none — an
    /// assertion in <c>crypto_test.sql</c> insists on exactly that. Every such
    /// account was therefore refused, and every existing test of the path used
    /// a version 1 account, so nothing noticed.
    /// </remarks>
    [Fact]
    public async Task An_encrypted_account_can_be_closed()
    {
        var account = await RegisterAsync();
        fixture.CurrentUser.UserId = account.UserId;

        await using var scope = fixture.Provider.CreateAsyncScope();
        var closed = await Sender(scope).Send(new DeleteAccountCommand(
            account.UserId, new DeleteAccountRequest(AuthSecret: account.AuthSecret)));

        closed.Succeeded.Should().BeTrue(closed.FailureCode);

        using var connection = DatabaseFixture.Open();
        var remaining = await connection.ExecuteScalarAsync<int>(
            """
            SELECT (SELECT COUNT(*) FROM [Identity].[User] WHERE UserId = @userId)
                 + (SELECT COUNT(*) FROM [Identity].[UserCredential] WHERE UserId = @userId)
                 + (SELECT COUNT(*) FROM [Crypto].[Generation] WHERE UserId = @userId);
            """,
            new { account.UserId });

        remaining.Should().Be(0, "deletion means deletion, on this path too");
    }

    [Fact]
    public async Task A_wrong_secret_does_not_close_an_encrypted_account()
    {
        var account = await RegisterAsync();
        fixture.CurrentUser.UserId = account.UserId;

        await using var scope = fixture.Provider.CreateAsyncScope();
        var refused = await Sender(scope).Send(new DeleteAccountCommand(
            account.UserId,
            new DeleteAccountRequest(AuthSecret: RandomNumberGenerator.GetBytes(32))));

        refused.Succeeded.Should().BeFalse();

        using var connection = DatabaseFixture.Open();
        var alive = await connection.ExecuteScalarAsync<int>(
            "SELECT COUNT(*) FROM [Identity].[User] WHERE UserId = @userId;",
            new { account.UserId });

        alive.Should().Be(1);
    }

    /// <summary>
    /// A password is not accepted for an account that has no password.
    /// </summary>
    /// <remarks>
    /// The handler decides from the account, not from what arrived. Falling
    /// back to the version 1 check when an account has migrated would mean the
    /// leftover version 1 material — which
    /// <c>usp_UserCredential_SetAuthoritative</c> deliberately does not clear —
    /// could still close an account whose password had been replaced.
    /// </remarks>
    // -----------------------------------------------------------------------
    // What an operator can answer for her
    // -----------------------------------------------------------------------

    /// <summary>
    /// "Did someone else get into my account?"
    /// </summary>
    /// <remarks>
    /// The one question an operator genuinely needs to answer about this
    /// slice, and the reason the two dates are on the summary at all. They
    /// come from the audit log rather than a column, so this asserts the join
    /// actually finds them — a summary that silently reported "never" for an
    /// account whose password <em>had</em> been changed would be worse than
    /// having no field.
    /// </remarks>
    [Fact]
    public async Task An_operator_can_say_when_her_credentials_last_changed()
    {
        var account = await RegisterAsync();
        fixture.CurrentUser.UserId = account.UserId;

        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            var before = await Sender(scope).Send(
                new GetCryptoAccountSummaryQuery(account.UserId));

            before.Succeeded.Should().BeTrue(before.FailureCode);
            before.Value!.PasswordChangedOn.Should().BeNull(
                "a new account has never had its password changed");
            before.Value.RecoveryPhraseChangedOn.Should().BeNull();
        }

        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            var changed = await Sender(scope).Send(new ChangePasswordCommand(
                new ChangePasswordRequest(
                    account.AuthSecret, RandomNumberGenerator.GetBytes(32),
                    Bytes(16, 0x95), account.KdfProfileId, Envelope(seed: 0x26))));
            changed.Succeeded.Should().BeTrue(changed.FailureCode);

            var replaced = await Sender(scope).Send(
                new ReplaceRecoveryPhraseCommand(
                    new ReplaceRecoveryPhraseRequest(
                        account.AuthSecret, Envelope(seed: 0x34), Bytes(32, 0x84))));
            replaced.Succeeded.Should().BeFalse(
                "the password it was confirming with has just been replaced");
        }

        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            var after = await Sender(scope).Send(
                new GetCryptoAccountSummaryQuery(account.UserId));

            after.Value!.PasswordChangedOn.Should().NotBeNull(
                "she can be told when it happened, or told that it did not");
            after.Value.RecoveryPhraseChangedOn.Should().BeNull(
                "a refused replacement is not a replacement");
        }
    }

    [Fact]
    public async Task A_password_cannot_close_an_encrypted_account()
    {
        var account = await RegisterAsync();
        fixture.CurrentUser.UserId = account.UserId;

        await using var scope = fixture.Provider.CreateAsyncScope();
        var refused = await Sender(scope).Send(new DeleteAccountCommand(
            account.UserId, new DeleteAccountRequest(Password: "any password at all")));

        refused.Succeeded.Should().BeFalse();

        using var connection = DatabaseFixture.Open();
        var alive = await connection.ExecuteScalarAsync<int>(
            "SELECT COUNT(*) FROM [Identity].[User] WHERE UserId = @userId;",
            new { account.UserId });

        alive.Should().Be(1);
    }
}
