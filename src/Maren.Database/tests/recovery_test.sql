/*  recovery_test.sql

    Path R, asserted as a state machine rather than as a happy path.

    What this suite is really checking is that the ways in are the only ways
    in. A recovery path that works when used correctly and also works when
    used incorrectly is not a recovery path, it is a second front door.

    Run:
      sqlcmd -S "$SERVER" -I -d "$DB" -i src/Maren.Database/tests/recovery_test.sql

    Expect: TOTAL: 18  FAILED: 0

    Creates and removes its own data, on the way in as well as on the way out.
*/

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

DECLARE @failed int = 0;

DECLARE @userR uniqueidentifier = '0C0DE000-0000-4000-B000-000000000001';
DECLARE @genR  uniqueidentifier = '0C0DE000-0000-4000-B100-000000000001';
DECLARE @genR2 uniqueidentifier = '0C0DE000-0000-4000-B100-000000000002';

DECLARE @emailR nvarchar(256) = N'recovery_test@test.invalid';
DECLARE @normR  nvarchar(256) = N'RECOVERY_TEST@TEST.INVALID';

DECLARE @env48 varbinary(max) = CAST(REPLICATE(CAST(0x5A AS binary(1)), 48) AS varbinary(max));
DECLARE @envNew varbinary(max) = CAST(REPLICATE(CAST(0x7B AS binary(1)), 48) AS varbinary(max));
DECLARE @pk32  varbinary(32) = CAST(REPLICATE(CAST(0xA1 AS binary(1)), 32) AS varbinary(32));
DECLARE @pk32b varbinary(32) = CAST(REPLICATE(CAST(0xA2 AS binary(1)), 32) AS varbinary(32));
DECLARE @nonce varbinary(32) = CAST(REPLICATE(CAST(0x11 AS binary(1)), 32) AS varbinary(32));
DECLARE @salt  varbinary(32) = CAST(REPLICATE(CAST(0xC9 AS binary(1)), 16) AS varbinary(32));
DECLARE @grant varbinary(32) = CAST(REPLICATE(CAST(0xD1 AS binary(1)), 32) AS varbinary(32));
DECLARE @grant2 varbinary(32) = CAST(REPLICATE(CAST(0xD2 AS binary(1)), 32) AS varbinary(32));
DECLARE @profile int = (SELECT TOP 1 KdfProfileId FROM [Crypto].[KdfProfile] ORDER BY KdfProfileId);

PRINT '=== Path R: recovery by phrase ===';
PRINT '';

-- ---------------------------------------------------------------------------
-- Clean up, then build one account with one generation and one of each wrapper.
-- ---------------------------------------------------------------------------
DELETE FROM [Crypto].[RecoveryChallenge] WHERE UserId = @userR OR IpAddress = '203.0.113.9';
DELETE FROM [Crypto].[Record]            WHERE UserId = @userR;
DELETE FROM [Crypto].[RecoveryVerifier]  WHERE GenerationId IN
       (SELECT GenerationId FROM [Crypto].[Generation] WHERE UserId = @userR);
DELETE FROM [Crypto].[Wrapper]           WHERE GenerationId IN
       (SELECT GenerationId FROM [Crypto].[Generation] WHERE UserId = @userR);
DELETE FROM [Crypto].[Generation]        WHERE UserId = @userR;
DELETE FROM [Identity].[UserCredential]  WHERE UserId = @userR;
DELETE FROM [Identity].[RefreshToken]    WHERE UserId = @userR;
DELETE FROM [Audit].[AuditLog]           WHERE ActorUserId = @userR;
DELETE FROM [Identity].[User]            WHERE UserId = @userR;

INSERT INTO [Identity].[User] (UserId, Email, NormalisedEmail)
VALUES (@userR, @emailR, @normR);

INSERT INTO [Identity].[UserCredential]
    (UserId, CredentialVersion, AuthSecretHash, AuthSecretSalt, KdfProfileId, IsAuthoritative)
VALUES (@userR, 2, @pk32, @salt, @profile, 1);

