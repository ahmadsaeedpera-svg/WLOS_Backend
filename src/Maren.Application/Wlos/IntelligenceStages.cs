using System.Globalization;
using Maren.Application.Behaviour;
using Maren.Application.Coaching;
using Maren.Application.Growth;
using Maren.Application.Recommend;
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
// Behaviour Intelligence
// ---------------------------------------------------------------------------

/// <summary>Observes how she lives, and publishes it for everything downstream.</summary>
/// <remarks>
/// <para>
/// The only stage that computes behaviour. It resolves and persists the day's
/// observations, then publishes them under
/// <see cref="IntelligenceKeys.Behaviour"/>. Habit, routine, goal,
/// recommendation, coach and prediction all read that key; none of them counts
/// a day, derives a streak or estimates a probability of its own.
/// </para>
/// <para>
/// Resolving here rather than in each consumer is the reason it is a stage at
/// all: six engines each triggering a recomputation would observe the same
/// woman six times in one page load.
/// </para>
/// </remarks>
public sealed class BehaviourResolutionStage(IBehaviourRepository repository)
    : IIntelligenceStage
{
    public string Name => "behaviourResolution";
    public string Version => "1.0";

    public async Task<IntelligenceResult> ExecuteAsync(
        IntelligenceContext context, CancellationToken ct)
    {
        /*  Eight weeks. Long enough for the momentum and rhythm measures to
            reach full confidence, short enough that the read stays a seek on
            the timeline's clustered index. Measures needing more than this
            report lower confidence rather than nothing, which is the honest
            degradation. */
        const int windowDays = 56;

        var observations = await repository.ResolveAsync(
            context.UserId, context.AsOfLocalDate, windowDays, ct);

        context.Publish(IntelligenceKeys.Behaviour, observations);

        if (observations.Count == 0)
            return IntelligenceResult.NoResult(
                "Nothing logged yet, so there is no behaviour to observe.");

        /*  The mean of what the observations computed from her span. Not a
            figure invented here: a woman who joined yesterday produces low
            confidence because that is what one day supports. */
        var confidence = Math.Round(
            (decimal)observations.Sum(o => o.Confidence) / observations.Count / 100m, 2);

        var subjects = observations.Select(o => o.SubjectKey).Distinct().ToList();

        var factors = new List<ConfidenceFactor>
        {
            new("span",
                confidence,
                $"Mean coverage of the history each measure needs, across "
                + $"{observations.Count} observation(s)."),
            new("subjects",
                subjects.Count == 0 ? 0m : 1.00m,
                $"{subjects.Count} subject(s) had enough logged to observe."),
        };

        var warnings = new List<string>();

        /*  Said plainly rather than hidden. A thin span is not a fault, but a
            consumer treating a two-day observation as settled would be. */
        var thin = observations.Count(o => o.Confidence < 50);
        if (thin > 0)
            warnings.Add($"{thin} observation(s) rest on less history than they need.");

        return IntelligenceResult.Contributed(
            confidence: confidence,
            factors: factors,
            evidence: observations.SelectMany(o => o.Evidence).Distinct().ToList(),
            warnings: warnings,
            diagnostics: new Dictionary<string, string>
            {
                ["observations"] = observations.Count.ToString(CultureInfo.InvariantCulture),
                ["subjects"] = subjects.Count.ToString(CultureInfo.InvariantCulture),
                ["engineVersion"] = observations[0].EngineVersion,
            });
    }
}

/// <summary>Her habits — the habit-family view of what behaviour observed.</summary>
/// <remarks>
/// Orchestration only, and deliberately so. It selects from what
/// <c>behaviourResolution</c> published and computes nothing. If this stage
/// ever counts a day or derives a streak it has become a second source of
/// truth, and the second source is always the one that is wrong.
/// </remarks>
public sealed class HabitResolutionStage : IIntelligenceStage
{
    public string Name => "habitResolution";
    public string Version => "1.0";

