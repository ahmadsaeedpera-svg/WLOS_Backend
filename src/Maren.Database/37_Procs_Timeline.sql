/*  37_Procs_Timeline.sql

    Recording, syncing and reading the timeline.

    The Health schema has nine tables and zero procedures, which under this
    repository's procedures-only rule means it is unreachable - deployed,
    indexed, audit-compliant and impossible to call. This file exists so the
    timeline does not repeat that: the store ships with the procedures that
    make it usable in the same change.

    Aggregation lives here too, in usp_Timeline_Aggregate. The score, insight
    and recommendation engines all need the same question answered - how much
    of this, over that window - and if each computes it in C# they will
    disagree within a release. One procedure, one definition of a daily total.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- usp_Timeline_Record
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Timeline.usp_Timeline_Record') IS NOT NULL
    DROP PROCEDURE [Timeline].[usp_Timeline_Record];
GO
/*  Records one event, or updates it if the client has sent it before.

    An upsert on a client-supplied id rather than an insert, because the app is
    offline-first: a sync that times out after the server committed will be
    retried, and a retry must not produce a second glass of water. Idempotence
    is what makes that safe, and it is cheaper to guarantee here than to detect
    afterwards. */
CREATE PROCEDURE [Timeline].[usp_Timeline_Record]
    @EventId           UNIQUEIDENTIFIER,
    @UserId            UNIQUEIDENTIFIER,
    @EventTypeCode     VARCHAR(40),
    @OccurredUtc       DATETIME2(3),
    @OccurredLocalDate DATE = NULL,
    @Source            VARCHAR(20) = 'manual',
    @ValueNumeric      DECIMAL(18, 4) = NULL,
    @ValueText         NVARCHAR(200) = NULL,
    @Unit              VARCHAR(20) = NULL,
    @MetadataJson      NVARCHAR(2000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [Identity].[User]
                   WHERE UserId = @UserId AND IsDeleted = 0)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'USER_NOT_FOUND' AS FailureCode;
        RETURN;
    END

    DECLARE @kind VARCHAR(12), @defaultUnit VARCHAR(20);
    SELECT @kind = ValueKind, @defaultUnit = DefaultUnit
    FROM [Timeline].[EventType]
    WHERE EventTypeCode = @EventTypeCode AND IsActive = 1;

    IF @kind IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'UNKNOWN_EVENT_TYPE' AS FailureCode;
        RETURN;
    END

    IF @MetadataJson IS NOT NULL AND ISJSON(@MetadataJson) = 0
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'INVALID_JSON' AS FailureCode;
        RETURN;
    END

    /*  A scale is 1 to 5 everywhere it appears. Refused rather than clamped:
        a client sending 9 has a bug, and silently storing 5 hides it while
        corrupting every average computed from that row afterwards. */
    IF @kind = 'scale' AND @ValueNumeric IS NOT NULL
       AND (@ValueNumeric < 1 OR @ValueNumeric > 5)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'VALUE_OUT_OF_RANGE' AS FailureCode;
        RETURN;
    END

    /*  Quantities and durations are never negative. Minus two hundred
        millilitres of water is not a correction, it is a defect. */
    IF @kind IN ('quantity', 'duration') AND @ValueNumeric < 0
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'VALUE_OUT_OF_RANGE' AS FailureCode;
        RETURN;
    END

    /*  Falls back to UTC's date only when the client did not say. A client
        that knows her offset should always send it - see 36_Timeline.sql. */
    IF @OccurredLocalDate IS NULL
        SET @OccurredLocalDate = CAST(@OccurredUtc AS DATE);

    IF @Unit IS NULL SET @Unit = @defaultUnit;

    MERGE [Timeline].[Event] AS target
    USING (SELECT @EventId AS EventId) AS source
        ON target.EventId = source.EventId
    WHEN MATCHED THEN UPDATE SET
        EventTypeCode     = @EventTypeCode,
        OccurredUtc       = @OccurredUtc,
        OccurredLocalDate = @OccurredLocalDate,
        [Source]          = @Source,
        ValueNumeric      = @ValueNumeric,
        ValueText         = @ValueText,
        Unit              = @Unit,
        MetadataJson      = @MetadataJson,
        IsDeleted         = 0,
        ModifiedOn        = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN INSERT
        (EventId, UserId, EventTypeCode, OccurredUtc, OccurredLocalDate,
         [Source], ValueNumeric, ValueText, Unit, MetadataJson)
        VALUES
        (@EventId, @UserId, @EventTypeCode, @OccurredUtc, @OccurredLocalDate,
         @Source, @ValueNumeric, @ValueText, @Unit, @MetadataJson);

    /*  Deliberately not written to Audit.AuditLog. This is the most sensitive
        data in the platform and the audit trail already refuses to copy health
        data - mirroring it would double the exposure and tell an operator
        nothing they could act on. */

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(50)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Timeline_Delete
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Timeline.usp_Timeline_Delete') IS NOT NULL
    DROP PROCEDURE [Timeline].[usp_Timeline_Delete];
