using FluentValidation.TestHelper;
using Maren.Application.Content;
using Maren.Contracts;
using Xunit;

namespace Maren.Tests;

/// <summary>
/// Validators are the first gate on anything an editor types, and the last
/// place a bad payload can be stopped before it reaches SQL. These pin the
/// rules that exist for a reason rather than every rule mechanically.
/// </summary>
public sealed class SaveContentValidatorTests
{
    private readonly SaveContentValidator _validator = new();

    private static SaveContentRequest Valid(
        IReadOnlyList<SaveLocalizationRequest>? localizations = null,
        string contentType = "article",
        string? key = "valid-key",
        int weight = 100,
        byte? fromWeek = null,
        byte? toWeek = null,
        string? countryFilter = null,
        string? minAppVersion = null) =>
        new(null, contentType, key, "nutrition", null, countryFilter,
            minAppVersion, fromWeek, toWeek, null, weight, null,
            localizations ?? [new SaveLocalizationRequest(
                "en-GB", "Title", "Body", null, null)],
            null, null, null);

    [Fact]
    public void Accepts_a_well_formed_request()
    {
        _validator.TestValidate(new SaveContentCommand(Valid()))
            .ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void Rejects_an_unknown_content_type()
    {
        _validator.TestValidate(new SaveContentCommand(
                Valid(contentType: "blogPost")))
            .ShouldHaveValidationErrorFor(x => x.Request.ContentType);
    }

    [Fact]
    public void Rejects_a_localisation_with_neither_title_nor_body()
    {
        // Renders as an empty card in the app, which is worse than the item
        // not existing.
        var request = Valid([
            new SaveLocalizationRequest("en-GB", null, null, "Summary only", null)
        ]);

        _validator.TestValidate(new SaveContentCommand(request))
            .ShouldHaveValidationErrorFor("Request.Localizations[0]");
    }

    [Fact]
    public void Accepts_a_localisation_with_only_a_title()
    {
        var request = Valid([
            new SaveLocalizationRequest("en-GB", "Just a title", null, null, null)
        ]);

        _validator.TestValidate(new SaveContentCommand(request))
            .ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void Rejects_a_duplicated_language()
    {
        // Two rows for one language would violate the unique constraint in
        // SQL; catching it here gives a field-level message instead of a 500.
        var request = Valid([
            new SaveLocalizationRequest("en-GB", "One", "Body", null, null),
            new SaveLocalizationRequest("en-GB", "Two", "Body", null, null)
        ]);

        _validator.TestValidate(new SaveContentCommand(request))
            .ShouldHaveValidationErrorFor(x => x.Request.Localizations);
    }

    [Fact]
    public void Rejects_no_localisations_at_all()
    {
        _validator.TestValidate(new SaveContentCommand(Valid([])))
            .ShouldHaveValidationErrorFor(x => x.Request.Localizations);
    }

    [Theory]
    [InlineData("has spaces")]
    [InlineData("has/slash")]
    [InlineData("has;semicolon")]
    [InlineData("'; DROP TABLE Content.ContentItem--")]
    public void Rejects_keys_outside_the_safe_character_set(string key)
    {
        _validator.TestValidate(new SaveContentCommand(Valid(key: key)))
            .ShouldHaveValidationErrorFor(x => x.Request.Key);
    }

    [Theory]
    [InlineData("valid-key")]
    [InlineData("valid.key")]
    [InlineData("valid_key")]
    [InlineData("ValidKey123")]
    public void Accepts_conventional_keys(string key)
    {
        _validator.TestValidate(new SaveContentCommand(Valid(key: key)))
            .ShouldNotHaveValidationErrorFor(x => x.Request.Key);
    }

    [Fact]
    public void Rejects_a_week_range_that_runs_backwards()
    {
        _validator.TestValidate(new SaveContentCommand(
                Valid(fromWeek: 30, toWeek: 10)))
            .ShouldHaveValidationErrorFor(x => x.Request);
    }

    [Fact]
    public void Accepts_an_open_ended_week_range()
    {
        _validator.TestValidate(new SaveContentCommand(
                Valid(fromWeek: 30, toWeek: null)))
            .ShouldNotHaveValidationErrorFor(x => x.Request);
    }

    [Theory]
    [InlineData("not json")]
    [InlineData("{\"not\":\"an array\"}")]
    [InlineData("[unclosed")]
    public void Rejects_a_country_filter_that_is_not_a_json_array(string filter)
    {
        // A malformed filter makes OPENJSON throw inside the client read,
        // which is on the launch path for every device.
        _validator.TestValidate(new SaveContentCommand(
                Valid(countryFilter: filter)))
            .ShouldHaveValidationErrorFor(x => x.Request.CountryFilter);
    }

    [Fact]
    public void Accepts_a_valid_country_filter()
    {
        _validator.TestValidate(new SaveContentCommand(
                Valid(countryFilter: "[\"GB\",\"IE\"]")))
            .ShouldNotHaveValidationErrorFor(x => x.Request.CountryFilter);
    }

    [Theory]
    [InlineData("2.1")]
    [InlineData("2.1.0")]
    [InlineData("10.20.30")]
    public void Accepts_semantic_versions(string version)
    {
        _validator.TestValidate(new SaveContentCommand(
                Valid(minAppVersion: version)))
            .ShouldNotHaveValidationErrorFor(x => x.Request.MinAppVersion);
    }

    [Theory]
    [InlineData("v2.1")]
    [InlineData("2")]
    [InlineData("latest")]
    public void Rejects_malformed_versions(string version)
    {
        _validator.TestValidate(new SaveContentCommand(
                Valid(minAppVersion: version)))
            .ShouldHaveValidationErrorFor(x => x.Request.MinAppVersion);
    }
}

public sealed class SearchContentValidatorTests
{
    private readonly SearchContentValidator _validator = new();

    [Theory]
    [InlineData("modified")]
    [InlineData("created")]
    [InlineData("title")]
    public void Accepts_known_sort_keys(string sortBy)
    {
        _validator.TestValidate(new SearchContentQuery(
                new ContentSearchQuery(SortBy: sortBy)))
            .ShouldNotHaveValidationErrorFor(x => x.Criteria.SortBy);
    }

    [Theory]
    [InlineData("Title; DROP TABLE Content.ContentItem--")]
    [InlineData("1; WAITFOR DELAY '00:00:05'")]
    [InlineData("unknown")]
    public void Rejects_sort_keys_outside_the_whitelist(string sortBy)
    {
        // The procedure picks its sort column with a CASE so injection is not
        // possible even if this passed, but a caller deserves an error rather
        // than a silent fallback to a different ordering.
        _validator.TestValidate(new SearchContentQuery(
                new ContentSearchQuery(SortBy: sortBy)))
            .ShouldHaveValidationErrorFor(x => x.Criteria.SortBy);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    public void Rejects_a_non_positive_page(int page)
    {
        _validator.TestValidate(new SearchContentQuery(
                new ContentSearchQuery(Page: page)))
            .ShouldHaveValidationErrorFor(x => x.Criteria.Page);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(201)]
    [InlineData(10_000)]
    public void Rejects_page_sizes_outside_the_allowed_band(int pageSize)
    {
        // An unbounded page size is a denial-of-service vector: one request
        // asking for a million rows holds a connection and a lot of memory.
        _validator.TestValidate(new SearchContentQuery(
                new ContentSearchQuery(PageSize: pageSize)))
            .ShouldHaveValidationErrorFor(x => x.Criteria.PageSize);
    }
}

public sealed class WorkflowValidatorTests
{
    [Fact]
    public void Rejection_must_carry_a_reason()
    {
        // A rejection without a reason leaves the author nothing to act on,
        // and the reason is what the audit trail records.
        new ApproveContentValidator()
            .TestValidate(new ApproveContentCommand(
                Guid.NewGuid(), new ApproveContentRequest(null, false, null)))
            .ShouldHaveValidationErrorFor(x => x.Request.Reason);
    }

    [Fact]
    public void Approval_does_not_require_a_reason()
    {
        new ApproveContentValidator()
            .TestValidate(new ApproveContentCommand(
                Guid.NewGuid(), new ApproveContentRequest(null, true, null)))
            .ShouldNotHaveValidationErrorFor(x => x.Request.Reason);
    }

    [Fact]
    public void Scheduling_in_the_past_is_rejected()
    {
        // A past schedule fires on the next sweep, which looks like the
        // scheduler ignoring the date entirely.
        new ScheduleContentValidator()
            .TestValidate(new ScheduleContentCommand(
                Guid.NewGuid(),
                new ScheduleContentRequest("publish", DateTime.UtcNow.AddDays(-1))))
            .ShouldHaveValidationErrorFor(x => x.Request.ScheduledUtc);
    }

    [Fact]
    public void Scheduling_in_the_future_is_accepted()
    {
        new ScheduleContentValidator()
            .TestValidate(new ScheduleContentCommand(
                Guid.NewGuid(),
                new ScheduleContentRequest("publish", DateTime.UtcNow.AddHours(1))))
            .ShouldNotHaveAnyValidationErrors();
    }

    [Fact]
    public void A_publish_window_must_end_after_it_starts()
    {
        var now = DateTime.UtcNow;
        new PublishContentValidator()
            .TestValidate(new PublishContentCommand(
                Guid.NewGuid(),
                new PublishContentRequest(null, now.AddDays(5), now.AddDays(1))))
            .ShouldHaveValidationErrorFor(x => x.Request);
    }

    [Fact]
    public void Bulk_operations_are_capped()
    {
        // The whole batch runs in one transaction; thousands of rows would
        // block every other editor working in the same table.
        var ids = Enumerable.Range(0, 201).Select(_ => Guid.NewGuid()).ToList();

        new BulkContentValidator()
            .TestValidate(new BulkContentCommand(
                new BulkContentRequest(ids, "publish")))
            .ShouldHaveValidationErrorFor(x => x.Request.ContentItemIds);
    }

    [Fact]
    public void Bulk_operations_reject_an_empty_selection()
    {
        new BulkContentValidator()
            .TestValidate(new BulkContentCommand(
                new BulkContentRequest([], "publish")))
            .ShouldHaveValidationErrorFor(x => x.Request.ContentItemIds);
    }
}

public sealed class MediaValidatorTests
{
    private readonly SaveMediaValidator _validator = new();

    private static SaveMediaRequest Media(
        string contentType = "image/png",
        long size = 1024,
        string? altText = "A description") =>
        new(null, "photo.png", contentType, size, "media/photo.png",
            800, 600, altText);

    [Fact]
    public void Images_require_alt_text()
    {
        // A CMS that lets an editor skip alt text produces an app that fails
        // accessibility review later, when fixing it means revisiting every
        // article.
        _validator.TestValidate(new SaveMediaCommand(Media(altText: null)))
            .ShouldHaveValidationErrorFor(x => x.Request.AltText);
    }

    [Fact]
    public void Non_images_do_not_require_alt_text()
    {
        _validator.TestValidate(new SaveMediaCommand(
                Media(contentType: "application/pdf", altText: null)))
            .ShouldNotHaveValidationErrorFor(x => x.Request.AltText);
    }

    [Theory]
    [InlineData("application/x-msdownload")]
    [InlineData("text/html")]
    [InlineData("application/javascript")]
    public void Rejects_executable_and_scriptable_types(string contentType)
    {
        // An uploaded HTML or JS file served from the media host is stored XSS
        // against anyone who opens it.
        _validator.TestValidate(new SaveMediaCommand(Media(contentType)))
            .ShouldHaveValidationErrorFor(x => x.Request.ContentType);
    }

    [Fact]
    public void Rejects_oversized_files()
    {
        _validator.TestValidate(new SaveMediaCommand(
                Media(size: 51L * 1024 * 1024)))
            .ShouldHaveValidationErrorFor(x => x.Request.SizeBytes);
    }
}