    public Task<IntelligenceResult> ExecuteAsync(
        IntelligenceContext context, CancellationToken ct)
    {
        /*  Degrades rather than throwing when behaviour is absent. A stage
            whose input never arrived must not take the pipeline down with it. */
        if (!context.TryGet<IReadOnlyList<BehaviourObservation>>(
                IntelligenceKeys.Behaviour, out var observations))
            return Task.FromResult(IntelligenceResult.NoResult(
                "Behaviour was not observed for this request."));

        var habits = observations!.Where(o => o.Family == "habit").ToList();

        if (habits.Count == 0)
            return Task.FromResult(IntelligenceResult.NoResult(
                "Nothing logged often enough to read as a habit yet."));

        var confidence = Math.Round(
            (decimal)habits.Sum(o => o.Confidence) / habits.Count / 100m, 2);

        /*  Streaks she is actually on, taken from the observation rather than
            recounted. The number and the reason travel together, so anything
            that shows it can also explain it. */
        var live = habits
            .Where(o => o.MeasureCode == "streak_current" && o.ValueNumeric > 0)
            .ToList();

        return Task.FromResult(IntelligenceResult.Contributed(
            confidence: confidence,
            factors:
            [
                new ConfidenceFactor("observed", confidence,
                    "Inherited from Behaviour Intelligence; nothing recomputed here."),
            ],
            evidence: habits.SelectMany(o => o.Evidence).Distinct().ToList(),
            diagnostics: new Dictionary<string, string>
            {
                ["habitMeasures"] = habits.Count.ToString(CultureInfo.InvariantCulture),
                ["liveStreaks"] = live.Count.ToString(CultureInfo.InvariantCulture),
                ["subjects"] = habits.Select(o => o.SubjectKey).Distinct().Count()
                    .ToString(CultureInfo.InvariantCulture),
            }));
    }
}

// ---------------------------------------------------------------------------
// Stages whose engines do not exist yet
// ---------------------------------------------------------------------------

/// <summary>Where she stands on what she is working towards.</summary>
/// <remarks>
/// <para>
/// Orchestration over Behaviour, like <c>habitResolution</c>. The engine
/// resolves progress from <c>Growth.fn_ResolveGoals</c>, which reads Behaviour
/// through its published interface; nothing here counts a day, derives a streak
/// or decides whether a goal is met.
/// </para>
/// <para>
/// Publishes under <see cref="IntelligenceKeys.Goals"/> because recommendation
/// assembly reads it. A recommendation that ignores what she is actually trying
/// to do is advice about somebody else.
/// </para>
/// </remarks>
public sealed class GoalResolutionStage(IGoalRepository repository) : IIntelligenceStage
{
    public string Name => "goalResolution";
    public string Version => "1.0";

    public async Task<IntelligenceResult> ExecuteAsync(
        IntelligenceContext context, CancellationToken ct)
    {
        var goals = await repository.ResolveAsync(
            context.UserId, context.AsOfLocalDate, ct);

        context.Publish(IntelligenceKeys.Goals, goals);

        if (goals.Count == 0)
            return IntelligenceResult.NoResult("She has not taken on any goals yet.");

        /*  Inherited from the observations behind each goal, never invented
            here. A goal resting on nine days of history is not a confident 40%. */
        var confidence = Math.Round(
            (decimal)goals.Sum(g => g.Confidence) / goals.Count / 100m, 2);

        var achieved = goals.Count(g => g.IsComplete);
        var measurable = goals.Count(g => g.ProgressPercent.HasValue);

        var warnings = new List<string>();

        /*  Said plainly. A goal the platform cannot yet measure is not a failure,
            but a consumer treating its silence as zero progress would be. */
        var unmeasured = goals.Count - measurable;
        if (unmeasured > 0)
            warnings.Add($"{unmeasured} goal(s) have too little logged to measure yet.");

        return IntelligenceResult.Contributed(
            confidence: confidence,
            factors:
            [
                new ConfidenceFactor("observed", confidence,
                    "Inherited from Behaviour Intelligence; nothing recomputed here."),
                new ConfidenceFactor("measurable",
                    goals.Count == 0 ? 0m : Math.Round((decimal)measurable / goals.Count, 2),
                    $"{measurable} of {goals.Count} goal(s) have enough behind them to measure."),
            ],
            evidence: goals.SelectMany(g => g.Evidence).Distinct().ToList(),
            warnings: warnings,
            diagnostics: new Dictionary<string, string>
            {
                ["goals"] = goals.Count.ToString(CultureInfo.InvariantCulture),
                ["met"] = achieved.ToString(CultureInfo.InvariantCulture),
                ["engineVersion"] = goals[0].EngineVersion,
            });
    }
}

