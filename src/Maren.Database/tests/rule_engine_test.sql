SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Rule engine verification.

    Two things are being proved here.

    First, that the consolidation changed nothing about what reaches a woman.
    That evidence is mostly elsewhere: content_targeting_test and
    dashboard_engine_test still pass, unchanged, against the rewritten
    functions. If those two suites are green the semantics survived.

    Second, the invariant that replaces a foreign key. A generic rule table
    cannot reference its target - TargetKey points at a content item in one
    scope and a card type in another - so Dashboard.CardRule's ON DELETE
    CASCADE was genuinely lost. Assertion 5 is what replaces it, and it is the
    reason this suite exists rather than being folded into the other two.

    Run: sqlcmd -S "$SERVER" -d "$DB" -i tests/rule_engine_test.sql -I
    Expect: TOTAL: 12  FAILED: 0

    Re-runnable: owns its rows and removes them at both ends.
*/

SET NOCOUNT ON;

DECLARE @results TABLE (Seq INT IDENTITY(1,1), Assertion NVARCHAR(200),
                        Detail NVARCHAR(200), Outcome CHAR(4));
DECLARE @res TABLE (Succeeded BIT, FailureCode VARCHAR(50));
DECLARE @actor UNIQUEIDENTIFIER = (SELECT TOP 1 UserId FROM [Identity].[User]);
DECLARE @item UNIQUEIDENTIFIER, @n INT, @ok BIT, @code VARCHAR(50);

CREATE TABLE #saved (ContentItemId UNIQUEIDENTIFIER,
                     ContentVersionId UNIQUEIDENTIFIER, VersionNumber INT);

DELETE FROM [Rules].[Rule] WHERE TargetKey = N'rule-engine-orphan-check';
DELETE FROM [Content].[ContentItem] WHERE [Key] = 'rule-engine-item';

DECLARE @pregnant NVARCHAR(MAX) = N'[{"dimension":"life_stage","value":"pregnancy"}]';
DECLARE @teen     NVARCHAR(MAX) = N'[{"dimension":"life_stage","value":"adolescence"}]';
DECLARE @unknown  NVARCHAR(MAX) = N'[]';

-- 1 -------------------------------------------------------------------------
/*  The duplicated tables are gone. Two sources of truth for one concept is
    what this change existed to remove. */
SELECT @n = CASE WHEN OBJECT_ID('Content.ContentTargetingRule') IS NULL
                  AND OBJECT_ID('Dashboard.CardRule') IS NULL
            THEN 1 ELSE 0 END;
INSERT @results VALUES ('the duplicated rule tables are gone',
    CASE WHEN @n = 1 THEN 'one store' ELSE 'still two' END,
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 2 -------------------------------------------------------------------------
/*  And their rows arrived. The dashboard seeds eight card rules. */
SELECT @n = COUNT(*) FROM [Rules].[Rule] WHERE ScopeCode = 'dashboardCard';
INSERT @results VALUES ('card rules survived the migration',
    CONCAT(@n, ' rule(s)'),
    CASE WHEN @n >= 8 THEN 'PASS' ELSE 'FAIL' END);

-- 3 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Rules].[TargetScope];
INSERT @results VALUES ('scopes are a registry, not a hardcoded list',
    CONCAT(@n, ' scope(s)'),
    CASE WHEN @n >= 2 THEN 'PASS' ELSE 'FAIL' END);

