/*  crypto_test.sql

    Asserts that the three invariants in 74_Crypto.sql are enforced by the
    database and not merely described in a comment.

      AUTH-1   exactly one authoritative credential verifier per account
      GEN-1    exactly one ACTIVE generation per account
      GEN-2    at most one MIGRATING generation per account

    Every one of these is a filtered unique index or a check constraint, so
    the test is written the only way such a thing can honestly be tested:
    by attempting the violation and asserting the engine refuses it. A test
    that merely inserts valid rows proves nothing about a constraint.

    These are committed-state invariants. Each assertion below is its own
    statement, so "refused" here means refused at the moment of the write,
    which is the strongest form available.

    Run:
      sqlcmd -S "$SERVER" -I -d "$DB" -i src/Maren.Database/tests/crypto_test.sql

    Expect: TOTAL: 36  FAILED: 0

    Creates and removes its own data. Re-runnable and order-independent:
    it cleans up on the way in as well as on the way out, so a previous
    interrupted run cannot fail the next one.
*/

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

DECLARE @failed int = 0;

DECLARE @userA uniqueidentifier = '0C0DE000-0000-4000-A000-00000000000A';
DECLARE @userB uniqueidentifier = '0C0DE000-0000-4000-A000-00000000000B';
DECLARE @genA1 uniqueidentifier = '0C0DE000-0000-4000-6E00-000000000001';
DECLARE @genA2 uniqueidentifier = '0C0DE000-0000-4000-6E00-000000000002';
DECLARE @genA3 uniqueidentifier = '0C0DE000-0000-4000-6E00-000000000003';
DECLARE @genB1 uniqueidentifier = '0C0DE000-0000-4000-6E00-00000000000B';
DECLARE @dev   uniqueidentifier = '0C0DE000-0000-4000-DE00-000000000001';

-- A syntactically plausible 48-byte envelope: the floor, with no ciphertext.
DECLARE @env48 varbinary(max) = CAST(REPLICATE(CAST(0x5A AS binary(1)), 48) AS varbinary(max));
DECLARE @env47 varbinary(max) = CAST(REPLICATE(CAST(0x5A AS binary(1)), 47) AS varbinary(max));
DECLARE @pk32  varbinary(32)  = CAST(REPLICATE(CAST(0xA1 AS binary(1)), 32) AS varbinary(32));
DECLARE @profile int = (SELECT TOP 1 KdfProfileId FROM [Crypto].[KdfProfile] ORDER BY KdfProfileId);

PRINT '=== Crypto: key hierarchy invariants ===';
PRINT '';

-- ---------------------------------------------------------------------------
-- Clean up on the way in.
-- ---------------------------------------------------------------------------
DELETE FROM [Crypto].[Record]           WHERE UserId IN (@userA, @userB);
DELETE FROM [Crypto].[RecoveryVerifier] WHERE GenerationId IN
       (SELECT GenerationId FROM [Crypto].[Generation] WHERE UserId IN (@userA, @userB));
DELETE FROM [Crypto].[Wrapper]          WHERE GenerationId IN
       (SELECT GenerationId FROM [Crypto].[Generation] WHERE UserId IN (@userA, @userB));
DELETE FROM [Crypto].[Generation]       WHERE UserId IN (@userA, @userB);
DELETE FROM [Identity].[UserCredential] WHERE UserId IN (@userA, @userB);
DELETE FROM [Identity].[User]           WHERE UserId IN (@userA, @userB);

INSERT INTO [Identity].[User] (UserId, Email, NormalisedEmail)
VALUES (@userA, N'crypto_test_a@test.invalid', N'CRYPTO_TEST_A@TEST.INVALID'),
       (@userB, N'crypto_test_b@test.invalid', N'CRYPTO_TEST_B@TEST.INVALID');

-- ---------------------------------------------------------------------------
-- AUTH-1
-- ---------------------------------------------------------------------------

INSERT INTO [Identity].[UserCredential]
    (UserId, CredentialVersion, AuthSecretHash, AuthSecretSalt, KdfProfileId, IsAuthoritative)
VALUES (@userA, 2, @pk32, CAST(REPLICATE(CAST(0xB2 AS binary(1)), 16) AS varbinary(32)), @profile, 1);

BEGIN TRY
    INSERT INTO [Identity].[UserCredential]
        (UserId, CredentialVersion, AuthSecretHash, AuthSecretSalt, KdfProfileId, IsAuthoritative)
    VALUES (@userA, 2, @pk32, CAST(REPLICATE(CAST(0xB3 AS binary(1)), 16) AS varbinary(32)), @profile, 1);
    SET @failed = @failed + 1;
    PRINT '  1 AUTH-1 second authoritative credential refused                  FAIL';
