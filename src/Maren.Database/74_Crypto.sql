/*  74_Crypto.sql

    Client-side encryption: the key hierarchy, the generations it is organised
    into, and the encrypted records themselves.

    Specification: docs/architecture/WLOS_CRYPTO_PROTOCOL_V1_FINAL.md and
    docs/architecture/WLOS_RESET_AUTHORIZATION_V1.md. Open items that this
    script deliberately does not decide are listed in
    docs/architecture/WLOS_DEFERRED_DECISIONS.md.

    What this script is for
    -----------------------
    The journal never leaves a device as plaintext. The server stores
    ciphertext, public keys and wrapped keys, and holds nothing that can open
    any of it. Everything here exists to make that true and, more importantly,
    to make it *enforced* rather than merely intended.

    Three invariants live in this file as constraints, not as code
    --------------------------------------------------------------
    A rule enforced in C# is a rule the next caller bypasses. These three are
    the ones whose violation would be silent and unrecoverable, so they are
    filtered unique indexes that the engine refuses to break:

      AUTH-1   Exactly one authoritative credential verifier per account, in
               every committed state. There is never a committed moment in
               which an old and a new password both authenticate.
               -> UX_UserCredential_Authoritative

      GEN-1    Exactly one ACTIVE generation per account.
               -> UX_Generation_Active

      GEN-2    At most one MIGRATING generation per account.
               -> UX_Generation_Migrating

    These are *committed-state* invariants. They say nothing about what is true
    part-way through a transaction, and they are asserted after each commit —
    which is the only form a database can enforce and the only form a test can
    honestly check.

    Why a generation row is the staging boundary
    --------------------------------------------
    A password reset by email stages its new material — a new password
    verifier, new wrappers, a new recovery public key — before anything is
    applied, so that the commit needs no client present and so that what she
    approves is exactly what will be applied.

    Staged material must authenticate nothing and verify nothing until that
    commit. **This script enforces that structurally: no generation row exists
    until the reset commits, so a staged recovery public key has nowhere to
    live.** `Crypto.RecoveryVerifier` hangs off `Crypto.Generation`, and a
    verifier for a generation that does not exist cannot be stored, let alone
    read by a lookup.

    That matters more than it sounds. If staged recovery keys were readable by
    the recovery-reset path, an attacker who started an email reset would hold
    the private half of a key the server would accept — and he would complete
    an immediate recovery-phrase reset, skipping the delay window and the
    device approval entirely. The staging table for a pending reset is
    deliberately not in this script; it arrives with the reset engine, and it
    does not write here.

    Why KDF parameters are data
    ---------------------------
    `Crypto.KdfProfile` holds Argon2id parameters as rows, and every credential
    names the profile it was written with. The platform already does exactly
    this for PBKDF2 via `Identity.User.PasswordIterations`, for the same
    reason: when the cost is raised, existing credentials must still verify
    against the parameters they were created with and upgrade on next
    successful login.

    The seeded profile is marked provisional. The production profile is set by
    measurement on real minimum-specification hardware, and that measurement
    has not happened. **A provisional profile is a placeholder, not a
    recommendation** — see D6 and D7 in the deferred-decisions register.

    What this script does not create
    --------------------------------
    No device-enrolment table, no reset-request table, no migration cursor, no
    destruction tombstone. Those belong to slices that are not being built yet,
    and a table created before the behaviour that uses it is a table whose
    shape was guessed. The `MIGRATING` and `ORPHANED` states are named here
    because they are part of the invariant's domain, not because anything
    writes them yet.

    Ordering
    --------
    `76_AuditContract_Apply.sql` must run after this script. It applies the
    audit contract with a cursor over sys.tables and cannot see anything
    created after it — which is why it was renumbered from 74 when this file
    took that number.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF SCHEMA_ID('Crypto') IS NULL
    EXEC('CREATE SCHEMA [Crypto]');
GO

-- ---------------------------------------------------------------------------
-- Crypto.KdfProfile
--
-- Versioned key-derivation parameters. Referenced by every credential written
-- under the client-derived scheme, so that raising the cost never invalidates
-- credentials written under the old one.
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Crypto.KdfProfile', 'U') IS NULL
BEGIN
    CREATE TABLE [Crypto].[KdfProfile] (
        KdfProfileId    INT IDENTITY(1,1) NOT NULL,
        Algorithm       VARCHAR(32)   NOT NULL,
        MemoryKiB       INT           NOT NULL,
        Iterations      INT           NOT NULL,
        Parallelism     TINYINT       NOT NULL,
        SaltBytes       TINYINT       NOT NULL,
        OutputBytes     TINYINT       NOT NULL,
        /*  Provisional until measured on minimum-specification hardware.
            A provisional profile must never be used for a production
            credential; the deployment check for that lives with the
            registration procedure, not here, because this table has no way to
            know which database it is in. */
        IsProvisional   BIT           NOT NULL CONSTRAINT DF_KdfProfile_Provisional DEFAULT 1,
        IsCurrent       BIT           NOT NULL CONSTRAINT DF_KdfProfile_Current     DEFAULT 0,
        Notes           NVARCHAR(400) NULL,
        CreatedOn       DATETIME2(3)  NOT NULL CONSTRAINT DF_KdfProfile_CreatedOn   DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_KdfProfile PRIMARY KEY CLUSTERED (KdfProfileId),
        CONSTRAINT CK_KdfProfile_Algorithm
            CHECK (Algorithm IN ('ARGON2ID')),
        CONSTRAINT CK_KdfProfile_Positive
            CHECK (MemoryKiB > 0 AND Iterations > 0 AND Parallelism > 0),
        /*  RFC 9106 salts are at least 16 bytes; a 32-byte output is what the
            HKDF stage downstream expects. Both are floors, not preferences. */
        CONSTRAINT CK_KdfProfile_Sizes
            CHECK (SaltBytes >= 16 AND OutputBytes >= 32)
    );