-- 4 -------------------------------------------------------------------------
/*  One matcher serves both scopes, and they do not see each other's rules. */
SELECT @n = COUNT(*) FROM [Rules].[fn_Match]('dashboardCard', @pregnant)
WHERE TargetKey = 'baby_development';
INSERT @results VALUES ('the shared matcher answers for the dashboard scope',
    CONCAT(@n, ' match'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 5 -------------------------------------------------------------------------
/*  The invariant that replaces the lost foreign key. Every rule's target must
    resolve inside its own scope, checked without building SQL from the scope
    registry - the two scopes are enumerated here deliberately so this test
    cannot be satisfied by a scope nobody validates. */
SELECT @n =
    (SELECT COUNT(*) FROM [Rules].[Rule] r
     WHERE r.ScopeCode = 'content'
       AND NOT EXISTS (SELECT 1 FROM [Content].[ContentItem] ci
                       WHERE CONVERT(NVARCHAR(100), ci.ContentItemId) = r.TargetKey))
  + (SELECT COUNT(*) FROM [Rules].[Rule] r
     WHERE r.ScopeCode = 'dashboardCard'
       AND NOT EXISTS (SELECT 1 FROM [Dashboard].[CardType] ct
                       WHERE CONVERT(NVARCHAR(100), ct.CardTypeCode) = r.TargetKey))
  + (SELECT COUNT(*) FROM [Rules].[Rule] r
     WHERE r.ScopeCode NOT IN ('content', 'dashboardCard'));
INSERT @results VALUES ('no rule points at a target that does not exist',
    CONCAT(@n, ' orphan(s)'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 6 -------------------------------------------------------------------------
/*  Semantics survived: a target with no rules is universal. */
DELETE #saved;
INSERT #saved EXEC [Content].[usp_Content_Save] @ContentType='article',
    @Key='rule-engine-item', @CategoryKey='nutrition',
    @LocalizationsJson=N'[{"languageCode":"en-GB","title":"Rules","body":"x"}]',
    @ActorUserId=@actor;
SELECT @item = ContentItemId FROM #saved;

SELECT @n = COUNT(*) FROM [Content].[fn_TargetedItems](@unknown)
WHERE ContentItemId = @item;
INSERT @results VALUES ('an untargeted item still reaches everyone',
    CONCAT(@n, ' match'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 7 -------------------------------------------------------------------------
DELETE @res;
INSERT @res EXEC [Content].[usp_Content_SetTargetingRules]
    @ContentItemId = @item,
    @RulesJson = N'[{"dimension":"life_stage","operator":"in","values":["pregnancy"],"note":"Test rule."}]',
    @ActorUserId = @actor;
SELECT @ok = Succeeded FROM @res;
SELECT @n = COUNT(*) FROM [Rules].[Rule]
WHERE ScopeCode = 'content' AND TargetKey = CONVERT(NVARCHAR(100), @item);
INSERT @results VALUES ('the old procedure now writes to the one store',
    CONCAT(@n, ' rule(s)'),
    CASE WHEN @ok = 1 AND @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 8 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Content].[fn_TargetedItems](@pregnant)
WHERE ContentItemId = @item;
INSERT @results VALUES ('a targeted item reaches a matching woman',
    CONCAT(@n, ' match'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 9 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Content].[fn_TargetedItems](@teen)
WHERE ContentItemId = @item;
INSERT @results VALUES ('and not a non-matching one', CONCAT(@n, ' match'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 10 ------------------------------------------------------------------------
/*  The conservative case, preserved through the consolidation. */
SELECT @n = COUNT(*) FROM [Content].[fn_TargetedItems](@unknown)
WHERE ContentItemId = @item;
INSERT @results VALUES ('an unknown context receives no targeted item',
    CONCAT(@n, ' match'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 11 ------------------------------------------------------------------------
/*  Clearing the rules makes it universal again. Narrowing distribution during
    an incident is only useful if it can be undone. */
DELETE @res;
INSERT @res EXEC [Content].[usp_Content_SetTargetingRules]
    @ContentItemId = @item, @RulesJson = N'[]', @ActorUserId = @actor;
SELECT @n = COUNT(*) FROM [Content].[fn_TargetedItems](@teen)
WHERE ContentItemId = @item;
INSERT @results VALUES ('clearing rules makes a target universal again',
    CONCAT(@n, ' match'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 12 ------------------------------------------------------------------------
DELETE @res;
INSERT @res EXEC [Rules].[usp_Rules_SetForTarget]
    @ScopeCode = 'astrology', @TargetKey = N'x', @RulesJson = N'[]';
SELECT @ok = Succeeded, @code = FailureCode FROM @res;
INSERT @results VALUES ('an unknown scope is refused', ISNULL(@code, '(none)'),
    CASE WHEN @ok = 0 AND @code = 'UNKNOWN_SCOPE' THEN 'PASS' ELSE 'FAIL' END);

-- Report --------------------------------------------------------------------
SELECT RIGHT('  ' + CAST(Seq AS varchar(3)), 3) + ' ' +
       LEFT(Assertion + REPLICATE('.', 58), 58) + ' ' +
       LEFT(ISNULL(Detail, '') + REPLICATE(' ', 22), 22) + ' ' + Outcome
FROM @results ORDER BY Seq;

DECLARE @total INT = (SELECT COUNT(*) FROM @results);
DECLARE @failed INT = (SELECT COUNT(*) FROM @results WHERE Outcome = 'FAIL');

PRINT '';
PRINT '---------------------------------------------';
PRINT CONCAT('TOTAL: ', @total, '  FAILED: ', @failed);
PRINT '---------------------------------------------';

DELETE FROM [Content].[ContentItem] WHERE [Key] = 'rule-engine-item';
DROP TABLE #saved;

IF @failed > 0
    THROW 51000, 'Rule engine assertions failed.', 1;
GO