END TRY
BEGIN CATCH
    PRINT '  1 AUTH-1 second authoritative credential refused                  PASS';
END CATCH

UPDATE [Identity].[UserCredential]
   SET IsAuthoritative = 0, SupersededOn = SYSUTCDATETIME()
 WHERE UserId = @userA;

BEGIN TRY
    INSERT INTO [Identity].[UserCredential]
        (UserId, CredentialVersion, AuthSecretHash, AuthSecretSalt, KdfProfileId, IsAuthoritative)
    VALUES (@userA, 2, @pk32, CAST(REPLICATE(CAST(0xB4 AS binary(1)), 16) AS varbinary(32)), @profile, 1);
    PRINT '  2 AUTH-1 replacement allowed once the first is superseded         PASS';
END TRY
BEGIN CATCH
    SET @failed = @failed + 1;
    PRINT '  2 AUTH-1 replacement allowed once the first is superseded         FAIL';
END CATCH

BEGIN TRY
    INSERT INTO [Identity].[UserCredential] (UserId, CredentialVersion, IsAuthoritative)
    VALUES (@userB, 2, 0);
    SET @failed = @failed + 1;
    PRINT '  3 version 2 without derivation material refused                   FAIL';
END TRY
BEGIN CATCH
    PRINT '  3 version 2 without derivation material refused                   PASS';
END CATCH

BEGIN TRY
    INSERT INTO [Identity].[UserCredential]
        (UserId, CredentialVersion, AuthSecretHash, AuthSecretSalt, KdfProfileId, IsAuthoritative)
    VALUES (@userB, 1, @pk32, CAST(REPLICATE(CAST(0xB5 AS binary(1)), 16) AS varbinary(32)), @profile, 0);
    SET @failed = @failed + 1;
    PRINT '  4 version 1 carrying version 2 material refused                   FAIL';
END TRY
BEGIN CATCH
    PRINT '  4 version 1 carrying version 2 material refused                   PASS';
END CATCH

BEGIN TRY
    INSERT INTO [Identity].[UserCredential]
        (UserId, CredentialVersion, AuthSecretHash, AuthSecretSalt, KdfProfileId,
         IsAuthoritative, SupersededOn)
    VALUES (@userB, 2, @pk32, CAST(REPLICATE(CAST(0xB6 AS binary(1)), 16) AS varbinary(32)), @profile,
            1, SYSUTCDATETIME());
    SET @failed = @failed + 1;
    PRINT '  5 authoritative-and-superseded refused                            FAIL';
END TRY
BEGIN CATCH
    PRINT '  5 authoritative-and-superseded refused                            PASS';
END CATCH

-- ---------------------------------------------------------------------------
-- GEN-1 and GEN-2
-- ---------------------------------------------------------------------------

INSERT INTO [Crypto].[Generation] (GenerationId, UserId, GenerationNumber, [State])
VALUES (@genA1, @userA, 1, 'ACTIVE');

BEGIN TRY
    INSERT INTO [Crypto].[Generation] (GenerationId, UserId, GenerationNumber, [State])
    VALUES (@genA2, @userA, 2, 'ACTIVE');
    SET @failed = @failed + 1;
    PRINT '  6 GEN-1 second ACTIVE generation refused                          FAIL';
END TRY
BEGIN CATCH
    PRINT '  6 GEN-1 second ACTIVE generation refused                          PASS';
END CATCH

BEGIN TRY
    INSERT INTO [Crypto].[Generation] (GenerationId, UserId, GenerationNumber, [State])
    VALUES (@genB1, @userB, 1, 'ACTIVE');
    PRINT '  7 GEN-1 is per account, not global                                PASS';
END TRY
BEGIN CATCH
    SET @failed = @failed + 1;
    PRINT '  7 GEN-1 is per account, not global                                FAIL';
END CATCH

INSERT INTO [Crypto].[Generation] (GenerationId, UserId, GenerationNumber, [State])
VALUES (@genA2, @userA, 2, 'MIGRATING');

BEGIN TRY
    INSERT INTO [Crypto].[Generation] (GenerationId, UserId, GenerationNumber, [State])
    VALUES (@genA3, @userA, 3, 'MIGRATING');
    SET @failed = @failed + 1;
    PRINT '  8 GEN-2 second MIGRATING generation refused                       FAIL';
END TRY
BEGIN CATCH
    PRINT '  8 GEN-2 second MIGRATING generation refused                       PASS';
END CATCH

