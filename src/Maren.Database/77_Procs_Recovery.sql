/*  77_Procs_Recovery.sql

    The Path R state machine. Specification: WLOS_RESET_AUTHORIZATION_V1.md §5.

        R0  challenge issued        for any address, in constant time
        R1  proof verified          challenge consumed, wrapper released,
                                    reset grant issued
        R2  completion              the wrapper opened; her generation and her
                                    old journal survive
        R3  completion, degraded    the wrapper did not open; a new generation,
                                    and the old one is not recovered

    **No procedure here receives the recovery phrase, the entropy behind it,
    the key it derives, or a password.** What arrives is a signature, verified
    against a public key this platform already held, and — at completion —
    material the device produced. That is asserted by name across every
    procedure in the database by the crypto assertion suite.

    Why verification happens in the application
    -------------------------------------------
    Ed25519 verification is not available in T-SQL, and putting it there would
    mean the comparison happened somewhere without a constant-time primitive.
    So these procedures hand out the public key and the nonce, the API
    verifies, and the API comes back. The consumption is still atomic here,
    which is the part that has to be.

    The consequence is worth stating: `usp_Recovery_ConsumeChallenge` spends
    the challenge **before** anyone knows whether the signature is good. That
    is deliberate and is what makes each guess cost a round trip.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- Crypto.usp_Recovery_IssueChallenge   (R0)
-- ---------------------------------------------------------------------------
/*
    Issues a nonce for any address, whether or not it has an account.

    Returns the same shape either way. A caller cannot tell a registered
    address from an unregistered one, which is the whole reason this writes a
    row for an address it has never seen.

    Rate limits, from the specification:
      * per account   5 / hour, 20 / day
      * per IP        20 / hour
      * failures      10 / day, then Path R locks for 24 hours

    A refused request still returns a challenge. Saying "too many attempts"
    would answer the question the limit exists to stop being answerable: it
    would only ever be said about an address that has an account. The
    challenge it hands back is real and simply will not verify, which costs an
    attacker a round trip and tells him nothing.
*/
IF OBJECT_ID('Crypto.usp_Recovery_IssueChallenge') IS NOT NULL
    DROP PROCEDURE [Crypto].[usp_Recovery_IssueChallenge];
GO
CREATE PROCEDURE [Crypto].[usp_Recovery_IssueChallenge]
    @Email      NVARCHAR(256),
    @Nonce      VARBINARY(32),
    @IpAddress  VARCHAR(45) = NULL,
    @TtlMinutes INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @normalised NVARCHAR(256) = UPPER(LTRIM(RTRIM(@Email)));
    DECLARE @now DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @challengeId UNIQUEIDENTIFIER = NEWID();

    /*  Opportunistic sweep. Challenges are short-lived and there is no reason
        to keep one a day after it expired; a table that only grows is a table
        somebody has to remember to prune. Bounded so this never becomes the
        expensive part of an ordinary request. */
    DELETE TOP (200) FROM [Crypto].[RecoveryChallenge]
     WHERE ExpiresOn < DATEADD(DAY, -1, @now) AND [State] <> 'SPENT';

    DECLARE @userId UNIQUEIDENTIFIER =
        (SELECT UserId FROM [Identity].[User]
          WHERE NormalisedEmail = @normalised AND IsDeleted = 0);

    DECLARE @generationId UNIQUEIDENTIFIER =
        (SELECT GenerationId FROM [Crypto].[Generation]
          WHERE UserId = @userId AND [State] = 'ACTIVE');

    /*  Limits are evaluated, and their only effect is to detach the challenge
        from the account. It is still issued, still the right shape, and will
        simply fail to verify -- which is what a limit has to look like on an
        endpoint that must not confirm an address exists. */
    IF @userId IS NOT NULL
    BEGIN
        DECLARE @lastHour INT = (
            SELECT COUNT(*) FROM [Crypto].[RecoveryChallenge]
             WHERE UserId = @userId AND IssuedOn > DATEADD(HOUR, -1, @now));

        DECLARE @lastDay INT = (
            SELECT COUNT(*) FROM [Crypto].[RecoveryChallenge]
             WHERE UserId = @userId AND IssuedOn > DATEADD(DAY, -1, @now));

        DECLARE @failures INT = (
            SELECT COUNT(*) FROM [Crypto].[RecoveryChallenge]
             WHERE UserId = @userId AND [State] = 'CONSUMED'
               AND ConsumedOn > DATEADD(DAY, -1, @now));

        IF @lastHour >= 5 OR @lastDay >= 20 OR @failures >= 10
        BEGIN
            SET @userId = NULL;
            SET @generationId = NULL;
        END
    END

    IF @IpAddress IS NOT NULL
       AND (SELECT COUNT(*) FROM [Crypto].[RecoveryChallenge]
             WHERE IpAddress = @IpAddress
               AND IssuedOn > DATEADD(HOUR, -1, @now)) >= 20
    BEGIN
        SET @userId = NULL;
        SET @generationId = NULL;
    END

    INSERT INTO [Crypto].[RecoveryChallenge]
        (ChallengeId, UserId, GenerationId, Nonce, [State],
         IssuedOn, ExpiresOn, IpAddress)
    VALUES
        (@challengeId, @userId, @generationId, @Nonce, 'ISSUED',
         @now, DATEADD(MINUTE, @TtlMinutes, @now), @IpAddress);

    SELECT @challengeId AS ChallengeId,
           @Nonce       AS Nonce,
           DATEADD(MINUTE, @TtlMinutes, @now) AS ExpiresOn;
