namespace Maren.Contracts;

/// <summary>
/// Behaviour Intelligence: what the platform has observed about how she lives.
/// </summary>
/// <remarks>
/// <para>
/// One observation is one measure of one subject — how consistently she drinks
/// water, the weekday she is strongest, the chance she completes her wind-down
/// tomorrow. Every engine downstream reads these; none computes its own.
/// </para>
/// <para>
/// Every field after <see cref="BehaviourObservation.ValueText"/> exists so the
/// observation can justify itself. A recommendation built on one has to be able
/// to show why, and a woman asking "why does it think that about me" has to get
/// an answer that is true — which means the answer travels with the number
/// rather than being reconstructed later by code that has since changed.
/// </para>
/// </remarks>
public sealed record BehaviourObservation(
    string SubjectKey,
    string SubjectName,
    string DomainCode,
    bool IsHealthSensitive,

    string MeasureCode,
    string MeasureName,

    /// <summary>habit, rhythm, trend, preference or probability.</summary>
    string Family,

    /// <summary>count, percent, probability, hour, weekday or days.</summary>
    string ValueKind,
    string? Unit,

    /// <summary>Null whenever confidence is zero. Never zero standing in for unknown.</summary>
    decimal? ValueNumeric,

    /// <summary>The value as a person reads it, produced server-side so every client says the same thing.</summary>
    string ValueText,

    /// <summary>Coverage of the span this measure needs. Computed, never asserted.</summary>
    int Confidence,

    /// <summary>Days of her history this was measured over — not the window width.</summary>
    int SpanDays,
    int SupportingEventCount,
    DateOnly? FirstObservedDate,
    DateOnly? LastObservedDate,

    /// <summary>Observational wording: what was logged, over what period.</summary>
    string Reason,

    /// <summary>The event types that carried it, so evidence resolves to her own timeline.</summary>
    IReadOnlyList<string> Evidence,

    /// <summary>
    /// Which version of the observation logic produced this. Without it a change
    /// to the engine makes historical rows unattributable, and nobody can tell a
    /// real change in her behaviour from a change in the definition.
    /// </summary>
    string EngineVersion);

/// <summary>Everything observed about one woman, grouped for reading.</summary>
public sealed record BehaviourProfile(
    DateOnly AsOfDate,
    IReadOnlyList<BehaviourObservation> Observations);

/// <summary>One measure over time — what a trend line reads.</summary>
public sealed record BehaviourHistoryPoint(
    DateOnly ForLocalDate,
    decimal? ValueNumeric,
    string ValueText,
    int Confidence,
    int SpanDays,
    int SupportingEventCount,
    string EngineVersion);

/// <summary>A behaviour subject as configured: what it is and what feeds it.</summary>
public sealed record BehaviourSubject(
    string SubjectKey,
    string DisplayName,

    /// <summary>event or routine. A routine is done only when its required parts are.</summary>
    string SubjectKind,
    string DomainCode,
    bool IsHealthSensitive,

    /// <summary>How many distinct required parts make a day count as done.</summary>
    int TargetPerDay,
    string ObservationText,
    bool IsActive,
    int PartCount,
    int MeasureCount,

    /// <summary>The timeline event types that compose it.</summary>
    IReadOnlyList<string> EventTypes);
