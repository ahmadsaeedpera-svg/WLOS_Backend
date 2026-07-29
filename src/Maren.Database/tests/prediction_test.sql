SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Prediction Platform.

    A prediction is framed, never computed. The assertions here are about the
    two properties that are easy to lose and expensive to lose quietly.

    The first is that this engine invents no number. Behaviour observes three
    probabilities; prediction attaches a window to one of them and says it out
    loud. That is made structural: a PredictionType carries a SourceFamily
    pinned to 'probability' by a constraint, and the (code, family) pair is a
    foreign key into Behaviour.MeasureType. There is no configuration that
    points a prediction at a measure Behaviour does not publish as a
    probability, and no code path that produces one.

    The second is that it never states a likelihood bare. A framing pattern
    must carry {chance}, {window} and {support}; a CHECK refuses one that drops
    any of them. "70%" with no window and no history behind it reads as
    knowledge, and it is a summary of three weeks.

    The rest follows: given nothing observed it predicts nothing; under either
    floor it withholds rather than hedges; and the shorthand an operator types
    reaches the same implementation the live path does.

    Run: sqlcmd -S "$SERVER" -d "$DB" -i tests/prediction_test.sql -I
    Expect: TOTAL: 20  FAILED: 0

    Re-runnable: owns nothing persistent. Rows inserted to prove a constraint
    bites are removed again on the path where the constraint failed to bite.
*/

SET NOCOUNT ON;

DECLARE @results TABLE (Seq INT IDENTITY(1,1), Assertion NVARCHAR(200),
                        Detail NVARCHAR(200), Outcome CHAR(4));

DECLARE @n INT, @t NVARCHAR(600), @ok BIT, @pct INT;

DECLARE @obs [Predict].[ObservationSet];

DECLARE @out TABLE (
    PredictionKey VARCHAR(40), DisplayName NVARCHAR(80), SubjectKey VARCHAR(40),
    SubjectName NVARCHAR(80), HorizonCode VARCHAR(20), HorizonName NVARCHAR(60),
    WindowDays INT, ProbabilityPercent INT, SupportDays INT, Confidence INT,
    StatementText NVARCHAR(600), EvidenceCsv NVARCHAR(600),
    SourceMeasureCode VARCHAR(30), ExpiresUtc DATETIME2(3));

-- 1 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Predict].[PredictionType] WHERE IsActive = 1;
INSERT @results VALUES ('the prediction catalogue is seeded',
    CONCAT(@n, ' types'),
    CASE WHEN @n >= 3 THEN 'PASS' ELSE 'FAIL' END);

-- 2 -------------------------------------------------------------------------
/*  The honesty guard, at rest. Every framing must carry all three. */
SELECT @n = COUNT(*) FROM [Predict].[PredictionType]
WHERE FramingPattern NOT LIKE '%{chance}%'
   OR FramingPattern NOT LIKE '%{window}%'
   OR FramingPattern NOT LIKE '%{support}%';
