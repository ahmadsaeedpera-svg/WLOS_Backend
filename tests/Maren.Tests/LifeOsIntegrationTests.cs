using System.Globalization;
using Dapper;
using FluentAssertions;
using Maren.Application.Onboarding;
using Maren.Application.Wlos;
using MediatR;
using Microsoft.Extensions.DependencyInjection;

namespace Maren.Tests;

/// <summary>
/// The Women's Life OS, end to end against a real database.
/// </summary>
/// <remarks>
/// The properties tested here are the ones every future client will rely on
/// without checking: that the answer adapts to who she is, that every decision
/// explains itself, that the platform sorts rather than the client, and that a
/// stage whose engine does not exist says so instead of returning silence.
/// </remarks>
[Collection("database")]
public sealed class LifeOsIntegrationTests(DatabaseFixture fixture)
{
    private const string Prefix = "wlos-test-";

    private static async Task<Guid> CreateUserAsync()
    {
        var id = Guid.NewGuid();
        using var connection = DatabaseFixture.Open();
        await connection.ExecuteAsync(
            """
            INSERT INTO [Identity].[User]
                (UserId, Email, NormalisedEmail, PasswordHash, PasswordSalt,
                 PasswordIterations, SecurityStamp)
            VALUES (@id, @email, UPPER(@email), 0x00, 0x00, 210000, NEWID());
            INSERT INTO [Identity].[Profile] (UserId) VALUES (@id);
            """,
            new { id, email = Prefix + id.ToString("N") + "@example.com" });
        return id;
    }

    private static async Task CleanupAsync()
    {
        using var connection = DatabaseFixture.Open();
        await connection.ExecuteAsync(
            """
            DELETE e FROM [Timeline].[Event] e
              JOIN [Identity].[User] u ON u.UserId = e.UserId WHERE u.Email LIKE @p;
            DELETE uls FROM [Identity].[UserLifeStage] uls
              JOIN [Identity].[User] u ON u.UserId = uls.UserId WHERE u.Email LIKE @p;
            DELETE urm FROM [Identity].[UserRoleMode] urm
              JOIN [Identity].[User] u ON u.UserId = urm.UserId WHERE u.Email LIKE @p;
            DELETE pr FROM [Identity].[Profile] pr
              JOIN [Identity].[User] u ON u.UserId = pr.UserId WHERE u.Email LIKE @p;
            DELETE FROM [Identity].[User] WHERE Email LIKE @p;
            """,
            new { p = Prefix + "%" });
    }

    private async Task<T> ScopedAsync<T>(Func<IServiceProvider, Task<T>> work)
    {
        await using var scope = fixture.Provider.CreateAsyncScope();
        return await work(scope.ServiceProvider);
    }

    private Task<Contracts.LifeOsResponse> ResolveAsync(Guid userId) =>
        ScopedAsync(async sp =>
        {
            var result = await sp.GetRequiredService<ISender>()
                .Send(new ResolveLifeOsQuery(userId, new DateOnly(2026, 7, 20)));
            result.Succeeded.Should().BeTrue();
            return result.Value!;
        });

    private Task SetStageAsync(Guid userId, string code) =>
        ScopedAsync(async sp =>
        {
            await sp.GetRequiredService<IOnboardingRepository>()
                .SetLifeStageAsync(userId, code, null, default);
            return true;
        });

    private static async Task RecordAsync(
        Guid userId, string type, string localDate, decimal value)
    {
        using var connection = DatabaseFixture.Open();
        await connection.ExecuteAsync(
            "[Timeline].[usp_Timeline_Record]",
            new
            {
                EventId = Guid.NewGuid(),
                UserId = userId,
                EventTypeCode = type,
                /*  InvariantCulture, not the runner's. A culture-sensitive
                    parse reads these dates differently depending on where the
                    machine thinks it is, which is a test that passes here and
                    fails on a CI runner in another region. */
                OccurredUtc = DateTime.Parse(
                    localDate + "T12:00:00", CultureInfo.InvariantCulture),
                OccurredLocalDate = DateTime.Parse(
                    localDate, CultureInfo.InvariantCulture),
                ValueNumeric = value
            },
            commandType: System.Data.CommandType.StoredProcedure);
    }

    // -----------------------------------------------------------------------

    [Fact]
    public async Task Every_surface_asks_one_question_and_gets_one_answer()
    {
        var userId = await CreateUserAsync();
        try
        {
            var response = await ResolveAsync(userId);

            response.UserId.Should().Be(userId);
            response.Decisions.Should().NotBeEmpty(
                "a woman we know nothing about still gets the universal cards");
            response.Trace.Should().NotBeEmpty();
        }
        finally { await CleanupAsync(); }
    }