IF EXISTS (SELECT 1 FROM [Crypto].[Generation] WHERE UserId = @userA AND [State] = 'ACTIVE')
   AND EXISTS (SELECT 1 FROM [Crypto].[Generation] WHERE UserId = @userA AND [State] = 'MIGRATING')
    PRINT '  9 one ACTIVE and one MIGRATING coexist                            PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT '  9 one ACTIVE and one MIGRATING coexist                            FAIL';
END

BEGIN TRY
    INSERT INTO [Crypto].[Generation] (GenerationId, UserId, GenerationNumber, [State])
    VALUES (@genA3, @userA, 3, 'RETIRED');
    SET @failed = @failed + 1;
    PRINT ' 10 unknown generation state refused                                FAIL';
END TRY
BEGIN CATCH
    PRINT ' 10 unknown generation state refused                                PASS';
END CATCH

BEGIN TRY
    INSERT INTO [Crypto].[Generation] (GenerationId, UserId, GenerationNumber, [State])
    VALUES (@genA3, @userA, 1, 'DORMANT');
    SET @failed = @failed + 1;
    PRINT ' 11 duplicate generation number refused                             FAIL';
END TRY
BEGIN CATCH
    PRINT ' 11 duplicate generation number refused                             PASS';
END CATCH

/*  The envelope names its generation in a uint16 field, so a generation the
    envelope cannot name is one no record could ever be sealed under. The
    column has to agree with the format rather than merely with itself. */
BEGIN TRY
    INSERT INTO [Crypto].[Generation] (GenerationId, UserId, GenerationNumber, [State])
    VALUES (@genA3, @userA, 65536, 'DORMANT');
    SET @failed = @failed + 1;
    PRINT ' 11b generation number beyond the envelope uint16 refused          FAIL';
END TRY
BEGIN CATCH
    PRINT ' 11b generation number beyond the envelope uint16 refused          PASS';
END CATCH

-- ---------------------------------------------------------------------------
-- Wrappers
-- ---------------------------------------------------------------------------

INSERT INTO [Crypto].[Wrapper] (GenerationId, WrapperKind, Envelope)
VALUES (@genA1, 'PASSWORD', @env48);

BEGIN TRY
    INSERT INTO [Crypto].[Wrapper] (GenerationId, WrapperKind, Envelope)
    VALUES (@genA1, 'PASSWORD', @env48);
    SET @failed = @failed + 1;
    PRINT ' 12 second password wrapper on one generation refused               FAIL';
END TRY
BEGIN CATCH
    PRINT ' 12 second password wrapper on one generation refused               PASS';
END CATCH

BEGIN TRY
    INSERT INTO [Crypto].[Wrapper] (GenerationId, WrapperKind, DeviceId, Envelope)
    VALUES (@genA1, 'DEVICE', NULL, @env48);
    SET @failed = @failed + 1;
    PRINT ' 13 device wrapper without a device refused                         FAIL';
END TRY
BEGIN CATCH
    PRINT ' 13 device wrapper without a device refused                         PASS';
END CATCH

BEGIN TRY
    INSERT INTO [Crypto].[Wrapper] (GenerationId, WrapperKind, DeviceId, Envelope)
    VALUES (@genA1, 'RECOVERY', @dev, @env48);
    SET @failed = @failed + 1;
    PRINT ' 14 non-device wrapper naming a device refused                      FAIL';
END TRY
BEGIN CATCH
    PRINT ' 14 non-device wrapper naming a device refused                      PASS';
END CATCH

BEGIN TRY
    INSERT INTO [Crypto].[Wrapper] (GenerationId, WrapperKind, Envelope)
    VALUES (@genA1, 'RECOVERY', @env47);
    SET @failed = @failed + 1;
    PRINT ' 15 wrapper envelope below the 48-byte floor refused                FAIL';
END TRY
BEGIN CATCH
    PRINT ' 15 wrapper envelope below the 48-byte floor refused                PASS';
END CATCH

-- ---------------------------------------------------------------------------
-- Recovery verifiers: the staging boundary
--
-- A recovery public key hangs off a generation. Material staged for a reset
-- that has not committed has no generation, so it cannot be stored and cannot
-- be found by a verifier lookup. That is what stops an attacker who starts an
-- email reset from using the key pair he just generated to pass the
-- recovery-phrase path and skip the window entirely.
-- ---------------------------------------------------------------------------

BEGIN TRY
    INSERT INTO [Crypto].[RecoveryVerifier] (GenerationId, PublicKey)
    VALUES ('0C0DE000-0000-4000-6E00-0000000000FF', @pk32);
    SET @failed = @failed + 1;
    PRINT ' 16 recovery verifier without a generation refused                  FAIL';
