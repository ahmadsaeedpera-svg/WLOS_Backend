namespace Maren.Contracts;

// ---------------------------------------------------------------------------
// Decision inspector
//
// An operator asking "would my configuration do what I intended". Everything
// here describes a hypothetical woman: no user id, no timeline, no account.
// See 47_Procs_Inspector.sql for why that is a privacy decision rather than a
// convenience.
// ---------------------------------------------------------------------------

/// <summary>The hypothetical woman to resolve against.</summary>
public sealed record SimulateRequest(
    string? LifeStageCode,
    IReadOnlyList<string>? RoleModeCodes,
    string? CountryIso,
    string? LanguageCode,

    /// <summary>Signals to pretend are raised. Unknown names are ignored.</summary>
    IReadOnlyList<string>? Signals);

/// <summary>One card the engine would produce, or suppress.</summary>
public sealed record SimulatedCard(
    string CardTypeCode,
    string DisplayName,
    string DomainCode,
    int Priority,
    int BasePriority,
    decimal Confidence,
    bool IsHealthSensitive,

    /// <summary>
    /// True when the card was eligible and then driven to zero or below.
    /// The live engine drops these silently; the inspector shows them, because
    /// "why is my card missing" is the question operators arrive with.
    /// </summary>
    bool IsSuppressed,

    string Reason,
    IReadOnlyList<string> EvidenceSignals,
    string Source);

/// <summary>What the engines would do for that woman.</summary>
public sealed record SimulateResponse(
    /// <summary>The targeting context the pipeline derived, echoed back so an
    /// operator can see what was actually asked rather than what they typed.</summary>
    string ContextJson,

    IReadOnlyList<string> AppliedSignals,
    IReadOnlyList<SimulatedCard> Cards);

/// <summary>One eligibility rule and whether this context satisfies it.</summary>
public sealed record InspectedRule(
    Guid RuleId,
    string DimensionCode,
    string DimensionName,
    string Operator,
    string ValuesJson,
    string RuleNote,

    /// <summary>Returned for failing rules too — a list of only what matched
    /// explains a card's presence and never its absence.</summary>
    bool ContextPasses);

/// <summary>One signal that could move a card's priority.</summary>
public sealed record InspectedAdjustment(
    string SignalCode,
    string SignalName,
    string AdjustmentKind,
    int Amount,
    string ReasonText,
    decimal Confidence,
    bool IsActive);

/// <summary>Everything governing one card.</summary>
public sealed record ExplainCardResponse(
    string CardTypeCode,
    string DisplayName,
    string DomainCode,
    int BasePriority,
    int RefreshSeconds,
    int? LifetimeSeconds,
    bool IsDismissible,
    bool IsHealthSensitive,
    bool IsActive,
    IReadOnlyList<InspectedRule> Rules,
    IReadOnlyList<InspectedAdjustment> Adjustments);

/// <summary>A signal an operator can pretend is raised.</summary>
/// <remarks>
/// Server-driven, like the life stages: a signal added by an editor appears in
/// the inspector without a portal release. Only signals that actually move a
/// card are offered — one with no adjustment changes nothing, and offering it
/// would invite an operator to toggle it and conclude the engine is broken.
/// </remarks>
public sealed record InspectableSignal(
    string SignalCode,
    string DisplayName,
    string DomainCode,
    string ObservationText,
    bool IsHealthSensitive,
    int AffectsCardCount);
