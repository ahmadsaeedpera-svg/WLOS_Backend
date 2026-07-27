/* Required for filtered indexes and indexes on computed columns. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Content procedures.

    ## Every write versions first

    usp_Content_Save snapshots the item into ContentVersion before it mutates
    anything, then advances the pointer. So the history is written even if the
    subsequent update fails, and "restore" is a snapshot read rather than a
    reconstruction from a diff chain.

    ## Publishing is a pointer move

    usp_Content_Publish sets PublishedVersionId. It never edits the payload.
    That is what lets an editor keep drafting past a published version without
    the app seeing the work in progress.
*/

-- ---------------------------------------------------------------------------
-- usp_Content_Save
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Content.usp_Content_Save') IS NOT NULL
    DROP PROCEDURE [Content].[usp_Content_Save];
GO
CREATE PROCEDURE [Content].[usp_Content_Save]
    @ContentItemId  UNIQUEIDENTIFIER = NULL,
    @ContentType    VARCHAR(40),
    @Key            VARCHAR(150) = NULL,
    @CategoryKey    VARCHAR(64) = NULL,
    @AuthorId       UNIQUEIDENTIFIER = NULL,
    @CountryFilter  NVARCHAR(MAX) = NULL,
    @MinAppVersion  NVARCHAR(20) = NULL,
    @FromWeek       TINYINT = NULL,
    @ToWeek         TINYINT = NULL,
    @Season         VARCHAR(20) = NULL,
    @Weight         INT = 100,
    @SourceCitation NVARCHAR(300) = NULL,
    /*  JSON array: [{ "languageCode": "en-GB", "title": "...", "body": "...",
        "summary": "...", "metadataJson": "..." }] */
    @LocalizationsJson NVARCHAR(MAX),
    @ChangeSummary  NVARCHAR(500) = NULL,
    @ActorUserId    UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @isNew BIT = 0;
    DECLARE @categoryId INT =
        (SELECT CategoryId FROM [Content].[Category] WHERE [Key] = @CategoryKey);
    DECLARE @nextVersion INT;
    DECLARE @versionId UNIQUEIDENTIFIER = NEWID();

    IF @ContentItemId IS NULL OR NOT EXISTS (
        SELECT 1 FROM [Content].[ContentItem] WHERE ContentItemId = @ContentItemId)
    BEGIN
        SET @isNew = 1;
        SET @ContentItemId = ISNULL(@ContentItemId, NEWID());
    END

    BEGIN TRAN;

        IF @isNew = 1
        BEGIN
            INSERT INTO [Content].[ContentItem]
                (ContentItemId, ContentType, [Key], CategoryId, AuthorId,
                 Status, CountryFilter, MinAppVersion, FromWeek, ToWeek,
                 Season, Weight, SourceCitation, CreatedBy, ModifiedBy)
            VALUES
                (@ContentItemId, @ContentType, @Key, @categoryId, @AuthorId,
                 'draft', @CountryFilter, @MinAppVersion, @FromWeek, @ToWeek,
                 @Season, @Weight, @SourceCitation, @ActorUserId, @ActorUserId);
        END
        ELSE
        BEGIN
            UPDATE [Content].[ContentItem]
            SET ContentType = @ContentType,
                [Key] = @Key,
                CategoryId = @categoryId,
                AuthorId = @AuthorId,
                CountryFilter = @CountryFilter,
                MinAppVersion = @MinAppVersion,
                FromWeek = @FromWeek,
                ToWeek = @ToWeek,
                Season = @Season,
                Weight = @Weight,
                SourceCitation = @SourceCitation,
                ModifiedOn = SYSUTCDATETIME(),
                ModifiedBy = @ActorUserId
            WHERE ContentItemId = @ContentItemId;
        END

        /*  Replace-all rather than merge.

            A localisation removed in the editor must disappear, and a merge
            would leave the old row behind — which is how a language nobody
            maintains any more keeps being served. The previous state is safe
            in the version snapshot taken below. */
        DELETE FROM [Content].[ContentTranslation]
        WHERE ContentItemId = @ContentItemId;

        INSERT INTO [Content].[ContentTranslation]
            (ContentItemId, LanguageCode, Title, Body, Summary, MetadataJson,
             IsMachineTranslated)
        SELECT
            @ContentItemId,
            JSON_VALUE(value, '$.languageCode'),
            JSON_VALUE(value, '$.title'),
            JSON_VALUE(value, '$.body'),
            JSON_VALUE(value, '$.summary'),
            JSON_QUERY(value, '$.metadata'),
            ISNULL(TRY_CAST(JSON_VALUE(value, '$.isMachineTranslated') AS BIT), 0)
        FROM OPENJSON(@LocalizationsJson);

        SET @nextVersion = ISNULL(
            (SELECT MAX(VersionNumber) FROM [Content].[ContentVersion]
             WHERE ContentItemId = @ContentItemId), 0) + 1;

        INSERT INTO [Content].[ContentVersion]
            (ContentVersionId, ContentItemId, VersionNumber, SnapshotJson,
             ChangeSummary, CreatedBy)
        SELECT
            @versionId, @ContentItemId, @nextVersion,
            (SELECT
                i.ContentType, i.[Key], i.CountryFilter, i.MinAppVersion,
                i.FromWeek, i.ToWeek, i.Season, i.Weight, i.SourceCitation,
                (SELECT t.LanguageCode, t.Title, t.Body, t.Summary,
                        t.MetadataJson, t.IsMachineTranslated
                 FROM [Content].[ContentTranslation] t
                 WHERE t.ContentItemId = i.ContentItemId
                 FOR JSON PATH) AS Localizations
             FROM [Content].[ContentItem] i
             WHERE i.ContentItemId = @ContentItemId
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
            @ChangeSummary, @ActorUserId;

        UPDATE [Content].[ContentItem]
        SET CurrentVersionId = @versionId, VersionNumber = @nextVersion
        WHERE ContentItemId = @ContentItemId;

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId, AfterJson)
        VALUES
            (@ActorUserId, 'admin',
             CASE WHEN @isNew = 1 THEN 'Content.Create' ELSE 'Content.Update' END,
             'ContentItem', CONVERT(NVARCHAR(50), @ContentItemId),
             CONCAT('{"version":', @nextVersion, '}'));

    COMMIT TRAN;

    SELECT @ContentItemId AS ContentItemId, @versionId AS ContentVersionId,
           @nextVersion AS VersionNumber;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Content_Publish / Unpublish
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Content.usp_Content_Publish') IS NOT NULL
    DROP PROCEDURE [Content].[usp_Content_Publish];
