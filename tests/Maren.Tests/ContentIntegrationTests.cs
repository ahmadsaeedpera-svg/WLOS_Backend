using Dapper;
using FluentAssertions;
using Maren.Application.Behaviors;
using Maren.Application.Content;
using Maren.Contracts;
using Maren.Shared;
using MediatR;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Maren.Tests;

/// <summary>
/// The CMS exercised end to end: MediatR pipeline, handlers, repository,
/// stored procedures, real database.
/// </summary>
[Collection("database")]
public sealed class ContentWorkflowTests : IAsyncLifetime
{
    private const string Prefix = "itest-workflow-";
    private readonly DatabaseFixture _fixture;

    public ContentWorkflowTests(DatabaseFixture fixture) => _fixture = fixture;

    public Task InitializeAsync()
    {
        DatabaseFixture.CleanUp(Prefix);
        _fixture.CurrentUser.WithAllPermissions();
        return Task.CompletedTask;
    }

    public Task DisposeAsync() => Task.CompletedTask;

    private async Task<ISender> Sender()
    {
        await Task.CompletedTask;
        return _fixture.Provider.GetRequiredService<ISender>();
    }

    private static SaveContentRequest Article(
        string key,
        string title = "A title",
        string body = "A body",
        Guid? id = null,
        int? expectedVersion = null,
        string? countryFilter = null,
        IReadOnlyList<SaveLocalizationRequest>? localizations = null) =>
        new(id, "article", key, "nutrition", null, countryFilter, null,
            null, null, null, 100, null,
            localizations ?? [new SaveLocalizationRequest(
                "en-GB", title, body, null, null)],
            null, null, expectedVersion);

    // -----------------------------------------------------------------------

    [Fact]
    public async Task Saving_creates_an_item_and_its_first_version()
    {
        var sender = await Sender();

        var saved = await sender.Send(new SaveContentCommand(
            Article(Prefix + "first")));

        saved.Succeeded.Should().BeTrue(saved.Message);
        saved.Value!.VersionNumber.Should().Be(1);

        var versions = await sender.Send(
            new GetVersionsQuery(saved.Value.ContentItemId));

        versions.Value.Should().HaveCount(1);
    }

    [Fact]
    public async Task Each_save_appends_a_version_and_never_overwrites_one()
    {
        // The version history is the CMS's undo. If a save mutated the previous
        // snapshot there would be nothing to restore to.
        var sender = await Sender();
        var key = Prefix + "history";

        var first = await sender.Send(new SaveContentCommand(
            Article(key, "Draft one", "Body one")));

        var second = await sender.Send(new SaveContentCommand(
            Article(key, "Draft two", "Body two",
                id: first.Value!.ContentItemId,
                expectedVersion: first.Value.VersionNumber)));

        second.Value!.VersionNumber.Should().Be(2);

        var versions = await sender.Send(
            new GetVersionsQuery(first.Value.ContentItemId));

        versions.Value.Should().HaveCount(2);
        versions.Value!.Select(v => v.VersionNumber)
            .Should().BeEquivalentTo([2, 1], o => o.WithStrictOrdering());
    }

    [Fact]
    public async Task Publishing_is_refused_when_nothing_has_been_approved()
    {
        // The whole point of the approval step. If this passes, the workflow is
        // decoration.
        var sender = await Sender();

        var saved = await sender.Send(new SaveContentCommand(
            Article(Prefix + "unapproved")));

        var published = await sender.Send(new PublishContentCommand(
            saved.Value!.ContentItemId,
            new PublishContentRequest(null, null, null)));

        published.Succeeded.Should().BeFalse();
        published.FailureCode.Should().Be(ContentFailureCodes.NotApproved);
    }

