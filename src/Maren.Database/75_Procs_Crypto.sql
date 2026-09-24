/*  75_Procs_Crypto.sql

    Procedures for the client-side encryption scheme in 74_Crypto.sql.

    The one rule this file exists to hold
    -------------------------------------
    **The server never receives the password.** Not to verify it, not to
    migrate a credential, not "just this once during the transition".

        OLD (CredentialVersion 1, Slice 1)
          password ──► server ──► PBKDF2 verifier

        NEW (CredentialVersion 2)
          password ──► device ──► Argon2id ──► MASTER
                                                ├── auth_secret  ──► server
                                                └── KEK_password ──► stays

    `auth_secret` and `KEK_password` are separate HKDF outputs of the same
    master secret. The server holds a salted hash of the first and has no path
    to the second, so possession of everything the server stores does not open
    a single record.

    This means the upgrade from version 1 to version 2 cannot happen silently
    on the server. It happens on her device, at a moment when the device
    legitimately holds the password because she has just typed it: the client
    derives the new material and calls `usp_UserCredential_SetAuthoritative`.
    **There is no server-side migration of version 1 credentials, and there
    must never be one** — writing one would require the password to cross the
    boundary this whole design exists to keep it behind.

    Backward compatibility
    ----------------------
    Version 1 accounts keep working exactly as they did. `usp_User_GetForLogin`
    is untouched and remains the version 1 path. `usp_UserCredential_GetForLogin`
    reports which version an account is on so the API can route, and returns
    version 2 material only. Neither procedure knows anything about the other.

    Why record writes are not audited
    --------------------------------
    Step 8 of the capability checklist asks for an audit row on every command.
    Generation and credential changes get one, because they are security events
    she would want to see. **Record writes deliberately do not.**

    An audit row per journal write would build a precise behavioural history —
    when she writes, how often, at what hour, from which address — about the
    one part of WLOS that exists to be private. That the payload is encrypted
    does not help; the pattern is the sensitive part. The record rows carry
    their own timestamps for the features that need them, and those go when the
    account goes. This is a deliberate departure from the checklist and is
    named here so it is a decision rather than an omission.

    Ownership
    ---------
    Every read and write is scoped by `@UserId` and resolves the generation
    server-side. **A client never names a generation.** If it could, it could
    ask for another account's generation, or write new records into a dormant
    one whose key an attacker already holds.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- Identity.usp_UserCredential_GetKdfParameters
-- ---------------------------------------------------------------------------
/*
    The parameters a device needs before it can derive anything: the salt and
    the cost settings that were used when the credential was written.

    This is an unauthenticated lookup by email, which makes it an account
    enumeration oracle unless something is done about that. **This procedure
    does not do it, and its result must never be returned to a client as-is.**

    It returns a row for a version 2 account and no rows otherwise. The API is
    responsible for synthesising an indistinguishable decoy — a salt derived
    deterministically from the address under a server-held key, plus the
    current profile — so that a caller cannot tell a registered address from an
    unregistered one, or a version 1 account from a version 2 one.

    The decoy belongs in the API because it needs a secret, and a secret in a
    stored procedure is a secret in source control. The API already holds
    signing key material; this is the same class of thing and lives with it.
*/
IF OBJECT_ID('Identity.usp_UserCredential_GetKdfParameters') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_UserCredential_GetKdfParameters];
GO
CREATE PROCEDURE [Identity].[usp_UserCredential_GetKdfParameters]
    @Email NVARCHAR(256)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @normalised NVARCHAR(256) = UPPER(LTRIM(RTRIM(@Email)));

    SELECT TOP 1
        c.AuthSecretSalt,
        c.KdfProfileId,
        p.Algorithm,
        p.MemoryKiB,
        p.Iterations,
        p.Parallelism,
        p.OutputBytes
    FROM [Identity].[UserCredential] c
    JOIN [Identity].[User] u        ON u.UserId       = c.UserId
    JOIN [Crypto].[KdfProfile] p    ON p.KdfProfileId = c.KdfProfileId
    WHERE u.NormalisedEmail = @normalised
      AND u.IsDeleted       = 0
      AND c.IsAuthoritative = 1
      AND c.CredentialVersion = 2;
END
GO

-- ---------------------------------------------------------------------------
-- Identity.usp_UserCredential_GetCurrentKdfProfile
-- ---------------------------------------------------------------------------
/*
    The profile a new credential should be written with. Also what the API
    needs to build a decoy that looks like a real answer.

    `IsProvisional` is returned rather than hidden so the caller can refuse to
    register a production account against parameters nobody has measured. The
    seeded profile is provisional; D6 and D7 are what replace it.
*/
IF OBJECT_ID('Identity.usp_UserCredential_GetCurrentKdfProfile') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_UserCredential_GetCurrentKdfProfile];
GO
CREATE PROCEDURE [Identity].[usp_UserCredential_GetCurrentKdfProfile]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 1
        p.KdfProfileId,
        p.Algorithm,
        p.MemoryKiB,
        p.Iterations,
        p.Parallelism,
        p.SaltBytes,
        p.OutputBytes,
        p.IsProvisional
    FROM [Crypto].[KdfProfile] p
    WHERE p.IsCurrent = 1;
