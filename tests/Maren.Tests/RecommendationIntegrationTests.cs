using FluentAssertions;
using Maren.Application.Behaviour;
using Maren.Application.Recommend;
using Microsoft.Extensions.DependencyInjection;

namespace Maren.Tests;

/// <summary>
/// The Recommendation Platform, end to end against a real database.
/// </summary>
/// <remarks>
/// A recommendation is assembled and decides nothing. These assertions cover
/// what that has to mean in practice: that a suggestion never appears without
/// evidence, that its confidence is inherited rather than asserted, that its
/// reasoning names observations she logged, and that the simulator runs the
/// same assembly as the live path.
/// </remarks>
[Collection("database")]
public sealed class RecommendationIntegrationTests(DatabaseFixture fixture)
{
    private static readonly Guid Thirsty = Guid.Parse("000000E5-0000-0000-0000-0000000000AA");
    private static readonly Guid Quiet = Guid.Parse("000000E5-0000-0000-0000-0000000000BB");
    private static readonly DateOnly Today = DateOnly.FromDateTime(DateTime.UtcNow);

    private async Task<T> ScopedAsync<T>(Func<IServiceProvider, Task<T>> work)
    {
        await using var scope = fixture.Provider.CreateAsyncScope();
        return await work(scope.ServiceProvider);
    }

    /*  One woman who logged water for a month and then stopped three days ago,
        and one who logged nothing at all. The first should attract a hydration
        suggestion built entirely from her own behaviour; the second must
        attract nothing, because there is nothing to build one from. */
    private static async Task SeedAsync(IServiceProvider sp)
    {
        var factory = sp.GetRequiredService<Maren.Application.Abstractions.IDbConnectionFactory>();
        using var connection = await factory.CreateAsync(default);

        await Dapper.SqlMapper.ExecuteAsync(connection, """
            DELETE FROM [Recommend].[Assembled]   WHERE UserId IN (@Thirsty, @Quiet);
            DELETE FROM [Behaviour].[Observation] WHERE UserId IN (@Thirsty, @Quiet);
            DELETE FROM [Timeline].[Event]        WHERE UserId IN (@Thirsty, @Quiet);
            DELETE FROM [Identity].[User]         WHERE UserId IN (@Thirsty, @Quiet);

            INSERT INTO [Identity].[User] (UserId, Email, NormalisedEmail,
                PasswordHash, PasswordSalt, PasswordIterations, SecurityStamp)
            VALUES (@Thirsty, 'rec-a@example.com', 'REC-A@EXAMPLE.COM',
                    0x00, 0x00, 210000, NEWID()),
                   (@Quiet,   'rec-b@example.com', 'REC-B@EXAMPLE.COM',
                    0x00, 0x00, 210000, NEWID());

            -- Days 3 to 32 inclusive: a month of water, then three dry days.
            DECLARE @i INT = 3, @d DATE;
            WHILE @i < 33
            BEGIN
                SET @d = DATEADD(DAY, -@i, @Today);
                INSERT [Timeline].[Event] (EventId, UserId, EventTypeCode,
                    OccurredUtc, OccurredLocalDate, RecordedUtc, [Source], ValueNumeric)
                VALUES (NEWID(), @Thirsty, 'water',
                        DATEADD(HOUR, 14, CAST(@d AS DATETIME2(3))), @d,
                        SYSUTCDATETIME(), 'manual', 250);
                SET @i = @i + 1;
            END
            """,
            new { Thirsty, Quiet, Today = Today.ToDateTime(TimeOnly.MinValue) });
    }

    private Task<IReadOnlyList<Maren.Contracts.Recommendation>> ResolveAsync(Guid userId) =>
        ScopedAsync(async sp =>
        {
            await SeedAsync(sp);
            await sp.GetRequiredService<IBehaviourRepository>()
                    .ResolveAsync(userId, Today, 56, default);
            return await sp.GetRequiredService<IRecommendationRepository>()
                           .ResolveAsync(userId, Today, null, default);
        });

    // -----------------------------------------------------------------------

