using FluentAssertions;
using Maren.Application.Behaviour;
using Maren.Application.Growth;
using Maren.Contracts;
using Microsoft.Extensions.DependencyInjection;

namespace Maren.Tests;

/// <summary>
/// Goals, end to end against a real database.
/// </summary>
/// <remarks>
/// A goal is a desired outcome, and progress is the distance between what
/// Behaviour observed and what the goal asks for. These assertions cover the
/// properties a coach, a recommendation and a progress ring will all assume:
/// that progress comes from behaviour, that a goal is never awarded on silence,
/// that unknown progress is null rather than zero, and that achievement is
/// earned rather than declared.
/// </remarks>
[Collection("database")]
public sealed class GoalIntegrationTests(DatabaseFixture fixture)
{
    private static readonly Guid Active = Guid.Parse("000000E1-0000-0000-0000-0000000000AA");
    private static readonly Guid Quiet = Guid.Parse("000000E1-0000-0000-0000-0000000000BB");
    private static readonly DateOnly Today = DateOnly.FromDateTime(DateTime.UtcNow);

    private async Task<T> ScopedAsync<T>(Func<IServiceProvider, Task<T>> work)
    {
        await using var scope = fixture.Provider.CreateAsyncScope();
        return await work(scope.ServiceProvider);
    }

    /*  One woman who logs water every day, one who logs nothing. Built from
        arithmetic rather than fixed dates so the suite is re-runnable. */
    private static async Task SeedAsync(IServiceProvider sp)
    {
        var factory = sp.GetRequiredService<Maren.Application.Abstractions.IDbConnectionFactory>();
        using var connection = await factory.CreateAsync(default);

        await Dapper.SqlMapper.ExecuteAsync(connection, """
            DELETE FROM [Growth].[GoalProgress]   WHERE UserId IN (@Active, @Quiet);
            DELETE FROM [Growth].[UserGoal]       WHERE UserId IN (@Active, @Quiet);
            DELETE FROM [Behaviour].[Observation] WHERE UserId IN (@Active, @Quiet);
            DELETE FROM [Timeline].[Event]        WHERE UserId IN (@Active, @Quiet);
            DELETE FROM [Identity].[User]         WHERE UserId IN (@Active, @Quiet);

            INSERT INTO [Identity].[User] (UserId, Email, NormalisedEmail,
                PasswordHash, PasswordSalt, PasswordIterations, SecurityStamp)
            VALUES (@Active, 'goal-a@example.com', 'GOAL-A@EXAMPLE.COM',
                    0x00, 0x00, 210000, NEWID()),
                   (@Quiet,  'goal-b@example.com', 'GOAL-B@EXAMPLE.COM',
                    0x00, 0x00, 210000, NEWID());

            DECLARE @i INT = 0, @d DATE;
            WHILE @i < 30
            BEGIN
                SET @d = DATEADD(DAY, -@i, @Today);
                INSERT [Timeline].[Event] (EventId, UserId, EventTypeCode,
                    OccurredUtc, OccurredLocalDate, RecordedUtc, [Source], ValueNumeric)
                VALUES (NEWID(), @Active, 'water',
                        DATEADD(HOUR, 14, CAST(@d AS DATETIME2(3))), @d,
                        SYSUTCDATETIME(), 'manual', 250);
                SET @i = @i + 1;
            END
            """,
            new { Active, Quiet, Today = Today.ToDateTime(TimeOnly.MinValue) });
    }

    private static async Task ObserveAsync(IServiceProvider sp, Guid userId) =>
        await sp.GetRequiredService<IBehaviourRepository>()
                .ResolveAsync(userId, Today, 56, default);

    // -----------------------------------------------------------------------