END TRY
BEGIN CATCH
    PRINT ' 16 recovery verifier without a generation refused                  PASS';
END CATCH

BEGIN TRY
    INSERT INTO [Crypto].[RecoveryVerifier] (GenerationId, PublicKey)
    VALUES (@genA1, CAST(REPLICATE(CAST(0xA1 AS binary(1)), 31) AS varbinary(32)));
    SET @failed = @failed + 1;
    PRINT ' 17 recovery public key of the wrong length refused                 FAIL';
END TRY
BEGIN CATCH
    PRINT ' 17 recovery public key of the wrong length refused                 PASS';
END CATCH

-- ---------------------------------------------------------------------------
-- Records
-- ---------------------------------------------------------------------------

BEGIN TRY
    INSERT INTO [Crypto].[Record]
        (RecordId, UserId, GenerationId, RecordKind, SchemaVersion, [Version], Envelope)
    VALUES (NEWID(), @userA, @genA1, 'journal.entry', 1, 1, @env47);
    SET @failed = @failed + 1;
    PRINT ' 18 record envelope below the 48-byte floor refused                 FAIL';
END TRY
BEGIN CATCH
    PRINT ' 18 record envelope below the 48-byte floor refused                 PASS';
END CATCH

BEGIN TRY
    INSERT INTO [Crypto].[Record]
        (RecordId, UserId, GenerationId, RecordKind, SchemaVersion, [Version], Envelope)
    VALUES (NEWID(), @userA, @genA1, 'journal.entry', 1, 0, @env48);
    SET @failed = @failed + 1;
    PRINT ' 19 record version zero refused                                     FAIL';
END TRY
BEGIN CATCH
    PRINT ' 19 record version zero refused                                     PASS';
END CATCH

-- ---------------------------------------------------------------------------
-- KDF profiles
-- ---------------------------------------------------------------------------

BEGIN TRY
    INSERT INTO [Crypto].[KdfProfile]
        (Algorithm, MemoryKiB, Iterations, Parallelism, SaltBytes, OutputBytes, IsCurrent)
    VALUES ('ARGON2ID', 131072, 3, 4, 16, 32, 1);
    SET @failed = @failed + 1;
    PRINT ' 20 second current KDF profile refused                              FAIL';
END TRY
BEGIN CATCH
    PRINT ' 20 second current KDF profile refused                              PASS';
END CATCH

/*  The seeded profile is provisional and says so. This assertion exists to be
    noticed: it documents that production parameters have not been measured,
    and it is the line to change when D6 and D7 are decided. */
IF EXISTS (SELECT 1 FROM [Crypto].[KdfProfile] WHERE IsCurrent = 1 AND IsProvisional = 1)
    PRINT ' 21 current KDF profile is still provisional (D6/D7 open)           PASS';
ELSE IF EXISTS (SELECT 1 FROM [Crypto].[KdfProfile] WHERE IsCurrent = 1 AND IsProvisional = 0)
    PRINT ' 21 current KDF profile is measured - update this assertion         PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 21 exactly one current KDF profile exists                          FAIL';
END

-- ---------------------------------------------------------------------------
-- The rule the whole scheme rests on: the server never receives the password.
--
-- Asserted by name, across every procedure in the database. A procedure that
-- takes a password is the one change that would quietly turn client-side
-- encryption back into server-side encryption while every other test still
-- passed. Wrapper parameters are not caught by this and should not be: a
-- wrapper is ciphertext, and its name says which key opens it.
-- ---------------------------------------------------------------------------

DECLARE @plaintextParams int =
    (SELECT COUNT(*)
       FROM sys.parameters p
       JOIN sys.objects o ON o.object_id = p.object_id
      WHERE o.type = 'P'
        AND p.name IN ('@Password', '@PlainPassword', '@PlainTextPassword',
                       '@Passphrase', '@RecoveryPhrase', '@Mnemonic',
                       '@RecoveryEntropy', '@MasterSecret', '@Dek'));

IF @plaintextParams = 0
    PRINT ' 22 no procedure accepts a password, phrase or raw key            PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 22 no procedure accepts a password, phrase or raw key            FAIL';
END

