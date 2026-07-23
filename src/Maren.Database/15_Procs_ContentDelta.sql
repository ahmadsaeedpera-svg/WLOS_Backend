/*  15_Procs_ContentDelta.sql
    ---------------------------------------------------------------------------
    Delta content sync for the mobile client.

    ## Why a delta, not a full download

    A client that re-downloads the whole library on every launch wastes the
    user's data and battery and does not scale to millions of devices. This
    returns only what changed since the client last synced, plus a token to
    pass next time.

    ## Why the cursor is a ROWVERSION, not a timestamp

    The obvious design uses "changed since <timestamp>". It has a race that only
    shows up under load: two edits, or an edit and a sync, landing in the same
    millisecond. datetime2(3) cannot tell them apart, so a "> lastSyncTime"
    query silently drops the update whose ModifiedOn equals the token — a lost
    update on a phone, undetectable until the next unrelated edit happens to
    bump the row again.

    ROWVERSION is a database-wide monotonic counter. Every update to any row
    gets a strictly greater value than every prior update, with no ties, ever.
    Using it as the cursor removes the race at the root rather than papering
    over it with an overlap window.

    ## The high-water mark, and the one gap it leaves

    @token is @@DBTS — the highest rowversion assigned in the database. The
    query returns RowVersion > @since AND RowVersion <= @token, and the client
    stores @token to send back next time.

    There is one theoretical gap, worth stating plainly rather than hiding. If
    transaction A claims a rowversion slot, transaction B claims a higher one
    and commits first, and a client syncs in between, the client can advance its
    cursor past A's slot; when A commits with its lower rowversion it falls
    below @since and that one change is never delivered incrementally.

    MIN_ACTIVE_ROWVERSION() would close this by holding the cursor below any
    open transaction. It is not used here for two reasons. First, this is
    content delivery, not a ledger: writes are short single-procedure
    transactions at editorial pace, so overlapping content commits are rare.
    Second, the client performs a periodic FULL resync (since = NULL), which
    reconciles any row the incremental path could have missed — so the gap
    self-heals within one resync interval rather than persisting.

    The tradeoff is deliberate: @@DBTS is simple, observable and stable;
    MIN_ACTIVE_ROWVERSION() is sensitive to unrelated open transactions in ways
    that buy correctness this system recovers by other means.

    ## The half everyone forgets: tombstones

    A "changed" query returns items created or edited. It cannot return items
    that were REMOVED, because they no longer match "published". Unifying both
    under the rowversion cursor solves this cleanly: an unpublish or delete
    bumps the item's RowVersion, so it falls into the same window and is emitted
    as a tombstone — an instruction to the client to delete it. Without this a
    device that cached a retired article shows it forever, and a rollback never
    reaches the phone.

    ## Token wire format

    A rowversion is BINARY(8). It crosses the wire as a 0x-prefixed hex string
    the client treats as opaque — it never parses or compares it, only echoes it
    back. CONVERT(..., 1) is the hex style in both directions.
*/
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('Content.usp_Content_GetDelta') IS NOT NULL
    DROP PROCEDURE [Content].[usp_Content_GetDelta];
