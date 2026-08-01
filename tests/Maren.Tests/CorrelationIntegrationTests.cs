using Dapper;
using FluentAssertions;
using Maren.Application;
using Maren.Application.Abstractions;
using Microsoft.Extensions.DependencyInjection;

namespace Maren.Tests;

/// <summary>
/// Correlation, end to end against a real database.
/// </summary>
/// <remarks>
/// <para>
/// The value is established once per connection in <c>SESSION_CONTEXT</c> and
/// the audit columns default from it, so an <c>INSERT</c> that omits the column
/// picks it up. That is what allowed 33 existing write sites to gain correlation
/// without one of them being edited.
/// </para>
/// <para>
/// <see cref="A_recycled_connection_does_not_inherit_a_correlation_id"/> pins an
/// assumption rather than proving our own code. A pooled connection carrying the
/// previous request's id into the next request's audit rows would read as a
/// woman's action having been part of somebody else's request, and the audit
/// trail is the thing that gets believed — so it is worth an assertion. But the
/// thing that prevents it is <c>sp_reset_connection</c>, which the pool issues
/// when handing a connection on and which already discards session context.
/// Deleting the factory's unconditional clear does <em>not</em> make this test
/// fail; that was checked. It is recorded here so nobody later reads the clear
/// as load-bearing, or this test as proof that it is.
/// </para>
/// </remarks>
[Collection("database")]
public sealed class CorrelationIntegrationTests(DatabaseFixture fixture)
{
    private async Task<T> ScopedAsync<T>(Func<IServiceProvider, Task<T>> work)
    {
        await using var scope = fixture.Provider.CreateAsyncScope();
        return await work(scope.ServiceProvider);
    }

    private static Task<Guid?> ReadSessionCorrelationAsync(IDbConnectionFactory factory) =>
        ReadSessionCorrelationCoreAsync(factory);

    private static async Task<Guid?> ReadSessionCorrelationCoreAsync(IDbConnectionFactory factory)
    {
        using var connection = await factory.CreateAsync(default);
        return await connection.ExecuteScalarAsync<Guid?>(
            new CommandDefinition("SELECT [dbo].[fn_CurrentCorrelation]();"));
    }

    // -----------------------------------------------------------------------

    [Fact]
    public async Task The_connection_carries_the_ambient_correlation_id()
    {
        var expected = Guid.NewGuid();

        var actual = await ScopedAsync(async sp =>
        {
            using (CorrelationScope.Begin(expected))
            {
                return await ReadSessionCorrelationAsync(
                    sp.GetRequiredService<IDbConnectionFactory>());
            }
        });

        actual.Should().Be(expected);
    }

    [Fact]
    public async Task A_recycled_connection_does_not_inherit_a_correlation_id()
    {
        var first = Guid.NewGuid();

        var leaked = await ScopedAsync(async sp =>
        {
            var factory = sp.GetRequiredService<IDbConnectionFactory>();

            /*  Open and close inside a correlated scope, then read again with no
                correlation at all — very likely on the same physical
                connection. If session context ever survived the pool handing it
                on, this is where it would show. */
            using (CorrelationScope.Begin(first))
            {
                (await ReadSessionCorrelationAsync(factory)).Should().Be(first);
            }

            // Now a caller with no correlation at all, very likely handed the
            // same physical connection back.
            return await ReadSessionCorrelationAsync(factory);
        });

        leaked.Should().BeNull(
            "a pooled connection must never carry one request's correlation id "
            + "into another's audit rows");
    }

    [Fact]
    public async Task Two_connections_in_one_operation_share_an_id()
    {
        var expected = Guid.NewGuid();

        var (a, b) = await ScopedAsync(async sp =>
        {
            var factory = sp.GetRequiredService<IDbConnectionFactory>();
            using (CorrelationScope.Begin(expected))
            {
                /*  One request writes audit rows on the ambient connection and a
                    security event on its own — deliberately, so a rollback
                    cannot erase the record of the attempt that caused it. Both
                    must land under the same id or the two records cannot be
                    joined, which was the whole problem. */
                var one = await ReadSessionCorrelationAsync(factory);
                var two = await ReadSessionCorrelationAsync(factory);
                return (one, two);
            }
        });

        a.Should().Be(expected);
        b.Should().Be(expected);
    }

    [Fact]
    public async Task An_audit_row_written_without_the_column_is_correlated()
    {
        var correlationId = Guid.NewGuid();
        var actor = Guid.NewGuid();

        var stored = await ScopedAsync(async sp =>
        {
            var factory = sp.GetRequiredService<IDbConnectionFactory>();

            using (CorrelationScope.Begin(correlationId))
            {
                using var connection = await factory.CreateAsync(default);

                /*  The column is omitted, exactly as all 33 existing audit
                    write sites omit it. Nothing here mentions correlation. */
                await connection.ExecuteAsync(new CommandDefinition("""
                    INSERT INTO [Audit].[AuditLog]
                        (OccurredUtc, ActorUserId, ActorKind, [Action],
                         EntityType, EntityId)
                    VALUES
                        (SYSUTCDATETIME(), @Actor, 'system', 'correlation.probe',
                         'Probe', @Marker);
                    """,
                    new { Actor = actor, Marker = correlationId.ToString() }));

                return await connection.ExecuteScalarAsync<Guid?>(
                    new CommandDefinition(
                        "SELECT CorrelationId FROM [Audit].[AuditLog] WHERE EntityId = @Marker;",
                        new { Marker = correlationId.ToString() }));
            }
        });

        stored.Should().Be(correlationId,
            "the default reads SESSION_CONTEXT, so an unmodified write site "
            + "gains correlation without being edited");

        await ScopedAsync(async sp =>
        {
            var factory = sp.GetRequiredService<IDbConnectionFactory>();
            using var connection = await factory.CreateAsync(default);
            await connection.ExecuteAsync(new CommandDefinition(
                "DELETE FROM [Audit].[AuditLog] WHERE EntityId = @Marker;",
                new { Marker = correlationId.ToString() }));
            return 0;
        });
    }

    [Fact]
    public async Task Without_correlation_the_row_is_null_not_invented()
    {
        var id = Guid.NewGuid();
        var actor = Guid.NewGuid();

        var stored = await ScopedAsync(async sp =>
        {
            var factory = sp.GetRequiredService<IDbConnectionFactory>();
            using var connection = await factory.CreateAsync(default);

            await connection.ExecuteAsync(new CommandDefinition("""
                INSERT INTO [Audit].[AuditLog]
                    (OccurredUtc, ActorUserId, ActorKind, [Action],
                     EntityType, EntityId)
                VALUES
                    (SYSUTCDATETIME(), @Actor, 'system', 'correlation.probe',
                     'Probe', @Marker);
                """, new { Actor = actor, Marker = id.ToString() }));

            var value = await connection.ExecuteScalarAsync<Guid?>(
                new CommandDefinition(
                    "SELECT CorrelationId FROM [Audit].[AuditLog] WHERE EntityId = @Marker;",
                    new { Marker = id.ToString() }));

            await connection.ExecuteAsync(new CommandDefinition(
                "DELETE FROM [Audit].[AuditLog] WHERE EntityId = @Marker;",
                new { Marker = id.ToString() }));

            return value;
        });

        /*  Unknown, never invented. An uncorrelated row is honest; one stamped
            with a manufactured id would be indistinguishable from a real trail
            and would be trusted. */
        stored.Should().BeNull();
    }
}
