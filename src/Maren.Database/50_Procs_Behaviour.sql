/*  50_Procs_Behaviour.sql

    The one place behaviour is computed.

    Behaviour.fn_Observe is the single source of truth for every behavioural
    number in the platform. Habit, routine, goal, recommendation, coach and
    prediction all read what it produces. None of them computes a streak, a
    consistency figure or a probability of its own.

    That rule is not a style preference. Six engines each deciding "did she do
    this on that day" is six chances to decide it differently, and the failure
    mode is a woman reading two screens that disagree about her own week. The
    duplication is also asserted against - behaviour_test.sql fails if the words
    that mean "count her days" appear in a procedure outside this schema.

    Everything comes from Timeline.Event
    ------------------------------------
    There is no other input. No profile field, no assumed routine, no default.
    A subject with no logged events produces no observations rather than zeros,
    because a zero streak and an unknown streak look identical on a screen and
    mean opposite things.

    Local dates throughout
    ----------------------
    Days are counted on OccurredLocalDate, never on the UTC timestamp. A woman
    in Karachi logging water at 2am would otherwise break her own streak by
    doing the thing she is trying to keep doing.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- fn_SubjectDays — the atom every measure is built from
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Behaviour.fn_SubjectDays') IS NOT NULL
    DROP FUNCTION [Behaviour].[fn_SubjectDays];
GO
/*  One row per (subject, day she did it), inside the window.

    Everything else - consistency, streaks, rhythm, momentum, probability - is
    arithmetic over this set. Defining "a day she did it" exactly once is the
    whole point: it is the only judgement in behaviour intelligence, and it is
    made here.

    A day counts when the number of distinct required parts logged reaches the
    subject's target. For a simple subject that is one event. For a routine it
    is the number of its required parts, so two of three optional-included
    steps do not silently count as a complete wind-down.

    Distinct part, not event count: logging water eight times in a day is one
    day of hydration, not eight. Otherwise a thirsty afternoon would look like
    a week of consistency. */
CREATE FUNCTION [Behaviour].[fn_SubjectDays]
    (@UserId UNIQUEIDENTIFIER, @AsOfDate DATE, @WindowDays INT)
RETURNS TABLE
AS
RETURN
    SELECT
        se.SubjectKey,
        e.OccurredLocalDate AS LocalDate,
        COUNT(DISTINCT e.EventTypeCode) AS PartsLogged,
        COUNT_BIG(*) AS EventCount
    FROM [Behaviour].[SubjectEvent] se
    JOIN [Timeline].[Event] e
          ON e.EventTypeCode = se.EventTypeCode
    JOIN [Behaviour].[Subject] s
          ON s.SubjectKey = se.SubjectKey
    WHERE e.UserId = @UserId
      AND e.IsDeleted = 0
      AND s.IsActive = 1
      AND se.IsRequired = 1
      AND e.OccurredLocalDate <= @AsOfDate
      AND e.OccurredLocalDate > DATEADD(DAY, -@WindowDays, @AsOfDate)
    GROUP BY se.SubjectKey, e.OccurredLocalDate, s.TargetPerDay
    HAVING COUNT(DISTINCT e.EventTypeCode) >= s.TargetPerDay;
GO

-- ---------------------------------------------------------------------------
-- fn_SubjectSpan — how much history exists to reason from
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Behaviour.fn_SubjectSpan') IS NOT NULL
    DROP FUNCTION [Behaviour].[fn_SubjectSpan];
GO
/*  The observed span per subject: first day, last day, how many days carried
    activity, and how many events supported it.

    Span is measured from her first logged day, not from the window, because
    confidence must describe what she has actually shown the platform. A woman
    who joined four days ago has four days of span inside a 56-day window, and
    reporting 56 would be the platform claiming to have watched her for two
    months. */
CREATE FUNCTION [Behaviour].[fn_SubjectSpan]
    (@UserId UNIQUEIDENTIFIER, @AsOfDate DATE, @WindowDays INT)
