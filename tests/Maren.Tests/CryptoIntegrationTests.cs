using System.Security.Cryptography;
using Dapper;
using FluentAssertions;
using Maren.Application.Auth;
using Maren.Application.Crypto;
using Maren.Contracts;
using Maren.Shared;
using MediatR;
using Microsoft.Extensions.DependencyInjection;

namespace Maren.Tests;

/// <summary>
/// The client-derived credential path and the first encrypted records, end to
/// end through the real handlers and the real procedures.
/// </summary>
/// <remarks>
/// <para>
/// The envelopes here are opaque bytes rather than genuinely sealed records,
/// and that is the point rather than a shortcut: to this server an envelope
/// <i>is</i> opaque bytes, and a test that encrypted them properly would be
/// testing the client. What the real ciphertext looks like is pinned by the
/// cross-language vectors and by the codec's own suite.
/// </para>
/// <para>
/// What these tests are for is everything the server does have an opinion
/// about: that it stores what it was given without touching it, that it never
/// holds a password for these accounts, that one woman cannot reach another's
/// records, and that a stale write is refused rather than silently winning.
/// </para>
/// </remarks>
[Collection("database")]
public sealed class CryptoIntegrationTests(DatabaseFixture fixture) : IAsyncLifetime
{
    private const string Prefix = "crypto-slice-test-";

    public async Task InitializeAsync() => await CleanupAsync();

    public Task DisposeAsync() => Task.CompletedTask;

    private static string NewEmail() => Prefix + Guid.NewGuid().ToString("N") + "@example.com";

    private static DateOnly Aged(int years) =>
        DateOnly.FromDateTime(DateTime.UtcNow.AddYears(-years));

    private ISender Sender(IServiceScope scope) =>
        scope.ServiceProvider.GetRequiredService<ISender>();

    private static byte[] Bytes(int length, byte seed) =>
        Enumerable.Range(0, length).Select(i => (byte)(seed + i)).ToArray();

    /// <summary>An envelope-shaped blob. Opaque to this server, by design.</summary>
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

