/*  40_Procs_Knowledge.sql

    Evaluating signals against the timeline, and walking the graph.

    Deterministic throughout. No model, no inference, no probability beyond the
    stored Strength that orders what she sees. The roadmap puts an AI companion
    several capabilities later, and its job will be to phrase what these
    procedures found - not to decide it. Keeping the detection deterministic is
    what makes that division honest: the reasoning can be shown to a clinician
    and reproduced exactly.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- usp_Knowledge_EvaluateSignals
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Knowledge.usp_Knowledge_EvaluateSignals') IS NOT NULL
    DROP PROCEDURE [Knowledge].[usp_Knowledge_EvaluateSignals];
GO
/*  Which signals are currently raised for her.

    Reads the timeline through the same daily aggregation the score engine will
    use, so a signal and a score can never disagree about what a day's water
    was.

    A rule fires only when the threshold is breached on at least MinBreachDays
    within its window. One unusual Tuesday is not a pattern, and treating it as
    one is how a companion becomes a nag.

    Days with no data are not breaches. Absence of evidence is not evidence:
    she may simply not have logged, and raising "you have been drinking less"
    because she stopped recording would be both wrong and discouraging at
    exactly the moment she needs the opposite. */
CREATE PROCEDURE [Knowledge].[usp_Knowledge_EvaluateSignals]
    @UserId  UNIQUEIDENTIFIER,
    @AsOfDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @AsOfDate IS NULL SET @AsOfDate = CAST(SYSUTCDATETIME() AS DATE);

    /*  One pass over her recent events, aggregated per day per type. The
        widest rule window bounds how far back to read. */
    DECLARE @maxWindow INT =
        (SELECT ISNULL(MAX(WindowDays), 1) FROM [Knowledge].[SignalRule] WHERE IsActive = 1);

    ;WITH daily AS (
        SELECT
            e.EventTypeCode,
            e.OccurredLocalDate,
            CASE WHEN t.IsCumulative = 1 THEN SUM(e.ValueNumeric) ELSE AVG(e.ValueNumeric) END AS DayValue
        FROM [Timeline].[Event] e
        JOIN [Timeline].[EventType] t ON t.EventTypeCode = e.EventTypeCode
        WHERE e.UserId = @UserId
          AND e.IsDeleted = 0
          AND e.ValueNumeric IS NOT NULL
          AND e.OccurredLocalDate > DATEADD(DAY, -@maxWindow, @AsOfDate)
          AND e.OccurredLocalDate <= @AsOfDate
        /*  IsCumulative is grouped as well as tested: it appears in the CASE
            above, and a column in a select list must be aggregated or grouped.
            It is functionally dependent on EventTypeCode, so grouping by it
            changes nothing about the result. */
        GROUP BY e.EventTypeCode, e.OccurredLocalDate, t.IsCumulative
    ),
    breaches AS (
        SELECT
            r.SignalCode,
            r.SignalRuleId,
            r.MinBreachDays,
            COUNT(*) AS BreachDays
        FROM [Knowledge].[SignalRule] r
        JOIN daily d
              ON d.EventTypeCode = r.EventTypeCode
             AND d.OccurredLocalDate > DATEADD(DAY, -r.WindowDays, @AsOfDate)
        WHERE r.IsActive = 1
          AND ((r.Comparator = 'lt'  AND d.DayValue <  r.Threshold)
            OR (r.Comparator = 'lte' AND d.DayValue <= r.Threshold)
            OR (r.Comparator = 'gt'  AND d.DayValue >  r.Threshold)
            OR (r.Comparator = 'gte' AND d.DayValue >= r.Threshold))
        GROUP BY r.SignalCode, r.SignalRuleId, r.MinBreachDays
    )
    SELECT
        s.SignalCode,
        s.DisplayName,
        s.DomainCode,
        s.ObservationText,
        s.IsHealthSensitive,
        b.BreachDays
    FROM breaches b
    JOIN [Knowledge].[Signal] s ON s.SignalCode = b.SignalCode
    WHERE b.BreachDays >= b.MinBreachDays
      AND s.IsActive = 1
    ORDER BY s.SortOrder;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Knowledge_Related
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Knowledge.usp_Knowledge_Related') IS NOT NULL
    DROP PROCEDURE [Knowledge].[usp_Knowledge_Related];