END
GO

-- Exactly one current profile.
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'UX_KdfProfile_Current'
                 AND object_id = OBJECT_ID('Crypto.KdfProfile'))
    CREATE UNIQUE INDEX UX_KdfProfile_Current
        ON [Crypto].[KdfProfile](IsCurrent)
        WHERE IsCurrent = 1;
GO

/*  A provisional starting point, so that nothing downstream has to hard-code
    parameters while D6 and D7 are open. The values are RFC 9106's second
    recommended option (64 MiB, t=3, p=4), which is a defensible floor for a
    mobile device and is NOT a measured result for any device WLOS supports. */
IF NOT EXISTS (SELECT 1 FROM [Crypto].[KdfProfile])
BEGIN
    INSERT INTO [Crypto].[KdfProfile]
        (Algorithm, MemoryKiB, Iterations, Parallelism, SaltBytes, OutputBytes,
         IsProvisional, IsCurrent, Notes)
    VALUES
        ('ARGON2ID', 65536, 3, 4, 16, 32, 1, 1,
         N'Provisional. RFC 9106 second recommended option. Replace with a '
         + N'measured profile once D6 (minimum device) and D7 (p95 ceiling) '
         + N'are decided. Not a measured result.');
END
GO

-- ---------------------------------------------------------------------------
-- Identity.UserCredential
--
-- AUTH-1 lives here.
--
-- Slice 1 stores password material on Identity.User: PasswordHash,
-- PasswordSalt, PasswordIterations, verified server-side. That is
-- CredentialVersion 1 and it still works.
--
-- The client-derived scheme is CredentialVersion 2: the device derives a
-- master secret with Argon2id and sends only an authentication secret derived
-- from it under a separate HKDF label. The key that opens her journal is
-- derived from the same master under a DIFFERENT label and never leaves the
-- device. The server cannot get from one to the other.
--
-- Both versions exist as rows in one table so that a single, ordinary
-- rehash-on-login upgrade carries an account from one to the other, and so
-- that "which credential authenticates this account right now" has exactly one
-- answer the database itself guarantees.
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Identity.UserCredential', 'U') IS NULL
BEGIN
    CREATE TABLE [Identity].[UserCredential] (
        UserCredentialId    UNIQUEIDENTIFIER NOT NULL
            CONSTRAINT DF_UserCredential_Id DEFAULT NEWSEQUENTIALID(),
        UserId              UNIQUEIDENTIFIER NOT NULL,
        /*  1 = server-verified PBKDF2 (Slice 1, material on Identity.User)
            2 = client-derived Argon2id authentication secret (this table) */
        CredentialVersion   TINYINT       NOT NULL,
        AuthSecretHash      VARBINARY(64) NULL,
        AuthSecretSalt      VARBINARY(32) NULL,
        KdfProfileId        INT           NULL,
        IsAuthoritative     BIT           NOT NULL,
        CreatedOn           DATETIME2(3)  NOT NULL
            CONSTRAINT DF_UserCredential_CreatedOn DEFAULT SYSUTCDATETIME(),
        SupersededOn        DATETIME2(3)  NULL,
        CONSTRAINT PK_UserCredential PRIMARY KEY CLUSTERED (UserCredentialId),
        CONSTRAINT FK_UserCredential_User FOREIGN KEY (UserId)
            REFERENCES [Identity].[User](UserId),
        CONSTRAINT FK_UserCredential_KdfProfile FOREIGN KEY (KdfProfileId)
            REFERENCES [Crypto].[KdfProfile](KdfProfileId),
        CONSTRAINT CK_UserCredential_Version
            CHECK (CredentialVersion IN (1, 2)),
        /*  Version 2 carries its own material and names its profile. Version 1
            carries none, because its material is on Identity.User. Neither may
            borrow the other's shape. */
        CONSTRAINT CK_UserCredential_Shape CHECK (
            (CredentialVersion = 2
                AND AuthSecretHash IS NOT NULL
                AND AuthSecretSalt IS NOT NULL
                AND KdfProfileId   IS NOT NULL)
         OR (CredentialVersion = 1
                AND AuthSecretHash IS NULL
                AND AuthSecretSalt IS NULL
                AND KdfProfileId   IS NULL)
        ),
        /*  An authoritative credential has not been superseded. The two
            statements are the same fact and must not be able to disagree. */
        CONSTRAINT CK_UserCredential_Authoritative_NotSuperseded
            CHECK (IsAuthoritative = 0 OR SupersededOn IS NULL)
    );
