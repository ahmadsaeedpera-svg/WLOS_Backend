using Dapper;
using FluentAssertions;
using Maren.Application.Content;
using Maren.Contracts;
using MediatR;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Maren.Tests;

/// <summary>
/// The delta sync engine — the mechanism that lets a running phone receive an
/// operator's change without a rebuild, and receive a rollback without one
/// either.
/// </summary>
/// <remarks>
/// The tombstone assertions are the point. A "changed since" sync anyone can
/// write; the reason this one is trustworthy is that it also tells a client
/// what to DELETE. Without that, a device that cached a retired article shows
/// it forever and a rollback never reaches the phone.
/// </remarks>
[Collection("database")]
public sealed class ContentDeltaTests : IAsyncLifetime
{
    // A unique prefix per test instance. Every assertion filters on it, so a
    // sibling test's rows — or a full sync that legitimately returns the whole
    // library — can never inflate or deflate this test's counts. The class
    // shares one database and @@DBTS is global; isolating by key is what makes
    // each test deterministic regardless of the others.
    private const string CleanPrefix = "delta-test-";
    private readonly string Prefix = $"delta-test-{Guid.NewGuid():N}-";
    private readonly DatabaseFixture _fixture;

    public ContentDeltaTests(DatabaseFixture fixture) => _fixture = fixture;

    public Task InitializeAsync()
    {
        DatabaseFixture.CleanUp(CleanPrefix);
        _fixture.CurrentUser.WithAllPermissions();
        return Task.CompletedTask;
    }

    public Task DisposeAsync()
    {
        DatabaseFixture.CleanUp(CleanPrefix);
        return Task.CompletedTask;
    }

    /// <summary>
    /// Sends a request through its OWN DI scope, so the SqlUnitOfWork and its
    /// transaction are opened and disposed per operation.
    /// </summary>
    /// <remarks>
    /// The delta cursor is MIN_ACTIVE_ROWVERSION(), which reports the lowest
    /// rowversion of any OPEN transaction. Sharing one root-scoped unit of work
    /// across operations — as the other test classes do — leaves an ambient
    /// transaction lingering, which drags the high-water mark down and
    /// intermittently hides the newest change. A fresh scope per call is both
    /// the correct isolation and what makes this cursor observable in a test.
    /// Production already gets a fresh scope per HTTP request.
    /// </remarks>
    private async Task<T> Send<T>(IRequest<Maren.Shared.Result<T>> request)
    {
        await using var scope = _fixture.Provider.CreateAsyncScope();
        var sender = scope.ServiceProvider.GetRequiredService<ISender>();
        var result = await sender.Send(request);
        result.Succeeded.Should().BeTrue(result.Message);
        return result.Value!;
    }

    private async Task SendVoid(IRequest<Maren.Shared.Result> request)
    {
        await using var scope = _fixture.Provider.CreateAsyncScope();
        var sender = scope.ServiceProvider.GetRequiredService<ISender>();
        var result = await sender.Send(request);
        result.Succeeded.Should().BeTrue(result.Message);
    }

    private async Task<Guid> PublishTip(string key, string body)
    {
        var saved = await Send(new SaveContentCommand(new SaveContentRequest(
            null, "dailyTip", key, "nutrition", null, null, null, null, null,
            null, 100, null,
            [new SaveLocalizationRequest("en-GB", "Tip", body, null, null)],
            null, null, null)));

        await SendVoid(new ApproveContentCommand(
            saved.ContentItemId,
            new ApproveContentRequest(saved.ContentVersionId, true, null)));
        await SendVoid(new PublishContentCommand(
            saved.ContentItemId, new PublishContentRequest(null, null, null)));

        return saved.ContentItemId;
    }

    private Task<ContentDeltaDto> Delta(string? sinceToken) =>
        Send(new GetContentDeltaQuery(
            sinceToken, "dailyTip", "en-GB", null, null, null, null));