/// <summary>Which routines belong to her day, and where she is up to.</summary>
/// <remarks>
/// <para>
/// Orchestration, and thinner than the goal stage. A routine is several
/// behaviours done together, which Behaviour already models; this stage adds
/// only when in the day each belongs and which are hers.
/// </para>
/// <para>
/// Completion is derived from logged events every time it is asked for. There
/// is no stored percentage anywhere in the routine layer, so this stage cannot
/// disagree with the streak Behaviour computed from the same events.
/// </para>
/// </remarks>
public sealed class RoutinePlanResolutionStage(IRoutineRepository repository)
    : IIntelligenceStage
{
    public string Name => "routinePlanResolution";
    public string Version => "1.0";

    public async Task<IntelligenceResult> ExecuteAsync(
        IntelligenceContext context, CancellationToken ct)
    {
        var routines = await repository.TodayAsync(
            context.UserId, context.AsOfLocalDate, null, ct);

        context.Publish(IntelligenceKeys.Routines, routines);

        if (routines.Count == 0)
            return IntelligenceResult.NoResult("No routine applies to her today.");

        var done = routines.Count(r => r.IsDoneToday);
        var started = routines.Count(r => r.IsStarted);

        /*  Inherited from the consistency observations behind them, never
            invented here. A routine resting on nine days is not confident. */
        var confidence = Math.Round(
            (decimal)routines.Sum(r => r.Confidence) / routines.Count / 100m, 2);

        var warnings = new List<string>();

        /*  A routine whose target exceeds its required parts can never be
            completed, and on her screen looks exactly like one she keeps
            missing. Reported rather than hidden, because it is a configuration
            fault and she would otherwise carry the blame for it. */
        var impossible = routines.Count(r => r.TargetPerDay > r.RequiredCount);
        if (impossible > 0)
            warnings.Add($"{impossible} routine(s) ask for more steps than they have.");

        return IntelligenceResult.Contributed(
            confidence: confidence,
            factors:
            [
                new ConfidenceFactor("observed", confidence,
                    "Inherited from Behaviour Intelligence; nothing recomputed here."),
            ],
            evidence: routines.SelectMany(r => r.Steps.Select(s => s.EventTypeCode))
                              .Distinct().ToList(),
            warnings: warnings,
            diagnostics: new Dictionary<string, string>
            {
                ["routines"] = routines.Count.ToString(CultureInfo.InvariantCulture),
                ["doneToday"] = done.ToString(CultureInfo.InvariantCulture),
                ["started"] = started.ToString(CultureInfo.InvariantCulture),
            });
    }
}

