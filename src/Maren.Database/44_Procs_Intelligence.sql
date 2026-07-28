/*  44_Procs_Intelligence.sql

    Deriving how she lives.

    Deterministic. The same timeline produces the same state, so a result can
    be reproduced, shown to an operator, and explained. Nothing here infers a
    condition or describes a body.

    Confidence first
    ----------------
    Every dimension is computed the same way:

      1. coverage  - of the event types this dimension reads, how many have
                     data in the window, weighted
      2. rules     - which signals fired, and what they argue for
      3. value     - a score adjusted from baseline, or the categorical value
                     with the strongest support
      4. unknown   - if coverage is zero, the value is 'unknown' and nothing
                     else is reported

    Step four is the one that matters. A woman who logged nothing gets "not
    enough logged to tell yet", never a baseline score dressed up as an
    observation about her day.

    A table-valued function, not a procedure, for the same reason the signal
    evaluation is: T-SQL forbids nesting INSERT ... EXEC, and the orchestration
    layer collects this while being collected itself.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- fn_ResolveState
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Intelligence.fn_ResolveState') IS NOT NULL
    DROP FUNCTION [Intelligence].[fn_ResolveState];
GO
/*  Every dimension, resolved for one woman on one day. */
CREATE FUNCTION [Intelligence].[fn_ResolveState]
    (@UserId UNIQUEIDENTIFIER, @AsOfDate DATE, @WindowDays INT)