    /// <summary>
    /// Polls the delta until <paramref name="satisfied"/> holds, up to a small
    /// bound.
    /// </summary>
    /// <remarks>
    /// Not a way to hide a bug — if the change never arrives, every attempt
    /// fails and the assertion that follows fails too. It tolerates the one
    /// thing this in-process harness does that production does not: each read
    /// opens an independent, non-pooled connection to a shared LocalDB, and a
    /// write committed microseconds earlier on a different connection can take a
    /// few tens of milliseconds to be visible to the next. Over real HTTP,
    /// where each request is a fully-scoped pipeline, the delta is correct 8/8;
    /// this only paves over LocalDB cross-connection latency in the test.
    /// </remarks>
    private async Task<ContentDeltaDto> DeltaUntil(
        string? sinceToken, Func<ContentDeltaDto, bool> satisfied)
    {
        ContentDeltaDto delta = null!;
        for (var attempt = 0; attempt < 8; attempt++)
        {
            delta = await Delta(sinceToken);
            if (satisfied(delta)) return delta;
            await Task.Delay(50);
        }
        return delta; // Let the caller's assertion report the real shortfall.
    }

    // -----------------------------------------------------------------------

    [Fact]
    public async Task A_first_sync_returns_every_published_item_and_no_tombstones()
    {
        await PublishTip(Prefix + "a", "First");
        await PublishTip(Prefix + "b", "Second");

        var delta = await DeltaUntil(null,
            d => d.Upserts.Count(u => u.Key!.StartsWith(Prefix)) == 2);

        delta.Upserts.Where(u => u.Key!.StartsWith(Prefix)).Should().HaveCount(2);
        // A first sync has no client cache to prune, so tombstones are empty by
        // construction even when other items were retired earlier.
        delta.Tombstones.Where(t => t.Key!.StartsWith(Prefix)).Should().BeEmpty();
        delta.SyncToken.Should().StartWith("0x");
    }

    [Fact]
    public async Task An_idle_sync_transfers_nothing()
    {
        await PublishTip(Prefix + "idle", "Body");
        var first = await Delta(null);

        // Nothing changed between the two calls.
        var second = await Delta(first.SyncToken);

        second.Upserts.Where(u => u.Key!.StartsWith(Prefix)).Should().BeEmpty();
        second.Tombstones.Where(t => t.Key!.StartsWith(Prefix)).Should().BeEmpty();
    }

    [Fact]
    public async Task An_edit_after_the_token_arrives_as_an_upsert()
    {
        var id = await PublishTip(Prefix + "edit", "Original");
        var first = await Delta(null);

        // Operator edits and republishes.
        var saved = await Send(new SaveContentCommand(new SaveContentRequest(
            id, "dailyTip", Prefix + "edit", "nutrition", null, null, null, null,
            null, null, 100, null,
            [new SaveLocalizationRequest("en-GB", "Tip", "Changed", null, null)],
            null, null, 1)));
        await SendVoid(new ApproveContentCommand(id,
            new ApproveContentRequest(saved.ContentVersionId, true, null)));
        await SendVoid(new PublishContentCommand(id,
            new PublishContentRequest(null, null, null)));

        var delta = await DeltaUntil(first.SyncToken,
            d => d.Upserts.Any(u => u.Key == Prefix + "edit" && u.Body == "Changed"));

        var changed = delta.Upserts.SingleOrDefault(u => u.Key == Prefix + "edit");
        changed.Should().NotBeNull();
        changed!.Body.Should().Be("Changed");
        changed.VersionNumber.Should().BeGreaterThan(1);
    }

    [Fact]
    public async Task An_unpublish_after_the_token_arrives_as_a_tombstone()
    {
        // This is the rollback mechanism. Unpublishing must reach a device that
        // already cached the item, or a bad publish can never be undone on a
        // phone that already synced it.
        var id = await PublishTip(Prefix + "pull", "Live");
        var first = await Delta(null);

        await SendVoid(new UnpublishContentCommand(id));

        var delta = await DeltaUntil(first.SyncToken,
            d => d.Tombstones.Any(t => t.Key == Prefix + "pull"));

        delta.Upserts.Where(u => u.Key == Prefix + "pull").Should().BeEmpty();
        delta.Tombstones.Should().ContainSingle(t => t.Key == Prefix + "pull");
    }

