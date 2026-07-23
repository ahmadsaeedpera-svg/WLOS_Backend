namespace Maren.Contracts;

// ---------------------------------------------------------------------------
// Reads
// ---------------------------------------------------------------------------

public sealed record ContentLocalizationDto(
    string LanguageCode,
    string? Title,
    string? Body,
    string? Summary,
    string? MetadataJson,
    bool IsMachineTranslated);

public sealed record ContentTagDto(string Key, string Label);

public sealed record ContentItemDto(
    Guid ContentItemId,
    string ContentType,
    string? Key,
    string Status,
    int Weight,
    string? CountryFilter,
    string? MinAppVersion,
    byte? FromWeek,
    byte? ToWeek,
    string? Season,
    string? SourceCitation,
    DateTime? ReviewedUtc,
    string? ReviewedBy,
    int VersionNumber,
    Guid? CurrentVersionId,
    Guid? PublishedVersionId,
    DateTime? PublishFromUtc,
    DateTime? PublishUntilUtc,
    bool IsDeleted,
    DateTime CreatedOn,
    DateTime ModifiedOn,
    string? CategoryKey,
    Guid? AuthorId,
    string? AuthorName,
    IReadOnlyList<ContentLocalizationDto> Localizations,
    IReadOnlyList<ContentTagDto> Tags);

/// <summary>A row in the admin list. Deliberately flatter than the full item.</summary>
/// <remarks>
/// The grid renders hundreds of rows; shipping every localisation with each
/// one would multiply the payload for data the grid never displays.
/// </remarks>
public sealed record ContentListItemDto(
    Guid ContentItemId,
    string ContentType,
    string? Key,
    string Status,
    int Weight,
    byte? FromWeek,
    byte? ToWeek,
    string? Season,
    string? SourceCitation,
    int VersionNumber,
    Guid? PublishedVersionId,
    bool IsDeleted,
    DateTime CreatedOn,
    DateTime ModifiedOn,
    string? CategoryKey,
    string? AuthorName,
    string? Title);

public sealed record ContentVersionDto(
    Guid ContentVersionId,
    int VersionNumber,
    string? ChangeSummary,
    DateTime CreatedOn,
    Guid? CreatedBy,
    string SnapshotJson,
    bool IsPublished);

public sealed record ContentCategoryDto(
    int CategoryId, string Key, int SortOrder, bool IsActive, int ItemCount);

public sealed record ContentAuthorDto(
    Guid AuthorId, Guid? UserId, string DisplayName,
    string? Credentials, string? Bio, bool IsActive);

public sealed record MediaDto(
    Guid MediaId, string FileName, string ContentType, long SizeBytes,
    string StorageKey, int? Width, int? Height, string? AltText,
    DateTime CreatedOn);

/// <summary>What the mobile client reads.</summary>
public sealed record ClientContentDto(
    Guid ContentItemId,
    string ContentType,
    string? Key,
    int Weight,
    string? SourceCitation,
    byte? FromWeek,
    byte? ToWeek,
    string? Season,
    DateTime ModifiedOn,
    string? CategoryKey,
    string? Title,
    string? Body,
    string? Summary,
    string? MetadataJson,
    bool IsFallback);

// ---------------------------------------------------------------------------
// Paging
// ---------------------------------------------------------------------------

public sealed record PagedResult<T>(
    IReadOnlyList<T> Items,
    int Page,
    int PageSize,
    int TotalCount)
{
    public int TotalPages =>
        PageSize == 0 ? 0 : (int)Math.Ceiling(TotalCount / (double)PageSize);

    public bool HasNext => Page < TotalPages;
    public bool HasPrevious => Page > 1;
}

// ---------------------------------------------------------------------------
// Writes
// ---------------------------------------------------------------------------

public sealed record SaveLocalizationRequest(
    string LanguageCode,
    string? Title,
    string? Body,
    string? Summary,
    string? Metadata,
    bool IsMachineTranslated = false);