END
GO

/*  AUTH-1. This is the constraint, and it is why account-level password
    changes and resets are single transactions: two authoritative credentials
    for one account is not a state the engine will accept. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'UX_UserCredential_Authoritative'
                 AND object_id = OBJECT_ID('Identity.UserCredential'))
    CREATE UNIQUE INDEX UX_UserCredential_Authoritative
        ON [Identity].[UserCredential](UserId)
        WHERE IsAuthoritative = 1;
GO

-- Supporting index for the FK, required by index_coverage_test.sql.
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_UserCredential_KdfProfileId'
                 AND object_id = OBJECT_ID('Identity.UserCredential'))
    CREATE INDEX IX_UserCredential_KdfProfileId
        ON [Identity].[UserCredential](KdfProfileId);
GO

-- ---------------------------------------------------------------------------
-- Crypto.Generation
--
-- A generation is one data-encryption key and every record written under it.
-- Rotation and reset create generations; nothing ever edits one.
--
-- States:
--   ACTIVE     records are written under this key. Exactly one per account.
--   MIGRATING  a dormant generation being re-encrypted into the active one.
--              At most one per account.
--   DORMANT    no longer written to; still openable by a credential she holds.
--   ORPHANED   no wrapper the server holds can open it.
--
-- ORPHANED is not a claim that no copy of the key exists anywhere. A device
-- that cached the key keeps it until it discards it, and no server action
-- reaches that. The state describes what the server can offer, which is the
-- only thing the server can honestly describe.
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Crypto.Generation', 'U') IS NULL
BEGIN
    CREATE TABLE [Crypto].[Generation] (
        GenerationId        UNIQUEIDENTIFIER NOT NULL
            CONSTRAINT DF_Generation_Id DEFAULT NEWSEQUENTIALID(),
        UserId              UNIQUEIDENTIFIER NOT NULL,
        /*  Monotonic per account, and stable: it appears in the record
            envelope's associated data, so it can never be renumbered. */
        GenerationNumber    INT           NOT NULL,
        [State]             VARCHAR(16)   NOT NULL,
        CreatedOn           DATETIME2(3)  NOT NULL
            CONSTRAINT DF_Generation_CreatedOn DEFAULT SYSUTCDATETIME(),
        RetiredOn           DATETIME2(3)  NULL,
        CONSTRAINT PK_Generation PRIMARY KEY CLUSTERED (GenerationId),
        CONSTRAINT FK_Generation_User FOREIGN KEY (UserId)
            REFERENCES [Identity].[User](UserId),
        CONSTRAINT CK_Generation_State
            CHECK ([State] IN ('ACTIVE', 'MIGRATING', 'DORMANT', 'ORPHANED')),
        CONSTRAINT CK_Generation_Number CHECK (GenerationNumber > 0),
        CONSTRAINT UQ_Generation_Number UNIQUE (UserId, GenerationNumber)
    );
