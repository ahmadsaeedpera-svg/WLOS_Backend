/*  31_AI_Safety.sql

    The safety ledger for the AI companion.

    Increment 1 of the order set out in docs/ai/AI_PIPELINE.md section 7: every
    guardrail ships and is proven before the first token is ever generated.
    Nothing here calls a model, and nothing here depends on one existing.

    What this table is for
    ----------------------
    One question, asked continuously: is the boundary holding? The companion
    must never diagnose and never prescribe (docs/ai/AI_SYSTEM.md section 2),
    and a rule nobody measures is a rule that quietly stops being true. This
    records that a refusal happened, which category it fell into, and what the
    classifiers scored - enough to alert on drift and to reproduce an incident.

    What this table deliberately cannot hold
    ----------------------------------------
    The message. Not the woman's, not the model's.

    There is no content column, and ai_safety_test.sql fails the build if one
    is ever added. That is the point of the design rather than an oversight:
    the product's privacy position is that conversation stays on the device, so
    a server-side table of what people asked their health companion would
    reverse it in a single migration. A safety ledger answers "is the boundary
    holding"; it does not need to answer "what did she say".

    Append-only, like Audit.AuditLog
    --------------------------------
    No procedure updates or deletes it, and the test asserts that. It is
    registered in dbo.AuditContractExemption for the same reason the audit log
    is: soft-delete columns would advertise a capability that must never exist.

    UserId carries no foreign key, matching Audit.AuditLog.ActorUserId. A
    safety ledger must not be the thing that blocks erasing an account.

    Idempotent. Purely additive - no existing table, column or procedure is
    touched.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE [name] = 'AI')
    EXEC('CREATE SCHEMA [AI]');
GO

IF OBJECT_ID('AI.SafetyEvent') IS NULL
CREATE TABLE [AI].[SafetyEvent] (
    SafetyEventId   BIGINT IDENTITY(1,1) NOT NULL,
    OccurredUtc     DATETIME2(3) NOT NULL
                        CONSTRAINT DF_SafetyEvent_OccurredUtc DEFAULT SYSUTCDATETIME(),

    /*  Nullable and unconstrained by design. An event may be recorded for an
        anonymous or already-erased account, and this table must never be the
        reason a deletion cannot proceed. */
    UserId          UNIQUEIDENTIFIER NULL,

    /*  Which of the fourteen domains the turn was about. Enumerated here as a
        constraint rather than left as free text so that widening the
        companion's scope is a deliberate schema change somebody reviews,
        not a string that appears one day in production. */
    [Domain]        VARCHAR(30) NOT NULL,

    /*  answered    - the model replied
        refused     - declined before generation, on classification
        replaced    - generated, then rejected by the output screen
        intercepted - never reached the model at all (crisis path) */
    Decision        VARCHAR(20) NOT NULL,

    RefusalCategory VARCHAR(40) NULL,

    /*  Classifier outputs, 0..1. Kept because a drifting distribution is the
        earliest warning that a prompt or model change has moved the boundary,
        and it is visible here long before it is visible in complaints. */
    ClinicalScore   DECIMAL(4,3) NULL,
    CrisisScore     DECIMAL(4,3) NULL,

    /*  Which prompt and model served the turn. Without these an eval result
        cannot be reproduced and an incident cannot be investigated. */
    PromptVersion   VARCHAR(60) NOT NULL,
    ModelId         VARCHAR(100) NULL,

    LatencyMs       INT NULL,
    CorrelationId   UNIQUEIDENTIFIER NULL,

    CONSTRAINT PK_SafetyEvent PRIMARY KEY CLUSTERED (SafetyEventId),

    CONSTRAINT CK_SafetyEvent_Domain CHECK ([Domain] IN (
        'lifestyle', 'nutrition', 'habits', 'sleep', 'exercise',
        'mental_wellness', 'routine', 'productivity', 'hydration',
        'medication_reminder', 'relationships', 'learning', 'career',
        'planning', 'other')),

    CONSTRAINT CK_SafetyEvent_Decision CHECK (Decision IN (
        'answered', 'refused', 'replaced', 'intercepted')),

    CONSTRAINT CK_SafetyEvent_RefusalCategory CHECK (
        RefusalCategory IS NULL OR RefusalCategory IN (
            'diagnosis', 'medication', 'interpretation', 'urgency',
            'crisis', 'out_of_scope', 'no_sources', 'screen_reject')),

    /*  Anything that is not a plain answer must say why. A refusal with no
        category is a row that cannot be alerted on, which makes recording it
        pointless. */
    CONSTRAINT CK_SafetyEvent_RefusalHasCategory CHECK (
        Decision = 'answered' OR RefusalCategory IS NOT NULL),

    CONSTRAINT CK_SafetyEvent_Scores CHECK (
        (ClinicalScore IS NULL OR ClinicalScore BETWEEN 0 AND 1) AND
        (CrisisScore   IS NULL OR CrisisScore   BETWEEN 0 AND 1))
);
GO

/*  Time-ordered reads: "what has the boundary done this week". DESC because
    every question asked of this table is about the recent end of it. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_SafetyEvent_Occurred'
                 AND object_id = OBJECT_ID('[AI].[SafetyEvent]'))
    CREATE INDEX [IX_SafetyEvent_Occurred]
        ON [AI].[SafetyEvent] (OccurredUtc DESC);
GO

/*  The alerting query from docs/ai/AI_PIPELINE.md section 5: refusal rate by
    category over time. A fall in that rate is a regression signal, not good
    news, so it is worth being able to ask cheaply and often. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_SafetyEvent_Decision_Occurred'
                 AND object_id = OBJECT_ID('[AI].[SafetyEvent]'))
    CREATE INDEX [IX_SafetyEvent_Decision_Occurred]
        ON [AI].[SafetyEvent] (Decision, OccurredUtc DESC)
        INCLUDE (RefusalCategory, [Domain]);
GO

/*  Keep the audit-column contract away from this table.

    08_AuditContract.sql adds CreatedBy/DeletedOn/IsDeleted and friends to every
    table that has not been exempted. On a second application it would find this
    one and give an append-only ledger a soft-delete column - which is exactly
    the capability that must not exist. The exemption carries its reason in the
    row, as that script requires. */
MERGE dbo.AuditContractExemption AS target
USING (VALUES
    ('AI', 'SafetyEvent',
     N'Append-only by design, like Audit.AuditLog. No procedure updates or '
     + N'deletes it and ai_safety_test.sql asserts that. Soft-delete columns '
     + N'would advertise a capability that must never exist on a safety ledger.')
) AS source (SchemaName, TableName, Reason)
    ON target.SchemaName = source.SchemaName
   AND target.TableName = source.TableName
WHEN NOT MATCHED THEN
    INSERT (SchemaName, TableName, Reason)
    VALUES (source.SchemaName, source.TableName, source.Reason);
GO
