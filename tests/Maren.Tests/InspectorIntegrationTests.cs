using FluentAssertions;
using Maren.Application.Inspector;
using Maren.Contracts;
using Microsoft.Extensions.DependencyInjection;

namespace Maren.Tests;

/// <summary>
/// The decision inspector, end to end against a real database.
/// </summary>
/// <remarks>
/// The inspector's value depends entirely on it agreeing with the live engine.
/// If it computed its own answers an operator would configure against a
/// fiction, which is worse than having no inspector — so these assertions pin
/// its output to the same numbers production produces.
/// </remarks>
[Collection("database")]
public sealed class InspectorIntegrationTests(DatabaseFixture fixture)
{
    private async Task<T> ScopedAsync<T>(Func<IServiceProvider, Task<T>> work)
    {
        await using var scope = fixture.Provider.CreateAsyncScope();
        return await work(scope.ServiceProvider);
    }

    private Task<SimulateResponse> SimulateAsync(SimulateRequest request) =>
        ScopedAsync(async sp =>
        {
            var handler = new SimulateDashboardHandler(
                sp.GetRequiredService<IInspectorRepository>());
            var result = await handler.Handle(new SimulateDashboardQuery(request), default);
            result.Succeeded.Should().BeTrue();
            return result.Value!;
        });

    private Task<IReadOnlyList<InspectableSignal>> SignalsAsync() =>
        ScopedAsync(async sp =>
        {
            var handler = new ListInspectableSignalsHandler(
                sp.GetRequiredService<IInspectorRepository>());
            var result = await handler.Handle(new ListInspectableSignalsQuery(), default);
            result.Succeeded.Should().BeTrue();
            return result.Value!;
        });

    // -----------------------------------------------------------------------

    [Fact]
    public async Task It_reproduces_what_a_pregnant_woman_would_see()
    {
        var response = await SimulateAsync(new SimulateRequest(
            "pregnancy", null, null, null, null));

        response.Cards.Should().Contain(c => c.CardTypeCode == "baby_development");
        response.Cards.Should().NotContain(c => c.CardTypeCode == "study_focus");
    }

    [Fact]
    public async Task Baseline_priority_matches_the_live_engine()
    {
        var response = await SimulateAsync(new SimulateRequest(
            "independent", ["professional"], null, null, null));

        var water = response.Cards.Single(c => c.CardTypeCode == "hydration_prompt");
        water.Priority.Should().Be(40, "the registry's base priority, unchanged");
        water.EvidenceSignals.Should().BeEmpty();
        water.Source.Should().Be("baseline");
    }

    [Fact]
    public async Task Supplied_signals_move_priority_by_the_same_arithmetic()
    {
        var response = await SimulateAsync(new SimulateRequest(
            "independent", ["professional"], null, null,
            ["low_hydration", "short_sleep"]));

        var water = response.Cards.Single(c => c.CardTypeCode == "hydration_prompt");
        water.Priority.Should().Be(90, "40 base, plus 35 and 15 from the adjustments");
        water.EvidenceSignals.Should().Contain("low_hydration");
        water.Source.Should().Be("signal");
    }

    [Fact]
    public async Task A_suppressed_card_is_returned_flagged_rather_than_dropped()
    {
        // The reason the inspector exists. On the live path this card simply
        // vanishes, which makes "why is my card missing" unanswerable.
        var response = await SimulateAsync(new SimulateRequest(
            "independent", ["professional"], null, null, ["long_work"]));

        var nudge = response.Cards.Single(c => c.CardTypeCode == "learning_nudge");
        nudge.IsSuppressed.Should().BeTrue();
        nudge.Priority.Should().BeLessThanOrEqualTo(0);
        nudge.EvidenceSignals.Should().Contain("long_work",
            "an operator needs to know which signal did it");
    }

    [Fact]
    public async Task The_context_is_echoed_so_an_operator_sees_what_was_asked()
    {
        var response = await SimulateAsync(new SimulateRequest(
            "menopause", ["professional", "caregiver"], "GB", "en-GB", null));

        response.ContextJson.Should().Contain("\"life_stage\"").And.Contain("menopause");
        response.ContextJson.Should().Contain("caregiver");
        response.ContextJson.Should().Contain("\"country\"").And.Contain("GB");
    }

    [Fact]
    public async Task An_unknown_signal_is_ignored_rather_than_failing_the_request()
    {
        // Somebody typing into a what-if box should see the effect of what the
        // platform recognises, not an error about a name it does not.
        var response = await SimulateAsync(new SimulateRequest(
            "independent", ["professional"], null, null,
            ["not_a_real_signal", "low_hydration"]));

        var water = response.Cards.Single(c => c.CardTypeCode == "hydration_prompt");
        water.Priority.Should().Be(75, "only the recognised signal applied");
    }

