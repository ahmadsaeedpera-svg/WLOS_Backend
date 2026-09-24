/*  76_Recovery.sql

    Path R: getting back in with the recovery phrase.

    Specification: docs/architecture/WLOS_RESET_AUTHORIZATION_V1.md section 5.

    What this is for
    ----------------
    She has forgotten her password. She has twelve words on a piece of paper.
    Those words are the only thing left that opens her journal, and this is the
    path that lets her use them without ever sending them anywhere.

    How it works, in one paragraph
    ------------------------------
    The words decode to 128 bits of entropy. One HKDF label turns that into the
    key that unwraps her data key; a different label turns it into an Ed25519
    signing key whose public half this platform already holds. She signs a
    challenge this platform issued; the signature proves she has the phrase and
    reveals nothing about it. **The phrase, the wrapping key and the data key
    never leave her device**, and there is no parameter anywhere in this file
    that could carry one.

    Why a challenge at all
    ----------------------
    Without one the platform would have to take "I have the recovery phrase" on
    trust, which is not a proof and not a credential -- it is a sentence anyone
    can type. The challenge is what makes the claim checkable.

    The three things the challenge has to be
    ---------------------------------------
      * **Issued for every address.** An endpoint that answered only for real
        accounts would say which addresses are registered, and it cannot be
        authenticated -- she has nothing to authenticate with. So a row is
        written for an address with no account too, and the response is the
        same shape either way. `UserId` is null for those.

      * **Single use, consumed on any attempt.** Valid or not. That makes each
        guess cost a fresh round trip and removes the oracle that repeated
        tries against one nonce would otherwise give.

      * **Short-lived.** Ten minutes. A challenge that outlives the sitting it
        belongs to is a credential nobody is watching.

    What is deliberately not stored
    -------------------------------
    The address. A row for an unknown address records an attempt, and writing
    down which addresses were attempted would build exactly the list this
    endpoint exists to avoid revealing. Unknown addresses are rate-limited by
    IP; known ones by account.

    Ordering
    --------
    `81_AuditContract_Apply.sql` must run after this. It applies the audit
    contract with a cursor over sys.tables and cannot see anything created
    after it -- which is why it was renumbered from 76 when this file took that
    number.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- Crypto.RecoveryChallenge
--
-- One row per attempt to use a recovery phrase, successful or not.
--
-- States:
--   ISSUED    a nonce is outstanding and unspent
--   CONSUMED  an attempt was made; the signature did not verify
--   VERIFIED  the signature verified; a reset grant is outstanding
--   SPENT     the grant was used and the reset completed
--
-- CONSUMED is not an error state to be cleaned up. It is the record of a
-- failed attempt, and counting those is how the path locks itself.
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Crypto.RecoveryChallenge', 'U') IS NULL
BEGIN
    CREATE TABLE [Crypto].[RecoveryChallenge] (
        ChallengeId     UNIQUEIDENTIFIER NOT NULL
            CONSTRAINT DF_RecoveryChallenge_Id DEFAULT NEWSEQUENTIALID(),

        /*  Null when the address has no account.

            The row is written anyway, so that answering takes the same work
            and the same time either way. It is the absence of a user, not the
            absence of a row, that says nothing came of it. */
        UserId          UNIQUEIDENTIFIER NULL,

        /*  The generation the phrase would open, captured when the challenge
            is issued. A rotation between issue and use makes the challenge
            stale rather than silently applying to a different key. */
        GenerationId    UNIQUEIDENTIFIER NULL,

        Nonce           VARBINARY(32)    NOT NULL,
        [State]         VARCHAR(16)      NOT NULL
            CONSTRAINT DF_RecoveryChallenge_State DEFAULT 'ISSUED',

        IssuedOn        DATETIME2(3)     NOT NULL
            CONSTRAINT DF_RecoveryChallenge_IssuedOn DEFAULT SYSUTCDATETIME(),
        ExpiresOn       DATETIME2(3)     NOT NULL,
        ConsumedOn      DATETIME2(3)     NULL,

        /*  The reset grant: a short-lived, single-use token issued only after
            a signature verifies, and the only thing that can complete a reset.

            Hashed, like a refresh token. A grant readable from this table
            would be a five-minute password reset for anyone who could read
            the table. */
        GrantHash       VARBINARY(32)    NULL,
        GrantExpiresOn  DATETIME2(3)     NULL,

        /*  For rate limiting an address with no account, which has no user to
            count against. Not the address itself -- see the header. */
        IpAddress       VARCHAR(45)      NULL,

        CONSTRAINT PK_RecoveryChallenge PRIMARY KEY CLUSTERED (ChallengeId),
        CONSTRAINT FK_RecoveryChallenge_User FOREIGN KEY (UserId)
            REFERENCES [Identity].[User](UserId),
        CONSTRAINT FK_RecoveryChallenge_Generation FOREIGN KEY (GenerationId)
            REFERENCES [Crypto].[Generation](GenerationId),
        CONSTRAINT CK_RecoveryChallenge_State
            CHECK ([State] IN ('ISSUED', 'CONSUMED', 'VERIFIED', 'SPENT')),
        CONSTRAINT CK_RecoveryChallenge_Nonce
            CHECK (DATALENGTH(Nonce) = 32),

        /*  A grant exists only once a signature has verified. Without this the
            table would permit a grant on a challenge nobody proved anything
            against, which is the one row that must not be constructible. */
        CONSTRAINT CK_RecoveryChallenge_Grant CHECK (
            (GrantHash IS NULL AND GrantExpiresOn IS NULL)
         OR ([State] IN ('VERIFIED', 'SPENT')
             AND GrantHash IS NOT NULL AND GrantExpiresOn IS NOT NULL)
        )
    );
END
GO

-- Supporting index for FK_RecoveryChallenge_User, and the per-account rate
-- limit and failure count both read by user and time.
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_RecoveryChallenge_User_IssuedOn'
                 AND object_id = OBJECT_ID('Crypto.RecoveryChallenge'))
    CREATE INDEX IX_RecoveryChallenge_User_IssuedOn
        ON [Crypto].[RecoveryChallenge](UserId, IssuedOn)
        INCLUDE ([State]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_RecoveryChallenge_GenerationId'
                 AND object_id = OBJECT_ID('Crypto.RecoveryChallenge'))
    CREATE INDEX IX_RecoveryChallenge_GenerationId
        ON [Crypto].[RecoveryChallenge](GenerationId);
GO

-- The per-IP rate limit for addresses with no account.
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_RecoveryChallenge_Ip_IssuedOn'
                 AND object_id = OBJECT_ID('Crypto.RecoveryChallenge'))
    CREATE INDEX IX_RecoveryChallenge_Ip_IssuedOn
        ON [Crypto].[RecoveryChallenge](IpAddress, IssuedOn);
GO

-- Expiry sweep, and the lookup a grant arrives by.
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_RecoveryChallenge_ExpiresOn'
                 AND object_id = OBJECT_ID('Crypto.RecoveryChallenge'))
    CREATE INDEX IX_RecoveryChallenge_ExpiresOn
        ON [Crypto].[RecoveryChallenge](ExpiresOn);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'UX_RecoveryChallenge_Grant'
                 AND object_id = OBJECT_ID('Crypto.RecoveryChallenge'))
    CREATE UNIQUE INDEX UX_RecoveryChallenge_Grant
        ON [Crypto].[RecoveryChallenge](GrantHash)
        WHERE GrantHash IS NOT NULL;
GO