GO
CREATE PROCEDURE [Content].[usp_Content_Publish]
    @ContentItemId   UNIQUEIDENTIFIER,
    @ContentVersionId UNIQUEIDENTIFIER = NULL,
    @PublishFromUtc  DATETIME2(3) = NULL,
    @PublishUntilUtc DATETIME2(3) = NULL,
    @ActorUserId     UNIQUEIDENTIFIER = NULL,
    /*  When set, publishing refuses unless an approval exists for the exact
        version being published. Off for content types where an editorial
        sign-off is not required; on for anything clinical. */
    @RequireApproval BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @version UNIQUEIDENTIFIER = COALESCE(
        @ContentVersionId,
        (SELECT CurrentVersionId FROM [Content].[ContentItem]
         WHERE ContentItemId = @ContentItemId));

    IF @version IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'NO_VERSION' AS FailureCode;
        RETURN;
    END

    IF @RequireApproval = 1 AND NOT EXISTS (
        SELECT 1 FROM [Content].[ContentApproval]
        WHERE ContentItemId = @ContentItemId
          AND ContentVersionId = @version
          AND IsApproved = 1)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'NOT_APPROVED' AS FailureCode;
        RETURN;
    END

    BEGIN TRAN;

        UPDATE [Content].[ContentItem]
        SET Status = 'published',
            PublishedVersionId = @version,
            PublishFromUtc = COALESCE(@PublishFromUtc, SYSUTCDATETIME()),
            PublishUntilUtc = @PublishUntilUtc,
            ModifiedOn = SYSUTCDATETIME(),
            ModifiedBy = @ActorUserId
        WHERE ContentItemId = @ContentItemId;

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId, AfterJson)
        VALUES
            (@ActorUserId, 'admin', 'Content.Publish', 'ContentItem',
             CONVERT(NVARCHAR(50), @ContentItemId),
             CONCAT('{"versionId":"', CONVERT(NVARCHAR(50), @version), '"}'));

    COMMIT TRAN;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(50)) AS FailureCode;
END
GO

IF OBJECT_ID('Content.usp_Content_Unpublish') IS NOT NULL
    DROP PROCEDURE [Content].[usp_Content_Unpublish];
GO
CREATE PROCEDURE [Content].[usp_Content_Unpublish]
    @ContentItemId UNIQUEIDENTIFIER,
    @ActorUserId   UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRAN;
        /*  PublishedVersionId is kept. Unpublishing is reversible and the app
            may still hold a cached copy; knowing which version that was is
            what makes a support question answerable. */
        UPDATE [Content].[ContentItem]
        SET Status = 'draft',
            PublishUntilUtc = SYSUTCDATETIME(),
            ModifiedOn = SYSUTCDATETIME(),
            ModifiedBy = @ActorUserId
        WHERE ContentItemId = @ContentItemId;

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId)
        VALUES
            (@ActorUserId, 'admin', 'Content.Unpublish', 'ContentItem',
             CONVERT(NVARCHAR(50), @ContentItemId));
    COMMIT TRAN;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(50)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Content_Approve / Reject
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Content.usp_Content_Approve') IS NOT NULL
    DROP PROCEDURE [Content].[usp_Content_Approve];
