SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Life-stage model verification.

    The properties asserted here are the ones the platform pivot depends on.
    Two matter more than the rest:

      - a transition preserves history rather than overwriting it. That record
        is the whole basis of the AI companion's longitudinal context, and it
        cannot be recovered once a transition has thrown it away.

      - exactly one stage is open at a time. Every dashboard, notification and
        AI turn asks "what stage is she in", and a second open row makes that
        question unanswerable.

    Run: sqlcmd -S "$SERVER" -d "$DB" -i tests/life_stage_test.sql -I
    Expect: TOTAL: 14  FAILED: 0

    Re-runnable: creates its own user, cleans up on the way in and out.
*/

SET NOCOUNT ON;

DECLARE @results TABLE (Seq INT IDENTITY(1,1), Assertion NVARCHAR(200),
                        Detail NVARCHAR(200), Outcome CHAR(4));
DECLARE @res TABLE (Succeeded BIT, FailureCode VARCHAR(50));
DECLARE @user UNIQUEIDENTIFIER = '00000000-0000-0000-0000-0000000ABCDE';
DECLARE @n INT, @ok BIT, @code VARCHAR(50);

/*  Own user, deterministic id, removed first so the suite is re-runnable. */
DELETE FROM [Identity].[UserRoleMode]   WHERE UserId = @user;
DELETE FROM [Identity].[UserLifeStage]  WHERE UserId = @user;
DELETE FROM [Identity].[Profile]        WHERE UserId = @user;
DELETE FROM [Identity].[User]           WHERE UserId = @user;

INSERT INTO [Identity].[User] (UserId, Email, NormalisedEmail, PasswordHash,
                               PasswordSalt, PasswordIterations, SecurityStamp)
VALUES (@user, 'stage-test@example.com', 'STAGE-TEST@EXAMPLE.COM',
        0x00, 0x00, 210000, NEWID());

-- 1 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Identity].[LifeStage];
INSERT @results VALUES ('twelve life stages are seeded', CONCAT(@n, ' stages'),
    CASE WHEN @n = 12 THEN 'PASS' ELSE 'FAIL' END);

-- 2 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Identity].[RoleMode];
INSERT @results VALUES ('eight role modes are seeded', CONCAT(@n, ' modes'),
    CASE WHEN @n = 8 THEN 'PASS' ELSE 'FAIL' END);

-- 3 -------------------------------------------------------------------------
/*  The nineteen product categories must be expressible as stage + modes.
    Spot-checked on the two that need both dimensions at once. */
SELECT @n = CASE WHEN EXISTS (SELECT 1 FROM [Identity].[LifeStage] WHERE LifeStageCode='motherhood')
                  AND EXISTS (SELECT 1 FROM [Identity].[RoleMode]  WHERE RoleModeCode='professional')
                  AND EXISTS (SELECT 1 FROM [Identity].[LifeStage] WHERE LifeStageCode='young_adult')
                  AND EXISTS (SELECT 1 FROM [Identity].[RoleMode]  WHERE RoleModeCode='student')
            THEN 1 ELSE 0 END;
