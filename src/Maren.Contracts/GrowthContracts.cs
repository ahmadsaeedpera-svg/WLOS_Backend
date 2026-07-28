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