public sealed record SaveContentRequest(
    Guid? ContentItemId,
    string ContentType,
    string? Key,
    string? CategoryKey,
    Guid? AuthorId,
    string? CountryFilter,
    string? MinAppVersion,
    byte? FromWeek,
    byte? ToWeek,
    string? Season,
    int Weight,
    string? SourceCitation,
    IReadOnlyList<SaveLocalizationRequest> Localizations,
    IReadOnlyList<string>? Tags,
    string? ChangeSummary,
    /// <summary>
    /// The version the editor loaded. When supplied and stale, the save is
    /// refused rather than silently overwriting somebody else's work.
    /// </summary>
    int? ExpectedVersionNumber);

public sealed record SaveContentResponse(
    Guid ContentItemId, Guid ContentVersionId, int VersionNumber);

public sealed record PublishContentRequest(
    Guid? ContentVersionId,
    DateTime? PublishFromUtc,
    DateTime? PublishUntilUtc);

public sealed record ApproveContentRequest(
    Guid? ContentVersionId, bool IsApproved, string? Reason);

public sealed record ReviewContentRequest(
    Guid? ContentVersionId, string ReviewKind, string Outcome, string? Comments);

public sealed record ScheduleContentRequest(string Action, DateTime ScheduledUtc);

public sealed record RestoreVersionRequest(Guid ContentVersionId);

public sealed record SaveAuthorRequest(
    Guid? AuthorId, Guid? UserId, string DisplayName,
    string? Credentials, string? Bio);

public sealed record SaveMediaRequest(
    Guid? MediaId, string FileName, string ContentType, long SizeBytes,
    string StorageKey, int? Width, int? Height, string? AltText);

/// <summary>Applies one operation to many items in a single transaction.</summary>
/// <remarks>
/// All-or-nothing. A bulk publish that half-succeeds leaves an editor with no
/// way to tell which items went live without checking each one.
/// </remarks>
public sealed record BulkContentRequest(
    IReadOnlyList<Guid> ContentItemIds, string Operation);

public sealed record BulkContentResponse(
    int Succeeded, int Failed, IReadOnlyDictionary<string, string> Failures);

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

public sealed record ContentSearchQuery(
    string? Query = null,
    string? ContentType = null,
    string? CategoryKey = null,
    string? Status = null,
    string? LanguageCode = null,
    Guid? AuthorId = null,
    string? TagKey = null,
    bool IncludeDeleted = false,
    int Page = 1,
    int PageSize = 25,
    string SortBy = "modified",
    bool SortDescending = true);

// ---------------------------------------------------------------------------
// Delta content sync (mobile)
// ---------------------------------------------------------------------------

/// <summary>One content item as the mobile client stores it.</summary>
public sealed record DeltaContentItemDto(
    Guid ContentItemId,
    string ContentType,
    string? Key,
    int Weight,
    string? SourceCitation,
    byte? FromWeek,
    byte? ToWeek,
    string? Season,
    DateTime ModifiedOn,
    int VersionNumber,
    string? CategoryKey,
    string? Title,
    string? Body,
    string? Summary,
    string? MetadataJson,
    bool IsFallback);

/// <summary>
/// An item the client should delete from its cache.
/// </summary>
/// <remarks>
/// The half a naive "changed since" sync omits. Without it a client that has
/// cached a now-retired article keeps showing it forever, and a rollback never
/// reaches the device.
/// </remarks>
public sealed record ContentTombstoneDto(
    Guid ContentItemId,
    string? Key,
    string ContentType,
    DateTime ModifiedOn);

/// <summary>The whole delta: what changed, what to remove, and the next token.</summary>
public sealed record ContentDeltaDto(
    /// <summary>
    /// Opaque cursor. Pass it back verbatim as <c>since</c> on the next sync.
    /// A hex-encoded rowversion — the client never parses it, only echoes it.
    /// </summary>
    string SyncToken,
    IReadOnlyList<DeltaContentItemDto> Upserts,
    IReadOnlyList<ContentTombstoneDto> Tombstones);