    [Fact]
    public async Task It_assembles_from_what_she_logged()
    {
        var assembled = await ResolveAsync(Thirsty);

        var water = assembled.SingleOrDefault(r => r.RecommendationKey == "water_reminder");
        water.Should().NotBeNull("three dry days after a month of logging is what this is for");

        // Every clause of the reasoning is an observation, not an algorithm.
        water!.Reason.Should().Contain("not logged a drink today");
        water.Evidence.Should().Contain(e => e.StartsWith("behaviour:", StringComparison.Ordinal));
        water.Engines.Should().Contain("behaviour");
    }

    [Fact]
    public async Task Nothing_is_suggested_to_a_woman_who_logged_nothing()
    {
        var assembled = await ResolveAsync(Quiet);

        // A suggestion built on no evidence is a guess. The platform must never
        // make one, and the schema refuses to store one.
        assembled.Should().BeEmpty();
    }

    [Fact]
    public async Task Confidence_is_inherited_from_the_observations()
    {
        var assembled = await ResolveAsync(Thirsty);

        assembled.Should().NotBeEmpty();

        // Never asserted, never 100 by default, and never zero — a zero-
        // confidence recommendation is one assembled from nothing.
        assembled.Should().OnlyContain(r => r.Confidence > 0 && r.Confidence <= 100);
    }

    [Fact]
    public async Task Every_recommendation_carries_what_it_costs_her()
    {
        var assembled = await ResolveAsync(Thirsty);

        // A woman with no energy needs the low-effort one. Without both numbers
        // nothing downstream can make that choice for her.
        assembled.Should().OnlyContain(r =>
            r.ExpectedBenefit >= 1 && r.ExpectedBenefit <= 5
            && r.ExpectedEffort >= 1 && r.ExpectedEffort <= 5);
    }

    [Fact]
    public async Task A_suggestion_about_today_expires()
    {
        var assembled = await ResolveAsync(Thirsty);

        // A suggestion about tonight is wrong tomorrow.
        assembled.Should().OnlyContain(r => r.ExpiresUtc > DateTime.UtcNow);
        assembled.Should().OnlyContain(r => r.ExpiresUtc < DateTime.UtcNow.AddDays(31));
    }

    [Fact]
    public async Task Reading_returns_what_assembling_produced()
    {
        var (assembled, read) = await ScopedAsync(async sp =>
        {
            await SeedAsync(sp);
            await sp.GetRequiredService<IBehaviourRepository>()
                    .ResolveAsync(Thirsty, Today, 56, default);

            var repository = sp.GetRequiredService<IRecommendationRepository>();
            var a = await repository.ResolveAsync(Thirsty, Today, null, default);
            var b = await repository.GetAsync(Thirsty, Today, default);
            return (a, b);
        });

        read.Should().HaveCount(assembled.Count);

        foreach (var expected in assembled)
        {
            var actual = read.Single(r => r.RecommendationKey == expected.RecommendationKey);
            actual.Priority.Should().Be(expected.Priority);
            actual.Confidence.Should().Be(expected.Confidence);
            actual.Reason.Should().Be(expected.Reason);
        }
    }

    [Fact]
    public async Task Simulation_runs_the_same_assembly_as_the_live_path()
    {
        var (simulated, live) = await ScopedAsync(async sp =>
        {
            await SeedAsync(sp);
            await sp.GetRequiredService<IBehaviourRepository>()
                    .ResolveAsync(Thirsty, Today, 56, default);

            var repository = sp.GetRequiredService<IRecommendationRepository>();
            var l = await repository.ResolveAsync(Thirsty, Today, null, default);

            /*  The same observation the live path found, described by hand.
                Three dry days, and consistency below the optional threshold. */
            var s = await repository.SimulateAsync(
                "behaviour:hydration.days_since_last=3,behaviour:hydration.consistency=88",
                100, default);

            return (s, l);
        });

        var simWater = simulated.Assembled.Single(r => r.RecommendationKey == "water_reminder");
        var liveWater = live.Single(r => r.RecommendationKey == "water_reminder");

        // Same assembly, so the same sentence. If these ever diverge, an
        // operator is configuring the platform against a fiction.
        simWater.Reason.Should().Be(liveWater.Reason);
        simWater.Evidence.Should().BeEquivalentTo(liveWater.Evidence);
    }

