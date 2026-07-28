/*  63_Procs_Coach.sql

    Explanation, and only explanation.

    fn_ExplainFrom is the whole of it. It takes recommendations that have
    already been assembled and evidence that has already been observed, chooses
    a voice, and fills in a pattern. It computes nothing, assembles nothing and
    reaches no store - coach_test.sql asserts that against the dependency graph.

    The composition is substitution, not writing. {body} becomes the
    recommendation and {reason} becomes the observations behind it; the rest of
    the pattern is connective phrasing carrying no claim. A tone that dropped
    {reason} is refused by a constraint, so no configuration can produce
    encouragement without evidence.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- fn_SelectTone — which voice, and why
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Coach.fn_SelectTone') IS NOT NULL
    DROP FUNCTION [Coach].[fn_SelectTone];
GO
/*  The tone whose rules the evidence matches, heaviest first, falling back to
    the default.

    Returns the rationale as well as the code, because an operator asking "why
    is it speaking to her like that" needs an answer, and a tone chosen without
    a stated reason is indistinguishable from a tone chosen at random.

    Exactly one row, always. A recommendation with no voice would reach her as
    a bare fact, and the fallback exists so that cannot happen. */
CREATE FUNCTION [Coach].[fn_SelectTone]
    (@Evidence [Recommend].[EvidenceSet] READONLY)
RETURNS TABLE
AS
RETURN
    WITH matched AS (
        SELECT
            tr.ToneCode,
            tr.RationaleText,
            t.Weight,
            ROW_NUMBER() OVER (
                ORDER BY t.Weight DESC, tr.ToneCode, tr.InputKey) AS rn
        FROM [Coach].[ToneRule] tr
        JOIN [Coach].[ToneProfile] t ON t.ToneCode = tr.ToneCode
        JOIN @Evidence e
              ON e.InputKind = tr.InputKind AND e.InputKey = tr.InputKey
        WHERE t.IsActive = 1
          AND CASE
                WHEN tr.Comparison = 'is' THEN 1
                WHEN e.ValueNumeric IS NULL THEN 0
                WHEN tr.Comparison = 'gte' AND e.ValueNumeric >= tr.ThresholdValue THEN 1
                WHEN tr.Comparison = 'lte' AND e.ValueNumeric <= tr.ThresholdValue THEN 1
                ELSE 0
              END = 1
    )
    SELECT TOP 1
        ToneCode,
        RationaleText,
        CAST(1 AS BIT) AS FromRule
    FROM matched
    WHERE rn = 1

    UNION ALL

    SELECT TOP 1
        t.ToneCode,
        N'Nothing about today suggested a different voice.' AS RationaleText,
        CAST(0 AS BIT) AS FromRule
    FROM [Coach].[ToneProfile] t
    WHERE t.IsDefault = 1 AND t.IsActive = 1
      AND NOT EXISTS (SELECT 1 FROM matched);
GO

-- ---------------------------------------------------------------------------
-- fn_ExplainFrom — the only explanation logic
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Coach.fn_ExplainFrom') IS NOT NULL
    DROP FUNCTION [Coach].[fn_ExplainFrom];
GO
/*  One message per recommendation, in the voice the evidence called for.

    Given no recommendations this returns nothing, and that is the strongest
    statement of what the coach is: with nothing to explain it says nothing. It
    has no other source of things to say.

    Confidence and evidence are carried through from the recommendation
    unchanged. The coach observes nothing, so it has none of its own to add. */
CREATE FUNCTION [Coach].[fn_ExplainFrom]
    (@Recommendations [Coach].[ExplainSet]   READONLY,
     @Evidence        [Recommend].[EvidenceSet] READONLY,
     @LifetimeHours   INT)
RETURNS TABLE
AS
RETURN
    SELECT
        r.RecommendationKey,
        r.DisplayName,
        tone.ToneCode,
        t.DisplayName AS ToneName,
        tone.RationaleText AS ToneRationale,
        tone.FromRule AS ToneFromRule,

        /*  Substitution, not composition. Every fact in the result came from
            the recommendation; the pattern contributes only connective
            phrasing, and a constraint refuses one that drops {reason}. */
        LTRIM(RTRIM(REPLACE(REPLACE(t.Pattern, '{body}', r.BodyText),
                            '{reason}', r.Reason))) AS MessageText,

        r.Priority,
        r.Confidence,
        r.ExpectedEffort,
        r.EvidenceCsv,
        DATEADD(HOUR, @LifetimeHours, SYSUTCDATETIME()) AS ExpiresUtc
    FROM @Recommendations r
    CROSS JOIN [Coach].[fn_SelectTone](@Evidence) tone
    JOIN [Coach].[ToneProfile] t ON t.ToneCode = tone.ToneCode;
