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
    @UserId         UNIQUEIDENTIFIER,
    @AuthSecretHash VARBINARY(64),
    @AuthSecretSalt VARBINARY(32),
    @KdfProfileId   INT,
    @RevokeSessions BIT = 1
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

    DECLARE @generationId UNIQUEIDENTIFIER = NEWID();

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

    SELECT @existingVersion = [Version], @existingOwner = UserId
      FROM [Crypto].[Record] WITH (UPDLOCK, HOLDLOCK)
     WHERE RecordId = @RecordId;

    /*  A record id that belongs to someone else is reported as a version
        conflict, not as "not yours". The distinction would confirm that the
        id exists, and the caller has no legitimate way to have guessed it. */
    IF @existingOwner IS NOT NULL AND @existingOwner <> @UserId
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'VERSION_CONFLICT' AS FailureCode,
               CAST(NULL AS INT) AS CurrentVersion;
        RETURN;
    END

    IF @Version <> ISNULL(@existingVersion, 0) + 1
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'VERSION_CONFLICT' AS FailureCode,
               @existingVersion AS CurrentVersion;
        RETURN;
    END

    IF @existingVersion IS NULL
        INSERT INTO [Crypto].[Record]
            (RecordId, UserId, GenerationId, RecordKind, SchemaVersion,
             [Version], Envelope)
        VALUES
            (@RecordId, @UserId, @generationId, @RecordKind, @SchemaVersion,
             @Version, @Envelope);
    ELSE
        UPDATE [Crypto].[Record]
           SET GenerationId  = @generationId,
               SchemaVersion = @SchemaVersion,
               [Version]     = @Version,
               Envelope      = @Envelope,
               ModifiedOn    = SYSUTCDATETIME()
         WHERE RecordId = @RecordId;

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

    DELETE FROM [Crypto].[Record]
     WHERE RecordId = @RecordId AND UserId = @UserId;

    SELECT CAST(CASE WHEN @@ROWCOUNT > 0 THEN 1 ELSE 0 END AS BIT) AS Succeeded,
           CAST(NULL AS VARCHAR(64)) AS FailureCode;
END
GO
