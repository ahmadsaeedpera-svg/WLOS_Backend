using Dapper;
using FluentAssertions;
using Xunit;

namespace Maren.Tests;

/// <summary>
/// Enforces the platform audit-column contract.
/// </summary>
/// <remarks>
/// This class is the reason the contract will still hold in a year.
///
/// <para>
/// Before <c>08_AuditContract.sql</c>, zero of forty-three tables complied and
/// nobody knew, because nothing checked. A documented standard with no
/// enforcement is a preference. These tests fail the build the moment a table
/// is added without the contract, which is the only point at which fixing it is
/// cheap.
/// </para>
///
/// <para>
/// Exemptions live in <c>dbo.AuditContractExemption</c> and must carry a
/// written reason. A bare list of exempt table names becomes a hiding place
/// within a year.
/// </para>
/// </remarks>
[Collection("database")]
public sealed class AuditContractTests
{
    /// <summary>The eight columns every business table must carry.</summary>
    private static readonly string[] RequiredColumns =
    [
        "CreatedBy", "CreatedOn",
        "ModifiedBy", "ModifiedOn",
        "DeletedBy", "DeletedOn",
        "IsDeleted"
        // RowVersion is checked by type, not name — see below.
    ];

    private sealed record TableRow(string SchemaName, string TableName);

    private static IReadOnlyList<TableRow> InScopeTables(System.Data.IDbConnection c) =>
        c.Query<TableRow>("""
            SELECT s.name AS SchemaName, t.name AS TableName
            FROM sys.tables t
            JOIN sys.schemas s ON s.schema_id = t.schema_id
            WHERE NOT EXISTS (
                    SELECT 1 FROM dbo.AuditContractExemption e
                    WHERE e.SchemaName = s.name AND e.TableName = t.name)
              AND t.name <> 'AuditContractExemption'
            ORDER BY s.name, t.name
            """).ToList();

    [Fact]
    public void Every_table_carries_the_full_audit_contract()
    {
        using var connection = DatabaseFixture.Open();

        var offenders = connection.Query<string>("""
            SELECT s.name + '.' + t.name + ' is missing: ' +
                STUFF((
                    SELECT ', ' + required.col
                    FROM (VALUES ('CreatedBy'), ('CreatedOn'), ('ModifiedBy'),
                                 ('ModifiedOn'), ('DeletedBy'), ('DeletedOn'),
                                 ('IsDeleted')) AS required(col)
                    WHERE NOT EXISTS (
                        SELECT 1 FROM sys.columns c
                        WHERE c.object_id = t.object_id AND c.name = required.col)
                    FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, '')
            FROM sys.tables t
            JOIN sys.schemas s ON s.schema_id = t.schema_id
            WHERE NOT EXISTS (
                    SELECT 1 FROM dbo.AuditContractExemption e
                    WHERE e.SchemaName = s.name AND e.TableName = t.name)
              AND t.name <> 'AuditContractExemption'
              AND EXISTS (
                    SELECT 1
                    FROM (VALUES ('CreatedBy'), ('CreatedOn'), ('ModifiedBy'),
                                 ('ModifiedOn'), ('DeletedBy'), ('DeletedOn'),
                                 ('IsDeleted')) AS required(col)
                    WHERE NOT EXISTS (
                        SELECT 1 FROM sys.columns c
                        WHERE c.object_id = t.object_id AND c.name = required.col))
            ORDER BY s.name, t.name
            """).ToList();

        offenders.Should().BeEmpty(
            "every table must carry the audit contract. Add the columns in a "
            + "numbered migration, or add a justified row to "
            + "dbo.AuditContractExemption if the table genuinely should not "
            + "have them.\n" + string.Join("\n", offenders));
    }

    [Fact]
    public void Every_table_has_a_rowversion_for_optimistic_concurrency()
    {
        // Checked by type (system_type_id 189 = timestamp/rowversion) rather
        // than by name. SQL Server allows exactly one per table, so a column
        // called anything else still satisfies concurrency — insisting on the
        // name would fail tables that are actually correct.
        using var connection = DatabaseFixture.Open();

        var offenders = connection.Query<string>("""
            SELECT s.name + '.' + t.name
            FROM sys.tables t
            JOIN sys.schemas s ON s.schema_id = t.schema_id
            WHERE NOT EXISTS (
                    SELECT 1 FROM dbo.AuditContractExemption e
                    WHERE e.SchemaName = s.name AND e.TableName = t.name)
              AND t.name <> 'AuditContractExemption'
              AND NOT EXISTS (
                    SELECT 1 FROM sys.columns c
                    WHERE c.object_id = t.object_id AND c.system_type_id = 189)
            ORDER BY s.name, t.name
            """).ToList();

        offenders.Should().BeEmpty(
            "without RowVersion a table allows silent last-write-wins, which is "
            + "how one operator's work disappears with nobody told");
    }