    [Fact]
    public async Task Publishing_succeeds_once_the_version_is_approved()
    {
        var sender = await Sender();

        var saved = await sender.Send(new SaveContentCommand(
            Article(Prefix + "approved")));

        var approved = await sender.Send(new ApproveContentCommand(
            saved.Value!.ContentItemId,
            new ApproveContentRequest(saved.Value.ContentVersionId, true, null)));
        approved.Succeeded.Should().BeTrue(approved.Message);

        var published = await sender.Send(new PublishContentCommand(
            saved.Value.ContentItemId,
            new PublishContentRequest(null, null, null)));

        published.Succeeded.Should().BeTrue(published.Message);

        var item = await sender.Send(new GetContentQuery(saved.Value.ContentItemId));
        item.Value!.Status.Should().Be("published");
    }

    [Fact]
    public async Task Editing_a_published_item_does_not_change_what_readers_see()
    {
        // The published pointer names a specific version. An edit creates a new
        // draft version; until somebody publishes it, the app keeps serving the
        // approved text. This is the property that makes the CMS safe to type
        // into.
        var sender = await Sender();
        var key = Prefix + "pointer";

        var saved = await sender.Send(new SaveContentCommand(
            Article(key, "Approved title", "Approved body")));

        await sender.Send(new ApproveContentCommand(
            saved.Value!.ContentItemId,
            new ApproveContentRequest(saved.Value.ContentVersionId, true, null)));

        await sender.Send(new PublishContentCommand(
            saved.Value.ContentItemId, new PublishContentRequest(null, null, null)));

        await sender.Send(new SaveContentCommand(
            Article(key, "Unreviewed edit", "Unreviewed body",
                id: saved.Value.ContentItemId, expectedVersion: 1)));

        var client = await sender.Send(new GetClientContentQuery(
            "article", "en-GB", null, null, null, null, null));

        var served = client.Value!.SingleOrDefault(c => c.Key == key);
        served.Should().NotBeNull();
        served!.Title.Should().Be("Approved title");
    }

    [Fact]
    public async Task Restoring_a_version_writes_it_forward_rather_than_rewinding()
    {
        // Restore must not delete history. An editor who restores by mistake
        // needs to be able to restore back.
        var sender = await Sender();
        var key = Prefix + "restore";

        var v1 = await sender.Send(new SaveContentCommand(
            Article(key, "Original", "Original body")));

        await sender.Send(new SaveContentCommand(
            Article(key, "Replacement", "Replacement body",
                id: v1.Value!.ContentItemId, expectedVersion: 1)));

        var restored = await sender.Send(new RestoreVersionCommand(
            v1.Value.ContentItemId, v1.Value.ContentVersionId));

        restored.Succeeded.Should().BeTrue(restored.Message);

        var item = await sender.Send(new GetContentQuery(v1.Value.ContentItemId));
        item.Value!.VersionNumber.Should().Be(3, "restore appends, it does not rewind");
        item.Value.Localizations.Single(l => l.LanguageCode == "en-GB")
            .Title.Should().Be("Original");

        var versions = await sender.Send(new GetVersionsQuery(v1.Value.ContentItemId));
        versions.Value.Should().HaveCount(3);
    }

    [Fact]
    public async Task Restoring_brings_back_translations_that_were_removed()
    {
        // Regression. An earlier implementation delegated restore to save and
        // passed an empty localisation set, which deleted every translation it
        // was in the middle of restoring.
        var sender = await Sender();
        var key = Prefix + "restore-i18n";

        var v1 = await sender.Send(new SaveContentCommand(
            Article(key, localizations: [
                new SaveLocalizationRequest("en-GB", "English", "English body", null, null),
                new SaveLocalizationRequest("es-ES", "Español", "Cuerpo", null, null)
            ])));

        await sender.Send(new SaveContentCommand(
            Article(key, id: v1.Value!.ContentItemId, expectedVersion: 1,
                localizations: [
                    new SaveLocalizationRequest("en-GB", "English only", "Body", null, null)
                ])));

        var afterDrop = await sender.Send(new GetContentQuery(v1.Value.ContentItemId));
        afterDrop.Value!.Localizations.Should().HaveCount(1);

        await sender.Send(new RestoreVersionCommand(
            v1.Value.ContentItemId, v1.Value.ContentVersionId));

        var afterRestore = await sender.Send(new GetContentQuery(v1.Value.ContentItemId));
        afterRestore.Value!.Localizations.Should().HaveCount(2);
        afterRestore.Value.Localizations.Select(l => l.LanguageCode)
            .Should().Contain("es-ES");
    }