/*  The section 4.3 allow-list, extended to the client-derived scheme.

    The version 1 list names four procedures against Identity.User; these are
    the version 2 equivalents against Identity.UserCredential, and each is on
    the credential path rather than on it for convenience:

      usp_UserCredential_GetForLogin      verify an authentication secret
      usp_UserCredential_GetKdfParameters the salt a device needs before it
                                          can derive anything
      usp_UserCredential_SetAuthoritative replace the stored verifier
      usp_User_RegisterClientDerived      set the first one -- the counterpart
                                          of usp_User_Register on the v1 list
      usp_User_DeleteAccount              erase it with the account

    A name added here that is not one of those five is the signal that the
    rule has stopped meaning anything. Watch for that rather than for the
    length of the list. */
DECLARE @authSecretLeaks int =
    (SELECT COUNT(*)
       FROM sys.sql_modules m
       JOIN sys.objects o ON o.object_id = m.object_id
      WHERE o.type = 'P'
        AND o.name NOT IN ('usp_UserCredential_GetForLogin',
                           'usp_UserCredential_GetKdfParameters',
                           'usp_UserCredential_SetAuthoritative',
                           'usp_User_RegisterClientDerived',
                           'usp_User_DeleteAccount')
        AND (m.definition LIKE '%AuthSecretHash%'
          OR m.definition LIKE '%AuthSecretSalt%'));

IF @authSecretLeaks = 0
    PRINT ' 23 no procedure outside the login path reads auth material       PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 23 no procedure outside the login path reads auth material       FAIL';
END

-- ---------------------------------------------------------------------------
-- Procedure behaviour
-- ---------------------------------------------------------------------------

DECLARE @genResult TABLE (Succeeded bit, FailureCode varchar(64),
                          GenerationId uniqueidentifier);
DECLARE @saveResult TABLE (Succeeded bit, FailureCode varchar(64),
                           CurrentVersion int);

DECLARE @userC uniqueidentifier = '0C0DE000-0000-4000-A000-00000000000C';
DECLARE @genC  uniqueidentifier = '0C0DE000-0000-4000-6E00-00000000000C';
DELETE FROM [Identity].[User] WHERE UserId = @userC;
INSERT INTO [Identity].[User] (UserId, Email, NormalisedEmail)
VALUES (@userC, N'crypto_test_c@test.invalid', N'CRYPTO_TEST_C@TEST.INVALID');

/*  userA has an authoritative version 2 credential, inserted at assertion 2.
    The version 1 login path must refuse it outright rather than return
    material that happens to be unused. */
DECLARE @v1Rows TABLE (UserId uniqueidentifier, PasswordHash varbinary(256),
                       PasswordSalt varbinary(128), PasswordIterations int,
                       IsLockedOut bit, LockoutEndUtc datetime2(3));
INSERT @v1Rows EXEC [Identity].[usp_User_GetForLogin] @Email = N'crypto_test_a@test.invalid';

IF NOT EXISTS (SELECT 1 FROM @v1Rows)
    PRINT ' 24 version 1 login path refuses a migrated account               PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 24 version 1 login path refuses a migrated account               FAIL';
END

DELETE FROM @genResult;
INSERT @genResult EXEC [Crypto].[usp_Generation_CreateInitial]
    @UserId = @userC, @GenerationId = @genC, @PasswordWrapper = @env48,
    @RecoveryWrapper = @env48, @RecoveryPublicKey = @pk32;

IF EXISTS (SELECT 1 FROM @genResult WHERE Succeeded = 1)
   AND (SELECT COUNT(*) FROM [Crypto].[Generation]
         WHERE UserId = @userC AND [State] = 'ACTIVE') = 1
   AND (SELECT COUNT(*) FROM [Crypto].[Wrapper] w
         JOIN [Crypto].[Generation] g ON g.GenerationId = w.GenerationId
        WHERE g.UserId = @userC) = 2
   AND (SELECT COUNT(*) FROM [Crypto].[RecoveryVerifier] v
         JOIN [Crypto].[Generation] g ON g.GenerationId = v.GenerationId
        WHERE g.UserId = @userC) = 1
    PRINT ' 25 initial generation creates key, wrappers and verifier at once PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 25 initial generation creates key, wrappers and verifier at once FAIL';
END

DELETE FROM @genResult;
INSERT @genResult EXEC [Crypto].[usp_Generation_CreateInitial]
    @UserId = @userC, @GenerationId = @genC, @PasswordWrapper = @env48,
    @RecoveryWrapper = @env48, @RecoveryPublicKey = @pk32;

IF EXISTS (SELECT 1 FROM @genResult WHERE Succeeded = 0 AND FailureCode = 'GENERATION_EXISTS')
    PRINT ' 26 a second initial generation is refused                        PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 26 a second initial generation is refused                        FAIL';
END

DECLARE @recordId uniqueidentifier = NEWID();

