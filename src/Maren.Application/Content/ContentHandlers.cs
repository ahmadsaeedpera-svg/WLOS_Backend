using FluentValidation;
using Maren.Application.Abstractions;
using Maren.Application.Behaviors;
using Maren.Contracts;
using Maren.Shared;
using MediatR;

namespace Maren.Application.Content;

/// <summary>Permission codes. Never string literals at a call site.</summary>
public static class ContentPermissions
{
    public const string Read = "content.read";
    public const string Write = "content.write";
    public const string Publish = "content.publish";
    public const string Review = "content.review";
    public const string Delete = "content.delete";
    public const string Restore = "content.restore";
    public const string MediaManage = "media.manage";
    public const string CategoryManage = "category.manage";
    public const string AuditRead = "audit.read";
    public const string SettingsManage = "settings.manage";
}

/// <summary>Feature flag keys gating CMS capabilities.</summary>
public static class ContentFeatures
{
    public const string Scheduling = "cms_scheduling";
    public const string Localization = "cms_localization";
    public const string Media = "cms_media";
    public const string VersionCompare = "cms_version_compare";
    public const string ApprovalWorkflow = "cms_approval_workflow";
    public const string BulkPublish = "cms_bulk_publish";
    public const string Preview = "cms_preview";
    public const string Search = "cms_search";
    public const string ExperimentalEditor = "cms_experimental_editor";
}

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

public sealed record GetContentQuery(Guid ContentItemId)
    : IRequest<Result<ContentItemDto>>, IRequirePermission
{
    public string Permission => ContentPermissions.Read;
}

public sealed class GetContentHandler(IContentRepository repository)
    : IRequestHandler<GetContentQuery, Result<ContentItemDto>>
{
    public async Task<Result<ContentItemDto>> Handle(
        GetContentQuery query, CancellationToken ct)
    {
        var item = await repository.GetAsync(query.ContentItemId, ct);
        return item is null
            ? Result<ContentItemDto>.Failure(FailureCodes.NotFound,
                "No content item with that identifier.")
            : Result<ContentItemDto>.Success(item);
    }
}

public sealed record SearchContentQuery(ContentSearchQuery Criteria)
    : IRequest<Result<PagedResult<ContentListItemDto>>>,
      IRequirePermission, IRequireFeature
{
    public string Permission => ContentPermissions.Read;
    public string FeatureKey => ContentFeatures.Search;
}

public sealed class SearchContentValidator : AbstractValidator<SearchContentQuery>
{
    /// <summary>Sort keys the procedure understands.</summary>
    /// <remarks>
    /// Whitelisted rather than passed through. The procedure selects its sort
    /// column with a CASE so an unknown value cannot inject, but rejecting it
    /// here gives the caller a clear error instead of silently sorting by
    /// something they did not ask for.
    /// </remarks>
    private static readonly string[] SortKeys = ["modified", "created", "title"];

    public SearchContentValidator()
    {
        RuleFor(x => x.Criteria.Page).GreaterThan(0);
        RuleFor(x => x.Criteria.PageSize).InclusiveBetween(1, 200);

        RuleFor(x => x.Criteria.SortBy)
            .Must(s => SortKeys.Contains(s))
            .WithMessage($"Sort by one of: {string.Join(", ", SortKeys)}.");

        RuleFor(x => x.Criteria.Query)
            .MaximumLength(300)
            .When(x => x.Criteria.Query is not null);

        RuleFor(x => x.Criteria.LanguageCode)
            .Length(5)
            .When(x => !string.IsNullOrEmpty(x.Criteria.LanguageCode));
    }
}

public sealed class SearchContentHandler(IContentRepository repository)
    : IRequestHandler<SearchContentQuery, Result<PagedResult<ContentListItemDto>>>
{
    public async Task<Result<PagedResult<ContentListItemDto>>> Handle(
        SearchContentQuery query, CancellationToken ct) =>
        Result<PagedResult<ContentListItemDto>>.Success(
            await repository.SearchAsync(query.Criteria, ct));
}

