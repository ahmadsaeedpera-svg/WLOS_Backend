using FluentAssertions;
using Maren.Application.Behaviour;
using Maren.Application.Coaching;
using Maren.Application.Recommend;
using Microsoft.Extensions.DependencyInjection;

namespace Maren.Tests;

/// <summary>
/// The Coach Platform, end to end against a real database.
/// </summary>
/// <remarks>
/// The coach explains and invents nothing. These assertions hold that: given
/// nothing to explain it says nothing, every message carries the
/// recommendation and its reasoning verbatim, no placeholder reaches her
/// unfilled, and it never reassembles.
/// </remarks>
[Collection("database")]
public sealed class CoachIntegrationTests(DatabaseFixture fixture)
{
    private static readonly Guid Thirsty = Guid.Parse("000000E6-0000-0000-0000-0000000000AA");
    private static readonly Guid Quiet = Guid.Parse("000000E6-0000-0000-0000-0000000000BB");
    private static readonly DateOnly Today = DateOnly.FromDateTime(DateTime.UtcNow);

    private async Task<T> ScopedAsync<T>(Func<IServiceProvider, Task<T>> work)
    {
        await using var scope = fixture.Provider.CreateAsyncScope();
        return await work(scope.ServiceProvider);
    }

    private static async Task SeedAsync(IServiceProvider sp)
    {
        var factory = sp.GetRequiredService<Maren.Application.Abstractions.IDbConnectionFactory>();
        using var connection = await factory.CreateAsync(default);

        await Dapper.SqlMapper.ExecuteAsync(connection, """
            DELETE FROM [Coach].[Explained]       WHERE UserId IN (@Thirsty, @Quiet);
            DELETE FROM [Recommend].[Assembled]   WHERE UserId IN (@Thirsty, @Quiet);
            DELETE FROM [Behaviour].[Observation] WHERE UserId IN (@Thirsty, @Quiet);
            DELETE FROM [Timeline].[Event]        WHERE UserId IN (@Thirsty, @Quiet);
            DELETE FROM [Identity].[User]         WHERE UserId IN (@Thirsty, @Quiet);

            INSERT INTO [Identity].[User] (UserId, Email, NormalisedEmail,
                PasswordHash, PasswordSalt, PasswordIterations, SecurityStamp)
            VALUES (@Thirsty, 'coach-a@example.com', 'COACH-A@EXAMPLE.COM',
                    0x00, 0x00, 210000, NEWID()),
                   (@Quiet,   'coach-b@example.com', 'COACH-B@EXAMPLE.COM',
                    0x00, 0x00, 210000, NEWID());

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

    /*  Behaviour, then recommendations, then the coach — the order the pipeline
        runs them in, because each reads what the one before published. */
    private Task<IReadOnlyList<Maren.Contracts.CoachMessage>> ResolveAsync(Guid userId) =>
        ScopedAsync(async sp =>
        {
            await SeedAsync(sp);
            await sp.GetRequiredService<IBehaviourRepository>()
                    .ResolveAsync(userId, Today, 56, default);
            await sp.GetRequiredService<IRecommendationRepository>()
                    .ResolveAsync(userId, Today, null, default);
            return await sp.GetRequiredService<ICoachRepository>()
                           .ResolveAsync(userId, Today, default);
        });

    // -----------------------------------------------------------------------

    [Fact]
    public async Task It_explains_what_the_platform_already_suggested()
    {
        var messages = await ResolveAsync(Thirsty);

        messages.Should().NotBeEmpty();

        var water = messages.Single(m => m.RecommendationKey == "water_reminder");

        // The message must carry the recommendation itself.
        water.MessageText.Should().Contain("not logged a drink today");
        water.ToneCode.Should().NotBeEmpty();
    }

    [Fact]
    public async Task With_nothing_to_explain_it_says_nothing()
    {
        var messages = await ResolveAsync(Quiet);

        // The strongest statement of what the coach is. It has no other source
        // of things to say, so a woman with no suggestions hears silence rather
        // than encouragement.
        messages.Should().BeEmpty();
    }

    [Fact]
    public async Task No_placeholder_reaches_her_unfilled()
    {
        var messages = await ResolveAsync(Thirsty);

        // A pattern with a typo would otherwise ship "{resaon}" to a woman.
        messages.Should().OnlyContain(m => !m.MessageText.Contains('{'));
        messages.Should().OnlyContain(m => !m.MessageText.Contains('}'));
    }

    [Fact]
    public async Task Evidence_is_carried_through_never_added_to()
    {
        var (messages, recommendations) = await ScopedAsync(async sp =>
        {
            await SeedAsync(sp);
            await sp.GetRequiredService<IBehaviourRepository>()
                    .ResolveAsync(Thirsty, Today, 56, default);
            var r = await sp.GetRequiredService<IRecommendationRepository>()
                            .ResolveAsync(Thirsty, Today, null, default);
            var c = await sp.GetRequiredService<ICoachRepository>()
                            .ResolveAsync(Thirsty, Today, default);
            return (c, r);
        });

        // The coach observes nothing, so it has no evidence of its own to add.
        foreach (var message in messages)
        {
            var source = recommendations.Single(r =>
                r.RecommendationKey == message.RecommendationKey);
            message.Evidence.Should().BeEquivalentTo(source.Evidence);
            message.Confidence.Should().Be(source.Confidence);
        }
    }

    [Fact]
    public async Task The_choice_of_voice_explains_itself()
    {
        var messages = await ResolveAsync(Thirsty);

        // A tone chosen without a stated reason is indistinguishable from one
        // chosen at random.
        messages.Should().OnlyContain(m => m.ToneRationale.Length > 10);
    }

    [Fact]
    public async Task Reading_returns_what_explaining_produced()
    {
        var (resolved, read) = await ScopedAsync(async sp =>
        {
            await SeedAsync(sp);
            await sp.GetRequiredService<IBehaviourRepository>()
                    .ResolveAsync(Thirsty, Today, 56, default);
            await sp.GetRequiredService<IRecommendationRepository>()
                    .ResolveAsync(Thirsty, Today, null, default);

            var coach = sp.GetRequiredService<ICoachRepository>();
            var a = await coach.ResolveAsync(Thirsty, Today, default);
            var b = await coach.GetAsync(Thirsty, Today, default);
            return (a, b);
        });

        read.Should().HaveCount(resolved.Count);

        foreach (var expected in resolved)
        {
            var actual = read.Single(m => m.RecommendationKey == expected.RecommendationKey);
            actual.MessageText.Should().Be(expected.MessageText);
            actual.ToneCode.Should().Be(expected.ToneCode);
        }
    }

    [Fact]
    public async Task Simulation_speaks_in_the_voice_the_evidence_calls_for()
    {
        var simulated = await ScopedAsync(sp =>
            sp.GetRequiredService<ICoachRepository>().SimulateAsync(
                "behaviour:hydration.days_since_last=3,state:energy.low", 100, default));

        simulated.Messages.Should().NotBeEmpty();

        // Low energy asks for the gentle voice, and the message must still
        // carry the same facts — a tone that softened by dropping evidence
        // would be the failure this platform refuses.
        var message = simulated.Messages.First();
        message.ToneCode.Should().Be("gentle");
        message.MessageText.Should().Contain("not logged a drink today");
    }

    [Fact]
    public async Task Simulation_explains_the_voices_it_did_not_choose()
    {
        var simulated = await ScopedAsync(sp =>
            sp.GetRequiredService<ICoachRepository>().SimulateAsync(
                "behaviour:hydration.days_since_last=3", 100, default));

        // "Why is it not being gentle" is the question an operator arrives
        // with, and a chosen tone alone cannot answer it.
        simulated.Tones.Should().Contain(t => t.ToneCode == "gentle");

        var gentle = simulated.Tones.Where(t => t.ToneCode == "gentle").ToList();
        gentle.Should().NotBeEmpty();
        gentle.Should().OnlyContain(t => !t.IsMatch,
            "no gentle rule was satisfied by this evidence");
    }

    [Fact]
    public async Task The_tone_library_is_configuration_not_anybody_s_data()
    {
        var tones = await ScopedAsync(sp =>
            sp.GetRequiredService<ICoachRepository>().ListTonesAsync(default));

        tones.Should().NotBeEmpty();

        // Every pattern must keep both placeholders, or a tone could encourage
        // without evidence. The database refuses one that does not; this is the
        // same rule asserted where a client can see it.
        tones.Should().OnlyContain(t =>
            t.Pattern.Contains("{body}") && t.Pattern.Contains("{reason}"));

        // Exactly one fallback: none means a recommendation reaches her with no
        // voice, two makes the fallback arbitrary.
        tones.Count(t => t.IsDefault && t.IsActive).Should().Be(1);

        // A non-default tone with no rules can never be selected.
        tones.Where(t => t.IsActive && !t.IsDefault)
             .Should().OnlyContain(t => t.RuleCount > 0);
    }

    [Fact]
    public void Her_own_coach_messages_need_no_permission()
    {
        typeof(GetMyCoachQuery).Should().NotBeAssignableTo<
            Maren.Application.Behaviors.IRequirePermission>();
    }

    [Fact]
    public void The_simulator_requires_a_permission()
    {
        new SimulateCoachQuery(
            new Maren.Contracts.SimulateRecommendationsRequest("behaviour:x", null))
            .Permission.Should().Be(Maren.Shared.PlatformPermissions.ContentRead);
    }

    [Fact]
    public void Unbounded_simulated_evidence_is_refused()
    {
        var validator = new SimulateCoachValidator();

        var result = validator.Validate(new SimulateCoachQuery(
            new Maren.Contracts.SimulateRecommendationsRequest(
                new string('x', 10_000), null)));

        result.IsValid.Should().BeFalse();
    }
}