GO

-- ---------------------------------------------------------------------------
-- usp_Coach_Resolve
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Coach.usp_Coach_Resolve') IS NOT NULL
    DROP PROCEDURE [Coach].[usp_Coach_Resolve];
GO
/*  Explain what the platform is already suggesting to her.

    Reads Recommend.Assembled rather than reassembling. That is the whole
    boundary: a coach that called fn_Assemble would be a second opinion about
    the same woman, and the two could disagree the moment a threshold changed
    between the calls.

    The tone evidence comes from the same published interfaces Recommend used,
    because the voice should suit the day the suggestion was made for. */
CREATE PROCEDURE [Coach].[usp_Coach_Resolve]
    @UserId   UNIQUEIDENTIFIER,
    @AsOfDate DATE = NULL,
    @Persist  BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF @AsOfDate IS NULL SET @AsOfDate = CAST(SYSUTCDATETIME() AS DATE);

    DECLARE @version VARCHAR(20) = '1.0.0';
    DECLARE @lifetimeHours INT = 24;

    DECLARE @recs [Coach].[ExplainSet];
    DECLARE @evidence [Recommend].[EvidenceSet];

    /*  Already assembled, and not expired. Explaining a suggestion that has
        lapsed would be the coach talking about a day that has gone. */
    INSERT @recs (RecommendationKey, DisplayName, BodyText, Reason, EvidenceCsv,
                  Priority, Confidence, ExpectedEffort)
    SELECT a.RecommendationKey, t.DisplayName, t.BodyText, a.Reason,
           a.EvidenceCsv, a.Priority, a.Confidence, t.ExpectedEffort
    FROM [Recommend].[Assembled] a
    JOIN [Recommend].[RecommendationType] t
          ON t.RecommendationKey = a.RecommendationKey
    WHERE a.UserId = @UserId
      AND a.ForLocalDate = @AsOfDate
      AND a.ExpiresUtc > SYSUTCDATETIME();

    /*  Tone evidence, from the published interfaces. Behaviour and state only:
        the voice is about how she is today, and goals already reach the coach
        through the recommendations themselves. */
    INSERT @evidence (InputKind, InputKey, ValueNumeric, Confidence)
    SELECT 'behaviour', b.SubjectKey + '.' + b.MeasureCode, b.ValueNumeric, b.Confidence
    FROM [Behaviour].[fn_Read](@UserId, @AsOfDate) b;

    INSERT @evidence (InputKind, InputKey, ValueNumeric, Confidence)
    SELECT 'state', st.DimensionCode + '.' + st.ValueCode, st.Score, st.Confidence
    FROM [Intelligence].[fn_ResolveState](@UserId, @AsOfDate, 14) st
    WHERE st.ValueCode <> 'unknown'
      AND NOT EXISTS (SELECT 1 FROM @evidence e
                      WHERE e.InputKind = 'state'
                        AND e.InputKey = st.DimensionCode + '.' + st.ValueCode);

    /*  Whether any goal of hers is nearly done. Derived once, here, exactly as
        Recommend derives it - the same shape so a tone rule and an assembly
        rule mean the same thing by 'nearly_there'. */
    INSERT @evidence (InputKind, InputKey, ValueNumeric, Confidence)
    SELECT 'goal', 'nearly_there', MAX(g.ProgressPercent), MAX(g.Confidence)
    FROM [Growth].[fn_ResolveGoals](@UserId, @AsOfDate) g
    WHERE g.ProgressPercent >= 70 AND g.IsComplete = 0
    HAVING COUNT(*) > 0;

    DECLARE @explained TABLE (
        RecommendationKey VARCHAR(40), DisplayName NVARCHAR(80),
        ToneCode VARCHAR(30), ToneName NVARCHAR(60),
        ToneRationale NVARCHAR(200), ToneFromRule BIT,
        MessageText NVARCHAR(1200), Priority INT, Confidence INT,
        ExpectedEffort TINYINT, EvidenceCsv NVARCHAR(600),
        ExpiresUtc DATETIME2(3));

    INSERT @explained
    SELECT RecommendationKey, DisplayName, ToneCode, ToneName, ToneRationale,
           ToneFromRule, MessageText, Priority, Confidence, ExpectedEffort,
           EvidenceCsv, ExpiresUtc
    FROM [Coach].[fn_ExplainFrom](@recs, @evidence, @lifetimeHours);

    IF @Persist = 1
    BEGIN
        MERGE [Coach].[Explained] AS target
        USING (SELECT * FROM @explained) AS source
            ON  target.UserId = @UserId
            AND target.ForLocalDate = @AsOfDate
            AND target.RecommendationKey = source.RecommendationKey
        WHEN MATCHED THEN UPDATE SET
            ToneCode = source.ToneCode,
            MessageText = source.MessageText,
            ToneRationale = source.ToneRationale,
            EvidenceCsv = source.EvidenceCsv,
            Confidence = source.Confidence,
            ExpiresUtc = source.ExpiresUtc,
            EngineVersion = @version,
            ComputedUtc = SYSUTCDATETIME()
        WHEN NOT MATCHED THEN INSERT
            (UserId, RecommendationKey, ForLocalDate, ToneCode, MessageText,
             ToneRationale, EvidenceCsv, Confidence, ExpiresUtc, EngineVersion)
        VALUES
            (@UserId, source.RecommendationKey, @AsOfDate, source.ToneCode,
             source.MessageText, source.ToneRationale, source.EvidenceCsv,
             source.Confidence, source.ExpiresUtc, @version);
    END

    SELECT RecommendationKey, DisplayName, ToneCode, ToneName, ToneRationale,
           ToneFromRule, MessageText, Priority, Confidence, ExpectedEffort,
           EvidenceCsv, ExpiresUtc, @version AS EngineVersion
    FROM @explained
    ORDER BY Priority DESC, RecommendationKey;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Coach_Get
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Coach.usp_Coach_Get') IS NOT NULL
    DROP PROCEDURE [Coach].[usp_Coach_Get];
