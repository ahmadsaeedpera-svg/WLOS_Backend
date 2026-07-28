/*  51_Procs_Inspector_Behaviour.sql

    The Decision Inspector, extended to behaviour.

    Split into its own script for an ordering reason a fresh build found and
    incremental testing hid: this procedure declares variables of
    Behaviour.DaySet and Behaviour.HourSet, and those types are created by
    49_Behaviour.sql. Kept in 47 it referenced a type that did not exist yet,
    and the whole deployment stopped at position 36 of 43.

    So it lives after Behaviour rather than with the rest of the inspector.
    Position carries the dependency, the same way 57_AuditContract_Apply.sql
    carries "after every table".

    Everything the inspector guarantees still holds here: no user id, no
    timeline, no snapshot. inspector_test.sql asserts that of every procedure
    named usp_Inspector%, wherever it is defined.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- usp_Inspector_SimulateBehaviour
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Dashboard.usp_Inspector_SimulateBehaviour') IS NOT NULL
    DROP PROCEDURE [Dashboard].[usp_Inspector_SimulateBehaviour];
GO
/*  What the behaviour engine would say about a woman who logged like this.

    The operator describes a pattern - "she logged on these days out of the last
    eight weeks" - and gets back every measure: consistency, streaks, momentum,
    rhythm, the probabilities, and the confidence behind each. It is the same
    arithmetic the real path runs, because Behaviour.fn_Measure is the only copy
    of it and this procedure simply hands it a different day set.

    That is what made this possible. Until fn_Observe was split, the arithmetic
    read Timeline.Event directly, and simulating behaviour would have meant a
    second implementation of fourteen measures. An operator would eventually
    have been configuring the platform against a fiction, which is worse than
    having no inspector - so the inspector went without until the refactor
    landed rather than the refactor being worked around.

    No user id, no timeline, no snapshot. inspector_test.sql asserts that of
    every procedure in this file. */
CREATE PROCEDURE [Dashboard].[usp_Inspector_SimulateBehaviour]
    @SubjectKey     VARCHAR(40),
    /*  Days ago she did it: '0,1,2,5' means today, yesterday, the day before,
        and five days back. Offsets rather than dates so a saved scenario still
        means the same thing next week. */
    @DayOffsetsCsv  NVARCHAR(MAX),
    /*  Optional. Which local hour those events fell in, so the preference
        measures have something to read. */
    @HourOfDay      TINYINT = NULL,
    @WindowDays     INT = 56
AS
BEGIN
    SET NOCOUNT ON;

    IF @WindowDays IS NULL OR @WindowDays < 7   SET @WindowDays = 7;
    IF @WindowDays > 400                        SET @WindowDays = 400;

    /*  Anchored to today. The inspector has no account to read a date from, and
        a fixed date would make a saved scenario drift out of its own window. */
    DECLARE @asOf DATE = CAST(SYSUTCDATETIME() AS DATE);

    DECLARE @days  [Behaviour].[DaySet];
    DECLARE @hours [Behaviour].[HourSet];

    /*  Offsets outside the window are dropped rather than refused: an operator
        widening then narrowing the window should not lose their pattern. */
    INSERT @days (SubjectKey, LocalDate, EventCount)
    SELECT DISTINCT
        @SubjectKey,
        DATEADD(DAY, -TRY_CAST(LTRIM(RTRIM(s.[value])) AS INT), @asOf),
        1
    FROM STRING_SPLIT(ISNULL(@DayOffsetsCsv, N''), ',') s
    WHERE TRY_CAST(LTRIM(RTRIM(s.[value])) AS INT) BETWEEN 0 AND @WindowDays - 1;

    IF @HourOfDay BETWEEN 5 AND 23
        INSERT @hours (SubjectKey, HourNo, EventCount)
        SELECT @SubjectKey, @HourOfDay, COUNT(*) FROM @days;

    SELECT
        m.SubjectKey,
        s.DisplayName AS SubjectName,
        s.DomainCode,
        s.IsHealthSensitive,
        m.MeasureCode,
        m.MeasureName,
        m.Family,
        m.ValueKind,
        m.Unit,
        m.ValueNumeric,
        m.ValueText,
        m.Confidence,
        m.SpanDays,
        m.SupportingEventCount,
        m.FirstObservedDate,
        m.LastObservedDate,
        m.Reason,
        m.EvidenceCsv
    FROM [Behaviour].[fn_Measure](@days, @hours, @asOf, @WindowDays) m
    JOIN [Behaviour].[Subject] s ON s.SubjectKey = m.SubjectKey
    WHERE m.SubjectKey = @SubjectKey
    ORDER BY m.SortOrder;
END
GO
