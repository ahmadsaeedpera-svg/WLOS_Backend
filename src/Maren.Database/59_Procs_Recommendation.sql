/*  59_Procs_Recommendation.sql

    Assembly, and only assembly.

    fn_AssembleFrom is the whole of the logic and it reads one thing: an
    evidence set. It does not know whether that evidence came from a real
    woman's engines or from an operator describing a hypothetical, which is what
    lets the Decision Inspector show real recommendations without a second
    implementation - the same split Behaviour.fn_Measure already has.

    fn_Assemble gathers the real evidence. It reads only published interfaces:
    Behaviour.fn_Read, Growth.fn_ResolveGoals, Growth.fn_ResolveRoutines,
    Knowledge.fn_EvaluateSignals and Intelligence.fn_ResolveState. It touches
    Timeline.Event, Behaviour.Observation and the snapshot tables never;
    recommendation_test.sql asserts that against the dependency graph rather
    than against the text, because a textual guard is defeated by formatting.

    Nothing here computes a streak, a consistency figure or a probability. It
    compares values other engines published against thresholds an operator
    configured. That is what assembly means.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- fn_ParseEvidence — the operator-facing evidence shorthand
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Recommend.fn_ParseEvidence') IS NOT NULL
    DROP FUNCTION [Recommend].[fn_ParseEvidence];
GO
/*  Turns "behaviour:hydration.consistency=40, signal:low_hydration" into an
    evidence set.

    A function rather than parsing inline in the inspector, so the shorthand has
    one definition and can be tested directly. The inspector returns two result
    sets - what assembled, and every input with whether it matched - and
    INSERT ... EXEC takes only the first, so a T-SQL assertion cannot consume it.
    Extracting the parse lets the suite verify shorthand and assembly together
    without a second copy of either.

    Malformed entries are dropped rather than refused: an operator mid-edit
    should see a partial answer, not an error. */
CREATE FUNCTION [Recommend].[fn_ParseEvidence]
    (@EvidenceCsv NVARCHAR(MAX), @Confidence INT)
RETURNS TABLE
AS
RETURN
    SELECT DISTINCT
        LEFT(part, CHARINDEX(':', part) - 1) AS InputKind,
        CASE WHEN CHARINDEX('=', part) > 0
             THEN SUBSTRING(part, CHARINDEX(':', part) + 1,
                            CHARINDEX('=', part) - CHARINDEX(':', part) - 1)
             ELSE SUBSTRING(part, CHARINDEX(':', part) + 1, 200) END AS InputKey,
        CASE WHEN CHARINDEX('=', part) > 0
             THEN TRY_CAST(SUBSTRING(part, CHARINDEX('=', part) + 1, 40) AS DECIMAL(9, 4))
             ELSE NULL END AS ValueNumeric,
        CASE WHEN @Confidence IS NULL THEN 100
             WHEN @Confidence < 0 THEN 0
             WHEN @Confidence > 100 THEN 100
             ELSE @Confidence END AS Confidence
    FROM (
        SELECT LTRIM(RTRIM(s.[value])) AS part
        FROM STRING_SPLIT(ISNULL(@EvidenceCsv, N''), ',') s
    ) p
    WHERE CHARINDEX(':', part) > 1
      AND LEN(part) > CHARINDEX(':', part);
GO

-- ---------------------------------------------------------------------------
-- fn_AssembleFrom — the only assembly logic
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Recommend.fn_AssembleFrom') IS NOT NULL
    DROP FUNCTION [Recommend].[fn_AssembleFrom];
GO
/*  Which recommendations this evidence supports, and why each one.

    A recommendation is eligible when every one of its required inputs matches.
    Its priority is the base plus the weight of what matched, capped; its
    confidence is the weighted mean of the confidences of the matching inputs,
    so a suggestion resting on thin history reports thin confidence; its
    reasoning is the sentences of the inputs that matched, joined.

    A recommendation with no matching input at all is not returned. Assembled
    from nothing is a guess, and the schema refuses to store one. */
CREATE FUNCTION [Recommend].[fn_AssembleFrom]
    (@Evidence [Recommend].[EvidenceSet] READONLY,
     @AsOfDate DATE)
