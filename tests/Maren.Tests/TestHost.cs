using System.Data;
using Dapper;
using Maren.Application.Abstractions;
using Maren.Application.Behaviors;
using Maren.Application.Content;
using FluentValidation;
using Maren.Infrastructure;
using Maren.Persistence;
using MediatR;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace Maren.Tests;

/// <summary>
/// A caller whose identity and permissions the test controls.
/// </summary>
public sealed class FakeCurrentUser : ICurrentUser
{
    public Guid? UserId { get; set; } = Guid.Parse("11111111-1111-1111-1111-111111111111");
    public string? IpAddress => "127.0.0.1";
    public string? UserAgent => "Maren.Tests";
    public IReadOnlyList<string> Permissions { get; set; } = [];
    public bool Has(string permission) => Permissions.Contains(permission);

    /// <summary>Grants everything — for tests not about authorization.</summary>
    public FakeCurrentUser WithAllPermissions()
    {
        Permissions = Maren.Shared.PlatformPermissions.All.ToList();
        return this;
    }

    public FakeCurrentUser With(params string[] permissions)
    {
        Permissions = permissions;
        return this;
    }
}

/// <summary>
/// A real container over the real database.
/// </summary>
/// <remarks>
/// Deliberately not an in-memory substitute. Every rule that matters in this
/// system — the approval gate, the version pointer, the language fallback, the
/// country filter — lives in a stored procedure. A test suite that mocks the
/// repository verifies the mocks and tells you nothing about whether an editor
/// can publish something nobody approved.
///
/// <para>
/// Each test class gets its own scope and its own key prefix, and deletes its
/// own rows on the way in, so the suite is re-runnable and order-independent.
/// </para>
/// </remarks>
public sealed class DatabaseFixture : IAsyncLifetime
{
    /// <summary>Where the tests find SQL Server.</summary>
    /// <remarks>
    /// Environment first so CI can point at its own service container, falling
    /// back to LocalDB so a developer needs no setup. Hardcoding LocalDB meant
    /// the suite could only ever run on a Windows machine that had it — which
    /// is a large part of why nothing ran these tests automatically.
    /// <para>
    /// The key must stay in step with what <c>AddMarenPersistence</c> resolves,
    /// which is <c>WlosPlatform</c>. When the fork renamed the key this file
    /// kept the old one, so every integration test failed at container build
    /// with "Connection string 'WlosPlatform' is not configured" — the whole
    /// suite was red for a reason that had nothing to do with anything under
    /// test. The old variable is still read so an existing shell or CI
    /// definition does not silently fall through to LocalDB instead.
    /// </para>
    /// </remarks>
    public static readonly string ConnectionString =
        Environment.GetEnvironmentVariable("ConnectionStrings__WlosPlatform")
        ?? Environment.GetEnvironmentVariable("ConnectionStrings__MarenPlatform")
        ?? @"Server=(localdb)\MSSQLLocalDB;Database=WlosPlatform;"
           + "Trusted_Connection=True;TrustServerCertificate=True;"
           // Pooling off in the test harness only. The delta cursor reads
           // @@DBTS, which is sensitive to connection state that pooling can
           // carry between operations in a fast in-process suite; a pooled
           // connection returned mid-settle intermittently hid a just-committed
           // row from the following read. Production keeps pooling — it gets a
           // fresh DI scope and connection per HTTP request, and the delta is
           // verified correct 8/8 over real HTTP.
           + "Pooling=False;MultipleActiveResultSets=True";

    public ServiceProvider Provider { get; }
    public FakeCurrentUser CurrentUser { get; } = new();

