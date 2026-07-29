using FluentAssertions;
using Maren.Application.Behaviour;
using Maren.Application.Predicting;
using Maren.Contracts;
using Microsoft.Extensions.DependencyInjection;

namespace Maren.Tests;

/// <summary>
/// The Prediction Platform, end to end against a real database.
/// </summary>
/// <remarks>
/// A prediction is framed, never computed. These assertions hold that: the
/// probability equals the behaviour measure it came from to the point, given
/// nothing observed it says nothing, every statement carries its window and its
/// support, no placeholder reaches her unfilled, and nothing said is clinical.
/// </remarks>
[Collection("database")]
public sealed class PredictionIntegrationTests(DatabaseFixture fixture)
{
    private static readonly Guid Steady = Guid.Parse("000000E7-0000-0000-0000-0000000000AA");
    private static readonly Guid Quiet = Guid.Parse("000000E7-0000-0000-0000-0000000000BB");
    private static readonly DateOnly Today = DateOnly.FromDateTime(DateTime.UtcNow);

    private async Task<T> ScopedAsync<T>(Func<IServiceProvider, Task<T>> work)
    {
        await using var scope = fixture.Provider.CreateAsyncScope();
        return await work(scope.ServiceProvider);
    }

    /*  Steady logs water on most days for a month, which is enough history for
        the probability measures to be produced at all. Quiet logs nothing, and
        exists to prove the engine stays silent rather than reaching for a
        default. */
    private static async Task SeedAsync(IServiceProvider sp)
    {
        var factory = sp.GetRequiredService<Maren.Application.Abstractions.IDbConnectionFactory>();
        using var connection = await factory.CreateAsync(default);

        await Dapper.SqlMapper.ExecuteAsync(connection, """
            DELETE FROM [Predict].[Predicted]     WHERE UserId IN (@Steady, @Quiet);
            DELETE FROM [Behaviour].[Observation] WHERE UserId IN (@Steady, @Quiet);
            DELETE FROM [Timeline].[Event]        WHERE UserId IN (@Steady, @Quiet);
            DELETE FROM [Identity].[User]         WHERE UserId IN (@Steady, @Quiet);

            INSERT INTO [Identity].[User] (UserId, Email, NormalisedEmail,
                PasswordHash, PasswordSalt, PasswordIterations, SecurityStamp)
            VALUES (@Steady, 'predict-a@example.com', 'PREDICT-A@EXAMPLE.COM',
                    0x00, 0x00, 210000, NEWID()),
                   (@Quiet,  'predict-b@example.com', 'PREDICT-B@EXAMPLE.COM',
                    0x00, 0x00, 210000, NEWID());

            /*  Every day but every fourth, so the observed rate is neither 0 nor
                1 and the clamp is not what is being measured. */
            DECLARE @i INT = 0, @d DATE;
            WHILE @i < 32
            BEGIN
                SET @d = DATEADD(DAY, -@i, @Today);
                IF @i % 4 <> 0
                    INSERT [Timeline].[Event] (EventId, UserId, EventTypeCode,
                        OccurredUtc, OccurredLocalDate, RecordedUtc, [Source], ValueNumeric)
                    VALUES (NEWID(), @Steady, 'water',
                            DATEADD(HOUR, 14, CAST(@d AS DATETIME2(3))), @d,
                            SYSUTCDATETIME(), 'manual', 250);
                SET @i = @i + 1;
            END
            """,
            new { Steady, Quiet, Today = Today.ToDateTime(TimeOnly.MinValue) });
    }

    /*  Behaviour, then prediction — the order the pipeline runs them in, because
        prediction frames what behaviour published. */
    private Task<IReadOnlyList<Prediction>> ResolveAsync(Guid userId) =>
        ScopedAsync(async sp =>
        {
            await SeedAsync(sp);
            await sp.GetRequiredService<IBehaviourRepository>()
                    .ResolveAsync(userId, Today, 56, default);
            return await sp.GetRequiredService<IPredictionRepository>()
                           .ResolveAsync(userId, Today, default);
        });

    // -----------------------------------------------------------------------

