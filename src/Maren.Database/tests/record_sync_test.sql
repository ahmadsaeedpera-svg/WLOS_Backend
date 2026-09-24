/*  record_sync_test.sql

    What a second device needs to catch up, and the ways it silently fails.

    Every assertion here is about one question: **does a change on one phone
    reach the other one?** The failures this guards against are all quiet —
    nothing throws, nothing logs, an entry is simply present on one device and
    absent on another, or deleted on one and alive on the other.

    The worst of them is resurrection. She deletes an entry deliberately, is
    told it is gone for good, and finds it on her other phone because a delta
    sync had nothing to tell it. Assertions 5 to 8 exist for that alone.

    Run:
      sqlcmd -S "$SERVER" -I -d "$DB" -i src/Maren.Database/tests/record_sync_test.sql

    Expect: TOTAL: 14  FAILED: 0

    Creates and removes its own data. Re-runnable and order-independent.
*/

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

DECLARE @failed int = 0;

DECLARE @user  uniqueidentifier = '0C0DE000-0000-4000-5C00-000000000001';
DECLARE @gen   uniqueidentifier = '0C0DE000-0000-4000-5C00-0000000000A1';
DECLARE @recA  uniqueidentifier = '0C0DE000-0000-4000-5C00-00000000000A';
DECLARE @recB  uniqueidentifier = '0C0DE000-0000-4000-5C00-00000000000B';
DECLARE @recC  uniqueidentifier = '0C0DE000-0000-4000-5C00-00000000000C';

DECLARE @env varbinary(max) = CAST(REPLICATE(CAST(0x5A AS binary(1)), 64) AS varbinary(max));
DECLARE @profile int = (SELECT TOP 1 KdfProfileId FROM [Crypto].[KdfProfile] ORDER BY KdfProfileId);

PRINT '=== Record sync: does a change reach her other phone? ===';
PRINT '';

-- ---------------------------------------------------------------------------
-- Clean up on the way in.
-- ---------------------------------------------------------------------------
DELETE FROM [Crypto].[RecordTombstone] WHERE UserId = @user;
DELETE FROM [Crypto].[Record]          WHERE UserId = @user;
DELETE FROM [Crypto].[Wrapper]         WHERE GenerationId = @gen;
DELETE FROM [Crypto].[Generation]      WHERE UserId = @user;
DELETE FROM [Identity].[UserCredential] WHERE UserId = @user;
DELETE FROM [Identity].[User]          WHERE UserId = @user;

INSERT INTO [Identity].[User] (UserId, Email, NormalisedEmail)
VALUES (@user, N'sync_test@test.invalid', N'SYNC_TEST@TEST.INVALID');

INSERT INTO [Crypto].[Generation] (GenerationId, UserId, GenerationNumber, [State])
VALUES (@gen, @user, 1, 'ACTIVE');

DECLARE @save TABLE (Succeeded bit, FailureCode varchar(64), [Version] int);
DECLARE @del  TABLE (Succeeded bit, FailureCode varchar(64));

-- ---------------------------------------------------------------------------
-- The cursor exists and is not a clock
-- ---------------------------------------------------------------------------

/*  A timestamp cannot be a sync cursor. DATETIME2(3) ties within a
    millisecond, so "everything after T" drops one of a tied pair for good,
    and a clock adjustment moves rows back past a cursor that has already
    passed them. Both losses are silent and permanent. ROWVERSION is
    maintained by the engine and cannot tie. */
IF EXISTS (SELECT 1 FROM sys.columns c
           JOIN sys.types t ON t.user_type_id = c.user_type_id
           WHERE c.object_id = OBJECT_ID('Crypto.Record')
             AND c.name = 'RowVersion' AND t.name = 'timestamp')
    PRINT '  1 records carry an engine-maintained cursor, not a time        PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT '  1 records carry an engine-maintained cursor, not a time        FAIL';
END

DELETE FROM @save;
INSERT @save EXEC [Crypto].[usp_Record_Save]
    @UserId = @user, @RecordId = @recA, @RecordKind = 'journal.entry',
    @SchemaVersion = 1, @Version = 1, @Envelope = @env;

DELETE FROM @save;
INSERT @save EXEC [Crypto].[usp_Record_Save]
    @UserId = @user, @RecordId = @recB, @RecordKind = 'journal.entry',
    @SchemaVersion = 1, @Version = 1, @Envelope = @env;

/*  Two records written in sequence must be orderable. If the cursor could tie
    them, a page boundary between them would drop one. */
IF (SELECT COUNT(DISTINCT CAST([RowVersion] AS binary(8)))
      FROM [Crypto].[Record] WHERE UserId = @user) = 2
    PRINT '  2 two records never share a cursor value                       PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT '  2 two records never share a cursor value                       FAIL';
END

/*  A write moves the record forward in the stream. If an update left the
    cursor alone, an edit made on one phone would never reach the other. */
DECLARE @beforeUpdate binary(8) =
    (SELECT CAST([RowVersion] AS binary(8)) FROM [Crypto].[Record] WHERE RecordId = @recA);