END
GO

-- ---------------------------------------------------------------------------
-- Identity.usp_UserCredential_GetForLogin
-- ---------------------------------------------------------------------------
/*
    The version 2 counterpart of usp_User_GetForLogin: returns the material
    needed to verify an authentication secret, and nothing else.

    Verification happens in the application, with a constant-time comparison,
    exactly as it does for version 1. A procedure that compared here would have
    to receive the secret and would lose the timing property.

    `CredentialVersion` is always returned, including for accounts that have no
    version 2 credential, so the API can route to the version 1 path without a
    second round trip and without the two procedures knowing about each other.

    Lockout state travels with it because the caller has proved nothing yet at
    this point and must not need a second unauthenticated lookup to find out
    that it should stop.
*/
IF OBJECT_ID('Identity.usp_UserCredential_GetForLogin') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_UserCredential_GetForLogin];
GO
CREATE PROCEDURE [Identity].[usp_UserCredential_GetForLogin]
    @Email NVARCHAR(256)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @normalised NVARCHAR(256) = UPPER(LTRIM(RTRIM(@Email)));

    SELECT TOP 1
        u.UserId,
        CAST(ISNULL(c.CredentialVersion, 1) AS TINYINT) AS CredentialVersion,
        c.AuthSecretHash,
        c.AuthSecretSalt,
        c.KdfProfileId,
        u.IsLockedOut,
        u.LockoutEndUtc
    FROM [Identity].[User] u
    LEFT JOIN [Identity].[UserCredential] c
           ON c.UserId          = u.UserId
          AND c.IsAuthoritative = 1
          AND c.CredentialVersion = 2
    WHERE u.NormalisedEmail = @normalised
      AND u.IsDeleted       = 0;
END
GO

-- ---------------------------------------------------------------------------
-- Identity.usp_UserCredential_SetAuthoritative
-- ---------------------------------------------------------------------------
/*
    Make a client-derived authentication secret the account's one authoritative
    credential.

    Used at registration, at password change, and at the version 1 to version 2
    upgrade on a successful login. In every case the caller has just proved it
    holds the password, on the device, and the password itself never travels.

    Supersede-then-insert is a single transaction because AUTH-1 — the filtered
    unique index in 74_Crypto.sql — refuses two authoritative credentials for
    one account. That is deliberate: the failure mode it prevents is a window
    in which an old and a new password both work, which is precisely the state
    a password change exists to end.

    The security stamp is bumped in the same transaction. Revoking refresh
    tokens stops her getting a new access token; it does nothing about one
    already issued, which stays correctly signed for up to fifteen minutes. The
    stamp is what kills those, and it has to move at the same instant as the
    credential or there is a committed state where the old password is gone and
    the sessions it created are not.
*/
IF OBJECT_ID('Identity.usp_UserCredential_SetAuthoritative') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_UserCredential_SetAuthoritative];
GO
CREATE PROCEDURE [Identity].[usp_UserCredential_SetAuthoritative]
    @UserId          UNIQUEIDENTIFIER,
    @AuthSecretHash  VARBINARY(64),
    @AuthSecretSalt  VARBINARY(32),
    @KdfProfileId    INT,
    /*  The data key, resealed under the key-encryption key the new password
        derives. Required, and in the same transaction as the credential.

        Changing a password changes KEK_password, and the stored wrapper was
        sealed under the old one. Writing the credential without the wrapper
        would leave an account whose new password authenticates and opens
        nothing, with the old password gone -- her journal unreachable by any
        route. The two are one change. */
    @PasswordWrapper VARBINARY(MAX),
    @RevokeSessions  BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [Identity].[User]
                   WHERE UserId = @UserId AND IsDeleted = 0)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'USER_NOT_FOUND' AS FailureCode;
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM [Crypto].[KdfProfile]
                   WHERE KdfProfileId = @KdfProfileId)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'KDF_PROFILE_NOT_FOUND' AS FailureCode;
        RETURN;
    END

    BEGIN TRAN;

        UPDATE [Identity].[UserCredential]
           SET IsAuthoritative = 0,
               SupersededOn    = SYSUTCDATETIME()
         WHERE UserId = @UserId AND IsAuthoritative = 1;

        INSERT INTO [Identity].[UserCredential]
            (UserId, CredentialVersion, AuthSecretHash, AuthSecretSalt,
             KdfProfileId, IsAuthoritative)
        VALUES
            (@UserId, 2, @AuthSecretHash, @AuthSecretSalt,
             @KdfProfileId, 1);

        /*  The data key, resealed. Same transaction, for the reason in the
            parameter comment: a credential without a matching wrapper is an
            account she can sign in to and cannot open.

            Null generation means she has no key yet, which is possible only
            for an account that never finished registering. Nothing to reseal,
            and nothing to refuse over. */
        DECLARE @activeGenerationId UNIQUEIDENTIFIER =
            (SELECT GenerationId FROM [Crypto].[Generation]
              WHERE UserId = @UserId AND [State] = 'ACTIVE');

        IF @activeGenerationId IS NOT NULL
        BEGIN
            DELETE FROM [Crypto].[Wrapper]
             WHERE GenerationId = @activeGenerationId AND WrapperKind = 'PASSWORD';

            INSERT INTO [Crypto].[Wrapper] (GenerationId, WrapperKind, Envelope)
            VALUES (@activeGenerationId, 'PASSWORD', @PasswordWrapper);
        END

        /*  This procedure deliberately does NOT clear the version 1 material
            on Identity.User, even though an account with a version 2
            credential must never authenticate through the version 1 path.

            Clearing it would mean writing to the version 1 credential columns
            on Identity.User from here, which would put this procedure on the
            four-name allow-list in section 4.3 of CLAUDE.md. That list is the
            credential path, not a convenience list, and a procedure that needs
            adding to it is almost always one that should not be touching the
            material at all. This is such a procedure.

            Note for anyone editing this comment: the assertion that enforces
            the list is a text scan over the whole module definition, comments
            included. Naming those columns here — even to say we do not touch
            them — fails it. That is the conservative behaviour and it is
            correct; paraphrase instead.

            The property is enforced where it belongs instead:
            usp_User_GetForLogin returns no rows once an authoritative version
            2 credential exists, so the old material is unreachable rather than
            merely unused. Structural, and it keeps the allow-list at four.

            The residue goes when the account goes — usp_User_DeleteAccount. */
        UPDATE [Identity].[User]
           SET SecurityStamp = CASE WHEN @RevokeSessions = 1
                                    THEN NEWID() ELSE SecurityStamp END,
               ModifiedOn    = SYSUTCDATETIME()
         WHERE UserId = @UserId;

        IF @RevokeSessions = 1
            DELETE FROM [Identity].[RefreshToken] WHERE UserId = @UserId;

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId)
        VALUES
            (@UserId, 'user', 'Credential.SetAuthoritative', 'User',
             CAST(@UserId AS NVARCHAR(64)));

    COMMIT;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(64)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- Crypto.usp_Generation_CreateInitial
