/*  79_RecordSync.sql

    What a second device needs to catch up, and the one thing it cannot work
    out for itself.

    The problem this exists for
    ---------------------------
    Multi-device already works for reading: any phone that knows her password
    derives KEK_password, opens the PASSWORD wrapper, and holds the same data
    key. Nothing here changes that.

    What does not work is **catching up**. `usp_Record_GetPage` is offset
    paging over a set that is being written to, which skips and duplicates
    rows, and every sync is a full download of every envelope she owns. The
    obvious fix is a "what changed since X" call — and that fix is unsafe
    against the current schema, for one reason:

        Device A deletes an entry.
        The row is gone.
        Device B asks what changed since its cursor.
        Nothing mentions the entry.
        Device B keeps showing it, forever.

    **A delta sync without tombstones silently resurrects deleted entries.**
    For a journal that is the worst failure available: she deleted something
    deliberately, was told it was gone for good, and finds it on her other
    phone. So the deletion semantics have to support sync before the sync
    exists, which is why this script comes before any client cache.

    Why ROWVERSION and not a timestamp
    ----------------------------------
    `ModifiedOn` is DATETIME2(3) and cannot be a sync cursor:

      * two records written in the same millisecond tie, and a cursor of
        "greater than T" drops one of them permanently;
      * a clock adjustment moves rows backwards past a cursor that has already
        passed, and they are never seen again.

    Both failures are silent and lose her writing. `ROWVERSION` is a
    database-wide monotonically increasing value the engine maintains on every
    insert and update. **No application code can get it wrong**, which is the
    property that matters — this is the mechanism that decides whether an
    entry reaches her other phone.

    It is not a time and must never be shown as one. It orders changes; it
    says nothing about when.

    What a tombstone holds, and what it does not
    --------------------------------------------
    A record id, a kind, and when it was deleted. **No ciphertext, no
    plaintext, nothing derived from content** — there is nothing here to
    decrypt and nothing to infer from.

    It is a deliberate, named exception to "deletion is deletion", and it is
    an exception that serves her: without it her deletion does not reach her
    other devices, which is a worse outcome than the platform remembering that
    a record id once existed. `usp_User_DeleteAccount` erases these with
    everything else, so it does not outlive the account.

    They are kept for the life of the account rather than pruned. Pruning
    would mean knowing every device has caught up, and this platform has no
    device registry to know it with — inventing a retention window would be
    guessing with her deletions. The cost is bounded by her own behaviour: a
    tombstone is about forty bytes, so ten thousand deletions is under half a
    megabyte.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- A sync cursor on Crypto.Record
-- ---------------------------------------------------------------------------
/*  Added rather than created with the table, because the table shipped before
    there was a second device to catch up. ALTER populates every existing row,
    so records written before this script are orderable too. */
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE name = 'RowVersion'
                 AND object_id = OBJECT_ID('Crypto.Record'))
    ALTER TABLE [Crypto].[Record] ADD [RowVersion] ROWVERSION NOT NULL;
GO

/*  The sync read: one account, everything past a cursor, in cursor order.
    Without this the delta is a scan of every record she owns, which is the
    thing the delta exists to avoid. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Record_User_RowVersion'
                 AND object_id = OBJECT_ID('Crypto.Record'))
    CREATE INDEX IX_Record_User_RowVersion
        ON [Crypto].[Record](UserId, [RowVersion])
        INCLUDE (RecordKind);
GO

-- ---------------------------------------------------------------------------
-- Crypto.RecordTombstone
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Crypto.RecordTombstone') IS NULL
BEGIN
    CREATE TABLE [Crypto].[RecordTombstone] (
        RecordId    UNIQUEIDENTIFIER NOT NULL,
        UserId      UNIQUEIDENTIFIER NOT NULL,

        /*  Carried so a client syncing one kind is not told about another.
            It is the same routing value the record row held and reveals
            nothing the record did not -- but it is the only field here that
            is about the thing rather than about the deletion, so it is worth
            being deliberate that it stops at "kind". */
        RecordKind  VARCHAR(32)      NOT NULL,

        DeletedOn   DATETIME2(3)     NOT NULL
            CONSTRAINT DF_RecordTombstone_DeletedOn DEFAULT SYSUTCDATETIME(),

        [RowVersion] ROWVERSION      NOT NULL,

        CONSTRAINT PK_RecordTombstone PRIMARY KEY CLUSTERED (RecordId),
        CONSTRAINT FK_RecordTombstone_User FOREIGN KEY (UserId)
            REFERENCES [Identity].[User](UserId)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_RecordTombstone_User_RowVersion'
                 AND object_id = OBJECT_ID('Crypto.RecordTombstone'))
    CREATE INDEX IX_RecordTombstone_User_RowVersion
        ON [Crypto].[RecordTombstone](UserId, [RowVersion])
        INCLUDE (RecordKind);
GO

-- ---------------------------------------------------------------------------
-- Outside the audit contract, with the reason recorded in the database
-- ---------------------------------------------------------------------------
/*  Declared here rather than in 08_AuditContract.sql because the table does
    not exist until this script, and because an exemption is easier to judge
    next to the thing it exempts than in a list somewhere else.

    The reason is not convenience. `IsDeleted` on a tombstone would mean a
    deletion could itself be marked deleted -- and a soft-deleted tombstone is
    an entry that comes back on her other phone. The contract's own soft
    delete is the exact failure this table exists to prevent. */
MERGE dbo.AuditContractExemption AS target
USING (VALUES
    ('Crypto', 'RecordTombstone',
     N'Records that a record was deleted, so the deletion reaches her other '
     + N'devices. Soft-delete columns would allow a deletion to be marked '
     + N'deleted, which is exactly the resurrection this table prevents. It '
     + N'holds a record id, a kind and a time -- no ciphertext and nothing '
     + N'derived from content -- and usp_User_DeleteAccount erases it with '
     + N'the account.')
) AS source (SchemaName, TableName, Reason)
    ON target.SchemaName = source.SchemaName
   AND target.TableName = source.TableName
WHEN NOT MATCHED THEN
    INSERT (SchemaName, TableName, Reason)
    VALUES (source.SchemaName, source.TableName, source.Reason);
GO
