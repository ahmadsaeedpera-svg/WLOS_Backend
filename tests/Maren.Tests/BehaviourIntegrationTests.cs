using FluentAssertions;
using Maren.Application.Behaviour;
using Maren.Contracts;
using Microsoft.Extensions.DependencyInjection;

namespace Maren.Tests;

/// <summary>
/// Behaviour Intelligence, end to end against a real database.
/// </summary>
/// <remarks>
/// <para>
/// Behaviour is the single source of truth every later engine reads without
/// checking, so these assertions cover what those engines will assume: that a
/// day is counted once, that a measure without enough history is absent rather
/// than zero, that confidence describes coverage, and that every observation
/// can justify itself.
/// </para>
/// <para>
/// Against the real database, with no repository mock, for the reason
/// CLAUDE.md §7 gives: every rule worth testing lives in a function, and a
/// suite that mocked <c>IBehaviourRepository</c> would verify the mock.
/// </para>
/// </remarks>
[Collection("database")]
public sealed class BehaviourIntegrationTests(DatabaseFixture fixture)
{
    private static readonly Guid User = Guid.Parse("000000BE-0000-0000-0000-0000000000AA");
    private static readonly Guid Newcomer = Guid.Parse("000000BE-0000-0000-0000-0000000000BB");
    private static readonly DateOnly Today = DateOnly.FromDateTime(DateTime.UtcNow);

    private async Task<T> ScopedAsync<T>(Func<IServiceProvider, Task<T>> work)
    {
        await using var scope = fixture.Provider.CreateAsyncScope();
        return await work(scope.ServiceProvider);
    }

    private Task<IReadOnlyList<BehaviourObservation>> ResolveAsync(Guid userId) =>
        ScopedAsync(async sp =>
        {
            await SeedAsync(sp);
            var repository = sp.GetRequiredService<IBehaviourRepository>();
            return await repository.ResolveAsync(userId, Today, 56, default);
        });

    /*  Thirty days of water with a gap five days ago, and one part of a
        two-part evening routine. Built from arithmetic rather than fixed dates
        so the suite is re-runnable on any day. */
    private static async Task SeedAsync(IServiceProvider sp)
    {
        var factory = sp.GetRequiredService<Maren.Application.Abstractions.IDbConnectionFactory>();
        using var connection = await factory.CreateAsync(default);

        await Dapper.SqlMapper.ExecuteAsync(connection, """
            DELETE FROM [Behaviour].[Observation] WHERE UserId IN (@User, @New);
            DELETE FROM [Timeline].[Event]        WHERE UserId IN (@User, @New);
            DELETE FROM [Identity].[User]         WHERE UserId IN (@User, @New);

            INSERT INTO [Identity].[User] (UserId, Email, NormalisedEmail,
                PasswordHash, PasswordSalt, PasswordIterations, SecurityStamp)
            VALUES (@User, 'bhv-a@example.com', 'BHV-A@EXAMPLE.COM',
                    0x00, 0x00, 210000, NEWID()),
                   (@New,  'bhv-b@example.com', 'BHV-B@EXAMPLE.COM',
                    0x00, 0x00, 210000, NEWID());

            DECLARE @i INT = 0, @d DATE;
            WHILE @i < 30
            BEGIN
                SET @d = DATEADD(DAY, -@i, @Today);

                IF @i <> 5
                BEGIN
                    INSERT [Timeline].[Event] (EventId, UserId, EventTypeCode,
                        OccurredUtc, OccurredLocalDate, RecordedUtc, [Source], ValueNumeric)
                    VALUES (NEWID(), @User, 'water',
                            DATEADD(HOUR, 14, CAST(@d AS DATETIME2(3))), @d,
                            SYSUTCDATETIME(), 'manual', 250);

                    -- Twice on the same day. One day of hydration, not two.
                    INSERT [Timeline].[Event] (EventId, UserId, EventTypeCode,
                        OccurredUtc, OccurredLocalDate, RecordedUtc, [Source], ValueNumeric)
                    VALUES (NEWID(), @User, 'water',
                            DATEADD(HOUR, 20, CAST(@d AS DATETIME2(3))), @d,
                            SYSUTCDATETIME(), 'manual', 250);
                END

                -- One of the evening routine's two required parts.
                INSERT [Timeline].[Event] (EventId, UserId, EventTypeCode,
                    OccurredUtc, OccurredLocalDate, RecordedUtc, [Source])
                VALUES (NEWID(), @User, 'brush_teeth',
                        DATEADD(HOUR, 22, CAST(@d AS DATETIME2(3))), @d,
                        SYSUTCDATETIME(), 'manual');

                SET @i = @i + 1;
            END

            -- Joined today.
            INSERT [Timeline].[Event] (EventId, UserId, EventTypeCode,
                OccurredUtc, OccurredLocalDate, RecordedUtc, [Source], ValueNumeric)
            VALUES (NEWID(), @New, 'water',
                    DATEADD(HOUR, 9, CAST(@Today AS DATETIME2(3))), @Today,
                    SYSUTCDATETIME(), 'manual', 250);
            """,
            new { User, New = Newcomer, Today = Today.ToDateTime(TimeOnly.MinValue) });
    }