/// <summary>What the platform is suggesting to her, and why each thing.</summary>
/// <remarks>
/// <para>
/// Assembly only. Every suggestion comes from <c>Recommend.fn_AssembleFrom</c>,
/// which reads an evidence set gathered from published interfaces. This stage
/// decides nothing, computes no behavioural number and applies no threshold.
/// </para>
/// <para>
/// Registered after behaviour, goals and routines, because a recommendation is
/// the sentence you get when several of those line up. It publishes under
/// <see cref="IntelligenceKeys.Recommendations"/> so the coach can explain them
/// without reassembling them.
/// </para>
/// </remarks>
public sealed class RecommendationResolutionStage(IRecommendationRepository repository)
    : IIntelligenceStage
{
    public string Name => "recommendationResolution";
    public string Version => "1.0";

    public async Task<IntelligenceResult> ExecuteAsync(
        IntelligenceContext context, CancellationToken ct)
    {
        /*  The targeting context the earlier stages derived, so who a
            recommendation is for stays with Rules rather than being decided
            here. Absent means universal, matching every other scope. */
        context.TryGet<string>(IntelligenceKeys.TargetingContext, out var targeting);

        var assembled = await repository.ResolveAsync(
            context.UserId, context.AsOfLocalDate, targeting, ct);

        context.Publish(IntelligenceKeys.Recommendations, assembled);

        if (assembled.Count == 0)
            return IntelligenceResult.NoResult(
                "Nothing she has logged supports a suggestion today.");

        /*  Inherited from the observations that matched. A suggestion resting
            on thin history reports thin confidence, and the pipeline says so
            rather than averaging it away. */
        var confidence = Math.Round(
            (decimal)assembled.Sum(a => a.Confidence) / assembled.Count / 100m, 2);

        var warnings = new List<string>();

        /*  Said plainly. A low-effort suggestion is the one a tired woman can
            act on, and a day with none of those is worth flagging to whatever
            chooses what to show her. */
        if (!assembled.Any(a => a.ExpectedEffort <= 2))
            warnings.Add("Every suggestion today asks for real effort.");

        return IntelligenceResult.Contributed(
            confidence: confidence,
            factors:
            [
                new ConfidenceFactor("assembled", confidence,
                    "Inherited from the observations that matched; nothing inferred."),
            ],
            evidence: assembled.SelectMany(a => a.Evidence).Distinct().ToList(),
            warnings: warnings,
            diagnostics: new Dictionary<string, string>
            {
                ["recommendations"] = assembled.Count.ToString(CultureInfo.InvariantCulture),
                ["engines"] = string.Join(",",
                    assembled.SelectMany(a => a.Engines).Distinct().Order()),
                ["topPriority"] = assembled.Max(a => a.Priority)
                    .ToString(CultureInfo.InvariantCulture),
            });
    }
}

/// <summary>How the platform says what it is already suggesting.</summary>
/// <remarks>
/// Explanation only. It reads the recommendations the previous stage published
/// and fills in a tone pattern; it assembles nothing, observes nothing and adds
/// no evidence. A coach that reassembled would be a second opinion about the
/// same woman, and the two could disagree the moment a threshold changed
/// between them.
/// </remarks>
public sealed class CoachResolutionStage(ICoachRepository repository)
    : IIntelligenceStage
{
    public string Name => "coachResolution";
    public string Version => "1.0";

    public async Task<IntelligenceResult> ExecuteAsync(
        IntelligenceContext context, CancellationToken ct)
    {
        /*  Degrades rather than throwing when there is nothing to explain. A
            stage whose input never arrived must not take the pipeline down. */
        if (!context.TryGet<IReadOnlyList<Recommendation>>(
                IntelligenceKeys.Recommendations, out var recommendations)
            || recommendations!.Count == 0)
        {
            return IntelligenceResult.NoResult(
                "Nothing was suggested today, so there is nothing to explain.");
        }

        var messages = await repository.ResolveAsync(
            context.UserId, context.AsOfLocalDate, ct);

        context.Publish(IntelligenceKeys.CoachMessages, messages);

        if (messages.Count == 0)
            return IntelligenceResult.NoResult(
                "The suggestions had lapsed before they could be explained.");

        /*  Carried through from the recommendations. The coach observes
            nothing, so it has no confidence of its own to report. */
        var confidence = Math.Round(
            (decimal)messages.Sum(m => m.Confidence) / messages.Count / 100m, 2);

        var warnings = new List<string>();

        /*  A voice chosen by the fallback is not wrong, but it means nothing
            about her day shaped how she is being spoken to. Worth saying
            rather than presenting it as a considered choice. */
        if (messages.All(m => !m.ToneFromRule))
            warnings.Add("Nothing about today shaped the voice; the default was used.");

        return IntelligenceResult.Contributed(
            confidence: confidence,
            factors:
            [
                new ConfidenceFactor("explained", confidence,
                    "Carried through from the recommendations; the coach observes nothing."),
            ],
            evidence: messages.SelectMany(m => m.Evidence).Distinct().ToList(),
            warnings: warnings,
            diagnostics: new Dictionary<string, string>
            {
                ["messages"] = messages.Count.ToString(CultureInfo.InvariantCulture),
                ["tones"] = string.Join(",",
                    messages.Select(m => m.ToneCode).Distinct().Order()),
            });
    }
}

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