    [Fact]
    public async Task The_answer_adapts_to_who_she_is()
    {
        // The whole point of the platform: one engine, not nineteen apps.
        var pregnant = await CreateUserAsync();
        var student = await CreateUserAsync();
        try
        {
            await SetStageAsync(pregnant, "pregnancy");
            await SetStageAsync(student, "young_adult");

            var forPregnant = await ResolveAsync(pregnant);
            var forStudent = await ResolveAsync(student);

            forPregnant.Decisions.Should().Contain(d => d.Code == "baby_development");
            forStudent.Decisions.Should().NotContain(d => d.Code == "baby_development");
        }
        finally { await CleanupAsync(); }
    }

    [Fact]
    public async Task Every_decision_explains_itself()
    {
        var userId = await CreateUserAsync();
        try
        {
            var response = await ResolveAsync(userId);

            // A surface nobody can interrogate is one nobody can debug or defend.
            foreach (var decision in response.Decisions)
            {
                decision.Reason.Should().NotBeNullOrWhiteSpace();
                decision.Source.Should().NotBeNullOrWhiteSpace();
                decision.Confidence.Should().BeInRange(0m, 1m);
                decision.Kind.Should().Be("dashboardCard");
            }
        }
        finally { await CleanupAsync(); }
    }

    [Fact]
    public async Task The_timeline_changes_what_she_sees_and_the_evidence_says_why()
    {
        var userId = await CreateUserAsync();
        try
        {
            await SetStageAsync(userId, "independent");

            var before = await ResolveAsync(userId);
            var waterBefore = before.Decisions.Single(d => d.Code == "hydration_prompt");
            waterBefore.Evidence.Should().BeEmpty("nothing has been recorded yet");

            // Two dry days inside the window raises low hydration.
            await RecordAsync(userId, "water", "2026-07-19", 500);
            await RecordAsync(userId, "water", "2026-07-20", 600);

            var after = await ResolveAsync(userId);
            var waterAfter = after.Decisions.Single(d => d.Code == "hydration_prompt");

            waterAfter.Priority.Should().BeGreaterThan(waterBefore.Priority);
            waterAfter.Evidence.Should().Contain("low_hydration");
            after.Context.RaisedSignals.Should().Contain("low_hydration");
        }
        finally { await CleanupAsync(); }
    }

    [Fact]
    public async Task The_platform_sorts_so_a_client_never_has_to()
    {
        // A client that re-sorted would be disagreeing with the platform
        // rather than presenting it.
        var userId = await CreateUserAsync();
        try
        {
            await SetStageAsync(userId, "pregnancy");
            var response = await ResolveAsync(userId);

            response.Decisions.Select(d => d.Priority)
                .Should().BeInDescendingOrder();
        }
        finally { await CleanupAsync(); }
    }

    [Fact]
    public async Task An_unbuilt_engine_says_so_rather_than_returning_silence()
    {
        // "Ran and found nothing" and "was never built" are different facts.
        // Collapsing them would make the platform look complete while hollow.
        var userId = await CreateUserAsync();
        try
        {
            var response = await ResolveAsync(userId);

            var unavailable = response.Trace.Where(t => t.Status == "unavailable").ToList();
            unavailable.Should().NotBeEmpty();
            /*  recommendationResolution used to be named here. It is built now,
                so this names stages that genuinely are not — the assertion is
                that the pipeline still admits its gaps, not that any particular
                engine is missing. When the last of these is built, replace them
                rather than deleting the test: a pipeline reporting no
                unavailable stages should be true, not merely unasserted. */
            unavailable.Should().Contain(t => t.Stage == "predictionResolution");
            unavailable.Should().Contain(t => t.Stage == "aiContextResolution");
            unavailable.Should().OnlyContain(t => !string.IsNullOrWhiteSpace(t.Reason),
                "an operator must be told why, not just that");
        }
        finally { await CleanupAsync(); }
    }

    [Fact]
    public async Task The_trace_shows_which_engines_actually_contributed()
    {
        var userId = await CreateUserAsync();
        try
        {
            await SetStageAsync(userId, "pregnancy");
            var response = await ResolveAsync(userId);

            var dashboard = response.Trace.Single(t => t.Stage == "dashboardResolution");
            dashboard.Status.Should().Be("contributed");
            dashboard.Diagnostics.Should().ContainKey("cards");

            var context = response.Trace.Single(t => t.Stage == "contextResolution");
            context.Status.Should().Be("contributed");

            // Observed by the context, not declared by the stage — a stage
            // cannot misreport what it actually read or wrote.
            var profileStage = response.Trace.Single(t => t.Stage == "profileResolution");
            profileStage.InputsUsed.Should().Contain("profile");
            profileStage.OutputsProduced.Should().Contain("targetingContext");
        }
        finally { await CleanupAsync(); }
    }