INSERT INTO [Crypto].[Generation] (GenerationId, UserId, GenerationNumber, [State])
VALUES (@genR, @userR, 1, 'ACTIVE');

INSERT INTO [Crypto].[Wrapper] (GenerationId, WrapperKind, Envelope)
VALUES (@genR, 'PASSWORD', @env48), (@genR, 'RECOVERY', @env48);

INSERT INTO [Crypto].[RecoveryVerifier] (GenerationId, PublicKey)
VALUES (@genR, @pk32);

DECLARE @stampBefore uniqueidentifier =
    (SELECT SecurityStamp FROM [Identity].[User] WHERE UserId = @userR);

-- ---------------------------------------------------------------------------
-- R0 — issuing
-- ---------------------------------------------------------------------------

DECLARE @issued TABLE (ChallengeId uniqueidentifier, Nonce varbinary(32),
                       ExpiresOn datetime2(3));

DECLARE @unknownEmail nvarchar(256) = N'nobody_recovery@test.invalid';
DELETE FROM @issued;
INSERT @issued EXEC [Crypto].[usp_Recovery_IssueChallenge]
    @Email = @unknownEmail, @Nonce = @nonce, @IpAddress = NULL;

DECLARE @unknownId uniqueidentifier = (SELECT TOP 1 ChallengeId FROM @issued);

/*  The whole point of the endpoint. An address with no account gets a real
    challenge, of the right shape, so that answering cannot be used to ask
    which addresses are registered. */
IF @unknownId IS NOT NULL
   AND EXISTS (SELECT 1 FROM [Crypto].[RecoveryChallenge]
                WHERE ChallengeId = @unknownId AND UserId IS NULL
                  AND [State] = 'ISSUED')
    PRINT '  1 an address with no account still gets a challenge            PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT '  1 an address with no account still gets a challenge            FAIL';
END

DELETE FROM [Crypto].[RecoveryChallenge] WHERE ChallengeId = @unknownId;

DELETE FROM @issued;
INSERT @issued EXEC [Crypto].[usp_Recovery_IssueChallenge]
    @Email = @emailR, @Nonce = @nonce, @IpAddress = NULL;

DECLARE @challengeId uniqueidentifier = (SELECT TOP 1 ChallengeId FROM @issued);

IF EXISTS (SELECT 1 FROM [Crypto].[RecoveryChallenge]
            WHERE ChallengeId = @challengeId AND UserId = @userR
              AND GenerationId = @genR AND [State] = 'ISSUED')
    PRINT '  2 a known address gets a challenge bound to its generation     PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT '  2 a known address gets a challenge bound to its generation     FAIL';
END

/*  Nothing is told to her yet. A challenge is not an event -- anyone can ask
    for one, and notifying on a request would make the endpoint a way to send
    her mail. The notification belongs at R1, where something was proved. */
IF NOT EXISTS (SELECT 1 FROM [Audit].[AuditLog]
                WHERE ActorUserId = @userR AND [Action] = 'Recovery.PhraseUsed')
    PRINT '  3 issuing a challenge is not yet an event                      PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT '  3 issuing a challenge is not yet an event                      FAIL';
END

-- ---------------------------------------------------------------------------
-- R1 — consuming, and what a failed attempt costs
-- ---------------------------------------------------------------------------

DECLARE @consumed TABLE (UserId uniqueidentifier, GenerationId uniqueidentifier,
                         Nonce varbinary(32), PublicKey varbinary(32),
                         GenerationNumber int);

INSERT @consumed EXEC [Crypto].[usp_Recovery_ConsumeChallenge]
    @ChallengeId = @challengeId;

IF EXISTS (SELECT 1 FROM @consumed WHERE UserId = @userR AND PublicKey = @pk32
                                     AND Nonce = @nonce)
   AND EXISTS (SELECT 1 FROM [Crypto].[RecoveryChallenge]
                WHERE ChallengeId = @challengeId AND [State] = 'CONSUMED')
    PRINT '  4 consuming returns the verifier and spends the challenge      PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT '  4 consuming returns the verifier and spends the challenge      FAIL';