END
GO

-- ---------------------------------------------------------------------------
-- Crypto.usp_Recovery_ConsumeChallenge   (R1, first half)
-- ---------------------------------------------------------------------------
/*
    Spends a challenge and hands back what is needed to check the signature.

    **Consumed on any attempt, valid or not.** The caller has not verified
    anything yet when this runs, and that is the point: a challenge that
    survived a failed attempt would let an attacker grind guesses against one
    nonce without paying for a new one.

    Returns no rows for an unknown, expired or already-spent challenge. The
    API turns every one of those into the same generic failure, so this
    procedure does not have to distinguish them and deliberately does not.

    It does **not** return the wrapper. That is released only once a signature
    has verified -- see usp_Recovery_IssueGrant. `wrap/recovery/{k}` is the
    target of any offline attack on the phrase, and handing it to whoever
    knows an email address would be an oracle.
*/
IF OBJECT_ID('Crypto.usp_Recovery_ConsumeChallenge') IS NOT NULL
    DROP PROCEDURE [Crypto].[usp_Recovery_ConsumeChallenge];
GO
CREATE PROCEDURE [Crypto].[usp_Recovery_ConsumeChallenge]
    @ChallengeId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @spent TABLE (
        UserId        UNIQUEIDENTIFIER,
        GenerationId  UNIQUEIDENTIFIER,
        Nonce         VARBINARY(32)
    );

    /*  One statement, so two callers racing the same challenge cannot both
        come away believing they consumed it. The WHERE clause is the guard:
        a row already out of ISSUED matches nothing. */
    UPDATE [Crypto].[RecoveryChallenge]
       SET [State]    = 'CONSUMED',
           ConsumedOn = SYSUTCDATETIME()
    OUTPUT inserted.UserId, inserted.GenerationId, inserted.Nonce INTO @spent
     WHERE ChallengeId = @ChallengeId
       AND [State]     = 'ISSUED'
       AND ExpiresOn   > SYSUTCDATETIME();

    SELECT s.UserId,
           s.GenerationId,
           s.Nonce,
           v.PublicKey,
           g.GenerationNumber
      FROM @spent s
      LEFT JOIN [Crypto].[RecoveryVerifier] v ON v.GenerationId = s.GenerationId
      LEFT JOIN [Crypto].[Generation] g       ON g.GenerationId = s.GenerationId;