DELETE FROM @saveResult;
INSERT @saveResult EXEC [Crypto].[usp_Record_Save]
    @UserId = @userC, @RecordId = @recordId, @RecordKind = 'journal.entry',
    @SchemaVersion = 1, @Version = 1, @Envelope = @env48;

/*  The client never names a generation. The record must land in whichever
    generation is ACTIVE, resolved server-side. */
IF EXISTS (SELECT 1 FROM @saveResult WHERE Succeeded = 1)
   AND EXISTS (SELECT 1 FROM [Crypto].[Record] r
                JOIN [Crypto].[Generation] g ON g.GenerationId = r.GenerationId
               WHERE r.RecordId = @recordId AND g.[State] = 'ACTIVE'
                 AND g.UserId = @userC)
    PRINT ' 27 a saved record lands in the active generation                 PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 27 a saved record lands in the active generation                 FAIL';
END

DELETE FROM @saveResult;
INSERT @saveResult EXEC [Crypto].[usp_Record_Save]
    @UserId = @userC, @RecordId = @recordId, @RecordKind = 'journal.entry',
    @SchemaVersion = 1, @Version = 1, @Envelope = @env48;

IF EXISTS (SELECT 1 FROM @saveResult WHERE Succeeded = 0 AND FailureCode = 'VERSION_CONFLICT')
    PRINT ' 28 a stale write is refused as a version conflict                PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 28 a stale write is refused as a version conflict                FAIL';
END

/*  Another account writing to a record id it does not own must get the same
    answer as an ordinary conflict. Anything more specific confirms the id
    exists, and there is no legitimate way to have guessed it. */
DELETE FROM @saveResult;
INSERT @saveResult EXEC [Crypto].[usp_Record_Save]
    @UserId = @userB, @RecordId = @recordId, @RecordKind = 'journal.entry',
    @SchemaVersion = 1, @Version = 1, @Envelope = @env48;

IF EXISTS (SELECT 1 FROM @saveResult WHERE Succeeded = 0 AND FailureCode = 'VERSION_CONFLICT')
   AND (SELECT UserId FROM [Crypto].[Record] WHERE RecordId = @recordId) = @userC
    PRINT ' 29 another account cannot take over a record id                  PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 29 another account cannot take over a record id                  FAIL';
END

DECLARE @foreignRead TABLE (RecordId uniqueidentifier, RecordKind varchar(32),
                            SchemaVersion int, [Version] int,
                            Envelope varbinary(max), GenerationNumber int,
                            CreatedOn datetime2(3), ModifiedOn datetime2(3));
INSERT @foreignRead EXEC [Crypto].[usp_Record_Get]
    @UserId = @userB, @RecordId = @recordId;

IF NOT EXISTS (SELECT 1 FROM @foreignRead)
    PRINT ' 30 a record is unreadable by another account                     PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 30 a record is unreadable by another account                     FAIL';
END

/*  Account deletion must reach the encrypted records and the whole key
    hierarchy, or a closed account leaves its journal on disk. The C# erasure
    test scans every table carrying a UserId; wrappers and verifiers carry
    none, so they are checked here by their generation instead. */
DECLARE @deleteResult TABLE (Succeeded bit, FailureCode varchar(64));
INSERT @deleteResult EXEC [Identity].[usp_User_DeleteAccount] @UserId = @userC;

IF NOT EXISTS (SELECT 1 FROM [Crypto].[Record]           WHERE UserId = @userC)
   AND NOT EXISTS (SELECT 1 FROM [Crypto].[Generation]   WHERE UserId = @userC)
   AND NOT EXISTS (SELECT 1 FROM [Identity].[UserCredential] WHERE UserId = @userC)
   AND NOT EXISTS (SELECT 1 FROM [Crypto].[Wrapper] w
                    LEFT JOIN [Crypto].[Generation] g ON g.GenerationId = w.GenerationId
                   WHERE g.GenerationId IS NULL)
   AND NOT EXISTS (SELECT 1 FROM [Crypto].[RecoveryVerifier] v
                    LEFT JOIN [Crypto].[Generation] g ON g.GenerationId = v.GenerationId
                   WHERE g.GenerationId IS NULL)
    PRINT ' 31 account deletion reaches records, keys and wrappers           PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 31 account deletion reaches records, keys and wrappers           FAIL';
END

DELETE FROM [Identity].[User] WHERE UserId = @userC;

-- ---------------------------------------------------------------------------
-- Registration on the client-derived path
-- ---------------------------------------------------------------------------

DECLARE @regResult TABLE (Succeeded bit, FailureCode varchar(64),
                          UserId uniqueidentifier, GenerationId uniqueidentifier);