GO
CREATE PROCEDURE [Content].[usp_Content_GetDelta]
    @SinceToken     VARCHAR(20) = NULL,    -- NULL = full initial sync
    @ContentType    VARCHAR(40) = NULL,
    @LanguageCode   CHAR(5) = 'en-GB',
    @CountryIso     CHAR(2) = NULL,
    @AppVersionCode INT = NULL,
    @Week           TINYINT = NULL,
    @Season         VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    /*  Highest rowversion assigned so far. Committed rows have RowVersion <=
        @@DBTS; the client stores it and asks for `> @since` next time. See the
        header for the one gap this leaves and how the periodic full resync
        closes it. */
    DECLARE @token BINARY(8) = @@DBTS;
    DECLARE @since BINARY(8) =
        CASE WHEN @SinceToken IS NULL THEN NULL
             ELSE CONVERT(BINARY(8), @SinceToken, 1) END;

    -- Result set 1: the new token, as a hex string ------------------------
    SELECT CONVERT(VARCHAR(20), @token, 1) AS SyncToken;

    -- Result set 2: upserts ------------------------------------------------
    /*  Text comes from the PUBLISHED VERSION SNAPSHOT, never the live
        translation table — an editor mid-edit must not leak unreviewed words
        to a device. Same rule as usp_Content_GetForClient. */
    SELECT
        i.ContentItemId, i.ContentType, i.[Key], i.Weight, i.SourceCitation,
        i.FromWeek, i.ToWeek, i.Season, i.ModifiedOn, i.VersionNumber,
        c.[Key] AS CategoryKey,
        COALESCE(t.Title, fb.Title) AS Title,
        COALESCE(t.Body, fb.Body) AS Body,
        COALESCE(t.Summary, fb.Summary) AS Summary,
        COALESCE(t.MetadataJson, fb.MetadataJson) AS MetadataJson,
        CAST(CASE WHEN t.LanguageCode IS NULL THEN 1 ELSE 0 END AS BIT) AS IsFallback
    FROM [Content].[ContentItem] i
    LEFT JOIN [Content].[Category] c ON c.CategoryId = i.CategoryId
    JOIN [Content].[ContentVersion] pv
           ON pv.ContentVersionId = i.PublishedVersionId
    OUTER APPLY (
        SELECT TOP 1 j.Title, j.Body, j.Summary, j.MetadataJson, j.LanguageCode
        FROM OPENJSON(pv.SnapshotJson, '$.Localizations')
        WITH (
            LanguageCode CHAR(5)        '$.LanguageCode',
            Title        NVARCHAR(400)  '$.Title',
            Body         NVARCHAR(MAX)  '$.Body',
            Summary      NVARCHAR(1000) '$.Summary',
            MetadataJson NVARCHAR(MAX)  '$.MetadataJson' AS JSON
        ) j
        WHERE j.LanguageCode = @LanguageCode
    ) t
    OUTER APPLY (
        SELECT TOP 1 j.Title, j.Body, j.Summary, j.MetadataJson
        FROM OPENJSON(pv.SnapshotJson, '$.Localizations')
        WITH (
            LanguageCode CHAR(5)        '$.LanguageCode',
            Title        NVARCHAR(400)  '$.Title',
            Body         NVARCHAR(MAX)  '$.Body',
            Summary      NVARCHAR(1000) '$.Summary',
            MetadataJson NVARCHAR(MAX)  '$.MetadataJson' AS JSON
        ) j
        WHERE j.LanguageCode = 'en-GB'
    ) fb
    WHERE i.IsDeleted = 0
      AND i.Status = 'published'
      AND i.PublishedVersionId IS NOT NULL
      AND i.RowVersion <= @token
      AND (@since IS NULL OR i.RowVersion > @since)
      AND (i.PublishFromUtc IS NULL OR i.PublishFromUtc <= SYSUTCDATETIME())
      AND (i.PublishUntilUtc IS NULL OR i.PublishUntilUtc > SYSUTCDATETIME())
      AND (@ContentType IS NULL OR i.ContentType = @ContentType)
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

    -- Result set 3: tombstones ---------------------------------------------
    /*  Always emitted, empty on a first sync. A conditional result set is a
        Dapper footgun — the reader would map columns to the wrong set
        depending on a parameter. Empty rather than absent, guarded by @since. */
    SELECT
        i.ContentItemId,
        i.[Key],
        i.ContentType,
        i.ModifiedOn
    FROM [Content].[ContentItem] i
    WHERE @since IS NOT NULL
      AND i.RowVersion > @since
      AND i.RowVersion <= @token
      AND (@ContentType IS NULL OR i.ContentType = @ContentType)
      AND (i.IsDeleted = 1
           OR i.Status <> 'published'
           OR i.PublishedVersionId IS NULL
           OR (i.PublishUntilUtc IS NOT NULL AND i.PublishUntilUtc <= SYSUTCDATETIME()))
    ORDER BY i.ContentItemId;
END
GO

PRINT 'Content delta procedure applied (rowversion cursor).';
GO