    [Fact]
    public async Task A_concurrent_edit_is_refused_rather_than_silently_winning()
    {
        // Two editors open the same article. Without this, the second save
        // overwrites the first and neither editor is told.
        var sender = await Sender();
        var key = Prefix + "concurrency";

        var saved = await sender.Send(new SaveContentCommand(Article(key)));

        // Both hold version 1. The first save moves it to 2.
        await sender.Send(new SaveContentCommand(
            Article(key, "Editor A", "Body A",
                id: saved.Value!.ContentItemId, expectedVersion: 1)));

        var second = await sender.Send(new SaveContentCommand(
            Article(key, "Editor B", "Body B",
                id: saved.Value.ContentItemId, expectedVersion: 1)));

        second.Succeeded.Should().BeFalse("editor B's copy is stale");
        second.FailureCode.Should().Be(ContentFailureCodes.VersionConflict);

        var item = await sender.Send(new GetContentQuery(saved.Value.ContentItemId));
        item.Value!.Localizations.Single().Title
            .Should().Be("Editor A", "the refused save must not have landed");
    }

    [Fact]
    public async Task A_rejected_version_cannot_be_published()
    {
        var sender = await Sender();

        var saved = await sender.Send(new SaveContentCommand(
            Article(Prefix + "rejected")));

        await sender.Send(new ApproveContentCommand(
            saved.Value!.ContentItemId,
            new ApproveContentRequest(saved.Value.ContentVersionId, false,
                "The dosage figure in paragraph two is unsourced.")));

        var published = await sender.Send(new PublishContentCommand(
            saved.Value.ContentItemId, new PublishContentRequest(null, null, null)));

        published.Succeeded.Should().BeFalse();
        published.FailureCode.Should().Be(ContentFailureCodes.NotApproved);
    }

    [Fact]
    public async Task Deleted_content_disappears_from_the_client_but_stays_in_the_table()
    {
        // Soft delete. A hard delete would take the audit trail and the version
        // history with it.
        var sender = await Sender();
        var key = Prefix + "deleted";

        var saved = await sender.Send(new SaveContentCommand(Article(key)));

        await sender.Send(new ApproveContentCommand(
            saved.Value!.ContentItemId,
            new ApproveContentRequest(saved.Value.ContentVersionId, true, null)));
        await sender.Send(new PublishContentCommand(
            saved.Value.ContentItemId, new PublishContentRequest(null, null, null)));

        await sender.Send(new DeleteContentCommand(saved.Value.ContentItemId));

        var client = await sender.Send(new GetClientContentQuery(
            "article", "en-GB", null, null, null, null, null));
        client.Value!.Should().NotContain(c => c.Key == key);

        using var connection = DatabaseFixture.Open();
        var row = connection.QuerySingle<int>(
            "SELECT COUNT(*) FROM [Content].[ContentItem] WHERE [Key] = @Key",
            new { Key = key });
        row.Should().Be(1, "the row is retained for audit");
    }
}

// ---------------------------------------------------------------------------

[Collection("database")]
public sealed class ClientContentTests : IAsyncLifetime
{
    private const string Prefix = "itest-client-";
    private readonly DatabaseFixture _fixture;

    public ClientContentTests(DatabaseFixture fixture) => _fixture = fixture;

    public Task InitializeAsync()
    {
        DatabaseFixture.CleanUp(Prefix);
        _fixture.CurrentUser.WithAllPermissions();
        return Task.CompletedTask;
    }

