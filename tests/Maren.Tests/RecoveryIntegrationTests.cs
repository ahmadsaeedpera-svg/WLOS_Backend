using System.Security.Cryptography;
using Dapper;
using FluentAssertions;
using Maren.Application.Abstractions;
using Maren.Application.Crypto;
using Maren.Contracts;
using Maren.Infrastructure;
using Maren.Shared;
using MediatR;
using Microsoft.Extensions.DependencyInjection;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;

namespace Maren.Tests;

/// <summary>
/// Path R, end to end, with signatures made for real.
/// </summary>
/// <remarks>
/// <para>
/// The Ed25519 keys here are generated and signed with in the test, because a
/// proof of possession tested with a stubbed verifier is a proof of nothing.
/// What the platform does with them — build the context, check the signature,
/// release the wrapper, issue a grant — is the real code path.
/// </para>
/// <para>
/// The wrappers are opaque bytes, as everywhere else on this side: this server
/// cannot open one and a test that sealed them properly would be testing the
/// client. What matters here is which wrapper comes back, to whom, and after
/// what.
/// </para>
/// </remarks>
[Collection("database")]
public sealed class RecoveryIntegrationTests(DatabaseFixture fixture) : IAsyncLifetime
{
    private const string Prefix = "recovery-slice-test-";

    public async Task InitializeAsync() => await CleanupAsync();

    public Task DisposeAsync() => Task.CompletedTask;

    private static string NewEmail() => Prefix + Guid.NewGuid().ToString("N") + "@example.com";

    private ISender Sender(IServiceScope scope) =>
        scope.ServiceProvider.GetRequiredService<ISender>();

    private static byte[] Bytes(int length, byte seed) =>
        Enumerable.Range(0, length).Select(i => (byte)(seed + i)).ToArray();

    private static byte[] Envelope(int length = 256, byte seed = 0x40)
    {
        var buffer = Bytes(length, seed);
        buffer[0] = 0x57; buffer[1] = 0x4C; buffer[2] = 0x4F; buffer[3] = 0x53;
        return buffer;
    }

    /// <summary>A real Ed25519 key pair, as her device would derive from the phrase.</summary>
    private static (byte[] PublicKey, Ed25519PrivateKeyParameters Private) NewRecoveryKey()
    {
        var seed = RandomNumberGenerator.GetBytes(32);
        var priv = new Ed25519PrivateKeyParameters(seed, 0);
        return (priv.GeneratePublicKey().GetEncoded(), priv);
    }

    private static byte[] Sign(Ed25519PrivateKeyParameters key, byte[] message)
    {
        var signer = new Ed25519Signer();
        signer.Init(true, key);
        signer.BlockUpdate(message, 0, message.Length);
        return signer.GenerateSignature();
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
        Guid UserId, string Email, Guid GenerationId,
        Ed25519PrivateKeyParameters RecoveryKey, byte[] AuthSecret);

    private async Task<Account> RegisterAsync()
    {
        var email = NewEmail();
        var authSecret = RandomNumberGenerator.GetBytes(32);
        var generationId = Guid.NewGuid();
        var (publicKey, privateKey) = NewRecoveryKey();

        await using var scope = fixture.Provider.CreateAsyncScope();
        var profile = await scope.ServiceProvider
            .GetRequiredService<ICryptoRepository>().GetCurrentKdfProfileAsync(default);

        var result = await Sender(scope).Send(new RegisterClientDerivedCommand(
            new RegisterClientDerivedRequest(
                email, DateOnly.FromDateTime(DateTime.UtcNow.AddYears(-30)),
                generationId, authSecret, Bytes(16, 0x10), profile!.KdfProfileId,
                Envelope(seed: 0x50), Envelope(seed: 0x60), publicKey,
                "GB", "en-GB")));

        result.Succeeded.Should().BeTrue(result.FailureCode);
        return new Account(result.Value!.UserId, email, generationId, privateKey, authSecret);
    }

