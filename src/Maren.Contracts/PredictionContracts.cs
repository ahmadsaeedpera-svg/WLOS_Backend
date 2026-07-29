namespace Maren.Contracts;

/// <summary>
/// One forward statement about her behaviour, framed from something Behaviour
/// already observed.
/// </summary>
/// <remarks>
/// <para>
/// This engine computes no probability. Behaviour observes three — the chance
/// of doing a thing again, of still logging, of stopping — and a prediction
/// attaches a window to one of them and says it out loud. That is structural:
/// a prediction type may only name a measure the behaviour engine publishes as
/// a probability, enforced by a foreign key carrying the measure's family.
/// </para>
/// <para>
/// Behavioural only. Nothing here describes a condition, an outcome of one, or
/// a cause, and nothing here is deterministic:
/// <see cref="StatementText"/> always carries the chance, the window and the
/// support, because a database constraint refuses a framing that drops any of
/// them. A bare percentage reads as knowledge and is a summary of a few weeks.
/// </para>
/// </remarks>
public sealed record Prediction(
    string PredictionKey,
    string DisplayName,

    /// <summary>The thing she does that this is about.</summary>
    string SubjectKey,
    string SubjectName,

    string HorizonCode,
    string HorizonName,

    /// <summary>How far ahead the statement reaches.</summary>
    int WindowDays,

    /// <summary>
    /// Carried through from the behaviour measure unchanged. The 0–1 value said
    /// as a whole percent is the only transformation this engine performs.
    /// </summary>
    int ProbabilityPercent,

    /// <summary>The days of history the probability rests on.</summary>
    int SupportDays,

    /// <summary>Inherited from the observation, never asserted.</summary>
    int Confidence,

    /// <summary>
    /// What she reads. Filled into a framing pattern, so every fact in it came
    /// from the observation.
    /// </summary>
    string StatementText,

    /// <summary>Resolves back to the behaviour observation, as <c>kind:key</c>.</summary>
    IReadOnlyList<string> Evidence,

    /// <summary>The behaviour measure this frames. Always a probability.</summary>
    string SourceMeasureCode,

    DateTime ExpiresUtc,
    string EngineVersion);

/// <summary>A prediction type as configured, for operators.</summary>
/// <remarks>
/// Carries the source measure and its family beside the framing, because the
/// question an operator arrives with is "where does this number come from" and
/// the honest answer is the name of a measure in another engine.
/// </remarks>
public sealed record PredictionTypeSummary(
    string PredictionKey,
    string DisplayName,
    string Description,
    string HorizonCode,
    string HorizonName,
    string PhraseText,
    int WindowDays,
    string SourceMeasureCode,
    string SourceMeasureName,

    /// <summary>Always <c>probability</c>. The schema permits nothing else.</summary>
    string SourceFamily,
    int SourceMinSpanDays,

    /// <summary>Must contain <c>{chance}</c>, <c>{window}</c> and <c>{support}</c>.</summary>
    string FramingPattern,

    /// <summary>Below this the prediction is withheld entirely, not hedged.</summary>
    int MinConfidence,
    int MinSupportDays,
    int LifetimeHours,
    bool IsActive,

    /// <summary>
    /// False when the behaviour measure underneath has been switched off. Such a
    /// prediction can never fire, and looks identical to one nobody qualifies for.
    /// </summary>
    bool SourceIsActive);

/// <summary>Observations an operator describes, to see what would be said about them.</summary>
public sealed record SimulatePredictionRequest(
    /// <summary>
    /// <c>subject.measure=value@span</c>, comma separated. The span suffix is
    /// optional and falls back to <see cref="DefaultSpanDays"/>.
    /// </summary>
    string ObservationCsv,
    int? Confidence,
    int? DefaultSpanDays);

/// <summary>One prediction type against the observations, and whether it fired.</summary>
/// <remarks>
/// The important half of the simulation. This engine withholds deliberately and
/// often, and "nothing appeared" is indistinguishable from a bug without a
/// stated reason.
/// </remarks>
public sealed record SimulatedPrediction(
    string PredictionKey,
    string DisplayName,
    string SourceMeasureCode,
    string HorizonCode,
    int MinConfidence,
    int MinSupportDays,
    bool IsActive,
    string? SubjectKey,
    decimal? SuppliedValue,
    int? SuppliedConfidence,
    int? SuppliedSpanDays,
    bool WasSupplied,
    bool IsPredicted,

    /// <summary>Why it fired, or why it did not. Written for the person reading it.</summary>
    string Explanation);

/// <summary>What the platform would predict, and what it would withhold.</summary>
public sealed record SimulatePredictionResponse(
    IReadOnlyList<Prediction> Predictions,

    /// <summary>
    /// Every prediction type with whether these observations produced it.
    /// Answers "why is nothing shown", which the predictions alone cannot.
    /// </summary>
    IReadOnlyList<SimulatedPrediction> Considered);