public sealed record GetVersionsQuery(Guid ContentItemId)
    : IRequest<Result<IReadOnlyList<ContentVersionDto>>>,
      IRequirePermission, IRequireFeature
{
    public string Permission => ContentPermissions.Read;
    public string FeatureKey => ContentFeatures.VersionCompare;
}

public sealed class GetVersionsHandler(IContentRepository repository)
    : IRequestHandler<GetVersionsQuery, Result<IReadOnlyList<ContentVersionDto>>>
{
    public async Task<Result<IReadOnlyList<ContentVersionDto>>> Handle(
        GetVersionsQuery query, CancellationToken ct) =>
        Result<IReadOnlyList<ContentVersionDto>>.Success(
            await repository.GetVersionsAsync(query.ContentItemId, ct));
}

public sealed record GetCategoriesQuery
    : IRequest<Result<IReadOnlyList<ContentCategoryDto>>>, IRequirePermission,
      ICacheableQuery
{
    public string Permission => ContentPermissions.Read;
    public string CacheKey => "content:categories";

    // Short. Categories change rarely but an editor who adds one and does not
    // see it assumes the save failed.
    public TimeSpan CacheDuration => TimeSpan.FromSeconds(30);
}

public sealed class GetCategoriesHandler(IContentRepository repository)
    : IRequestHandler<GetCategoriesQuery, Result<IReadOnlyList<ContentCategoryDto>>>
{
    public async Task<Result<IReadOnlyList<ContentCategoryDto>>> Handle(
        GetCategoriesQuery query, CancellationToken ct) =>
        Result<IReadOnlyList<ContentCategoryDto>>.Success(
            await repository.GetCategoriesAsync(ct));
}

/// <summary>The mobile client read. Anonymous and cached.</summary>
public sealed record GetClientContentQuery(
    string? ContentType, string LanguageCode, string? CountryIso,
    int? AppVersionCode, byte? Week, string? Season, DateTime? ModifiedSince)
    : IRequest<Result<IReadOnlyList<ClientContentDto>>>, ICacheableQuery
{
    public string CacheKey =>
        $"content:client:{ContentType}:{LanguageCode}:{CountryIso}:" +
        $"{AppVersionCode}:{Week}:{Season}:{ModifiedSince:O}";

    public TimeSpan CacheDuration => TimeSpan.FromMinutes(5);
}

