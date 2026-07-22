using System.Data;
using System.Text.Json;
using Dapper;
using Maren.Application.Abstractions;
using Maren.Contracts;
using Maren.Shared;
using Microsoft.Data.SqlClient;

namespace Maren.Persistence;

/// <summary>
/// A connection and optional transaction shared across repository calls.
/// </summary>
/// <remarks>
/// Scoped, so one request gets one instance. Repositories ask it for the
/// ambient connection: outside a transaction they get a fresh short-lived one,
/// inside a transaction they get the enlisted one. That is what lets a bulk
/// operation span several stored procedure calls atomically without every
/// repository method growing a transaction parameter.
/// </remarks>
public sealed class SqlUnitOfWork(IDbConnectionFactory factory)
    : IUnitOfWork, IAmbientConnection
{
    private IDbConnection? _connection;
    private IDbTransaction? _transaction;

    public bool IsActive => _transaction is not null;

    public async Task BeginAsync(CancellationToken ct = default)
    {
        if (_transaction is not null)
            throw new InvalidOperationException("A transaction is already open.");

        _connection ??= await factory.CreateAsync(ct);
        _transaction = _connection.BeginTransaction(IsolationLevel.ReadCommitted);
    }

    public Task CommitAsync(CancellationToken ct = default)
    {
        _transaction?.Commit();
        DisposeTransaction();
        return Task.CompletedTask;
    }

    public Task RollbackAsync(CancellationToken ct = default)
    {
        _transaction?.Rollback();
        DisposeTransaction();
        return Task.CompletedTask;
    }

    /// <summary>
    /// The connection a repository call should use, plus its transaction.
    /// </summary>
    /// <param name="owned">
    /// True when the caller must dispose it. False inside a transaction, where
    /// the unit of work owns the lifetime.
    /// </param>
    public async Task<(IDbConnection Connection, IDbTransaction? Transaction, bool Owned)>
        GetAsync(CancellationToken ct)
    {
        if (_transaction is not null && _connection is not null)
            return (_connection, _transaction, false);

        return (await factory.CreateAsync(ct), null, true);
    }

    private void DisposeTransaction()
    {
        _transaction?.Dispose();
        _transaction = null;
    }

    public ValueTask DisposeAsync()
    {
        // Rolls back rather than committing. Reaching dispose with an open
        // transaction means an exception unwound past the commit, and the
        // safe reading of that is "this did not finish".
        if (_transaction is not null)
        {
            try { _transaction.Rollback(); } catch { /* already dead */ }
        }
        DisposeTransaction();
        _connection?.Dispose();
        _connection = null;
        return ValueTask.CompletedTask;
    }
}

public interface IAmbientConnection
{
    Task<(IDbConnection Connection, IDbTransaction? Transaction, bool Owned)>
        GetAsync(CancellationToken ct);
}

/// <summary>
/// Turns SQL Server errors into failure codes the API can act on.
/// </summary>
/// <remarks>
/// Without this a duplicate key surfaces as a 500 with a stack trace, which
/// tells an editor nothing and tells an attacker the table name. The numbers
/// below are the ones this schema can actually produce.
/// </remarks>
internal static class SqlErrorMapper
{
    public static Result<T> Map<T>(SqlException ex) =>
        Result<T>.Failure(CodeFor(ex), MessageFor(ex));

    public static Result Map(SqlException ex) =>
        Result.Failure(CodeFor(ex), MessageFor(ex));

    private static string CodeFor(SqlException ex) => ex.Number switch
    {
        2601 or 2627 => ContentFailureCodes.DuplicateKey,
        547 => ContentFailureCodes.ReferenceViolation,
        1205 => ContentFailureCodes.Deadlock,
        -2 => ContentFailureCodes.Timeout,
        _ => ContentFailureCodes.StorageFailure
    };

    private static string MessageFor(SqlException ex) => ex.Number switch
    {
        2601 or 2627 =>
            "Another item already uses that key. Keys are unique per content type.",
        547 =>
            "That referenced a category, author or version that does not exist.",
        1205 =>
            "The database was busy and rolled this back. Try again.",
        -2 =>
            "The database took too long to respond. Nothing was changed.",
        // Deliberately generic. The raw message can name tables and columns.
        _ => "The change could not be saved."
    };
}

