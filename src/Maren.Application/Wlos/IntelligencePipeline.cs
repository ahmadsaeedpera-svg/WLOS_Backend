using System.Diagnostics;
using Maren.Contracts;
using Maren.Shared;
using MediatR;

namespace Maren.Application.Wlos;

// ---------------------------------------------------------------------------
// The intelligence pipeline.
//
// One interface, one context, one result. Every understanding the platform has
// of a woman's life is produced here; nothing computes independently.
//
// The rule this design exists to satisfy: adding a stage must require zero
// modification to any existing stage or to the shared context. Registration
// only. The previous shape failed that — the working set had typed fields, so
// a stage needing new shared data meant editing a class every other stage
// depends on. That is fine at eight stages and untenable at eighty.
// ---------------------------------------------------------------------------

/// <summary>Keys stages publish and consume. A new stage adds its own.</summary>
/// <remarks>
/// Constants rather than an enum: a stage in a future assembly can declare a
/// key without this file knowing about it, which is the point.
/// </remarks>
public static class IntelligenceKeys
{
    public const string Profile = "profile";
    public const string TargetingContext = "targetingContext";
    public const string RaisedSignals = "raisedSignals";
    public const string StateReadings = "stateReadings";

    /// <summary>
    /// Every behavioural observation about her: habits, rhythms, trends,
    /// preferences and probabilities.
    /// </summary>
    /// <remarks>
    /// Published once, by <c>behaviourResolution</c>, and read by every engine
    /// that has anything to say about how she lives. The habit, routine, goal,
    /// recommendation, coach and prediction stages are orchestration over this
    /// key — none of them counts a day or derives a streak. Six stages each
    /// deciding "did she do this on that day" is six chances to decide it
    /// differently, and the failure mode is a woman reading two screens that
    /// disagree about her own week.
    /// </remarks>
    public const string Behaviour = "behaviour";

    /// <summary>Where she stands on what she is working towards.</summary>
    /// <remarks>
    /// Published by <c>goalResolution</c>, read by recommendation assembly. A
    /// recommendation that ignores what she is actually trying to do is advice
    /// about somebody else.
    /// </remarks>
    public const string Goals = "goals";
}

/// <summary>What a stage may read, publish and emit.</summary>
/// <remarks>
/// Reads and writes are recorded against whichever stage is running, so the
/// trace reports what a stage <em>actually</em> used rather than what it claims
/// to have used. Self-reported inputs drift from reality the first time
/// somebody edits a query and forgets the declaration.
/// </remarks>
public sealed class IntelligenceContext
{
    public required Guid UserId { get; init; }
    public required DateOnly AsOfLocalDate { get; init; }

    private readonly Dictionary<string, object> _values = [];
    private readonly List<LifeDecision> _decisions = [];
    private readonly List<LifeStateReading> _state = [];

    private string _currentStage = "(none)";
    private readonly Dictionary<string, HashSet<string>> _reads = [];
    private readonly Dictionary<string, HashSet<string>> _writes = [];

    /// <summary>Called by the orchestrator before each stage runs.</summary>
    internal void BeginStage(string stageName)
    {
        _currentStage = stageName;
        _reads[stageName] = [];
        _writes[stageName] = [];
    }

    internal IReadOnlyList<string> ReadsFor(string stage) =>
        _reads.TryGetValue(stage, out var set) ? [.. set.Order()] : [];

    internal IReadOnlyList<string> WritesFor(string stage) =>
        _writes.TryGetValue(stage, out var set) ? [.. set.Order()] : [];

    /// <summary>Makes a value available to later stages.</summary>
    public void Publish<T>(string key, T value) where T : notnull
    {
        _values[key] = value;
        _writes[_currentStage].Add(key);
    }

    /// <summary>Reads what an earlier stage published, if it did.</summary>
    /// <remarks>
    /// Returns false rather than throwing when a key is absent. A stage whose
    /// input never arrived — because the stage before it was unavailable or
    /// failed — must degrade, not take the pipeline down with it.
    /// </remarks>
    public bool TryGet<T>(string key, out T value)
    {
        _reads[_currentStage].Add(key);

        if (_values.TryGetValue(key, out var stored) && stored is T typed)
        {
            value = typed;
            return true;
        }

        value = default!;
        return false;
    }

    /// <summary>Adds something to show her.</summary>
    public void Emit(LifeDecision decision) => _decisions.Add(decision);

    /// <summary>Adds something the platform understands about her.</summary>
    public void EmitState(LifeStateReading reading) => _state.Add(reading);

    public IReadOnlyList<LifeDecision> Decisions => _decisions;
    public IReadOnlyList<LifeStateReading> State => _state;
}

/// <summary>What a stage reports about its own run.</summary>
public sealed record IntelligenceResult(
    string Status,
    string? Reason = null,
    decimal? Confidence = null,
    IReadOnlyList<ConfidenceFactor>? ConfidenceFactors = null,
    IReadOnlyList<string>? Evidence = null,
    IReadOnlyList<string>? Warnings = null,
    IReadOnlyDictionary<string, string>? Diagnostics = null)
{
    public static IntelligenceResult Contributed(
        decimal? confidence = null,
        IReadOnlyList<ConfidenceFactor>? factors = null,
        IReadOnlyList<string>? evidence = null,
        IReadOnlyList<string>? warnings = null,
        IReadOnlyDictionary<string, string>? diagnostics = null) =>
        new("contributed", null, confidence, factors, evidence, warnings, diagnostics);

    /// <summary>Ran, and had nothing to say. Different from not existing.</summary>
    public static IntelligenceResult NoResult(string reason) => new("noResult", reason);

    /// <summary>The engine behind this stage does not exist yet.</summary>
    public static IntelligenceResult Unavailable(string reason) => new("unavailable", reason);
}

/// <summary>One step of the intelligence pipeline.</summary>
/// <remarks>
/// Stages never call each other. They read what earlier stages published and
/// publish their own, which is what keeps them independently removable — a
/// stage that called another would make the second one's absence a crash
/// rather than a degraded answer.
/// </remarks>
public interface IIntelligenceStage
{
    string Name { get; }

    /// <summary>Bumped when behaviour changes, so a stored trace stays readable.</summary>
    string Version { get; }

    Task<IntelligenceResult> ExecuteAsync(IntelligenceContext context, CancellationToken ct);
}

/// <summary>A stage whose engine has not been built.</summary>
/// <remarks>
/// Registered deliberately rather than omitted. "Ran and found nothing" and
/// "was never built" are different facts, and a pipeline that showed only the
/// stages it had would look complete while being a fraction of itself.
/// </remarks>
public abstract class UnbuiltStage(string name, string reason) : IIntelligenceStage
{
    public string Name => name;
    public string Version => "0.0";

    public Task<IntelligenceResult> ExecuteAsync(
        IntelligenceContext context, CancellationToken ct)
        => Task.FromResult(IntelligenceResult.Unavailable(reason));
}