    public Task DisposeAsync() => Task.CompletedTask;

    private ISender Sender => _fixture.Provider.GetRequiredService<ISender>();

    private async Task<Guid> PublishAsync(
        string key,
        IReadOnlyList<SaveLocalizationRequest> localizations,
        string? countryFilter = null)
    {
        var saved = await Sender.Send(new SaveContentCommand(
            new SaveContentRequest(null, "article", key, "nutrition", null,
                countryFilter, null, null, null, null, 100, null,
                localizations, null, null, null)));

        await Sender.Send(new ApproveContentCommand(
            saved.Value!.ContentItemId,
            new ApproveContentRequest(saved.Value.ContentVersionId, true, null)));

        await Sender.Send(new PublishContentCommand(
            saved.Value.ContentItemId, new PublishContentRequest(null, null, null)));

        return saved.Value.ContentItemId;
    }

    [Fact]
    public async Task Falls_back_to_en_GB_when_the_requested_language_is_missing()
    {
        // A missing translation must show English, not an empty screen. A user
        // whose phone is set to French sees the app half-blank otherwise.
        await PublishAsync(Prefix + "fallback", [
            new SaveLocalizationRequest("en-GB", "English title", "English body", null, null)
        ]);

        var result = await Sender.Send(new GetClientContentQuery(
            "article", "fr-FR", null, null, null, null, null));

        var item = result.Value!.SingleOrDefault(c => c.Key == Prefix + "fallback");
        item.Should().NotBeNull();
        item!.Title.Should().Be("English title");
    }

    [Fact]
    public async Task Prefers_the_requested_language_when_it_exists()
    {
        await PublishAsync(Prefix + "translated", [
            new SaveLocalizationRequest("en-GB", "English title", "English body", null, null),
            new SaveLocalizationRequest("es-ES", "Título español", "Cuerpo", null, null)
        ]);

        var result = await Sender.Send(new GetClientContentQuery(
            "article", "es-ES", null, null, null, null, null));

        result.Value!.Single(c => c.Key == Prefix + "translated")
            .Title.Should().Be("Título español");
    }

    [Fact]
    public async Task Country_gated_content_reaches_only_the_listed_countries()
    {
        // Health content is regulated differently by market. Content written
        // for the UK appearing in the US is a compliance incident, not a bug.
        await PublishAsync(Prefix + "gb-only", [
            new SaveLocalizationRequest("en-GB", "NHS guidance", "Body", null, null)
        ], countryFilter: "[\"GB\"]");

        var inGb = await Sender.Send(new GetClientContentQuery(
            "article", "en-GB", "GB", null, null, null, null));
        inGb.Value!.Should().Contain(c => c.Key == Prefix + "gb-only");

        var inUs = await Sender.Send(new GetClientContentQuery(
            "article", "en-GB", "US", null, null, null, null));
        inUs.Value!.Should().NotContain(c => c.Key == Prefix + "gb-only");
    }

    [Fact]
    public async Task Unpublished_drafts_are_never_served_to_a_client()
    {
        var sender = Sender;

        await sender.Send(new SaveContentCommand(new SaveContentRequest(
            null, "article", Prefix + "draft", "nutrition", null, null, null,
            null, null, null, 100, null,
            [new SaveLocalizationRequest("en-GB", "Secret draft", "Body", null, null)],
            null, null, null)));

        var result = await sender.Send(new GetClientContentQuery(
            "article", "en-GB", null, null, null, null, null));

        result.Value!.Should().NotContain(c => c.Key == Prefix + "draft");
    }

    [Fact]
    public async Task Delta_sync_returns_nothing_when_the_client_is_current()
    {
        await PublishAsync(Prefix + "delta", [
            new SaveLocalizationRequest("en-GB", "Title", "Body", null, null)
        ]);

        var future = DateTime.UtcNow.AddMinutes(5);

        var result = await Sender.Send(new GetClientContentQuery(
            "article", "en-GB", null, null, null, null, future));

        result.Value!.Should().NotContain(c => c.Key == Prefix + "delta");
    }
}