END
GO

-- ---------------------------------------------------------------------------
-- Crypto.usp_Recovery_IssueGrant   (R1, second half)
-- ---------------------------------------------------------------------------
/*
    The signature verified. Releases the recovery wrapper and issues the grant
    that can complete a reset.

    Both halves of R1 happen here, together: this is the first moment anything
    is handed out, and the last moment at which nothing has changed. She can
    still walk away -- an abandoned grant expires and the account is untouched.

    Refuses a challenge that is not CONSUMED. A grant on a challenge nobody
    attempted, or on one already granted, is not a state worth being able to
    reach; the table refuses it too.
*/
IF OBJECT_ID('Crypto.usp_Recovery_IssueGrant') IS NOT NULL
    DROP PROCEDURE [Crypto].[usp_Recovery_IssueGrant];
GO
CREATE PROCEDURE [Crypto].[usp_Recovery_IssueGrant]
    @ChallengeId    UNIQUEIDENTIFIER,
    @GrantHash      VARBINARY(32),
    @GrantMinutes   INT = 5
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @granted TABLE (
        UserId       UNIQUEIDENTIFIER,
        GenerationId UNIQUEIDENTIFIER
    );

    UPDATE [Crypto].[RecoveryChallenge]
       SET [State]         = 'VERIFIED',
           GrantHash       = @GrantHash,
           GrantExpiresOn  = DATEADD(MINUTE, @GrantMinutes, SYSUTCDATETIME())
    OUTPUT inserted.UserId, inserted.GenerationId INTO @granted
     WHERE ChallengeId = @ChallengeId
       AND [State]     = 'CONSUMED'
       AND UserId IS NOT NULL;

    IF NOT EXISTS (SELECT 1 FROM @granted)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'RECOVERY_FAILED' AS FailureCode,
               CAST(NULL AS UNIQUEIDENTIFIER) AS UserId,
               CAST(NULL AS UNIQUEIDENTIFIER) AS GenerationId,
               CAST(NULL AS INT) AS GenerationNumber,
               CAST(NULL AS VARBINARY(MAX)) AS RecoveryWrapper;
        RETURN;
    END

    /*  She is told, now, before anything changes. A recovery phrase being used
        is the loudest security event this account has; if it was not her, the
        window in which she can do something about it starts here and not at
        completion. */
    INSERT INTO [Audit].[AuditLog]
        (ActorUserId, ActorKind, [Action], EntityType, EntityId)
    SELECT g.UserId, 'user', 'Recovery.PhraseUsed', 'User',
           CONVERT(NVARCHAR(50), g.UserId)
      FROM @granted g;

    SELECT CAST(1 AS BIT) AS Succeeded,
           CAST(NULL AS VARCHAR(64)) AS FailureCode,
           g.UserId,
           g.GenerationId,
           gen.GenerationNumber,
           w.Envelope AS RecoveryWrapper
      FROM @granted g
      JOIN [Crypto].[Generation] gen ON gen.GenerationId = g.GenerationId
      LEFT JOIN [Crypto].[Wrapper] w
             ON w.GenerationId = g.GenerationId AND w.WrapperKind = 'RECOVERY';
END
GO

-- ---------------------------------------------------------------------------
-- Crypto.usp_Recovery_Complete   (R2)
-- ---------------------------------------------------------------------------
/*
    The wrapper opened. She has her data key, and she has chosen a new
    password.

    **Path R changes no generation.** Her old journal is still hers: the data
    key never changed, only the key-encryption key that wraps it. That is the
    whole difference between this path and an email reset, and it is why the
    phrase is worth writing down.

    What moves:
      wrap/pw      replaced, under the new key-encryption key
      wrap/rec     untouched -- the phrase still works afterwards
      wrap/device  retained; the data key did not change and the devices are
                   still hers
      sessions     all revoked, and the security stamp bumped with them

    The stamp matters as much as the revocation. Killing refresh tokens stops
    her getting a new access token; it does nothing about one already issued,
    which stays correctly signed for up to fifteen minutes. On the one path
    that exists because something may have gone wrong, fifteen minutes is the
    wrong answer.
*/
IF OBJECT_ID('Crypto.usp_Recovery_Complete') IS NOT NULL
    DROP PROCEDURE [Crypto].[usp_Recovery_Complete];