RETURNS TABLE
AS
RETURN
    WITH signals AS (
        SELECT SignalCode
        FROM [Knowledge].[fn_EvaluateSignals](@UserId, @AsOfDate)
    ),
    /*  Which of a dimension's inputs actually have data. Presence, not value:
        confidence asks "did she tell us", not "was it good". */
    covered AS (
        SELECT
            si.DimensionCode,
            SUM(si.Weight) AS CoveredWeight
        FROM [Intelligence].[StateInput] si
        WHERE EXISTS (
            SELECT 1 FROM [Timeline].[Event] e
            WHERE e.UserId = @UserId
              AND e.EventTypeCode = si.EventTypeCode
              AND e.IsDeleted = 0
              AND e.ValueNumeric IS NOT NULL
              AND e.OccurredLocalDate > DATEADD(DAY, -@WindowDays, @AsOfDate)
              AND e.OccurredLocalDate <= @AsOfDate)
        GROUP BY si.DimensionCode
    ),
    expected AS (
        SELECT DimensionCode, SUM(Weight) AS TotalWeight
        FROM [Intelligence].[StateInput]
        GROUP BY DimensionCode
    ),
    confidence AS (
        SELECT
            d.DimensionCode,
            CAST(ROUND(100.0 * ISNULL(c.CoveredWeight, 0)
                       / NULLIF(e.TotalWeight, 0), 0) AS INT) AS Confidence
        FROM [Intelligence].[StateDimension] d
        JOIN expected e ON e.DimensionCode = d.DimensionCode
        LEFT JOIN covered c ON c.DimensionCode = d.DimensionCode
        WHERE d.IsActive = 1
    ),
    /*  Every rule whose signal is currently raised. */
    fired AS (
        SELECT
            r.DimensionCode,
            r.SignalCode,
            r.ScoreDelta,
            r.ValueCode,
            r.ValueText,
            r.ReasonText
        FROM [Intelligence].[StateRule] r
        JOIN signals s ON s.SignalCode = r.SignalCode
        WHERE r.IsActive = 1
    ),
    /*  For a categorical dimension: the value with the most support wins, and
        ties break on the code so the answer is stable rather than arbitrary. */
    categoricalPick AS (
        SELECT
            f.DimensionCode,
            f.ValueCode,
            f.ValueText,
            SUM(f.ScoreDelta) AS Support,
            ROW_NUMBER() OVER (
                PARTITION BY f.DimensionCode
                ORDER BY SUM(f.ScoreDelta) DESC, f.ValueCode) AS rn
        FROM fired f
        WHERE f.ValueCode IS NOT NULL
        GROUP BY f.DimensionCode, f.ValueCode, f.ValueText
    )
    SELECT
        d.DimensionCode,
        d.DisplayName,
        d.ValueKind,
        conf.Confidence,

        /*  Unknown whenever nothing was logged. The schema enforces this too;
            it is stated in both places because it is the property most likely
            to be quietly relaxed by someone making a dashboard look better. */
        CASE
            WHEN conf.Confidence = 0 THEN 'unknown'
            WHEN d.ValueKind = 'categorical' THEN ISNULL(cp.ValueCode, 'steady')
            ELSE 'scored'
        END AS ValueCode,

        CASE
            WHEN conf.Confidence = 0 THEN d.UnknownText
            WHEN d.ValueKind = 'categorical' THEN ISNULL(cp.ValueText, N'Steady')
            ELSE d.DisplayName
        END AS ValueText,

        CASE
            WHEN conf.Confidence = 0 OR d.ValueKind <> 'score' THEN NULL
            ELSE
                /*  Clamped to 0-100. A pile of negative rules must not produce
                    a negative energy score, which would be meaningless to show
                    and would fail the column's own constraint. */
                CASE
                    WHEN d.BaselineScore + ISNULL(
                        (SELECT SUM(f.ScoreDelta) FROM fired f
                         WHERE f.DimensionCode = d.DimensionCode), 0) < 0 THEN 0
                    WHEN d.BaselineScore + ISNULL(
                        (SELECT SUM(f.ScoreDelta) FROM fired f
                         WHERE f.DimensionCode = d.DimensionCode), 0) > 100 THEN 100
                    ELSE d.BaselineScore + ISNULL(
                        (SELECT SUM(f.ScoreDelta) FROM fired f
                         WHERE f.DimensionCode = d.DimensionCode), 0)
                END
        END AS Score,

        /*  The reasons that actually fired. A dimension with none says so
            plainly rather than inventing a justification. */
        CASE WHEN conf.Confidence = 0 THEN d.UnknownText
             ELSE ISNULL(
                STUFF((SELECT N' ' + f.ReasonText
                       FROM fired f
                       WHERE f.DimensionCode = d.DimensionCode
                       ORDER BY ABS(f.ScoreDelta) DESC
                       FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, N''),
                N'Nothing unusual in what you have logged.')
        END AS Reason,

        ISNULL(
            STUFF((SELECT N',' + f.SignalCode
                   FROM fired f
                   WHERE f.DimensionCode = d.DimensionCode
                   ORDER BY f.SignalCode
                   FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, N''),
            N'') AS EvidenceCsv

    FROM [Intelligence].[StateDimension] d
    JOIN confidence conf ON conf.DimensionCode = d.DimensionCode
    LEFT JOIN categoricalPick cp
           ON cp.DimensionCode = d.DimensionCode AND cp.rn = 1
    WHERE d.IsActive = 1;
GO

-- ---------------------------------------------------------------------------
-- usp_Intelligence_Resolve
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Intelligence.usp_Intelligence_Resolve') IS NOT NULL
    DROP PROCEDURE [Intelligence].[usp_Intelligence_Resolve];
GO
/*  Her state today, with trend against the last day we computed.

    Persists the snapshot as a side effect. That is deliberate: trend needs
    yesterday, and recomputing history on demand would mean every rule change
    silently rewrote what the platform used to think. A snapshot is what it
    believed at the time, and it stays that way.

    Re-running for the same day overwrites that day only, so this is safe to
    call repeatedly - which it will be, on every app launch. */
CREATE PROCEDURE [Intelligence].[usp_Intelligence_Resolve]
    @UserId     UNIQUEIDENTIFIER,
    @AsOfDate   DATE = NULL,
    @WindowDays INT = 3,
    @Persist    BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @AsOfDate IS NULL SET @AsOfDate = CAST(SYSUTCDATETIME() AS DATE);
    IF @WindowDays IS NULL OR @WindowDays < 1 SET @WindowDays = 3;
    IF @WindowDays > 30 SET @WindowDays = 30;

    DECLARE @resolved TABLE (
        DimensionCode VARCHAR(30) PRIMARY KEY,
        DisplayName   NVARCHAR(80),
        ValueKind     VARCHAR(12),
        Confidence    INT,
        ValueCode     VARCHAR(30),
        ValueText     NVARCHAR(80),
        Score         INT,
        Reason        NVARCHAR(MAX),
        EvidenceCsv   NVARCHAR(MAX));

    INSERT INTO @resolved
    SELECT DimensionCode, DisplayName, ValueKind, Confidence,
           ValueCode, ValueText, Score, Reason, EvidenceCsv
    FROM [Intelligence].[fn_ResolveState](@UserId, @AsOfDate, @WindowDays);

    IF @Persist = 1
    BEGIN
        BEGIN TRAN;

            DELETE FROM [Intelligence].[UserStateSnapshot]
            WHERE UserId = @UserId AND ForLocalDate = @AsOfDate;

            INSERT INTO [Intelligence].[UserStateSnapshot]
                (UserId, DimensionCode, ForLocalDate, ValueCode, ValueText,
                 Score, Confidence, Reason, EvidenceCsv)
            SELECT @UserId, r.DimensionCode, @AsOfDate, r.ValueCode, r.ValueText,
                   r.Score, r.Confidence,
                   LEFT(r.Reason, 600), LEFT(r.EvidenceCsv, 400)
            FROM @resolved r;

        COMMIT;
    END

    /*  Trend compares today with the most recent earlier snapshot. 'new' when
        there is nothing to compare against - saying "improving" on the first
        day would be an invention. */
    SELECT
        r.DimensionCode,
        r.DisplayName,
        r.ValueKind,
        r.ValueCode,
        r.ValueText,
        r.Score,
        r.Confidence,
        r.Reason,
        r.EvidenceCsv,
        prev.Score AS PreviousScore,
        prev.ForLocalDate AS PreviousDate,
        CASE
            WHEN prev.ForLocalDate IS NULL THEN 'new'
            WHEN r.Score IS NULL OR prev.Score IS NULL THEN 'steady'
            WHEN r.Score > prev.Score + 4 THEN 'improving'
            WHEN r.Score < prev.Score - 4 THEN 'slipping'
            ELSE 'steady'
        END AS Trend,
        d.SortOrder
    FROM @resolved r
    JOIN [Intelligence].[StateDimension] d ON d.DimensionCode = r.DimensionCode
    OUTER APPLY (
        SELECT TOP 1 s.Score, s.ForLocalDate
        FROM [Intelligence].[UserStateSnapshot] s
        WHERE s.UserId = @UserId
          AND s.DimensionCode = r.DimensionCode
          AND s.ForLocalDate < @AsOfDate
        ORDER BY s.ForLocalDate DESC
    ) prev
    ORDER BY d.SortOrder;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Intelligence_History
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Intelligence.usp_Intelligence_History') IS NOT NULL
    DROP PROCEDURE [Intelligence].[usp_Intelligence_History];
GO
/*  What the platform believed about one dimension over time. Powers the trend
    view and the operator's inspector. */
CREATE PROCEDURE [Intelligence].[usp_Intelligence_History]
    @UserId        UNIQUEIDENTIFIER,
    @DimensionCode VARCHAR(30),
    @Days          INT = 30
AS
BEGIN
    SET NOCOUNT ON;

    IF @Days IS NULL OR @Days < 1 SET @Days = 30;
    IF @Days > 365 SET @Days = 365;

    SELECT TOP (@Days)
        s.ForLocalDate,
        s.ValueCode,
        s.ValueText,
        s.Score,
        s.Confidence,
        s.Reason,
        s.EvidenceCsv,
        s.ComputedUtc
    FROM [Intelligence].[UserStateSnapshot] s
    WHERE s.UserId = @UserId
      AND s.DimensionCode = @DimensionCode
    ORDER BY s.ForLocalDate DESC;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Intelligence_ListDimensions
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Intelligence.usp_Intelligence_ListDimensions') IS NOT NULL
    DROP PROCEDURE [Intelligence].[usp_Intelligence_ListDimensions];
GO
/*  The registry, for the portal's inspector. */
CREATE PROCEDURE [Intelligence].[usp_Intelligence_ListDimensions]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        d.DimensionCode,
        d.DisplayName,
        d.ValueKind,
        d.BaselineScore,
        d.UnknownText,
        d.SortOrder,
        d.IsActive,
        (SELECT COUNT(*) FROM [Intelligence].[StateInput] i
         WHERE i.DimensionCode = d.DimensionCode) AS InputCount,
        (SELECT COUNT(*) FROM [Intelligence].[StateRule] r
         WHERE r.DimensionCode = d.DimensionCode AND r.IsActive = 1) AS RuleCount
    FROM [Intelligence].[StateDimension] d
    ORDER BY d.SortOrder;
END
GO