GO
CREATE PROCEDURE [Content].[usp_Content_Approve]
    @ContentItemId    UNIQUEIDENTIFIER,
    @ContentVersionId UNIQUEIDENTIFIER = NULL,
    @IsApproved       BIT,
    @Reason           NVARCHAR(MAX) = NULL,
    @ActorUserId      UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @version UNIQUEIDENTIFIER = COALESCE(
        @ContentVersionId,
        (SELECT CurrentVersionId FROM [Content].[ContentItem]
         WHERE ContentItemId = @ContentItemId));

    IF @version IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'NO_VERSION' AS FailureCode;
        RETURN;
    END

    BEGIN TRAN;

        INSERT INTO [Content].[ContentApproval]
            (ContentItemId, ContentVersionId, ApproverUserId, IsApproved, Reason)
        VALUES
            (@ContentItemId, @version, @ActorUserId, @IsApproved, @Reason);

        UPDATE [Content].[ContentItem]
        SET Status = CASE WHEN @IsApproved = 1 THEN 'review' ELSE 'draft' END,
            ModifiedOn = SYSUTCDATETIME(),
            ModifiedBy = @ActorUserId
        WHERE ContentItemId = @ContentItemId AND Status <> 'published';

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId, AfterJson)
        VALUES
            (@ActorUserId, 'admin',
             CASE WHEN @IsApproved = 1 THEN 'Content.Approve' ELSE 'Content.Reject' END,
             'ContentItem', CONVERT(NVARCHAR(50), @ContentItemId),
             CONCAT('{"versionId":"', CONVERT(NVARCHAR(50), @version), '"}'));

    COMMIT TRAN;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(50)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Content_RestoreVersion
-- ---------------------------------------------------------------------------
/*
    Restores by writing the old snapshot forward as a new version.

    Never by rewinding the version number. History stays append-only, so the
    restore itself is auditable and the version it replaced is still readable.
*/
IF OBJECT_ID('Content.usp_Content_RestoreVersion') IS NOT NULL
    DROP PROCEDURE [Content].[usp_Content_RestoreVersion];
GO
CREATE PROCEDURE [Content].[usp_Content_RestoreVersion]
    @ContentItemId    UNIQUEIDENTIFIER,
    @ContentVersionId UNIQUEIDENTIFIER,
    @ActorUserId      UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @snapshot NVARCHAR(MAX), @restoredFrom INT;

    SELECT @snapshot = SnapshotJson, @restoredFrom = VersionNumber
    FROM [Content].[ContentVersion]
    WHERE ContentVersionId = @ContentVersionId
      AND ContentItemId = @ContentItemId;

    IF @snapshot IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'NOT_FOUND' AS FailureCode;
        RETURN;
    END

    /*  Restore re-applies the snapshot rather than delegating to
        usp_Content_Save.

        Two reasons, both found by the workflow test. Calling Save with
        EXEC leaks its result set into any caller using INSERT ... EXEC,
        because SQL Server tries to shape the inner SELECT into the outer
        target table. And Save takes the localisations as a parameter, so
        delegating meant passing an empty array — which would have deleted
        every translation the restore was supposed to bring back. */

    DECLARE @nextVersion INT = ISNULL(
        (SELECT MAX(VersionNumber) FROM [Content].[ContentVersion]
         WHERE ContentItemId = @ContentItemId), 0) + 1;
    DECLARE @versionId UNIQUEIDENTIFIER = NEWID();

    BEGIN TRAN;

        UPDATE [Content].[ContentItem]
        SET ContentType    = JSON_VALUE(@snapshot, '$.ContentType'),
            [Key]          = JSON_VALUE(@snapshot, '$.Key'),
            CountryFilter  = JSON_QUERY(@snapshot, '$.CountryFilter'),
            MinAppVersion  = JSON_VALUE(@snapshot, '$.MinAppVersion'),
            FromWeek       = TRY_CAST(JSON_VALUE(@snapshot, '$.FromWeek') AS TINYINT),
            ToWeek         = TRY_CAST(JSON_VALUE(@snapshot, '$.ToWeek') AS TINYINT),
            Season         = JSON_VALUE(@snapshot, '$.Season'),
            Weight         = ISNULL(TRY_CAST(JSON_VALUE(@snapshot, '$.Weight') AS INT), 100),
            SourceCitation = JSON_VALUE(@snapshot, '$.SourceCitation'),
            ModifiedOn    = SYSUTCDATETIME(),
            ModifiedBy     = @ActorUserId
        WHERE ContentItemId = @ContentItemId;

        DELETE FROM [Content].[ContentTranslation]
        WHERE ContentItemId = @ContentItemId;

        INSERT INTO [Content].[ContentTranslation]
            (ContentItemId, LanguageCode, Title, Body, Summary, MetadataJson,
             IsMachineTranslated)
        SELECT
            @ContentItemId,
            JSON_VALUE(value, '$.LanguageCode'),
            JSON_VALUE(value, '$.Title'),
            JSON_VALUE(value, '$.Body'),
            JSON_VALUE(value, '$.Summary'),
            JSON_QUERY(value, '$.MetadataJson'),
            ISNULL(TRY_CAST(JSON_VALUE(value, '$.IsMachineTranslated') AS BIT), 0)
        FROM OPENJSON(@snapshot, '$.Localizations');

        INSERT INTO [Content].[ContentVersion]
            (ContentVersionId, ContentItemId, VersionNumber, SnapshotJson,
             ChangeSummary, CreatedBy)
        VALUES
            (@versionId, @ContentItemId, @nextVersion, @snapshot,
             CONCAT('Restored from version ', @restoredFrom), @ActorUserId);

        UPDATE [Content].[ContentItem]
        SET CurrentVersionId = @versionId, VersionNumber = @nextVersion
        WHERE ContentItemId = @ContentItemId;

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId, AfterJson)
        VALUES
            (@ActorUserId, 'admin', 'Content.RestoreVersion', 'ContentItem',
             CONVERT(NVARCHAR(50), @ContentItemId),
             CONCAT('{"restoredFrom":', @restoredFrom,
                    ',"newVersion":', @nextVersion, '}'));

    COMMIT TRAN;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(50)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Content_Delete
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Content.usp_Content_Delete') IS NOT NULL
    DROP PROCEDURE [Content].[usp_Content_Delete];