DELETE FROM @save;
INSERT @save EXEC [Crypto].[usp_Record_Save]
    @UserId = @user, @RecordId = @recA, @RecordKind = 'journal.entry',
    @SchemaVersion = 1, @Version = 2, @Envelope = @env;

IF (SELECT CAST([RowVersion] AS binary(8)) FROM [Crypto].[Record] WHERE RecordId = @recA)
   > @beforeUpdate
    PRINT '  3 an edit moves the record forward in the stream               PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT '  3 an edit moves the record forward in the stream               FAIL';
END

-- ---------------------------------------------------------------------------
-- A first sync, and catching up
-- ---------------------------------------------------------------------------

/*  The shape of one ordered stream: writes and deletions together, each
    row carrying the cursor to resume from. A deletion is a row with an id and
    no envelope. */
DECLARE @changes TABLE ([Cursor] binary(8), RecordId uniqueidentifier,
                        IsDeleted bit, RecordKind varchar(32),
                        SchemaVersion int, [Version] int,
                        Envelope varbinary(max), GenerationNumber int,
                        CreatedOn datetime2(3), ChangedOn datetime2(3));

/*  A first sync passes no cursor and is the same code path as catching up.
    A separate bootstrap is a second thing to get wrong. */
DELETE FROM @changes;
INSERT @changes EXEC [Crypto].[usp_Record_GetChanges]
    @UserId = @user, @RecordKind = 'journal.entry';

IF (SELECT COUNT(*) FROM @changes) = 2
    PRINT '  4 a first sync with no cursor returns everything               PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT '  4 a first sync with no cursor returns everything               FAIL';
END

-- ---------------------------------------------------------------------------
-- Deletion, and the resurrection it would otherwise cause
-- ---------------------------------------------------------------------------

DELETE FROM @del;
INSERT @del EXEC [Crypto].[usp_Record_Delete] @UserId = @user, @RecordId = @recB;

/*  The envelope is gone. This is still deletion, not a soft delete: a row
    that still held ciphertext would be a row a future bug could serve. */
IF NOT EXISTS (SELECT 1 FROM [Crypto].[Record] WHERE RecordId = @recB)
   AND EXISTS (SELECT 1 FROM @del WHERE Succeeded = 1)
    PRINT '  5 deleting a record removes the ciphertext                     PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT '  5 deleting a record removes the ciphertext                     FAIL';
END

/*  And leaves something for her other phone to find. Without this the entry
    she deliberately deleted stays on that device forever -- the worst failure
    available to a journal, and completely silent. */
IF EXISTS (SELECT 1 FROM [Crypto].[RecordTombstone]
            WHERE RecordId = @recB AND UserId = @user)
    PRINT '  6 the deletion is discoverable by a device catching up         PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT '  6 the deletion is discoverable by a device catching up         FAIL';
END

/*  And holds nothing but an id, a kind and a time. A tombstone carrying
    ciphertext would put the thing she deleted back on the server. */
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
     WHERE object_id = OBJECT_ID('Crypto.RecordTombstone')
       AND name NOT IN ('RecordId', 'UserId', 'RecordKind', 'DeletedOn', 'RowVersion'))
    PRINT '  7 a tombstone holds no content and nothing derived from it     PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT '  7 a tombstone holds no content and nothing derived from it     FAIL';
END

/*  The one that proves the point. A device whose cursor predates the deletion
    must be *told* about it; the whole mechanism exists for this single row,
    and without it she deletes an entry on one phone and it lives on the
    other. */
DELETE FROM @changes;
INSERT @changes EXEC [Crypto].[usp_Record_GetChanges]
    @UserId = @user, @RecordKind = 'journal.entry', @Since = @beforeUpdate;

IF EXISTS (SELECT 1 FROM @changes WHERE RecordId = @recB AND IsDeleted = 1)
    PRINT '  8 a catching-up device is told the entry was deleted           PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT '  8 a catching-up device is told the entry was deleted           FAIL';
END

/*  And is told it without being handed ciphertext for something that no
    longer exists. A deletion is an id and nothing else. */
IF EXISTS (SELECT 1 FROM @changes
            WHERE RecordId = @recB AND IsDeleted = 1 AND Envelope IS NULL)
    PRINT '  9 a deletion carries no envelope, because there is none        PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT '  9 a deletion carries no envelope, because there is none        FAIL';
END

-- ---------------------------------------------------------------------------
-- Paging across both streams
-- ---------------------------------------------------------------------------

DELETE FROM @save;
INSERT @save EXEC [Crypto].[usp_Record_Save]
    @UserId = @user, @RecordId = @recC, @RecordKind = 'journal.entry',
    @SchemaVersion = 1, @Version = 1, @Envelope = @env;

/*  Writes and deletions are paged as one ordered stream. Paged separately,
    each page would carry its own highest cursor and a caller would have no
    safe value to store -- advance past the lower one and everything between
    is skipped for good. */
DECLARE @small TABLE ([Cursor] binary(8), RecordId uniqueidentifier,
                      IsDeleted bit, RecordKind varchar(32),
                      SchemaVersion int, [Version] int,
                      Envelope varbinary(max), GenerationNumber int,
                      CreatedOn datetime2(3), ChangedOn datetime2(3));

