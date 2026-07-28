using System.Diagnostics;
using Maren.Contracts;
using Maren.Shared;
using MediatR;

namespace Maren.Application.Wlos;

// ---------------------------------------------------------------------------
// Women's Life Operating System — orchestration
//
// This layer owns coordination and nothing else. It holds no rule about what a
// life stage means, when a card is eligible or how a priority is calculated;
// those live in the engines it calls, and ultimately in stored procedures where
// nothing can bypass them.
//
// The engines were not rewritten to fit this. They are wrapped.
// ---------------------------------------------------------------------------

/// <summary>Data the orchestration layer needs, wrapping existing engines.</summary>
public interface ILifeOsRepository
{
    /// <summary>Her stage, roles and locale — the inputs everything else keys on.</summary>
    Task<LifeOsContextRow?> GetContextAsync(Guid userId, CancellationToken ct);

    /// <summary>What the timeline currently says about her.</summary>
    Task<IReadOnlyList<string>> GetRaisedSignalsAsync(
        Guid userId, DateOnly asOf, CancellationToken ct);

    /// <summary>The dashboard engine's answer, already prioritised and explained.</summary>
    Task<IReadOnlyList<DashboardCardRow>> ResolveDashboardAsync(
        Guid userId, string contextJson, DateOnly asOf, int take, CancellationToken ct);
}

/// <summary>Her context as the database returns it.</summary>
public sealed record LifeOsContextRow(
    string? LifeStageCode,
    string? CountryIso,
    string? LanguageCode,
    string? TimeZoneId,
    string RoleModesCsv);

/// <summary>One card as the dashboard engine returns it.</summary>
public sealed record DashboardCardRow(
    string CardTypeCode,
    string DisplayName,
    string DomainCode,
    int Priority,
    decimal Confidence,
    int RefreshSeconds,
    int? LifetimeSeconds,
    bool IsHealthSensitive,
    string Reason,
    string EvidenceSignals,
    string Source);

// ---------------------------------------------------------------------------
// Stages
// ---------------------------------------------------------------------------

/// <summary>What a stage receives and adds to.</summary>
public sealed class LifeOsWorkingSet
{
    public required Guid UserId { get; init; }
    public required DateOnly AsOfLocalDate { get; init; }

    public LifeOsContextRow? Context { get; set; }
    public List<string> RaisedSignals { get; } = [];
    public List<LifeDecision> Decisions { get; } = [];

    /// <summary>
    /// The targeting context, built once by context resolution and reused.
    /// Rebuilt per stage it would be a second interpretation of who she is.
    /// </summary>
    public string ContextJson { get; set; } = "[]";
}

/// <summary>One step of the pipeline.</summary>
/// <remarks>
/// Registered in order. A stage may add decisions, enrich the working set, or
/// report that it has nothing to offer — and a stage whose engine does not
/// exist yet says so rather than returning empty, because "ran and found
/// nothing" and "was never built" are different facts and a platform that
/// confuses them looks finished while being hollow.
/// </remarks>
public interface ILifeOsStage
{
    string Name { get; }

    Task<LifeOsStageTrace> ExecuteAsync(LifeOsWorkingSet working, CancellationToken ct);
}

/// <summary>Base for a stage whose engine has not been built yet.</summary>
/// <remarks>
/// Deliberately explicit. These appear in the trace as <c>unavailable</c> with
/// the reason, so the portal's decision inspector shows an operator what the
/// platform can and cannot yet decide — and so nobody mistakes silence for a
/// considered answer.
/// </remarks>
public abstract class NotYetBuiltStage(string name, string reason) : ILifeOsStage
{
    public string Name => name;

    public Task<LifeOsStageTrace> ExecuteAsync(LifeOsWorkingSet working, CancellationToken ct)
        => Task.FromResult(new LifeOsStageTrace(Name, "unavailable", reason, 0, 0));
}

// ---------------------------------------------------------------------------
// Stage 1 — context resolution
// ---------------------------------------------------------------------------

/// <summary>Who she is. Everything downstream keys on this.</summary>
public sealed class ContextResolutionStage(ILifeOsRepository repository) : ILifeOsStage
{
    public string Name => "contextResolution";