// ---------------------------------------------------------------------------

[Collection("database")]
public sealed class AuthorizationPipelineTests : IAsyncLifetime
{
    private const string Prefix = "itest-authz-";
    private readonly DatabaseFixture _fixture;

    public AuthorizationPipelineTests(DatabaseFixture fixture) => _fixture = fixture;

    public Task InitializeAsync()
    {
        DatabaseFixture.CleanUp(Prefix);
        return Task.CompletedTask;
    }

    public Task DisposeAsync()
    {
        _fixture.CurrentUser.WithAllPermissions();
        return Task.CompletedTask;
    }

    private ISender Sender => _fixture.Provider.GetRequiredService<ISender>();

    [Fact]
    public async Task A_caller_without_the_permission_is_refused()
    {
        _fixture.CurrentUser.With(ContentPermissions.Read);

        var act = async () => await Sender.Send(new SaveContentCommand(
            new SaveContentRequest(null, "article", Prefix + "denied", "nutrition",
                null, null, null, null, null, null, 100, null,
                [new SaveLocalizationRequest("en-GB", "Title", "Body", null, null)],
                null, null, null)));

        (await act.Should().ThrowAsync<UnauthorizedRequestException>())
            .Which.Permission.Should().Be(ContentPermissions.Write);
    }

    [Fact]
    public async Task Read_permission_alone_does_not_grant_publish()
    {
        // Publishing is the action with external consequences. Every other
        // permission being present must not imply it.
        _fixture.CurrentUser.With(
            ContentPermissions.Read,
            ContentPermissions.Write,
            ContentPermissions.Review);

        var act = async () => await Sender.Send(new PublishContentCommand(
            Guid.NewGuid(), new PublishContentRequest(null, null, null)));

        (await act.Should().ThrowAsync<UnauthorizedRequestException>())
            .Which.Permission.Should().Be(ContentPermissions.Publish);
    }

    [Fact]
    public async Task An_anonymous_caller_is_refused_a_gated_request()
    {
        var previous = _fixture.CurrentUser.UserId;
        _fixture.CurrentUser.UserId = null;
        _fixture.CurrentUser.With(ContentPermissions.Read);

        try
        {
            var act = async () => await Sender.Send(new GetVersionsQuery(Guid.NewGuid()));
            await act.Should().ThrowAsync<UnauthorizedRequestException>();
        }
        finally
        {
            _fixture.CurrentUser.UserId = previous;
        }
    }

    [Fact]
    public async Task Client_content_needs_no_permission_at_all()
    {
        // The published library is what an unauthenticated user opens the app
        // to. Gating it would show a signed-out user an empty product.
        _fixture.CurrentUser.UserId = null;
        _fixture.CurrentUser.With();

        try
        {
            var result = await Sender.Send(new GetClientContentQuery(
                "article", "en-GB", null, null, null, null, null));

            result.Succeeded.Should().BeTrue();
        }
        finally
        {
            _fixture.CurrentUser.UserId =
                Guid.Parse("11111111-1111-1111-1111-111111111111");
        }
    }
}

// ---------------------------------------------------------------------------

/// <summary>
/// Permission codes exist in two places: the C# constants the pipeline checks,
/// and the rows the database grants. When they drift, an endpoint becomes
/// unreachable by everyone and nothing in the build says so.
/// </summary>
[Collection("database")]
public sealed class PermissionSeedTests
{
    [Fact]
    public void Every_code_the_platform_declares_exists_in_the_database()
    {
        using var connection = DatabaseFixture.Open();
        var seeded = connection.Query<string>(
            "SELECT Code FROM [Identity].[Permission]").ToHashSet();

        var missing = PlatformPermissions.All.Where(p => !seeded.Contains(p)).ToList();

        missing.Should().BeEmpty(
            "a permission no role can be granted locks the endpoint for everyone");
    }

