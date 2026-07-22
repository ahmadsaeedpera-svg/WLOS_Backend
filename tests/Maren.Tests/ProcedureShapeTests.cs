using Dapper;
using FluentAssertions;
using Maren.Contracts;
using Xunit;

namespace Maren.Tests;

/// <summary>
/// Asserts that procedures returning a result set return exactly the columns
/// their DTO expects.
/// </summary>
/// <remarks>
/// This class exists because three endpoints shipped broken in the same way and
/// nothing caught any of them.
///
/// <para>
/// Dapper materialises a positional C# record by matching the result set to the
/// constructor. A procedure written as <c>SELECT *</c> returns every column the
/// table has, including audit and concurrency columns the DTO deliberately
/// omits, and the call throws at runtime — not at build time, and not in any
/// test that mocks the repository. <c>usp_FeatureFlag_Upsert</c>,
/// <c>usp_Content_SaveAuthor</c> and <c>usp_Media_Save</c> all returned
/// 500 on every request they ever served.
/// </para>
///
/// <para>
/// Executing each procedure for real is the only check that would have caught
/// it, so that is what these do.
/// </para>
/// </remarks>
[Collection("database")]
public sealed class ProcedureShapeTests
{
    [Fact]
    public void FeatureFlag_upsert_materialises_its_dto()
    {
        using var connection = DatabaseFixture.Open();

        var result = connection.QuerySingle<FeatureFlagAdminDto>(
            "[Administration].[usp_FeatureFlag_Upsert]",
            new
            {
                Key = "test_shape_probe",
                Name = "Shape probe",
                Description = "Written by the test suite.",
                IsEnabled = false,
                RolloutPercent = (byte)0,
                MinAppVersion = (string?)null,
                CountryFilter = (string?)null,
                RequiresPremium = false,
                BetaOnly = false,
                DefaultValue = false,
                ActorUserId = (Guid?)null,
            },
            commandType: System.Data.CommandType.StoredProcedure);

        result.Key.Should().Be("test_shape_probe");
        result.Name.Should().Be("Shape probe");

        // Otherwise it appears in the admin portal's flag list as a real flag
        // that nothing reads.
        connection.Execute(
            "DELETE FROM [Administration].[FeatureFlag] WHERE [Key] = @Key",
            new { Key = "test_shape_probe" });
    }

    [Fact]
    public void Content_author_save_materialises_its_dto()
    {
        using var connection = DatabaseFixture.Open();

        var result = connection.QuerySingle<ContentAuthorDto>(
            "[Content].[usp_Content_SaveAuthor]",
            new
            {
                AuthorId = (Guid?)null,
                UserId = (Guid?)null,
                DisplayName = "Shape probe author",
                Credentials = "RM",
                Bio = (string?)null,
                ActorUserId = (Guid?)null,
            },
            commandType: System.Data.CommandType.StoredProcedure);

        result.DisplayName.Should().Be("Shape probe author");

        connection.Execute(
            "DELETE FROM [Content].[ContentAuthor] WHERE AuthorId = @AuthorId",
            new { result.AuthorId });
    }

    [Fact]
    public void Media_save_materialises_its_dto()
    {
        using var connection = DatabaseFixture.Open();

        var result = connection.QuerySingle<MediaDto>(
            "[Content].[usp_Media_Save]",
            new
            {
                MediaId = (Guid?)null,
                FileName = "shape-probe.png",
                ContentType = "image/png",
                SizeBytes = 1024L,
                StorageKey = "media/shape-probe.png",
                Width = 100,
                Height = 100,
                AltText = "A probe",
                ActorUserId = (Guid?)null,
            },
            commandType: System.Data.CommandType.StoredProcedure);

        result.FileName.Should().Be("shape-probe.png");

        connection.Execute(
            "DELETE FROM [Content].[Media] WHERE MediaId = @MediaId",
            new { result.MediaId });
    }

    [Fact]
    public void No_procedure_returns_an_unbounded_result_set()
    {
        // A guard against the pattern coming back. SELECT * inside a subquery
        // or a FOR JSON expression is fine — it never becomes a result set —
        // so this only looks at statements that would return one to a caller.
        using var connection = DatabaseFixture.Open();

        var offenders = connection.Query<string>("""
            SELECT o.name
            FROM sys.sql_modules m
            JOIN sys.objects o ON o.object_id = m.object_id
            WHERE o.type = 'P'
              AND m.definition LIKE '%SELECT [*] FROM%'
              AND m.definition NOT LIKE '%(SELECT [*] FROM%'
            """).ToList();

        offenders.Should().BeEmpty(
            "a procedure whose result set is SELECT * breaks the moment a "
            + "column is added to the table");
    }
}