GO
CREATE PROCEDURE [Crypto].[usp_Recovery_Complete]
    @GrantHash        VARBINARY(32),
    @AuthSecretHash   VARBINARY(64),
    @AuthSecretSalt   VARBINARY(32),
    @KdfProfileId     INT,
    @PasswordWrapper  VARBINARY(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @userId UNIQUEIDENTIFIER, @generationId UNIQUEIDENTIFIER;

    SELECT @userId = UserId, @generationId = GenerationId
      FROM [Crypto].[RecoveryChallenge]
     WHERE GrantHash = @GrantHash
       AND [State] = 'VERIFIED'
       AND GrantExpiresOn > SYSUTCDATETIME();

    IF @userId IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'RECOVERY_FAILED' AS FailureCode;
        RETURN;
    END

    BEGIN TRAN;

        UPDATE [Crypto].[RecoveryChallenge]
           SET [State] = 'SPENT'
         WHERE GrantHash = @GrantHash;

        UPDATE [Identity].[UserCredential]
           SET IsAuthoritative = 0, SupersededOn = SYSUTCDATETIME()
         WHERE UserId = @userId AND IsAuthoritative = 1;

        INSERT INTO [Identity].[UserCredential]
            (UserId, CredentialVersion, AuthSecretHash, AuthSecretSalt,
             KdfProfileId, IsAuthoritative)
        VALUES
            (@userId, 2, @AuthSecretHash, @AuthSecretSalt, @KdfProfileId, 1);

        DELETE FROM [Crypto].[Wrapper]
         WHERE GenerationId = @generationId AND WrapperKind = 'PASSWORD';

        INSERT INTO [Crypto].[Wrapper] (GenerationId, WrapperKind, Envelope)
        VALUES (@generationId, 'PASSWORD', @PasswordWrapper);

        DELETE FROM [Identity].[RefreshToken] WHERE UserId = @userId;

        UPDATE [Identity].[User]
           SET SecurityStamp = NEWID(), ModifiedOn = SYSUTCDATETIME()
         WHERE UserId = @userId;

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId)
        VALUES
            (@userId, 'user', 'Recovery.Completed', 'User',
             CONVERT(NVARCHAR(50), @userId));

    COMMIT;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(64)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- Crypto.usp_Recovery_CompleteUnrecoverable   (R3)
-- ---------------------------------------------------------------------------
/*
    The signature verified and the wrapper did not open.

    **This is cryptographic data loss for that generation**, and the name says
    so. It is not a degraded mode and not a partial success: the entropy was
    right, so the phrase is hers, but the wrapper that held the data key is
    absent or corrupt and nobody -- not she, not this platform, not an
    operator -- can derive that key again.

    She gets her account back and a new generation to write into. Her old
    records stay exactly where they are, as ciphertext, and are not deleted:
    a device somewhere may still hold the data key, and destroying the only
    remaining copy of what she wrote on the strength of one failed unwrap
    would be the worst possible response to it.

    The old recovery wrapper is kept too, unopenable as it is. Deleting it
    would remove the evidence of what happened, and there is nothing to gain
    by removing a blob nobody can use.
*/
IF OBJECT_ID('Crypto.usp_Recovery_CompleteUnrecoverable') IS NOT NULL
    DROP PROCEDURE [Crypto].[usp_Recovery_CompleteUnrecoverable];