GO
CREATE PROCEDURE [Content].[usp_Content_Delete]
    @ContentItemId UNIQUEIDENTIFIER,
    @ActorUserId   UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRAN;
        /*  Soft. A hard delete would cascade the version history away, and the
            history is the record of what users were shown — which is exactly
            what a later clinical or legal question needs to consult. */
        UPDATE [Content].[ContentItem]
        SET IsDeleted = 1, Status = 'retired',
            ModifiedOn = SYSUTCDATETIME(), ModifiedBy = @ActorUserId
        WHERE ContentItemId = @ContentItemId;

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId)
        VALUES
            (@ActorUserId, 'admin', 'Content.Delete', 'ContentItem',
             CONVERT(NVARCHAR(50), @ContentItemId));
    COMMIT TRAN;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(50)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Content_Search
-- ---------------------------------------------------------------------------
/*
    Admin-side search and listing, paged.

    LIKE rather than a full-text index: full-text needs a catalog that has to
    exist before this deploys, and at the scale of an editorial library the
    difference is not measurable. The predicate is written so it can be swapped
    for CONTAINS() without changing the surface.
*/
IF OBJECT_ID('Content.usp_Content_Search') IS NOT NULL
    DROP PROCEDURE [Content].[usp_Content_Search];
GO
CREATE PROCEDURE [Content].[usp_Content_Search]
    @Query        NVARCHAR(300) = NULL,
    @ContentType  VARCHAR(40) = NULL,
    @CategoryKey  VARCHAR(64) = NULL,
    @Status       VARCHAR(20) = NULL,
    @LanguageCode CHAR(5) = NULL,
    @AuthorId     UNIQUEIDENTIFIER = NULL,
    @TagKey       VARCHAR(64) = NULL,
    @IncludeDeleted BIT = 0,
    @Page         INT = 1,
    @PageSize     INT = 25,
    @SortBy       VARCHAR(30) = 'modified',
    @SortDescending BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF @Page < 1 SET @Page = 1;
    IF @PageSize < 1 OR @PageSize > 200 SET @PageSize = 25;

    ;WITH matched AS (
        SELECT
            i.ContentItemId, i.ContentType, i.[Key], i.Status, i.Weight,
            i.FromWeek, i.ToWeek, i.Season, i.SourceCitation,
            i.VersionNumber, i.PublishedVersionId, i.IsDeleted,
            i.CreatedOn, i.ModifiedOn,
            c.[Key] AS CategoryKey,
            a.DisplayName AS AuthorName,
            (SELECT TOP 1 t.Title FROM [Content].[ContentTranslation] t
             WHERE t.ContentItemId = i.ContentItemId
               AND (@LanguageCode IS NULL OR t.LanguageCode = @LanguageCode)
             ORDER BY CASE WHEN t.LanguageCode = 'en-GB' THEN 0 ELSE 1 END
            ) AS Title
        FROM [Content].[ContentItem] i
        LEFT JOIN [Content].[Category] c ON c.CategoryId = i.CategoryId
        LEFT JOIN [Content].[ContentAuthor] a ON a.AuthorId = i.AuthorId
        WHERE (@IncludeDeleted = 1 OR i.IsDeleted = 0)
          AND (@ContentType IS NULL OR i.ContentType = @ContentType)
          AND (@Status IS NULL OR i.Status = @Status)
          AND (@AuthorId IS NULL OR i.AuthorId = @AuthorId)
          AND (@CategoryKey IS NULL OR c.[Key] = @CategoryKey)
          AND (@TagKey IS NULL OR EXISTS (
                SELECT 1 FROM [Content].[ContentItemTag] it
                JOIN [Content].[ContentTag] tg ON tg.TagId = it.TagId
                WHERE it.ContentItemId = i.ContentItemId AND tg.[Key] = @TagKey))
          AND (@Query IS NULL OR EXISTS (
                SELECT 1 FROM [Content].[ContentTranslation] t
                WHERE t.ContentItemId = i.ContentItemId
                  AND (t.Title LIKE '%' + @Query + '%'
                       OR t.Body LIKE '%' + @Query + '%'
                       OR t.Summary LIKE '%' + @Query + '%')))
    )
    SELECT *, COUNT(*) OVER() AS TotalCount
    FROM matched
    /*  Sort columns are selected by CASE rather than built into a string and
        executed, so the whole procedure stays parameterised and there is no
        path from @SortBy to injectable SQL. Each expression is typed
        consistently — mixing a date and a string inside one CASE makes SQL
        Server coerce both to the wider type and sort wrongly. */
    ORDER BY
        CASE WHEN @SortDescending = 0 AND @SortBy = 'title' THEN Title END ASC,
        CASE WHEN @SortDescending = 1 AND @SortBy = 'title' THEN Title END DESC,
        CASE WHEN @SortDescending = 0 AND @SortBy = 'created' THEN CreatedOn END ASC,
        CASE WHEN @SortDescending = 1 AND @SortBy = 'created' THEN CreatedOn END DESC,
        CASE WHEN @SortDescending = 0 AND @SortBy NOT IN ('title','created')
             THEN ModifiedOn END ASC,
        CASE WHEN @SortDescending = 1 AND @SortBy NOT IN ('title','created')
             THEN ModifiedOn END DESC,
        ContentItemId
    OFFSET (@Page - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Content_Get
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Content.usp_Content_Get') IS NOT NULL
    DROP PROCEDURE [Content].[usp_Content_Get];
GO
CREATE PROCEDURE [Content].[usp_Content_Get]
    @ContentItemId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT i.ContentItemId, i.ContentType, i.[Key], i.Status, i.Weight,
           i.CountryFilter, i.MinAppVersion, i.FromWeek, i.ToWeek, i.Season,
           i.SourceCitation, i.ReviewedUtc, i.ReviewedBy, i.VersionNumber,
           i.CurrentVersionId, i.PublishedVersionId, i.PublishFromUtc,
           i.PublishUntilUtc, i.IsDeleted, i.CreatedOn, i.ModifiedOn,
           c.[Key] AS CategoryKey, i.AuthorId, a.DisplayName AS AuthorName
    FROM [Content].[ContentItem] i
    LEFT JOIN [Content].[Category] c ON c.CategoryId = i.CategoryId
    LEFT JOIN [Content].[ContentAuthor] a ON a.AuthorId = i.AuthorId
    WHERE i.ContentItemId = @ContentItemId;

    SELECT LanguageCode, Title, Body, Summary, MetadataJson, IsMachineTranslated
    FROM [Content].[ContentTranslation]
    WHERE ContentItemId = @ContentItemId
    ORDER BY LanguageCode;

    SELECT tg.[Key], tg.Label
    FROM [Content].[ContentItemTag] it
    JOIN [Content].[ContentTag] tg ON tg.TagId = it.TagId
    WHERE it.ContentItemId = @ContentItemId
    ORDER BY tg.[Key];
END
GO

-- ---------------------------------------------------------------------------
-- usp_Content_Revisions
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Content.usp_Content_Revisions') IS NOT NULL
    DROP PROCEDURE [Content].[usp_Content_Revisions];
GO
CREATE PROCEDURE [Content].[usp_Content_Revisions]
    @ContentItemId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SELECT v.ContentVersionId, v.VersionNumber, v.ChangeSummary,
           v.CreatedOn, v.CreatedBy, v.SnapshotJson,
           CAST(CASE WHEN i.PublishedVersionId = v.ContentVersionId
                     THEN 1 ELSE 0 END AS BIT) AS IsPublished
    FROM [Content].[ContentVersion] v
    JOIN [Content].[ContentItem] i ON i.ContentItemId = v.ContentItemId
    WHERE v.ContentItemId = @ContentItemId
    ORDER BY v.VersionNumber DESC;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Content_GetForClient
-- ---------------------------------------------------------------------------
/*
    What the mobile app reads. Published versions only.

    The targeting predicates mirror the feature flag rules deliberately: an
    editor who understands one understands the other, and a content item that
    is region- or version-gated behaves the same way a feature is.
*/
IF OBJECT_ID('Content.usp_Content_GetForClient') IS NOT NULL
    DROP PROCEDURE [Content].[usp_Content_GetForClient];
GO
CREATE PROCEDURE [Content].[usp_Content_GetForClient]
    @ContentType    VARCHAR(40) = NULL,
    @LanguageCode   CHAR(5) = 'en-GB',
    @CountryIso     CHAR(2) = NULL,
    @AppVersionCode INT = NULL,
    @Week           TINYINT = NULL,
    @Season         VARCHAR(20) = NULL,
    @ModifiedSince  DATETIME2(3) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIME2(3) = SYSUTCDATETIME();

    /*  Text comes from the PUBLISHED VERSION SNAPSHOT, never from
        ContentTranslation.

        ContentTranslation is the live working copy — it holds whatever an
        editor last typed, reviewed or not. Reading it here made the approval
        workflow decorative: an editor opening a published article and typing
        pushed unreviewed text to every device on the next sync, with no
        approval, no audit of a publish, and no way to tell from the admin UI
        that it had happened. In a pregnancy app that is a clinical-safety
        problem, not only a workflow one.

        The snapshot is the exact bytes somebody approved. Serving those is the
        entire reason the version table stores JSON rather than pointers.

        Targeting (country, week, season, app version, publish window) is still
        read live from the item. Those are operational controls: narrowing
        distribution during an incident must take effect immediately and must
        not require a publish. Text is what approval governs; reach is what an
        operator governs. */
    SELECT
        i.ContentItemId, i.ContentType, i.[Key], i.Weight, i.SourceCitation,
        i.FromWeek, i.ToWeek, i.Season, i.ModifiedOn,
        c.[Key] AS CategoryKey,
        COALESCE(t.Title, fb.Title) AS Title,
        COALESCE(t.Body, fb.Body) AS Body,
        COALESCE(t.Summary, fb.Summary) AS Summary,
        COALESCE(t.MetadataJson, fb.MetadataJson) AS MetadataJson,
        /*  Falls back to en-GB when a translation is missing. Showing English
            beats showing an empty card, and the flag lets the client mark it
            rather than pretending it is localised. */
        CAST(CASE WHEN t.LanguageCode IS NULL THEN 1 ELSE 0 END AS BIT) AS IsFallback
    FROM [Content].[ContentItem] i
    LEFT JOIN [Content].[Category] c ON c.CategoryId = i.CategoryId
    JOIN [Content].[ContentVersion] pv
           ON pv.ContentVersionId = i.PublishedVersionId
    OUTER APPLY (
        SELECT TOP 1 j.Title, j.Body, j.Summary, j.MetadataJson, j.LanguageCode
        FROM OPENJSON(pv.SnapshotJson, '$.Localizations')
        WITH (
            LanguageCode CHAR(5)       '$.LanguageCode',
            Title        NVARCHAR(400) '$.Title',
            Body         NVARCHAR(MAX) '$.Body',
            Summary      NVARCHAR(1000)'$.Summary',
            MetadataJson NVARCHAR(MAX) '$.MetadataJson' AS JSON
        ) j
        WHERE j.LanguageCode = @LanguageCode
    ) t
    OUTER APPLY (
        SELECT TOP 1 j.Title, j.Body, j.Summary, j.MetadataJson
        FROM OPENJSON(pv.SnapshotJson, '$.Localizations')
        WITH (
            LanguageCode CHAR(5)       '$.LanguageCode',
            Title        NVARCHAR(400) '$.Title',
            Body         NVARCHAR(MAX) '$.Body',
            Summary      NVARCHAR(1000)'$.Summary',
            MetadataJson NVARCHAR(MAX) '$.MetadataJson' AS JSON
        ) j
        WHERE j.LanguageCode = 'en-GB'
    ) fb
    WHERE i.IsDeleted = 0
      AND i.Status = 'published'
      AND i.PublishedVersionId IS NOT NULL
      AND (i.PublishFromUtc IS NULL OR i.PublishFromUtc <= @now)
      AND (i.PublishUntilUtc IS NULL OR i.PublishUntilUtc > @now)
      AND (@ContentType IS NULL OR i.ContentType = @ContentType)
      AND (@ModifiedSince IS NULL OR i.ModifiedOn > @ModifiedSince)
      AND (i.MinAppVersion IS NULL OR @AppVersionCode IS NULL
           OR @AppVersionCode >= [Administration].[fn_VersionToCode](i.MinAppVersion))
      AND (i.CountryFilter IS NULL OR @CountryIso IS NULL
           OR EXISTS (SELECT 1 FROM OPENJSON(i.CountryFilter)
                      WHERE [value] = @CountryIso))
      AND (@Week IS NULL OR i.FromWeek IS NULL OR @Week >= i.FromWeek)
      AND (@Week IS NULL OR i.ToWeek IS NULL OR @Week <= i.ToWeek)
      AND (@Season IS NULL OR i.Season IS NULL OR i.Season = @Season)
      AND (COALESCE(t.Title, fb.Title) IS NOT NULL
           OR COALESCE(t.Body, fb.Body) IS NOT NULL)
    ORDER BY i.Weight DESC, i.ContentItemId;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Content_Schedule
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Content.usp_Content_Schedule') IS NOT NULL
    DROP PROCEDURE [Content].[usp_Content_Schedule];
GO
CREATE PROCEDURE [Content].[usp_Content_Schedule]
    @ContentItemId UNIQUEIDENTIFIER,
    @Action        VARCHAR(20),
    @ScheduledUtc  DATETIME2(3),
    @ActorUserId   UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO [Content].[ContentPublishSchedule]
        (ContentItemId, [Action], ScheduledUtc, CreatedBy)
    VALUES
        (@ContentItemId, @Action, @ScheduledUtc, @ActorUserId);

    INSERT INTO [Audit].[AuditLog]
        (ActorUserId, ActorKind, [Action], EntityType, EntityId, AfterJson)
    VALUES
        (@ActorUserId, 'admin', 'Content.Schedule', 'ContentItem',
         CONVERT(NVARCHAR(50), @ContentItemId),
         CONCAT('{"action":"', @Action, '"}'));

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(50)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Content_RunDueSchedules
-- ---------------------------------------------------------------------------
/*
    Executed by the background job.

    Claims rows with UPDATE ... OUTPUT before acting on them, so two workers
    racing cannot both publish the same item. A SELECT-then-UPDATE would let
    both read the same pending row.
*/
IF OBJECT_ID('Content.usp_Content_RunDueSchedules') IS NOT NULL
    DROP PROCEDURE [Content].[usp_Content_RunDueSchedules];
GO
CREATE PROCEDURE [Content].[usp_Content_RunDueSchedules]
    @BatchSize INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @claimed TABLE (
        ScheduleId UNIQUEIDENTIFIER,
        ContentItemId UNIQUEIDENTIFIER,
        [Action] VARCHAR(20));

    DECLARE @refused TABLE (
        ScheduleId UNIQUEIDENTIFIER,
        ContentItemId UNIQUEIDENTIFIER);

    UPDATE TOP (@BatchSize) s
    SET Status = 'executed', ExecutedUtc = SYSUTCDATETIME()
    OUTPUT inserted.ScheduleId, inserted.ContentItemId, inserted.[Action]
        INTO @claimed
    FROM [Content].[ContentPublishSchedule] s
    WHERE s.Status = 'pending' AND s.ScheduledUtc <= SYSUTCDATETIME();

    /*  A scheduled publish is the same act as an immediate one, deferred, so
        it answers to the same approval rule as usp_Content_Publish. Without
        this an editor could schedule an unreviewed draft and have it reach
        every device unattended - the one outcome the whole approval workflow
        exists to prevent.

        Refusals are recorded on the schedule row rather than dropped. The
        table already carries 'failed' and FailureReason for exactly this;
        leaving the row marked 'executed' would report success for work that
        never happened, and the editor would never learn why their post did
        not appear.

        An item with no current version fails here too, matching the
        NO_VERSION path in usp_Content_Publish. */
    UPDATE s
    SET Status = 'failed',
        ExecutedUtc = SYSUTCDATETIME(),
        FailureReason = N'Not published: this version has not been approved. '
                      + N'A scheduled publish follows the same approval rule '
                      + N'as an immediate one.'
    OUTPUT inserted.ScheduleId, inserted.ContentItemId INTO @refused
    FROM [Content].[ContentPublishSchedule] s
    JOIN @claimed c ON c.ScheduleId = s.ScheduleId
    JOIN [Content].[ContentItem] i ON i.ContentItemId = c.ContentItemId
    WHERE c.[Action] = 'publish'
      AND NOT EXISTS (
            SELECT 1 FROM [Content].[ContentApproval] a
            WHERE a.ContentItemId = i.ContentItemId
              AND a.ContentVersionId = i.CurrentVersionId
              AND a.IsApproved = 1);

    /*  Drop the refused rows so they are neither published below nor audited
        as though they had been. */
    DELETE c FROM @claimed c
    JOIN @refused r ON r.ScheduleId = c.ScheduleId;

    /*  Publishes CurrentVersionId, not COALESCE(PublishedVersionId, ...).
        For an item that had been published before, the COALESCE resolved to
        the version already live, so scheduling a newly approved edit quietly
        republished the old text. usp_Content_Publish defaults to the current
        version; this now agrees with it. */
    UPDATE i
    SET Status = 'published',
        PublishedVersionId = i.CurrentVersionId,
        PublishFromUtc = SYSUTCDATETIME(),
        ModifiedOn = SYSUTCDATETIME()
    FROM [Content].[ContentItem] i
    JOIN @claimed c ON c.ContentItemId = i.ContentItemId
    WHERE c.[Action] = 'publish';

    UPDATE i
    SET Status = CASE WHEN c.[Action] = 'retire' THEN 'retired' ELSE 'draft' END,
        PublishUntilUtc = SYSUTCDATETIME(),
        ModifiedOn = SYSUTCDATETIME()
    FROM [Content].[ContentItem] i
    JOIN @claimed c ON c.ContentItemId = i.ContentItemId
    WHERE c.[Action] IN ('unpublish','retire');

    INSERT INTO [Audit].[AuditLog]
        (ActorUserId, ActorKind, [Action], EntityType, EntityId)
    SELECT NULL, 'system', CONCAT('Content.Scheduled.', c.[Action]),
           'ContentItem', CONVERT(NVARCHAR(50), c.ContentItemId)
    FROM @claimed c;

    /*  A refused publish is worth an audit row of its own. It is the record
        that unreviewed content was stopped, and it is the only trace an
        operator has when an editor asks why a scheduled post never went out. */
    INSERT INTO [Audit].[AuditLog]
        (ActorUserId, ActorKind, [Action], EntityType, EntityId)
    SELECT NULL, 'system', 'Content.Scheduled.PublishRefused',
           'ContentItem', CONVERT(NVARCHAR(50), r.ContentItemId)
    FROM @refused r;

    /*  Counts work actually done. Refusals are deliberately excluded: the
        caller records this as the number of schedules executed, and a refusal
        is the opposite of that.

        One column, deliberately. The caller reads this with
        QuerySingleAsync<int>, so widening the result set here would break it
        silently at runtime - see CLAUDE.md 4.2. */
    SELECT COUNT(*) AS Executed FROM @claimed;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Content_Categories / Tags / Authors
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Content.usp_Content_Categories') IS NOT NULL
    DROP PROCEDURE [Content].[usp_Content_Categories];
GO
CREATE PROCEDURE [Content].[usp_Content_Categories]
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.CategoryId, c.[Key], c.SortOrder, c.IsActive,
           (SELECT COUNT(*) FROM [Content].[ContentItem] i
            WHERE i.CategoryId = c.CategoryId AND i.IsDeleted = 0) AS ItemCount
    FROM [Content].[Category] c
    ORDER BY c.SortOrder, c.[Key];
END
GO

IF OBJECT_ID('Content.usp_Content_SetTags') IS NOT NULL
    DROP PROCEDURE [Content].[usp_Content_SetTags];
GO
CREATE PROCEDURE [Content].[usp_Content_SetTags]
    @ContentItemId UNIQUEIDENTIFIER,
    @TagKeysJson   NVARCHAR(MAX),
    @ActorUserId   UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRAN;
        /*  Tags named but not yet defined are created rather than rejected.
            An editor typing a new tag should not have to visit another screen
            first; the taxonomy grows from use. */
        INSERT INTO [Content].[ContentTag] ([Key], Label)
        SELECT DISTINCT j.[value], j.[value]
        FROM OPENJSON(@TagKeysJson) j
        WHERE NOT EXISTS (SELECT 1 FROM [Content].[ContentTag] t
                          WHERE t.[Key] = j.[value]);

        DELETE FROM [Content].[ContentItemTag] WHERE ContentItemId = @ContentItemId;

        INSERT INTO [Content].[ContentItemTag] (ContentItemId, TagId)
        SELECT @ContentItemId, t.TagId
        FROM OPENJSON(@TagKeysJson) j
        JOIN [Content].[ContentTag] t ON t.[Key] = j.[value];
    COMMIT TRAN;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(50)) AS FailureCode;
