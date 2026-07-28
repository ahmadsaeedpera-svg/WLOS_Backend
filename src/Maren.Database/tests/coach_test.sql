SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Coach Platform.

    The coach explains. The assertions here are about the one property that is
    hard to hold and easy to lose: it invents nothing.

    That is made structural rather than reviewed. A coach message is filled in,
    not written - a tone supplies a pattern with {body} and {reason}, and a
    constraint refuses a pattern that drops either. So the only facts in any
    message are facts the recommendation already carried, and those came from
    her timeline.

    The rest follows: given nothing to explain it says nothing; it never
    reassembles; it adds no evidence of its own; and no tone can be configured
    that encourages without evidence.

    Run: sqlcmd -S "$SERVER" -d "$DB" -i tests/coach_test.sql -I
    Expect: TOTAL: 16  FAILED: 0

    Re-runnable: owns nothing persistent.
*/

SET NOCOUNT ON;

DECLARE @results TABLE (Seq INT IDENTITY(1,1), Assertion NVARCHAR(200),
                        Detail NVARCHAR(200), Outcome CHAR(4));

DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
DECLARE @n INT, @t NVARCHAR(1200), @ok BIT;

DECLARE @ev   [Recommend].[EvidenceSet];
DECLARE @recs [Coach].[ExplainSet];

DECLARE @out TABLE (
    RecommendationKey VARCHAR(40), DisplayName NVARCHAR(80), ToneCode VARCHAR(30),
    ToneName NVARCHAR(60), ToneRationale NVARCHAR(200), ToneFromRule BIT,
    MessageText NVARCHAR(1200), Priority INT, Confidence INT,
    ExpectedEffort TINYINT, EvidenceCsv NVARCHAR(600), ExpiresUtc DATETIME2(3));

-- 1 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Coach].[ToneProfile] WHERE IsActive = 1;
INSERT @results VALUES ('the tone library is seeded',
    CONCAT(@n, ' tones'),
    CASE WHEN @n >= 3 THEN 'PASS' ELSE 'FAIL' END);

-- 2 -------------------------------------------------------------------------
/*  Exactly one default. None means a recommendation can reach her with no
    voice; two makes the fallback arbitrary. */