INSERT @results VALUES ('"professional mother" and "university student" are expressible',
    CASE WHEN @n = 1 THEN 'stage + mode' ELSE 'missing' END,
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 4 -------------------------------------------------------------------------
DELETE @res;
INSERT @res EXEC [Identity].[usp_UserLifeStage_Set]
    @UserId = @user, @LifeStageCode = 'planning', @ActorUserId = @user;
SELECT @ok = Succeeded FROM @res;
INSERT @results VALUES ('a first stage can be set', 'planning',
    CASE WHEN @ok = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 5 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Identity].[UserLifeStage]
WHERE UserId = @user AND EndedOn IS NULL;
INSERT @results VALUES ('exactly one stage is open', CONCAT(@n, ' open'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 6 -------------------------------------------------------------------------
/*  Re-setting the same stage must not create a second, one-day row. Onboarding
    is re-runnable and clients retry. */
DELETE @res;
INSERT @res EXEC [Identity].[usp_UserLifeStage_Set]
    @UserId = @user, @LifeStageCode = 'planning', @ActorUserId = @user;
SELECT @n = COUNT(*) FROM [Identity].[UserLifeStage] WHERE UserId = @user;
INSERT @results VALUES ('re-setting the same stage is a no-op', CONCAT(@n, ' row(s)'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 7 -------------------------------------------------------------------------
DELETE @res;
INSERT @res EXEC [Identity].[usp_UserLifeStage_Set]
    @UserId = @user, @LifeStageCode = 'pregnancy', @ActorUserId = @user;
SELECT @n = COUNT(*) FROM [Identity].[UserLifeStage] WHERE UserId = @user;
INSERT @results VALUES ('a transition preserves the previous stage',
    CONCAT(@n, ' rows in history'),
    CASE WHEN @n = 2 THEN 'PASS' ELSE 'FAIL' END);

-- 8 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Identity].[UserLifeStage]
WHERE UserId = @user AND LifeStageCode = 'planning' AND EndedOn IS NOT NULL;
INSERT @results VALUES ('the previous stage was closed, not deleted',
    CASE WHEN @n = 1 THEN 'closed with a date' ELSE 'lost' END,
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 9 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Identity].[UserLifeStage]
WHERE UserId = @user AND EndedOn IS NULL;
INSERT @results VALUES ('still exactly one stage open after transition',
    CONCAT(@n, ' open'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 10 ------------------------------------------------------------------------
/*  A stage that does not exist must be refused as a Result, not thrown: a
    client typo is an expected failure, not an exception. */
DELETE @res;
INSERT @res EXEC [Identity].[usp_UserLifeStage_Set]
    @UserId = @user, @LifeStageCode = 'astronaut', @ActorUserId = @user;
SELECT @ok = Succeeded, @code = FailureCode FROM @res;
INSERT @results VALUES ('an unknown stage is refused', ISNULL(@code, '(none)'),
    CASE WHEN @ok = 0 AND @code = 'UNKNOWN_LIFE_STAGE' THEN 'PASS' ELSE 'FAIL' END);

-- 11 ------------------------------------------------------------------------
DELETE @res;
INSERT @res EXEC [Identity].[usp_Profile_Save]
    @UserId = @user, @DisplayName = N'Test User',
    @DateOfBirth = '1990-05-04', @TimeZoneId = 'Europe/London',
    @ActorUserId = @user;
SELECT @ok = Succeeded FROM @res;
SELECT @n = COUNT(*) FROM [Identity].[Profile]
WHERE UserId = @user AND DisplayName = N'Test User' AND DateOfBirth = '1990-05-04';
INSERT @results VALUES ('the profile is readable and writable at last',
    CASE WHEN @n = 1 THEN 'saved' ELSE 'not saved' END,
    CASE WHEN @ok = 1 AND @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 12 ------------------------------------------------------------------------
/*  A partial save must not blank what it was not told. Onboarding sets fields
    a few at a time. */
DELETE @res;
INSERT @res EXEC [Identity].[usp_Profile_Save]
    @UserId = @user, @TimeZoneId = 'Asia/Karachi', @ActorUserId = @user;
SELECT @n = COUNT(*) FROM [Identity].[Profile]
WHERE UserId = @user AND DisplayName = N'Test User'
  AND DateOfBirth = '1990-05-04' AND TimeZoneId = 'Asia/Karachi';
INSERT @results VALUES ('a partial save leaves other fields alone',
    CASE WHEN @n = 1 THEN 'preserved' ELSE 'blanked' END,
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 13 ------------------------------------------------------------------------
DELETE @res;
INSERT @res EXEC [Identity].[usp_Profile_Save]
    @UserId = @user, @DateOfBirth = '2999-01-01', @ActorUserId = @user;
SELECT @ok = Succeeded, @code = FailureCode FROM @res;
INSERT @results VALUES ('a date of birth in the future is refused',
    ISNULL(@code, '(none)'),
    CASE WHEN @ok = 0 AND @code = 'INVALID_DATE_OF_BIRTH' THEN 'PASS' ELSE 'FAIL' END);

-- 14 ------------------------------------------------------------------------
/*  Several modes at once is the normal case, not the exception. */
DELETE @res;
INSERT @res EXEC [Identity].[usp_UserRoleMode_Set]
    @UserId = @user, @ModeCodesJson = N'["professional","caregiver","partner"]',
    @ActorUserId = @user;
SELECT @n = COUNT(*) FROM [Identity].[UserRoleMode] WHERE UserId = @user;
INSERT @results VALUES ('several role modes can be held at once',
    CONCAT(@n, ' modes'),
    CASE WHEN @n = 3 THEN 'PASS' ELSE 'FAIL' END);

-- Report --------------------------------------------------------------------
SELECT RIGHT('  ' + CAST(Seq AS varchar(3)), 3) + ' ' +
       LEFT(Assertion + REPLICATE('.', 62), 62) + ' ' +
       LEFT(ISNULL(Detail, '') + REPLICATE(' ', 24), 24) + ' ' + Outcome
FROM @results ORDER BY Seq;

DECLARE @total INT = (SELECT COUNT(*) FROM @results);
DECLARE @failed INT = (SELECT COUNT(*) FROM @results WHERE Outcome = 'FAIL');

PRINT '';
PRINT '---------------------------------------------';
PRINT CONCAT('TOTAL: ', @total, '  FAILED: ', @failed);
PRINT '---------------------------------------------';

-- Clean up so a populated database is left as it was found.
DELETE FROM [Identity].[UserRoleMode]  WHERE UserId = @user;
DELETE FROM [Identity].[UserLifeStage] WHERE UserId = @user;
DELETE FROM [Identity].[Profile]       WHERE UserId = @user;
DELETE FROM [Identity].[User]          WHERE UserId = @user;

IF @failed > 0
    THROW 51000, 'Life stage assertions failed.', 1;
GO