END
GO

IF OBJECT_ID('Content.usp_Content_SaveAuthor') IS NOT NULL
    DROP PROCEDURE [Content].[usp_Content_SaveAuthor];
GO
CREATE PROCEDURE [Content].[usp_Content_SaveAuthor]
    @AuthorId    UNIQUEIDENTIFIER = NULL,
    @UserId      UNIQUEIDENTIFIER = NULL,
    @DisplayName NVARCHAR(200),
    @Credentials NVARCHAR(200) = NULL,
    @Bio         NVARCHAR(MAX) = NULL,
    @ActorUserId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @AuthorId = ISNULL(@AuthorId, NEWID());

    MERGE [Content].[ContentAuthor] AS target
    USING (SELECT @AuthorId AS AuthorId) AS source
       ON target.AuthorId = source.AuthorId
    WHEN MATCHED THEN UPDATE SET
        UserId = @UserId, DisplayName = @DisplayName,
        Credentials = @Credentials, Bio = @Bio
    WHEN NOT MATCHED THEN INSERT
        (AuthorId, UserId, DisplayName, Credentials, Bio)
        VALUES (@AuthorId, @UserId, @DisplayName, @Credentials, @Bio);

    /*  Named to match ContentAuthorDto. The table has eight columns and the
        record has six; Dapper cannot materialise a positional record from a
        wider result set, so SELECT * made this endpoint fail on every call. */
    SELECT AuthorId, UserId, DisplayName, Credentials, Bio, IsActive
    FROM [Content].[ContentAuthor] WHERE AuthorId = @AuthorId;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Media_Save