GO
/*  Soft delete, so the tombstone can reach her other devices. A hard delete
    would remove the row and leave every other device still showing it. */
CREATE PROCEDURE [Timeline].[usp_Timeline_Delete]
    @EventId UNIQUEIDENTIFIER,
    @UserId  UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /*  Scoped to the owner. Without the UserId predicate, knowing an id would
        be enough to delete somebody else's record. */
    UPDATE [Timeline].[Event]
    SET IsDeleted = 1, ModifiedOn = SYSUTCDATETIME()
    WHERE EventId = @EventId AND UserId = @UserId AND IsDeleted = 0;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(50)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Timeline_GetDelta
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Timeline.usp_Timeline_GetDelta') IS NOT NULL
    DROP PROCEDURE [Timeline].[usp_Timeline_GetDelta];
GO
/*  What changed for this woman since her last sync.

    The same shape as usp_Content_GetDelta: an opaque rowversion token,
    upserts and tombstones in one pass, and a new token to store. That pattern
    is already proven in this schema and there is no reason for health sync to
    invent a second one.

    Bounded by @Take. A first sync on a long history would otherwise return
    everything in one response, which is the failure mode the content delta
    documents and does not yet solve. */
CREATE PROCEDURE [Timeline].[usp_Timeline_GetDelta]
    @UserId    UNIQUEIDENTIFIER,
    @SinceToken BINARY(8) = NULL,
    @Take      INT = 500
AS
BEGIN
    SET NOCOUNT ON;

    IF @Take IS NULL OR @Take < 1 SET @Take = 500;
    IF @Take > 2000 SET @Take = 2000;

    DECLARE @since BINARY(8) = ISNULL(@SinceToken, 0x0000000000000000);

    /*  Upserts and tombstones together, ordered by rowversion, so the client
        applies them in the order they happened and the next token is simply
        the highest it saw. */
    SELECT TOP (@Take)
        e.EventId,
        e.EventTypeCode,
        e.OccurredUtc,
        e.OccurredLocalDate,
        e.[Source],
        e.ValueNumeric,
        e.ValueText,
        e.Unit,
        e.MetadataJson,
        e.IsDeleted,
        e.ModifiedOn,
        e.[RowVersion] AS SyncToken
    FROM [Timeline].[Event] e
    WHERE e.UserId = @UserId
      AND e.[RowVersion] > @since
    ORDER BY e.[RowVersion];
END
GO

-- ---------------------------------------------------------------------------
-- usp_Timeline_Get
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Timeline.usp_Timeline_Get') IS NOT NULL
    DROP PROCEDURE [Timeline].[usp_Timeline_Get];
GO
/*  Her timeline for a window, newest first. What a dashboard or a day view
    reads. */