INSERT @small EXEC [Crypto].[usp_Record_GetChanges]
    @UserId = @user, @RecordKind = 'journal.entry', @Take = 1;

IF (SELECT COUNT(*) FROM @small) = 1
   AND (SELECT COUNT(*) FROM @small WHERE [Cursor] IS NOT NULL) = 1
    PRINT ' 10 a page is bounded across writes and deletions together       PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 10 a page is bounded across writes and deletions together       FAIL';
END

/*  An empty answer must hand back the cursor it was given. Returning null
    would send a caught-up device back to the beginning of her journal on
    every poll. */
DECLARE @head binary(8) =
    (SELECT MAX(CAST([RowVersion] AS binary(8))) FROM [Crypto].[Record] WHERE UserId = @user);
DECLARE @tail TABLE ([Cursor] binary(8), RecordId uniqueidentifier,
                     IsDeleted bit, RecordKind varchar(32),
                     SchemaVersion int, [Version] int,
                     Envelope varbinary(max), GenerationNumber int,
                     CreatedOn datetime2(3), ChangedOn datetime2(3));

INSERT @tail EXEC [Crypto].[usp_Record_GetChanges]
    @UserId = @user, @RecordKind = 'journal.entry', @Since = @head;

IF NOT EXISTS (SELECT 1 FROM @tail)
    PRINT ' 11 a caught-up device is told there is nothing new              PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 11 a caught-up device is told there is nothing new              FAIL';
END

-- ---------------------------------------------------------------------------
-- Ownership, re-creation, and erasure
-- ---------------------------------------------------------------------------

/*  Scoped by user like every other read here. A sync that leaked across
    accounts would hand one woman another's ciphertext. */
DECLARE @stranger uniqueidentifier = '0C0DE000-0000-4000-5C00-00000000000F';
DECLARE @other TABLE ([Cursor] binary(8), RecordId uniqueidentifier,
                      IsDeleted bit, RecordKind varchar(32),
                      SchemaVersion int, [Version] int,
                      Envelope varbinary(max), GenerationNumber int,
                      CreatedOn datetime2(3), ChangedOn datetime2(3));

INSERT @other EXEC [Crypto].[usp_Record_GetChanges] @UserId = @stranger;

IF NOT EXISTS (SELECT 1 FROM @other)
    PRINT ' 12 the sync stream is scoped to one account                     PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 12 the sync stream is scoped to one account                     FAIL';
END

/*  Writing a deleted id again clears its tombstone, so the stream stops
    carrying a deletion and a creation for the same record forever. */
DELETE FROM @save;
INSERT @save EXEC [Crypto].[usp_Record_Save]
    @UserId = @user, @RecordId = @recB, @RecordKind = 'journal.entry',
    @SchemaVersion = 1, @Version = 1, @Envelope = @env;

IF NOT EXISTS (SELECT 1 FROM [Crypto].[RecordTombstone] WHERE RecordId = @recB)
   AND EXISTS (SELECT 1 FROM [Crypto].[Record] WHERE RecordId = @recB)
    PRINT ' 13 writing a deleted id again retires its tombstone             PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 13 writing a deleted id again retires its tombstone             FAIL';
END

/*  And a record of what she once deleted must not outlive the account it
    belonged to. Deletion means deletion applies to the tombstones too. */
DELETE FROM @del;
INSERT @del EXEC [Crypto].[usp_Record_Delete] @UserId = @user, @RecordId = @recC;

DECLARE @accountDelete TABLE (Succeeded bit, FailureCode varchar(64));
INSERT @accountDelete EXEC [Identity].[usp_User_DeleteAccount] @UserId = @user;

IF NOT EXISTS (SELECT 1 FROM [Crypto].[RecordTombstone] WHERE UserId = @user)
   AND NOT EXISTS (SELECT 1 FROM [Crypto].[Record] WHERE UserId = @user)
    PRINT ' 14 closing the account erases the tombstones too                PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 14 closing the account erases the tombstones too                FAIL';
END

-- ---------------------------------------------------------------------------
-- Clean up on the way out.
-- ---------------------------------------------------------------------------
DELETE FROM [Crypto].[RecordTombstone] WHERE UserId = @user;
DELETE FROM [Crypto].[Record]          WHERE UserId = @user;
DELETE FROM [Crypto].[Wrapper]         WHERE GenerationId = @gen;
DELETE FROM [Crypto].[Generation]      WHERE UserId = @user;
DELETE FROM [Identity].[UserCredential] WHERE UserId = @user;
DELETE FROM [Audit].[AuditLog]         WHERE ActorUserId = @user;
DELETE FROM [Identity].[User]          WHERE UserId = @user;

PRINT '';
PRINT '---------------------------------------------';
PRINT 'TOTAL: 14  FAILED: ' + CAST(@failed AS varchar(10));
PRINT '---------------------------------------------';

IF @failed > 0
    THROW 51000, 'Record sync assertions failed.', 1;
GO
