/*  08_AuditContract.sql
    ---------------------------------------------------------------------------
    Applies the platform audit-column contract to every table.

    ## The contract

    Every business table carries:

        CreatedBy    UNIQUEIDENTIFIER NULL      who created the row
        CreatedOn    DATETIME2(3)     NOT NULL  when
        ModifiedBy   UNIQUEIDENTIFIER NULL      who last changed it
        ModifiedOn   DATETIME2(3)     NOT NULL  when
        DeletedBy    UNIQUEIDENTIFIER NULL      who soft-deleted it
        DeletedOn    DATETIME2(3)     NULL      when
        IsDeleted    BIT              NOT NULL  soft-delete flag
        RowVersion   ROWVERSION                 optimistic concurrency

    Before this script: 0 of 43 tables complied. `DeletedBy` existed on none of
    them, so the platform could say a row was deleted but never who deleted it.
    For health data under GDPR that is not an answer a regulator accepts.

    ## Why this is data-driven rather than 43 hand-written blocks

    A cursor over sys.tables cannot forget a table. Forty-three ALTER blocks
    written by hand will drift the moment somebody adds the forty-fourth, and
    the drift is invisible until an auditor asks. The compliance test in
    tests/audit_contract_test.sql fails the build if any table falls out.

    ## Naming

    `CreatedUtc` -> `CreatedOn`, and likewise for Modified and Deleted.

    Only those three rename. The other twenty-three `*Utc` columns —
    `OccurredUtc`, `ExpiresUtc`, `PublishFromUtc`, `ScheduledUtc` and so on —
    are DOMAIN timestamps, not the audit contract, and they keep the suffix
    because stating the timezone in the name is genuinely useful there.

    All platform times are UTC. The contract columns default to
    SYSUTCDATETIME().

    ## Deliberate exclusion

    Audit.AuditLog is excluded. It is append-only by design and no procedure in
    the platform updates or deletes it — a test asserts that. Giving it
    IsDeleted and DeletedBy would advertise a capability that must never exist:
    an audit trail somebody can mark as deleted is not an audit trail.

    Re-runnable. Every step checks before acting.
*/
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- Tables outside the contract, with the reason recorded in the database
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.AuditContractExemption') IS NULL
BEGIN
    CREATE TABLE dbo.AuditContractExemption (
        SchemaName SYSNAME NOT NULL,
        TableName  SYSNAME NOT NULL,
        Reason     NVARCHAR(500) NOT NULL,
        CONSTRAINT PK_AuditContractExemption
            PRIMARY KEY CLUSTERED (SchemaName, TableName)
    );
END
GO

/*  An exemption must be justified in the row itself. A list of table names with
    no reasons becomes a place to hide things within a year. */
MERGE dbo.AuditContractExemption AS target
USING (VALUES
    ('Audit', 'AuditLog',
     N'Append-only by design. No procedure updates or deletes it and a test '
     + N'asserts that. Soft-delete columns would advertise a capability that '
     + N'must never exist.')
) AS source (SchemaName, TableName, Reason)
    ON target.SchemaName = source.SchemaName
   AND target.TableName = source.TableName
WHEN NOT MATCHED THEN
    INSERT (SchemaName, TableName, Reason)
    VALUES (source.SchemaName, source.TableName, source.Reason);
GO

-- ---------------------------------------------------------------------------
-- Apply the contract
-- ---------------------------------------------------------------------------
/*  A procedure rather than a loose batch, because it has to run more than once.
    This script sits at position 9 of the deployment order, and every script
    after it that creates a table creates one this cursor has already passed.
    Run once, in order, on an empty server, it left 19 tables without the
    contract — 147 columns and 19 filtered indexes — including Timeline.Event
    and Intelligence.UserStateSnapshot, which hold what a woman logs and what
    the platform infers from it. Earlier databases looked compliant only
    because this file happened to be applied a second time.

    So the logic lives here once and the last numbered script calls it again,
    after every table exists. Both callers share this body; a second copy would
    drift and the drift would be invisible until a table was silently missing
    its soft-delete columns. */