    /// <summary>Runs R0 and R1 with a genuine signature.</summary>
    private async Task<Result<RecoveryVerifyResponse>> ProveAsync(
        Account account, bool signCorrectly = true)
    {
        await using var scope = fixture.Provider.CreateAsyncScope();

        var challenge = await Sender(scope).Send(
            new RecoveryChallengeCommand(new RecoveryChallengeRequest(account.Email)));
        challenge.Succeeded.Should().BeTrue();

        var context = WlosRecoveryContext.Build(
            challenge.Value!.ChallengeId, challenge.Value.Nonce);

        var signature = signCorrectly
            ? Sign(account.RecoveryKey, context)
            : Sign(NewRecoveryKey().Private, context);

        return await Sender(scope).Send(new RecoveryVerifyCommand(
            new RecoveryVerifyRequest(challenge.Value.ChallengeId, signature)));
    }

    // -----------------------------------------------------------------------
    // R0
    // -----------------------------------------------------------------------

    [Fact]
    public async Task An_address_with_no_account_still_gets_a_challenge()
    {
        /*  She is here because she lost what she would authenticate with, so
            this cannot be authenticated — and an endpoint that answered only
            for real accounts would say which addresses are registered. */
        await using var scope = fixture.Provider.CreateAsyncScope();

        var result = await Sender(scope).Send(new RecoveryChallengeCommand(
            new RecoveryChallengeRequest(NewEmail())));

        result.Succeeded.Should().BeTrue();
        result.Value!.Nonce.Should().HaveCount(32);
        result.Value.ChallengeId.Should().NotBeEmpty();
    }

    [Fact]
    public async Task A_challenge_for_an_unknown_address_proves_nothing()
    {
        var unknown = NewEmail();

        await using var scope = fixture.Provider.CreateAsyncScope();
        var challenge = await Sender(scope).Send(new RecoveryChallengeCommand(
            new RecoveryChallengeRequest(unknown)));

        var (_, key) = NewRecoveryKey();
        var signature = Sign(key, WlosRecoveryContext.Build(
            challenge.Value!.ChallengeId, challenge.Value.Nonce));

        var verified = await Sender(scope).Send(new RecoveryVerifyCommand(
            new RecoveryVerifyRequest(challenge.Value.ChallengeId, signature)));

        verified.Succeeded.Should().BeFalse();
        verified.FailureCode.Should().Be(FailureCodes.RecoveryFailed);
    }

    // -----------------------------------------------------------------------
    // R1
    // -----------------------------------------------------------------------

    [Fact]
    public async Task The_phrase_proves_possession_and_releases_the_wrapper()
    {
        var account = await RegisterAsync();

        var verified = await ProveAsync(account);

        verified.Succeeded.Should().BeTrue(verified.FailureCode);
        verified.Value!.Grant.Should().NotBeNullOrWhiteSpace();
        verified.Value.GenerationId.Should().Be(account.GenerationId);
        verified.Value.RecoveryWrapper.Should().Equal(Envelope(seed: 0x60),
            "the recovery wrapper, and only after the signature verified");
    }

    [Fact]
    public async Task A_wrong_signature_is_refused()
    {
        var account = await RegisterAsync();

        var verified = await ProveAsync(account, signCorrectly: false);

        verified.Succeeded.Should().BeFalse();
        verified.FailureCode.Should().Be(FailureCodes.RecoveryFailed);
    }

    [Fact]
    public async Task A_challenge_is_spent_by_a_failed_attempt()
    {
        /*  The property that makes each guess cost a round trip. A challenge
            that survived a failure would let an attacker grind against one
            nonce. */
        var account = await RegisterAsync();

        await using var scope = fixture.Provider.CreateAsyncScope();
        var challenge = await Sender(scope).Send(new RecoveryChallengeCommand(
            new RecoveryChallengeRequest(account.Email)));

        var context = WlosRecoveryContext.Build(
            challenge.Value!.ChallengeId, challenge.Value.Nonce);

        var wrong = await Sender(scope).Send(new RecoveryVerifyCommand(
            new RecoveryVerifyRequest(
                challenge.Value.ChallengeId, Sign(NewRecoveryKey().Private, context))));
        wrong.Succeeded.Should().BeFalse();

        // The right signature, on a challenge already spent.
        var right = await Sender(scope).Send(new RecoveryVerifyCommand(
            new RecoveryVerifyRequest(
                challenge.Value.ChallengeId, Sign(account.RecoveryKey, context))));

        right.Succeeded.Should().BeFalse();
        right.FailureCode.Should().Be(FailureCodes.RecoveryFailed);
    }