public sealed class GetClientContentHandler(IContentRepository repository)
    : IRequestHandler<GetClientContentQuery, Result<IReadOnlyList<ClientContentDto>>>
{
    public async Task<Result<IReadOnlyList<ClientContentDto>>> Handle(
        GetClientContentQuery query, CancellationToken ct) =>
        Result<IReadOnlyList<ClientContentDto>>.Success(
            await repository.GetForClientAsync(
                query.ContentType, query.LanguageCode, query.CountryIso,
                query.AppVersionCode, query.Week, query.Season,
                query.ModifiedSince, ct));
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

public sealed record SaveContentCommand(SaveContentRequest Request)
    : IRequest<Result<SaveContentResponse>>, IRequirePermission, ITransactional
{
    public string Permission => ContentPermissions.Write;
}

public sealed class SaveContentValidator : AbstractValidator<SaveContentCommand>
{
    private static readonly string[] ContentTypes =
    [
        "article", "wellnessSnippet", "greeting", "seasonalNote", "challenge",
        "encouragement", "notificationCopy", "onboardingPage", "insightTopic",
        "hospitalBagTemplate", "birthPreferenceOption"
    ];

    public SaveContentValidator()
    {
        RuleFor(x => x.Request.ContentType)
            .NotEmpty()
            .Must(t => ContentTypes.Contains(t))
            .WithMessage($"Content type must be one of: {string.Join(", ", ContentTypes)}.");

        RuleFor(x => x.Request.Key)
            .MaximumLength(150)
            .Matches("^[a-zA-Z0-9._-]+$")
            .When(x => !string.IsNullOrWhiteSpace(x.Request.Key))
            .WithMessage("Keys may contain letters, digits, dots, dashes and underscores.");

        RuleFor(x => x.Request.Weight).InclusiveBetween(0, 10_000);

        RuleFor(x => x.Request.Localizations)
            .NotEmpty()
            .WithMessage("At least one localisation is required.");

        RuleForEach(x => x.Request.Localizations).ChildRules(l =>
        {
            l.RuleFor(x => x.LanguageCode)
                .NotEmpty().Length(5)
                .WithMessage("Language codes look like en-GB.");

            // A localisation with neither a title nor a body renders as an
            // empty card in the app, which is worse than the item not
            // existing at all.
            l.RuleFor(x => x)
                .Must(x => !string.IsNullOrWhiteSpace(x.Title) ||
                           !string.IsNullOrWhiteSpace(x.Body))
                .WithMessage("Give a localisation at least a title or a body.");

            l.RuleFor(x => x.Title).MaximumLength(300);
            l.RuleFor(x => x.Summary).MaximumLength(1000);
        });

        RuleFor(x => x.Request.Localizations)
            .Must(l => l.Select(x => x.LanguageCode)
                        .Distinct(StringComparer.OrdinalIgnoreCase)
                        .Count() == l.Count)
            .WithMessage("Each language may appear only once.");

        RuleFor(x => x.Request.CountryFilter)
            .Must(BeAJsonArray)
            .When(x => !string.IsNullOrWhiteSpace(x.Request.CountryFilter))
            .WithMessage("Country filter must be a JSON array, e.g. [\"GB\",\"IE\"].");

        RuleFor(x => x.Request.MinAppVersion)
            .Matches(@"^\d+\.\d+(\.\d+)?$")
            .When(x => !string.IsNullOrWhiteSpace(x.Request.MinAppVersion));

        RuleFor(x => x.Request)
            .Must(r => r.FromWeek is null || r.ToWeek is null || r.FromWeek <= r.ToWeek)
            .WithMessage("The starting week must not be after the ending week.");
    }

    private static bool BeAJsonArray(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return true;
        try
        {
            using var document = System.Text.Json.JsonDocument.Parse(value);
            return document.RootElement.ValueKind ==
                   System.Text.Json.JsonValueKind.Array;
        }
        catch (System.Text.Json.JsonException)
        {
            return false;
        }
    }
}

public sealed class SaveContentHandler(
    IContentRepository repository, ICurrentUser currentUser, IQueryCache cache)
    : IRequestHandler<SaveContentCommand, Result<SaveContentResponse>>
{
    public async Task<Result<SaveContentResponse>> Handle(
        SaveContentCommand command, CancellationToken ct)
    {
        var saved = await repository.SaveAsync(
            command.Request, currentUser.UserId, ct);

        // Invalidated on every write, including a draft save. A draft does not
        // change what the client sees, but reasoning about which writes do is
        // how a stale cache ships; the read is cheap enough that always
        // clearing is the safer default.
        if (saved.Succeeded) cache.RemoveByPrefix("content:");

        return saved;
    }
}

public sealed record PublishContentCommand(
    Guid ContentItemId, PublishContentRequest Request)
    : IRequest<Result>, IRequirePermission, ITransactional
{
    public string Permission => ContentPermissions.Publish;
}

public sealed class PublishContentValidator
    : AbstractValidator<PublishContentCommand>
{
    public PublishContentValidator()
    {
        RuleFor(x => x.ContentItemId).NotEmpty();

        RuleFor(x => x.Request)
            .Must(r => r.PublishUntilUtc is null || r.PublishFromUtc is null ||
                       r.PublishUntilUtc > r.PublishFromUtc)
            .WithMessage("The publish window must end after it starts.");
    }
}

public sealed class PublishContentHandler(
    IContentRepository repository, ICurrentUser currentUser,
    IQueryCache cache, IFeatureFlagEvaluator features)
    : IRequestHandler<PublishContentCommand, Result>
{
    public async Task<Result> Handle(
        PublishContentCommand command, CancellationToken ct)
    {
        // When the approval workflow is switched off the publish gate relaxes
        // with it. Leaving the gate on while the UI for approving is hidden
        // would make publishing impossible with no visible cause.
        var requireApproval = await features.IsEnabledAsync(
            ContentFeatures.ApprovalWorkflow, currentUser.UserId, ct);

        var result = await repository.PublishAsync(
            command.ContentItemId, command.Request, currentUser.UserId,
            requireApproval, ct);

        if (result.Succeeded) cache.RemoveByPrefix("content:");
        return result;
    }
}

public sealed record UnpublishContentCommand(Guid ContentItemId)
    : IRequest<Result>, IRequirePermission, ITransactional
{
    public string Permission => ContentPermissions.Publish;
}

public sealed class UnpublishContentHandler(
    IContentRepository repository, ICurrentUser currentUser, IQueryCache cache)
    : IRequestHandler<UnpublishContentCommand, Result>
{
    public async Task<Result> Handle(
        UnpublishContentCommand command, CancellationToken ct)
    {
        var result = await repository.UnpublishAsync(
            command.ContentItemId, currentUser.UserId, ct);
        if (result.Succeeded) cache.RemoveByPrefix("content:");
        return result;
    }
}

public sealed record ApproveContentCommand(
    Guid ContentItemId, ApproveContentRequest Request)
    : IRequest<Result>, IRequirePermission, IRequireFeature, ITransactional
{
    public string Permission => ContentPermissions.Review;
    public string FeatureKey => ContentFeatures.ApprovalWorkflow;
}

public sealed class ApproveContentValidator
    : AbstractValidator<ApproveContentCommand>
{
    public ApproveContentValidator()
    {
        RuleFor(x => x.ContentItemId).NotEmpty();

        // A rejection without a reason leaves the author with nothing to act
        // on, and the reason is what the audit trail records.
        RuleFor(x => x.Request.Reason)
            .NotEmpty()
            .When(x => !x.Request.IsApproved)
            .WithMessage("Say why it was rejected.");

        RuleFor(x => x.Request.Reason).MaximumLength(4000);
    }
}

public sealed class ApproveContentHandler(
    IContentRepository repository, ICurrentUser currentUser)
    : IRequestHandler<ApproveContentCommand, Result>
{
    public Task<Result> Handle(ApproveContentCommand command, CancellationToken ct) =>
        repository.ApproveAsync(
            command.ContentItemId, command.Request, currentUser.UserId, ct);
}

public sealed record ReviewContentCommand(
    Guid ContentItemId, ReviewContentRequest Request)
    : IRequest<Result>, IRequirePermission, IRequireFeature
{
    public string Permission => ContentPermissions.Review;
    public string FeatureKey => ContentFeatures.ApprovalWorkflow;
}

public sealed class ReviewContentValidator : AbstractValidator<ReviewContentCommand>
{
    private static readonly string[] Kinds =
        ["editorial", "clinical", "legal", "translation"];
    private static readonly string[] Outcomes =
        ["pending", "approved", "rejected", "changesRequested"];

    public ReviewContentValidator()
    {
        RuleFor(x => x.Request.ReviewKind).Must(k => Kinds.Contains(k))
            .WithMessage($"Review kind must be one of: {string.Join(", ", Kinds)}.");
        RuleFor(x => x.Request.Outcome).Must(o => Outcomes.Contains(o))
            .WithMessage($"Outcome must be one of: {string.Join(", ", Outcomes)}.");
        RuleFor(x => x.Request.Comments).MaximumLength(4000);
    }
}

public sealed class ReviewContentHandler(
    IContentRepository repository, ICurrentUser currentUser)
    : IRequestHandler<ReviewContentCommand, Result>
{
    public Task<Result> Handle(ReviewContentCommand command, CancellationToken ct) =>
        repository.ReviewAsync(
            command.ContentItemId, command.Request, currentUser.UserId, ct);
}

public sealed record DeleteContentCommand(Guid ContentItemId)
    : IRequest<Result>, IRequirePermission, ITransactional
{
    public string Permission => ContentPermissions.Delete;
}

public sealed class DeleteContentHandler(
    IContentRepository repository, ICurrentUser currentUser, IQueryCache cache)
    : IRequestHandler<DeleteContentCommand, Result>
{
    public async Task<Result> Handle(
        DeleteContentCommand command, CancellationToken ct)
    {
        var result = await repository.DeleteAsync(
            command.ContentItemId, currentUser.UserId, ct);
        if (result.Succeeded) cache.RemoveByPrefix("content:");
        return result;
    }
}

public sealed record RestoreVersionCommand(
    Guid ContentItemId, Guid ContentVersionId)
    : IRequest<Result>, IRequirePermission, ITransactional
{
    public string Permission => ContentPermissions.Restore;
}

public sealed class RestoreVersionHandler(
    IContentRepository repository, ICurrentUser currentUser, IQueryCache cache)
    : IRequestHandler<RestoreVersionCommand, Result>
{
    public async Task<Result> Handle(
        RestoreVersionCommand command, CancellationToken ct)
    {
        var result = await repository.RestoreVersionAsync(
            command.ContentItemId, command.ContentVersionId,
            currentUser.UserId, ct);
        if (result.Succeeded) cache.RemoveByPrefix("content:");
        return result;
    }
}

public sealed record ScheduleContentCommand(
    Guid ContentItemId, ScheduleContentRequest Request)
    : IRequest<Result>, IRequirePermission, IRequireFeature
{
    public string Permission => ContentPermissions.Publish;
    public string FeatureKey => ContentFeatures.Scheduling;
}

public sealed class ScheduleContentValidator
    : AbstractValidator<ScheduleContentCommand>
{
    private static readonly string[] Actions = ["publish", "unpublish", "retire"];

    public ScheduleContentValidator()
    {
        RuleFor(x => x.Request.Action).Must(a => Actions.Contains(a))
            .WithMessage($"Action must be one of: {string.Join(", ", Actions)}.");

        // A schedule in the past fires on the next sweep, which looks like the
        // scheduler ignoring the date. Rejecting it makes the mistake visible
        // at the point it is made.
        RuleFor(x => x.Request.ScheduledUtc)
            .GreaterThan(_ => DateTime.UtcNow)
            .WithMessage("Schedule a time in the future.");
    }
}

public sealed class ScheduleContentHandler(
    IContentRepository repository, ICurrentUser currentUser)
    : IRequestHandler<ScheduleContentCommand, Result>
{
    public Task<Result> Handle(ScheduleContentCommand command, CancellationToken ct) =>
        repository.ScheduleAsync(
            command.ContentItemId, command.Request, currentUser.UserId, ct);
}

// ---------------------------------------------------------------------------
// Bulk
// ---------------------------------------------------------------------------

public sealed record BulkContentCommand(BulkContentRequest Request)
    : IRequest<Result<BulkContentResponse>>, IRequirePermission,
      IRequireFeature, ITransactional
{
    public string Permission => ContentPermissions.Publish;
    public string FeatureKey => ContentFeatures.BulkPublish;
}

public sealed class BulkContentValidator : AbstractValidator<BulkContentCommand>
{
    private static readonly string[] Operations =
        ["publish", "unpublish", "delete"];

    public BulkContentValidator()
    {
        RuleFor(x => x.Request.ContentItemIds)
            .NotEmpty()
            // Capped because the whole batch runs in one transaction, and a
            // transaction holding thousands of rows blocks editors working on
            // anything else in the table.
            .Must(ids => ids.Count <= 200)
            .WithMessage("Apply a bulk operation to at most 200 items at once.");

        RuleFor(x => x.Request.Operation).Must(o => Operations.Contains(o))
            .WithMessage($"Operation must be one of: {string.Join(", ", Operations)}.");
    }
}

public sealed class BulkContentHandler(
    IContentRepository repository, ICurrentUser currentUser,
    IQueryCache cache, IFeatureFlagEvaluator features)
    : IRequestHandler<BulkContentCommand, Result<BulkContentResponse>>
{
    public async Task<Result<BulkContentResponse>> Handle(
        BulkContentCommand command, CancellationToken ct)
    {
        var requireApproval = await features.IsEnabledAsync(
            ContentFeatures.ApprovalWorkflow, currentUser.UserId, ct);

        var failures = new Dictionary<string, string>();
        var succeeded = 0;

        foreach (var id in command.Request.ContentItemIds)
        {
            var result = command.Request.Operation switch
            {
                "publish" => await repository.PublishAsync(
                    id, new PublishContentRequest(null, null, null),
                    currentUser.UserId, requireApproval, ct),
                "unpublish" => await repository.UnpublishAsync(
                    id, currentUser.UserId, ct),
                "delete" => await repository.DeleteAsync(id, currentUser.UserId, ct),
                _ => Result.Failure(FailureCodes.ValidationFailed)
            };

            if (result.Succeeded) succeeded++;
            else failures[id.ToString()] = result.FailureCode!;
        }

        // Any failure fails the whole batch, and ITransactional rolls it back.
        // A partially applied bulk publish leaves an editor unable to tell
        // which items went live without checking each one by hand.
        if (failures.Count > 0)
        {
            return Result<BulkContentResponse>.Failure(
                "BULK_PARTIAL_FAILURE",
                $"{failures.Count} of {command.Request.ContentItemIds.Count} " +
                "items could not be processed, so none were changed.");
        }

        cache.RemoveByPrefix("content:");
        return Result<BulkContentResponse>.Success(
            new BulkContentResponse(succeeded, 0, failures));
    }
}

// ---------------------------------------------------------------------------
// Authors and media
// ---------------------------------------------------------------------------

public sealed record SaveAuthorCommand(SaveAuthorRequest Request)
    : IRequest<Result<ContentAuthorDto>>, IRequirePermission
{
    public string Permission => ContentPermissions.Write;
}

public sealed class SaveAuthorValidator : AbstractValidator<SaveAuthorCommand>
{
    public SaveAuthorValidator()
    {
        RuleFor(x => x.Request.DisplayName).NotEmpty().MaximumLength(200);
        RuleFor(x => x.Request.Credentials).MaximumLength(200);
    }
}

public sealed class SaveAuthorHandler(
    IContentRepository repository, ICurrentUser currentUser)
    : IRequestHandler<SaveAuthorCommand, Result<ContentAuthorDto>>
{
    public async Task<Result<ContentAuthorDto>> Handle(
        SaveAuthorCommand command, CancellationToken ct) =>
        Result<ContentAuthorDto>.Success(
            await repository.SaveAuthorAsync(
                command.Request, currentUser.UserId, ct));
}

public sealed record SaveMediaCommand(SaveMediaRequest Request)
    : IRequest<Result<MediaDto>>, IRequirePermission, IRequireFeature
{
    public string Permission => ContentPermissions.MediaManage;
    public string FeatureKey => ContentFeatures.Media;
}

public sealed class SaveMediaValidator : AbstractValidator<SaveMediaCommand>
{
    private static readonly string[] AllowedTypes =
    [
        "image/png", "image/jpeg", "image/webp", "image/svg+xml",
        "video/mp4", "application/pdf"
    ];

    public SaveMediaValidator()
    {
        RuleFor(x => x.Request.FileName).NotEmpty().MaximumLength(300);

        RuleFor(x => x.Request.ContentType)
            .Must(t => AllowedTypes.Contains(t))
            .WithMessage($"Allowed types: {string.Join(", ", AllowedTypes)}.");

        RuleFor(x => x.Request.SizeBytes)
            .GreaterThan(0)
            .LessThanOrEqualTo(50L * 1024 * 1024)
            .WithMessage("Files must be 50 MB or smaller.");

        RuleFor(x => x.Request.StorageKey).NotEmpty().MaximumLength(500);

        // Alt text is required for images. A CMS that lets an editor skip it
        // produces an app that fails accessibility review later, when fixing
        // it means revisiting every article.
        RuleFor(x => x.Request.AltText)
            .NotEmpty()
            .When(x => x.Request.ContentType.StartsWith(
                "image/", StringComparison.OrdinalIgnoreCase))
            .WithMessage("Images need alt text.");
    }
}

public sealed class SaveMediaHandler(
    IContentRepository repository, ICurrentUser currentUser)
    : IRequestHandler<SaveMediaCommand, Result<MediaDto>>
{
    public async Task<Result<MediaDto>> Handle(
        SaveMediaCommand command, CancellationToken ct) =>
        Result<MediaDto>.Success(
            await repository.SaveMediaAsync(
                command.Request, currentUser.UserId, ct));
}