    [Fact]
    public async Task A_quote_in_the_input_cannot_break_out_of_the_context()
    {
        // The context is composed as JSON by hand and these values come from a
        // browser, so the escaping is load-bearing rather than defensive.
        var response = await SimulateAsync(new SimulateRequest(
            "pregnancy\",\"x\":\"y", null, null, null, null));

        // The injected text stays inside one string value; the document still
        // parses and the engine sees a stage code it does not recognise.
        var parsed = System.Text.Json.JsonDocument.Parse(response.ContextJson);
        parsed.RootElement.GetArrayLength().Should().Be(1);
        response.Cards.Should().NotContain(c => c.CardTypeCode == "baby_development",
            "the mangled code must not match the real pregnancy stage");
    }

    [Fact]
    public async Task A_card_explains_the_rules_that_rejected_it()
    {
        // A list of only the rules that passed explains a card's presence and
        // never its absence, and absence is what an operator investigates.
        var explanation = await ScopedAsync(async sp =>
        {
            var handler = new ExplainCardHandler(sp.GetRequiredService<IInspectorRepository>());
            var result = await handler.Handle(
                new ExplainCardQuery("baby_development", new SimulateRequest(
                    "independent", ["professional"], null, null, null)), default);
            result.Succeeded.Should().BeTrue();
            return result.Value!;
        });

        explanation.CardTypeCode.Should().Be("baby_development");
        explanation.Rules.Should().NotBeEmpty();
        explanation.Rules.Should().OnlyContain(r => !r.ContextPasses,
            "a working woman does not satisfy the pregnancy rule");
        explanation.Rules.Should().OnlyContain(r => !string.IsNullOrWhiteSpace(r.RuleNote));
    }

    [Fact]
    public async Task An_unknown_card_is_a_clean_not_found()
    {
        var result = await ScopedAsync(async sp =>
        {
            var handler = new ExplainCardHandler(sp.GetRequiredService<IInspectorRepository>());
            return await handler.Handle(
                new ExplainCardQuery("no_such_card", new SimulateRequest(
                    null, null, null, null, null)), default);
        });

        result.Succeeded.Should().BeFalse();
        result.FailureCode.Should().Be("NOT_FOUND");
    }

    [Fact]
    public void The_inspector_requires_a_permission()
    {
        // Read-only, but it exposes how the platform targets women. The
        // pipeline enforces this before the handler runs.
        var query = new SimulateDashboardQuery(new SimulateRequest(null, null, null, null, null));
        query.Permission.Should().Be(Maren.Shared.PlatformPermissions.ContentRead);
    }

    [Fact]
    public async Task The_signal_picker_offers_only_signals_that_move_a_card()
    {
        var signals = await SignalsAsync();

        // Empty would render a fieldset with nothing in it, and an operator
        // would conclude the platform has no signals at all.
        signals.Should().NotBeEmpty();

        // A signal with no adjustment changes nothing. Offering it invites an
        // operator to toggle it, see identical cards, and report a bug.
        signals.Should().OnlyContain(s => s.AffectsCardCount > 0);
    }

    [Fact]
    public async Task Every_offered_signal_is_one_the_simulator_actually_applies()
    {
        // The contract between the two endpoints. If the picker could list a
        // name SimulateDashboard drops as unknown, the inspector would lie
        // silently: toggled on, nothing moves, no error.
        var codes = (await SignalsAsync()).Select(s => s.SignalCode).ToArray();

        var response = await SimulateAsync(new SimulateRequest(
            "independent", ["professional"], null, null, codes));

        response.AppliedSignals.Should().BeEquivalentTo(codes);
    }

    [Fact]
    public void The_signal_picker_requires_the_same_permission_as_the_simulator()
    {
        // It names the signals the platform observes about women. Anyone who
        // may see how content is targeted may see these; nobody else.
        new ListInspectableSignalsQuery().Permission
            .Should().Be(Maren.Shared.PlatformPermissions.ContentRead);
    }

    [Fact]
    public void Oversized_input_is_refused_before_it_reaches_the_database()
    {
        var validator = new SimulateDashboardValidator();

        var result = validator.Validate(new SimulateDashboardQuery(
            new SimulateRequest(null, [.. Enumerable.Repeat("professional", 40)],
                null, null, null)));

        result.IsValid.Should().BeFalse("an unbounded list is a denial-of-service vector");
    }
}
