/*  80_Procs_RecordSync.sql

    The catch-up read, against the tables in 79_RecordSync.sql.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- Crypto.usp_Record_GetChanges
-- ---------------------------------------------------------------------------
/*
    Everything that happened to her records after a cursor, in the order it
    happened: writes and deletions in one stream.

    One result set, and why
    -----------------------
    The obvious shape is two — changed records, then tombstones — and it is
    wrong twice over.

    The first way is a correctness trap. Two sets means two highest cursors
    and a caller with no safe value to store: advance to the higher and
    everything between it and the lower is skipped forever; advance to the
    lower and the caller re-reads rows it already applied. So both are ranked
    into a single stream ordered by RowVersion and one page is taken across
    the two.

    The second way is ordering. A record that was written, deleted, and
    written again must be applied in that sequence; handed two lists, a client
    has to merge them correctly and will eventually merge them wrong. **A
    deletion is just a change with no envelope**, so it travels in the same
    list and the client applies rows in the order it receives them.

    (The database made this argument first: a procedure returning three
    differently shaped result sets cannot be consumed by `INSERT ... EXEC` at
    all, which is how the assertion suite reads it. That was a hint about the
    shape, not an obstacle to work around.)

    Ordering is by RowVersion and never by time. See the header of
    79_RecordSync.sql: a timestamp cursor drops entries that tie within a
    millisecond and loses entries permanently when a clock moves backwards.
    Both failures are silent, and both lose her writing.

    The cursor travels per row
    --------------------------
    Not once per page. A client that is interrupted halfway through applying a
    page resumes from the last row it actually committed rather than redoing
    the page or, worse, skipping the rest of it.

    There is no `HasMore`. A caller asks again until a page comes back empty,
    which costs one round trip and removes the whole class of bugs that live
    in the difference between "the page was full" and "there is more".

    A first sync passes no cursor and receives everything — the same code path
    as catching up, so there is no separate bootstrap to get wrong.

    Scoped by @UserId like every other read here. There is no parameter that
    could name another account's records, and the generation is resolved by
    join rather than accepted from the caller.
*/
IF OBJECT_ID('Crypto.usp_Record_GetChanges') IS NOT NULL
    DROP PROCEDURE [Crypto].[usp_Record_GetChanges];
GO
CREATE PROCEDURE [Crypto].[usp_Record_GetChanges]
    @UserId     UNIQUEIDENTIFIER,
    @RecordKind VARCHAR(32)   = NULL,
    /*  Binary, not a date. Null means "everything", which is a first sync. */
    @Since      VARBINARY(8)  = NULL,
    @Take       INT           = 200
AS
BEGIN
    SET NOCOUNT ON;

    /*  Bounded here as well as in the validator. An unbounded page over a
        table of encrypted blobs is a denial-of-service vector and the easiest
        way to pull an entire journal across a wire by accident. */
    IF @Take IS NULL OR @Take <= 0 OR @Take > 500 SET @Take = 200;

    DECLARE @page TABLE (
        Cursor8   BINARY(8)        NOT NULL PRIMARY KEY,
        RecordId  UNIQUEIDENTIFIER NOT NULL,
        IsDeleted BIT              NOT NULL
    );

    INSERT INTO @page (Cursor8, RecordId, IsDeleted)
    SELECT TOP (@Take) s.rv, s.RecordId, s.IsDeleted
    FROM (
        SELECT CAST(r.[RowVersion] AS BINARY(8)) AS rv, r.RecordId,
               CAST(0 AS BIT) AS IsDeleted
        FROM [Crypto].[Record] r
        WHERE r.UserId = @UserId
          AND (@RecordKind IS NULL OR r.RecordKind = @RecordKind)
          AND (@Since IS NULL OR r.[RowVersion] > @Since)

        UNION ALL

        SELECT CAST(t.[RowVersion] AS BINARY(8)), t.RecordId,
               CAST(1 AS BIT)
        FROM [Crypto].[RecordTombstone] t
        WHERE t.UserId = @UserId
          AND (@RecordKind IS NULL OR t.RecordKind = @RecordKind)
          AND (@Since IS NULL OR t.[RowVersion] > @Since)
    ) AS s
    ORDER BY s.rv;

    /*  Deletions carry nulls where the envelope would be. That is the shape
        of the fact rather than missing data: there is nothing left to send
        for a record that is gone, and a row with an id and no ciphertext is
        exactly what "this was deleted" looks like. */
    SELECT
        p.Cursor8               AS [Cursor],
        p.RecordId,
        p.IsDeleted,
        COALESCE(r.RecordKind, t.RecordKind) AS RecordKind,
        r.SchemaVersion,
        r.[Version],
        r.Envelope,
        g.GenerationNumber,
        r.CreatedOn,
        COALESCE(r.ModifiedOn, t.DeletedOn)  AS ChangedOn
    FROM @page p
    LEFT JOIN [Crypto].[Record] r          ON r.RecordId = p.RecordId
                                          AND p.IsDeleted = 0
    LEFT JOIN [Crypto].[Generation] g      ON g.GenerationId = r.GenerationId
    LEFT JOIN [Crypto].[RecordTombstone] t ON t.RecordId = p.RecordId
                                          AND p.IsDeleted = 1
    ORDER BY p.Cursor8;
END
GO