GO
/*  What is commonly reported alongside a signal, walking outward.

    Bounded depth, and the bound is small on purpose. Three hops from "sleeping
    less" reaches almost every node in a connected graph, and a companion that
    connects her short sleep to her screen time to her stress to her mood to a
    headache has written a diagnosis by accident - one hop at a time, each of
    them individually defensible.

    Strength decays with distance so a second-hop association is never
    presented as firmly as a first-hop one, and cycles are prevented by
    tracking the path rather than by trusting the data to be acyclic. The seed
    already contains a legitimate two-way pair, stress and short sleep, so
    cycles are expected rather than a data error. */
CREATE PROCEDURE [Knowledge].[usp_Knowledge_Related]
    @SignalCode VARCHAR(40),
    @MaxDepth   INT = 2,
    @MinStrength DECIMAL(3,2) = 0.30
AS
BEGIN
    SET NOCOUNT ON;

    IF @MaxDepth IS NULL OR @MaxDepth < 1 SET @MaxDepth = 1;
    /*  Hard ceiling, not a suggestion. See the header. */
    IF @MaxDepth > 3 SET @MaxDepth = 3;

    ;WITH walk AS (
        SELECT
            r.ToSignalCode,
            r.RelationKind,
            CAST(r.Strength AS DECIMAL(10,6)) AS Strength,
            1 AS Depth,
            CAST('|' + r.FromSignalCode + '|' + r.ToSignalCode + '|' AS NVARCHAR(2000)) AS Path
        FROM [Knowledge].[SignalRelation] r
        WHERE r.FromSignalCode = @SignalCode
          AND r.IsActive = 1

        UNION ALL

        SELECT
            r.ToSignalCode,
            r.RelationKind,
            CAST(w.Strength * r.Strength AS DECIMAL(10,6)),
            w.Depth + 1,
            CAST(w.Path + r.ToSignalCode + '|' AS NVARCHAR(2000))
        FROM walk w
        JOIN [Knowledge].[SignalRelation] r ON r.FromSignalCode = w.ToSignalCode
        WHERE w.Depth < @MaxDepth
          AND r.IsActive = 1
          /*  Never revisit a node already on this path. */
          AND w.Path NOT LIKE '%|' + r.ToSignalCode + '|%'
    )
    SELECT
        w.ToSignalCode AS SignalCode,
        s.DisplayName,
        s.DomainCode,
        s.ObservationText,
        s.IsHealthSensitive,
        MIN(w.Depth) AS Depth,
        MAX(w.Strength) AS Strength
    FROM walk w
    JOIN [Knowledge].[Signal] s ON s.SignalCode = w.ToSignalCode
    WHERE s.IsActive = 1
    GROUP BY w.ToSignalCode, s.DisplayName, s.DomainCode, s.ObservationText,
             s.IsHealthSensitive, s.SortOrder
    HAVING MAX(w.Strength) >= @MinStrength
    ORDER BY MAX(w.Strength) DESC, s.SortOrder;
END
GO

-- ---------------------------------------------------------------------------
-- usp_LifeDomain_List
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Content.usp_LifeDomain_List') IS NOT NULL
    DROP PROCEDURE [Content].[usp_LifeDomain_List];
GO
CREATE PROCEDURE [Content].[usp_LifeDomain_List]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DomainCode, DisplayName, [Description], ParentDomainCode,
           IsHealthSensitive, SortOrder
    FROM [Content].[LifeDomain]
    WHERE IsActive = 1
    ORDER BY SortOrder;
END
GO