DECLARE @regEmail  nvarchar(256) = N'crypto_test_reg@test.invalid';
DECLARE @regNorm   nvarchar(256) = N'CRYPTO_TEST_REG@TEST.INVALID';
DECLARE @regUserId uniqueidentifier;
DECLARE @genReg   uniqueidentifier = '0C0DE000-0000-4000-6E00-0000000000E1';
DECLARE @genChild uniqueidentifier = '0C0DE000-0000-4000-6E00-0000000000E2';

DECLARE @adult DATE = DATEADD(YEAR, -30, CAST(SYSUTCDATETIME() AS DATE));
DECLARE @salt16a varbinary(32)  = CAST(REPLICATE(CAST(0xC1 AS binary(1)), 16) AS varbinary(32));
DECLARE @salt16b varbinary(32)  = CAST(REPLICATE(CAST(0xC2 AS binary(1)), 16) AS varbinary(32));
DECLARE @salt128 varbinary(128) = CAST(REPLICATE(CAST(0xC3 AS binary(1)), 16) AS varbinary(128));
DECLARE @child DATE = DATEADD(YEAR, -12, CAST(SYSUTCDATETIME() AS DATE));

-- Clean up any previous run before asserting anything.
SET @regUserId = (SELECT UserId FROM [Identity].[User] WHERE NormalisedEmail = @regNorm);
IF @regUserId IS NOT NULL
BEGIN
    DELETE FROM [Crypto].[Record]           WHERE UserId = @regUserId;
    DELETE FROM [Crypto].[RecoveryVerifier] WHERE GenerationId IN
           (SELECT GenerationId FROM [Crypto].[Generation] WHERE UserId = @regUserId);
    DELETE FROM [Crypto].[Wrapper]          WHERE GenerationId IN
           (SELECT GenerationId FROM [Crypto].[Generation] WHERE UserId = @regUserId);
    DELETE FROM [Crypto].[Generation]       WHERE UserId = @regUserId;
    DELETE FROM [Identity].[UserCredential] WHERE UserId = @regUserId;
    DELETE FROM [Identity].[UserRole]       WHERE UserId = @regUserId;
    DELETE FROM [Identity].[Profile]        WHERE UserId = @regUserId;
    DELETE FROM [Audit].[AuditLog]          WHERE ActorUserId = @regUserId;
    DELETE FROM [Identity].[User]           WHERE UserId = @regUserId;
END

INSERT @regResult EXEC [Identity].[usp_User_RegisterClientDerived]
    @Email = @regEmail, @DateOfBirth = @adult, @GenerationId = @genReg,
    @AuthSecretHash = @pk32,
    @AuthSecretSalt = @salt16a,
    @KdfProfileId = @profile,
    @PasswordWrapper = @env48, @RecoveryWrapper = @env48,
    @RecoveryPublicKey = @pk32;

SET @regUserId = (SELECT TOP 1 UserId FROM @regResult);

/*  One transaction, or none. Every partial outcome here is unrecoverable
    without an operator reaching into her account, and this platform does not
    give operators that reach. */
IF EXISTS (SELECT 1 FROM @regResult WHERE Succeeded = 1)
   AND @regUserId IS NOT NULL
   AND EXISTS (SELECT 1 FROM [Identity].[UserCredential]
                WHERE UserId = @regUserId AND CredentialVersion = 2 AND IsAuthoritative = 1)
   AND (SELECT COUNT(*) FROM [Crypto].[Generation]
         WHERE UserId = @regUserId AND [State] = 'ACTIVE' AND GenerationNumber = 1) = 1
   AND (SELECT COUNT(*) FROM [Crypto].[Wrapper] w
         JOIN [Crypto].[Generation] g ON g.GenerationId = w.GenerationId
        WHERE g.UserId = @regUserId) = 2
   AND (SELECT COUNT(*) FROM [Crypto].[RecoveryVerifier] v
         JOIN [Crypto].[Generation] g ON g.GenerationId = v.GenerationId
        WHERE g.UserId = @regUserId) = 1
   AND EXISTS (SELECT 1 FROM [Identity].[UserRole] ur
                JOIN [Identity].[Role] r ON r.RoleId = ur.RoleId
               WHERE ur.UserId = @regUserId AND r.Name = 'Member')
    PRINT ' 33 registration creates account, credential, key and wrappers at once PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 33 registration creates account, credential, key and wrappers at once FAIL';
END

/*  A version 2 account has no server-verified password, and the version 1
    login path must refuse it rather than return an all-NULL row a caller
    might mistake for a valid credential. */
