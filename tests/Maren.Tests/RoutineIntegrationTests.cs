using FluentAssertions;
using Maren.Application.Behaviour;
using Maren.Application.Growth;
using Microsoft.Extensions.DependencyInjection;

namespace Maren.Tests;

/// <summary>
/// Routines, end to end against a real database.
/// </summary>
/// <remarks>
/// A routine is several behaviours done together, and Behaviour already models
/// that. So these assertions are about keeping this layer thin: that completion
/// is derived rather than stored, that the checklist and the streak come from
/// the same events, and that a routine owns no step list of its own.
/// </remarks>
[Collection("database")]
public sealed class RoutineIntegrationTests(DatabaseFixture fixture)
{
    private static readonly Guid User = Guid.Parse("000000E3-0000-0000-0000-0000000000AA");
    private static readonly DateOnly Today = DateOnly.FromDateTime(DateTime.UtcNow);

    private async Task<T> ScopedAsync<T>(Func<IServiceProvider, Task<T>> work)
    {
        await using var scope = fixture.Provider.CreateAsyncScope();
        return await work(scope.ServiceProvider);
    }

    /*  Steps logged is a parameter, so one helper covers "not begun", "half
        way" and "finished" without three near-identical fixtures. */
    private static async Task SeedAsync(IServiceProvider sp, params string[] stepsLogged)
    {
        var factory = sp.GetRequiredService<Maren.Application.Abstractions.IDbConnectionFactory>();
        using var connection = await factory.CreateAsync(default);

        await Dapper.SqlMapper.ExecuteAsync(connection, """
            DELETE FROM [Behaviour].[Observation] WHERE UserId = @User;
            DELETE FROM [Timeline].[Event]        WHERE UserId = @User;
            DELETE FROM [Identity].[User]         WHERE UserId = @User;

            INSERT INTO [Identity].[User] (UserId, Email, NormalisedEmail,
                PasswordHash, PasswordSalt, PasswordIterations, SecurityStamp)
            VALUES (@User, 'routine-a@example.com', 'ROUTINE-A@EXAMPLE.COM',
                    0x00, 0x00, 210000, NEWID());
            """, new { User });

        foreach (var step in stepsLogged)
        {
            await Dapper.SqlMapper.ExecuteAsync(connection, """
                INSERT [Timeline].[Event] (EventId, UserId, EventTypeCode,
                    OccurredUtc, OccurredLocalDate, RecordedUtc, [Source])
                VALUES (NEWID(), @User, @Step,
                        DATEADD(HOUR, 22, CAST(@Today AS DATETIME2(3))), @Today,
                        SYSUTCDATETIME(), 'manual');
                """,
                new { User, Step = step, Today = Today.ToDateTime(TimeOnly.MinValue) });
        }
    }

    private Task<IReadOnlyList<Maren.Contracts.RoutineToday>> TodayAsync(
        params string[] stepsLogged) =>
        ScopedAsync(async sp =>
        {
            await SeedAsync(sp, stepsLogged);
            return await sp.GetRequiredService<IRoutineRepository>()
                           .TodayAsync(User, Today, null, default);
        });

    // -----------------------------------------------------------------------

    [Fact]
    public async Task A_routine_she_has_never_done_still_appears()
    {
        var routines = await TodayAsync();

        // Hiding it until the platform has something to say means she never
        // sees a routine she has not started — which is when she needs it most.
        routines.Should().NotBeEmpty();

        var evening = routines.Single(r => r.RoutineKey == "evening_winddown");
        evening.IsDoneToday.Should().BeFalse();
        evening.IsStarted.Should().BeFalse();
    }

    [Fact]
    public async Task Its_steps_come_from_the_behaviour_subject()
    {
        var routines = await TodayAsync();
        var evening = routines.Single(r => r.RoutineKey == "evening_winddown");

        // The routine owns no step list. These are the subject's parts.
        evening.Steps.Should().NotBeEmpty();
        evening.SubjectKey.Should().Be("evening_routine");
        evening.Steps.Select(s => s.EventTypeCode)
               .Should().Contain(["brush_teeth", "skin_care"]);
    }

    [Fact]
    public async Task Optional_steps_are_shown_and_flagged()
    {
        var routines = await TodayAsync();
        var evening = routines.Single(r => r.RoutineKey == "evening_winddown");

        // Hiding the step she may skip would quietly turn optional into
        // non-existent.
        evening.Steps.Should().Contain(s => !s.IsRequired);
        evening.RequiredCount.Should().BeLessThan(evening.StepCount);
    }

    [Fact]
    public async Task One_step_in_reads_as_started_not_done()
    {
        var routines = await TodayAsync("brush_teeth");
        var evening = routines.Single(r => r.RoutineKey == "evening_winddown");

        // "You are one step in" is a different thing to say than "you have not
        // begun", and different again from "done".
        evening.IsStarted.Should().BeTrue();
        evening.IsDoneToday.Should().BeFalse();
        evening.RequiredDoneToday.Should().Be(1);
        evening.StatusText.Should().Contain("so far");
    }