CREATE PROCEDURE [Timeline].[usp_Timeline_Get]
    @UserId    UNIQUEIDENTIFIER,
    @FromDate  DATE,
    @ToDate    DATE,
    @Category  VARCHAR(30) = NULL,
    @Take      INT = 200
AS
BEGIN
    SET NOCOUNT ON;

    IF @Take IS NULL OR @Take < 1 SET @Take = 200;
    IF @Take > 1000 SET @Take = 1000;

    SELECT TOP (@Take)
        e.EventId,
        e.EventTypeCode,
        t.DisplayName,
        t.Category,
        t.ValueKind,
        e.OccurredUtc,
        e.OccurredLocalDate,
        e.[Source],
        e.ValueNumeric,
        e.ValueText,
        e.Unit
    FROM [Timeline].[Event] e
    JOIN [Timeline].[EventType] t ON t.EventTypeCode = e.EventTypeCode
    WHERE e.UserId = @UserId
      AND e.IsDeleted = 0
      AND e.OccurredLocalDate BETWEEN @FromDate AND @ToDate
      AND (@Category IS NULL OR t.Category = @Category)
    ORDER BY e.OccurredUtc DESC;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Timeline_Aggregate
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Timeline.usp_Timeline_Aggregate') IS NOT NULL
    DROP PROCEDURE [Timeline].[usp_Timeline_Aggregate];
GO
/*  Daily totals for one event type over a window.

    This is the shared foundation of every engine the roadmap describes. A
    hydration score, an insight about Mondays and a recommendation to drink
    more all ask the same question, and they must get the same answer - so the
    definition of "a day's water" lives here once rather than in three places
    that drift apart.

    Cumulative types are summed, others averaged, and which is which comes from
    EventType rather than from the caller guessing. Summing weight would be
    meaningless; averaging water would be wrong. */
CREATE PROCEDURE [Timeline].[usp_Timeline_Aggregate]
    @UserId        UNIQUEIDENTIFIER,
    @EventTypeCode VARCHAR(40),
    @FromDate      DATE,
    @ToDate        DATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @cumulative BIT;
    SELECT @cumulative = IsCumulative
    FROM [Timeline].[EventType] WHERE EventTypeCode = @EventTypeCode;

    IF @cumulative IS NULL
    BEGIN
        /*  Named columns even on the empty path: a client materialising this
            positionally must get the same shape whether or not the type
            exists - see CLAUDE.md 4.2 for what happens otherwise. */
        SELECT CAST(NULL AS DATE) AS LocalDate,
               CAST(NULL AS DECIMAL(18, 4)) AS Total,
               CAST(NULL AS INT) AS EventCount
        WHERE 1 = 0;
        RETURN;
    END

    SELECT
        e.OccurredLocalDate AS LocalDate,
        CASE WHEN @cumulative = 1
             THEN SUM(e.ValueNumeric)
             ELSE AVG(e.ValueNumeric)
        END AS Total,
        COUNT(*) AS EventCount
    FROM [Timeline].[Event] e
    WHERE e.UserId = @UserId
      AND e.EventTypeCode = @EventTypeCode
      AND e.IsDeleted = 0
      AND e.OccurredLocalDate BETWEEN @FromDate AND @ToDate
    GROUP BY e.OccurredLocalDate
    ORDER BY e.OccurredLocalDate DESC;
END
GO

-- ---------------------------------------------------------------------------
-- usp_EventType_List
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Timeline.usp_EventType_List') IS NOT NULL
    DROP PROCEDURE [Timeline].[usp_EventType_List];
GO
/*  What a client may record. Data-driven, so a new event type reaches the app
    without a store release - the constraint this whole platform is organised
    around. */
CREATE PROCEDURE [Timeline].[usp_EventType_List]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT EventTypeCode, DisplayName, Category, ValueKind, DefaultUnit,
           IsCumulative, IsHealthSensitive, SortOrder
    FROM [Timeline].[EventType]
    WHERE IsActive = 1
    ORDER BY SortOrder;
END
GO