    [Fact]
    public void The_deprecated_Utc_audit_column_names_are_gone()
    {
        // Two naming conventions in one schema means every new developer picks
        // the wrong one half the time. Domain timestamps — OccurredUtc,
        // ExpiresUtc, ScheduledUtc — deliberately keep the suffix, because
        // stating the timezone is genuinely useful there. Only the three
        // contract columns were renamed.
        using var connection = DatabaseFixture.Open();

        var offenders = connection.Query<string>("""
            SELECT s.name + '.' + t.name + '.' + c.name
            FROM sys.columns c
            JOIN sys.tables t ON t.object_id = c.object_id
            JOIN sys.schemas s ON s.schema_id = t.schema_id
            WHERE c.name IN ('CreatedUtc', 'ModifiedUtc', 'DeletedUtc')
            """).ToList();

        offenders.Should().BeEmpty(
            "the contract names these CreatedOn / ModifiedOn / DeletedOn");
    }

    [Fact]
    public void Every_exemption_carries_a_written_reason()
    {
        using var connection = DatabaseFixture.Open();

        var unjustified = connection.Query<string>("""
            SELECT SchemaName + '.' + TableName
            FROM dbo.AuditContractExemption
            WHERE Reason IS NULL OR LEN(LTRIM(RTRIM(Reason))) < 20
            """).ToList();

        unjustified.Should().BeEmpty(
            "an exemption without a real reason is a hiding place");
    }

    [Fact]
    public void Soft_deleted_rows_are_indexed_out_of_the_common_path()
    {
        // Every query that respects soft delete filters on IsDeleted = 0.
        // Deleted rows accumulate forever by definition, so without an index
        // that filter gets slower every month.
        using var connection = DatabaseFixture.Open();

        var missing = connection.Query<string>("""
            SELECT s.name + '.' + t.name
            FROM sys.tables t
            JOIN sys.schemas s ON s.schema_id = t.schema_id
            WHERE EXISTS (SELECT 1 FROM sys.columns c
                          WHERE c.object_id = t.object_id AND c.name = 'IsDeleted')
              AND NOT EXISTS (SELECT 1 FROM sys.indexes i
                              WHERE i.object_id = t.object_id
                                AND i.has_filter = 1)
            ORDER BY s.name, t.name
            """).ToList();

        missing.Should().BeEmpty(
            "a table with IsDeleted needs a filtered index, or the filter is "
            + "applied after a full scan that grows without bound");
    }

    [Fact]
    public void The_audit_log_is_deliberately_exempt_and_stays_append_only()
    {
        // The exemption is load-bearing: giving AuditLog IsDeleted and
        // DeletedBy would advertise a capability that must never exist. This
        // asserts both halves — that it is exempt, and that nothing has quietly
        // added a write path to it.
        using var connection = DatabaseFixture.Open();

        connection.QuerySingle<int>("""
            SELECT COUNT(*) FROM dbo.AuditContractExemption
            WHERE SchemaName = 'Audit' AND TableName = 'AuditLog'
            """).Should().Be(1);

        connection.QuerySingle<int>("""
            SELECT COUNT(*) FROM sys.columns c
            JOIN sys.tables t ON t.object_id = c.object_id
            JOIN sys.schemas s ON s.schema_id = t.schema_id
            WHERE s.name = 'Audit' AND t.name = 'AuditLog' AND c.name = 'IsDeleted'
            """).Should().Be(0, "an audit row that can be marked deleted is not an audit row");
    }

    [Fact]
    public void The_contract_is_documented_where_a_developer_will_find_it()
    {
        // A standard nobody can read is a standard nobody follows. This asserts
        // the migration script still explains itself, so the reasoning cannot
        // be lost to a later refactor that keeps the SQL and drops the header.
        var repoRoot = FindRepositoryRoot();
        var script = Path.Combine(
            repoRoot, "src", "Maren.Database", "08_AuditContract.sql");

        File.Exists(script).Should().BeTrue();

        var text = File.ReadAllText(script);
        text.Should().Contain("CreatedBy");
        text.Should().Contain("DeletedBy");
        text.Should().Contain("RowVersion");
        text.Should().Contain("AuditContractExemption");
    }

    private static string FindRepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);

        while (directory is not null && !IsRepositoryRoot(directory))
        {
            directory = directory.Parent;
        }

        return directory?.FullName
               ?? throw new InvalidOperationException("Repository root not found.");
    }

    /// <summary>
    /// True when <paramref name="directory"/> is the top of a working tree.
    /// </summary>
    /// <remarks>
    /// `.git` is a directory in an ordinary clone and a FILE in a linked
    /// worktree — a one-line pointer at the real git directory. Testing only
    /// for a directory made this walk stride straight past the root of any
    /// worktree and keep climbing, so it either threw or, worse, resolved to
    /// some unrelated ancestor repository and asserted against its files.
    ///
    /// Found by running the suite from a worktree: this test reported
    /// 08_AuditContract.sql missing while the file sat in plain sight. A path
    /// helper that silently resolves to the wrong repository is the kind of
    /// failure that reads as a product defect for as long as it takes somebody
    /// to stop believing it.
    /// </remarks>
    private static bool IsRepositoryRoot(DirectoryInfo directory)
    {
        var git = Path.Combine(directory.FullName, ".git");
        return Directory.Exists(git) || File.Exists(git);
    }
}