    [Fact]
    public async Task Simulation_explains_absence_as_well_as_presence()
    {
        var simulated = await ScopedAsync(sp =>
            sp.GetRequiredService<IRecommendationRepository>()
              .SimulateAsync("behaviour:hydration.days_since_last=0", 100, default));

        // Nothing assembled — the required input was supplied and did not match.
        simulated.Assembled.Should().NotContain(r => r.RecommendationKey == "water_reminder");

        // And the inputs explain why. A list of only what fired explains
        // presence and never absence.
        var unmet = simulated.Inputs.Single(i =>
            i.RecommendationKey == "water_reminder"
            && i.InputKey == "hydration.days_since_last");

        unmet.WasSupplied.Should().BeTrue();
        unmet.IsMatch.Should().BeFalse();
        unmet.IsRequired.Should().BeTrue();
        unmet.SuppliedValue.Should().Be(0m);
    }

    [Fact]
    public async Task Inputs_that_were_never_supplied_are_distinguishable_from_ones_that_failed()
    {
        var simulated = await ScopedAsync(sp =>
            sp.GetRequiredService<IRecommendationRepository>()
              .SimulateAsync("behaviour:hydration.days_since_last=3", 100, default));

        // "You did not tell me" and "you told me and it did not match" are
        // different answers to "why is this not firing", and an operator needs
        // to tell them apart.
        var notSupplied = simulated.Inputs.Single(i =>
            i.RecommendationKey == "gentle_movement"
            && i.InputKey == "movement.days_since_last");

        notSupplied.WasSupplied.Should().BeFalse();
        notSupplied.IsMatch.Should().BeFalse();
        notSupplied.SuppliedValue.Should().BeNull();
    }

    [Fact]
    public async Task The_catalogue_is_configuration_not_anybody_s_data()
    {
        var catalogue = await ScopedAsync(sp =>
            sp.GetRequiredService<IRecommendationRepository>().ListAsync(default));

        catalogue.Should().NotBeEmpty();

        // A recommendation with no required input fires the moment any optional
        // one matches, which is almost never what somebody meant.
        catalogue.Where(r => r.IsActive).Should().OnlyContain(r => r.RequiredCount > 0);
        catalogue.Should().OnlyContain(r => r.InputsText.Length > 0);
    }

    [Fact]
    public void Her_own_recommendations_need_no_permission()
    {
        typeof(GetMyRecommendationsQuery).Should().NotBeAssignableTo<
            Maren.Application.Behaviors.IRequirePermission>();
    }

    [Fact]
    public void The_simulator_requires_a_permission()
    {
        new SimulateRecommendationsQuery(
            new Maren.Contracts.SimulateRecommendationsRequest("behaviour:x", null))
            .Permission.Should().Be(Maren.Shared.PlatformPermissions.ContentRead);
    }

    [Fact]
    public void Unbounded_simulated_evidence_is_refused()
    {
        var validator = new SimulateRecommendationsValidator();

        var result = validator.Validate(new SimulateRecommendationsQuery(
            new Maren.Contracts.SimulateRecommendationsRequest(
                new string('x', 10_000), null)));

        result.IsValid.Should().BeFalse(
            "an unbounded string reaching a string-split is a denial-of-service vector");
    }

    [Fact]
    public void Nothing_in_the_recommendation_contract_can_be_set_after_assembly()
    {
        /*  A mutable priority or confidence would let a client present a
            suggestion the platform did not make. Init-only accessors are what a
            positional record generates and are fine; a real setter is not. */
        static bool IsInitOnly(System.Reflection.PropertyInfo p) =>
            p.SetMethod is not null
            && p.SetMethod.ReturnParameter.GetRequiredCustomModifiers()
                .Any(m => m.FullName == "System.Runtime.CompilerServices.IsExternalInit");

        typeof(Maren.Contracts.Recommendation)
            .GetProperties()
            .Where(p => p.SetMethod is { IsPublic: true } && !IsInitOnly(p))
            .Should().BeEmpty();
    }
}