    public DatabaseFixture()
    {
        var services = new ServiceCollection();

        services.AddSingleton<IConfiguration>(
            new ConfigurationBuilder().AddInMemoryCollection(
                new Dictionary<string, string?>
                {
                    ["ConnectionStrings:WlosPlatform"] = ConnectionString,

                    /*  A signing key for the token service, which validates its
                        own length at construction. Test-only and obviously so:
                        the production key comes from the environment and the
                        API refuses to start without one. */
                    ["Jwt:SigningKey"] =
                        "test-only-signing-key-not-a-secret-0123456789",
                    ["Jwt:Issuer"] = "wlos.platform",
                    ["Jwt:Audience"] = "wlos.app"
                }).Build());

        services.Configure<JwtOptions>(o =>
        {
            o.SigningKey = "test-only-signing-key-not-a-secret-0123456789";
            o.Issuer = "wlos.platform";
            o.Audience = "wlos.app";
        });

        services.AddLogging(b => b.SetMinimumLevel(LogLevel.Warning));
        services.AddSingleton<ICurrentUser>(CurrentUser);
        services.AddMarenPersistence();

        /*  The password hasher and the token service.

            Absent until Slice 1, which is why no test in this suite had ever
            registered, signed in or signed out: resolving RegisterHandler threw
            on IPasswordHasher before it reached a single assertion. The auth
            path was the one part of the platform with no integration coverage
            at all, and the reason was three missing lines here. */
        services.AddMarenInfrastructure();

        services.AddMarenCaching();
        services.AddMarenSecurityStamps();

        services.AddMediatR(cfg =>
        {
            cfg.RegisterServicesFromAssembly(typeof(SaveContentCommand).Assembly);
            cfg.AddOpenBehavior(typeof(LoggingBehavior<,>));
            cfg.AddOpenBehavior(typeof(AuthorizationBehavior<,>));
            cfg.AddOpenBehavior(typeof(FeatureFlagBehavior<,>));
            cfg.AddOpenBehavior(typeof(ValidationBehavior<,>));
            cfg.AddOpenBehavior(typeof(CachingBehavior<,>));
            cfg.AddOpenBehavior(typeof(TransactionBehavior<,>));
        });

        services.AddValidatorsFromAssemblyContaining<SaveContentValidator>();

        Provider = services.BuildServiceProvider();
    }

    public IServiceScope Scope() => Provider.CreateScope();

    public static IDbConnection Open()
    {
        var connection = new SqlConnection(ConnectionString);
        connection.Open();
        return connection;
    }

    /// <summary>Removes anything a previous run of this suite left behind.</summary>
    public static void CleanUp(string keyPrefix)
    {
        using var connection = Open();
        // Children first, then the parent. ContentTag is deliberately absent:
        // it is the tag dictionary shared across all content, not a child of
        // an item — ContentItemTag is the join. Deleting from it would remove
        // tags belonging to rows this suite never created.
        // Approvals before versions: ContentApproval names the exact version it
        // approved, so the version cannot go first.
        connection.Execute("""
            DELETE ca FROM [Content].[ContentApproval] ca
            JOIN [Content].[ContentItem] ci ON ci.ContentItemId = ca.ContentItemId
            WHERE ci.[Key] LIKE @Pattern;

            UPDATE ci SET PublishedVersionId = NULL
            FROM [Content].[ContentItem] ci
            WHERE ci.[Key] LIKE @Pattern;

            DELETE cv FROM [Content].[ContentVersion] cv
            JOIN [Content].[ContentItem] ci ON ci.ContentItemId = cv.ContentItemId
            WHERE ci.[Key] LIKE @Pattern;

            DELETE cr FROM [Content].[ContentReview] cr
            JOIN [Content].[ContentItem] ci ON ci.ContentItemId = cr.ContentItemId
            WHERE ci.[Key] LIKE @Pattern;

            DELETE ct FROM [Content].[ContentTranslation] ct
            JOIN [Content].[ContentItem] ci ON ci.ContentItemId = ct.ContentItemId
            WHERE ci.[Key] LIKE @Pattern;

            DELETE cs FROM [Content].[ContentPublishSchedule] cs
            JOIN [Content].[ContentItem] ci ON ci.ContentItemId = cs.ContentItemId
            WHERE ci.[Key] LIKE @Pattern;

            DELETE cit FROM [Content].[ContentItemTag] cit
            JOIN [Content].[ContentItem] ci ON ci.ContentItemId = cit.ContentItemId
            WHERE ci.[Key] LIKE @Pattern;

            DELETE FROM [Content].[ContentItem] WHERE [Key] LIKE @Pattern;
            """, new { Pattern = keyPrefix + "%" }, commandTimeout: 60);
    }

    public Task InitializeAsync() => Task.CompletedTask;

    /*  Disposed asynchronously, and this is not a style preference.

        The container holds SqlUnitOfWork, which implements IAsyncDisposable and
        not IDisposable - the same rule CLAUDE.md section 7 states for scopes.
        Calling the synchronous Provider.Dispose() on a container holding an
        async-only disposable throws InvalidOperationException, which xUnit
        reported as a collection cleanup failure while still printing
        "Passed! 127".

        That combination is why it survived: the summary line looked green, but
        dotnet test exited non-zero, so the CI integration-test step would have
        failed even once the build was fixed. Implementing IAsyncLifetime only -
        not IDisposable as well - matters, because xUnit would call both and the
        synchronous path would throw again. */
    public async Task DisposeAsync() => await Provider.DisposeAsync();
}

[CollectionDefinition("database")]
public sealed class DatabaseCollection : ICollectionFixture<DatabaseFixture>;