-- ---------------------------------------------------------------------------
/*
    Records a blob that already exists in storage.

    The API uploads to Blob Storage first and registers the key here second. A
    row that pointed at a blob which failed to upload would render as a broken
    image, which is worse than a failed upload the editor can retry.
*/
IF OBJECT_ID('Content.usp_Media_Save') IS NOT NULL
    DROP PROCEDURE [Content].[usp_Media_Save];
GO
CREATE PROCEDURE [Content].[usp_Media_Save]
    @MediaId     UNIQUEIDENTIFIER = NULL,
    @FileName    NVARCHAR(300),
    @ContentType NVARCHAR(100),
    @SizeBytes   BIGINT,
    @StorageKey  NVARCHAR(500),
    @Width       INT = NULL,
    @Height      INT = NULL,
    @AltText     NVARCHAR(300) = NULL,
    @ActorUserId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET @MediaId = ISNULL(@MediaId, NEWID());

    MERGE [Content].[Media] AS target
    USING (SELECT @MediaId AS MediaId) AS source
       ON target.MediaId = source.MediaId
    WHEN MATCHED THEN UPDATE SET
        [FileName] = @FileName, ContentType = @ContentType,
        SizeBytes = @SizeBytes, StorageKey = @StorageKey,
        Width = @Width, Height = @Height, AltText = @AltText
    WHEN NOT MATCHED THEN INSERT
        (MediaId, [FileName], ContentType, SizeBytes, StorageKey,
         Width, Height, AltText, UploadedBy)
        VALUES (@MediaId, @FileName, @ContentType, @SizeBytes, @StorageKey,
                @Width, @Height, @AltText, @ActorUserId);

    INSERT INTO [Audit].[AuditLog]
        (ActorUserId, ActorKind, [Action], EntityType, EntityId)
    VALUES
        (@ActorUserId, 'admin', 'Media.Save', 'Media',
         CONVERT(NVARCHAR(50), @MediaId));

    /*  Named to match MediaDto — same reason as usp_Content_SaveAuthor. */
    SELECT MediaId, FileName, ContentType, SizeBytes, StorageKey,
           Width, Height, AltText, CreatedOn
    FROM [Content].[Media] WHERE MediaId = @MediaId;
END
GO
