namespace Maren.Contracts;

/// <summary>
/// A recommendation the platform assembled for her.
/// </summary>
/// <remarks>
/// <para>
/// Assembled, never inferred. Every field after <see cref="Confidence"/> exists
/// so the suggestion can justify itself: a woman asking "why am I being told
/// this" gets an answer made of observations she logged, not a description of
/// an algorithm.
/// </para>
/// <para>
/// There is no accept or dismiss here. What she does about a suggestion is a
/// timeline event like everything else the platform observes, and a separate
/// acceptance store would be a second record of her behaviour that Behaviour
/// could not see.
/// </para>
/// </remarks>
public sealed record Recommendation(
    string RecommendationKey,
    string DisplayName,
    string DomainCode,

    /// <summary>What she is actually told, written from her side of the screen.</summary>
    string BodyText,
    bool IsHealthSensitive,

    /// <summary>1-5. How much this tends to move the thing it is about.</summary>
    int ExpectedBenefit,

    /// <summary>1-5. What it costs her. A woman with no energy needs the low one.</summary>
    int ExpectedEffort,

    int Priority,

    /// <summary>Inherited from the observations that matched, never asserted.</summary>
    int Confidence,

    /// <summary>How many configured inputs matched.</summary>
    int MatchedCount,

    /// <summary>A suggestion about tonight is wrong tomorrow.</summary>
    DateTime ExpiresUtc,

    /// <summary>The sentences of the observations that matched, joined.</summary>
    string Reason,

    /// <summary>The observations themselves, as <c>kind:key</c>.</summary>
    IReadOnlyList<string> Evidence,

    /// <summary>Which engines contributed: behaviour, signal, goal, routine, state.</summary>
    IReadOnlyList<string> Engines,
    string EngineVersion);

/// <summary>A recommendation as configured, for operators.</summary>
public sealed record RecommendationSummary(
    string RecommendationKey,
    string DisplayName,
    string DomainCode,
    string BodyText,
    int BasePriority,
    int ExpectedBenefit,
    int ExpectedEffort,
    int LifetimeHours,
    bool IsHealthSensitive,
    bool IsActive,
    int InputCount,

    /// <summary>Zero means it fires the moment any optional input matches.</summary>
    int RequiredCount,

    /// <summary>How many rules narrow it. Zero means universal.</summary>
    int RuleCount,

    /// <summary>Every input in words, required ones first.</summary>
    string InputsText);

/// <summary>One configured input, and whether the simulated evidence matched it.</summary>
/// <remarks>
/// Returned for inputs that did not match as well as those that did. A list of
/// only what fired explains a recommendation's presence and never its absence,
/// and absence is what an operator is usually investigating.
/// </remarks>
public sealed record SimulatedInput(
    string RecommendationKey,
    string DisplayName,
    string InputKind,
    string InputKey,
    string Comparison,
    decimal? ThresholdValue,
    bool IsRequired,
    int Weight,
    string ReasonText,
    bool WasSupplied,
    bool IsMatch,
    decimal? SuppliedValue);

/// <summary>What the platform would suggest, given evidence an operator described.</summary>
public sealed record SimulateRecommendationsResponse(
    IReadOnlyList<Recommendation> Assembled,
    IReadOnlyList<SimulatedInput> Inputs);

/// <summary>Evidence in the operator shorthand: <c>behaviour:hydration.consistency=40</c>.</summary>
public sealed record SimulateRecommendationsRequest(
    string EvidenceCsv,
    int? Confidence);