    public async Task<LifeOsStageTrace> ExecuteAsync(
        LifeOsWorkingSet working, CancellationToken ct)
    {
        var started = Stopwatch.GetTimestamp();

        working.Context = await repository.GetContextAsync(working.UserId, ct);

        if (working.Context is null)
        {
            return Trace(started, "noResult",
                "No profile row. She can still be served universal decisions.");
        }

        /*  The targeting vocabulary the content and dashboard engines already
            share. Built here once so every later stage asks the same question
            of the same context — two stages composing it separately would be
            two interpretations of who she is. */
        var parts = new List<string>();

        if (!string.IsNullOrWhiteSpace(working.Context.LifeStageCode))
            parts.Add($$"""{"dimension":"life_stage","value":"{{working.Context.LifeStageCode}}"}""");

        foreach (var role in SplitRoles(working.Context.RoleModesCsv))
            parts.Add($$"""{"dimension":"role_mode","value":"{{role}}"}""");

        if (!string.IsNullOrWhiteSpace(working.Context.CountryIso))
            parts.Add($$"""{"dimension":"country","value":"{{working.Context.CountryIso}}"}""");

        if (!string.IsNullOrWhiteSpace(working.Context.LanguageCode))
            parts.Add($$"""{"dimension":"language","value":"{{working.Context.LanguageCode}}"}""");

        working.ContextJson = "[" + string.Join(",", parts) + "]";

        return Trace(started, "contributed",
            $"Resolved {parts.Count} context dimension(s).");
    }

    internal static IEnumerable<string> SplitRoles(string? csv) =>
        string.IsNullOrWhiteSpace(csv)
            ? []
            : csv.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

    private LifeOsStageTrace Trace(long started, string status, string note) =>
        new(Name, status, note, 0, (long)Stopwatch.GetElapsedTime(started).TotalMilliseconds);
}

// ---------------------------------------------------------------------------
// Stage 2 — signal analysis
// ---------------------------------------------------------------------------

/// <summary>What the timeline currently says about her.</summary>
public sealed class SignalAnalysisStage(ILifeOsRepository repository) : ILifeOsStage
{
    public string Name => "signalAnalysis";

    public async Task<LifeOsStageTrace> ExecuteAsync(
        LifeOsWorkingSet working, CancellationToken ct)
    {
        var started = Stopwatch.GetTimestamp();

        var signals = await repository.GetRaisedSignalsAsync(
            working.UserId, working.AsOfLocalDate, ct);

        working.RaisedSignals.AddRange(signals);

        var elapsed = (long)Stopwatch.GetElapsedTime(started).TotalMilliseconds;

        /*  No signals is a normal, healthy answer — most days nothing is worth
            raising, and a quiet day is not a failure to report. */
        return signals.Count == 0
            ? new LifeOsStageTrace(Name, "noResult", "Nothing raised today.", 0, elapsed)
            : new LifeOsStageTrace(Name, "contributed",
                $"Raised: {string.Join(", ", signals)}.", 0, elapsed);
    }
}

// ---------------------------------------------------------------------------
// Stage 3 — dashboard resolution
// ---------------------------------------------------------------------------

/// <summary>What she should see, from the dashboard engine.</summary>
/// <remarks>
/// The engine already applies eligibility, priority and suppression and returns
/// its reasoning. This stage translates its rows into the common envelope and
/// adds nothing — a stage that re-sorted or re-scored here would be a second
/// copy of the priority rules.
/// </remarks>
public sealed class DashboardResolutionStage(ILifeOsRepository repository) : ILifeOsStage
{
    public string Name => "dashboardResolution";

