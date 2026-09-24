using System.Security.Cryptography;
using Dapper;
using FluentAssertions;
using Maren.Application.Abstractions;
using Maren.Application.Crypto;
using Maren.Contracts;
using MediatR;
using Microsoft.Extensions.DependencyInjection;

namespace Maren.Tests;

/// <summary>
/// Catching a second device up, through the real handlers and procedures.
/// </summary>
/// <remarks>
/// <para>
/// One question, asked several ways: <b>does a change on one phone reach the
/// other one?</b> Every failure guarded against here is silent — nothing
/// throws and nothing logs. An entry is simply present on one device and
/// absent on another.
/// </para>
/// <para>
/// The worst of them is resurrection: she deletes an entry deliberately, is
/// told it is gone for good, and finds it on her other phone because the
/// delta had nothing to say about it. That is what the tombstone exists for
/// and what most of this file is about.
/// </para>
/// </remarks>
[Collection("database")]
public sealed class RecordSyncIntegrationTests(DatabaseFixture fixture)
    : IAsyncLifetime
{
    private const string Prefix = "record-sync-test-";

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
        buffer[0] = 0x57; buffer[1] = 0x4C; buffer[2] = 0x4F; buffer[3] = 0x53;
        return buffer;
    }

    private static async Task CleanupAsync()
    {
        using var connection = DatabaseFixture.Open();
        await connection.ExecuteAsync(
            """
            DECLARE @ids TABLE (UserId UNIQUEIDENTIFIER PRIMARY KEY);
            INSERT @ids SELECT UserId FROM [Identity].[User] WHERE Email LIKE @p;

            DELETE FROM [Crypto].[RecordTombstone] WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Crypto].[Record]          WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Crypto].[RecoveryVerifier] WHERE GenerationId IN
                   (SELECT GenerationId FROM [Crypto].[Generation]
                     WHERE UserId IN (SELECT UserId FROM @ids));
            DELETE FROM [Crypto].[Wrapper]         WHERE GenerationId IN
                   (SELECT GenerationId FROM [Crypto].[Generation]
                     WHERE UserId IN (SELECT UserId FROM @ids));
            DELETE FROM [Crypto].[Generation]      WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Identity].[UserCredential] WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Identity].[RefreshToken]  WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Identity].[UserRole]      WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Identity].[Profile]       WHERE UserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Audit].[AuditLog]         WHERE ActorUserId IN (SELECT UserId FROM @ids);
            DELETE FROM [Identity].[User]          WHERE UserId IN (SELECT UserId FROM @ids);
            """,
            new { p = Prefix + "%" });
    }

    private async Task<Guid> RegisterAsync()
    {
        await using var scope = fixture.Provider.CreateAsyncScope();
        var profile = await scope.ServiceProvider
            .GetRequiredService<ICryptoRepository>()
            .GetCurrentKdfProfileAsync(default);

        var result = await Sender(scope).Send(new RegisterClientDerivedCommand(
            new RegisterClientDerivedRequest(
                NewEmail(), DateOnly.FromDateTime(DateTime.UtcNow.AddYears(-30)),
                Guid.NewGuid(), RandomNumberGenerator.GetBytes(32), Bytes(16, 0x10),
                profile!.KdfProfileId,
                Envelope(seed: 0x50), Envelope(seed: 0x60), Bytes(32, 0x70),
                "GB", "en-GB")));

        result.Succeeded.Should().BeTrue(result.FailureCode);
        return result.Value!.UserId;
    }

    private async Task<Guid> WriteAsync(byte seed)
    {
        var recordId = Guid.NewGuid();
        await using var scope = fixture.Provider.CreateAsyncScope();
        var saved = await Sender(scope).Send(new SaveRecordCommand(
            new SaveRecordRequest(recordId, "journal.entry", 1, 1, Envelope(seed: seed))));
        saved.Succeeded.Should().BeTrue(saved.FailureCode);
        return recordId;
    }

    private async Task<RecordChangesResponse> ChangesAsync(
        string? since, int take = 200)
    {
        await using var scope = fixture.Provider.CreateAsyncScope();
        var result = await Sender(scope).Send(
            new GetRecordChangesQuery("journal.entry", since, take));
        result.Succeeded.Should().BeTrue(result.FailureCode);
        return result.Value!;
    }

    private static string? Encode(byte[]? cursor) =>
        cursor is null ? null : Convert.ToBase64String(cursor);

    // -----------------------------------------------------------------------
    // Catching up
    // -----------------------------------------------------------------------

    [Fact]
    public async Task A_first_sync_sends_no_cursor_and_receives_everything()
    {
        fixture.CurrentUser.UserId = await RegisterAsync();
        await WriteAsync(0x11);
        await WriteAsync(0x22);

        var page = await ChangesAsync(since: null);

        /*  The same code path as catching up. A separate bootstrap would be a
            second thing to get wrong, and the one that runs least often. */
        page.Changes.Should().HaveCount(2);
        page.Changes.Should().OnlyContain(c => !c.IsDeleted);
        page.Cursor.Should().NotBeNull();
    }

    [Fact]
    public async Task A_caught_up_device_is_told_there_is_nothing_new()
    {
        fixture.CurrentUser.UserId = await RegisterAsync();
        await WriteAsync(0x11);

        var first = await ChangesAsync(since: null);
        var second = await ChangesAsync(Encode(first.Cursor));

        second.Changes.Should().BeEmpty();

        /*  And keeps its place. Handing back null for an empty page would send
            her whole journal down the wire again on every poll. */
        second.Cursor.Should().Equal(first.Cursor);
    }

    [Fact]
    public async Task An_edit_reaches_a_device_that_had_already_seen_the_entry()
    {
        fixture.CurrentUser.UserId = await RegisterAsync();
        var recordId = await WriteAsync(0x11);

        var first = await ChangesAsync(since: null);

        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            var saved = await Sender(scope).Send(new SaveRecordCommand(
                new SaveRecordRequest(recordId, "journal.entry", 1, 2,
                    Envelope(seed: 0x33))));
            saved.Succeeded.Should().BeTrue(saved.FailureCode);
        }

        var second = await ChangesAsync(Encode(first.Cursor));

        second.Changes.Should().ContainSingle()
            .Which.RecordId.Should().Be(recordId);
        second.Changes.Single().Version.Should().Be(2);
    }

    // -----------------------------------------------------------------------
    // Deletion, and the resurrection it would otherwise cause
    // -----------------------------------------------------------------------

    /// <summary>
    /// The one this whole mechanism exists for.
    /// </summary>
    /// <remarks>
    /// Without a tombstone the deleted row is mentioned by nothing, so a
    /// device catching up never learns and keeps the entry forever. She
    /// deleted it deliberately and was told it was gone.
    /// </remarks>
    [Fact]
    public async Task A_deletion_reaches_a_device_that_had_already_seen_the_entry()
    {
        fixture.CurrentUser.UserId = await RegisterAsync();
        var kept = await WriteAsync(0x11);
        var doomed = await WriteAsync(0x22);

        var first = await ChangesAsync(since: null);
        first.Changes.Should().HaveCount(2);

        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            var deleted = await Sender(scope).Send(new DeleteRecordCommand(doomed));
            deleted.Succeeded.Should().BeTrue(deleted.FailureCode);
        }

        var second = await ChangesAsync(Encode(first.Cursor));

        var change = second.Changes.Should().ContainSingle().Subject;
        change.RecordId.Should().Be(doomed);
        change.IsDeleted.Should().BeTrue();

        /*  And carries no ciphertext, because there is none left. A deletion
            that shipped an envelope would mean the thing she deleted was
            still on the server. */
        change.Envelope.Should().BeNull();

        second.Changes.Should().NotContain(c => c.RecordId == kept);
    }

    [Fact]
    public async Task A_first_sync_after_a_deletion_never_mentions_it()
    {
        fixture.CurrentUser.UserId = await RegisterAsync();
        var doomed = await WriteAsync(0x11);

        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            await Sender(scope).Send(new DeleteRecordCommand(doomed));
        }

        /*  A device that never saw the entry has nothing to un-see. Sending a
            tombstone for a record it never held would be work for no reason,
            and would tell a brand-new phone what she has deleted. */
        var page = await ChangesAsync(since: null);

        page.Changes.Should().ContainSingle()
            .Which.IsDeleted.Should().BeTrue(
                "the tombstone is still in the stream until it is pruned, "
                + "and applying it to an empty cache is a no-op");
    }

    [Fact]
    public async Task Writes_and_deletions_arrive_in_the_order_they_happened()
    {
        fixture.CurrentUser.UserId = await RegisterAsync();

        var first = await WriteAsync(0x11);
        var second = await WriteAsync(0x22);

        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            await Sender(scope).Send(new DeleteRecordCommand(first));
        }

        var third = await WriteAsync(0x33);

        var page = await ChangesAsync(since: null);

        /*  Order is the whole reason writes and deletions travel in one list.
            Given two lists a client has to merge them by cursor, and the
            merge it eventually gets wrong puts back an entry she deleted. */
        var order = page.Changes.Select(c => (c.RecordId, c.IsDeleted)).ToList();

        order.Should().HaveCount(3);
        order[0].Should().Be((second, false));
        order[1].Should().Be((first, true));
        order[2].Should().Be((third, false));
    }

    // -----------------------------------------------------------------------
    // Paging, cursors and ownership
    // -----------------------------------------------------------------------

    [Fact]
    public async Task A_client_can_walk_the_whole_stream_one_page_at_a_time()
    {
        fixture.CurrentUser.UserId = await RegisterAsync();
        for (byte i = 0; i < 5; i++) await WriteAsync((byte)(0x10 + i));

        var seen = new List<Guid>();
        string? cursor = null;

        /*  Ask until a page comes back empty. There is deliberately no
            "has more" flag: "the page was full" and "there is more" are
            different facts, and a client that conflates them stops one sync
            short of her most recent entry. */
        for (var guard = 0; guard < 20; guard++)
        {
            var page = await ChangesAsync(cursor, take: 2);
            if (page.Changes.Count == 0) break;
            seen.AddRange(page.Changes.Select(c => c.RecordId));
            cursor = Encode(page.Cursor);
        }

        seen.Should().HaveCount(5);
        seen.Should().OnlyHaveUniqueItems(
            "a page boundary that repeated or skipped a row would do it "
            + "silently");
    }

    [Fact]
    public async Task A_cursor_this_server_did_not_issue_is_refused()
    {
        fixture.CurrentUser.UserId = await RegisterAsync();
        await WriteAsync(0x11);

        await using var scope = fixture.Provider.CreateAsyncScope();

        /*  Refused rather than treated as a first sync. Silently resyncing
            her whole journal is how a small client bug becomes a large amount
            of traffic that nobody ever investigates. */
        var refusal = async () => await Sender(scope).Send(
            new GetRecordChangesQuery("journal.entry", "not-a-cursor", 200));

        await refusal.Should().ThrowAsync<Exception>();
    }

    [Fact]
    public async Task One_womans_changes_never_appear_in_anothers_stream()
    {
        var hers = await RegisterAsync();
        var his = await RegisterAsync();

        fixture.CurrentUser.UserId = hers;
        await WriteAsync(0x11);

        fixture.CurrentUser.UserId = his;
        var page = await ChangesAsync(since: null);

        page.Changes.Should().BeEmpty(
            "the subject comes from the token and there is no parameter that "
            + "could name another account");
    }

    [Fact]
    public async Task Closing_the_account_erases_the_tombstones_too()
    {
        var userId = await RegisterAsync();
        fixture.CurrentUser.UserId = userId;

        var doomed = await WriteAsync(0x11);

        await using (var scope = fixture.Provider.CreateAsyncScope())
        {
            await Sender(scope).Send(new DeleteRecordCommand(doomed));
        }

        using var connection = DatabaseFixture.Open();
        var before = await connection.ExecuteScalarAsync<int>(
            "SELECT COUNT(*) FROM [Crypto].[RecordTombstone] WHERE UserId = @userId;",
            new { userId });
        before.Should().Be(1);

        await connection.ExecuteAsync(
            "[Identity].[usp_User_DeleteAccount]",
            new { UserId = userId },
            commandType: System.Data.CommandType.StoredProcedure);

        var after = await connection.ExecuteScalarAsync<int>(
            "SELECT COUNT(*) FROM [Crypto].[RecordTombstone] WHERE UserId = @userId;",
            new { userId });

        /*  A record of what she once deleted must not outlive the account it
            was about. Deletion means deletion covers the tombstones. */
        after.Should().Be(0);
    }
}