DELETE FROM @v1Rows;
INSERT @v1Rows EXEC [Identity].[usp_User_GetForLogin] @Email = @regEmail;

IF NOT EXISTS (SELECT 1 FROM @v1Rows)
   AND NOT EXISTS (SELECT 1 FROM [Identity].[User]
                    WHERE UserId = @regUserId AND PasswordHash IS NOT NULL)
    PRINT ' 34 a client-derived account holds no server-side password        PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 34 a client-derived account holds no server-side password        FAIL';
END

/*  The age gate is duplicated between usp_User_Register and this procedure,
    because sharing it would mean one procedure calling another inside a
    transaction it did not open. Duplication is only safe while something
    holds the copies in step. This is that something: the same under-age date
    must be refused identically by both, and neither may leave a row behind. */
DECLARE @childResult TABLE (Succeeded bit, FailureCode varchar(64),
                            UserId uniqueidentifier, GenerationId uniqueidentifier);
DECLARE @childV1 TABLE (Succeeded bit, FailureCode varchar(50),
                        UserId uniqueidentifier);
DECLARE @childEmail nvarchar(256) = N'crypto_test_child@test.invalid';

INSERT @childResult EXEC [Identity].[usp_User_RegisterClientDerived]
    @Email = @childEmail, @DateOfBirth = @child, @GenerationId = @genChild,
    @AuthSecretHash = @pk32,
    @AuthSecretSalt = @salt16b,
    @KdfProfileId = @profile,
    @PasswordWrapper = @env48, @RecoveryWrapper = @env48,
    @RecoveryPublicKey = @pk32;

INSERT @childV1 EXEC [Identity].[usp_User_Register]
    @Email = @childEmail, @PasswordHash = @pk32,
    @PasswordSalt = @salt128,
    @PasswordIterations = 210000, @DateOfBirth = @child;

IF EXISTS (SELECT 1 FROM @childResult WHERE Succeeded = 0 AND FailureCode = 'UNDER_MINIMUM_AGE')
   AND EXISTS (SELECT 1 FROM @childV1 WHERE Succeeded = 0 AND FailureCode = 'UNDER_MINIMUM_AGE')
   AND NOT EXISTS (SELECT 1 FROM [Identity].[User]
                    WHERE NormalisedEmail = UPPER(@childEmail))
    PRINT ' 35 both registration paths refuse the same under-age date        PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 35 both registration paths refuse the same under-age date        FAIL';
END

/*  Deleting a client-derived account has to reach the same places as any
    other, and it is a different shape of account -- no password material, a
    credential row, a generation. */
DECLARE @regDelete TABLE (Succeeded bit, FailureCode varchar(64));
INSERT @regDelete EXEC [Identity].[usp_User_DeleteAccount] @UserId = @regUserId;

IF NOT EXISTS (SELECT 1 FROM [Identity].[User] WHERE UserId = @regUserId)
   AND NOT EXISTS (SELECT 1 FROM [Identity].[UserCredential] WHERE UserId = @regUserId)
   AND NOT EXISTS (SELECT 1 FROM [Crypto].[Generation] WHERE UserId = @regUserId)
    PRINT ' 36 deleting a client-derived account leaves nothing behind       PASS';
ELSE
BEGIN
    SET @failed = @failed + 1;
    PRINT ' 36 deleting a client-derived account leaves nothing behind       FAIL';
END

DELETE FROM [Identity].[User] WHERE NormalisedEmail IN (@regNorm, UPPER(@childEmail));

-- ---------------------------------------------------------------------------
-- Clean up on the way out.
-- ---------------------------------------------------------------------------
DELETE FROM [Crypto].[Record]           WHERE UserId IN (@userA, @userB);
DELETE FROM [Crypto].[RecoveryVerifier] WHERE GenerationId IN
       (SELECT GenerationId FROM [Crypto].[Generation] WHERE UserId IN (@userA, @userB));
DELETE FROM [Crypto].[Wrapper]          WHERE GenerationId IN
       (SELECT GenerationId FROM [Crypto].[Generation] WHERE UserId IN (@userA, @userB));
DELETE FROM [Crypto].[Generation]       WHERE UserId IN (@userA, @userB);
DELETE FROM [Identity].[UserCredential] WHERE UserId IN (@userA, @userB);
DELETE FROM [Identity].[User]           WHERE UserId IN (@userA, @userB);

PRINT '';
PRINT '---------------------------------------------';
PRINT 'TOTAL: 36  FAILED: ' + CAST(@failed AS varchar(10));
PRINT '---------------------------------------------';

IF @failed > 0
    THROW 51000, 'Crypto invariant assertions failed.', 1;
GO