    [Fact]
    public async Task Completion_is_derived_from_logged_events()
    {
        var routines = await TodayAsync("brush_teeth", "skin_care");
        var evening = routines.Single(r => r.RoutineKey == "evening_winddown");

        // Two required parts logged, target of two. Nothing was stored and
        // nothing was marked — it is complete because the events exist.
        evening.IsDoneToday.Should().BeTrue();
        evening.RequiredDoneToday.Should().Be(evening.TargetPerDay);
    }

    [Fact]
    public async Task The_checklist_and_the_streak_come_from_the_same_events()
    {
        var (routine, daysSinceLast) = await ScopedAsync(async sp =>
        {
            await SeedAsync(sp, "brush_teeth", "skin_care");

            // Behaviour observes the same day the checklist just reported on.
            var observations = await sp.GetRequiredService<IBehaviourRepository>()
                .ResolveAsync(User, Today, 56, default);

            var routines = await sp.GetRequiredService<IRoutineRepository>()
                .TodayAsync(User, Today, null, default);

            var since = observations.SingleOrDefault(o =>
                o.SubjectKey == "evening_routine" && o.MeasureCode == "days_since_last");

            return (routines.Single(r => r.RoutineKey == "evening_winddown"), since);
        });

        // If these disagreed she would see a completed routine beside a broken
        // streak. They cannot: both are derived from the same logged events.
        routine.IsDoneToday.Should().BeTrue();
        daysSinceLast!.ValueNumeric.Should().Be(0m);
    }

    [Fact]
    public async Task A_deleted_event_stops_counting()
    {
        var evening = await ScopedAsync(async sp =>
        {
            await SeedAsync(sp, "brush_teeth", "skin_care");

            var factory = sp.GetRequiredService<Maren.Application.Abstractions.IDbConnectionFactory>();
            using var connection = await factory.CreateAsync(default);
            await Dapper.SqlMapper.ExecuteAsync(connection,
                "UPDATE [Timeline].[Event] SET IsDeleted = 1 WHERE UserId = @User AND EventTypeCode = 'skin_care';",
                new { User });

            var routines = await sp.GetRequiredService<IRoutineRepository>()
                .TodayAsync(User, Today, null, default);

            return routines.Single(r => r.RoutineKey == "evening_winddown");
        });

        // This is the specific way two definitions of "done" drift apart.
        evening.IsDoneToday.Should().BeFalse();
    }

    [Fact]
    public async Task Confidence_is_inherited_never_invented()
    {
        var evening = await ScopedAsync(async sp =>
        {
            await SeedAsync(sp, "brush_teeth", "skin_care");
            var routines = await sp.GetRequiredService<IRoutineRepository>()
                .TodayAsync(User, Today, null, default);
            return routines.Single(r => r.RoutineKey == "evening_winddown");
        });

        // Nothing has been observed yet — behaviour was never resolved — so the
        // routine reports no confidence rather than assuming any.
        evening.Confidence.Should().Be(0);
        evening.Consistency.Should().BeNull();
    }

    [Fact]
    public async Task The_library_reports_what_makes_a_routine_completable()
    {
        var routines = await ScopedAsync(sp =>
            sp.GetRequiredService<IRoutineRepository>().ListAsync(default));

        routines.Should().NotBeEmpty();

        // A target above the required-part count is a routine that can never be
        // completed, and on her screen it looks exactly like one she keeps
        // missing. An operator must be able to see both numbers.
        routines.Should().OnlyContain(r => r.TargetPerDay <= r.RequiredCount);
        routines.Should().OnlyContain(r => r.Steps.Count > 0);
    }

    [Fact]
    public void Her_own_routines_need_no_permission()
    {
        typeof(GetMyRoutinesQuery).Should().NotBeAssignableTo<
            Maren.Application.Behaviors.IRequirePermission>();
    }

    [Fact]
    public void The_operator_library_does_require_one()
    {
        new ListRoutinesQuery().Permission
            .Should().Be(Maren.Shared.PlatformPermissions.ContentRead);
    }

    [Fact]
    public void Nothing_in_the_routine_contract_can_declare_completion()
    {
        /*  The invariant, held at the contract boundary too. A mutable
            completion flag or a stored percentage would be a second definition
            of done, and the API is where a client would reach for one.

            Init-only accessors are fine and are what a positional record
            generates — the record is built from what was resolved. What must
            not exist is a setter that can change it afterwards, so the check is
            for a genuine setter rather than for CanWrite, which is true of
            every init property. */
        static bool IsInitOnly(System.Reflection.PropertyInfo p) =>
            p.SetMethod is not null
            && p.SetMethod.ReturnParameter.GetRequiredCustomModifiers()
                .Any(m => m.FullName == "System.Runtime.CompilerServices.IsExternalInit");

        var mutable = typeof(Maren.Contracts.RoutineToday)
            .GetProperties()
            .Where(p => p.SetMethod is { IsPublic: true } && !IsInitOnly(p))
            .ToList();

        mutable.Should().BeEmpty("a routine's state is derived, never set");

        typeof(Maren.Contracts.RoutineToday).GetProperties()
            .Should().NotContain(p => p.Name.Contains("Percent", StringComparison.Ordinal));
    }
}