    [Fact]
    public async Task Progress_comes_from_behaviour()
    {
        var goals = await ScopedAsync(async sp =>
        {
            await SeedAsync(sp);
            await ObserveAsync(sp, Active);

            var repository = sp.GetRequiredService<IGoalRepository>();
            await repository.AdoptAsync(Active,
                new AdoptGoalRequest("drink_more_water", "Work days are hardest.", null, null),
                Today, default);

            return await repository.ResolveAsync(Active, Today, default);
        });

        var water = goals.Single(g => g.GoalTemplateKey == "drink_more_water");

        // 30 unbroken days clears both targets: 70% consistency and a 3-day run.
        water.ProgressPercent.Should().Be(100m);
        water.MeasuresMet.Should().Be(water.MeasureCount);
        water.Confidence.Should().BeGreaterThan(0);
    }

    [Fact]
    public async Task Achievement_is_earned_from_the_timeline_not_declared()
    {
        var (afterResolve, refused) = await ScopedAsync(async sp =>
        {
            await SeedAsync(sp);
            await ObserveAsync(sp, Active);

            var repository = sp.GetRequiredService<IGoalRepository>();
            var (_, _, goalId) = await repository.AdoptAsync(Active,
                new AdoptGoalRequest("drink_more_water", null, null, null), Today, default);

            var resolved = await repository.ResolveAsync(Active, Today, default);

            // The one number in the platform that has to be earned.
            var attempt = await repository.SetStatusAsync(
                Active, goalId!.Value, "achieved", default);

            return (resolved, attempt);
        });

        afterResolve.Single(g => g.GoalTemplateKey == "drink_more_water")
                    .Status.Should().Be("achieved");

        refused.Succeeded.Should().BeFalse(
            "a client that could declare achievement would make it something to ask for");
    }

    [Fact]
    public async Task A_goal_is_never_awarded_on_silence()
    {
        var goals = await ScopedAsync(async sp =>
        {
            await SeedAsync(sp);
            await ObserveAsync(sp, Quiet);

            var repository = sp.GetRequiredService<IGoalRepository>();
            await repository.AdoptAsync(Quiet,
                new AdoptGoalRequest("steady_sleep", null, null, null), Today, default);

            return await repository.ResolveAsync(Quiet, Today, default);
        });

        var sleep = goals.Single(g => g.GoalTemplateKey == "steady_sleep");

        sleep.IsComplete.Should().BeFalse();
        sleep.Status.Should().Be("active");

        // Unknown, not zero. A zero ring says she has made no progress; the
        // truth is the platform has not seen enough to say.
        sleep.ProgressPercent.Should().BeNull();
        sleep.Confidence.Should().Be(0);
    }

    [Fact]
    public async Task Adopting_twice_updates_rather_than_duplicating()
    {
        var (first, second, goals) = await ScopedAsync(async sp =>
        {
            await SeedAsync(sp);
            await ObserveAsync(sp, Active);

            var repository = sp.GetRequiredService<IGoalRepository>();
            var a = await repository.AdoptAsync(Active,
                new AdoptGoalRequest("move_most_days", "For my knees.", null, null),
                Today, default);

            // An offline client retries; a woman taps twice.
            var b = await repository.AdoptAsync(Active,
                new AdoptGoalRequest("move_most_days", null, null, null), Today, default);

            return (a, b, await repository.ResolveAsync(Active, Today, default));
        });

        first.Succeeded.Should().BeTrue();
        second.Succeeded.Should().BeTrue();
        second.UserGoalId.Should().Be(first.UserGoalId);

        goals.Count(g => g.GoalTemplateKey == "move_most_days").Should().Be(1);

        // Her words survive a retry that did not carry them.
        goals.Single(g => g.GoalTemplateKey == "move_most_days")
             .MotivationText.Should().Be("For my knees.");
    }

    [Fact]
    public async Task Nobody_can_change_another_womans_goal()
    {
        var attempt = await ScopedAsync(async sp =>
        {
            await SeedAsync(sp);
            var repository = sp.GetRequiredService<IGoalRepository>();

            var (_, _, goalId) = await repository.AdoptAsync(Active,
                new AdoptGoalRequest("check_in_weekly", null, null, null), Today, default);

            // Without the user-id predicate in the procedure this is a
            // one-parameter way to abandon a stranger's goal.
            return await repository.SetStatusAsync(Quiet, goalId!.Value, "abandoned", default);
        });

        attempt.Succeeded.Should().BeFalse();
        attempt.FailureCode.Should().Be("NOT_FOUND");
    }