END
GO

-- GEN-1: exactly one ACTIVE generation per account.
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'UX_Generation_Active'
                 AND object_id = OBJECT_ID('Crypto.Generation'))
    CREATE UNIQUE INDEX UX_Generation_Active
        ON [Crypto].[Generation](UserId)
        WHERE [State] = 'ACTIVE';
GO

-- GEN-2: at most one MIGRATING generation per account.
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'UX_Generation_Migrating'
                 AND object_id = OBJECT_ID('Crypto.Generation'))
    CREATE UNIQUE INDEX UX_Generation_Migrating
        ON [Crypto].[Generation](UserId)
        WHERE [State] = 'MIGRATING';
GO

-- ---------------------------------------------------------------------------
-- Crypto.Wrapper
--
-- The data-encryption key, encrypted under a key-encryption key she controls.
-- One row per way she can open a generation.
--
--   PASSWORD   opened by the key derived from her password
--   RECOVERY   opened by the key derived from her recovery phrase
--   DEVICE     opened by a key an enrolled device holds
--
-- The server stores these and cannot open any of them. A wrapper is ciphertext
-- whose key was never transmitted.
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Crypto.Wrapper', 'U') IS NULL
BEGIN
    CREATE TABLE [Crypto].[Wrapper] (
        WrapperId       UNIQUEIDENTIFIER NOT NULL
            CONSTRAINT DF_Wrapper_Id DEFAULT NEWSEQUENTIALID(),
        GenerationId    UNIQUEIDENTIFIER NOT NULL,
        WrapperKind     VARCHAR(16)      NOT NULL,
        /*  Set for DEVICE wrappers, null otherwise. The device table arrives
            with the enrolment slice, so this is deliberately not a foreign key
            yet; it becomes one when there is something to reference. */
        DeviceId        UNIQUEIDENTIFIER NULL,
        Envelope        VARBINARY(MAX)   NOT NULL,
        CreatedOn       DATETIME2(3)     NOT NULL
            CONSTRAINT DF_Wrapper_CreatedOn DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_Wrapper PRIMARY KEY CLUSTERED (WrapperId),
        CONSTRAINT FK_Wrapper_Generation FOREIGN KEY (GenerationId)
            REFERENCES [Crypto].[Generation](GenerationId),
        CONSTRAINT CK_Wrapper_Kind
            CHECK (WrapperKind IN ('PASSWORD', 'RECOVERY', 'DEVICE')),
        CONSTRAINT CK_Wrapper_DeviceId CHECK (
            (WrapperKind = 'DEVICE' AND DeviceId IS NOT NULL)
         OR (WrapperKind <> 'DEVICE' AND DeviceId IS NULL)
        ),
        /*  Envelope floor: magic(4) + version(1) + aead(1) + generation(2)
            + nonce(24) + tag(16) = 48 bytes before any ciphertext. A shorter
            value is not a short wrapper, it is a corrupt one. */
        CONSTRAINT CK_Wrapper_EnvelopeLength
            CHECK (DATALENGTH(Envelope) >= 48)
    );
END
GO