GO
/*  What was said to her, and has not lapsed. */
CREATE PROCEDURE [Coach].[usp_Coach_Get]
    @UserId   UNIQUEIDENTIFIER,
    @AsOfDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @AsOfDate IS NULL SET @AsOfDate = CAST(SYSUTCDATETIME() AS DATE);

    SELECT
        e.RecommendationKey,
        t.DisplayName,
        e.ToneCode,
        tp.DisplayName AS ToneName,
        e.ToneRationale,
        CAST(1 AS BIT) AS ToneFromRule,
        e.MessageText,
        a.Priority,
        e.Confidence,
        t.ExpectedEffort,
        e.EvidenceCsv,
        e.ExpiresUtc,
        e.EngineVersion
    FROM [Coach].[Explained] e
    JOIN [Coach].[ToneProfile] tp ON tp.ToneCode = e.ToneCode
    JOIN [Recommend].[RecommendationType] t
          ON t.RecommendationKey = e.RecommendationKey
    LEFT JOIN [Recommend].[Assembled] a
          ON a.UserId = e.UserId AND a.ForLocalDate = e.ForLocalDate
         AND a.RecommendationKey = e.RecommendationKey
    WHERE e.UserId = @UserId
      AND e.ForLocalDate = @AsOfDate
      AND e.ExpiresUtc > SYSUTCDATETIME()
    ORDER BY a.Priority DESC, e.RecommendationKey;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Coach_ListTones
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Coach.usp_Coach_ListTones') IS NOT NULL
    DROP PROCEDURE [Coach].[usp_Coach_ListTones];
GO
/*  The tone library, for operators. Configuration, not anybody's data.

    Carries the rule count, because a tone with no rules can only ever be the
    default - and a non-default tone with no rules is a voice the platform will
    never use, which looks identical to one nobody qualifies for. */
CREATE PROCEDURE [Coach].[usp_Coach_ListTones]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        t.ToneCode,
        t.DisplayName,
        t.[Description],
        t.Pattern,
        t.Weight,
        t.IsDefault,
        t.IsActive,
        (SELECT COUNT(*) FROM [Coach].[ToneRule] r
         WHERE r.ToneCode = t.ToneCode) AS RuleCount,
        ISNULL(STUFF((
            SELECT N'; ' + r.InputKind + N':' + r.InputKey
                 + CASE WHEN r.Comparison = 'is' THEN N''
                        ELSE N' ' + r.Comparison + N' '
                           + CAST(CAST(r.ThresholdValue AS DECIMAL(9,1)) AS NVARCHAR(20)) END
            FROM [Coach].[ToneRule] r
            WHERE r.ToneCode = t.ToneCode
            ORDER BY r.InputKind, r.InputKey
            FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, N''),
            N'') AS RulesText
    FROM [Coach].[ToneProfile] t
    ORDER BY t.SortOrder, t.ToneCode;
END
GO

PRINT 'Coach Platform — procedures ready.';
GO