    // -----------------------------------------------------------------------

    [Fact]
    public async Task It_observes_her_habits_from_the_timeline_alone()
    {
        var observations = await ResolveAsync(User);

        observations.Should().NotBeEmpty();

        var consistency = observations.Single(o =>
            o.SubjectKey == "hydration" && o.MeasureCode == "consistency");

        // 29 active days across a 30-day span.
        consistency.ValueNumeric.Should().BeApproximately(96.7m, 0.2m);
        consistency.SpanDays.Should().Be(30, "span is her history, not the window width");
    }

    [Fact]
    public async Task A_day_is_counted_once_however_often_she_logs()
    {
        var observations = await ResolveAsync(User);

        var active = observations.Single(o =>
            o.SubjectKey == "hydration" && o.MeasureCode == "days_active");

        // 58 water events over 29 days.
        active.ValueNumeric.Should().Be(29m,
            "a thirsty afternoon is one day of hydration, not eight");
    }

    [Fact]
    public async Task Half_a_routine_does_not_count_as_done()
    {
        var observations = await ResolveAsync(User);

        // brush_teeth logged daily, skin_care never. The routine needs both.
        observations.Should().NotContain(o => o.SubjectKey == "evening_routine",
            "crediting a half-finished routine would tell her she kept something she did not");
    }

    [Fact]
    public async Task The_streak_stops_at_the_gap()
    {
        var observations = await ResolveAsync(User);

        var streak = observations.Single(o =>
            o.SubjectKey == "hydration" && o.MeasureCode == "streak_current");

        streak.ValueNumeric.Should().Be(5m, "days 0 through 4, then a missed day");
    }

    [Fact]
    public async Task A_measure_without_enough_history_is_absent_not_zero()
    {
        var observations = await ResolveAsync(Newcomer);

        // A zero streak and an unknown streak look identical on a screen and
        // mean opposite things.
        observations.Should().NotContain(o => o.MeasureCode == "streak_best");
        observations.Should().NotContain(o => o.MeasureCode == "momentum");
        observations.Should().NotContain(o => o.MeasureCode == "rhythm_weekday_best");
    }

    [Fact]
    public async Task But_a_newcomer_is_not_invisible()
    {
        var observations = await ResolveAsync(Newcomer);

        // Counting is not inferring. "You logged water on one day" is complete
        // after one day, and withholding it would leave her with an empty
        // screen and every engine downstream treating her as having done
        // nothing.
        observations.Should().NotBeEmpty();
        observations.Should().Contain(o => o.MeasureCode == "days_active");
    }

    [Fact]
    public async Task Confidence_describes_coverage_and_is_never_asserted()
    {
        var observations = await ResolveAsync(User);

        var momentum = observations.Single(o =>
            o.SubjectKey == "hydration" && o.MeasureCode == "momentum");

        // 30 days of a 56-day full span. Not 100.
        momentum.Confidence.Should().BeInRange(50, 60);

        var active = observations.Single(o =>
            o.SubjectKey == "hydration" && o.MeasureCode == "days_active");

        // 30 days against a 28-day full span, so fully covered.
        active.Confidence.Should().Be(100);
    }