    [Fact]
    public async Task A_signature_for_one_challenge_does_not_work_on_another()
    {
        var account = await RegisterAsync();

        await using var scope = fixture.Provider.CreateAsyncScope();

        var first = await Sender(scope).Send(new RecoveryChallengeCommand(
            new RecoveryChallengeRequest(account.Email)));
        var second = await Sender(scope).Send(new RecoveryChallengeCommand(
            new RecoveryChallengeRequest(account.Email)));

        var signatureForFirst = Sign(account.RecoveryKey,
            WlosRecoveryContext.Build(first.Value!.ChallengeId, first.Value.Nonce));

        var replayed = await Sender(scope).Send(new RecoveryVerifyCommand(
            new RecoveryVerifyRequest(second.Value!.ChallengeId, signatureForFirst)));

        replayed.Succeeded.Should().BeFalse();
        replayed.FailureCode.Should().Be(FailureCodes.RecoveryFailed);
    }

    [Fact]
    public async Task Using_the_phrase_is_recorded_before_anything_changes()
    {
        /*  If it was not her, the window in which she can do something starts
            at the proof and not at the completion. */
        var account = await RegisterAsync();
        await ProveAsync(account);

        using var connection = DatabaseFixture.Open();
        var events = await connection.QuerySingleAsync<int>(
            "SELECT COUNT(*) FROM [Audit].[AuditLog] " +
            "WHERE ActorUserId = @userId AND [Action] = 'Recovery.PhraseUsed'",
            new { account.UserId });

        events.Should().Be(1);
    }

    // -----------------------------------------------------------------------
    // R2 — her journal survives
    // -----------------------------------------------------------------------

    [Fact]
    public async Task Recovery_keeps_her_generation_and_everything_in_it()
    {
        var account = await RegisterAsync();

        // One entry, written before she lost the password.
        fixture.CurrentUser.UserId = account.UserId;
        var recordId = Guid.NewGuid();
        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            await Sender(scope).Send(new SaveRecordCommand(
                new SaveRecordRequest(recordId, "journal.entry", 1, 1, Envelope(seed: 0x21))));
        }

        var verified = await ProveAsync(account);
        var newSecret = RandomNumberGenerator.GetBytes(32);

        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            var profile = await scope.ServiceProvider
                .GetRequiredService<ICryptoRepository>().GetCurrentKdfProfileAsync(default);

            var completed = await Sender(scope).Send(new RecoveryCompleteCommand(
                new RecoveryCompleteRequest(
                    verified.Value!.Grant, newSecret, Bytes(16, 0x30),
                    profile!.KdfProfileId, Envelope(seed: 0x70))));

