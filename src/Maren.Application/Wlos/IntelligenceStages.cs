using System.Globalization;
using Maren.Contracts;

namespace Maren.Application.Wlos;

// ---------------------------------------------------------------------------
// The stages.
//
// Each reads what it needs from the context and publishes what it produces.
// None of them calls another, and none holds a rule about what a life stage
// means or how a priority is calculated — those live in the engines, and
// ultimately in stored procedures where nothing can bypass them.
// ---------------------------------------------------------------------------

/// <summary>Loads who she is.</summary>
public sealed class ContextResolutionStage(ILifeOsRepository repository) : IIntelligenceStage
{
    public string Name => "contextResolution";
    public string Version => "1.0";

    public async Task<IntelligenceResult> ExecuteAsync(
        IntelligenceContext context, CancellationToken ct)
    {
        var profile = await repository.GetContextAsync(context.UserId, ct);

        if (profile is null)
        {
            return IntelligenceResult.NoResult(
                "No profile row. She can still receive universal decisions.");
        }

        context.Publish(IntelligenceKeys.Profile, profile);

        var warnings = new List<string>();
        if (string.IsNullOrWhiteSpace(profile.LifeStageCode))
            warnings.Add("No life stage set. Stage-targeted decisions will not reach her.");

        return IntelligenceResult.Contributed(
            evidence: [$"lifeStage={profile.LifeStageCode ?? "(none)"}"],
            warnings: warnings,
            diagnostics: new Dictionary<string, string>
            {
                ["country"] = profile.CountryIso ?? "(none)",
                ["roleModes"] = profile.RoleModesCsv,
            });
    }
}

/// <summary>Derives the targeting context every later engine keys on.</summary>
/// <remarks>
/// Built once, here. Two stages composing it separately would be two
/// interpretations of who she is.
/// </remarks>
public sealed class ProfileResolutionStage : IIntelligenceStage
{
    public string Name => "profileResolution";
    public string Version => "1.0";

    public Task<IntelligenceResult> ExecuteAsync(
        IntelligenceContext context, CancellationToken ct)
    {
        if (!context.TryGet<LifeOsContextRow>(IntelligenceKeys.Profile, out var profile))
        {
            context.Publish(IntelligenceKeys.TargetingContext, "[]");
            return Task.FromResult(IntelligenceResult.NoResult(
                "No profile to derive from. Universal decisions only."));
        }

        var parts = new List<string>();

        if (!string.IsNullOrWhiteSpace(profile.LifeStageCode))
            parts.Add(Dimension("life_stage", profile.LifeStageCode));

        foreach (var role in SplitRoles(profile.RoleModesCsv))
            parts.Add(Dimension("role_mode", role));

        if (!string.IsNullOrWhiteSpace(profile.CountryIso))
            parts.Add(Dimension("country", profile.CountryIso));

        if (!string.IsNullOrWhiteSpace(profile.LanguageCode))
            parts.Add(Dimension("language", profile.LanguageCode));

        context.Publish(IntelligenceKeys.TargetingContext,
            "[" + string.Join(",", parts) + "]");

        return Task.FromResult(IntelligenceResult.Contributed(
            evidence: [$"{parts.Count} dimension(s)"],
            diagnostics: new Dictionary<string, string> { ["dimensions"] = parts.Count.ToString(CultureInfo.InvariantCulture) }));
    }

    /*  Values reach here from the database's own enumerations - life stage and
        role mode codes are foreign keys, country and language are reference
        rows - so they cannot carry a quote. Escaped anyway: this composes JSON
        by hand, and the day somebody widens one of those columns is the day
        this would otherwise become an injection into a JSON document. */
    private static string Dimension(string dimension, string value) =>
        $$"""{"dimension":"{{Escape(dimension)}}","value":"{{Escape(value)}}"}""";

    private static string Escape(string value) =>
        value.Replace("\\", "\\\\", StringComparison.Ordinal)
             .Replace("\"", "\\\"", StringComparison.Ordinal);

    internal static IEnumerable<string> SplitRoles(string? csv) =>
        string.IsNullOrWhiteSpace(csv)
            ? []
            : csv.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
}

/// <summary>Asks the knowledge engine what the timeline currently says.</summary>
public sealed class SignalAnalysisStage(ILifeOsRepository repository) : IIntelligenceStage
{
    public string Name => "signalAnalysis";
    public string Version => "1.0";

