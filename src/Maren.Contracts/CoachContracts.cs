namespace Maren.Contracts;

/// <summary>
/// The coach explaining one recommendation the platform already made.
/// </summary>
/// <remarks>
/// <para>
/// The coach invents nothing, and that is structural rather than reviewed. A
/// message is filled in, not written: a tone supplies a pattern with the
/// recommendation and its reasoning as placeholders, and a database constraint
/// refuses a pattern that drops either. Every fact in
/// <see cref="MessageText"/> came from the recommendation, and those came from
/// her timeline.
/// </para>
/// <para>
/// It never reassembles. A coach that did would be a second opinion about the
/// same woman, and the two could disagree the moment a threshold changed.
/// </para>
/// </remarks>
public sealed record CoachMessage(
    string RecommendationKey,
    string DisplayName,
    string ToneCode,
    string ToneName,

    /// <summary>
    /// Why this voice was chosen. About the platform's choice, never about her —
    /// a tone selected without a stated reason is indistinguishable from one
    /// selected at random.
    /// </summary>
    string ToneRationale,

    /// <summary>False when nothing about today suggested a voice and the fallback was used.</summary>
    bool ToneFromRule,

    /// <summary>What she reads. Composed by substitution, so it adds no facts.</summary>
    string MessageText,

    int Priority,

    /// <summary>Carried through from the recommendation. The coach observes nothing.</summary>
    int Confidence,
    int ExpectedEffort,

    /// <summary>Carried through unchanged, as <c>kind:key</c>.</summary>
    IReadOnlyList<string> Evidence,
    DateTime ExpiresUtc,
    string EngineVersion);

/// <summary>A tone as configured, for operators.</summary>
public sealed record CoachToneSummary(
    string ToneCode,
    string DisplayName,
    string Description,

    /// <summary>Must contain <c>{body}</c> and <c>{reason}</c>. Enforced by the database.</summary>
    string Pattern,
    int Weight,
    bool IsDefault,
    bool IsActive,

    /// <summary>A non-default tone with no rules can never be selected.</summary>
    int RuleCount,
    string RulesText);

/// <summary>One tone rule, and whether the described evidence selected it.</summary>
public sealed record SimulatedTone(
    string ToneCode,
    string DisplayName,
    string Pattern,
    int Weight,
    bool IsDefault,
    bool IsActive,
    string? InputKind,
    string? InputKey,
    string? Comparison,
    decimal? ThresholdValue,
    string? RationaleText,
    bool WasSupplied,
    bool IsMatch,
    decimal? SuppliedValue);

/// <summary>What the platform would say, and in what voice.</summary>
public sealed record SimulateCoachResponse(
    IReadOnlyList<CoachMessage> Messages,

    /// <summary>
    /// Every tone with whether this evidence selected it. Answers "why is it not
    /// being gentle", which the chosen tone alone cannot.
    /// </summary>
    IReadOnlyList<SimulatedTone> Tones);