IF OBJECT_ID('dbo.usp_ApplyAuditContract') IS NOT NULL
    DROP PROCEDURE dbo.usp_ApplyAuditContract;
GO
CREATE PROCEDURE dbo.usp_ApplyAuditContract
AS
BEGIN
SET NOCOUNT ON;

DECLARE @schema SYSNAME, @table SYSNAME, @object_id INT;
DECLARE @sql NVARCHAR(MAX);
DECLARE @qualified NVARCHAR(300);
/*  sp_rename will not accept a concatenated expression as a parameter value,
    so the old name is built into a variable first. */
DECLARE @oldname NVARCHAR(400);
DECLARE @renamed INT = 0, @added INT = 0;

DECLARE table_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT s.name, t.name, t.object_id
    FROM sys.tables t
    JOIN sys.schemas s ON s.schema_id = t.schema_id
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.AuditContractExemption e
        WHERE e.SchemaName = s.name AND e.TableName = t.name)
      AND t.name <> 'AuditContractExemption'
    ORDER BY s.name, t.name;

OPEN table_cursor;
FETCH NEXT FROM table_cursor INTO @schema, @table, @object_id;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @qualified = QUOTENAME(@schema) + '.' + QUOTENAME(@table);

    /*  ---- Renames first -------------------------------------------------
        Rename before adding, or a table with CreatedUtc gets a second,
        empty CreatedOn column and the real data is orphaned. */

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = @object_id AND name = 'CreatedUtc')
       AND NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = @object_id AND name = 'CreatedOn')
    BEGIN
        SET @oldname = @schema + '.' + @table + '.CreatedUtc';
        EXEC sp_rename @oldname, 'CreatedOn', 'COLUMN';
        SET @renamed = @renamed + 1;
    END

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = @object_id AND name = 'ModifiedUtc')
       AND NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = @object_id AND name = 'ModifiedOn')
    BEGIN
        SET @oldname = @schema + '.' + @table + '.ModifiedUtc';
        EXEC sp_rename @oldname, 'ModifiedOn', 'COLUMN';
        SET @renamed = @renamed + 1;
    END

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = @object_id AND name = 'DeletedUtc')
       AND NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = @object_id AND name = 'DeletedOn')
    BEGIN
        SET @oldname = @schema + '.' + @table + '.DeletedUtc';
        EXEC sp_rename @oldname, 'DeletedOn', 'COLUMN';
        SET @renamed = @renamed + 1;
    END

    /*  ---- Then add whatever is still missing ----------------------------

        The *By columns are nullable on purpose. A row written by a migration,
        a seed or a scheduled job has no interactive actor, and inventing a
        system GUID to satisfy NOT NULL would put a fictional user id in the
        audit trail. NULL means "no human did this", which is the truth. */

    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = @object_id AND name = 'CreatedBy')
    BEGIN
        SET @sql = 'ALTER TABLE ' + @qualified + ' ADD CreatedBy UNIQUEIDENTIFIER NULL;';
        EXEC sp_executesql @sql; SET @added = @added + 1;
    END

    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = @object_id AND name = 'CreatedOn')
    BEGIN
        SET @sql = 'ALTER TABLE ' + @qualified + ' ADD CreatedOn DATETIME2(3) NOT NULL '
                 + 'CONSTRAINT DF_' + @schema + '_' + @table + '_CreatedOn '
                 + 'DEFAULT SYSUTCDATETIME();';
        EXEC sp_executesql @sql; SET @added = @added + 1;
    END

    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = @object_id AND name = 'ModifiedBy')
    BEGIN
        SET @sql = 'ALTER TABLE ' + @qualified + ' ADD ModifiedBy UNIQUEIDENTIFIER NULL;';
        EXEC sp_executesql @sql; SET @added = @added + 1;
    END

    /*  ModifiedOn is NOT NULL and defaults to creation time rather than being
        nullable. "Never modified" and "modified at creation" are the same
        thing for every query anybody writes, and NOT NULL saves a COALESCE in
        every ORDER BY. */
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = @object_id AND name = 'ModifiedOn')
    BEGIN
        SET @sql = 'ALTER TABLE ' + @qualified + ' ADD ModifiedOn DATETIME2(3) NOT NULL '
                 + 'CONSTRAINT DF_' + @schema + '_' + @table + '_ModifiedOn '
                 + 'DEFAULT SYSUTCDATETIME();';
        EXEC sp_executesql @sql; SET @added = @added + 1;
    END

    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = @object_id AND name = 'DeletedBy')
    BEGIN
        SET @sql = 'ALTER TABLE ' + @qualified + ' ADD DeletedBy UNIQUEIDENTIFIER NULL;';
        EXEC sp_executesql @sql; SET @added = @added + 1;
    END

    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = @object_id AND name = 'DeletedOn')
    BEGIN
        SET @sql = 'ALTER TABLE ' + @qualified + ' ADD DeletedOn DATETIME2(3) NULL;';
        EXEC sp_executesql @sql; SET @added = @added + 1;
    END

    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = @object_id AND name = 'IsDeleted')
    BEGIN
        SET @sql = 'ALTER TABLE ' + @qualified + ' ADD IsDeleted BIT NOT NULL '
                 + 'CONSTRAINT DF_' + @schema + '_' + @table + '_IsDeleted DEFAULT 0;';
        EXEC sp_executesql @sql; SET @added = @added + 1;
    END

    /*  ROWVERSION is maintained by the engine. One per table is the maximum
        SQL Server allows, so the check is on the type rather than the name —
        an existing column called anything else still satisfies concurrency. */
    IF NOT EXISTS (SELECT 1 FROM sys.columns
                   WHERE object_id = @object_id AND system_type_id = 189)
    BEGIN
        SET @sql = 'ALTER TABLE ' + @qualified + ' ADD RowVersion ROWVERSION;';
        EXEC sp_executesql @sql; SET @added = @added + 1;
    END

    FETCH NEXT FROM table_cursor INTO @schema, @table, @object_id;