    public async Task<IntelligenceResult> ExecuteAsync(
        IntelligenceContext context, CancellationToken ct)
    {
        var signals = await repository.GetRaisedSignalsAsync(
            context.UserId, context.AsOfLocalDate, ct);

        context.Publish(IntelligenceKeys.RaisedSignals, signals);

        /*  Nothing raised is a normal, healthy answer. Most days are ordinary,
            and a quiet day is not a failure to report. */
        return signals.Count == 0
            ? IntelligenceResult.NoResult("Nothing raised for this day.")
            : IntelligenceResult.Contributed(evidence: signals);
    }
}

/// <summary>Derives how she is living, from the intelligence core.</summary>
/// <remarks>
/// Computes every dimension once and publishes them. The per-dimension stages
/// below present them; none of them recomputes, so a woman's energy and her
/// balance can never disagree about the same day.
/// </remarks>
public sealed class StateResolutionStage(ILifeOsRepository repository) : IIntelligenceStage
{
    public string Name => "stateResolution";
    public string Version => "1.0";

    public async Task<IntelligenceResult> ExecuteAsync(
        IntelligenceContext context, CancellationToken ct)
    {
        var readings = await repository.ResolveStateAsync(
            context.UserId, context.AsOfLocalDate, ct);

        context.Publish(IntelligenceKeys.StateReadings, readings);

        if (readings.Count == 0)
            return IntelligenceResult.NoResult("No dimensions are configured.");

        var known = readings.Where(r => r.ValueCode != "unknown").ToList();

        /*  Pipeline confidence is the mean of what the dimensions themselves
            computed from coverage. Not a figure invented here: if she logged
            nothing, every dimension reports zero and so does this. */
        var confidence = readings.Count == 0
            ? 0m
            : Math.Round((decimal)readings.Sum(r => r.Confidence) / readings.Count / 100m, 2);

        var factors = new List<ConfidenceFactor>
        {
            new("coverage",
                confidence,
                $"Mean input coverage across {readings.Count} dimension(s)."),
            new("knownDimensions",
                readings.Count == 0 ? 0m : Math.Round((decimal)known.Count / readings.Count, 2),
                $"{known.Count} of {readings.Count} dimension(s) had enough data to report."),
        };

        var warnings = new List<string>();
        if (known.Count == 0)
            warnings.Add("Nothing logged in the window, so every dimension is unknown.");

        return IntelligenceResult.Contributed(
            confidence: confidence,
            factors: factors,
            evidence: known.SelectMany(r => r.Evidence).Distinct().ToList(),
            warnings: warnings,
            diagnostics: new Dictionary<string, string>
            {
                ["dimensions"] = readings.Count.ToString(CultureInfo.InvariantCulture),
                ["known"] = known.Count.ToString(CultureInfo.InvariantCulture),
            });
    }
}

/// <summary>Presents one derived dimension.</summary>
/// <remarks>
/// A thin projection over what <see cref="StateResolutionStage"/> already
/// computed. Each dimension is its own stage so it has its own timing,
/// confidence and trace entry, and can be switched off independently — without
/// any of them recomputing, which would let two stages disagree about the same
/// day.
/// <para>
/// Adding a tenth dimension is a registration, not a code change.
/// </para>
/// </remarks>
public abstract class StateDimensionStage(string dimensionCode) : IIntelligenceStage
{
    public string Name => $"{dimensionCode}Resolution";
    public string Version => "1.0";

    public Task<IntelligenceResult> ExecuteAsync(
        IntelligenceContext context, CancellationToken ct)
    {
        if (!context.TryGet<IReadOnlyList<LifeStateReading>>(
                IntelligenceKeys.StateReadings, out var readings))
        {
            return Task.FromResult(IntelligenceResult.NoResult(
                "State resolution did not run, so there is nothing to present."));
        }

        var reading = readings.FirstOrDefault(r => r.DimensionCode == dimensionCode);

        if (reading is null)
        {
            return Task.FromResult(IntelligenceResult.NoResult(
                $"No dimension '{dimensionCode}' is configured."));
        }

        if (reading.ValueCode == "unknown")
        {
            /*  Emitted anyway. A consumer showing "not enough logged yet" is
                more honest, and more useful, than one showing nothing and
                leaving her to guess whether the platform is broken. */
            context.EmitState(reading);

            return Task.FromResult(IntelligenceResult.NoResult(reading.Reason));
        }

        context.EmitState(reading);

        return Task.FromResult(IntelligenceResult.Contributed(
            confidence: Math.Round(reading.Confidence / 100m, 2),
            factors:
            [
                new ConfidenceFactor("coverage",
                    Math.Round(reading.Confidence / 100m, 2),
                    "Share of this dimension's declared inputs that had data."),
            ],
            evidence: reading.Evidence,
            diagnostics: new Dictionary<string, string>
            {
                ["value"] = reading.ValueCode,
                ["score"] = reading.Score?.ToString(CultureInfo.InvariantCulture) ?? "(none)",
                ["trend"] = reading.Trend,
            }));
    }
}