SELECT @n = COUNT(*) FROM [Coach].[ToneProfile] WHERE IsDefault = 1 AND IsActive = 1;
INSERT @results VALUES ('exactly one tone is the fallback',
    CONCAT(@n, ' defaults'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 3 -------------------------------------------------------------------------
/*  The invention guard, at rest. Every pattern must carry the reasoning. */
SELECT @n = COUNT(*) FROM [Coach].[ToneProfile]
WHERE Pattern NOT LIKE '%{reason}%' OR Pattern NOT LIKE '%{body}%';
INSERT @results VALUES ('every tone keeps the body and the reasoning',
    CONCAT(@n, ' lossy'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 4 -------------------------------------------------------------------------
/*  And the schema refuses one that does not, so no configuration can produce
    encouragement with the evidence stripped out. */
BEGIN TRY
    INSERT [Coach].[ToneProfile] (ToneCode, DisplayName, [Description], Pattern,
        Weight, IsDefault, SortOrder)
    VALUES ('zz_bad', N'Bad', N'x', N'{body} You have got this!', 10, 0, 999);
    SET @ok = 1;
END TRY
BEGIN CATCH
    SET @ok = 0;
END CATCH
DELETE FROM [Coach].[ToneProfile] WHERE ToneCode = 'zz_bad';
INSERT @results VALUES ('a tone that drops the reasoning is refused',
    CONCAT('inserted=', CAST(@ok AS varchar(1))),
    CASE WHEN @ok = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 5 -------------------------------------------------------------------------
/*  Nothing to explain. The coach must say nothing - it has no other source of
    things to say, and this is the strongest statement of what it is. */
DELETE @out;
INSERT @out SELECT * FROM [Coach].[fn_ExplainFrom](@recs, @ev, 24);
SELECT @n = COUNT(*) FROM @out;
INSERT @results VALUES ('with nothing to explain it says nothing',
    CONCAT(@n, ' invented'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 6 -------------------------------------------------------------------------
/*  One recommendation, no tone evidence. It should speak in the default voice
    rather than not at all. */
INSERT @recs VALUES ('water_reminder', N'A glass of water',
    N'You have not logged a drink today.',
    /*  Deliberately different words from the body. With the reason echoing the
        body, assertions 8 and 13 passed even when the reason substitution was
        removed - they were matching the body twice. */
    N'three days have passed since your last logged drink',
    N'behaviour:hydration.days_since_last', 60, 80, 1);

DELETE @out;
INSERT @out SELECT * FROM [Coach].[fn_ExplainFrom](@recs, @ev, 24);
SELECT @n = COUNT(*), @t = MAX(ToneCode) FROM @out;
INSERT @results VALUES ('with no tone evidence it uses the fallback voice',
    CONCAT(@n, ' message, tone=', ISNULL(@t, '(none)')),
    CASE WHEN @n = 1 AND @t = 'steady' THEN 'PASS' ELSE 'FAIL' END);

-- 7 -------------------------------------------------------------------------
/*  The message must contain the recommendation and its reasoning verbatim.
    Anything else in it is connective phrasing from the pattern. */
SELECT @t = MessageText FROM @out;
INSERT @results VALUES ('the message carries the recommendation verbatim',
    LEFT(ISNULL(@t, '(null)'), 40),
    CASE WHEN @t LIKE N'%You have not logged a drink today.%'
         THEN 'PASS' ELSE 'FAIL' END);

-- 8 -------------------------------------------------------------------------
INSERT @results VALUES ('and the reasoning verbatim',
    LEFT(ISNULL(@t, '(null)'), 40),
    CASE WHEN @t LIKE N'%three days have passed since your last logged drink%'
         THEN 'PASS' ELSE 'FAIL' END);

-- 9 -------------------------------------------------------------------------
/*  No placeholder may survive into what she reads. A pattern with a typo would
    otherwise ship "{resaon}" to a woman. */
SELECT @n = COUNT(*) FROM @out WHERE MessageText LIKE N'%{%';
INSERT @results VALUES ('no placeholder reaches her unfilled',
    CONCAT(@n, ' leaking'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 10 ------------------------------------------------------------------------
/*  Evidence is carried through unchanged. The coach observes nothing, so it
    has none of its own to add. */
SELECT @t = EvidenceCsv FROM @out;
INSERT @results VALUES ('evidence is carried through, never added to',
    LEFT(ISNULL(@t, '(null)'), 40),
    CASE WHEN @t = N'behaviour:hydration.days_since_last' THEN 'PASS' ELSE 'FAIL' END);

-- 11 ------------------------------------------------------------------------
/*  Tone follows the evidence. Low energy must produce the gentle voice. */
INSERT @ev VALUES ('state', 'energy.low', NULL, 90);
DELETE @out;
INSERT @out SELECT * FROM [Coach].[fn_ExplainFrom](@recs, @ev, 24);
SELECT @t = ToneCode FROM @out;
INSERT @results VALUES ('low energy is heard as a gentler voice',
    CONCAT('tone=', ISNULL(@t, '(none)')),
    CASE WHEN @t = 'gentle' THEN 'PASS' ELSE 'FAIL' END);

-- 12 ------------------------------------------------------------------------
/*  And the choice of voice explains itself. A tone chosen without a stated
    reason is indistinguishable from one chosen at random. */
SELECT @t = ToneRationale FROM @out;
INSERT @results VALUES ('the choice of voice explains itself',
    LEFT(ISNULL(@t, '(null)'), 40),
    CASE WHEN @t LIKE N'%low energy%' THEN 'PASS' ELSE 'FAIL' END);

-- 13 ------------------------------------------------------------------------
/*  The gentler voice must still carry the same facts. A tone that softened by
    dropping evidence would be the failure this platform refuses. */
SELECT @t = MessageText FROM @out;
INSERT @results VALUES ('a softer voice still carries the same facts',
    LEFT(ISNULL(@t, '(null)'), 40),
    CASE WHEN @t LIKE N'%You have not logged a drink today.%'
          AND @t LIKE N'%three days have passed since your last logged drink%'
         THEN 'PASS' ELSE 'FAIL' END);

-- 14 ------------------------------------------------------------------------
/*  A non-default tone with no rules can never be selected, and looks identical
    to a voice nobody qualifies for. */
SELECT @n = COUNT(*) FROM [Coach].[ToneProfile] t
WHERE t.IsActive = 1 AND t.IsDefault = 0
  AND NOT EXISTS (SELECT 1 FROM [Coach].[ToneRule] r WHERE r.ToneCode = t.ToneCode);
INSERT @results VALUES ('no active tone is unreachable',
    CONCAT(@n, ' unreachable'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 15 ------------------------------------------------------------------------
/*  The architectural assertion, checked against the dependency graph.

    The coach must never reassemble. Reaching RecommendationInput or the
    assembly function would make it a second opinion about the same woman, and
    the two could disagree the moment a threshold changed between them. It reads
    the assembled result and the published interfaces, nothing else. */
SELECT @n = COUNT(*)
FROM sys.sql_expression_dependencies d
JOIN sys.objects o ON o.object_id = d.referencing_id
JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE s.name = 'Coach'
  AND d.referenced_entity_name IN
      ('RecommendationInput', 'fn_AssembleFrom', 'fn_Assemble',
       'Event', 'Observation', 'fn_SubjectDays');
INSERT @results VALUES ('the coach never reassembles or recomputes',
    CONCAT(@n, ' reaching past its inputs'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 16 ------------------------------------------------------------------------
/*  Nothing clinical, nothing instructing, nothing diagnostic. A coach is where
    an authoritative voice would most naturally creep in. */
SELECT @n = COUNT(*)
FROM [Coach].[ToneProfile]
WHERE Pattern LIKE '%you should%' OR Pattern LIKE '%you must%'
   OR Pattern LIKE '%need to%'    OR Pattern LIKE '%diagnos%'
   OR Pattern LIKE '%symptom%'    OR Pattern LIKE '%treat%'
   OR Pattern LIKE '%will improve%' OR Pattern LIKE '%because it causes%';
INSERT @results VALUES ('no tone instructs, diagnoses or promises',
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
    THROW 51000, 'Coach assertions failed.', 1;
GO