END

CLOSE table_cursor;
DEALLOCATE table_cursor;

PRINT CONCAT('Audit contract applied. Renamed: ', @renamed, '. Added: ', @added, '.');

-- ---------------------------------------------------------------------------
-- Soft-delete filtered indexes
-- ---------------------------------------------------------------------------
/*  Every query that respects soft delete filters on IsDeleted = 0. Without an
    index the filter is applied after the scan, which costs more as deleted
    rows accumulate — and they accumulate forever, because soft delete never
    removes anything.

    Filtered rather than a plain index on IsDeleted: the deleted rows are the
    minority nobody queries, and indexing them wastes space that grows without
    bound. */
DECLARE @schema2 SYSNAME, @table2 SYSNAME, @sql2 NVARCHAR(MAX);
DECLARE @indexed INT = 0;

DECLARE idx_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT s.name, t.name
    FROM sys.tables t
    JOIN sys.schemas s ON s.schema_id = t.schema_id
    WHERE EXISTS (SELECT 1 FROM sys.columns c
                  WHERE c.object_id = t.object_id AND c.name = 'IsDeleted')
      AND NOT EXISTS (SELECT 1 FROM sys.indexes i
                      WHERE i.object_id = t.object_id
                        AND i.name = 'IX_' + t.name + '_NotDeleted');

OPEN idx_cursor;
FETCH NEXT FROM idx_cursor INTO @schema2, @table2;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql2 = 'CREATE INDEX ' + QUOTENAME('IX_' + @table2 + '_NotDeleted')
              + ' ON ' + QUOTENAME(@schema2) + '.' + QUOTENAME(@table2)
              + ' (IsDeleted) WHERE IsDeleted = 0;';
    EXEC sp_executesql @sql2;
    SET @indexed = @indexed + 1;

    FETCH NEXT FROM idx_cursor INTO @schema2, @table2;
END

CLOSE idx_cursor;
DEALLOCATE idx_cursor;

PRINT CONCAT('Soft-delete indexes created: ', @indexed, '.');
END
GO

/*  Applied here for the tables that already exist, and again by the last
    numbered script for every table created after this point. */
EXEC dbo.usp_ApplyAuditContract;
GO