INSERT @results VALUES ('every framing keeps chance, window and support',
    CONCAT(@n, ' lossy'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 3 -------------------------------------------------------------------------
/*  And the schema refuses one that drops the support, so no configuration can
    state a likelihood with nothing behind it. */
BEGIN TRY
    INSERT [Predict].[PredictionType] (PredictionKey, DisplayName, [Description],
        HorizonCode, SourceMeasureCode, FramingPattern, MinConfidence,
        MinSupportDays, LifetimeHours, SortOrder)
    VALUES ('zz_no_support', N'Bad', N'x', 'tomorrow', 'completion_probability',
            N'There is a {chance} chance {window}.', 40, 14, 24, 999);
    SET @ok = 1;
    DELETE [Predict].[PredictionType] WHERE PredictionKey = 'zz_no_support';
END TRY
BEGIN CATCH
    SET @ok = 0;
END CATCH
INSERT @results VALUES ('the schema refuses a framing with no support',
    CASE WHEN @ok = 1 THEN 'accepted' ELSE 'refused' END,
    CASE WHEN @ok = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 4 -------------------------------------------------------------------------
/*  And one that drops the window. A likelihood about no particular time cannot
    be wrong, which is the same as saying it is not a prediction. */
BEGIN TRY
    INSERT [Predict].[PredictionType] (PredictionKey, DisplayName, [Description],
        HorizonCode, SourceMeasureCode, FramingPattern, MinConfidence,
        MinSupportDays, LifetimeHours, SortOrder)
    VALUES ('zz_no_window', N'Bad', N'x', 'tomorrow', 'completion_probability',
            N'{chance} of days, based on {support}.', 40, 14, 24, 999);
    SET @ok = 1;
    DELETE [Predict].[PredictionType] WHERE PredictionKey = 'zz_no_window';
END TRY
BEGIN CATCH
    SET @ok = 0;
END CATCH
INSERT @results VALUES ('the schema refuses a framing with no window',
    CASE WHEN @ok = 1 THEN 'accepted' ELSE 'refused' END,
    CASE WHEN @ok = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 5 -------------------------------------------------------------------------
/*  The structural half of "never recomputes", proved rather than described.

    'consistency' is a real, active measure of a real subject. The only reason
    this insert fails is that Behaviour publishes it as a habit measure rather
    than as a probability, and the foreign key carries the family. */
BEGIN TRY
    INSERT [Predict].[PredictionType] (PredictionKey, DisplayName, [Description],
        HorizonCode, SourceMeasureCode, FramingPattern, MinConfidence,
        MinSupportDays, LifetimeHours, SortOrder)
    VALUES ('zz_bad_source', N'Bad', N'x', 'tomorrow', 'consistency',
            N'{chance} {window} {support}', 40, 14, 24, 999);
    SET @ok = 1;
    DELETE [Predict].[PredictionType] WHERE PredictionKey = 'zz_bad_source';
END TRY
BEGIN CATCH
    SET @ok = 0;
END CATCH
INSERT @results VALUES ('a prediction cannot be built on a non-probability',
    CASE WHEN @ok = 1 THEN 'accepted' ELSE 'refused' END,
    CASE WHEN @ok = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 6 -------------------------------------------------------------------------
/*  The control for assertion 5. A guard that refused everything would pass it
    while making the catalogue unextendable, and would look identical. */
BEGIN TRY
    INSERT [Predict].[PredictionType] (PredictionKey, DisplayName, [Description],
        HorizonCode, SourceMeasureCode, FramingPattern, MinConfidence,
        MinSupportDays, LifetimeHours, SortOrder)
    VALUES ('zz_good', N'Good', N'x', 'tomorrow', 'engagement_probability',
            N'{chance} {window} {support}', 40, 14, 24, 999);
    SET @ok = 1;
    DELETE [Predict].[PredictionType] WHERE PredictionKey = 'zz_good';
END TRY
BEGIN CATCH
    SET @ok = 0;
END CATCH
INSERT @results VALUES ('a well-formed prediction type is still accepted',
    CASE WHEN @ok = 1 THEN 'accepted' ELSE 'refused' END,
    CASE WHEN @ok = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 7 -------------------------------------------------------------------------
/*  Every seeded type names a measure Behaviour actually publishes as a
    probability. The foreign key guarantees it; this states it in the engine's
    own vocabulary so a failure reads as a fact rather than as a constraint
    name. */
SELECT @n = COUNT(*)
FROM [Predict].[PredictionType] pt
WHERE NOT EXISTS (
    SELECT 1 FROM [Behaviour].[MeasureType] m
    WHERE m.MeasureCode = pt.SourceMeasureCode AND m.Family = 'probability');
INSERT @results VALUES ('every prediction frames an observed probability',
    CONCAT(@n, ' unbacked'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 8 -------------------------------------------------------------------------
/*  A window long enough to be unfalsifiable is not a prediction. */
SELECT @n = COUNT(*) FROM [Predict].[Horizon]
WHERE WindowDays < 1 OR WindowDays > 90;
INSERT @results VALUES ('every horizon is a bounded forward window',
    CONCAT(@n, ' out of range'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 9 -------------------------------------------------------------------------
/*  The architectural assertion, checked against the dependency graph rather
    than the text. Prediction reads Behaviour through fn_Read; a raw store here
    would be a second reader of behaviour, and the two would answer differently
    the day either changed. */
SELECT @n = COUNT(*)
FROM sys.sql_expression_dependencies d
JOIN sys.objects o ON o.object_id = d.referencing_id
JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE s.name = 'Predict'
  AND d.referenced_entity_name IN
      ('Event', 'Observation', 'UserStateSnapshot', 'GoalProgress', 'UserGoal');
INSERT @results VALUES ('prediction never reaches a raw store',
    CONCAT(@n, ' reaching past the interfaces'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 10 ------------------------------------------------------------------------
/*  And it carries none of the arithmetic that produces a probability.

    ActiveDays and POWER( are the marks of the behaviour measure: the observed
    rate and the recency decay. Either appearing in a Predict module would mean
    a second implementation of a number that must have exactly one. */
SELECT @n = COUNT(*)
FROM sys.sql_modules sm
JOIN sys.objects o ON o.object_id = sm.object_id
JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE s.name = 'Predict'
  AND (sm.definition LIKE '%ActiveDays%' OR sm.definition LIKE '%POWER(%');
INSERT @results VALUES ('prediction contains none of the measure arithmetic',
    CONCAT(@n, ' module(s) computing'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 11 ------------------------------------------------------------------------
/*  The probability is carried through unchanged. 0.7 is 70%; the only
    transformation in this engine is that presentation. */
DELETE FROM @obs;
INSERT @obs VALUES ('hydration', 'completion_probability', 0.7000, 90, 28);
SELECT @pct = ProbabilityPercent FROM [Predict].[fn_PredictFrom](@obs);
INSERT @results VALUES ('the observed probability is carried through',
    CONCAT('0.7000 -> ', ISNULL(CAST(@pct AS VARCHAR(10)), 'none')),
    CASE WHEN @pct = 70 THEN 'PASS' ELSE 'FAIL' END);

-- 12 ------------------------------------------------------------------------
/*  Including at the rounding boundary, where a silent truncation would
    understate her by a whole point every time. */
DELETE FROM @obs;
INSERT @obs VALUES ('hydration', 'completion_probability', 0.0550, 90, 28);
SELECT @pct = ProbabilityPercent FROM [Predict].[fn_PredictFrom](@obs);
INSERT @results VALUES ('the percent rounds rather than truncates',
    CONCAT('0.0550 -> ', ISNULL(CAST(@pct AS VARCHAR(10)), 'none')),
    CASE WHEN @pct = 6 THEN 'PASS' ELSE 'FAIL' END);

-- 13 ------------------------------------------------------------------------
/*  Under the confidence floor it is withheld, not hedged. A statement about
    her behaviour built on thin history is not a weaker statement of the same
    kind - it is a different kind of thing, and the platform does not make it. */
DELETE FROM @obs;
INSERT @obs VALUES ('hydration', 'completion_probability', 0.9000, 30, 28);
SELECT @n = COUNT(*) FROM [Predict].[fn_PredictFrom](@obs);
INSERT @results VALUES ('under the confidence floor nothing is said',
    CONCAT(@n, ' predicted at confidence 30'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 14 ------------------------------------------------------------------------
/*  And under the support floor. */
DELETE FROM @obs;
INSERT @obs VALUES ('hydration', 'completion_probability', 0.9000, 95, 9);
SELECT @n = COUNT(*) FROM [Predict].[fn_PredictFrom](@obs);
INSERT @results VALUES ('under the support floor nothing is said',
    CONCAT(@n, ' predicted on 9 days'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 15 ------------------------------------------------------------------------
/*  A measure that is not a probability contributes nothing, even when it is
    supplied. The join is on the source measure, so there is no path by which
    a consistency figure becomes a chance. */
DELETE FROM @obs;
INSERT @obs VALUES ('hydration', 'consistency', 65.0000, 95, 28),
                   ('hydration', 'streak_current', 12.0000, 95, 28);
SELECT @n = COUNT(*) FROM [Predict].[fn_PredictFrom](@obs);
INSERT @results VALUES ('a non-probability measure predicts nothing',
    CONCAT(@n, ' predicted from habit measures'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 16 ------------------------------------------------------------------------
/*  Given nothing observed it says nothing. It has no other source of numbers,
    and this is the strongest statement of that. */
DELETE FROM @obs;
SELECT @n = COUNT(*) FROM [Predict].[fn_PredictFrom](@obs);
INSERT @results VALUES ('given nothing observed, nothing is predicted',
    CONCAT(@n, ' predicted from an empty set'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 17 ------------------------------------------------------------------------
/*  The three facts actually reach the sentence. A pattern can carry all three
    placeholders and still be filled in with the wrong things; this checks the
    percent, the horizon's phrase and the support days are all present in the
    text a woman would read. */
DELETE FROM @obs;
INSERT @obs VALUES ('hydration', 'completion_probability', 0.7000, 90, 21);
SELECT @t = StatementText FROM [Predict].[fn_PredictFrom](@obs);
INSERT @results VALUES ('the statement carries the chance, window and support',
    LEFT(ISNULL(@t, 'none'), 60),
    CASE WHEN @t LIKE '%70%%' AND @t LIKE '%tomorrow%'
          AND @t LIKE '%21 days of history%' THEN 'PASS' ELSE 'FAIL' END);

-- 18 ------------------------------------------------------------------------
/*  Evidence resolves back to the row in Behaviour that produced the number,
    rather than to prose about it. */
SELECT @t = EvidenceCsv FROM [Predict].[fn_PredictFrom](@obs);
INSERT @results VALUES ('evidence names the observation behind it',
    ISNULL(@t, 'none'),
    CASE WHEN @t = 'behaviour:hydration.completion_probability'
         THEN 'PASS' ELSE 'FAIL' END);

-- 19 ------------------------------------------------------------------------
/*  The proof that the operator shorthand and the live path are one
    implementation. The same observation typed into the inspector and built by
    hand must frame identically; if it ever does not, an operator is tuning a
    fiction.

    ExpiresUtc is excluded because the two calls happen at different instants,
    which is a property of the clock rather than of the framing. */
DECLARE @viaShorthand TABLE (PredictionKey VARCHAR(40), SubjectKey VARCHAR(40),
                             ProbabilityPercent INT, SupportDays INT,
                             Confidence INT, StatementText NVARCHAR(600));
DECLARE @viaHand TABLE (PredictionKey VARCHAR(40), SubjectKey VARCHAR(40),
                        ProbabilityPercent INT, SupportDays INT,
                        Confidence INT, StatementText NVARCHAR(600));

DELETE FROM @obs;
INSERT @obs (SubjectKey, MeasureCode, ValueNumeric, Confidence, SpanDays)
SELECT SubjectKey, MeasureCode, ValueNumeric, Confidence, SpanDays
FROM [Predict].[fn_ParseObservations](
    N'hydration.completion_probability=0.7@21,hydration.engagement_probability=0.55@21',
    90, 28);
INSERT @viaShorthand
SELECT PredictionKey, SubjectKey, ProbabilityPercent, SupportDays, Confidence,
       StatementText
FROM [Predict].[fn_PredictFrom](@obs);

DELETE FROM @obs;
INSERT @obs VALUES ('hydration', 'completion_probability', 0.7000, 90, 21),
                   ('hydration', 'engagement_probability', 0.5500, 90, 21);
INSERT @viaHand
SELECT PredictionKey, SubjectKey, ProbabilityPercent, SupportDays, Confidence,
       StatementText
FROM [Predict].[fn_PredictFrom](@obs);

SELECT @n = COUNT(*)
FROM @viaShorthand a
FULL OUTER JOIN @viaHand b
      ON b.PredictionKey = a.PredictionKey AND b.SubjectKey = a.SubjectKey
WHERE a.PredictionKey IS NULL OR b.PredictionKey IS NULL
   OR a.ProbabilityPercent <> b.ProbabilityPercent
   OR a.SupportDays <> b.SupportDays
   OR a.Confidence <> b.Confidence
   OR a.StatementText <> b.StatementText;
INSERT @results VALUES ('the operator shorthand frames identically',
    CONCAT((SELECT COUNT(*) FROM @viaShorthand), ' framed, ', @n, ' disagree'),
    CASE WHEN @n = 0 AND (SELECT COUNT(*) FROM @viaShorthand) > 0
         THEN 'PASS' ELSE 'FAIL' END);

-- 20 ------------------------------------------------------------------------
/*  Nothing clinical, nothing instructing, nothing certain. A prediction is
    where an authoritative voice would most naturally creep in, because a
    number about the future sounds like knowledge.

    'will' is banned in the deterministic sense; every framing here is written
    backward-looking on purpose. */
SELECT @n = COUNT(*)
FROM [Predict].[PredictionType]
WHERE FramingPattern LIKE '%you will%'   OR FramingPattern LIKE '%guarantee%'
   OR FramingPattern LIKE '%certain%'    OR FramingPattern LIKE '%diagnos%'
   OR FramingPattern LIKE '%symptom%'    OR FramingPattern LIKE '%treat%'
   OR FramingPattern LIKE '%risk of%'    OR FramingPattern LIKE '%causes%'
   OR FramingPattern LIKE '%you should%' OR FramingPattern LIKE '%you must%';
INSERT @results VALUES ('no framing instructs, diagnoses or promises',
    CONCAT(@n, ' offending'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- Report --------------------------------------------------------------------
SELECT RIGHT('  ' + CAST(Seq AS varchar(3)), 3) + ' ' +
       LEFT(Assertion + REPLICATE('.', 56), 56) + ' ' +
       LEFT(ISNULL(Detail, '') + REPLICATE(' ', 34), 34) + ' ' + Outcome
FROM @results ORDER BY Seq;

DECLARE @total INT = (SELECT COUNT(*) FROM @results);
DECLARE @failed INT = (SELECT COUNT(*) FROM @results WHERE Outcome = 'FAIL');

PRINT '';
PRINT '---------------------------------------------';
PRINT CONCAT('TOTAL: ', @total, '  FAILED: ', @failed);
PRINT '---------------------------------------------';

IF @failed > 0
    THROW 51000, 'Prediction assertions failed.', 1;
GO