public sealed class ContentRepository(IAmbientConnection ambient) : IContentRepository
{
    private static readonly JsonSerializerOptions JsonOptions =
        new(JsonSerializerDefaults.Web);

    // -----------------------------------------------------------------------
    // Reads
    // -----------------------------------------------------------------------

    public async Task<ContentItemDto?> GetAsync(Guid id, CancellationToken ct)
    {
        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            using var grid = await connection.QueryMultipleAsync(
                new CommandDefinition(
                    "[Content].[usp_Content_Get]",
                    new { ContentItemId = id },
                    transaction, commandType: CommandType.StoredProcedure,
                    cancellationToken: ct));

            var header = await grid.ReadSingleOrDefaultAsync<ContentHeaderRow>();
            if (header is null) return null;

            var localizations =
                (await grid.ReadAsync<ContentLocalizationDto>()).ToList();
            var tags = (await grid.ReadAsync<ContentTagDto>()).ToList();

            return header.ToDto(localizations, tags);
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    public async Task<PagedResult<ContentListItemDto>> SearchAsync(
        ContentSearchQuery query, CancellationToken ct)
    {
        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            var rows = (await connection.QueryAsync<SearchRow>(
                new CommandDefinition(
                    "[Content].[usp_Content_Search]",
                    new
                    {
                        query.Query,
                        query.ContentType,
                        query.CategoryKey,
                        query.Status,
                        query.LanguageCode,
                        query.AuthorId,
                        query.TagKey,
                        query.IncludeDeleted,
                        query.Page,
                        query.PageSize,
                        query.SortBy,
                        query.SortDescending
                    },
                    transaction, commandType: CommandType.StoredProcedure,
                    cancellationToken: ct))).ToList();

            // TotalCount rides on every row via COUNT(*) OVER(). An empty page
            // means zero matches, so defaulting to 0 is correct rather than a
            // second round trip to find out.
            var total = rows.Count > 0 ? rows[0].TotalCount : 0;

            return new PagedResult<ContentListItemDto>(
                rows.Select(r => r.ToDto()).ToList(),
                query.Page, query.PageSize, total);
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    public async Task<IReadOnlyList<ContentVersionDto>> GetVersionsAsync(
        Guid id, CancellationToken ct)
    {
        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            return (await connection.QueryAsync<ContentVersionDto>(
                new CommandDefinition(
                    "[Content].[usp_Content_Revisions]",
                    new { ContentItemId = id },
                    transaction, commandType: CommandType.StoredProcedure,
                    cancellationToken: ct))).ToList();
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    public async Task<int?> GetVersionNumberAsync(Guid id, CancellationToken ct)
    {
        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            return await connection.QuerySingleOrDefaultAsync<int?>(
                new CommandDefinition(
                    "SELECT VersionNumber FROM [Content].[ContentItem] " +
                    "WHERE ContentItemId = @id",
                    new { id }, transaction, cancellationToken: ct));
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    public async Task<IReadOnlyList<ContentCategoryDto>> GetCategoriesAsync(
        CancellationToken ct)
    {
        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            return (await connection.QueryAsync<ContentCategoryDto>(
                new CommandDefinition(
                    "[Content].[usp_Content_Categories]",
                    transaction: transaction,
                    commandType: CommandType.StoredProcedure,
                    cancellationToken: ct))).ToList();
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    public async Task<IReadOnlyList<ClientContentDto>> GetForClientAsync(
        string? contentType, string languageCode, string? countryIso,
        int? appVersionCode, byte? week, string? season,
        DateTime? modifiedSince, CancellationToken ct)
    {
        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            return (await connection.QueryAsync<ClientContentDto>(
                new CommandDefinition(
                    "[Content].[usp_Content_GetForClient]",
                    new
                    {
                        ContentType = contentType,
                        LanguageCode = languageCode,
                        CountryIso = countryIso,
                        AppVersionCode = appVersionCode,
                        Week = week,
                        Season = season,
                        ModifiedSince = modifiedSince
                    },
                    transaction, commandType: CommandType.StoredProcedure,
                    cancellationToken: ct))).ToList();
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    // -----------------------------------------------------------------------
    // Writes
    // -----------------------------------------------------------------------

    public async Task<Result<SaveContentResponse>> SaveAsync(
        SaveContentRequest request, Guid? actorUserId, CancellationToken ct)
    {
        // Optimistic concurrency, checked before the write rather than relying
        // on a rowversion. Two editors on the same item is the common case in
        // a CMS, and losing an edit silently is the failure that erodes trust
        // in the tool.
        if (request.ExpectedVersionNumber is { } expected &&
            request.ContentItemId is { } existingId)
        {
            var current = await GetVersionNumberAsync(existingId, ct);
            if (current is not null && current != expected)
            {
                return Result<SaveContentResponse>.Failure(
                    ContentFailureCodes.VersionConflict,
                    $"This item has moved on to version {current} since you " +
                    "opened it. Reload to see the changes before saving.");
            }
        }

        var localizations = JsonSerializer.Serialize(
            request.Localizations.Select(l => new
            {
                languageCode = l.LanguageCode,
                title = l.Title,
                body = l.Body,
                summary = l.Summary,
                metadata = l.Metadata,
                isMachineTranslated = l.IsMachineTranslated
            }), JsonOptions);

        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            var saved = await connection.QuerySingleAsync<SaveContentResponse>(
                new CommandDefinition(
                    "[Content].[usp_Content_Save]",
                    new
                    {
                        request.ContentItemId,
                        request.ContentType,
                        request.Key,
                        request.CategoryKey,
                        request.AuthorId,
                        request.CountryFilter,
                        request.MinAppVersion,
                        request.FromWeek,
                        request.ToWeek,
                        request.Season,
                        request.Weight,
                        request.SourceCitation,
                        LocalizationsJson = localizations,
                        request.ChangeSummary,
                        ActorUserId = actorUserId
                    },
                    transaction, commandType: CommandType.StoredProcedure,
                    cancellationToken: ct));

            if (request.Tags is { Count: > 0 })
            {
                await connection.ExecuteAsync(new CommandDefinition(
                    "[Content].[usp_Content_SetTags]",
                    new
                    {
                        saved.ContentItemId,
                        TagKeysJson = JsonSerializer.Serialize(request.Tags),
                        ActorUserId = actorUserId
                    },
                    transaction, commandType: CommandType.StoredProcedure,
                    cancellationToken: ct));
            }

            return Result<SaveContentResponse>.Success(saved);
        }
        catch (SqlException ex)
        {
            return SqlErrorMapper.Map<SaveContentResponse>(ex);
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    public Task<Result> PublishAsync(
        Guid id, PublishContentRequest request, Guid? actorUserId,
        bool requireApproval, CancellationToken ct) =>
        ExecuteOutcomeAsync("[Content].[usp_Content_Publish]", new
        {
            ContentItemId = id,
            request.ContentVersionId,
            request.PublishFromUtc,
            request.PublishUntilUtc,
            ActorUserId = actorUserId,
            RequireApproval = requireApproval
        }, ct);

    public Task<Result> UnpublishAsync(
        Guid id, Guid? actorUserId, CancellationToken ct) =>
        ExecuteOutcomeAsync("[Content].[usp_Content_Unpublish]",
            new { ContentItemId = id, ActorUserId = actorUserId }, ct);

    public Task<Result> ApproveAsync(
        Guid id, ApproveContentRequest request, Guid? actorUserId,
        CancellationToken ct) =>
        ExecuteOutcomeAsync("[Content].[usp_Content_Approve]", new
        {
            ContentItemId = id,
            request.ContentVersionId,
            request.IsApproved,
            request.Reason,
            ActorUserId = actorUserId
        }, ct);

    public async Task<Result> ReviewAsync(
        Guid id, ReviewContentRequest request, Guid? actorUserId,
        CancellationToken ct)
    {
        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            await connection.ExecuteAsync(new CommandDefinition(
                "INSERT INTO [Content].[ContentReview] " +
                "(ContentItemId, ContentVersionId, ReviewerUserId, ReviewKind, " +
                " Outcome, Comments) " +
                "VALUES (@ContentItemId, " +
                "  COALESCE(@ContentVersionId, (SELECT CurrentVersionId FROM " +
                "    [Content].[ContentItem] WHERE ContentItemId = @ContentItemId)), " +
                "  @ReviewerUserId, @ReviewKind, @Outcome, @Comments)",
                new
                {
                    ContentItemId = id,
                    request.ContentVersionId,
                    ReviewerUserId = actorUserId,
                    request.ReviewKind,
                    request.Outcome,
                    request.Comments
                },
                transaction, cancellationToken: ct));

            await connection.ExecuteAsync(new CommandDefinition(
                "INSERT INTO [Audit].[AuditLog] " +
                "(ActorUserId, ActorKind, [Action], EntityType, EntityId) " +
                "VALUES (@actor, 'admin', 'Content.Review', 'ContentItem', @id)",
                new { actor = actorUserId, id = id.ToString() },
                transaction, cancellationToken: ct));

            return Result.Success();
        }
        catch (SqlException ex)
        {
            return SqlErrorMapper.Map(ex);
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    public Task<Result> DeleteAsync(
        Guid id, Guid? actorUserId, CancellationToken ct) =>
        ExecuteOutcomeAsync("[Content].[usp_Content_Delete]",
            new { ContentItemId = id, ActorUserId = actorUserId }, ct);

    public Task<Result> RestoreVersionAsync(
        Guid id, Guid versionId, Guid? actorUserId, CancellationToken ct) =>
        ExecuteOutcomeAsync("[Content].[usp_Content_RestoreVersion]", new
        {
            ContentItemId = id,
            ContentVersionId = versionId,
            ActorUserId = actorUserId
        }, ct);

    public Task<Result> ScheduleAsync(
        Guid id, ScheduleContentRequest request, Guid? actorUserId,
        CancellationToken ct) =>
        ExecuteOutcomeAsync("[Content].[usp_Content_Schedule]", new
        {
            ContentItemId = id,
            request.Action,
            request.ScheduledUtc,
            ActorUserId = actorUserId
        }, ct);

    public Task<Result> SetTagsAsync(
        Guid id, IReadOnlyList<string> tags, Guid? actorUserId,
        CancellationToken ct) =>
        ExecuteOutcomeAsync("[Content].[usp_Content_SetTags]", new
        {
            ContentItemId = id,
            TagKeysJson = JsonSerializer.Serialize(tags),
            ActorUserId = actorUserId
        }, ct);

    public async Task<int> RunDueSchedulesAsync(int batchSize, CancellationToken ct)
    {
        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            return await connection.QuerySingleAsync<int>(new CommandDefinition(
                "[Content].[usp_Content_RunDueSchedules]",
                new { BatchSize = batchSize },
                transaction, commandType: CommandType.StoredProcedure,
                cancellationToken: ct));
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    public async Task<ContentAuthorDto> SaveAuthorAsync(
        SaveAuthorRequest request, Guid? actorUserId, CancellationToken ct)
    {
        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            return await connection.QuerySingleAsync<ContentAuthorDto>(
                new CommandDefinition(
                    "[Content].[usp_Content_SaveAuthor]",
                    new
                    {
                        request.AuthorId,
                        request.UserId,
                        request.DisplayName,
                        request.Credentials,
                        request.Bio,
                        ActorUserId = actorUserId
                    },
                    transaction, commandType: CommandType.StoredProcedure,
                    cancellationToken: ct));
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    public async Task<MediaDto> SaveMediaAsync(
        SaveMediaRequest request, Guid? actorUserId, CancellationToken ct)
    {
        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            return await connection.QuerySingleAsync<MediaDto>(
                new CommandDefinition(
                    "[Content].[usp_Media_Save]",
                    new
                    {
                        request.MediaId,
                        request.FileName,
                        request.ContentType,
                        request.SizeBytes,
                        request.StorageKey,
                        request.Width,
                        request.Height,
                        request.AltText,
                        ActorUserId = actorUserId
                    },
                    transaction, commandType: CommandType.StoredProcedure,
                    cancellationToken: ct));
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    // -----------------------------------------------------------------------

    /// <summary>
    /// Runs a procedure that returns the (Succeeded, FailureCode) pair.
    /// </summary>
    /// <remarks>
    /// Every workflow procedure returns that shape, so the mapping lives here
    /// once. Copying the try/catch and the null-check into each method is how
    /// one of them ends up silently swallowing a failure.
    /// </remarks>
    private async Task<Result> ExecuteOutcomeAsync(
        string procedure, object parameters, CancellationToken ct)
    {
        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            var outcome = await connection.QuerySingleOrDefaultAsync<OutcomeRow>(
                new CommandDefinition(
                    procedure, parameters, transaction,
                    commandType: CommandType.StoredProcedure,
                    cancellationToken: ct));

            if (outcome is null)
            {
                return Result.Failure(ContentFailureCodes.StorageFailure,
                    "The operation returned no result.");
            }

            return outcome.Succeeded
                ? Result.Success()
                : Result.Failure(outcome.FailureCode ?? FailureCodes.NotFound);
        }
        catch (SqlException ex)
        {
            return SqlErrorMapper.Map(ex);
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    // -----------------------------------------------------------------------
    // Row shapes
    // -----------------------------------------------------------------------

    private sealed class OutcomeRow
    {
        public bool Succeeded { get; init; }
        public string? FailureCode { get; init; }
    }

    private sealed class ContentHeaderRow
    {
        public Guid ContentItemId { get; init; }
        public string ContentType { get; init; } = "";
        public string? Key { get; init; }
        public string Status { get; init; } = "";
        public int Weight { get; init; }
        public string? CountryFilter { get; init; }
        public string? MinAppVersion { get; init; }
        public byte? FromWeek { get; init; }
        public byte? ToWeek { get; init; }
        public string? Season { get; init; }
        public string? SourceCitation { get; init; }
        public DateTime? ReviewedUtc { get; init; }
        public string? ReviewedBy { get; init; }
        public int VersionNumber { get; init; }
        public Guid? CurrentVersionId { get; init; }
        public Guid? PublishedVersionId { get; init; }
        public DateTime? PublishFromUtc { get; init; }
        public DateTime? PublishUntilUtc { get; init; }
        public bool IsDeleted { get; init; }
        public DateTime CreatedUtc { get; init; }
        public DateTime ModifiedUtc { get; init; }
        public string? CategoryKey { get; init; }
        public Guid? AuthorId { get; init; }
        public string? AuthorName { get; init; }

        public ContentItemDto ToDto(
            IReadOnlyList<ContentLocalizationDto> localizations,
            IReadOnlyList<ContentTagDto> tags) =>
            new(ContentItemId, ContentType, Key, Status, Weight, CountryFilter,
                MinAppVersion, FromWeek, ToWeek, Season, SourceCitation,
                ReviewedUtc, ReviewedBy, VersionNumber, CurrentVersionId,
                PublishedVersionId, PublishFromUtc, PublishUntilUtc, IsDeleted,
                CreatedUtc, ModifiedUtc, CategoryKey, AuthorId, AuthorName,
                localizations, tags);
    }

    private sealed class SearchRow
    {
        public Guid ContentItemId { get; init; }
        public string ContentType { get; init; } = "";
        public string? Key { get; init; }
        public string Status { get; init; } = "";
        public int Weight { get; init; }
        public byte? FromWeek { get; init; }
        public byte? ToWeek { get; init; }
        public string? Season { get; init; }
        public string? SourceCitation { get; init; }
        public int VersionNumber { get; init; }
        public Guid? PublishedVersionId { get; init; }
        public bool IsDeleted { get; init; }
        public DateTime CreatedUtc { get; init; }
        public DateTime ModifiedUtc { get; init; }
        public string? CategoryKey { get; init; }
        public string? AuthorName { get; init; }
        public string? Title { get; init; }
        public int TotalCount { get; init; }

        public ContentListItemDto ToDto() =>
            new(ContentItemId, ContentType, Key, Status, Weight, FromWeek,
                ToWeek, Season, SourceCitation, VersionNumber,
                PublishedVersionId, IsDeleted, CreatedUtc, ModifiedUtc,
                CategoryKey, AuthorName, Title);
    }
}