            completed.Succeeded.Should().BeTrue(completed.FailureCode);
        }

        // The generation is the same one, and her entry is untouched.
        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            var generation = await Sender(scope).Send(new GetActiveGenerationQuery());
            generation.Value!.GenerationId.Should().Be(account.GenerationId,
                "Path R replaces a password, not a data key");
            generation.Value.GenerationNumber.Should().Be(1);

            var record = await Sender(scope).Send(new GetRecordQuery(recordId));
            record.Value!.Envelope.Should().Equal(Envelope(seed: 0x21));
        }
    }

    [Fact]
    public async Task She_signs_in_with_the_new_secret_and_not_the_old()
    {
        var account = await RegisterAsync();
        var verified = await ProveAsync(account);
        var newSecret = RandomNumberGenerator.GetBytes(32);

        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            var profile = await scope.ServiceProvider
                .GetRequiredService<ICryptoRepository>().GetCurrentKdfProfileAsync(default);

            await Sender(scope).Send(new RecoveryCompleteCommand(
                new RecoveryCompleteRequest(
                    verified.Value!.Grant, newSecret, Bytes(16, 0x30),
                    profile!.KdfProfileId, Envelope(seed: 0x70))));
        }

        await using var check = fixture.Provider.CreateAsyncScope();

        var withNew = await Sender(check).Send(new LoginClientDerivedCommand(
            new LoginClientDerivedRequest(account.Email, newSecret)));
        withNew.Succeeded.Should().BeTrue(withNew.FailureCode);

        var withOld = await Sender(check).Send(new LoginClientDerivedCommand(
            new LoginClientDerivedRequest(account.Email, account.AuthSecret)));
        withOld.Succeeded.Should().BeFalse("the old credential was replaced");
    }

    [Fact]
    public async Task A_grant_cannot_complete_twice()
    {
        var account = await RegisterAsync();
        var verified = await ProveAsync(account);

        await using var scope = fixture.Provider.CreateAsyncScope();
        var profile = await scope.ServiceProvider
            .GetRequiredService<ICryptoRepository>().GetCurrentKdfProfileAsync(default);

        var first = await Sender(scope).Send(new RecoveryCompleteCommand(
            new RecoveryCompleteRequest(
                verified.Value!.Grant, RandomNumberGenerator.GetBytes(32),
                Bytes(16, 0x30), profile!.KdfProfileId, Envelope(seed: 0x70))));
        first.Succeeded.Should().BeTrue();

        var second = await Sender(scope).Send(new RecoveryCompleteCommand(
            new RecoveryCompleteRequest(
                verified.Value.Grant, RandomNumberGenerator.GetBytes(32),
                Bytes(16, 0x31), profile.KdfProfileId, Envelope(seed: 0x71))));

        second.Succeeded.Should().BeFalse();
        second.FailureCode.Should().Be(FailureCodes.RecoveryFailed);
    }

    [Fact]
    public async Task A_made_up_grant_completes_nothing()
    {
        await using var scope = fixture.Provider.CreateAsyncScope();
        var profile = await scope.ServiceProvider
            .GetRequiredService<ICryptoRepository>().GetCurrentKdfProfileAsync(default);

        var result = await Sender(scope).Send(new RecoveryCompleteCommand(
            new RecoveryCompleteRequest(
                Convert.ToBase64String(RandomNumberGenerator.GetBytes(48)),
                RandomNumberGenerator.GetBytes(32), Bytes(16, 0x30),
                profile!.KdfProfileId, Envelope())));

        result.Succeeded.Should().BeFalse();
        result.FailureCode.Should().Be(FailureCodes.RecoveryFailed);
    }

    // -----------------------------------------------------------------------
    // R3 — the wrapper did not open
    // -----------------------------------------------------------------------

    [Fact]
    public async Task An_unopenable_wrapper_costs_the_generation_not_the_account()
    {
        var account = await RegisterAsync();

        fixture.CurrentUser.UserId = account.UserId;
        var recordId = Guid.NewGuid();
        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            await Sender(scope).Send(new SaveRecordCommand(
                new SaveRecordRequest(recordId, "journal.entry", 1, 1, Envelope(seed: 0x21))));
        }

        var verified = await ProveAsync(account);
        var newGenerationId = Guid.NewGuid();

        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            var profile = await scope.ServiceProvider
                .GetRequiredService<ICryptoRepository>().GetCurrentKdfProfileAsync(default);

            var result = await Sender(scope).Send(
                new RecoveryCompleteUnrecoverableCommand(
                    new RecoveryCompleteUnrecoverableRequest(
                        verified.Value!.Grant, RandomNumberGenerator.GetBytes(32),
                        Bytes(16, 0x30), profile!.KdfProfileId, newGenerationId,
                        Envelope(seed: 0x80), Envelope(seed: 0x90),
                        NewRecoveryKey().PublicKey)));

            result.Succeeded.Should().BeTrue(result.FailureCode);
            result.Value.Should().Be(2, "she writes into a new generation now");
        }

        using var connection = DatabaseFixture.Open();

        var states = await connection.QueryAsync<(Guid Id, string State)>(
            "SELECT GenerationId, [State] FROM [Crypto].[Generation] WHERE UserId = @userId",
            new { account.UserId });

        states.Should().Contain((account.GenerationId, "DORMANT"));
        states.Should().Contain((newGenerationId, "ACTIVE"));

        /*  Her old entry is still there. A device somewhere may still hold the
            key, and deleting the only remaining copy of what she wrote because
            one unwrap failed would be the worst possible answer to it. */
        var kept = await connection.QuerySingleAsync<int>(
            "SELECT COUNT(*) FROM [Crypto].[Record] WHERE RecordId = @recordId",
            new { recordId });
        kept.Should().Be(1);

        var oldRecoveryWrapper = await connection.QuerySingleAsync<int>(
            "SELECT COUNT(*) FROM [Crypto].[Wrapper] " +
            "WHERE GenerationId = @gen AND WrapperKind = 'RECOVERY'",
            new { gen = account.GenerationId });
        oldRecoveryWrapper.Should().Be(1, "unopenable, but not evidence to destroy");
    }
}