public sealed class EnergyResolutionStage() : StateDimensionStage("energy");
public sealed class FocusResolutionStage() : StateDimensionStage("focus");
public sealed class ConsistencyResolutionStage() : StateDimensionStage("consistency");
public sealed class WellnessResolutionStage() : StateDimensionStage("wellness");
public sealed class BalanceResolutionStage() : StateDimensionStage("balance");
public sealed class RoutineStateStage() : StateDimensionStage("routine");
public sealed class MomentumResolutionStage() : StateDimensionStage("momentum");
public sealed class LoadResolutionStage() : StateDimensionStage("load");
public sealed class RiskResolutionStage() : StateDimensionStage("risk");

/// <summary>Asks the dashboard engine what she should see.</summary>
public sealed class DashboardResolutionStage(ILifeOsRepository repository) : IIntelligenceStage
{
    public string Name => "dashboardResolution";
    public string Version => "1.1";

    public async Task<IntelligenceResult> ExecuteAsync(
        IntelligenceContext context, CancellationToken ct)
    {
        /*  Degrades rather than fails when profile resolution did not run: an
            empty context still yields the universal cards, which is a better
            answer than none. */
        if (!context.TryGet<string>(IntelligenceKeys.TargetingContext, out var targeting))
            targeting = "[]";

        var cards = await repository.ResolveDashboardAsync(
            context.UserId, targeting, context.AsOfLocalDate, 20, ct);

        var resolvedUtc = DateTime.UtcNow;

        foreach (var card in cards)
        {
            context.Emit(new LifeDecision(
                Kind: "dashboardCard",
                Code: card.CardTypeCode,
                Title: card.DisplayName,
                DomainCode: card.DomainCode,
                Priority: card.Priority,
                Reason: card.Reason,
                Evidence: string.IsNullOrWhiteSpace(card.EvidenceSignals)
                    ? []
                    : card.EvidenceSignals.Split(',', StringSplitOptions.RemoveEmptyEntries),
                Confidence: card.Confidence,
                Source: $"dashboardEngine:{card.Source}",
                ExpiresUtc: card.LifetimeSeconds is { } seconds
                    ? resolvedUtc.AddSeconds(seconds)
                    : null,
                RefreshSeconds: card.RefreshSeconds,
                DependsOn: [],
                IsHealthSensitive: card.IsHealthSensitive));
        }

        if (cards.Count == 0)
            return IntelligenceResult.NoResult("No card was eligible for this context.");

        var adapted = cards.Count(c => c.Source != "baseline");

        return IntelligenceResult.Contributed(
            confidence: 1.00m,
            factors:
            [
                new ConfidenceFactor("deterministic", 1.00m,
                    "Eligibility and priority are rule-based, not inferred."),
            ],
            evidence: cards.SelectMany(c =>
                    c.EvidenceSignals.Split(',', StringSplitOptions.RemoveEmptyEntries))
                .Distinct().ToList(),
            diagnostics: new Dictionary<string, string>
            {
                ["cards"] = cards.Count.ToString(CultureInfo.InvariantCulture),
                ["adaptedBySignal"] = adapted.ToString(CultureInfo.InvariantCulture),
            });
    }
}

// ---------------------------------------------------------------------------
// Stages whose engines do not exist yet
// ---------------------------------------------------------------------------

public sealed class HabitResolutionStage()
    : UnbuiltStage("habitResolution", "No habit engine yet.");

public sealed class GoalResolutionStage()
    : UnbuiltStage("goalResolution", "No goal engine yet.");

public sealed class RoutinePlanResolutionStage()
    : UnbuiltStage("routinePlanResolution",
        "No routine engine yet. The routine state dimension is derived, not planned.");

public sealed class RecommendationResolutionStage()
    : UnbuiltStage("recommendationResolution",
        "No recommendation engine yet. It will consume signals and the knowledge graph.");

public sealed class CoachResolutionStage()
    : UnbuiltStage("coachResolution", "No coaching engine yet.");

public sealed class NotificationResolutionStage()
    : UnbuiltStage("notificationResolution",
        "Notification tables exist with no procedures or delivery path.");

public sealed class PredictionResolutionStage()
    : UnbuiltStage("predictionResolution",
        "No prediction engine. Nothing here may infer a health outcome.");

public sealed class ConversationContextStage()
    : UnbuiltStage("conversationContextResolution", "No conversation engine yet.");

public sealed class AiContextResolutionStage()
    : UnbuiltStage("aiContextResolution",
        "No model integration. Guardrails ship before generation — see docs/ai/AI_PIPELINE.md.");
