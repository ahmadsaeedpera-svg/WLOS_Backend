using System.Net;
using FluentAssertions;
using Maren.Api;
using Microsoft.Extensions.Configuration;

namespace Maren.Tests;

/// <summary>
/// The proxy configuration, and the states it must refuse.
/// </summary>
/// <remarks>
/// Unit tests rather than host tests, because what is being checked is a
/// decision made once at startup from configuration — and because the failure
/// this guards against does not look like a failure. An API behind a proxy
/// without this returns 200s all day; it simply records the proxy's address in
/// every audit row and counts every anonymous caller in one rate-limit bucket.
/// </remarks>
public sealed class ForwardedHeadersConfigurationTests
{
    private static IConfiguration Config(params (string Key, string Value)[] entries) =>
        new ConfigurationBuilder()
            .AddInMemoryCollection(entries.Select(e =>
                new KeyValuePair<string, string?>(e.Key, e.Value)))
            .Build();

    [Fact]
    public void No_proxy_section_means_the_middleware_is_not_registered()
    {
        /*  The default, and the right one for a directly-exposed Kestrel:
            X-Forwarded-For is attacker-controlled input on an open port, and
            honouring it there would let any caller pick the IP that lands in
            the audit trail. Null is how Program.cs knows not to register the
            middleware at all — not "register it with nothing trusted". */
        ForwardedHeadersConfiguration.Build(Config()).Should().BeNull();
    }

    [Fact]
    public void Disabled_means_the_middleware_is_not_registered()
    {
        var options = ForwardedHeadersConfiguration.Build(Config(
            ("Proxy:Enabled", "false"),
            ("Proxy:KnownProxies:0", "10.0.0.5")));

        options.Should().BeNull("a named proxy is not a request to trust it");
    }

    [Fact]
    public void Enabled_without_naming_a_proxy_is_refused_at_startup()
    {
        /*  The state this class exists for. Enabling forwarding without saying
            which hop to believe either does nothing — ASP.NET trusts loopback
            by default, and a proxy is rarely on loopback from inside a
            container — or, if the defaults are ever widened, hands every
            caller a free choice of audit IP and rate-limit partition.

            Both outcomes start cleanly and serve traffic, so this has to be a
            startup refusal to be noticed at all. Same reasoning as the
            signing-key length check. */
        var act = () => ForwardedHeadersConfiguration.Build(Config(
            ("Proxy:Enabled", "true")));

        act.Should().Throw<InvalidOperationException>()
            .WithMessage("*KnownProxies*KnownNetworks*");
    }

    [Fact]
    public void A_named_proxy_replaces_the_loopback_defaults()
    {
        var options = ForwardedHeadersConfiguration.Build(Config(
            ("Proxy:Enabled", "true"),
            ("Proxy:KnownProxies:0", "10.0.0.5")));

        options.Should().NotBeNull();
        options!.KnownProxies.Should().ContainSingle()
            .Which.Should().Be(IPAddress.Parse("10.0.0.5"));

        /*  Cleared, not added to. ASP.NET seeds KnownProxies with ::1 and
            KnownIPNetworks with loopback; leaving those in place would mean a
            process reachable on loopback — anything else on the same host, or
            in the same container — could forge the client address. */
        options.KnownIPNetworks.Should().BeEmpty();
    }

    [Fact]
    public void A_cidr_range_is_accepted_for_a_proxy_without_a_fixed_address()
    {
        // The case that actually arises: a container receives the connection
        // from the bridge gateway, whose address is assigned rather than
        // chosen.
        var options = ForwardedHeadersConfiguration.Build(Config(
            ("Proxy:Enabled", "true"),
            ("Proxy:KnownNetworks:0", "172.17.0.0/16")));

        options.Should().NotBeNull();
        options!.KnownIPNetworks.Should().ContainSingle();
        options.KnownIPNetworks[0].Contains(IPAddress.Parse("172.17.0.1")).Should().BeTrue();
        options.KnownIPNetworks[0].Contains(IPAddress.Parse("10.0.0.5")).Should().BeFalse();
        options.KnownProxies.Should().BeEmpty();
    }

    [Theory]
    [InlineData("Proxy:KnownProxies:0", "not-an-address")]
    [InlineData("Proxy:KnownProxies:0", "172.17.0.0/16")]
    [InlineData("Proxy:KnownNetworks:0", "172.17.0.1")]
    [InlineData("Proxy:KnownNetworks:0", "172.17.0.0/999")]
    public void A_malformed_entry_is_refused_and_named(string key, string value)
    {
        /*  Named, because the alternative is a deployment where one entry of
            several was dropped and the only symptom is that some callers'
            addresses are right and some are the proxy's. A CIDR range in
            KnownProxies and a bare address in KnownNetworks are both easy to
            write and neither is what it looks like. */
        var act = () => ForwardedHeadersConfiguration.Build(Config(
            ("Proxy:Enabled", "true"),
            (key, value)));

        act.Should().Throw<InvalidOperationException>().WithMessage($"*{value}*");
    }

    [Fact]
    public void Both_the_address_and_the_scheme_are_forwarded()
    {
        var options = ForwardedHeadersConfiguration.Build(Config(
            ("Proxy:Enabled", "true"),
            ("Proxy:KnownProxies:0", "10.0.0.5")))!;

        /*  XForwardedProto as well as XForwardedFor. Without it the app sees
            every request as http, because that is what the proxy speaks to it,
            and anything that reasons about the scheme — a redirect, a cookie
            policy, RequireHttpsMetadata — reasons from the wrong answer.
            XForwardedHost is deliberately absent: nothing here trusts the Host
            header, and forwarding it widens what a proxy misconfiguration can
            do. */
        options.ForwardedHeaders.Should().HaveFlag(
            Microsoft.AspNetCore.HttpOverrides.ForwardedHeaders.XForwardedFor);
        options.ForwardedHeaders.Should().HaveFlag(
            Microsoft.AspNetCore.HttpOverrides.ForwardedHeaders.XForwardedProto);
        options.ForwardedHeaders.Should().NotHaveFlag(
            Microsoft.AspNetCore.HttpOverrides.ForwardedHeaders.XForwardedHost);
    }

    [Fact]
    public void One_hop_unless_a_deployment_says_otherwise()
    {
        var options = ForwardedHeadersConfiguration.Build(Config(
            ("Proxy:Enabled", "true"),
            ("Proxy:KnownProxies:0", "10.0.0.5")))!;

        // Each increment is another hop whose claim about the client address
        // is taken on trust. One proxy is the deployment this repository
        // documents.
        options.ForwardLimit.Should().Be(1);

        var twoHops = ForwardedHeadersConfiguration.Build(Config(
            ("Proxy:Enabled", "true"),
            ("Proxy:KnownProxies:0", "10.0.0.5"),
            ("Proxy:ForwardLimit", "2")))!;

        twoHops.ForwardLimit.Should().Be(2);
    }
}
