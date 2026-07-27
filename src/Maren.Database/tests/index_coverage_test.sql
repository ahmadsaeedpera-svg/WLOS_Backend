/*  index_coverage_test.sql

    Asserts that every foreign key in the database has an index whose
    leading key column is the foreign key column.

    This is a standing invariant, not a one-off check. It fails the moment
    someone adds a foreign key without a supporting index - which is how the
    eighteen fixed in 30_Indexes_ForeignKeys.sql accumulated in the first
    place. See docs/DATABASE_REVIEW.md finding C-1.

    Run:
      sqlcmd -S "$SERVER" -I -d "$DB" -i src/Maren.Database/tests/index_coverage_test.sql

    Expect: TOTAL: <n>  FAILED: 0

    Read-only. Creates no objects and modifies no data.
*/

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

DECLARE @failed int = 0;
DECLARE @total  int = 0;

PRINT '=== Foreign key index coverage ===';
PRINT '';

/*  A foreign key is covered when some index on the referencing table has
    the foreign key column at key_ordinal 1. Included columns do not count:
    an INCLUDE cannot be seeked on, so it cannot serve the reference check.

    Multi-column foreign keys are judged on their own leading column
    (fkc.constraint_column_id = 1) for the same reason. */
DECLARE @uncovered TABLE (
    SchemaName sysname,
    TableName  sysname,
    ColumnName sysname,
    FkName     sysname
);

INSERT INTO @uncovered (SchemaName, TableName, ColumnName, FkName)
SELECT sch.[name], t.[name], c.[name], fk.[name]
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc
       ON fkc.constraint_object_id = fk.object_id
      AND fkc.constraint_column_id = 1
JOIN sys.tables  t   ON t.object_id   = fkc.parent_object_id
JOIN sys.schemas sch ON sch.schema_id = t.schema_id
JOIN sys.columns c   ON c.object_id   = t.object_id
                    AND c.column_id   = fkc.parent_column_id
WHERE NOT EXISTS (
    SELECT 1
    FROM sys.index_columns ic
    WHERE ic.object_id          = fkc.parent_object_id
      AND ic.column_id          = fkc.parent_column_id
      AND ic.key_ordinal        = 1
      AND ic.is_included_column = 0
);

SELECT @total = COUNT(*) FROM sys.foreign_keys;

DECLARE @uncoveredCount int = (SELECT COUNT(*) FROM @uncovered);

IF @uncoveredCount = 0
BEGIN
    PRINT '  1 every foreign key has a supporting index                        PASS';
END
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT '  1 every foreign key has a supporting index                        FAIL';
    PRINT '';
    PRINT '    Uncovered foreign keys:';

    DECLARE @s sysname, @t sysname, @c sysname, @f sysname;
    DECLARE uncovered_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT SchemaName, TableName, ColumnName, FkName
        FROM @uncovered ORDER BY SchemaName, TableName, ColumnName;

    OPEN uncovered_cur;
    FETCH NEXT FROM uncovered_cur INTO @s, @t, @c, @f;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        PRINT '      ' + @s + '.' + @t + '.' + @c + '  (' + @f + ')';
        FETCH NEXT FROM uncovered_cur INTO @s, @t, @c, @f;
    END
    CLOSE uncovered_cur;
    DEALLOCATE uncovered_cur;

    PRINT '';
    PRINT '    Add an index whose FIRST key column is the foreign key column.';
    PRINT '    Do not use a filtered index: a reference check and a cascade';
    PRINT '    delete must be able to find every referencing row, including';
    PRINT '    soft-deleted ones.';
END

PRINT '';

/*  Second assertion: the indexes this change introduced must be unfiltered.
    A filtered index here would look like coverage while leaving the cascade
    path scanning, which is the subtle failure this whole change exists to
    prevent. */
DECLARE @filteredFkIndexes int = (
    SELECT COUNT(*)
    FROM sys.foreign_keys fk
    JOIN sys.foreign_key_columns fkc
           ON fkc.constraint_object_id = fk.object_id
          AND fkc.constraint_column_id = 1
    JOIN sys.index_columns ic
           ON ic.object_id          = fkc.parent_object_id
          AND ic.column_id          = fkc.parent_column_id
          AND ic.key_ordinal        = 1
          AND ic.is_included_column = 0
    JOIN sys.indexes i
           ON i.object_id = ic.object_id
          AND i.index_id  = ic.index_id
    WHERE i.has_filter = 1
      AND NOT EXISTS (
            /*  Tolerated when an unfiltered index also covers the column,
                since the unfiltered one serves the cascade. */
            SELECT 1
            FROM sys.index_columns ic2
            JOIN sys.indexes i2 ON i2.object_id = ic2.object_id
                               AND i2.index_id  = ic2.index_id
            WHERE ic2.object_id          = fkc.parent_object_id
              AND ic2.column_id          = fkc.parent_column_id
              AND ic2.key_ordinal        = 1
              AND ic2.is_included_column = 0
              AND i2.has_filter          = 0)
);

IF @filteredFkIndexes = 0
    PRINT '  2 no foreign key relies on a filtered index alone                 PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT '  2 no foreign key relies on a filtered index alone                 FAIL';
END

PRINT '';
PRINT '---------------------------------------------';
PRINT 'TOTAL: 2  FAILED: ' + CAST(@failed AS varchar(10));
PRINT 'Foreign keys examined: ' + CAST(@total AS varchar(10));
PRINT '---------------------------------------------';

IF @failed > 0
    THROW 51000, 'Foreign key index coverage assertions failed.', 1;
GO