    [Fact]
    public async Task A_goal_she_already_holds_is_not_offered_again()
    {
        var offers = await ScopedAsync(async sp =>
        {
            await SeedAsync(sp);
            var repository = sp.GetRequiredService<IGoalRepository>();

            await repository.AdoptAsync(Active,
                new AdoptGoalRequest("drink_more_water", null, null, null), Today, default);

            return await repository.OfferAsync(Active, null, default);
        });

        offers.Should().NotBeEmpty();
        offers.Should().NotContain(o => o.GoalTemplateKey == "drink_more_water",
            "offering a goal she is three weeks into admits the platform does not know her");

        // Every offer says what taking it on would mean.
        offers.Should().OnlyContain(o =>
            o.MeasureCount > 0 && o.TargetsText.Length > 0 && o.MotivationPrompt.Length > 0);
    }

    [Fact]
    public async Task Every_goal_explains_where_it_stands()
    {
        var goals = await ScopedAsync(async sp =>
        {
            await SeedAsync(sp);
            await ObserveAsync(sp, Quiet);

            var repository = sp.GetRequiredService<IGoalRepository>();
            await repository.AdoptAsync(Quiet,
                new AdoptGoalRequest("steady_sleep", null, null, null), Today, default);

            return await repository.ResolveAsync(Quiet, Today, default);
        });

        // "Why am I not there yet" must resolve to the specific thing that is
        // short, not to a percentage.
        goals.Should().OnlyContain(g =>
            g.Reason.Length > 10 && g.Evidence.Count > 0 && g.EngineVersion.Length > 0);
    }

    [Fact]
    public async Task The_library_is_configuration_not_anybody_s_data()
    {
        var templates = await ScopedAsync(sp =>
            sp.GetRequiredService<IGoalRepository>().ListTemplatesAsync(default));

        templates.Should().NotBeEmpty();

        // A goal with no measures can never progress and never complete. It
        // would sit on her screen forever with no explanation.
        templates.Where(t => t.IsActive).Should().OnlyContain(t => t.MeasureCount > 0);
        templates.Where(t => t.IsActive).Should().OnlyContain(t => t.Measures.Count > 0);
    }

    [Fact]
    public void Her_own_goals_need_no_permission()
    {
        // Her goals, on her account, with the user id from the token. A
        // permission would be the platform asking whether she may see what she
        // is working towards.
        typeof(GetMyGoalsQuery).Should().NotBeAssignableTo<
            Maren.Application.Behaviors.IRequirePermission>();
    }

    [Fact]
    public void The_operator_library_does_require_one()
    {
        new ListGoalTemplatesQuery().Permission
            .Should().Be(Maren.Shared.PlatformPermissions.ContentRead);
    }

    [Fact]
    public void Declaring_a_goal_achieved_is_refused_before_the_database()
    {
        var validator = new SetGoalStatusValidator();

        var result = validator.Validate(
            new SetGoalStatusCommand(Active, Guid.NewGuid(), "achieved"));

        result.IsValid.Should().BeFalse();

        // The message tells her where achievement actually comes from rather
        // than just refusing.
        result.Errors[0].ErrorMessage.Should().Contain("what you log");
    }

    [Fact]
    public void An_oversized_motivation_is_refused_before_she_loses_it()
    {
        var validator = new AdoptGoalValidator();

        var result = validator.Validate(new AdoptGoalCommand(Active,
            new AdoptGoalRequest("drink_more_water", new string('x', 500), null, null)));

        result.IsValid.Should().BeFalse(
            "she should be told before the database refuses the row and her typing is gone");
    }
}