    [Fact]
    public async Task The_context_is_returned_so_a_decision_can_be_reproduced()
    {
        var userId = await CreateUserAsync();
        try
        {
            await SetStageAsync(userId, "menopause");
            await ScopedAsync(async sp =>
            {
                await sp.GetRequiredService<IOnboardingRepository>()
                    .SetRoleModesAsync(userId, ["professional"], default);
                return true;
            });

            var response = await ResolveAsync(userId);

            // Without this, "why did she see that yesterday" is unanswerable.
            response.Context.LifeStageCode.Should().Be("menopause");
            response.Context.RoleModes.Should().Contain("professional");
            response.Context.AsOfLocalDate.Should().Be(new DateOnly(2026, 7, 20));
        }
        finally { await CleanupAsync(); }
    }

    [Fact]
    public async Task The_pipeline_reports_her_state_alongside_her_cards()
    {
        var userId = await CreateUserAsync();
        try
        {
            await SetStageAsync(userId, "independent");
            await RecordAsync(userId, "sleep", "2026-07-19", 300);
            await RecordAsync(userId, "sleep", "2026-07-20", 310);

            var response = await ResolveAsync(userId);

            response.State.Should().NotBeEmpty();
            var energy = response.State.Single(s => s.DimensionCode == "energy");
            energy.ValueCode.Should().NotBe("unknown");
            energy.Score.Should().BeLessThan(70, "two short nights lower it from baseline");
            energy.Evidence.Should().Contain("short_sleep");
        }
        finally { await CleanupAsync(); }
    }

    [Fact]
    public async Task A_woman_who_logged_nothing_gets_unknown_not_a_confident_guess()
    {
        // The property the whole intelligence core rests on, asserted at the
        // pipeline boundary as well as in SQL.
        var userId = await CreateUserAsync();
        try
        {
            var response = await ResolveAsync(userId);

            response.State.Should().NotBeEmpty("she is still told what is unknown");
            response.State.Should().OnlyContain(s => s.ValueCode == "unknown");
            response.State.Should().OnlyContain(s => s.Confidence == 0);
            response.State.Should().OnlyContain(s => s.Score == null);
            response.State.Should().OnlyContain(s => !string.IsNullOrWhiteSpace(s.Reason));
        }
        finally { await CleanupAsync(); }
    }

    [Fact]
    public async Task Confidence_is_explained_wherever_it_is_reported()
    {
        var userId = await CreateUserAsync();
        try
        {
            await RecordAsync(userId, "sleep", "2026-07-20", 420);
            var response = await ResolveAsync(userId);

            // No bare numbers. A stage reporting confidence must say what
            // produced it, or an operator cannot tell 0.8 from a guess.
            foreach (var stage in response.Trace.Where(t => t.Confidence is not null))
            {
                stage.ConfidenceFactors.Should().NotBeEmpty(
                    $"{stage.Stage} reported confidence without explaining it");
                stage.ConfidenceFactors.Should()
                    .OnlyContain(f => !string.IsNullOrWhiteSpace(f.Explanation));
            }
        }
        finally { await CleanupAsync(); }
    }

    [Fact]
    public async Task Every_stage_reports_itself_including_the_unbuilt_ones()
    {
        var userId = await CreateUserAsync();
        try
        {
            var response = await ResolveAsync(userId);

            // Adding a stage is registration only; the trace grows with it.
            response.Trace.Should().HaveCountGreaterThanOrEqualTo(20);
            response.Trace.Should().OnlyContain(t => !string.IsNullOrWhiteSpace(t.Version));
            response.Trace.Select(t => t.Stage).Should().OnlyHaveUniqueItems();

            // No stage may fail the pipeline; a failure is recorded and the
            // run continues.
            response.Trace.Should().NotContain(t => t.Status == "failed");
        }
        finally { await CleanupAsync(); }
    }

    [Fact]
    public async Task Health_sensitive_decisions_are_flagged_for_every_consumer()
    {
        var userId = await CreateUserAsync();
        try
        {
            await SetStageAsync(userId, "pregnancy");
            var response = await ResolveAsync(userId);

            // Downstream surfaces, including a future model, must be able to
            // tell which decisions touch self-reported health without
            // re-deriving it from the domain.
            response.Decisions.Should().Contain(d => d.IsHealthSensitive);
            response.Decisions.Where(d => d.Code == "hydration_prompt")
                .Should().OnlyContain(d => !d.IsHealthSensitive);
        }
        finally { await CleanupAsync(); }
    }
}