-- ---------------------------------------------------------------------------
/*
    Generation 1: the first data-encryption key an account ever has, and the
    two ways she can open it.

    Everything here was produced on her device. The data key was generated
    there, wrapped twice — once under the key derived from her password, once
    under the key derived from her recovery phrase — and only the wrapped forms
    were sent. The recovery public key lets the server later verify that a
    caller holds the phrase without the phrase, the wrapping key or the data
    key ever reaching it.

    One transaction, because a generation with no wrapper is an account whose
    journal nobody can open, and a wrapper with no generation is a foreign key
    violation. Neither is a state worth being able to reach.

    Refuses if the account already has a generation. Creating a second initial
    generation would orphan the first — every record written under it becomes
    unopenable — and no caller has a legitimate reason to ask.
*/
IF OBJECT_ID('Crypto.usp_Generation_CreateInitial') IS NOT NULL
    DROP PROCEDURE [Crypto].[usp_Generation_CreateInitial];
GO
CREATE PROCEDURE [Crypto].[usp_Generation_CreateInitial]
    @UserId             UNIQUEIDENTIFIER,
    @GenerationId       UNIQUEIDENTIFIER,
    @PasswordWrapper    VARBINARY(MAX),
    @RecoveryWrapper    VARBINARY(MAX),
    @RecoveryPublicKey  VARBINARY(32)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [Identity].[User]
                   WHERE UserId = @UserId AND IsDeleted = 0)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'USER_NOT_FOUND' AS FailureCode,
               CAST(NULL AS UNIQUEIDENTIFIER) AS GenerationId;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM [Crypto].[Generation] WHERE UserId = @UserId)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'GENERATION_EXISTS' AS FailureCode,
               CAST(NULL AS UNIQUEIDENTIFIER) AS GenerationId;
        RETURN;
    END

    /*  The client chose this, and had to.

        Both wrappers are sealed before this call, with the generation id
        inside their associated data -- so it has to exist before the round
        trip, which means the client generates it. Assigning one here would
        produce wrappers that open in the session that made them and never
        again, on any device.

        A client-chosen identifier is safe here because it is 122 random bits
        from a CSPRNG and the primary key refuses a collision outright. */


    BEGIN TRAN;

        INSERT INTO [Crypto].[Generation]
            (GenerationId, UserId, GenerationNumber, [State])
        VALUES
            (@generationId, @UserId, 1, 'ACTIVE');

        INSERT INTO [Crypto].[Wrapper] (GenerationId, WrapperKind, Envelope)
        VALUES (@generationId, 'PASSWORD', @PasswordWrapper),
               (@generationId, 'RECOVERY', @RecoveryWrapper);

        INSERT INTO [Crypto].[RecoveryVerifier] (GenerationId, PublicKey)
        VALUES (@generationId, @RecoveryPublicKey);

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId)
        VALUES
            (@UserId, 'user', 'Crypto.GenerationCreated', 'Generation',
             CAST(@generationId AS NVARCHAR(64)));

    COMMIT;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(64)) AS FailureCode,
           @generationId AS GenerationId;
END
GO