/*  One password wrapper and one recovery wrapper per generation; one device
    wrapper per device per generation. SQL Server treats NULLs as equal in a
    unique index, which is exactly the behaviour wanted here. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'UX_Wrapper_Generation_Kind_Device'
                 AND object_id = OBJECT_ID('Crypto.Wrapper'))
    CREATE UNIQUE INDEX UX_Wrapper_Generation_Kind_Device
        ON [Crypto].[Wrapper](GenerationId, WrapperKind, DeviceId);
GO

-- ---------------------------------------------------------------------------
-- Crypto.RecoveryVerifier
--
-- The public half of a signing key derived from her recovery entropy, under a
-- different HKDF label from the key that wraps the data key. It lets the
-- server verify that a caller holds the recovery phrase without the phrase,
-- the wrapping key or the data key ever reaching it.
--
-- One per generation, and it exists only because the generation exists. That
-- is the whole enforcement of the staging boundary: material staged for a
-- reset that has not committed has no generation to hang from, so it cannot be
-- stored here and cannot be found by a verifier lookup.
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Crypto.RecoveryVerifier', 'U') IS NULL
BEGIN
    CREATE TABLE [Crypto].[RecoveryVerifier] (
        GenerationId    UNIQUEIDENTIFIER NOT NULL,
        Algorithm       VARCHAR(16)      NOT NULL
            CONSTRAINT DF_RecoveryVerifier_Algorithm DEFAULT 'ED25519',
        PublicKey       VARBINARY(32)    NOT NULL,
        CreatedOn       DATETIME2(3)     NOT NULL
            CONSTRAINT DF_RecoveryVerifier_CreatedOn DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_RecoveryVerifier PRIMARY KEY CLUSTERED (GenerationId),
        CONSTRAINT FK_RecoveryVerifier_Generation FOREIGN KEY (GenerationId)
            REFERENCES [Crypto].[Generation](GenerationId),
        CONSTRAINT CK_RecoveryVerifier_Algorithm
            CHECK (Algorithm IN ('ED25519')),
        CONSTRAINT CK_RecoveryVerifier_PublicKeyLength
            CHECK (DATALENGTH(PublicKey) = 32)
    );
END
GO

-- ---------------------------------------------------------------------------
-- Crypto.Record
--
-- Encrypted records. The server stores the envelope and the small amount of
-- routing information it needs to hand the right bytes back, and nothing else.
--
-- RecordId, Version and SchemaVersion are bound into the envelope's associated
-- data, so a record cannot be served in place of another, nor an older version
-- passed off as a newer one WITHOUT the client noticing -- provided the client
-- knows what version to expect. In v1 it has no trustworthy source for that
-- expectation, so rollback of a record is not detected. That limitation is
-- recorded in the protocol's threat boundary and must not be claimed away.
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Crypto.Record', 'U') IS NULL
BEGIN
    CREATE TABLE [Crypto].[Record] (
        RecordId        UNIQUEIDENTIFIER NOT NULL,
        UserId          UNIQUEIDENTIFIER NOT NULL,
        GenerationId    UNIQUEIDENTIFIER NOT NULL,
        /*  What kind of thing this is -- journal entry, note, reflection.
            Deliberately coarse. The server routes on it; it never infers from
            it, and it must never become a classification of her interior
            life. */
        RecordKind      VARCHAR(32)      NOT NULL,
        SchemaVersion   INT              NOT NULL,
        [Version]       INT              NOT NULL,
        Envelope        VARBINARY(MAX)   NOT NULL,
        CreatedOn       DATETIME2(3)     NOT NULL
            CONSTRAINT DF_Record_CreatedOn  DEFAULT SYSUTCDATETIME(),
        ModifiedOn      DATETIME2(3)     NOT NULL
            CONSTRAINT DF_Record_ModifiedOn DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_Record PRIMARY KEY CLUSTERED (RecordId),
        CONSTRAINT FK_Record_User FOREIGN KEY (UserId)
            REFERENCES [Identity].[User](UserId),
        CONSTRAINT FK_Record_Generation FOREIGN KEY (GenerationId)
            REFERENCES [Crypto].[Generation](GenerationId),
        CONSTRAINT CK_Record_Version CHECK ([Version] > 0),
        CONSTRAINT CK_Record_SchemaVersion CHECK (SchemaVersion > 0),
        CONSTRAINT CK_Record_EnvelopeLength CHECK (DATALENGTH(Envelope) >= 48)
    );
END
GO

/*  Records of one account, by generation. This is the read path and also what
    a migration walks. Records may span generations while one is being
    migrated; that is expected and is not an invariant violation. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Record_User_Generation'
                 AND object_id = OBJECT_ID('Crypto.Record'))
    CREATE INDEX IX_Record_User_Generation
        ON [Crypto].[Record](UserId, GenerationId)
        INCLUDE (RecordKind, [Version], ModifiedOn);
GO

-- Supporting index for FK_Record_Generation, required by index_coverage_test.
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Record_GenerationId'
                 AND object_id = OBJECT_ID('Crypto.Record'))
    CREATE INDEX IX_Record_GenerationId
        ON [Crypto].[Record](GenerationId);
GO

-- Supporting index for FK_Generation_User.
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Generation_UserId'
                 AND object_id = OBJECT_ID('Crypto.Generation'))
    CREATE INDEX IX_Generation_UserId
        ON [Crypto].[Generation](UserId)
        INCLUDE ([State], GenerationNumber);
GO

-- Supporting index for FK_UserCredential_User.
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_UserCredential_UserId'
                 AND object_id = OBJECT_ID('Identity.UserCredential'))
    CREATE INDEX IX_UserCredential_UserId
        ON [Identity].[UserCredential](UserId)
        INCLUDE (CredentialVersion, IsAuthoritative);
GO