RETURNS TABLE
AS
RETURN
    WITH matched AS (
        SELECT
            ri.RecommendationKey,
            ri.InputKind,
            ri.InputKey,
            ri.IsRequired,
            ri.Weight,
            ri.ReasonText,
            ri.SortOrder,
            e.Confidence,
            CAST(CASE
                /*  Presence. Signals, routines and goal states are things that
                    are either true of her right now or not. */
                WHEN ri.Comparison = 'is' THEN 1
                WHEN e.ValueNumeric IS NULL THEN 0
                WHEN ri.Comparison = 'gte' AND e.ValueNumeric >= ri.ThresholdValue THEN 1
                WHEN ri.Comparison = 'lte' AND e.ValueNumeric <= ri.ThresholdValue THEN 1
                ELSE 0
            END AS BIT) AS IsMatch
        FROM [Recommend].[RecommendationInput] ri
        JOIN @Evidence e
              ON e.InputKind = ri.InputKind AND e.InputKey = ri.InputKey
    ),
    required AS (
        SELECT RecommendationKey, COUNT(*) AS RequiredCount
        FROM [Recommend].[RecommendationInput]
        WHERE IsRequired = 1
        GROUP BY RecommendationKey
    ),
    requiredMet AS (
        SELECT RecommendationKey, COUNT(*) AS MetCount
        FROM matched
        WHERE IsRequired = 1 AND IsMatch = 1
        GROUP BY RecommendationKey
    ),
    rolled AS (
        SELECT
            m.RecommendationKey,
            SUM(m.Weight) AS MatchedWeight,
            COUNT(*) AS MatchedCount,
            SUM(m.Confidence * m.Weight) / NULLIF(SUM(m.Weight), 0) AS Confidence
        FROM matched m
        WHERE m.IsMatch = 1
        GROUP BY m.RecommendationKey
    )

    SELECT
        t.RecommendationKey,
        t.DisplayName,
        t.DomainCode,
        t.BodyText,
        t.IsHealthSensitive,
        t.ExpectedBenefit,
        t.ExpectedEffort,
        t.LifetimeHours,

        /*  Base plus what matched, capped at 100. Weight raises a suggestion
            that several observations agree on above one that rests on a single
            reading, which is the only ordering the platform can honestly
            defend. */
        CASE WHEN t.BasePriority + r.MatchedWeight > 100 THEN 100
             ELSE t.BasePriority + r.MatchedWeight END AS Priority,

        CAST(ROUND(r.Confidence, 0) AS INT) AS Confidence,
        r.MatchedCount,

        /*  Expiry travels with the recommendation. A suggestion about tonight
            is wrong tomorrow.

            Measured from when it was assembled, not from midnight of the date.
            Basing it on the date meant a twelve-hour suggestion assembled at
            six in the evening had expired six hours before it was made, so
            nothing survived to be read - which is exactly what an integration
            test found. Lifetime is how long a suggestion stays true after the
            platform makes it. */
        DATEADD(HOUR, t.LifetimeHours, SYSUTCDATETIME()) AS ExpiresUtc,

        /*  The sentences of what matched, in configured order. This is the
            whole answer to "why am I being told this", and every clause of it
            is something she logged. */
        ISNULL(STUFF((
            SELECT N' ' + m.ReasonText
            FROM matched m
            WHERE m.RecommendationKey = t.RecommendationKey AND m.IsMatch = 1
            ORDER BY m.SortOrder, m.Weight DESC, m.InputKey
            FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, N''),
            N'') AS Reason,

        ISNULL(STUFF((
            SELECT N',' + m.InputKind + N':' + m.InputKey
            FROM matched m
            WHERE m.RecommendationKey = t.RecommendationKey AND m.IsMatch = 1
            ORDER BY m.InputKind, m.InputKey
            FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, N''),
            N'') AS EvidenceCsv,

        /*  Which engines contributed, so a client can say "from your sleep and
            your goal" without parsing the evidence. */
        ISNULL(STUFF((
            SELECT N',' + k.InputKind
            FROM (SELECT DISTINCT m.InputKind
                  FROM matched m
                  WHERE m.RecommendationKey = t.RecommendationKey AND m.IsMatch = 1) k
            ORDER BY k.InputKind
            FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, N''),
            N'') AS EnginesCsv

    FROM [Recommend].[RecommendationType] t
    JOIN rolled r ON r.RecommendationKey = t.RecommendationKey
    JOIN required req ON req.RecommendationKey = t.RecommendationKey
    JOIN requiredMet met ON met.RecommendationKey = t.RecommendationKey
    WHERE t.IsActive = 1
      /*  Every required input matched. One unmet requirement means the
          recommendation is not true of her, however much else lined up. */
      AND met.MetCount = req.RequiredCount
      /*  And something was actually observed. */
      AND CAST(ROUND(r.Confidence, 0) AS INT) > 0;
GO

-- ---------------------------------------------------------------------------
-- fn_Assemble — the real path
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Recommend.fn_Assemble') IS NOT NULL
    DROP FUNCTION [Recommend].[fn_Assemble];
GO
/*  Gathers what the engines currently say about her, then assembles.

    Every read here goes through a published interface. This function is the
    single place the five vocabularies are translated into one evidence shape,
    so the assembly rules never have to know that a behaviour key is
    "subject.measure" while a signal key is a bare code.

    A multi-statement function because the evidence has to be materialised
    before it can be passed as a table-valued parameter. Still a function, so it
    composes and INSERT ... EXEC nesting is not a trap. */
CREATE FUNCTION [Recommend].[fn_Assemble]
    (@UserId UNIQUEIDENTIFIER, @AsOfDate DATE)
RETURNS @out TABLE (
    RecommendationKey VARCHAR(40),
    DisplayName       NVARCHAR(80),
    DomainCode        VARCHAR(30),
    BodyText          NVARCHAR(400),
    IsHealthSensitive BIT,
    ExpectedBenefit   TINYINT,
    ExpectedEffort    TINYINT,
    LifetimeHours     INT,
    Priority          INT,
    Confidence        INT,
    MatchedCount      INT,
    ExpiresUtc        DATETIME2(3),
    Reason            NVARCHAR(1000),
    EvidenceCsv       NVARCHAR(600),
    EnginesCsv        NVARCHAR(200))
AS
BEGIN
    DECLARE @evidence [Recommend].[EvidenceSet];

    /*  Behaviour. Keyed "subject.measure" so one row can carry any measure of
        any subject without the assembly rules learning the vocabulary. */
    INSERT @evidence (InputKind, InputKey, ValueNumeric, Confidence)
    SELECT 'behaviour', b.SubjectKey + '.' + b.MeasureCode,
           b.ValueNumeric, b.Confidence
    FROM [Behaviour].[fn_Read](@UserId, @AsOfDate) b;

    /*  Signals. Presence, so confidence is full: the knowledge engine either
        raised it or it did not. */
    INSERT @evidence (InputKind, InputKey, ValueNumeric, Confidence)
    SELECT 'signal', s.SignalCode, NULL, 100
    FROM [Knowledge].[fn_EvaluateSignals](@UserId, @AsOfDate) s
    WHERE NOT EXISTS (SELECT 1 FROM @evidence e
                      WHERE e.InputKind = 'signal' AND e.InputKey = s.SignalCode);

    /*  State. The value code is the key, so "energy is low" is
        state:energy.low rather than a magnitude to threshold. */
    INSERT @evidence (InputKind, InputKey, ValueNumeric, Confidence)
    SELECT 'state', st.DimensionCode + '.' + st.ValueCode, st.Score, st.Confidence
    FROM [Intelligence].[fn_ResolveState](@UserId, @AsOfDate, 14) st
    WHERE st.ValueCode <> 'unknown'
      AND NOT EXISTS (SELECT 1 FROM @evidence e
                      WHERE e.InputKind = 'state'
                        AND e.InputKey = st.DimensionCode + '.' + st.ValueCode);

    /*  Goals. Two shapes: the goal itself, keyed by template, carrying its
        progress; and the derived 'nearly_there', which is the thing an
        encouragement actually keys on and which every consumer would otherwise
        recompute from a percentage. */
    INSERT @evidence (InputKind, InputKey, ValueNumeric, Confidence)
    SELECT 'goal', g.GoalTemplateKey, g.ProgressPercent, g.Confidence
    FROM [Growth].[fn_ResolveGoals](@UserId, @AsOfDate) g
    WHERE NOT EXISTS (SELECT 1 FROM @evidence e
                      WHERE e.InputKind = 'goal' AND e.InputKey = g.GoalTemplateKey);

    /*  HAVING COUNT(*) > 0 is load-bearing. An aggregate with no GROUP BY
        returns one row even when nothing matched, so without it a woman with no
        nearly-finished goal got a 'nearly_there' row of NULLs - and the
        evidence set refuses a null confidence, which took the whole assembly
        down rather than quietly suggesting nothing. */
    INSERT @evidence (InputKind, InputKey, ValueNumeric, Confidence)
    SELECT 'goal', 'nearly_there', MAX(g.ProgressPercent), MAX(g.Confidence)
    FROM [Growth].[fn_ResolveGoals](@UserId, @AsOfDate) g
    WHERE g.ProgressPercent >= 70 AND g.IsComplete = 0
    HAVING COUNT(*) > 0;

    /*  Routines. Presence of an unfinished one she actually has set up. */
    INSERT @evidence (InputKind, InputKey, ValueNumeric, Confidence)
    SELECT 'routine', r.RoutineKey,
           CASE WHEN r.IsDoneToday = 1 THEN 1 ELSE 0 END, 100
    FROM [Growth].[fn_ResolveRoutines](@UserId, @AsOfDate) r
    WHERE NOT EXISTS (SELECT 1 FROM @evidence e
                      WHERE e.InputKind = 'routine' AND e.InputKey = r.RoutineKey);

    INSERT @out
    SELECT RecommendationKey, DisplayName, DomainCode, BodyText,
           IsHealthSensitive, ExpectedBenefit, ExpectedEffort, LifetimeHours,
           Priority, Confidence, MatchedCount, ExpiresUtc, Reason, EvidenceCsv,
           EnginesCsv
    FROM [Recommend].[fn_AssembleFrom](@evidence, @AsOfDate);

    RETURN;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Recommendation_Resolve
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Recommend.usp_Recommendation_Resolve') IS NOT NULL
    DROP PROCEDURE [Recommend].[usp_Recommendation_Resolve];
GO
/*  Assemble and persist for the day.

    Applicability is applied here rather than inside the assembly, so that the
    reasoning stays about her observations and the question of who a
    recommendation is for stays with Rules - the platform's one matcher. */
CREATE PROCEDURE [Recommend].[usp_Recommendation_Resolve]
    @UserId      UNIQUEIDENTIFIER,
    @AsOfDate    DATE = NULL,
    @ContextJson NVARCHAR(MAX) = NULL,
    @Persist     BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF @AsOfDate IS NULL SET @AsOfDate = CAST(SYSUTCDATETIME() AS DATE);

    DECLARE @version VARCHAR(20) = '1.0.0';

    DECLARE @assembled TABLE (
        RecommendationKey VARCHAR(40), DisplayName NVARCHAR(80),
        DomainCode VARCHAR(30), BodyText NVARCHAR(400),
        IsHealthSensitive BIT, ExpectedBenefit TINYINT, ExpectedEffort TINYINT,
        LifetimeHours INT, Priority INT, Confidence INT, MatchedCount INT,
        ExpiresUtc DATETIME2(3), Reason NVARCHAR(1000),
        EvidenceCsv NVARCHAR(600), EnginesCsv NVARCHAR(200));

    INSERT @assembled
    SELECT a.RecommendationKey, a.DisplayName, a.DomainCode, a.BodyText,
           a.IsHealthSensitive, a.ExpectedBenefit, a.ExpectedEffort,
           a.LifetimeHours, a.Priority, a.Confidence, a.MatchedCount,
           a.ExpiresUtc, a.Reason, a.EvidenceCsv, a.EnginesCsv
    FROM [Recommend].[fn_Assemble](@UserId, @AsOfDate) a
    WHERE NOT EXISTS (SELECT 1 FROM [Rules].[Rule] x
                      WHERE x.ScopeCode = 'recommendation'
                        AND x.TargetKey = a.RecommendationKey)
       OR EXISTS (SELECT 1 FROM [Rules].[fn_Match]('recommendation', @ContextJson) m
                  WHERE m.TargetKey = a.RecommendationKey);

    IF @Persist = 1
    BEGIN
        MERGE [Recommend].[Assembled] AS target
        USING (SELECT * FROM @assembled) AS source
            ON  target.UserId = @UserId
            AND target.ForLocalDate = @AsOfDate
            AND target.RecommendationKey = source.RecommendationKey
        WHEN MATCHED THEN UPDATE SET
            Priority = source.Priority,
            Confidence = source.Confidence,
            Reason = source.Reason,
            EvidenceCsv = source.EvidenceCsv,
            EnginesCsv = source.EnginesCsv,
            ExpiresUtc = source.ExpiresUtc,
            EngineVersion = @version,
            ComputedUtc = SYSUTCDATETIME()
        WHEN NOT MATCHED THEN INSERT
            (UserId, RecommendationKey, ForLocalDate, Priority, Confidence,
             Reason, EvidenceCsv, EnginesCsv, ExpiresUtc, EngineVersion)
        VALUES
            (@UserId, source.RecommendationKey, @AsOfDate, source.Priority,
             source.Confidence, source.Reason, source.EvidenceCsv,
             source.EnginesCsv, source.ExpiresUtc, @version);
    END

    SELECT RecommendationKey, DisplayName, DomainCode, BodyText,
           IsHealthSensitive, ExpectedBenefit, ExpectedEffort, Priority,
           Confidence, MatchedCount, ExpiresUtc, Reason, EvidenceCsv,
           EnginesCsv, @version AS EngineVersion
    FROM @assembled
    ORDER BY Priority DESC, RecommendationKey;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Recommendation_Get
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Recommend.usp_Recommendation_Get') IS NOT NULL
    DROP PROCEDURE [Recommend].[usp_Recommendation_Get];
GO
/*  What was assembled and has not expired.

    Expiry is applied on read as well as stored, because a client that opened
    the app at 23:58 and again at 00:02 must not be shown a suggestion about
    yesterday evening. */
CREATE PROCEDURE [Recommend].[usp_Recommendation_Get]
    @UserId   UNIQUEIDENTIFIER,
    @AsOfDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @AsOfDate IS NULL SET @AsOfDate = CAST(SYSUTCDATETIME() AS DATE);

    SELECT
        a.RecommendationKey,
        t.DisplayName,
        t.DomainCode,
        t.BodyText,
        t.IsHealthSensitive,
        t.ExpectedBenefit,
        t.ExpectedEffort,
        a.Priority,
        a.Confidence,
        a.Reason,
        a.EvidenceCsv,
        a.EnginesCsv,
        a.ExpiresUtc,
        a.EngineVersion
    FROM [Recommend].[Assembled] a
    JOIN [Recommend].[RecommendationType] t
          ON t.RecommendationKey = a.RecommendationKey
    WHERE a.UserId = @UserId
      AND a.ForLocalDate = @AsOfDate
      AND a.ExpiresUtc > SYSUTCDATETIME()
    ORDER BY a.Priority DESC, a.RecommendationKey;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Recommendation_ListTemplates
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Recommend.usp_Recommendation_ListTemplates') IS NOT NULL
    DROP PROCEDURE [Recommend].[usp_Recommendation_ListTemplates];
GO
/*  The catalogue, for operators. Configuration, not anybody's data.

    Carries the required-input count, because a recommendation with no required
    input is offered to everyone the moment any optional input matches - which
    is almost never what somebody meant. */
CREATE PROCEDURE [Recommend].[usp_Recommendation_ListTemplates]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        t.RecommendationKey,
        t.DisplayName,
        t.DomainCode,
        t.BodyText,
        t.BasePriority,
        t.ExpectedBenefit,
        t.ExpectedEffort,
        t.LifetimeHours,
        t.IsHealthSensitive,
        t.IsActive,
        (SELECT COUNT(*) FROM [Recommend].[RecommendationInput] i
         WHERE i.RecommendationKey = t.RecommendationKey) AS InputCount,
        (SELECT COUNT(*) FROM [Recommend].[RecommendationInput] i
         WHERE i.RecommendationKey = t.RecommendationKey AND i.IsRequired = 1)
            AS RequiredCount,
        (SELECT COUNT(*) FROM [Rules].[Rule] x
         WHERE x.ScopeCode = 'recommendation' AND x.TargetKey = t.RecommendationKey)
            AS RuleCount,
        ISNULL(STUFF((
            SELECT N'; ' + i.InputKind + N':' + i.InputKey
                 + CASE WHEN i.Comparison = 'is' THEN N''
                        ELSE N' ' + i.Comparison + N' '
                           + CAST(CAST(i.ThresholdValue AS DECIMAL(9,1)) AS NVARCHAR(20)) END
                 + CASE WHEN i.IsRequired = 1 THEN N' (required)' ELSE N'' END
            FROM [Recommend].[RecommendationInput] i
            WHERE i.RecommendationKey = t.RecommendationKey
            ORDER BY i.IsRequired DESC, i.SortOrder, i.InputKey
            FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, N''),
            N'') AS InputsText
    FROM [Recommend].[RecommendationType] t
    ORDER BY t.SortOrder, t.RecommendationKey;
END
GO

PRINT 'Recommendation Platform — procedures ready.';
GO