    [Fact]
    public void Every_code_the_database_grants_is_declared_in_the_platform()
    {
        using var connection = DatabaseFixture.Open();
        var seeded = connection.Query<string>(
            "SELECT Code FROM [Identity].[Permission]").ToList();

        var undeclared = seeded.Except(PlatformPermissions.All).ToList();

        undeclared.Should().BeEmpty(
            "a granted permission nothing checks is a permission that does nothing");
    }

    [Fact]
    public void Every_content_permission_the_handlers_require_is_seeded()
    {
        using var connection = DatabaseFixture.Open();
        var seeded = connection.Query<string>(
            "SELECT Code FROM [Identity].[Permission]").ToHashSet();

        foreach (var code in new[]
        {
            ContentPermissions.Read, ContentPermissions.Write,
            ContentPermissions.Publish, ContentPermissions.Review,
            ContentPermissions.Delete, ContentPermissions.Restore,
            ContentPermissions.MediaManage, ContentPermissions.CategoryManage,
            ContentPermissions.AuditRead, ContentPermissions.SettingsManage
        })
        {
            seeded.Should().Contain(code);
        }
    }

    [Fact]
    public void Every_cms_feature_flag_is_defined()
    {
        // An undefined flag defaults to enabled, so a missing row is not an
        // outage — but it is an off-switch that does not exist, which is worse
        // during an incident because the switch appears to be there.
        using var connection = DatabaseFixture.Open();
        var defined = connection.Query<string>(
            "SELECT [Key] FROM [Administration].[FeatureFlag]").ToHashSet();

        foreach (var key in new[]
        {
            ContentFeatures.Scheduling, ContentFeatures.Localization,
            ContentFeatures.Media, ContentFeatures.VersionCompare,
            ContentFeatures.ApprovalWorkflow, ContentFeatures.BulkPublish,
            ContentFeatures.Preview, ContentFeatures.Search,
            ContentFeatures.ExperimentalEditor
        })
        {
            defined.Should().Contain(key);
        }
    }

    [Fact]
    public void The_approver_role_cannot_write_content()
    {
        // Separation of duties. If an approver can edit, they can approve their
        // own work by editing after approval.
        using var connection = DatabaseFixture.Open();
        var codes = connection.Query<string>("""
            SELECT p.Code
            FROM [Identity].[Role] r
            JOIN [Identity].[RolePermission] rp ON rp.RoleId = r.RoleId
            JOIN [Identity].[Permission] p ON p.PermissionId = rp.PermissionId
            WHERE r.Name = 'ContentApprover'
            """).ToList();

        codes.Should().Contain(ContentPermissions.Review);
        codes.Should().NotContain(ContentPermissions.Write);
    }

    [Fact]
    public void The_editor_role_cannot_approve_its_own_content()
    {
        using var connection = DatabaseFixture.Open();
        var codes = connection.Query<string>("""
            SELECT p.Code
            FROM [Identity].[Role] r
            JOIN [Identity].[RolePermission] rp ON rp.RoleId = r.RoleId
            JOIN [Identity].[Permission] p ON p.PermissionId = rp.PermissionId
            WHERE r.Name = 'ContentEditor'
            """).ToList();

        codes.Should().Contain(ContentPermissions.Write);
        codes.Should().NotContain(ContentPermissions.Review);
    }
}

// ---------------------------------------------------------------------------

[Collection("database")]
public sealed class TransactionAndSearchTests : IAsyncLifetime
{
    private const string Prefix = "itest-tx-";
    private readonly DatabaseFixture _fixture;

    public TransactionAndSearchTests(DatabaseFixture fixture) => _fixture = fixture;

    public Task InitializeAsync()
    {
        DatabaseFixture.CleanUp(Prefix);
        _fixture.CurrentUser.WithAllPermissions();
        return Task.CompletedTask;
    }

