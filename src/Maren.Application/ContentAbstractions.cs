using Maren.Contracts;
using Maren.Shared;

namespace Maren.Application.Abstractions;

/// <summary>
/// A transaction that spans several repository calls.
/// </summary>
/// <remarks>
/// Needed because a bulk publish is one logical operation over many items and
/// must not half-apply. Individual writes go straight through — wrapping a
/// single stored procedure that already has its own transaction in a second
/// one buys nothing and holds a connection longer.
/// </remarks>
public interface IUnitOfWork : IAsyncDisposable
{
    Task BeginAsync(CancellationToken ct = default);
    Task CommitAsync(CancellationToken ct = default);
    Task RollbackAsync(CancellationToken ct = default);
    bool IsActive { get; }
}

public interface IContentRepository
{
    Task<ContentItemDto?> GetAsync(Guid contentItemId, CancellationToken ct);

    Task<PagedResult<ContentListItemDto>> SearchAsync(
        ContentSearchQuery query, CancellationToken ct);

    Task<Result<SaveContentResponse>> SaveAsync(
        SaveContentRequest request, Guid? actorUserId, CancellationToken ct);

    Task<Result> PublishAsync(
        Guid contentItemId, PublishContentRequest request, Guid? actorUserId,
        bool requireApproval, CancellationToken ct);

    Task<Result> UnpublishAsync(
        Guid contentItemId, Guid? actorUserId, CancellationToken ct);

    Task<Result> ApproveAsync(
        Guid contentItemId, ApproveContentRequest request, Guid? actorUserId,
        CancellationToken ct);

    Task<Result> ReviewAsync(
        Guid contentItemId, ReviewContentRequest request, Guid? actorUserId,
        CancellationToken ct);

    Task<Result> DeleteAsync(
        Guid contentItemId, Guid? actorUserId, CancellationToken ct);

    Task<Result> RestoreVersionAsync(
        Guid contentItemId, Guid contentVersionId, Guid? actorUserId,
        CancellationToken ct);

    Task<IReadOnlyList<ContentVersionDto>> GetVersionsAsync(
        Guid contentItemId, CancellationToken ct);

    Task<Result> ScheduleAsync(
        Guid contentItemId, ScheduleContentRequest request, Guid? actorUserId,
        CancellationToken ct);

    Task<int> RunDueSchedulesAsync(int batchSize, CancellationToken ct);

    Task<IReadOnlyList<ContentCategoryDto>> GetCategoriesAsync(
        CancellationToken ct);

    Task<Result> SetTagsAsync(
        Guid contentItemId, IReadOnlyList<string> tags, Guid? actorUserId,
        CancellationToken ct);

    Task<ContentAuthorDto> SaveAuthorAsync(
        SaveAuthorRequest request, Guid? actorUserId, CancellationToken ct);

    Task<MediaDto> SaveMediaAsync(
        SaveMediaRequest request, Guid? actorUserId, CancellationToken ct);

    Task<IReadOnlyList<ClientContentDto>> GetForClientAsync(
        string? contentType, string languageCode, string? countryIso,
        int? appVersionCode, byte? week, string? season,
        DateTime? modifiedSince, CancellationToken ct);

    /// <summary>
    /// The current version number, for optimistic concurrency and ETags.
    /// Null when the item does not exist.
    /// </summary>
    Task<int?> GetVersionNumberAsync(Guid contentItemId, CancellationToken ct);
}

/// <summary>Caches the mobile client's content reads.</summary>
/// <remarks>
/// Only the client read is cached, and only briefly. Admin reads must never be
/// stale — an editor who publishes and does not see the change assumes the
/// publish failed and does it again. The client read is served to every
/// launching device and changes at editorial pace, so it is the one place a
/// short cache is both safe and worth having.
/// </remarks>
public interface IContentCache
{
    Task<IReadOnlyList<ClientContentDto>?> TryGetAsync(string key);
    Task SetAsync(string key, IReadOnlyList<ClientContentDto> value, TimeSpan ttl);

    /// <summary>Drops everything. Called on any content mutation.</summary>
    void InvalidateAll();
}