-- ---------------------------------------------------------------------------
-- Crypto.usp_Generation_GetActive
-- ---------------------------------------------------------------------------
/*
    The generation new records are written under. Resolved here rather than
    supplied by the caller — see the ownership note at the top of this file.
*/
IF OBJECT_ID('Crypto.usp_Generation_GetActive') IS NOT NULL
    DROP PROCEDURE [Crypto].[usp_Generation_GetActive];
GO
CREATE PROCEDURE [Crypto].[usp_Generation_GetActive]
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 1
        g.GenerationId,
        g.GenerationNumber,
        g.[State],
        g.CreatedOn
    FROM [Crypto].[Generation] g
    WHERE g.UserId = @UserId AND g.[State] = 'ACTIVE';
END
GO

-- ---------------------------------------------------------------------------
-- Crypto.usp_Wrapper_GetForGeneration
-- ---------------------------------------------------------------------------
/*
    The wrapped data keys for one generation.

    Authenticated, and scoped by user: the generation is joined back to the
    caller rather than trusted from the parameter. A wrapper is useless without
    the key that opens it, but handing one to the wrong account would give an
    attacker something to work on offline, which is exactly the exposure the
    recovery path is careful to avoid.

    Device wrappers are included. They are opened by a key the device holds and
    the server does not.
*/
IF OBJECT_ID('Crypto.usp_Wrapper_GetForGeneration') IS NOT NULL
    DROP PROCEDURE [Crypto].[usp_Wrapper_GetForGeneration];
GO
CREATE PROCEDURE [Crypto].[usp_Wrapper_GetForGeneration]
    @UserId       UNIQUEIDENTIFIER,
    @GenerationId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        w.WrapperKind,
        w.DeviceId,
        w.Envelope
    FROM [Crypto].[Wrapper] w
    JOIN [Crypto].[Generation] g ON g.GenerationId = w.GenerationId
    WHERE w.GenerationId = @GenerationId
      AND g.UserId       = @UserId;
END
GO

-- ---------------------------------------------------------------------------
-- Crypto.usp_Record_Save
-- ---------------------------------------------------------------------------
/*
    Write an encrypted record.

    Versioning, and why the client supplies the version
    --------------------------------------------------
    The envelope is sealed on the device with associated data binding the
    record id, the version and the schema version. The client therefore has to
    know the version it is sealing with BEFORE it seals, so it sends that
    version and the version it believed was current. The server accepts the
    write only if the new version is exactly one past what it actually holds.

    That makes the concurrency check and the cryptographic binding the same
    check. A server that assigned the version itself would force the client to
    seal against a number it could not know, and the associated data would be
    wrong on every concurrent write.

    A stale write is an expected failure, not an exception: two devices writing
    the same entry is ordinary, and the client resolves it.

    The generation is resolved here. A caller cannot write into a dormant
    generation, which is what would happen if an old client kept using a key
    that has since been retired.
*/
IF OBJECT_ID('Crypto.usp_Record_Save') IS NOT NULL
    DROP PROCEDURE [Crypto].[usp_Record_Save];
GO
CREATE PROCEDURE [Crypto].[usp_Record_Save]
    @UserId         UNIQUEIDENTIFIER,
    @RecordId       UNIQUEIDENTIFIER,
    @RecordKind     VARCHAR(32),
    @SchemaVersion  INT,
    @Version        INT,
    @Envelope       VARBINARY(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @generationId UNIQUEIDENTIFIER =
        (SELECT GenerationId FROM [Crypto].[Generation]
          WHERE UserId = @UserId AND [State] = 'ACTIVE');

    IF @generationId IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'NO_ACTIVE_GENERATION' AS FailureCode,
               CAST(NULL AS INT) AS CurrentVersion;
        RETURN;
    END

    DECLARE @existingVersion INT;
    DECLARE @existingOwner   UNIQUEIDENTIFIER;

    /*  An explicit transaction, because the hint above only means something
        inside one.

        UPDLOCK and HOLDLOCK in autocommit are released when the SELECT
        finishes, so two devices saving the same entry could both read version
        3, both compute 4, and the second would overwrite the first with no
        conflict reported -- which is exactly the case the version check
        exists to catch. Holding the lock to the COMMIT is what makes the
        check and the write one decision. */
    BEGIN TRAN;

    /*  The refusal paths below COMMIT rather than ROLLBACK, which looks wrong
        and is not. Nothing has been written at that point -- the transaction
        exists only to hold the lock taken by the SELECT -- so committing an
        empty transaction and rolling one back are the same outcome.

        ROLLBACK is worse than merely unnecessary here: a procedure that rolls
        back cannot be called from INSERT ... EXEC, which fails with error
        3915 and makes this procedure untestable from the SQL assertion suite.
        A hidden constraint on how a procedure may be called is exactly the
        kind of thing that is discovered much later, by someone else. */

    SELECT @existingVersion = [Version], @existingOwner = UserId
      FROM [Crypto].[Record] WITH (UPDLOCK, HOLDLOCK)
     WHERE RecordId = @RecordId;

    /*  A record id that belongs to someone else is reported as a version
        conflict, not as "not yours". The distinction would confirm that the
        id exists, and the caller has no legitimate way to have guessed it. */
    IF @existingOwner IS NOT NULL AND @existingOwner <> @UserId
    BEGIN
        COMMIT TRAN;
        SELECT CAST(0 AS BIT) AS Succeeded, 'VERSION_CONFLICT' AS FailureCode,
               CAST(NULL AS INT) AS CurrentVersion;
        RETURN;
    END

    IF @Version <> ISNULL(@existingVersion, 0) + 1
    BEGIN
        COMMIT TRAN;
        SELECT CAST(0 AS BIT) AS Succeeded, 'VERSION_CONFLICT' AS FailureCode,
               @existingVersion AS CurrentVersion;
        RETURN;
    END

    IF @existingVersion IS NULL
    BEGIN
        /*  An id that was deleted and is being written again. Record ids are
            CSPRNG UUIDs so this is vanishingly rare, but leaving the
            tombstone behind would mean the sync stream carries a deletion and
            a creation for the same id forever. Clearing it here keeps the
            stream saying what is true now.

            Safe for a device that already applied the deletion: it sees the
            creation next, at a higher cursor, and ends in the same place. */
        DELETE FROM [Crypto].[RecordTombstone]
         WHERE RecordId = @RecordId AND UserId = @UserId;

        INSERT INTO [Crypto].[Record]
            (RecordId, UserId, GenerationId, RecordKind, SchemaVersion,
             [Version], Envelope)
        VALUES
            (@RecordId, @UserId, @generationId, @RecordKind, @SchemaVersion,
             @Version, @Envelope);
    END
    ELSE
        UPDATE [Crypto].[Record]
           SET GenerationId  = @generationId,
               SchemaVersion = @SchemaVersion,
               [Version]     = @Version,
               Envelope      = @Envelope,
               ModifiedOn    = SYSUTCDATETIME()
         WHERE RecordId = @RecordId;

    COMMIT TRAN;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(64)) AS FailureCode,
           @Version AS CurrentVersion;