    [Fact]
    public async Task It_frames_what_behaviour_observed()
    {
        var predictions = await ResolveAsync(Steady);

        predictions.Should().NotBeEmpty();
        predictions.Should().Contain(p => p.PredictionKey == "habit_continuation");
        predictions.Should().OnlyContain(p => p.SubjectKey.Length > 0);
    }

    [Fact]
    public async Task The_probability_is_the_behaviour_measure_never_a_new_one()
    {
        var (predictions, observations) = await ScopedAsync(async sp =>
        {
            await SeedAsync(sp);
            var b = await sp.GetRequiredService<IBehaviourRepository>()
                            .ResolveAsync(Steady, Today, 56, default);
            var p = await sp.GetRequiredService<IPredictionRepository>()
                            .ResolveAsync(Steady, Today, default);
            return (p, b);
        });

        predictions.Should().NotBeEmpty();

        /*  The assertion the whole engine rests on. If a prediction ever
            adjusts, blends or re-derives a probability, this is where it shows
            — and it would show as the platform telling a woman something about
            herself that the one place that observes her never said. */
        foreach (var prediction in predictions)
        {
            var source = observations.Single(o =>
                o.SubjectKey == prediction.SubjectKey &&
                o.MeasureCode == prediction.SourceMeasureCode);

            source.Family.Should().Be("probability");
            source.ValueNumeric.Should().NotBeNull();

            /*  AwayFromZero because that is what T-SQL ROUND does, and .NET's
                default is banker's rounding. They disagree on exactly the
                midpoints — an observed 0.325 is 33% on the server and 32% in
                .NET — which is why the percent is computed once, server-side,
                and shipped rather than re-derived. A client that recomputed it
                would show a woman a different number from the one in her
                statement text. This assertion is written to match the server on
                purpose; it caught the mismatch rather than papering over it. */
            prediction.ProbabilityPercent.Should()
                .Be((int)Math.Round(source.ValueNumeric!.Value * 100, 0,
                                    MidpointRounding.AwayFromZero));
            prediction.Confidence.Should().Be(source.Confidence);
            prediction.SupportDays.Should().Be(source.SpanDays);
        }
    }

    [Fact]
    public async Task With_nothing_observed_it_predicts_nothing()
    {
        var predictions = await ResolveAsync(Quiet);

        /*  The strongest statement of what this engine is. It has no source of
            numbers other than what behaviour observed, so a woman who has logged
            nothing is told nothing rather than given a default. */
        predictions.Should().BeEmpty();
    }

    [Fact]
    public async Task Every_statement_carries_its_window_and_its_support()
    {
        var predictions = await ResolveAsync(Steady);

        predictions.Should().NotBeEmpty();

        /*  A bare percentage reads as knowledge and is a summary of a few weeks.
            The schema refuses a framing that drops either; this is the same
            guarantee observed from outside, on the text she would actually
            read. */
        foreach (var prediction in predictions)
        {
            prediction.WindowDays.Should().BeGreaterThan(0);
            prediction.SupportDays.Should().BeGreaterThan(0);
            prediction.Confidence.Should().BeGreaterThan(0);
            prediction.Evidence.Should().NotBeEmpty();

            prediction.StatementText.Should()
                .Contain(prediction.ProbabilityPercent + "%");
            prediction.StatementText.Should()
                .Contain(prediction.SupportDays + " day");
        }
    }

    [Fact]
    public async Task No_placeholder_reaches_her_unfilled()
    {
        var predictions = await ResolveAsync(Steady);

        // A pattern with a typo would otherwise ship "{suport}" to a woman.
        predictions.Should().OnlyContain(p => !p.StatementText.Contains('{'));
        predictions.Should().OnlyContain(p => !p.StatementText.Contains('}'));
    }

    [Fact]
    public async Task Nothing_predicted_is_clinical_or_certain()
    {
        var predictions = await ResolveAsync(Steady);

        predictions.Should().NotBeEmpty();

        /*  Behavioural only. A number about the future sounds like knowledge,
            which is exactly why the vocabulary is policed here as well as in
            SQL. */
        string[] banned =
            ["you will", "guarantee", "certain", "diagnos", "symptom",
             "treat", "risk of", "causes", "you should", "you must"];

        foreach (var prediction in predictions)
        {
            foreach (var word in banned)
                prediction.StatementText.ToLowerInvariant()
                    .Should().NotContain(word);
        }
    }

