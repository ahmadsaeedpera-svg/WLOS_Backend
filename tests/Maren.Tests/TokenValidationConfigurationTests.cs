using System.Text.RegularExpressions;
using FluentAssertions;
using Maren.Infrastructure;

namespace Maren.Tests;

/// <summary>
/// Guards the one configuration mistake that turns authentication off without
/// failing, logging, or changing a single status code.
/// </summary>
/// <remarks>
/// <para>
/// <c>ValidateIssuer = true</c> with <c>ValidIssuer = null</c> does not reject
/// tokens. Microsoft.IdentityModel 8.3 <b>skips the check entirely</b> — a
/// token carrying any issuer at all is accepted, as long as the signature
/// verifies. The same is true of <c>ValidateAudience</c> and
/// <c>ValidAudience</c>. Measured, not assumed: two instances of this API were
/// started on the same signing key, one with the issuer unset and one with it
/// set to a different value, and the identical token returned 200 from the
/// first and 401 from the second.
/// </para>
/// <para>
/// That mattered because <c>Program.cs</c> read the issuer and audience twice
/// from two different places. Issuing went through <see cref="JwtOptions"/>,
/// which defaults them to <c>wlos.platform</c> / <c>wlos.app</c>; validation
/// read <c>Configuration["Jwt:Issuer"]</c> directly and got <c>null</c>
/// whenever nobody had set it. A deployment supplying a connection string and
/// a signing key and nothing else — which is every first deployment, and
/// exactly what a container with two secrets in its environment looks like —
/// therefore ran with issuer and audience validation silently disabled while
/// both flags read <c>true</c> in the source.
/// </para>
/// <para>
/// The cost is cross-environment token reuse. Any token signed with that key
/// is accepted regardless of who minted it or what it was minted for, so a
/// staging token works against production the moment the two share a key — and
/// sharing is plausible here, because the signing key is also what
/// <c>HmacKdfDecoy</c> derives the decoy-salt key from.
/// </para>
/// <para>
/// The fix is to bind <see cref="JwtOptions"/> once and use it on both sides,
/// so the two cannot disagree and neither can be null. These tests hold the
/// two halves of that: the source must not reach past the binding, and the
/// binding's defaults must not be empty.
/// </para>
/// </remarks>
public sealed class TokenValidationConfigurationTests
{
    /*  A source scan rather than a host test, deliberately.

        The defect is not observable from outside: the API starts, issues
        tokens, and answers authenticated requests correctly. Everything works.
        What is missing is a rejection that never happens, and a test can only
        see that by minting a token under a foreign issuer — which means
        standing up a second host with a second configuration, for a property
        that is decided by one line of Program.cs.

        This repository already uses the same shape elsewhere: ProcedureShapeTests
        scans sys.sql_modules for `SELECT *` rather than waiting for a DTO to
        drift. Scanning for the banned pattern is cheaper and catches it at the
        moment somebody writes it back. */
    [Fact]
    public void Program_does_not_read_jwt_issuer_or_audience_as_raw_configuration()
    {
        var source = File.ReadAllText(Path.Combine(RepositoryRoot(), "src", "Maren.Api", "Program.cs"));

        /*  Comments first. The paragraph in Program.cs that explains this
            defect quotes the banned expression, which is the right way to
            record why the line is not there — and the first run of this test
            failed on that comment. A scanner that cannot tell code from prose
            makes the explanation unwritable, and an unexplained rule is the
            one that gets removed. */
        var code = StripComments(source);

        var raw = Regex.Matches(code, """Configuration\s*\[\s*"Jwt:[A-Za-z]+"\s*\]""")
            .Select(m => m.Value)
            .ToArray();

        raw.Should().BeEmpty(
            "issuing and validating must read the same bound JwtOptions. Reading "
            + "Jwt:Issuer or Jwt:Audience straight from configuration yields null "
            + "when unset, and a null ValidIssuer does not fail — it turns the "
            + "check off, while ValidateIssuer still reads true. Found: "
            + string.Join(", ", raw));
    }

    [Fact]
    public void Jwt_defaults_are_never_empty()
    {
        /*  The whole fix rests on this. Binding a missing section produces a
            JwtOptions with these defaults, and validation is only genuinely on
            because they are non-empty strings. An "improvement" that cleared
            them to "" would restore the original defect exactly, and every
            existing test would still pass. */
        var defaults = new JwtOptions();

        defaults.Issuer.Should().NotBeNullOrWhiteSpace();
        defaults.Audience.Should().NotBeNullOrWhiteSpace();
    }

    /*  Good enough for this job and no more. It does not understand string
        literals, so a comment delimiter inside a string would confuse it —
        but the only thing being looked for afterwards is one specific indexer
        expression, and the failure mode of an over-eager strip is a false pass
        on a file nobody has written yet. If this ever guards something
        subtler, replace it with a Roslyn syntax walk. */
    private static string StripComments(string source)
    {
        source = Regex.Replace(source, @"/\*.*?\*/", string.Empty, RegexOptions.Singleline);
        source = Regex.Replace(source, @"//[^\n]*", string.Empty);
        return source;
    }

    private static string RepositoryRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);

        while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "Maren.Backend.slnx")))
            dir = dir.Parent;

        if (dir is null)
            throw new InvalidOperationException(
                "Could not find the repository root (Maren.Backend.slnx) above "
                + AppContext.BaseDirectory);

        return dir.FullName;
    }
}
