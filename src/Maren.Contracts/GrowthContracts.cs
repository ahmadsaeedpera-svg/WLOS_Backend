namespace Maren.Contracts;

/// <summary>
/// The Personal Growth Platform: goals.
/// </summary>
/// <remarks>
/// A goal is a desired outcome — not a reminder, not a habit, not a routine.
/// Those are things she does; a goal is what she is trying to reach by doing
/// them, and progress is the distance between what Behaviour Intelligence
/// observed and what the goal asks for.
/// </remarks>
public sealed record GoalProgress(
    Guid UserGoalId,
    string GoalTemplateKey,
    string DisplayName,
    string DomainCode,

    /// <summary>Why the goal exists, in the platform's words.</summary>
    string PurposeText,

    /// <summary>What is measured and over what period. Never a claim about her body.</summary>
    string ExplanationText,
    bool IsHealthSensitive,

    /// <summary>active, achieved, paused or abandoned.</summary>
    string Status,

    /// <summary>Her reason, in her words. The only part of a goal the platform cannot observe.</summary>
    string? MotivationText,
    int Priority,
    DateOnly StartedOn,
    DateOnly? TargetDate,
    DateOnly? AchievedOn,
    int? ExpectedDurationDays,

    int MeasureCount,
    int MeasuresMet,

    /// <summary>Inherited from the observations behind it, never asserted.</summary>
    int Confidence,

    /// <summary>Null when nothing has been observed. A zero ring would say she has made no progress.</summary>
    decimal? ProgressPercent,
    bool IsComplete,

    /// <summary>Names what is still short, rather than reporting a bare percentage.</summary>
    string Reason,

    /// <summary>The behaviour measures this rests on, as <c>subject.measure</c>.</summary>
    IReadOnlyList<string> Evidence,
    string EngineVersion);

/// <summary>A goal the platform would offer her, and what taking it on would mean.</summary>
public sealed record GoalOffer(
    string GoalTemplateKey,
    string DisplayName,
    string DomainCode,
    string PurposeText,
    string ExplanationText,

    /// <summary>What she is asked when adopting it.</summary>
    string MotivationPrompt,
    int BasePriority,
    int? ExpectedDurationDays,
    bool IsHealthSensitive,
    int MeasureCount,

    /// <summary>What reaching it looks like, in words.</summary>
    string TargetsText);

/// <summary>Taking a goal on.</summary>
public sealed record AdoptGoalRequest(
    string GoalTemplateKey,
    string? MotivationText,
    int? Priority,
    DateOnly? TargetDate);

/// <summary>A goal template as configured, for operators.</summary>
public sealed record GoalTemplateSummary(
    string GoalTemplateKey,
    string DisplayName,
    string DomainCode,
    string PurposeText,
    string ExplanationText,
    string MotivationPrompt,
    int BasePriority,
    int? ExpectedDurationDays,
    bool IsHealthSensitive,
    bool IsActive,
    int MeasureCount,

    /// <summary>How many rules narrow it. Zero means universal — visible, not inferred.</summary>
    int RuleCount,
    string TargetsText,

    /// <summary>The behaviour measures it depends on, as <c>subject.measure</c>.</summary>
    IReadOnlyList<string> Measures);

/// <summary>
/// A routine: several behaviours done together, and where she is up to today.
/// </summary>
/// <remarks>
/// <para>
/// A routine owns no step list. Its composition, required parts and done-today
/// rule all live on the Behaviour subject it observes — two step lists would be
/// two answers to "what is in my evening routine", and the day they disagree is
/// the day her checklist shows four steps while her streak counts three.
/// </para>
/// <para>
/// There is no percentage here and no "mark complete". Whether a routine was
/// done is derived from logged events, every time.
/// </para>
/// </remarks>
public sealed record RoutineToday(
    string RoutineKey,
    string DisplayName,

    /// <summary>The Behaviour subject that observes it.</summary>
    string SubjectKey,
    string PurposeText,
    string DomainCode,

    /// <summary>Local hours. May wrap midnight — a night routine can run 22:00 to 02:00.</summary>
    int StartHour,
    int EndHour,

    /// <summary>What to call the window when telling her: "this evening".</summary>
    string WindowText,
    int BasePriority,
    bool IsHealthSensitive,

    /// <summary>How many required parts make a day count. The subject's rule, not restated.</summary>
    int TargetPerDay,
    int StepCount,
    int RequiredCount,
    int StepsDoneToday,
    int RequiredDoneToday,
    bool IsDoneToday,

    /// <summary>Begun but not finished. "You are one step in" differs from "you have not begun".</summary>
    bool IsStarted,

    decimal? Consistency,
    decimal? CurrentStreak,
    decimal? CompletionProbability,

    /// <summary>Inherited from the consistency observation, never invented here.</summary>
    int Confidence,

    /// <summary>In words, because ticks alone cannot explain why it is asking now.</summary>
    string StatusText,

    IReadOnlyList<RoutineStep> Steps);

/// <summary>One step of a routine, and whether she has done it today.</summary>
public sealed record RoutineStep(
    string EventTypeCode,
    string StepName,

    /// <summary>Optional steps are returned and flagged — hiding them turns optional into non-existent.</summary>
    bool IsRequired,
    int SortOrder,
    bool IsDoneToday,
    DateOnly? LastDoneDate);

/// <summary>A routine as configured, for operators.</summary>
public sealed record RoutineSummary(
    string RoutineKey,
    string DisplayName,
    string SubjectKey,
    string PurposeText,
    string DomainCode,
    int StartHour,
    int EndHour,
    string WindowText,
    int BasePriority,
    bool IsHealthSensitive,
    bool IsActive,

    /// <summary>From the subject. A target above RequiredCount is a routine that can never finish.</summary>
    int TargetPerDay,
    int StepCount,
    int RequiredCount,
    int RuleCount,
    IReadOnlyList<string> Steps);