END
GO

-- ---------------------------------------------------------------------------
-- Crypto.usp_Record_Get
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Crypto.usp_Record_Get') IS NOT NULL
    DROP PROCEDURE [Crypto].[usp_Record_Get];
GO
CREATE PROCEDURE [Crypto].[usp_Record_Get]
    @UserId   UNIQUEIDENTIFIER,
    @RecordId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 1
        r.RecordId,
        r.RecordKind,
        r.SchemaVersion,
        r.[Version],
        r.Envelope,
        g.GenerationNumber,
        r.CreatedOn,
        r.ModifiedOn
    FROM [Crypto].[Record] r
    JOIN [Crypto].[Generation] g ON g.GenerationId = r.GenerationId
    WHERE r.RecordId = @RecordId AND r.UserId = @UserId;
END
GO

-- ---------------------------------------------------------------------------
-- Crypto.usp_Record_GetPage
-- ---------------------------------------------------------------------------
/*
    A page of records, newest first.

    Page size is bounded here as well as in the validator. An unbounded page
    over a table of encrypted blobs is a denial-of-service vector and also the
    easiest way to accidentally pull an entire journal across a wire.
*/
IF OBJECT_ID('Crypto.usp_Record_GetPage') IS NOT NULL
    DROP PROCEDURE [Crypto].[usp_Record_GetPage];
GO
CREATE PROCEDURE [Crypto].[usp_Record_GetPage]
    @UserId     UNIQUEIDENTIFIER,
    @RecordKind VARCHAR(32) = NULL,
    @Skip       INT = 0,
    @Take       INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    IF @Take IS NULL OR @Take <= 0 OR @Take > 200 SET @Take = 50;
    IF @Skip IS NULL OR @Skip <  0                SET @Skip = 0;

    SELECT
        r.RecordId,
        r.RecordKind,
        r.SchemaVersion,
        r.[Version],
        r.Envelope,
        g.GenerationNumber,
        r.CreatedOn,
        r.ModifiedOn
    FROM [Crypto].[Record] r
    JOIN [Crypto].[Generation] g ON g.GenerationId = r.GenerationId
    WHERE r.UserId = @UserId
      AND (@RecordKind IS NULL OR r.RecordKind = @RecordKind)
    ORDER BY r.ModifiedOn DESC, r.RecordId
    OFFSET @Skip ROWS FETCH NEXT @Take ROWS ONLY;
END
GO

-- ---------------------------------------------------------------------------
-- Crypto.usp_Record_Delete
-- ---------------------------------------------------------------------------
/*
    Deletion is deletion. There is no soft-delete flag on an encrypted record:
    a row that still exists is a row a future bug can serve, and "she deleted
    it" is not a property worth keeping about the contents of a journal.

    **A tombstone is written in the same transaction**, and that is not a
    weakening of the above. The row and its envelope are gone; what remains is
    a record id, a kind and a time, with no ciphertext and nothing derived
    from content.

    It exists because without it her deletion never reaches her other phone.
    A device catching up asks what changed since its cursor, and a row that
    has simply vanished is mentioned by nothing — so the entry she deliberately
    deleted stays on the other device forever. Remembering that an id once
    existed is a smaller cost than that, and `usp_User_DeleteAccount` erases
    the tombstones with everything else.

    See 79_RecordSync.sql. The table is created there; SQL Server resolves the
    name when this runs, not when it is created, so the order is fine.
*/
IF OBJECT_ID('Crypto.usp_Record_Delete') IS NOT NULL
    DROP PROCEDURE [Crypto].[usp_Record_Delete];