    public Task DisposeAsync() => Task.CompletedTask;

    private ISender Sender => _fixture.Provider.GetRequiredService<ISender>();

    [Fact]
    public async Task A_bulk_operation_that_fails_leaves_nothing_behind()
    {
        // All or nothing. A partially applied bulk publish is the worst
        // outcome: some items live, no error the operator can act on, and no
        // way to tell which is which without reading every row.
        var sender = Sender;

        var saved = await sender.Send(new SaveContentCommand(new SaveContentRequest(
            null, "article", Prefix + "bulk", "nutrition", null, null, null,
            null, null, null, 100, null,
            [new SaveLocalizationRequest("en-GB", "Title", "Body", null, null)],
            null, null, null)));

        // One real id and one that does not exist. The batch must fail whole.
        var result = await sender.Send(new BulkContentCommand(
            new BulkContentRequest(
                [saved.Value!.ContentItemId, Guid.NewGuid()], "publish")));

        result.Succeeded.Should().BeFalse();

        var item = await sender.Send(new GetContentQuery(saved.Value.ContentItemId));
        item.Value!.Status.Should().NotBe("published",
            "the valid item must have been rolled back with the batch");
    }

    [Fact]
    public async Task Search_pages_without_losing_or_repeating_rows()
    {
        var sender = Sender;

        for (var i = 0; i < 7; i++)
        {
            await sender.Send(new SaveContentCommand(new SaveContentRequest(
                null, "article", $"{Prefix}page-{i}", "nutrition", null, null,
                null, null, null, null, 100, null,
                [new SaveLocalizationRequest(
                    "en-GB", $"Paged item {i}", "Body", null, null)],
                null, null, null)));
        }

        var first = await sender.Send(new SearchContentQuery(
            new ContentSearchQuery(Query: "Paged item", PageSize: 3, Page: 1)));
        var second = await sender.Send(new SearchContentQuery(
            new ContentSearchQuery(Query: "Paged item", PageSize: 3, Page: 2)));

        first.Value!.TotalCount.Should().BeGreaterThanOrEqualTo(7);
        first.Value.Items.Should().HaveCount(3);

        var firstIds = first.Value.Items.Select(i => i.ContentItemId).ToList();
        var secondIds = second.Value!.Items.Select(i => i.ContentItemId).ToList();

        firstIds.Should().NotIntersectWith(secondIds,
            "a row appearing on two pages means the sort is not deterministic");
    }

    [Theory]
    [InlineData("'; DROP TABLE [Content].[ContentItem]; --")]
    [InlineData("%' OR 1=1 --")]
    [InlineData("' UNION SELECT PasswordHash FROM [Identity].[User] --")]
    public async Task Search_treats_injection_attempts_as_literal_text(string malicious)
    {
        // Everything is parameterised and the sort column is chosen by CASE,
        // so these are ordinary search strings that happen to match nothing.
        var result = await Sender.Send(new SearchContentQuery(
            new ContentSearchQuery(Query: malicious)));

        result.Succeeded.Should().BeTrue();

        using var connection = DatabaseFixture.Open();
        connection.QuerySingle<int>(
            "SELECT COUNT(*) FROM sys.tables WHERE name = 'ContentItem'")
            .Should().Be(1, "the table must still exist");
    }

    [Fact]
    public async Task A_client_read_of_the_full_library_stays_within_budget()
    {
        // The client fetches this on launch. Past roughly a second it is worth
        // knowing before a user does.
        var stopwatch = System.Diagnostics.Stopwatch.StartNew();

        var result = await Sender.Send(new GetClientContentQuery(
            null, "en-GB", "GB", null, 20, null, null));

        stopwatch.Stop();

        result.Succeeded.Should().BeTrue();
        stopwatch.ElapsedMilliseconds.Should().BeLessThan(1000);
    }
}
