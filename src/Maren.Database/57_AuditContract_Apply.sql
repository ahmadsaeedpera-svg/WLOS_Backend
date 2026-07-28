/*  48_AuditContract_Apply.sql

    Applies the audit contract to every table, after every table exists.

    This script must stay last in the deployment order. That is its entire
    purpose.

    08_AuditContract.sql defines the contract and applies it with a cursor over
    sys.tables. It runs at position 9 of 37, so it cannot see anything created
    by scripts 30 to 47 — the whole Women's Life OS: life stages, timeline,
    knowledge graph, dashboard, intelligence and rules.

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
    expresses and a comment does not. When a script 49 adds tables, this one
    becomes 50 and the requirement is still visible in the ordering itself.

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