RETURNS TABLE
AS
RETURN
    SELECT
        d.SubjectKey,
        MIN(d.LocalDate) AS FirstDate,
        MAX(d.LocalDate) AS LastDate,
        COUNT(*)         AS ActiveDays,
        SUM(d.EventCount) AS SupportingEvents,
        /*  Inclusive of both ends: one logged day is a span of one, not zero. */
        DATEDIFF(DAY, MIN(d.LocalDate), @AsOfDate) + 1 AS SpanDays
    FROM [Behaviour].[fn_SubjectDays](@UserId, @AsOfDate, @WindowDays) d
    GROUP BY d.SubjectKey;
GO

-- ---------------------------------------------------------------------------
-- fn_Observe — every measure, for every subject
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Behaviour.fn_Observe') IS NOT NULL
    DROP FUNCTION [Behaviour].[fn_Observe];
GO
/*  What the platform can honestly say about how she lives.

    A table-valued function rather than a procedure so it composes: the
    inspector, the resolver and any future engine can join to it directly.
    INSERT ... EXEC cannot nest, and the dashboard engine has already been
    caught once by that - a procedure here would silently return nothing to any
    caller that was itself inside an INSERT ... EXEC.

    Confidence is coverage, never a judgement about the value. It scales from
    MinSpanDays to FullSpanDays on the span actually observed, and a measure
    below its minimum is not returned at all. So a screen either shows a number
    that has history behind it, or shows nothing - never a confident-looking
    figure derived from three days. */
CREATE FUNCTION [Behaviour].[fn_Observe]
    (@UserId UNIQUEIDENTIFIER, @AsOfDate DATE, @WindowDays INT)
