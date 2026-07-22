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
public sealed class DatabaseFixture : IDisposable
{
    public const string ConnectionString =
        "Server=(localdb)\\MSSQLLocalDB;Database=MarenPlatform;" +
        "Trusted_Connection=True;TrustServerCertificate=True;" +
        "MultipleActiveResultSets=True";

    public ServiceProvider Provider { get; }
    public FakeCurrentUser CurrentUser { get; } = new();

    public DatabaseFixture()
    {
        var services = new ServiceCollection();

        services.AddSingleton<IConfiguration>(
            new ConfigurationBuilder().AddInMemoryCollection(
                new Dictionary<string, string?>
                {
                    ["ConnectionStrings:MarenPlatform"] = ConnectionString
                }).Build());

        services.AddLogging(b => b.SetMinimumLevel(LogLevel.Warning));
        services.AddSingleton<ICurrentUser>(CurrentUser);
        services.AddMarenPersistence();
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

    public void Dispose() => Provider.Dispose();
}

[CollectionDefinition("database")]
public sealed class DatabaseCollection : ICollectionFixture<DatabaseFixture>;