    [Fact]
    public async Task No_probability_is_ever_certain()
    {
        var observations = await ResolveAsync(User);

        var probabilities = observations.Where(o => o.Family == "probability").ToList();

        probabilities.Should().NotBeEmpty();

        // Watching someone cannot justify certainty. A woman who has done
        // something every day for a month is not certain to do it tomorrow.
        probabilities.Should().OnlyContain(o =>
            o.ValueNumeric > 0m && o.ValueNumeric < 1m);
    }

    [Fact]
    public async Task Every_observation_can_justify_itself()
    {
        var observations = await ResolveAsync(User);

        // A recommendation built on an observation has to be able to show why.
        observations.Should().OnlyContain(o =>
            o.Reason.Length > 10
            && o.Evidence.Count > 0
            && o.SpanDays > 0
            && o.EngineVersion.Length > 0);
    }

    [Fact]
    public async Task Reading_returns_what_resolving_computed()
    {
        var (resolved, read) = await ScopedAsync(async sp =>
        {
            await SeedAsync(sp);
            var repository = sp.GetRequiredService<IBehaviourRepository>();
            var a = await repository.ResolveAsync(User, Today, 56, default);
            var b = await repository.GetAsync(User, Today, default);
            return (a, b);
        });

        // If reading and computing disagree, every engine downstream is looking
        // at a different woman.
        read.Should().HaveCount(resolved.Count);

        foreach (var expected in resolved)
        {
            var actual = read.Single(o =>
                o.SubjectKey == expected.SubjectKey && o.MeasureCode == expected.MeasureCode);

            actual.ValueNumeric.Should().Be(expected.ValueNumeric);
            actual.Confidence.Should().Be(expected.Confidence);
        }
    }

    [Fact]
    public async Task History_carries_the_engine_version_with_every_point()
    {
        var history = await ScopedAsync(async sp =>
        {
            await SeedAsync(sp);
            var repository = sp.GetRequiredService<IBehaviourRepository>();
            await repository.ResolveAsync(User, Today, 56, default);
            return await repository.HistoryAsync(User, "hydration", "consistency", 30, default);
        });

        history.Should().NotBeEmpty();

        // Without it, nobody can tell a real change in her behaviour from a
        // change in the definition, and "you have improved since March" becomes
        // unverifiable.
        history.Should().OnlyContain(p => p.EngineVersion.Length > 0);
    }

    [Fact]
    public async Task The_subject_catalogue_is_configuration_not_anybody_s_data()
    {
        var subjects = await ScopedAsync(sp =>
            sp.GetRequiredService<IBehaviourRepository>().ListSubjectsAsync(default));

        subjects.Should().NotBeEmpty();

        // A subject nothing feeds would observe behaviour from nothing.
        subjects.Where(s => s.IsActive).Should().OnlyContain(s => s.PartCount > 0);

        var routine = subjects.Single(s => s.SubjectKey == "evening_routine");
        routine.SubjectKind.Should().Be("routine");
        routine.TargetPerDay.Should().BeGreaterThan(1);
    }

    [Fact]
    public void Her_own_behaviour_needs_no_permission()
    {
        // It is her behaviour, on her account, reached through /api/v1/me with
        // the user id taken from the token. A permission here would be the
        // platform asking whether she may see herself.
        typeof(GetMyBehaviourQuery).Should().NotBeAssignableTo<
            Maren.Application.Behaviors.IRequirePermission>();
    }

    [Fact]
    public void The_operator_catalogue_does_require_one()
    {
        new ListBehaviourSubjectsQuery().Permission
            .Should().Be(Maren.Shared.PlatformPermissions.ContentRead);
    }

    [Fact]
    public void An_unbounded_history_request_is_refused()
    {
        var validator = new GetMyBehaviourHistoryValidator();

        var result = validator.Validate(
            new GetMyBehaviourHistoryQuery(User, "hydration", "consistency", 100_000));

        result.IsValid.Should().BeFalse("an unbounded page size is a denial-of-service vector");
    }
}
