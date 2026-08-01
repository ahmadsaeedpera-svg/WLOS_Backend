/*  bootstrap_test.sql

    The first-administrator claim, asserted where it is enforced.

    The defect this closes: usp_User_Register grants Member and nothing grants
    anything else, while CLAUDE.md 4.6 — you cannot grant a permission you do
    not hold — is enforced inside usp_User_AssignRole. Together those mean no
    account can ever reach SuperAdmin through the API, so a correctly deployed
    database is administrable only by hand-written SQL against production.

    It went unnoticed for the platform's whole life because every verification
    database already had an operator. The platform had never once been started
    from nothing, which is exactly the state a real deployment begins in.

    These assertions exercise BEHAVIOUR against a live database rather than
    checking that a procedure exists. "The object is present" would have passed
    on every day the defect was shipping.
*/

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

PRINT '';
PRINT '=== bootstrap: first administrator ==========================================';

DECLARE @results TABLE (Seq INT IDENTITY(1,1), Assertion NVARCHAR(200),
                        Detail NVARCHAR(200), Outcome CHAR(4));
DECLARE @n INT, @ok BIT, @code VARCHAR(40);
DECLARE @stampBefore UNIQUEIDENTIFIER, @stampAfter UNIQUEIDENTIFIER;

DECLARE @claim TABLE (Succeeded BIT, FailureCode VARCHAR(40));

/*  Isolated ids so the suite is re-runnable and order-independent, matching
    every other suite here. Cleaned on the way IN, not only on the way out: a
    previous run that failed half way must not poison this one. */
DECLARE @u1 UNIQUEIDENTIFIER = '0B007E51-0000-0000-0000-00000000B001';
DECLARE @u2 UNIQUEIDENTIFIER = '0B007E51-0000-0000-0000-00000000B002';
DECLARE @superAdminId INT = (SELECT RoleId FROM [Identity].[Role] WHERE Name = 'SuperAdmin');
DECLARE @memberId INT = (SELECT RoleId FROM [Identity].[Role] WHERE Name = 'Member');

DELETE FROM [Audit].[AuditLog] WHERE ActorUserId IN (@u1, @u2);
DELETE FROM [Identity].[UserRole] WHERE UserId IN (@u1, @u2);
DELETE FROM [Identity].[Profile] WHERE UserId IN (@u1, @u2);
DELETE FROM [Identity].[User] WHERE UserId IN (@u1, @u2);

INSERT INTO [Identity].[User]
    (UserId, Email, NormalisedEmail, PasswordHash, PasswordSalt, PasswordIterations)
VALUES (@u1, 'bootstrap-1@test.invalid', 'BOOTSTRAP-1@TEST.INVALID', 0x00, 0x00, 1),
       (@u2, 'bootstrap-2@test.invalid', 'BOOTSTRAP-2@TEST.INVALID', 0x00, 0x00, 1);

/*  Every real holder of users.write is parked for the duration, so the suite
    can observe the genuinely-unclaimed state on a database that already has
    administrators. Restored at the end. Without this the suite could only ever
    exercise the refusal path, and the path that matters would be untested. */
DECLARE @parked TABLE (UserId UNIQUEIDENTIFIER, RoleId INT, AssignedBy UNIQUEIDENTIFIER);
INSERT INTO @parked (UserId, RoleId, AssignedBy)
SELECT ur.UserId, ur.RoleId, ur.AssignedBy
FROM [Identity].[UserRole] ur
JOIN [Identity].[RolePermission] rp ON rp.RoleId = ur.RoleId
JOIN [Identity].[Permission] p ON p.PermissionId = rp.PermissionId
WHERE p.Code = 'users.write';

DELETE ur FROM [Identity].[UserRole] ur
WHERE EXISTS (SELECT 1 FROM @parked k WHERE k.UserId = ur.UserId AND k.RoleId = ur.RoleId);

SELECT @stampBefore = SecurityStamp FROM [Identity].[User] WHERE UserId = @u1;

BEGIN TRY

-- 1 -------------------------------------------------------------------------
/*  The path that did not exist. On a database nobody administers, the first
    caller becomes the operator. */
DELETE FROM @claim;
INSERT @claim EXEC [Identity].[usp_Operator_Claim] @UserId = @u1;
SELECT @ok = Succeeded FROM @claim;
INSERT @results VALUES ('an unclaimed platform grants the first claimant',
    CONCAT('succeeded=', @ok), CASE WHEN @ok = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 2 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Identity].[UserRole]