            DELETE FROM [Crypto].[Record]           WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Crypto].[RecoveryVerifier] WHERE GenerationId IN
                   (SELECT GenerationId FROM [Crypto].[Generation]
                     WHERE UserId IN (SELECT UserId FROM @ids));
            DELETE FROM [Crypto].[Wrapper]          WHERE GenerationId IN
                   (SELECT GenerationId FROM [Crypto].[Generation]
                     WHERE UserId IN (SELECT UserId FROM @ids));
            DELETE FROM [Crypto].[Generation]       WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Identity].[UserCredential] WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Identity].[RefreshToken]   WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Identity].[UserRole]       WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Identity].[Profile]        WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Audit].[AuditLog]          WHERE ActorUserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Identity].[User]           WHERE UserId IN (SELECT UserId FROM @ids);
            """,
            new { p = Prefix + "%" });
    }

    private async Task<(Guid UserId, string Email, byte[] AuthSecret)> RegisterAsync(
        int age = 30)
    {
        var email = NewEmail();
        var authSecret = RandomNumberGenerator.GetBytes(32);

        await using var scope = fixture.Provider.CreateAsyncScope();
        var profile = await scope.ServiceProvider
            .GetRequiredService<Maren.Application.Abstractions.ICryptoRepository>()
            .GetCurrentKdfProfileAsync(default);

        var result = await Sender(scope).Send(new RegisterClientDerivedCommand(
            new RegisterClientDerivedRequest(
                email, Aged(age), authSecret, Bytes(16, 0x10), profile!.KdfProfileId,
                Envelope(seed: 0x50), Envelope(seed: 0x60), Bytes(32, 0x70),
                "GB", "en-GB")));

        result.Succeeded.Should().BeTrue(result.FailureCode);
        return (result.Value!.UserId, email, authSecret);
    }

    // -----------------------------------------------------------------------
    // Key derivation parameters
    // -----------------------------------------------------------------------

    [Fact]
    public async Task An_unregistered_address_still_gets_parameters()
    {
        /*  This endpoint cannot be authenticated -- a device has nothing to
            authenticate with until it has derived a key, and it cannot derive
            one without these. So the only thing standing between it and an
            account enumeration oracle is that every address gets an answer. */
        await using var scope = fixture.Provider.CreateAsyncScope();
        var result = await Sender(scope).Send(
            new GetKdfParametersQuery("nobody-" + Guid.NewGuid().ToString("N") + "@example.com"));

        result.Succeeded.Should().BeTrue();
        result.Value!.Salt.Should().NotBeEmpty();
        result.Value.Algorithm.Should().Be("ARGON2ID");
    }

    [Fact]
    public async Task A_decoy_salt_is_the_same_every_time()
    {
        /*  A salt that changed between calls would say "no account here" as
            loudly as an error would. */
        var email = "stable-" + Guid.NewGuid().ToString("N") + "@example.com";

        await using var scope = fixture.Provider.CreateAsyncScope();
        var first = await Sender(scope).Send(new GetKdfParametersQuery(email));
        var second = await Sender(scope).Send(new GetKdfParametersQuery(email.ToUpperInvariant()));

        first.Value!.Salt.Should().Equal(second.Value!.Salt,
            "capitalisation must not reveal that the salt is synthetic");
    }

    [Fact]
    public async Task Different_addresses_get_different_decoys()
    {
        await using var scope = fixture.Provider.CreateAsyncScope();
        var a = await Sender(scope).Send(new GetKdfParametersQuery("a@example.com"));
        var b = await Sender(scope).Send(new GetKdfParametersQuery("b@example.com"));

        a.Value!.Salt.Should().NotEqual(b.Value!.Salt);
    }

    [Fact]
    public async Task A_registered_address_returns_its_own_salt()
    {
        var (_, email, _) = await RegisterAsync();

        await using var scope = fixture.Provider.CreateAsyncScope();
        var result = await Sender(scope).Send(new GetKdfParametersQuery(email));

        result.Value!.Salt.Should().Equal(Bytes(16, 0x10),
            "she must derive with the salt her credential was written with");
    }

    // -----------------------------------------------------------------------
    // Registration
    // -----------------------------------------------------------------------

    [Fact]
    public async Task Registration_creates_the_account_and_its_first_key_together()
    {
        var (userId, _, _) = await RegisterAsync();

        using var connection = DatabaseFixture.Open();

        var credentialVersion = await connection.QuerySingleAsync<int>(
            "SELECT CredentialVersion FROM [Identity].[UserCredential] " +
            "WHERE UserId = @userId AND IsAuthoritative = 1", new { userId });
        credentialVersion.Should().Be(2);

        var generations = await connection.QuerySingleAsync<int>(
            "SELECT COUNT(*) FROM [Crypto].[Generation] " +
            "WHERE UserId = @userId AND [State] = 'ACTIVE'", new { userId });
        generations.Should().Be(1);

        var wrappers = await connection.QueryAsync<string>(
            """
            SELECT w.WrapperKind FROM [Crypto].[Wrapper] w
            JOIN [Crypto].[Generation] g ON g.GenerationId = w.GenerationId
            WHERE g.UserId = @userId
            """, new { userId });
        wrappers.Should().BeEquivalentTo(["PASSWORD", "RECOVERY"]);
    }

    [Fact]
    public async Task A_client_derived_account_holds_no_password()
    {
        /*  The load-bearing property. If this server held password material
            for these accounts it could derive the key that opens the journal,
            because both come from the same master secret. */
        var (userId, _, _) = await RegisterAsync();

        using var connection = DatabaseFixture.Open();
        var material = await connection.QuerySingleAsync<int>(
            """
            SELECT COUNT(*) FROM [Identity].[User]
            WHERE UserId = @userId
              AND (PasswordHash IS NOT NULL OR PasswordSalt IS NOT NULL
                   OR PasswordIterations IS NOT NULL)
            """, new { userId });

        material.Should().Be(0, "the password never reached this server");
    }

    [Fact]
    public async Task Registration_is_refused_below_the_launch_age()
    {
        await using var scope = fixture.Provider.CreateAsyncScope();
        var profile = await scope.ServiceProvider
            .GetRequiredService<Maren.Application.Abstractions.ICryptoRepository>()
            .GetCurrentKdfProfileAsync(default);

        var email = NewEmail();
        var result = await Sender(scope).Send(new RegisterClientDerivedCommand(
            new RegisterClientDerivedRequest(
                email, Aged(12), RandomNumberGenerator.GetBytes(32), Bytes(16, 0x10),
                profile!.KdfProfileId, Envelope(), Envelope(), Bytes(32, 0x70),
                null, null)));

        result.Succeeded.Should().BeFalse();
        result.FailureCode.Should().Be("UNDER_MINIMUM_AGE");

        using var connection = DatabaseFixture.Open();
        var rows = await connection.QuerySingleAsync<int>(
            "SELECT COUNT(*) FROM [Identity].[User] WHERE Email = @email", new { email });
        rows.Should().Be(0, "a refused registration keeps nothing about her");
    }

    // -----------------------------------------------------------------------
    // Signing in
    // -----------------------------------------------------------------------

    [Fact]
    public async Task She_can_sign_in_with_the_secret_her_device_derived()
    {
        var (userId, email, authSecret) = await RegisterAsync();

        await using var scope = fixture.Provider.CreateAsyncScope();
        var result = await Sender(scope).Send(new LoginClientDerivedCommand(
            new LoginClientDerivedRequest(email, authSecret)));

        result.Succeeded.Should().BeTrue(result.FailureCode);
        result.Value!.UserId.Should().Be(userId);
        result.Value.AccessToken.Should().NotBeNullOrWhiteSpace();
    }

    [Fact]
    public async Task A_wrong_secret_is_refused()
    {
        var (_, email, _) = await RegisterAsync();

        await using var scope = fixture.Provider.CreateAsyncScope();
        var result = await Sender(scope).Send(new LoginClientDerivedCommand(
            new LoginClientDerivedRequest(email, RandomNumberGenerator.GetBytes(32))));

        result.Succeeded.Should().BeFalse();
        result.FailureCode.Should().Be(FailureCodes.InvalidCredentials);
    }

    [Fact]
    public async Task An_unknown_address_fails_the_same_way_as_a_wrong_secret()
    {
        await using var scope = fixture.Provider.CreateAsyncScope();
        var result = await Sender(scope).Send(new LoginClientDerivedCommand(
            new LoginClientDerivedRequest(NewEmail(), RandomNumberGenerator.GetBytes(32))));

        result.FailureCode.Should().Be(FailureCodes.InvalidCredentials);
    }

    [Fact]
    public async Task The_version_one_login_path_refuses_a_client_derived_account()
    {
        /*  Enforced in usp_User_GetForLogin rather than by routing in the API,
            so the old material is unreachable rather than merely unused. */
        var (_, email, _) = await RegisterAsync();

        await using var scope = fixture.Provider.CreateAsyncScope();
        var result = await Sender(scope).Send(new LoginCommand(
            new LoginRequest(email, "whatever the password would have been", null)));

        result.Succeeded.Should().BeFalse();
        result.FailureCode.Should().Be(FailureCodes.InvalidCredentials);
    }

    // -----------------------------------------------------------------------
    // The key hierarchy she signs in to
    // -----------------------------------------------------------------------

    [Fact]
    public async Task She_gets_back_the_wrapped_keys_that_open_her_generation()
    {
        var (userId, _, _) = await RegisterAsync();
        fixture.CurrentUser.UserId = userId;

        await using var scope = fixture.Provider.CreateAsyncScope();
        var result = await Sender(scope).Send(new GetActiveGenerationQuery());

        result.Succeeded.Should().BeTrue(result.FailureCode);
        result.Value!.GenerationNumber.Should().Be(1);
        result.Value.State.Should().Be("ACTIVE");
        result.Value.Wrappers.Select(w => w.Kind)
            .Should().BeEquivalentTo(["PASSWORD", "RECOVERY"]);

        result.Value.Wrappers.Single(w => w.Kind == "PASSWORD").Envelope
            .Should().Equal(Envelope(seed: 0x50),
                "a wrapper comes back exactly as it was stored");
    }

    // -----------------------------------------------------------------------
    // Records
    // -----------------------------------------------------------------------

    [Fact]
    public async Task A_record_round_trips_byte_for_byte()
    {
        var (userId, _, _) = await RegisterAsync();
        fixture.CurrentUser.UserId = userId;

        var recordId = Guid.NewGuid();
        var envelope = Envelope(1024, 0x11);

        await using var scope = fixture.Provider.CreateAsyncScope();
        var saved = await Sender(scope).Send(new SaveRecordCommand(
            new SaveRecordRequest(recordId, "journal.entry", 1, 1, envelope)));
        saved.Succeeded.Should().BeTrue(saved.FailureCode);

        var read = await Sender(scope).Send(new GetRecordQuery(recordId));
        read.Succeeded.Should().BeTrue();
        read.Value!.Envelope.Should().Equal(envelope,
            "the server stores ciphertext and must not touch it");

        /*  And the same bytes in the table, not merely the same bytes back out
            of a cache. */
        using var connection = DatabaseFixture.Open();
        var stored = await connection.QuerySingleAsync<byte[]>(
            "SELECT Envelope FROM [Crypto].[Record] WHERE RecordId = @recordId",
            new { recordId });
        stored.Should().Equal(envelope);
    }

    [Fact]
    public async Task A_record_is_written_into_the_active_generation()
    {
        var (userId, _, _) = await RegisterAsync();
        fixture.CurrentUser.UserId = userId;

        var recordId = Guid.NewGuid();

        await using var scope = fixture.Provider.CreateAsyncScope();
        await Sender(scope).Send(new SaveRecordCommand(
            new SaveRecordRequest(recordId, "journal.entry", 1, 1, Envelope())));

        var read = await Sender(scope).Send(new GetRecordQuery(recordId));
        read.Value!.GenerationNumber.Should().Be(1,
            "the client never names a generation; the server resolves it");
    }

    [Fact]
    public async Task A_stale_write_is_refused()
    {
        var (userId, _, _) = await RegisterAsync();
        fixture.CurrentUser.UserId = userId;

        var recordId = Guid.NewGuid();

        await using var scope = fixture.Provider.CreateAsyncScope();
        await Sender(scope).Send(new SaveRecordCommand(
            new SaveRecordRequest(recordId, "journal.entry", 1, 1, Envelope())));

        /*  Two devices editing the same entry is ordinary, not exceptional.
            The second write has to be told, not silently dropped and not
            silently allowed to win. */
        var stale = await Sender(scope).Send(new SaveRecordCommand(
            new SaveRecordRequest(recordId, "journal.entry", 1, 1, Envelope(seed: 0x99))));

        stale.Succeeded.Should().BeFalse();
        stale.FailureCode.Should().Be("VERSION_CONFLICT");
    }

    [Fact]
    public async Task A_correctly_versioned_update_succeeds()
    {
        var (userId, _, _) = await RegisterAsync();
        fixture.CurrentUser.UserId = userId;

        var recordId = Guid.NewGuid();
        var second = Envelope(512, 0x22);

        await using var scope = fixture.Provider.CreateAsyncScope();
        await Sender(scope).Send(new SaveRecordCommand(
            new SaveRecordRequest(recordId, "journal.entry", 1, 1, Envelope())));

        var updated = await Sender(scope).Send(new SaveRecordCommand(
            new SaveRecordRequest(recordId, "journal.entry", 1, 2, second)));

        updated.Succeeded.Should().BeTrue(updated.FailureCode);

        var read = await Sender(scope).Send(new GetRecordQuery(recordId));
        read.Value!.Version.Should().Be(2);
        read.Value.Envelope.Should().Equal(second);
    }

    [Fact]
    public async Task Another_account_cannot_read_her_record()
    {
        var (hers, _, _) = await RegisterAsync();
        var (his, _, _) = await RegisterAsync();

        var recordId = Guid.NewGuid();

        fixture.CurrentUser.UserId = hers;
        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            await Sender(scope).Send(new SaveRecordCommand(
                new SaveRecordRequest(recordId, "journal.entry", 1, 1, Envelope())));
        }

        fixture.CurrentUser.UserId = his;
        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            var read = await Sender(scope).Send(new GetRecordQuery(recordId));

            /*  Not-found rather than forbidden. Distinguishing them would
                confirm the id exists, and there is no legitimate way to have
                guessed one. */
            read.Succeeded.Should().BeFalse();
            read.FailureCode.Should().Be(FailureCodes.NotFound);
        }
    }

    [Fact]
    public async Task Another_account_cannot_overwrite_her_record()
    {
        var (hers, _, _) = await RegisterAsync();
        var (his, _, _) = await RegisterAsync();

        var recordId = Guid.NewGuid();
        var original = Envelope(256, 0x33);

        fixture.CurrentUser.UserId = hers;
        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            await Sender(scope).Send(new SaveRecordCommand(
                new SaveRecordRequest(recordId, "journal.entry", 1, 1, original)));
        }

        fixture.CurrentUser.UserId = his;
        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            var hijack = await Sender(scope).Send(new SaveRecordCommand(
                new SaveRecordRequest(recordId, "journal.entry", 1, 1, Envelope(seed: 0x77))));
            hijack.Succeeded.Should().BeFalse();
        }

        using var connection = DatabaseFixture.Open();
        var stored = await connection.QuerySingleAsync<byte[]>(
            "SELECT Envelope FROM [Crypto].[Record] WHERE RecordId = @recordId",
            new { recordId });
        stored.Should().Equal(original, "hers is untouched");
    }

    [Fact]
    public async Task A_list_only_ever_shows_her_own()
    {
        var (hers, _, _) = await RegisterAsync();
        var (his, _, _) = await RegisterAsync();

        fixture.CurrentUser.UserId = hers;
        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            for (var i = 1; i <= 3; i++)
            {
                await Sender(scope).Send(new SaveRecordCommand(
                    new SaveRecordRequest(Guid.NewGuid(), "journal.entry", 1, 1, Envelope())));
            }
        }

        fixture.CurrentUser.UserId = his;
        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            var list = await Sender(scope).Send(new GetRecordsQuery(null, 0, 50));
            list.Value.Should().BeEmpty();
        }

        fixture.CurrentUser.UserId = hers;
        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            var list = await Sender(scope).Send(new GetRecordsQuery(null, 0, 50));
            list.Value.Should().HaveCount(3);
        }
    }

    [Fact]
    public async Task Deleting_a_record_removes_the_row()
    {
        var (userId, _, _) = await RegisterAsync();
        fixture.CurrentUser.UserId = userId;

        var recordId = Guid.NewGuid();

        await using var scope = fixture.Provider.CreateAsyncScope();
        await Sender(scope).Send(new SaveRecordCommand(
            new SaveRecordRequest(recordId, "journal.entry", 1, 1, Envelope())));

        var deleted = await Sender(scope).Send(new DeleteRecordCommand(recordId));
        deleted.Succeeded.Should().BeTrue();

        using var connection = DatabaseFixture.Open();
        var rows = await connection.QuerySingleAsync<int>(
            "SELECT COUNT(*) FROM [Crypto].[Record] WHERE RecordId = @recordId",
            new { recordId });
        rows.Should().Be(0, "deletion is deletion, not a flag");
    }

    [Fact]
    public async Task Another_account_cannot_delete_her_record()
    {
        var (hers, _, _) = await RegisterAsync();
        var (his, _, _) = await RegisterAsync();

        var recordId = Guid.NewGuid();

        fixture.CurrentUser.UserId = hers;
        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            await Sender(scope).Send(new SaveRecordCommand(
                new SaveRecordRequest(recordId, "journal.entry", 1, 1, Envelope())));
        }

        fixture.CurrentUser.UserId = his;
        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            var deleted = await Sender(scope).Send(new DeleteRecordCommand(recordId));
            deleted.Succeeded.Should().BeFalse();
        }

        using var connection = DatabaseFixture.Open();
        var rows = await connection.QuerySingleAsync<int>(
            "SELECT COUNT(*) FROM [Crypto].[Record] WHERE RecordId = @recordId",
            new { recordId });
        rows.Should().Be(1);
    }

    // -----------------------------------------------------------------------
    // What an operator sees
    // -----------------------------------------------------------------------

    [Fact]
    public async Task An_operator_sees_counts_and_no_content()
    {
        var (userId, email, _) = await RegisterAsync();
        fixture.CurrentUser.UserId = userId;

        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            await Sender(scope).Send(new SaveRecordCommand(
                new SaveRecordRequest(Guid.NewGuid(), "journal.entry", 1, 1, Envelope())));
            await Sender(scope).Send(new SaveRecordCommand(
                new SaveRecordRequest(Guid.NewGuid(), "journal.entry", 1, 1, Envelope())));
        }

        fixture.CurrentUser.With(PlatformPermissions.UsersRead);

        await using var operatorScope = fixture.Provider.CreateAsyncScope();
        var summary = await Sender(operatorScope).Send(
            new GetCryptoAccountSummaryQuery(userId));

        summary.Succeeded.Should().BeTrue(summary.FailureCode);
        summary.Value!.RecordCount.Should().Be(2);
        summary.Value.ActiveGenerationNumber.Should().Be(1);
        summary.Value.GenerationCount.Should().Be(1);
        summary.Value.HasRecoveryWrapper.Should().BeTrue();
        summary.Value.Email.Should().Be(email);

        /*  The contract has no field that could carry an envelope, a kind
            breakdown or a per-record time. That is asserted by the type, and
            stated here so the next person adding "just one more field" reads
            it first. */
        typeof(CryptoAccountSummary).GetProperties()
            .Select(p => p.Name)
            .Should().BeEquivalentTo(
            [
                nameof(CryptoAccountSummary.UserId),
                nameof(CryptoAccountSummary.Email),
                nameof(CryptoAccountSummary.GenerationCount),
                nameof(CryptoAccountSummary.ActiveGenerationNumber),
                nameof(CryptoAccountSummary.RecordCount),
                nameof(CryptoAccountSummary.HasRecoveryWrapper),
                nameof(CryptoAccountSummary.FirstRecordOn),
                nameof(CryptoAccountSummary.LastRecordOn)
            ], "an operator sees that records exist, never what is in them");
    }

    [Fact]
    public async Task An_operator_without_permission_is_refused()
    {
        var (userId, _, _) = await RegisterAsync();
        fixture.CurrentUser.With();

        await using var scope = fixture.Provider.CreateAsyncScope();

        /*  The authorization behaviour throws rather than returning a failed
            Result, and the refusal happens in the pipeline before the handler
            is constructed — which is the property worth asserting. A handler
            that checked its own permission could be reached by another handler
            calling it directly; this one cannot be reached at all. */
        var refusal = async () =>
            await Sender(scope).Send(new GetCryptoAccountSummaryQuery(userId));

        await refusal.Should().ThrowAsync<Maren.Application.Behaviors.UnauthorizedRequestException>();
    }
}
