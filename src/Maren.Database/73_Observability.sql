/*  73_Observability.sql

    Correlation: tying what a woman's request did to what the platform wrote
    down about it.

    The problem
    -----------
    `Audit.AuditLog` has carried a `CorrelationId` column since
    05_Content_Notifications_Audit.sql. It is selected back by
    `usp_Audit_Search` and surfaced in `AuditEntry`. **Nothing has ever written
    it.** On the verification database: 157 audit rows, 0 correlated.

    That is not a cosmetic gap. Audit exists so that "who changed this, and
    why" has an answer. Without correlation, an audit trail is a list of
    individual facts with no way to say *these six rows were one action* — so a
    support question ("what happened when she reported this?") is answered by
    reading timestamps and guessing. The same request may write to
    `Audit.AuditLog`, `Access.SecurityEvent` and `AI.SafetyEvent`, and nothing
    joined them.

    Why this is a DEFAULT and not a parameter
    -----------------------------------------
    The obvious implementation is to add a `@CorrelationId` parameter to every
    command procedure and pass it down. There are 33 audit write sites across
    more than a dozen procedures, and every future engine adds more — the cost
    of that approach grows with the platform, which is the definition of the
    debt this is meant to remove.

    Instead the value is established once per connection in
    `SESSION_CONTEXT`, and the column defaults from it. An `INSERT` that omits
    the column — which is exactly what all 33 existing write sites do — picks
    it up without being touched. **No existing procedure is edited by this
    script**, and a new engine gets correlation by writing an audit row the
    ordinary way, with no knowledge that correlation exists.

    That is the same "registration only" property the pipeline stages have, and
    it is what makes this affordable to have done at all.

    Why it cannot be spoofed into the wrong place
    --------------------------------------------
    `SESSION_CONTEXT` is per-session. One connection cannot read or write
    another's, so a correlation id cannot leak between concurrent requests
    inside the database. The API sets it on **every** connection it opens, so a
    pooled connection cannot inherit the previous request's value either —
    asserted by an integration test, because that is the failure that would
    quietly attribute one woman's actions to another request.

    What this does not do
    ---------------------
    It carries no personal data. A correlation id is a random GUID minted per
    request; it identifies a request, never a person. It is safe to put in a
    log line, a response header and a support ticket, which is the whole point.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- Audit.AuditLog
-- ---------------------------------------------------------------------------
/*  Guarded, and named, so re-applying converges and a later script can find
    it. The column already exists and is already nullable — this adds only the
    default, so no existing row changes and no write path is disturbed. */
IF NOT EXISTS (SELECT 1 FROM sys.default_constraints
               WHERE name = 'DF_AuditLog_CorrelationId')
    ALTER TABLE [Audit].[AuditLog]
        ADD CONSTRAINT DF_AuditLog_CorrelationId
        DEFAULT CAST(SESSION_CONTEXT(N'CorrelationId') AS UNIQUEIDENTIFIER)
        FOR CorrelationId;
GO

-- ---------------------------------------------------------------------------
-- AI.SafetyEvent
-- ---------------------------------------------------------------------------
/*  The safety ledger carries the same column and the same gap. A refusal by
    the AI guardrails and the audit rows for the request that triggered it
    belong to one story, and until now nothing said so.

    There is no model integration yet, so this table is empty — which is the
    cheapest possible moment to make it correlate. */
IF NOT EXISTS (SELECT 1 FROM sys.default_constraints
               WHERE name = 'DF_SafetyEvent_CorrelationId')
    ALTER TABLE [AI].[SafetyEvent]
        ADD CONSTRAINT DF_SafetyEvent_CorrelationId
        DEFAULT CAST(SESSION_CONTEXT(N'CorrelationId') AS UNIQUEIDENTIFIER)
        FOR CorrelationId;
GO

-- ---------------------------------------------------------------------------
-- fn_CurrentCorrelation
-- ---------------------------------------------------------------------------
IF OBJECT_ID('dbo.fn_CurrentCorrelation') IS NOT NULL
    DROP FUNCTION [dbo].[fn_CurrentCorrelation];
GO
/*  The correlation id of the current session, or NULL when none was set.

    A function rather than every caller writing the CAST, so there is one
    spelling of "what is the current correlation" in the database. The
    assertion suite uses it, and any future procedure that needs to correlate
    something the default cannot reach should use it rather than re-deriving
    the expression. */
CREATE FUNCTION [dbo].[fn_CurrentCorrelation]()
RETURNS UNIQUEIDENTIFIER
AS
BEGIN
    RETURN CAST(SESSION_CONTEXT(N'CorrelationId') AS UNIQUEIDENTIFIER);
END
GO

PRINT 'Observability — correlation defaults ready.';
GO