    [Fact]
    public async Task Evidence_resolves_to_the_observation_behind_it()
    {
        var predictions = await ResolveAsync(Steady);

        predictions.Should().NotBeEmpty();

        foreach (var prediction in predictions)
            prediction.Evidence.Should().Contain(
                "behaviour:" + prediction.SubjectKey + "." + prediction.SourceMeasureCode);
    }

    [Fact]
    public async Task Reading_returns_what_framing_produced()
    {
        var (resolved, read) = await ScopedAsync(async sp =>
        {
            await SeedAsync(sp);
            await sp.GetRequiredService<IBehaviourRepository>()
                    .ResolveAsync(Steady, Today, 56, default);
            var repository = sp.GetRequiredService<IPredictionRepository>();
            var r = await repository.ResolveAsync(Steady, Today, default);
            var g = await repository.GetAsync(Steady, Today, default);
            return (r, g);
        });

        read.Select(p => p.PredictionKey + '|' + p.SubjectKey)
            .Should().BeEquivalentTo(
                resolved.Select(p => p.PredictionKey + '|' + p.SubjectKey));

        foreach (var stored in read)
        {
            var source = resolved.Single(p =>
                p.PredictionKey == stored.PredictionKey &&
                p.SubjectKey == stored.SubjectKey);

            stored.ProbabilityPercent.Should().Be(source.ProbabilityPercent);
            stored.StatementText.Should().Be(source.StatementText);
            stored.SupportDays.Should().Be(source.SupportDays);
        }
    }

    [Fact]
    public async Task Every_prediction_type_frames_a_probability()
    {
        var types = await ScopedAsync(sp =>
            sp.GetRequiredService<IPredictionRepository>().ListTypesAsync(default));

        types.Should().NotBeEmpty();

        /*  The foreign key guarantees this; stating it here means a client
            reading the catalogue can rely on it too. */
        types.Should().OnlyContain(t => t.SourceFamily == "probability");
        types.Should().OnlyContain(t => t.FramingPattern.Contains("{chance}"));
        types.Should().OnlyContain(t => t.FramingPattern.Contains("{window}"));
        types.Should().OnlyContain(t => t.FramingPattern.Contains("{support}"));
    }

    [Fact]
    public async Task The_simulator_explains_what_it_withholds()
    {
        var response = await ScopedAsync(sp =>
            sp.GetRequiredService<IPredictionRepository>().SimulateAsync(
                "hydration.completion_probability=0.7@21," +
                "hydration.engagement_probability=0.8@9",
                90, 28, default));

        // The one that had enough behind it.
        response.Predictions.Should().ContainSingle();
        response.Predictions[0].PredictionKey.Should().Be("habit_continuation");
        response.Predictions[0].ProbabilityPercent.Should().Be(70);

        /*  And the one that did not, with a reason. "Nothing appeared" and
            "withheld on purpose" are different facts, and an operator who
            cannot tell them apart eventually lowers a floor to make the screen
            look busier. */
        var withheld = response.Considered.Single(c =>
            c.PredictionKey == "engagement" && c.SubjectKey == "hydration");

        withheld.IsPredicted.Should().BeFalse();
        withheld.WasSupplied.Should().BeTrue();
        withheld.Explanation.Should().Contain("9 days of history");

        // Including the type nothing was supplied for at all.
        var absent = response.Considered.Single(c => c.PredictionKey == "dropoff");
        absent.WasSupplied.Should().BeFalse();
        absent.Explanation.Should().Contain("Nothing was observed");
    }

    [Fact]
    public async Task The_simulator_never_touches_a_real_account()
    {
        var response = await ScopedAsync(sp =>
            sp.GetRequiredService<IPredictionRepository>().SimulateAsync(
                "hydration.completion_probability=0.7@21", 90, 28, default));

        /*  Nothing simulated is attributed, because nothing was stored. The
            account-free property itself is asserted in SQL against every
            inspector procedure; this is the consequence a client can see. */
        response.Predictions.Should().OnlyContain(p => p.EngineVersion == "simulated");
    }
}
