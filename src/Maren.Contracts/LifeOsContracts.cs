namespace Maren.Contracts;

// ---------------------------------------------------------------------------
// Women's Life OS — the intelligence pipeline's public shape
//
// Every surface asks the same question and receives the same answer. A
// dashboard, a notification scheduler, a widget and eventually an AI companion
// are all consumers; none of them decides anything.
//
// One envelope for every kind of decision, deliberately. A notification that
// carried different fields from a dashboard card would let a client special
// case one of them, and a client that special cases has started deciding.
// ---------------------------------------------------------------------------

/// <summary>One thing the platform has decided, whatever kind it is.</summary>
public sealed record LifeDecision(
    string Kind,
    string Code,
    string Title,
    string DomainCode,
    int Priority,
    string Reason,
    IReadOnlyList<string> Evidence,
    decimal Confidence,
    string Source,
    DateTime? ExpiresUtc,
    int RefreshSeconds,
    IReadOnlyList<string> DependsOn,
    bool IsHealthSensitive);

/// <summary>One derived understanding of how she is living.</summary>
/// <remarks>
/// Distinct from a decision. A decision is something to show her; this is
/// something the platform understands about her, which decisions are derived
/// from. Kept separate so a consumer can render her state without inferring it
/// back out of a list of cards.
/// </remarks>
public sealed record LifeStateReading(
    string DimensionCode,
    string DisplayName,

    /// <summary><c>unknown</c> when there was not enough logged to tell.</summary>
    string ValueCode,

    string ValueText,

    /// <summary>0–100 for a score dimension; null for a categorical one.</summary>
    int? Score,

    /// <summary>0–100, derived from coverage. Never asserted.</summary>
    int Confidence,

    string Reason,
    IReadOnlyList<string> Evidence,

    /// <summary><c>new</c> until there is an earlier reading to compare with.</summary>
    string Trend,

    int? PreviousScore);

/// <summary>What the platform knew about her when it decided.</summary>
public sealed record LifeContext(
    string? LifeStageCode,
    IReadOnlyList<string> RoleModes,
    string? CountryIso,
    string? LanguageCode,
    string? TimeZoneId,
    DateOnly AsOfLocalDate,
    IReadOnlyList<string> RaisedSignals);

/// <summary>One contribution to a confidence figure.</summary>
/// <remarks>
/// Confidence is never a bare number. Every stage that reports one has to say
/// what produced it, so an operator can see whether 82% means "most inputs
/// present" or "one stale input and a guess".
/// </remarks>
public sealed record ConfidenceFactor(
    string Name,
    decimal Value,
    string Explanation);

/// <summary>Everything one pipeline stage did.</summary>
/// <remarks>
/// The full record, not a summary. The decision inspector renders exactly
/// this, and anything omitted here is something an operator cannot see.
/// </remarks>
public sealed record IntelligenceStageReport(
    string Stage,

    /// <summary>
    /// <c>contributed</c> · <c>noResult</c> · <c>unavailable</c> ·
    /// <c>failed</c> · <c>skipped</c>
    /// </summary>
    string Status,

    /// <summary>Why, when the status is not <c>contributed</c>.</summary>
    string? Reason,

    /// <summary>0–1, or null when the stage produces nothing to be confident about.</summary>
    decimal? Confidence,

    /// <summary>How that confidence was arrived at.</summary>
    IReadOnlyList<ConfidenceFactor> ConfidenceFactors,

    /// <summary>Context keys this stage read.</summary>
    IReadOnlyList<string> InputsUsed,

    /// <summary>Context keys this stage published.</summary>
    IReadOnlyList<string> OutputsProduced,

    /// <summary>What it based its answer on — signals, event types, rows.</summary>
    IReadOnlyList<string> Evidence,

    /// <summary>Things that did not stop it but are worth knowing.</summary>
    IReadOnlyList<string> Warnings,

    /// <summary>Free-form detail for an operator. Never shown to a woman.</summary>
    IReadOnlyDictionary<string, string> Diagnostics,

    /// <summary>Bumped when a stage's behaviour changes, so a stored trace stays readable.</summary>
    string Version,

    long ElapsedMs);

/// <summary>Everything the platform has decided for her, right now.</summary>
public sealed record LifeOsResponse(
    Guid UserId,
    DateTime ResolvedUtc,
    LifeContext Context,
    IReadOnlyList<LifeStateReading> State,
    IReadOnlyList<LifeDecision> Decisions,

    /// <summary>How the answer was reached, stage by stage.</summary>
    IReadOnlyList<IntelligenceStageReport> Trace);
