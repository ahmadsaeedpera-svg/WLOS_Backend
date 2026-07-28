namespace Maren.Contracts;

// ---------------------------------------------------------------------------
// Women's Life Operating System — the unified output
//
// Every surface asks the same question and receives the same shape. A
// dashboard, a notification scheduler, a widget and eventually an AI companion
// are all consumers of this; none of them decides anything.
//
// One envelope for every kind of decision, deliberately. A notification that
// carried different fields from a dashboard card would let a client special
// case one of them, and a client that special cases is a client that has
// started making decisions.
// ---------------------------------------------------------------------------

/// <summary>One thing the platform has decided, whatever kind it is.</summary>
/// <remarks>
/// Every decision explains itself. Reason is written for the woman, Evidence
/// names the signals behind it for a client or model that wants the reasoning
/// rather than the sentence, and Source says which engine produced it.
/// <para>
/// An adaptive platform nobody can interrogate is one nobody can debug,
/// configure or defend — and the AI layer that will eventually phrase these
/// must be reading a decision rather than making one.
/// </para>
/// </remarks>
public sealed record LifeDecision(
    /// <summary>What kind of thing this is: <c>dashboardCard</c> today.</summary>
    string Kind,

    /// <summary>Stable identifier within its kind, for a client to key on.</summary>
    string Code,

    string Title,

    /// <summary>Which part of her life this belongs to.</summary>
    string DomainCode,

    /// <summary>Higher comes first. Resolved, never raw.</summary>
    int Priority,

    /// <summary>Why she is seeing this, in her words.</summary>
    string Reason,

    /// <summary>The signals behind it. Empty when it is simply routine.</summary>
    IReadOnlyList<string> Evidence,

    /// <summary>0 to 1. As weak as the weakest reason behind it.</summary>
    decimal Confidence,

    /// <summary>Which engine decided this.</summary>
    string Source,

    /// <summary>When a client should stop trusting it. Null means no expiry.</summary>
    DateTime? ExpiresUtc,

    /// <summary>How long a client may hold it before asking again.</summary>
    int RefreshSeconds,

    /// <summary>
    /// Codes this decision leans on. Lets a client drop a card whose
    /// prerequisite disappeared rather than showing something orphaned.
    /// </summary>
    IReadOnlyList<string> DependsOn,

    /// <summary>
    /// Whether this reflects self-reported health information. Such decisions
    /// may be shown back to her and must never be presented as a finding.
    /// </summary>
    bool IsHealthSensitive);

/// <summary>What the platform knew about her when it decided.</summary>
/// <remarks>
/// Returned rather than kept private so a decision can be reproduced. Without
/// it, "why did she see this yesterday" is unanswerable.
/// </remarks>
public sealed record LifeContext(
    string? LifeStageCode,
    IReadOnlyList<string> RoleModes,
    string? CountryIso,
    string? LanguageCode,
    string? TimeZoneId,
    DateOnly AsOfLocalDate,
    IReadOnlyList<string> RaisedSignals);

/// <summary>What one stage of the pipeline did.</summary>
/// <remarks>
/// The engine trace. Every stage reports itself, including the ones that are
/// not built yet — a stage that returned nothing because it does not exist is
/// a different fact from one that ran and found nothing, and collapsing them
/// would make the platform look complete while being empty.
/// </remarks>
public sealed record LifeOsStageTrace(
    string Stage,

    /// <summary>
    /// <c>contributed</c> — ran and produced decisions.
    /// <c>noResult</c> — ran and had nothing to say.
    /// <c>unavailable</c> — the engine behind it does not exist yet.
    /// <c>skipped</c> — deliberately not run for this request.
    /// </summary>
    string Status,

    string? Note,
    int DecisionCount,
    long ElapsedMs);

/// <summary>Everything the platform has decided for her, right now.</summary>
public sealed record LifeOsResponse(
    Guid UserId,
    DateTime ResolvedUtc,
    LifeContext Context,
    IReadOnlyList<LifeDecision> Decisions,

    /// <summary>
    /// How the answer was reached. Returned to operators through the portal's
    /// decision inspector; a client may ignore it.
    /// </summary>
    IReadOnlyList<LifeOsStageTrace> Trace);