GO
CREATE PROCEDURE [Crypto].[usp_Record_Delete]
    @UserId   UNIQUEIDENTIFIER,
    @RecordId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @deleted TABLE (RecordKind VARCHAR(32) NOT NULL);

    BEGIN TRAN;

        DELETE FROM [Crypto].[Record]
        OUTPUT deleted.RecordKind INTO @deleted (RecordKind)
         WHERE RecordId = @RecordId AND UserId = @UserId;

        /*  Both writes or neither. A deletion without its tombstone is an
            entry that stays on her other phone; a tombstone without its
            deletion is an entry that disappears from every device while the
            ciphertext is still stored here. */
        INSERT INTO [Crypto].[RecordTombstone] (RecordId, UserId, RecordKind)
        SELECT @RecordId, @UserId, d.RecordKind FROM @deleted d;

    COMMIT;

    SELECT CAST(CASE WHEN EXISTS (SELECT 1 FROM @deleted) THEN 1 ELSE 0 END AS BIT)
               AS Succeeded,
           CAST(NULL AS VARCHAR(64)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- Crypto.usp_Crypto_GetAccountSummary
-- ---------------------------------------------------------------------------
/*
    What an operator may see about a woman's encrypted records: that they
    exist, and how many.

    **Deliberately shaped to be unhelpful to curiosity.** Counts and states,
    one first and one last timestamp, and nothing else. No record kinds broken
    down, no sizes, no per-record times, no titles — because those are absent
    by design rather than by omission, and a shape that begins as "how much is
    there" grows into a behavioural profile one reasonable-sounding request at
    a time.

    It returns no ciphertext. An operator who could retrieve envelopes could
    not read them, but there is no support question whose answer requires
    holding a woman's encrypted journal, so the procedure does not offer it.

    `HasRecoveryWrapper` is here because it is the one fact that changes what
    an operator can honestly tell her: whether a recovery phrase can still
    open the current generation. Whether it *will* is between her and the
    phrase.

    `PasswordChangedOn` and `RecoveryPhraseChangedOn` are the two dates a
    woman asks about when something is wrong, and they come from the audit log
    rather than from a column, because the audit log is where the fact already
    lives and a second copy is a second thing to keep true.

    They are here on her behalf rather than for reporting. "Your password was
    changed on the fourteenth" -- or, far more importantly, "no, it was not" --
    is the answer to *did someone else get into my account*, and for a woman
    whose phone is not only hers that is not an idle question. Withholding it
    would protect nothing: it says when a credential changed, never what it
    became.

    Dates, not instants. An operator does not need to know she was awake at
    three in the morning, and the client formats these as dates for the same
    reason.
*/
IF OBJECT_ID('Crypto.usp_Crypto_GetAccountSummary') IS NOT NULL
    DROP PROCEDURE [Crypto].[usp_Crypto_GetAccountSummary];
GO
CREATE PROCEDURE [Crypto].[usp_Crypto_GetAccountSummary]
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 1
        u.UserId,
        u.Email,
        (SELECT COUNT(*) FROM [Crypto].[Generation] g2 WHERE g2.UserId = u.UserId)
            AS GenerationCount,
        ISNULL((SELECT g3.GenerationNumber FROM [Crypto].[Generation] g3
                 WHERE g3.UserId = u.UserId AND g3.[State] = 'ACTIVE'), 0)
            AS ActiveGenerationNumber,
        (SELECT COUNT(*) FROM [Crypto].[Record] r WHERE r.UserId = u.UserId)
            AS RecordCount,
        CAST(CASE WHEN EXISTS (
                SELECT 1 FROM [Crypto].[Wrapper] w
                JOIN [Crypto].[Generation] g4 ON g4.GenerationId = w.GenerationId
                WHERE g4.UserId = u.UserId AND g4.[State] = 'ACTIVE'
                  AND w.WrapperKind = 'RECOVERY')
             THEN 1 ELSE 0 END AS BIT) AS HasRecoveryWrapper,
        (SELECT MIN(r.CreatedOn) FROM [Crypto].[Record] r WHERE r.UserId = u.UserId)
            AS FirstRecordOn,
        (SELECT MAX(r.ModifiedOn) FROM [Crypto].[Record] r WHERE r.UserId = u.UserId)
            AS LastRecordOn,
        (SELECT MAX(a.OccurredUtc) FROM [Audit].[AuditLog] a
          WHERE a.ActorUserId = u.UserId
            AND a.[Action] = 'Credential.SetAuthoritative')
            AS PasswordChangedOn,
        (SELECT MAX(a.OccurredUtc) FROM [Audit].[AuditLog] a
          WHERE a.ActorUserId = u.UserId
            AND a.[Action] = 'Recovery.KeyReplaced')
            AS RecoveryPhraseChangedOn
    FROM [Identity].[User] u
    WHERE u.UserId = @UserId AND u.IsDeleted = 0;
END
GO

-- ---------------------------------------------------------------------------
-- Identity.usp_User_RegisterClientDerived
-- ---------------------------------------------------------------------------
/*
    Register an account whose credential was derived on her device.

    Everything this procedure receives was computed on the phone: an
    authentication secret, two wrapped copies of a data key, and a public key.
    **It receives no password.** There is no parameter that could carry one,
    and the assertion suite checks that across every procedure in the database.

    Why this is one transaction
    --------------------------
    An account, its credential and its first generation have to appear
    together or not at all. Each partial outcome is its own kind of stranded:

      * account without a credential  -> she cannot sign in, and cannot
                                         register again because the address is
                                         taken
      * credential without a generation -> she can sign in and has no key, so
                                         her first entry has nowhere to go
      * generation without wrappers   -> a data key nobody can ever unwrap,
                                         and every record written under it is
                                         lost from the first write

    All three are unrecoverable without an operator touching her account, and
    this platform does not give operators that reach. So: one transaction.

    The age gate
    ------------
    Duplicated from `usp_User_Register` rather than shared, because sharing it
    would mean one procedure calling another inside a transaction it did not
    open, and nested transaction semantics in T-SQL are a trap. The two copies
    are held in step by an assertion that feeds the same under-age date to both
    and requires the same refusal.

    A refused registration stores nothing. Recording it would mean keeping a
    child's email address and date of birth as the permanent record of having
    turned her away, which is the opposite of what the gate is for.
*/
IF OBJECT_ID('Identity.usp_User_RegisterClientDerived') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_User_RegisterClientDerived];
GO
CREATE PROCEDURE [Identity].[usp_User_RegisterClientDerived]
    @Email              NVARCHAR(256),
    @DateOfBirth        DATE,
    @GenerationId       UNIQUEIDENTIFIER,
    @AuthSecretHash     VARBINARY(64),
    @AuthSecretSalt     VARBINARY(32),
    @KdfProfileId       INT,
    @PasswordWrapper    VARBINARY(MAX),
    @RecoveryWrapper    VARBINARY(MAX),
    @RecoveryPublicKey  VARBINARY(32),
    @CountryIso         CHAR(2) = NULL,
    @LanguageCode       CHAR(5) = 'en-GB',
    @IpAddress          VARCHAR(45) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @normalised NVARCHAR(256) = UPPER(LTRIM(RTRIM(@Email)));
    DECLARE @userId UNIQUEIDENTIFIER;
    DECLARE @countryId INT =
        (SELECT CountryId FROM [Identity].[Country] WHERE IsoCode = @CountryIso);

    IF @DateOfBirth IS NULL
       OR @DateOfBirth > CAST(SYSUTCDATETIME() AS DATE)
       OR @DateOfBirth < DATEADD(YEAR, -120, CAST(SYSUTCDATETIME() AS DATE))
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'INVALID_DATE_OF_BIRTH' AS FailureCode,
               CAST(NULL AS UNIQUEIDENTIFIER) AS UserId,
               CAST(NULL AS UNIQUEIDENTIFIER) AS GenerationId;
        RETURN;
    END

    IF [Identity].[fn_IsOfMinimumAge](@DateOfBirth) = 0
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'UNDER_MINIMUM_AGE' AS FailureCode,
               CAST(NULL AS UNIQUEIDENTIFIER) AS UserId,
               CAST(NULL AS UNIQUEIDENTIFIER) AS GenerationId;
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM [Crypto].[KdfProfile] WHERE KdfProfileId = @KdfProfileId)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'KDF_PROFILE_NOT_FOUND' AS FailureCode,
               CAST(NULL AS UNIQUEIDENTIFIER) AS UserId,
               CAST(NULL AS UNIQUEIDENTIFIER) AS GenerationId;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM [Identity].[User]
               WHERE NormalisedEmail = @normalised AND IsDeleted = 0)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'EMAIL_IN_USE' AS FailureCode,
               CAST(NULL AS UNIQUEIDENTIFIER) AS UserId,
               CAST(NULL AS UNIQUEIDENTIFIER) AS GenerationId;
        RETURN;
    END

    BEGIN TRAN;

        /*  The version 1 credential columns are left untouched, and are not
            named here. This account has never had a server-verified password
            and never will; the login path for version 1 returns nothing for
            an account holding an authoritative version 2 credential. */
        INSERT INTO [Identity].[User]
            (Email, NormalisedEmail, CountryId, LanguageCode)
        VALUES
            (@Email, @normalised, @countryId, @LanguageCode);

        SET @userId = (SELECT UserId FROM [Identity].[User]
                       WHERE NormalisedEmail = @normalised AND IsDeleted = 0);

        INSERT INTO [Identity].[Profile] (UserId, DateOfBirth)
        VALUES (@userId, @DateOfBirth);

        INSERT INTO [Identity].[UserRole] (UserId, RoleId)
        SELECT @userId, RoleId FROM [Identity].[Role] WHERE Name = 'Member';

        INSERT INTO [Identity].[UserCredential]
            (UserId, CredentialVersion, AuthSecretHash, AuthSecretSalt,
             KdfProfileId, IsAuthoritative)
        VALUES
            (@userId, 2, @AuthSecretHash, @AuthSecretSalt, @KdfProfileId, 1);

        INSERT INTO [Crypto].[Generation]
            (GenerationId, UserId, GenerationNumber, [State])
        VALUES
            (@generationId, @userId, 1, 'ACTIVE');

        INSERT INTO [Crypto].[Wrapper] (GenerationId, WrapperKind, Envelope)
        VALUES (@generationId, 'PASSWORD', @PasswordWrapper),
               (@generationId, 'RECOVERY', @RecoveryWrapper);

        INSERT INTO [Crypto].[RecoveryVerifier] (GenerationId, PublicKey)
        VALUES (@generationId, @RecoveryPublicKey);

        /*  That she registered, and that a key exists. Not the date of birth,
            not the wrappers, not the public key. */
        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId, IpAddress)
        VALUES
            (@userId, 'user', 'User.RegisterClientDerived', 'User',
             CONVERT(NVARCHAR(50), @userId), @IpAddress);

    COMMIT TRAN;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(64)) AS FailureCode,
           @userId AS UserId, @generationId AS GenerationId;