END

/*  Single use, and spent on any attempt. A challenge that survived a failure
    would let an attacker grind guesses against one nonce. */
DELETE FROM @consumed;
INSERT @consumed EXEC [Crypto].[usp_Recovery_ConsumeChallenge]
    @ChallengeId = @challengeId;

IF NOT EXISTS (SELECT 1 FROM @consumed)
    PRINT '  5 a challenge cannot be consumed twice                         PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT '  5 a challenge cannot be consumed twice                         FAIL';
END

/*  The wrapper is not handed out here. It is the target of any offline attack
    on the phrase, so it is released only once a signature has verified. */
IF NOT EXISTS (SELECT 1 FROM sys.columns
                WHERE object_id = OBJECT_ID('Crypto.usp_Recovery_ConsumeChallenge'))
   AND (SELECT COUNT(*) FROM sys.sql_modules m
         JOIN sys.objects o ON o.object_id = m.object_id
        WHERE o.name = 'usp_Recovery_ConsumeChallenge'
          AND m.definition LIKE '%Wrapper%') = 0
    PRINT '  6 consuming does not release the recovery wrapper              PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT '  6 consuming does not release the recovery wrapper              FAIL';
END

-- An expired challenge is not consumable.
DECLARE @expiredId uniqueidentifier = NEWID();
INSERT INTO [Crypto].[RecoveryChallenge]
    (ChallengeId, UserId, GenerationId, Nonce, [State], IssuedOn, ExpiresOn)
VALUES (@expiredId, @userR, @genR, @nonce, 'ISSUED',
        DATEADD(MINUTE, -30, SYSUTCDATETIME()), DATEADD(MINUTE, -20, SYSUTCDATETIME()));

DELETE FROM @consumed;
INSERT @consumed EXEC [Crypto].[usp_Recovery_ConsumeChallenge] @ChallengeId = @expiredId;

IF NOT EXISTS (SELECT 1 FROM @consumed)
    PRINT '  7 an expired challenge is not consumable                       PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT '  7 an expired challenge is not consumable                       FAIL';
END

-- ---------------------------------------------------------------------------
-- The grant
-- ---------------------------------------------------------------------------

DECLARE @granted TABLE (Succeeded bit, FailureCode varchar(64),
                        UserId uniqueidentifier, GenerationId uniqueidentifier,
                        GenerationNumber int, RecoveryWrapper varbinary(max));

-- A grant on a challenge nobody attempted.
DECLARE @freshId uniqueidentifier;
DELETE FROM @issued;
INSERT @issued EXEC [Crypto].[usp_Recovery_IssueChallenge]
    @Email = @emailR, @Nonce = @nonce, @IpAddress = NULL;
SET @freshId = (SELECT TOP 1 ChallengeId FROM @issued);

INSERT @granted EXEC [Crypto].[usp_Recovery_IssueGrant]
    @ChallengeId = @freshId, @GrantHash = @grant;

IF EXISTS (SELECT 1 FROM @granted WHERE Succeeded = 0)
    PRINT '  8 a grant on an unattempted challenge is refused               PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT '  8 a grant on an unattempted challenge is refused               FAIL';
END

-- Now the real thing: consume, then grant.
DELETE FROM @consumed;
INSERT @consumed EXEC [Crypto].[usp_Recovery_ConsumeChallenge] @ChallengeId = @freshId;

DELETE FROM @granted;
INSERT @granted EXEC [Crypto].[usp_Recovery_IssueGrant]
    @ChallengeId = @freshId, @GrantHash = @grant;

IF EXISTS (SELECT 1 FROM @granted
            WHERE Succeeded = 1 AND UserId = @userR AND RecoveryWrapper = @env48)
    PRINT '  9 a verified challenge releases the wrapper and a grant        PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT '  9 a verified challenge releases the wrapper and a grant        FAIL';
END

/*  She is told now, before anything changes. If it was not her, the window in
    which she can act starts at the proof and not at the completion. */