RETURNS TABLE
AS
RETURN
    WITH days AS (
        SELECT SubjectKey, LocalDate, EventCount
        FROM [Behaviour].[fn_SubjectDays](@UserId, @AsOfDate, @WindowDays)
    ),
    span AS (
        SELECT SubjectKey, FirstDate, LastDate, ActiveDays,
               SupportingEvents, SpanDays
        FROM [Behaviour].[fn_SubjectSpan](@UserId, @AsOfDate, @WindowDays)
    ),

    /*  Gaps and islands. Consecutive days share a group because subtracting a
        dense row number from the date holds constant across a run; a break in
        the run shifts it. This is the only way to get a streak without a loop,
        and a loop inside a function called per user per day would be the
        platform's slowest path. */
    islands AS (
        SELECT
            d.SubjectKey,
            d.LocalDate,
            DATEADD(DAY,
                -ROW_NUMBER() OVER (PARTITION BY d.SubjectKey ORDER BY d.LocalDate),
                d.LocalDate) AS IslandKey
        FROM days d
    ),
    runs AS (
        SELECT
            SubjectKey,
            IslandKey,
            COUNT(*) AS RunLength,
            MAX(LocalDate) AS RunEnd
        FROM islands
        GROUP BY SubjectKey, IslandKey
    ),
    /*  A current streak only counts if it reaches today or yesterday. Ending
        three days ago it is history, and calling it current would tell her she
        is on a run she has already broken. */
    currentRun AS (
        SELECT SubjectKey, MAX(RunLength) AS RunLength
        FROM runs
        WHERE RunEnd >= DATEADD(DAY, -1, @AsOfDate)
        GROUP BY SubjectKey
    ),
    bestRun AS (
        SELECT SubjectKey, MAX(RunLength) AS RunLength
        FROM runs GROUP BY SubjectKey
    ),

    /*  Two halves of the window, for momentum. Compared as rates rather than
        counts so an uneven split does not read as a decline. */
    halves AS (
        SELECT
            d.SubjectKey,
            SUM(CASE WHEN d.LocalDate > DATEADD(DAY, -(@WindowDays / 2), @AsOfDate)
                     THEN 1 ELSE 0 END) AS RecentDays,
            SUM(CASE WHEN d.LocalDate <= DATEADD(DAY, -(@WindowDays / 2), @AsOfDate)
                     THEN 1 ELSE 0 END) AS EarlierDays
        FROM days d
        GROUP BY d.SubjectKey
    ),

    /*  Weekday rhythm. Ranked on the count of days she did it, because the
        number of each weekday inside a window differs by at most one and
        normalising by it would add arithmetic without changing the order. */
    weekday AS (
        SELECT
            d.SubjectKey,
            DATEPART(WEEKDAY, d.LocalDate) AS WeekdayNo,
            COUNT(*) AS DayCount,
            ROW_NUMBER() OVER (PARTITION BY d.SubjectKey
                               ORDER BY COUNT(*) DESC, DATEPART(WEEKDAY, d.LocalDate)) AS BestRank,
            ROW_NUMBER() OVER (PARTITION BY d.SubjectKey
                               ORDER BY COUNT(*) ASC, DATEPART(WEEKDAY, d.LocalDate)) AS WorstRank
        FROM days d
        GROUP BY d.SubjectKey, DATEPART(WEEKDAY, d.LocalDate)
    ),

    /*  Thirds of the month rather than day-of-month: with a year of data there
        are twelve observations of "the 7th" and roughly a hundred of "the first
        third", and a rhythm read off twelve points is noise. */
    monthPart AS (
        SELECT
            d.SubjectKey,
            CASE WHEN DAY(d.LocalDate) <= 10 THEN 1
                 WHEN DAY(d.LocalDate) <= 20 THEN 2
                 ELSE 3 END AS PartNo,
            COUNT(*) AS DayCount,
            ROW_NUMBER() OVER (PARTITION BY d.SubjectKey
                ORDER BY COUNT(*) DESC,
                         CASE WHEN DAY(d.LocalDate) <= 10 THEN 1
                              WHEN DAY(d.LocalDate) <= 20 THEN 2
                              ELSE 3 END) AS BestRank
        FROM days d
        GROUP BY d.SubjectKey,
                 CASE WHEN DAY(d.LocalDate) <= 10 THEN 1
                      WHEN DAY(d.LocalDate) <= 20 THEN 2
                      ELSE 3 END
    ),

    season AS (
        SELECT
            d.SubjectKey,
            DATEPART(QUARTER, d.LocalDate) AS QuarterNo,
            COUNT(*) AS DayCount,
            ROW_NUMBER() OVER (PARTITION BY d.SubjectKey
                ORDER BY COUNT(*) DESC, DATEPART(QUARTER, d.LocalDate)) AS BestRank
        FROM days d
        GROUP BY d.SubjectKey, DATEPART(QUARTER, d.LocalDate)
    ),

    /*  Hour of day, from the raw events rather than the day roll-up: the
        question is what time she does it, which a per-day set has thrown away.
        Local hour is reconstructed from the offset between the local date and
        the UTC timestamp, because that is the only local information the
        timeline stores. */
    hours AS (
        SELECT
            se.SubjectKey,
            DATEPART(HOUR, e.OccurredUtc) AS HourNo,
            COUNT(*) AS EventCount,
            ROW_NUMBER() OVER (PARTITION BY se.SubjectKey
                ORDER BY COUNT(*) DESC, DATEPART(HOUR, e.OccurredUtc)) AS BestRank,
            ROW_NUMBER() OVER (PARTITION BY se.SubjectKey
                ORDER BY COUNT(*) ASC, DATEPART(HOUR, e.OccurredUtc)) AS WorstRank
        FROM [Behaviour].[SubjectEvent] se
        JOIN [Timeline].[Event] e ON e.EventTypeCode = se.EventTypeCode
        WHERE e.UserId = @UserId
          AND e.IsDeleted = 0
          AND se.IsRequired = 1
          AND e.OccurredLocalDate <= @AsOfDate
          AND e.OccurredLocalDate > DATEADD(DAY, -@WindowDays, @AsOfDate)
          /*  Waking hours only. The least likely hour of any behaviour is 4am,
              which is true, useless, and would be the platform telling her
              something she already knows about sleep. */
          AND DATEPART(HOUR, e.OccurredUtc) BETWEEN 5 AND 23
        GROUP BY se.SubjectKey, DATEPART(HOUR, e.OccurredUtc)
    ),

    /*  Every measure this subject is configured for, with the span it has to
        work with. The cross join is bounded by SubjectMeasure, so a subject
        never produces a measure somebody decided was meaningless for it. */
    applicable AS (
        SELECT
            sm.SubjectKey,
            sm.MeasureCode,
            m.DisplayName AS MeasureName,
            m.Family,
            m.ValueKind,
            m.Unit,
            m.MinSpanDays,
            m.FullSpanDays,
            m.SortOrder,
            sp.FirstDate,
            sp.LastDate,
            sp.ActiveDays,
            sp.SupportingEvents,
            sp.SpanDays,
            /*  Coverage, clamped. Full span or more is 100; below the minimum
                the row is dropped entirely by the WHERE below. */
            CASE
                WHEN sp.SpanDays >= m.FullSpanDays THEN 100
                ELSE CAST(ROUND(100.0 * sp.SpanDays / NULLIF(m.FullSpanDays, 0), 0) AS INT)
            END AS Confidence
        FROM [Behaviour].[SubjectMeasure] sm
        JOIN [Behaviour].[MeasureType] m ON m.MeasureCode = sm.MeasureCode
        JOIN [Behaviour].[Subject] s ON s.SubjectKey = sm.SubjectKey
        JOIN span sp ON sp.SubjectKey = sm.SubjectKey
        WHERE m.IsActive = 1
          AND s.IsActive = 1
          AND sp.SpanDays >= m.MinSpanDays
    )

    SELECT
        a.SubjectKey,
        a.MeasureCode,
        a.MeasureName,
        a.Family,
        a.ValueKind,
        a.Unit,
        a.Confidence,
        a.SpanDays,
        a.SupportingEvents AS SupportingEventCount,
        a.FirstDate AS FirstObservedDate,
        a.LastDate  AS LastObservedDate,
        a.SortOrder,

        CAST(v.ValueNumeric AS DECIMAL(9, 4)) AS ValueNumeric,
        v.ValueText,
        v.Reason,

        /*  The evidence is the event types that actually carried the
            observation, so "why does it think that" resolves to rows in her own
            timeline rather than to a description of the algorithm. */
        ISNULL(STUFF((
            SELECT N',' + se.EventTypeCode
            FROM [Behaviour].[SubjectEvent] se
            WHERE se.SubjectKey = a.SubjectKey AND se.IsRequired = 1
            ORDER BY se.SortOrder, se.EventTypeCode
            FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, N''),
            N'') AS EvidenceCsv

    FROM applicable a
    CROSS APPLY (
        SELECT
            ValueNumeric = CASE a.MeasureCode
                WHEN 'days_active' THEN a.ActiveDays
                WHEN 'consistency' THEN
                    ROUND(100.0 * a.ActiveDays / NULLIF(a.SpanDays, 0), 1)
                WHEN 'streak_current' THEN
                    ISNULL((SELECT RunLength FROM currentRun c
                            WHERE c.SubjectKey = a.SubjectKey), 0)
                WHEN 'streak_best' THEN
                    ISNULL((SELECT RunLength FROM bestRun b
                            WHERE b.SubjectKey = a.SubjectKey), 0)
                WHEN 'days_since_last' THEN
                    DATEDIFF(DAY, a.LastDate, @AsOfDate)
                WHEN 'momentum' THEN
                    /*  Percentage points, both halves as rates over the same
                        number of days, so the comparison is like for like. */
                    ROUND(
                        100.0 * ISNULL((SELECT RecentDays FROM halves h
                                        WHERE h.SubjectKey = a.SubjectKey), 0)
                             / NULLIF(@WindowDays / 2, 0)
                      - 100.0 * ISNULL((SELECT EarlierDays FROM halves h
                                        WHERE h.SubjectKey = a.SubjectKey), 0)
                             / NULLIF(@WindowDays / 2, 0), 1)
                WHEN 'rhythm_weekday_best' THEN
                    (SELECT WeekdayNo FROM weekday w
                     WHERE w.SubjectKey = a.SubjectKey AND w.BestRank = 1)
                WHEN 'rhythm_weekday_worst' THEN
                    (SELECT WeekdayNo FROM weekday w
                     WHERE w.SubjectKey = a.SubjectKey AND w.WorstRank = 1)
                WHEN 'rhythm_month_best' THEN
                    (SELECT PartNo FROM monthPart p
                     WHERE p.SubjectKey = a.SubjectKey AND p.BestRank = 1)
                WHEN 'rhythm_season_best' THEN
                    (SELECT QuarterNo FROM season q
                     WHERE q.SubjectKey = a.SubjectKey AND q.BestRank = 1)
                WHEN 'preferred_hour' THEN
                    (SELECT HourNo FROM hours h
                     WHERE h.SubjectKey = a.SubjectKey AND h.BestRank = 1)
                WHEN 'hardest_hour' THEN
                    (SELECT HourNo FROM hours h
                     WHERE h.SubjectKey = a.SubjectKey AND h.WorstRank = 1)

                /*  Observed rate nudged by recent direction, clamped to 5-95.
                    Never 0 or 100: a woman who has done something every day for
                    a month is not certain to do it tomorrow, and saying so
                    would be the platform overstating what watching someone can
                    tell you. */
                WHEN 'completion_probability' THEN
                    ROUND(
                        CASE
                            WHEN 1.0 * a.ActiveDays / NULLIF(a.SpanDays, 0)
                               + 0.005 * ISNULL((SELECT 100.0 * h.RecentDays / NULLIF(@WindowDays / 2, 0)
                                                      - 100.0 * h.EarlierDays / NULLIF(@WindowDays / 2, 0)
                                                 FROM halves h WHERE h.SubjectKey = a.SubjectKey), 0)
                                 > 0.95 THEN 0.95
                            WHEN 1.0 * a.ActiveDays / NULLIF(a.SpanDays, 0)
                               + 0.005 * ISNULL((SELECT 100.0 * h.RecentDays / NULLIF(@WindowDays / 2, 0)
                                                      - 100.0 * h.EarlierDays / NULLIF(@WindowDays / 2, 0)
                                                 FROM halves h WHERE h.SubjectKey = a.SubjectKey), 0)
                                 < 0.05 THEN 0.05
                            ELSE 1.0 * a.ActiveDays / NULLIF(a.SpanDays, 0)
                               + 0.005 * ISNULL((SELECT 100.0 * h.RecentDays / NULLIF(@WindowDays / 2, 0)
                                                      - 100.0 * h.EarlierDays / NULLIF(@WindowDays / 2, 0)
                                                 FROM halves h WHERE h.SubjectKey = a.SubjectKey), 0)
                        END, 3)

                /*  Engagement decays with silence. Seven days without logging
                    halves it; a fortnight quarters it. Recency is the strongest
                    thing an observer has, and it is the only thing used here -
                    no proxy for how she feels. */
                WHEN 'engagement_probability' THEN
                    ROUND(
                        CASE
                            WHEN (1.0 * a.ActiveDays / NULLIF(a.SpanDays, 0))
                               * POWER(0.5, DATEDIFF(DAY, a.LastDate, @AsOfDate) / 7.0) > 0.95
                            THEN 0.95
                            WHEN (1.0 * a.ActiveDays / NULLIF(a.SpanDays, 0))
                               * POWER(0.5, DATEDIFF(DAY, a.LastDate, @AsOfDate) / 7.0) < 0.05
                            THEN 0.05
                            ELSE (1.0 * a.ActiveDays / NULLIF(a.SpanDays, 0))
                               * POWER(0.5, DATEDIFF(DAY, a.LastDate, @AsOfDate) / 7.0)
                        END, 3)

                WHEN 'dropoff_probability' THEN
                    ROUND(1.0 -
                        CASE
                            WHEN (1.0 * a.ActiveDays / NULLIF(a.SpanDays, 0))
                               * POWER(0.5, DATEDIFF(DAY, a.LastDate, @AsOfDate) / 7.0) > 0.95
                            THEN 0.95
                            WHEN (1.0 * a.ActiveDays / NULLIF(a.SpanDays, 0))
                               * POWER(0.5, DATEDIFF(DAY, a.LastDate, @AsOfDate) / 7.0) < 0.05
                            THEN 0.05
                            ELSE (1.0 * a.ActiveDays / NULLIF(a.SpanDays, 0))
                               * POWER(0.5, DATEDIFF(DAY, a.LastDate, @AsOfDate) / 7.0)
                        END, 3)
                ELSE NULL
            END
    ) raw
    CROSS APPLY (
        SELECT
            ValueNumeric = raw.ValueNumeric,

            /*  Text is what a person reads, and it is produced here rather than
                in a client so every client says the same thing. Weekday and
                hour are named, not numbered: "Tuesday" is an observation, "3"
                is an internal code leaking onto a screen. */
            ValueText = CASE
                WHEN raw.ValueNumeric IS NULL THEN N'Not enough logged yet'
                WHEN a.ValueKind = 'weekday' THEN
                    CHOOSE(CAST(raw.ValueNumeric AS INT), N'Sunday', N'Monday',
                           N'Tuesday', N'Wednesday', N'Thursday', N'Friday',
                           N'Saturday')
                WHEN a.ValueKind = 'hour' THEN
                    CONCAT(CAST(raw.ValueNumeric AS INT), N':00')
                WHEN a.ValueKind = 'percent' THEN
                    CONCAT(CAST(raw.ValueNumeric AS DECIMAL(5, 1)), N'%')
                WHEN a.ValueKind = 'probability' THEN
                    CONCAT(CAST(ROUND(raw.ValueNumeric * 100, 0) AS INT), N'%')
                WHEN a.ValueKind = 'days' THEN
                    CONCAT(CAST(raw.ValueNumeric AS INT), N' days')
                ELSE CAST(CAST(raw.ValueNumeric AS INT) AS NVARCHAR(20))
            END,

            /*  Observational wording only. Every sentence here describes what
                was logged and over what period. None of them says what it means
                for her, because that is a conclusion about a person and this
                platform reports what it saw. */
            Reason = CASE
                WHEN raw.ValueNumeric IS NULL THEN N'Nothing to base this on yet.'
                ELSE CONCAT(
                    N'From ', a.ActiveDays, N' active day',
                    CASE WHEN a.ActiveDays = 1 THEN N'' ELSE N's' END,
                    N' across ', a.SpanDays, N' day',
                    CASE WHEN a.SpanDays = 1 THEN N'' ELSE N's' END,
                    N' of history, ending ', CONVERT(VARCHAR(10), a.LastDate, 23),
                    N'.')
            END
    ) v;
GO

-- ---------------------------------------------------------------------------
-- usp_Behaviour_Resolve
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Behaviour.usp_Behaviour_Resolve') IS NOT NULL
    DROP PROCEDURE [Behaviour].[usp_Behaviour_Resolve];
GO
/*  Observe her behaviour and persist it for the day.

    Snapshotted for the same reason the state snapshot is: an observation is
    what the platform believed at the time, and recomputing history on demand
    would let a definition change silently rewrite the past. A coach that said
    "you have improved since March" must be reading what March actually looked
    like.

    Re-running for the same day overwrites that day only, so this is safe to
    call repeatedly - which it will be, because it runs from the pipeline. */
CREATE PROCEDURE [Behaviour].[usp_Behaviour_Resolve]
    @UserId      UNIQUEIDENTIFIER,
    @AsOfDate    DATE = NULL,
    @WindowDays  INT = 56,
    @Persist     BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF @AsOfDate IS NULL SET @AsOfDate = CAST(SYSUTCDATETIME() AS DATE);

    /*  Bounded. An unbounded window is a table scan of one woman's entire
        history on every dashboard load, and the measures that need more than a
        year do not exist. */
    IF @WindowDays IS NULL OR @WindowDays < 7   SET @WindowDays = 7;
    IF @WindowDays > 400                        SET @WindowDays = 400;

    DECLARE @version VARCHAR(20) = '1.0.0';

    DECLARE @observed TABLE (
        SubjectKey VARCHAR(40), MeasureCode VARCHAR(30),
        MeasureName NVARCHAR(80), Family VARCHAR(20),
        ValueKind VARCHAR(12), Unit VARCHAR(20),
        Confidence INT, SpanDays INT, SupportingEventCount INT,
        FirstObservedDate DATE, LastObservedDate DATE, SortOrder INT,
        ValueNumeric DECIMAL(9, 4), ValueText NVARCHAR(80),
        Reason NVARCHAR(600), EvidenceCsv NVARCHAR(400));

    INSERT @observed
    SELECT SubjectKey, MeasureCode, MeasureName, Family, ValueKind, Unit,
           Confidence, SpanDays, SupportingEventCount, FirstObservedDate,
           LastObservedDate, SortOrder, ValueNumeric, ValueText, Reason,
           EvidenceCsv
    FROM [Behaviour].[fn_Observe](@UserId, @AsOfDate, @WindowDays);

    IF @Persist = 1
    BEGIN
        MERGE [Behaviour].[Observation] AS target
        USING (SELECT * FROM @observed) AS source
            ON  target.UserId = @UserId
            AND target.ForLocalDate = @AsOfDate
            AND target.SubjectKey = source.SubjectKey
            AND target.MeasureCode = source.MeasureCode
        WHEN MATCHED THEN UPDATE SET
            ValueNumeric = source.ValueNumeric,
            ValueText = source.ValueText,
            Confidence = source.Confidence,
            SpanDays = source.SpanDays,
            SupportingEventCount = source.SupportingEventCount,
            FirstObservedDate = source.FirstObservedDate,
            LastObservedDate = source.LastObservedDate,
            Reason = source.Reason,
            EvidenceCsv = source.EvidenceCsv,
            EngineVersion = @version,
            ComputedUtc = SYSUTCDATETIME()
        WHEN NOT MATCHED THEN INSERT
            (UserId, SubjectKey, MeasureCode, ForLocalDate, ValueNumeric,
             ValueText, Confidence, SpanDays, SupportingEventCount,
             FirstObservedDate, LastObservedDate, Reason, EvidenceCsv,
             EngineVersion)
        VALUES
            (@UserId, source.SubjectKey, source.MeasureCode, @AsOfDate,
             source.ValueNumeric, source.ValueText, source.Confidence,
             source.SpanDays, source.SupportingEventCount,
             source.FirstObservedDate, source.LastObservedDate, source.Reason,
             source.EvidenceCsv, @version);
    END

    SELECT
        o.SubjectKey,
        s.DisplayName AS SubjectName,
        s.DomainCode,
        s.IsHealthSensitive,
        o.MeasureCode,
        o.MeasureName,
        o.Family,
        o.ValueKind,
        o.Unit,
        o.ValueNumeric,
        o.ValueText,
        o.Confidence,
        o.SpanDays,
        o.SupportingEventCount,
        o.FirstObservedDate,
        o.LastObservedDate,
        o.Reason,
        o.EvidenceCsv,
        @version AS EngineVersion
    FROM @observed o
    JOIN [Behaviour].[Subject] s ON s.SubjectKey = o.SubjectKey
    ORDER BY s.SortOrder, o.SortOrder;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Behaviour_Get
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Behaviour.usp_Behaviour_Get') IS NOT NULL
    DROP PROCEDURE [Behaviour].[usp_Behaviour_Get];
GO
/*  The last snapshot, without recomputing.

    What every consuming engine calls. Reading rather than resolving is
    deliberate: six engines each triggering a recomputation on the same request
    would observe the same woman six times in one page load. */
CREATE PROCEDURE [Behaviour].[usp_Behaviour_Get]
    @UserId   UNIQUEIDENTIFIER,
    @AsOfDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @AsOfDate IS NULL SET @AsOfDate = CAST(SYSUTCDATETIME() AS DATE);

    /*  The most recent day at or before the one asked for. A woman who has not
        opened the app since Friday still has behaviour; pinning to today would
        return nothing and every engine downstream would treat her as new. */
    DECLARE @actual DATE = (
        SELECT MAX(ForLocalDate) FROM [Behaviour].[Observation]
        WHERE UserId = @UserId AND ForLocalDate <= @AsOfDate);

    SELECT
        o.SubjectKey,
        s.DisplayName AS SubjectName,
        s.DomainCode,
        s.IsHealthSensitive,
        o.MeasureCode,
        m.DisplayName AS MeasureName,
        m.Family,
        m.ValueKind,
        m.Unit,
        o.ValueNumeric,
        o.ValueText,
        o.Confidence,
        o.SpanDays,
        o.SupportingEventCount,
        o.FirstObservedDate,
        o.LastObservedDate,
        o.Reason,
        o.EvidenceCsv,
        o.EngineVersion
    FROM [Behaviour].[Observation] o
    JOIN [Behaviour].[Subject] s ON s.SubjectKey = o.SubjectKey
    JOIN [Behaviour].[MeasureType] m ON m.MeasureCode = o.MeasureCode
    WHERE o.UserId = @UserId
      AND o.ForLocalDate = @actual
    ORDER BY s.SortOrder, m.SortOrder;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Behaviour_History
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Behaviour.usp_Behaviour_History') IS NOT NULL
    DROP PROCEDURE [Behaviour].[usp_Behaviour_History];
GO
/*  One measure over time. What a trend line reads, and what lets an operator
    tell a real change in her behaviour from a change in the engine - which is
    why EngineVersion travels with every point. */
CREATE PROCEDURE [Behaviour].[usp_Behaviour_History]
    @UserId      UNIQUEIDENTIFIER,
    @SubjectKey  VARCHAR(40),
    @MeasureCode VARCHAR(30),
    @Days        INT = 30
AS
BEGIN
    SET NOCOUNT ON;

    IF @Days IS NULL OR @Days < 1 SET @Days = 30;
    IF @Days > 365 SET @Days = 365;

    SELECT TOP (@Days)
        o.ForLocalDate,
        o.ValueNumeric,
        o.ValueText,
        o.Confidence,
        o.SpanDays,
        o.SupportingEventCount,
        o.EngineVersion
    FROM [Behaviour].[Observation] o
    WHERE o.UserId = @UserId
      AND o.SubjectKey = @SubjectKey
      AND o.MeasureCode = @MeasureCode
    ORDER BY o.ForLocalDate DESC;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Behaviour_ListSubjects
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Behaviour.usp_Behaviour_ListSubjects') IS NOT NULL
    DROP PROCEDURE [Behaviour].[usp_Behaviour_ListSubjects];
GO
/*  The catalogue, for the portal. Server-driven like every other picker, so a
    subject an operator adds appears without a portal release. */
CREATE PROCEDURE [Behaviour].[usp_Behaviour_ListSubjects]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        s.SubjectKey,
        s.DisplayName,
        s.SubjectKind,
        s.DomainCode,
        s.IsHealthSensitive,
        s.TargetPerDay,
        s.ObservationText,
        s.IsActive,
        (SELECT COUNT(*) FROM [Behaviour].[SubjectEvent] se
         WHERE se.SubjectKey = s.SubjectKey) AS PartCount,
        (SELECT COUNT(*) FROM [Behaviour].[SubjectMeasure] sm
         WHERE sm.SubjectKey = s.SubjectKey) AS MeasureCount,
        ISNULL(STUFF((
            SELECT N',' + se.EventTypeCode
            FROM [Behaviour].[SubjectEvent] se
            WHERE se.SubjectKey = s.SubjectKey
            ORDER BY se.SortOrder, se.EventTypeCode
            FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, N''),
            N'') AS EventTypesCsv
    FROM [Behaviour].[Subject] s
    ORDER BY s.SortOrder, s.SubjectKey;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Behaviour_ListMeasures
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Behaviour.usp_Behaviour_ListMeasures') IS NOT NULL
    DROP PROCEDURE [Behaviour].[usp_Behaviour_ListMeasures];
GO
/*  The measure vocabulary, with the spans that gate it.

    MinSpanDays and FullSpanDays are the honesty controls of the whole engine,
    and an operator cannot reason about a woman's empty behaviour screen without
    seeing them. "She has nine days of history and the weekly rhythm needs
    fourteen" is an answer; "it shows nothing" is a support ticket. */
CREATE PROCEDURE [Behaviour].[usp_Behaviour_ListMeasures]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        m.MeasureCode,
        m.DisplayName,
        m.Family,
        m.ValueKind,
        m.Unit,
        m.MinSpanDays,
        m.FullSpanDays,
        m.UnknownText,
        m.[Description],
        m.IsActive,
        (SELECT COUNT(*) FROM [Behaviour].[SubjectMeasure] sm
         WHERE sm.MeasureCode = m.MeasureCode) AS SubjectCount
    FROM [Behaviour].[MeasureType] m
    ORDER BY m.SortOrder, m.MeasureCode;
END
GO

PRINT 'Behaviour Intelligence procedures ready.';
GO