END
GO

-- ---------------------------------------------------------------------------
-- Identity.usp_UserCredential_GetForUser
-- ---------------------------------------------------------------------------
/*
    The same verification material, found by user id rather than by address.

    For re-confirming a password when the caller has already authenticated,
    which is how an irreversible action is gated. The version 1 path has
    `usp_User_GetLoginMaterial` for exactly this and for exactly this reason:
    the alternative is an authenticated endpoint accepting an email address to
    name an account the token already names, which is a second and weaker way
    of saying who is being acted on.

    Comparison happens in the application, constant-time, as everywhere else.
*/
IF OBJECT_ID('Identity.usp_UserCredential_GetForUser') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_UserCredential_GetForUser];
GO
CREATE PROCEDURE [Identity].[usp_UserCredential_GetForUser]
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 1
        c.AuthSecretHash,
        c.AuthSecretSalt,
        c.KdfProfileId
    FROM [Identity].[UserCredential] c
    JOIN [Identity].[User] u ON u.UserId = c.UserId
    WHERE c.UserId = @UserId
      AND c.IsAuthoritative = 1
      AND c.CredentialVersion = 2
      AND u.IsDeleted = 0;
END
GO

-- ---------------------------------------------------------------------------
-- Crypto.usp_Crypto_ReplaceRecoveryKey
-- ---------------------------------------------------------------------------
/*
    A new recovery phrase for the generation she is writing into.

    For the woman who has lost the piece of paper, or who used her phrase and
    would rather the old one stopped working. The old wrapper and the old
    public key are both replaced, so the old twelve words stop opening
    anything and stop proving anything.

    **This is destructive to the old phrase and cannot be undone**, which is
    why the caller must have re-authenticated with the current password first.
    A stolen session must not be able to do this: it would let an attacker
    replace the one credential she could have used to take the account back.

    It does not touch the data key. Her journal is unaffected -- this changes
    which words open it, not what they open.

    Only the ACTIVE generation. A dormant generation's phrase is the only
    thing that still opens it, and replacing that wrapper would orphan every
    record written under it.
*/
IF OBJECT_ID('Crypto.usp_Crypto_ReplaceRecoveryKey') IS NOT NULL
    DROP PROCEDURE [Crypto].[usp_Crypto_ReplaceRecoveryKey];