IF EXISTS (SELECT 1 FROM [Audit].[AuditLog]
            WHERE ActorUserId = @userR AND [Action] = 'Recovery.PhraseUsed')
    PRINT ' 10 using the phrase is recorded before anything changes         PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 10 using the phrase is recorded before anything changes         FAIL';
END

DELETE FROM @granted;
INSERT @granted EXEC [Crypto].[usp_Recovery_IssueGrant]
    @ChallengeId = @freshId, @GrantHash = @grant2;

IF EXISTS (SELECT 1 FROM @granted WHERE Succeeded = 0)
    PRINT ' 11 a second grant on the same challenge is refused              PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 11 a second grant on the same challenge is refused              FAIL';
END

/*  The table itself refuses a grant without a verification. A procedure can be
    rewritten; a check constraint has to be removed on purpose. */
BEGIN TRY
    INSERT INTO [Crypto].[RecoveryChallenge]
        (ChallengeId, UserId, GenerationId, Nonce, [State], ExpiresOn,
         GrantHash, GrantExpiresOn)
    VALUES (NEWID(), @userR, @genR, @nonce, 'ISSUED',
            DATEADD(MINUTE, 10, SYSUTCDATETIME()), @grant2,
            DATEADD(MINUTE, 5, SYSUTCDATETIME()));
    SET @failed = @failed + 1;
    PRINT ' 12 a grant on an unverified row is refused by the table         FAIL';
END TRY
BEGIN CATCH
    PRINT ' 12 a grant on an unverified row is refused by the table         PASS';
END CATCH

-- ---------------------------------------------------------------------------
-- R2 — completion, with her journal intact
-- ---------------------------------------------------------------------------

INSERT INTO [Identity].[RefreshToken] (UserId, TokenHash, ExpiresUtc)
VALUES (@userR, @pk32, DATEADD(DAY, 30, SYSUTCDATETIME()));

DECLARE @completed TABLE (Succeeded bit, FailureCode varchar(64));
INSERT @completed EXEC [Crypto].[usp_Recovery_Complete]
    @GrantHash = @grant, @AuthSecretHash = @pk32b, @AuthSecretSalt = @salt,
    @KdfProfileId = @profile, @PasswordWrapper = @envNew;

IF EXISTS (SELECT 1 FROM @completed WHERE Succeeded = 1)
   AND (SELECT COUNT(*) FROM [Crypto].[Generation]
         WHERE UserId = @userR AND [State] = 'ACTIVE' AND GenerationId = @genR) = 1
   AND EXISTS (SELECT 1 FROM [Crypto].[Wrapper]
                WHERE GenerationId = @genR AND WrapperKind = 'PASSWORD'
                  AND Envelope = @envNew)
   AND EXISTS (SELECT 1 FROM [Crypto].[Wrapper]
                WHERE GenerationId = @genR AND WrapperKind = 'RECOVERY'
                  AND Envelope = @env48)
   AND EXISTS (SELECT 1 FROM [Identity].[UserCredential]
                WHERE UserId = @userR AND IsAuthoritative = 1
                  AND AuthSecretHash = @pk32b)
    PRINT ' 13 recovery keeps her generation and her old journal            PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 13 recovery keeps her generation and her old journal            FAIL';
END

IF NOT EXISTS (SELECT 1 FROM [Identity].[RefreshToken] WHERE UserId = @userR)
   AND (SELECT SecurityStamp FROM [Identity].[User] WHERE UserId = @userR) <> @stampBefore
    PRINT ' 14 sessions are revoked and the security stamp moves            PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 14 sessions are revoked and the security stamp moves            FAIL';
END

DELETE FROM @completed;
INSERT @completed EXEC [Crypto].[usp_Recovery_Complete]
    @GrantHash = @grant, @AuthSecretHash = @pk32, @AuthSecretSalt = @salt,
    @KdfProfileId = @profile, @PasswordWrapper = @env48;