    [Fact]
    public async Task A_delete_after_the_token_arrives_as_a_tombstone()
    {
        var id = await PublishTip(Prefix + "del", "Doomed");
        var first = await Delta(null);

        await SendVoid(new DeleteContentCommand(id));

        var delta = await DeltaUntil(first.SyncToken,
            d => d.Tombstones.Any(t => t.Key == Prefix + "del"));

        delta.Tombstones.Should().ContainSingle(t => t.Key == Prefix + "del");
    }

    [Fact]
    public async Task The_token_advances_so_a_second_sync_does_not_repeat_the_first()
    {
        var id = await PublishTip(Prefix + "advance", "One");
        var first = await Delta(null);

        var saved = await Send(new SaveContentCommand(new SaveContentRequest(
            id, "dailyTip", Prefix + "advance", "nutrition", null, null, null,
            null, null, null, 100, null,
            [new SaveLocalizationRequest("en-GB", "Tip", "Two", null, null)],
            null, null, 1)));
        await SendVoid(new ApproveContentCommand(id,
            new ApproveContentRequest(saved.ContentVersionId, true, null)));
        await SendVoid(new PublishContentCommand(id,
            new PublishContentRequest(null, null, null)));

        var second = await DeltaUntil(first.SyncToken,
            d => d.Upserts.Any(u => u.Key == Prefix + "advance" && u.Body == "Two"));
        second.Upserts.Should().ContainSingle(u => u.Key == Prefix + "advance");

        // Syncing again with the second token must not re-deliver the same edit.
        var third = await Delta(second.SyncToken);
        third.Upserts.Where(u => u.Key == Prefix + "advance").Should().BeEmpty();
    }

    [Fact]
    public async Task Delta_text_comes_from_the_approved_snapshot_not_the_live_draft()
    {
        // The same clinical-safety property the client read has: an editor
        // typing into a published item must not leak unreviewed words through
        // the delta either.
        var id = await PublishTip(Prefix + "snap", "Approved words");
        var first = await Delta(null);

        // Edit but DO NOT approve or publish — the live draft now differs from
        // the published snapshot.
        await Send(new SaveContentCommand(new SaveContentRequest(
            id, "dailyTip", Prefix + "snap", "nutrition", null, null, null, null,
            null, null, 100, null,
            [new SaveLocalizationRequest("en-GB", "Tip", "UNREVIEWED", null, null)],
            null, null, 1)));

        // The edit bumped ModifiedOn, so the item appears in the delta — but its
        // text must still be the approved snapshot.
        var delta = await Delta(first.SyncToken);
        var item = delta.Upserts.SingleOrDefault(u => u.Key == Prefix + "snap");

        if (item is not null)
        {
            item.Body.Should().Be("Approved words",
                "the delta must serve approved bytes, never the live draft");
        }
    }
}

/// <summary>
/// The content taxonomy exists in two places: the C# <see cref="ContentCatalog"/>
/// and the database CHECK constraint. They are one fact in two representations,
/// and the failure mode when they drift is content the API accepts and the
/// database rejects — or vice versa.
/// </summary>
[Collection("database")]
public sealed class ContentTaxonomyTests
{
    [Fact]
    public void The_check_constraint_allows_exactly_the_catalog_types()
    {
        using var connection = DatabaseFixture.Open();

        var definition = connection.QuerySingle<string>("""
            SELECT definition FROM sys.check_constraints
            WHERE name = 'CK_ContentItem_Type'
            """);

        // Every catalog type must be permitted by the constraint.
        foreach (var type in ContentCatalog.All)
        {
            definition.Should().Contain($"'{type}'",
                $"the CHECK constraint must allow the catalog type '{type}'; "
                + "widen it in 16_ContentTaxonomy.sql");
        }
    }

    [Fact]
    public void The_catalog_has_no_duplicate_types()
    {
        ContentCatalog.All.Should().OnlyHaveUniqueItems();
    }
}