GO
CREATE PROCEDURE [Crypto].[usp_Crypto_ReplaceRecoveryKey]
    @UserId             UNIQUEIDENTIFIER,
    @RecoveryWrapper    VARBINARY(MAX),
    @RecoveryPublicKey  VARBINARY(32)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @generationId UNIQUEIDENTIFIER =
        (SELECT GenerationId FROM [Crypto].[Generation]
          WHERE UserId = @UserId AND [State] = 'ACTIVE');

    IF @generationId IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'NO_ACTIVE_GENERATION' AS FailureCode;
        RETURN;
    END

    BEGIN TRAN;

        DELETE FROM [Crypto].[Wrapper]
         WHERE GenerationId = @generationId AND WrapperKind = 'RECOVERY';

        INSERT INTO [Crypto].[Wrapper] (GenerationId, WrapperKind, Envelope)
        VALUES (@generationId, 'RECOVERY', @RecoveryWrapper);

        DELETE FROM [Crypto].[RecoveryVerifier] WHERE GenerationId = @generationId;

        INSERT INTO [Crypto].[RecoveryVerifier] (GenerationId, PublicKey)
        VALUES (@generationId, @RecoveryPublicKey);

        /*  Outstanding challenges against the old key are dead. Leaving them
            ISSUED would mean a challenge she asked for a minute ago could
            still be answered by the phrase she has just retired. */
        DELETE FROM [Crypto].[RecoveryChallenge]
         WHERE UserId = @UserId AND [State] IN ('ISSUED', 'CONSUMED', 'VERIFIED');

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId)
        VALUES
            (@UserId, 'user', 'Recovery.KeyReplaced', 'Generation',
             CONVERT(NVARCHAR(50), @generationId));

    COMMIT;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(64)) AS FailureCode;
END
GO