IF EXISTS (SELECT 1 FROM @completed WHERE Succeeded = 0)
    PRINT ' 15 a spent grant cannot complete a second reset                 PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 15 a spent grant cannot complete a second reset                 FAIL';
END

-- ---------------------------------------------------------------------------
-- R3 — the wrapper did not open
-- ---------------------------------------------------------------------------

DELETE FROM @issued;
INSERT @issued EXEC [Crypto].[usp_Recovery_IssueChallenge]
    @Email = @emailR, @Nonce = @nonce, @IpAddress = NULL;
SET @freshId = (SELECT TOP 1 ChallengeId FROM @issued);

DELETE FROM @consumed;
INSERT @consumed EXEC [Crypto].[usp_Recovery_ConsumeChallenge] @ChallengeId = @freshId;

DECLARE @grant3 varbinary(32) = CAST(REPLICATE(CAST(0xD3 AS binary(1)), 32) AS varbinary(32));
DELETE FROM @granted;
INSERT @granted EXEC [Crypto].[usp_Recovery_IssueGrant]
    @ChallengeId = @freshId, @GrantHash = @grant3;

DECLARE @degraded TABLE (Succeeded bit, FailureCode varchar(64), GenerationNumber int);
INSERT @degraded EXEC [Crypto].[usp_Recovery_CompleteUnrecoverable]
    @GrantHash = @grant3, @AuthSecretHash = @pk32, @AuthSecretSalt = @salt,
    @KdfProfileId = @profile, @NewGenerationId = @genR2,
    @PasswordWrapper = @envNew, @RecoveryWrapper = @envNew,
    @RecoveryPublicKey = @pk32b;

IF EXISTS (SELECT 1 FROM @degraded WHERE Succeeded = 1 AND GenerationNumber = 2)
   AND (SELECT [State] FROM [Crypto].[Generation] WHERE GenerationId = @genR) = 'DORMANT'
   AND (SELECT [State] FROM [Crypto].[Generation] WHERE GenerationId = @genR2) = 'ACTIVE'
    PRINT ' 16 an unopenable wrapper retires the generation, not the account PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 16 an unopenable wrapper retires the generation, not the account FAIL';
END

/*  Her old records are not deleted and the old recovery wrapper is kept.

    A device somewhere may still hold that data key, and destroying the only
    remaining copy of what she wrote on the strength of one failed unwrap
    would be the worst possible response to it. The old password wrapper does
    go -- the password it was sealed under has just been replaced. */
IF EXISTS (SELECT 1 FROM [Crypto].[Wrapper]
            WHERE GenerationId = @genR AND WrapperKind = 'RECOVERY')
   AND NOT EXISTS (SELECT 1 FROM [Crypto].[Wrapper]
                    WHERE GenerationId = @genR AND WrapperKind = 'PASSWORD')
    PRINT ' 17 the old recovery wrapper is kept, the old password one is not PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 17 the old recovery wrapper is kept, the old password one is not FAIL';
END

-- ---------------------------------------------------------------------------
-- Deletion
-- ---------------------------------------------------------------------------

DECLARE @deleted TABLE (Succeeded bit, FailureCode varchar(64));
INSERT @deleted EXEC [Identity].[usp_User_DeleteAccount] @UserId = @userR;

IF NOT EXISTS (SELECT 1 FROM [Crypto].[RecoveryChallenge] WHERE UserId = @userR)
   AND NOT EXISTS (SELECT 1 FROM [Identity].[User] WHERE UserId = @userR)
    PRINT ' 18 closing the account takes the attempts on it too             PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 18 closing the account takes the attempts on it too             FAIL';
END

DELETE FROM [Crypto].[RecoveryChallenge] WHERE UserId = @userR;
DELETE FROM [Identity].[User] WHERE UserId = @userR;

PRINT '';
PRINT '---------------------------------------------';
PRINT 'TOTAL: 18  FAILED: ' + CAST(@failed AS varchar(10));
PRINT '---------------------------------------------';

IF @failed > 0
    THROW 51000, 'Path R assertions failed.', 1;
GO