GO
CREATE PROCEDURE [Crypto].[usp_Recovery_CompleteUnrecoverable]
    @GrantHash          VARBINARY(32),
    @AuthSecretHash     VARBINARY(64),
    @AuthSecretSalt     VARBINARY(32),
    @KdfProfileId       INT,
    @NewGenerationId    UNIQUEIDENTIFIER,
    @PasswordWrapper    VARBINARY(MAX),
    @RecoveryWrapper    VARBINARY(MAX),
    @RecoveryPublicKey  VARBINARY(32)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @userId UNIQUEIDENTIFIER, @oldGenerationId UNIQUEIDENTIFIER;

    SELECT @userId = UserId, @oldGenerationId = GenerationId
      FROM [Crypto].[RecoveryChallenge]
     WHERE GrantHash = @GrantHash
       AND [State] = 'VERIFIED'
       AND GrantExpiresOn > SYSUTCDATETIME();

    IF @userId IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'RECOVERY_FAILED' AS FailureCode,
               CAST(NULL AS INT) AS GenerationNumber;
        RETURN;
    END

    DECLARE @nextNumber INT =
        (SELECT ISNULL(MAX(GenerationNumber), 0) + 1
           FROM [Crypto].[Generation] WHERE UserId = @userId);

    IF @nextNumber > 65535
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'GENERATION_LIMIT' AS FailureCode,
               CAST(NULL AS INT) AS GenerationNumber;
        RETURN;
    END

    BEGIN TRAN;

        UPDATE [Crypto].[RecoveryChallenge]
           SET [State] = 'SPENT'
         WHERE GrantHash = @GrantHash;

        /*  Retired before the new one is created, because exactly one ACTIVE
            generation per account is a filtered unique index and not a
            convention. The order is what keeps the invariant true at every
            committed state. */
        UPDATE [Crypto].[Generation]
           SET [State] = 'DORMANT', RetiredOn = SYSUTCDATETIME()
         WHERE GenerationId = @oldGenerationId;

        INSERT INTO [Crypto].[Generation]
            (GenerationId, UserId, GenerationNumber, [State])
        VALUES
            (@NewGenerationId, @userId, @nextNumber, 'ACTIVE');

        INSERT INTO [Crypto].[Wrapper] (GenerationId, WrapperKind, Envelope)
        VALUES (@NewGenerationId, 'PASSWORD', @PasswordWrapper),
               (@NewGenerationId, 'RECOVERY', @RecoveryWrapper);

        INSERT INTO [Crypto].[RecoveryVerifier] (GenerationId, PublicKey)
        VALUES (@NewGenerationId, @RecoveryPublicKey);

        /*  The old password wrapper goes: the key-encryption key it was
            sealed under is the old password's, and that password is being
            replaced. Device wrappers for the old generation go with it -- a
            device must not silently hold a key for a generation she can no
            longer reach through any other route. */
        DELETE FROM [Crypto].[Wrapper]
         WHERE GenerationId = @oldGenerationId
           AND WrapperKind IN ('PASSWORD', 'DEVICE');

        UPDATE [Identity].[UserCredential]
           SET IsAuthoritative = 0, SupersededOn = SYSUTCDATETIME()
         WHERE UserId = @userId AND IsAuthoritative = 1;

        INSERT INTO [Identity].[UserCredential]
            (UserId, CredentialVersion, AuthSecretHash, AuthSecretSalt,
             KdfProfileId, IsAuthoritative)
        VALUES
            (@userId, 2, @AuthSecretHash, @AuthSecretSalt, @KdfProfileId, 1);

        DELETE FROM [Identity].[RefreshToken] WHERE UserId = @userId;

        UPDATE [Identity].[User]
           SET SecurityStamp = NEWID(), ModifiedOn = SYSUTCDATETIME()
         WHERE UserId = @userId;

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId)
        VALUES
            (@userId, 'user', 'Recovery.GenerationUnrecoverable', 'Generation',
             CONVERT(NVARCHAR(50), @oldGenerationId));

    COMMIT;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(64)) AS FailureCode,
           @nextNumber AS GenerationNumber;
END
GO