    public async Task<LifeOsStageTrace> ExecuteAsync(
        LifeOsWorkingSet working, CancellationToken ct)
    {
        var started = Stopwatch.GetTimestamp();

        var cards = await repository.ResolveDashboardAsync(
            working.UserId, working.ContextJson, working.AsOfLocalDate, 20, ct);

        var resolvedUtc = DateTime.UtcNow;

        foreach (var card in cards)
        {
            working.Decisions.Add(new LifeDecision(
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
                /*  Nothing declares a dependency yet. The field is populated
                    from real relationships when routines exist, rather than
                    invented here from a guess about which card needs which. */
                DependsOn: [],
                IsHealthSensitive: card.IsHealthSensitive));
        }

        var elapsed = (long)Stopwatch.GetElapsedTime(started).TotalMilliseconds;

        return cards.Count == 0
            ? new LifeOsStageTrace(Name, "noResult",
                "No card was eligible for this context.", 0, elapsed)
            : new LifeOsStageTrace(Name, "contributed",
                $"{cards.Count} card(s) resolved.", cards.Count, elapsed);
    }
}

// ---------------------------------------------------------------------------
// Stages whose engines do not exist yet
// ---------------------------------------------------------------------------

public sealed class RoutineResolutionStage()
    : NotYetBuiltStage("routineResolution",
        "No routine engine yet. Planned after the dashboard engine.");

public sealed class RecommendationResolutionStage()
    : NotYetBuiltStage("recommendationResolution",
        "No recommendation engine yet. It will consume signals and the knowledge graph.");

public sealed class NotificationResolutionStage()
    : NotYetBuiltStage("notificationResolution",
        "Notification tables exist with no procedures or delivery path.");

public sealed class PredictionResolutionStage()
    : NotYetBuiltStage("predictionResolution",
        "No prediction engine. Nothing here may infer a health outcome.");

public sealed class AiContextResolutionStage()
    : NotYetBuiltStage("aiContextResolution",
        "No model integration. Guardrails ship before generation — see docs/ai/AI_PIPELINE.md.");

// ---------------------------------------------------------------------------
// The orchestrator
// ---------------------------------------------------------------------------

/// <summary>Ask the platform what a woman should see right now.</summary>
public sealed record ResolveLifeOsQuery(Guid UserId, DateOnly? AsOfLocalDate = null)
    : IRequest<Result<LifeOsResponse>>;

/// <summary>Runs the stages in order and assembles one answer.</summary>
/// <remarks>
/// Order is injected rather than hardcoded here, so the pipeline is visible in
/// one place in composition root instead of buried in a method.
/// <para>
/// A failing stage does not fail the request. A woman whose recommendation
/// engine threw should still get her dashboard, and the trace records what
/// broke — degrading to a smaller answer beats returning none.
/// </para>
/// </remarks>
public sealed class ResolveLifeOsHandler(IEnumerable<ILifeOsStage> stages)
    : IRequestHandler<ResolveLifeOsQuery, Result<LifeOsResponse>>
{
    public async Task<Result<LifeOsResponse>> Handle(
        ResolveLifeOsQuery query, CancellationToken ct)
    {
        var asOf = query.AsOfLocalDate ?? DateOnly.FromDateTime(DateTime.UtcNow);

        var working = new LifeOsWorkingSet
        {
            UserId = query.UserId,
            AsOfLocalDate = asOf,
        };

        var trace = new List<LifeOsStageTrace>();

        foreach (var stage in stages)
        {
            try
            {
                trace.Add(await stage.ExecuteAsync(working, ct));
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception ex)
            {
                /*  The message, not the exception. This reaches an operator
                    through the inspector, and a stack trace there would leak
                    schema detail into a browser. */
                trace.Add(new LifeOsStageTrace(
                    stage.Name, "failed", ex.Message, 0, 0));
            }
        }

        var context = new LifeContext(
            working.Context?.LifeStageCode,
            ContextResolutionStage.SplitRoles(working.Context?.RoleModesCsv).ToList(),
            working.Context?.CountryIso,
            working.Context?.LanguageCode,
            working.Context?.TimeZoneId,
            asOf,
            working.RaisedSignals);

        /*  Sorted once, here. Every consumer receives the same order, so a
            client that re-sorted would be disagreeing with the platform rather
            than presenting it. */
        var decisions = working.Decisions
            .OrderByDescending(d => d.Priority)
            .ThenBy(d => d.Title, StringComparer.Ordinal)
            .ToList();

        return Result<LifeOsResponse>.Success(new LifeOsResponse(
            query.UserId, DateTime.UtcNow, context, decisions, trace));
    }
}
