/*  74_AuditContract_Apply.sql

    Applies the audit contract to every table, after every table exists.

    This script must stay last in the deployment order. That is its entire
    purpose.

    It has been 48, 51, 54, 65, 69, 72, and is now 74 — renumbered every
    time a script added tables, which is exactly the case the rule exists for.
    The number is the requirement: a comment saying "run me last" is not
    checked by anything, and a position is. The header carried the wrong number
    through two of those moves without any consequence, which is the argument
    for the assertion suite below rather than for a more careful reader.

    08_AuditContract.sql defines the contract and applies it with a cursor over
    sys.tables. It runs at position 9, so it cannot see anything created by the
    scripts after it — the whole Women's Life OS: life stages, timeline,
    knowledge graph, dashboard, intelligence, rules, behaviour, growth,
    recommendation, coach, prediction and now the operations journals.

    Run once, in the documented order, on an empty server, that left 19 tables
    without the contract: 147 missing columns and 19 missing filtered indexes.
    Among them Timeline.Event and Intelligence.UserStateSnapshot, which hold
    what a woman logs and what the platform infers from it. Those are the last
    two tables in the platform that should be missing attribution and soft
    delete.

    It went unnoticed because the databases used for verification had this file
    applied more than once — a second pass over an already-built database picks
    the later tables up. A deployment to a genuinely new server would not have
    had that accident, so a first production database would have failed its own
    audit contract on day one.

    A new numbered script rather than renumbering 08: the ordering requirement
    is "after every table", and that is a property of position, which a number
    expresses and a comment does not. When a script adds tables, this one is
    renumbered past it and the requirement stays visible in the ordering.

    The logic is not repeated here. dbo.usp_ApplyAuditContract is defined in 08
    and called by both, because two copies of a cursor that silently adds
    columns would drift, and the drift would only surface as a table quietly
    missing its soft-delete columns.

    audit_contract_test.sql asserts that nothing is left non-compliant, so this
    cannot regress unnoticed the next time a table is added.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('dbo.usp_ApplyAuditContract') IS NULL
    THROW 51000,
        'dbo.usp_ApplyAuditContract is missing. Run 08_AuditContract.sql first.',
        1;
GO

EXEC dbo.usp_ApplyAuditContract;
GO