WHERE UserId = @u1 AND RoleId = @superAdminId;
INSERT @results VALUES ('the claimant actually holds SuperAdmin',
    CONCAT('rows=', @n), CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 3 -------------------------------------------------------------------------
/*  Self-disabling by construction rather than by bookkeeping. The claimant now
    holds users.write, so the same query that opened the door closes it. No
    flag is consulted, because a flag can disagree with reality. */
DELETE FROM @claim;
INSERT @claim EXEC [Identity].[usp_Operator_Claim] @UserId = @u2;
SELECT @ok = Succeeded, @code = FailureCode FROM @claim;
INSERT @results VALUES ('a second claim is refused once one exists',
    CONCAT('succeeded=', @ok, ' code=', ISNULL(@code, '(null)')),
    CASE WHEN @ok = 0 AND @code = 'ALREADY_CLAIMED' THEN 'PASS' ELSE 'FAIL' END);

-- 4 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Identity].[UserRole]
WHERE UserId = @u2 AND RoleId = @superAdminId;
INSERT @results VALUES ('a refused claim grants nothing',
    CONCAT('rows=', @n), CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 5 -------------------------------------------------------------------------
/*  A refused claim is a security event. Auditing only successes means somebody
    probing a deployed platform for an open bootstrap leaves no trace, and the
    first evidence of an attempt is the attempt that worked. */
SELECT @n = COUNT(*) FROM [Audit].[AuditLog]
WHERE ActorUserId = @u2 AND [Action] = 'Security.OperatorClaimRefused';
INSERT @results VALUES ('a refused claim is recorded as a security event',
    CONCAT('rows=', @n), CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 6 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Audit].[AuditLog]
WHERE ActorUserId = @u1 AND [Action] = 'Identity.OperatorClaimed';
INSERT @results VALUES ('a successful claim is recorded',
    CONCAT('rows=', @n), CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 7 -------------------------------------------------------------------------
/*  ActorKind must be 'user', not 'admin'. By definition the caller holds no
    administrative permission at the moment of the claim, and recording them as
    an admin would put a false actor kind on a security row — the one kind of
    row whose whole value is that it can be believed. */
SELECT @n = COUNT(*) FROM [Audit].[AuditLog]
WHERE ActorUserId = @u1 AND [Action] = 'Identity.OperatorClaimed' AND ActorKind = 'user';
INSERT @results VALUES ('the claim is audited as a user, not an admin',
    CONCAT('rows=', @n), CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 8 -------------------------------------------------------------------------
/*  Rotating the security stamp forces re-authentication, so the new permissions
    are held rather than waited for. Without it the claimant carries a token
    minted before the role existed and stays locked out until it expires.

    Asserted on the VALUE, not on an audit row. The first draft of this checked
    for a log entry whose Action contained "SecurityStamp" and failed against a
    correct implementation — the rotation procedure does not name itself that
    way. A guess about a log message is not evidence that a stamp rotated; the
    stamp is. */
SELECT @stampAfter = SecurityStamp FROM [Identity].[User] WHERE UserId = @u1;
INSERT @results VALUES ('claiming rotates the security stamp',
    CASE WHEN @stampAfter <> @stampBefore THEN 'changed' ELSE 'unchanged' END,
    CASE WHEN @stampAfter <> @stampBefore THEN 'PASS' ELSE 'FAIL' END);

-- 9 -------------------------------------------------------------------------
DELETE FROM @claim;
INSERT @claim EXEC [Identity].[usp_Operator_Claim]
    @UserId = '0B007E51-0000-0000-0000-0000DEADBEEF';
SELECT @ok = Succeeded, @code = FailureCode FROM @claim;
INSERT @results VALUES ('an unknown user cannot claim',
    CONCAT('code=', ISNULL(@code, '(null)')),
    CASE WHEN @ok = 0 AND @code = 'NOT_FOUND' THEN 'PASS' ELSE 'FAIL' END);

-- 10 ------------------------------------------------------------------------
/*  Reopening is deliberate and is the lost-administrator recovery path. It is
    safe because the API gate — a deployment secret this database never sees —
    is a second lock. Asserted so that nobody "fixes" it into a permanent flag
    and locks a real platform out of its own recovery. */
DELETE FROM [Identity].[UserRole] WHERE UserId = @u1 AND RoleId = @superAdminId;
DELETE FROM @claim;
INSERT @claim EXEC [Identity].[usp_Operator_Claim] @UserId = @u2;
SELECT @ok = Succeeded FROM @claim;
INSERT @results VALUES ('removing every operator reopens the claim',
    CONCAT('succeeded=', @ok), CASE WHEN @ok = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 11 ------------------------------------------------------------------------
/*  The claim must not be a back door into every role. It grants SuperAdmin and
    only SuperAdmin; a claimant does not silently acquire Member or anything a
    future seed adds. */
SELECT @n = COUNT(*) FROM [Identity].[UserRole] WHERE UserId = @u2;
INSERT @results VALUES ('the claim grants exactly one role',
    CONCAT('roles=', @n), CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

END TRY
BEGIN CATCH
    INSERT @results VALUES ('suite ran to completion',
        LEFT(ERROR_MESSAGE(), 190), 'FAIL');
END CATCH

-- Cleanup -------------------------------------------------------------------
DELETE FROM [Audit].[AuditLog] WHERE ActorUserId IN (@u1, @u2);
DELETE FROM [Identity].[UserRole] WHERE UserId IN (@u1, @u2);
DELETE FROM [Identity].[Profile] WHERE UserId IN (@u1, @u2);
DELETE FROM [Identity].[User] WHERE UserId IN (@u1, @u2);

/*  Restore every real operator. A suite that left a live database with no
    administrator would be worse than the defect it tests. */
INSERT INTO [Identity].[UserRole] (UserId, RoleId, AssignedBy)
SELECT k.UserId, k.RoleId, k.AssignedBy FROM @parked k
WHERE NOT EXISTS (SELECT 1 FROM [Identity].[UserRole] ur
                  WHERE ur.UserId = k.UserId AND ur.RoleId = k.RoleId);

-- Report --------------------------------------------------------------------
SELECT RIGHT('  ' + CAST(Seq AS varchar(3)), 3) + ' ' +
       LEFT(Assertion + REPLICATE('.', 56), 56) + ' ' +
       LEFT(ISNULL(Detail, '') + REPLICATE(' ', 30), 30) + ' ' + Outcome
FROM @results ORDER BY Seq;

DECLARE @total INT = (SELECT COUNT(*) FROM @results);
DECLARE @failed INT = (SELECT COUNT(*) FROM @results WHERE Outcome = 'FAIL');

PRINT '';
PRINT '---------------------------------------------';
PRINT CONCAT('TOTAL: ', @total, '  FAILED: ', @failed);
PRINT '---------------------------------------------';

IF @failed > 0
    THROW 51000, 'Bootstrap assertions failed.', 1;
GO
