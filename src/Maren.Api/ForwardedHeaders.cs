using Microsoft.AspNetCore.HttpOverrides;

namespace Maren.Api;

/// <summary>
/// Whether, and from whom, to believe <c>X-Forwarded-For</c> and
/// <c>X-Forwarded-Proto</c>.
/// </summary>
/// <remarks>
/// <para>
/// Off unless a deployment turns it on. A direct-to-Kestrel API must ignore
/// these headers entirely: they are attacker-controlled input on an open port,
/// and honouring them there lets any caller choose the IP that lands in the
/// audit trail and the bucket the rate limiter counts them in.
/// </para>
/// <para>
/// Turning it on without naming the proxy is the same mistake with extra
/// steps, so <see cref="ForwardedHeadersConfiguration.Build"/> refuses that
/// combination at startup rather than starting into it.
/// </para>
/// </remarks>
public sealed class ProxyOptions
{
    public const string SectionName = "Proxy";

    /// <summary>True when something terminates TLS in front of this API.</summary>
    public bool Enabled { get; set; }

    /// <summary>
    /// Addresses the proxy connects from. For a container behind a proxy on
    /// the host this is the bridge gateway, not loopback.
    /// </summary>
    public string[] KnownProxies { get; set; } = [];

    /// <summary>CIDR ranges, for when the proxy's address is not fixed.</summary>
    public string[] KnownNetworks { get; set; } = [];

    /// <summary>
    /// How many proxies to walk back through. One, unless there is genuinely
    /// a second one — each increment is another hop whose claim about the
    /// client address is taken on trust.
    /// </summary>
    public int ForwardLimit { get; set; } = 1;
}

/// <summary>
/// Builds <see cref="ForwardedHeadersOptions"/>, or refuses to.
/// </summary>
/// <remarks>
/// <para>
/// This exists as its own class so the dangerous states are testable without
/// standing up a host. All three of them are configuration mistakes that
/// produce a running service:
/// </para>
/// <list type="bullet">
/// <item>
/// <b>Proxy in front, middleware off.</b> Every caller appears to come from
/// the proxy. The audit trail records one address for the entire platform —
/// including the security events written on the refusal path, where the IP is
/// most of the evidence — and the rate limiter puts every anonymous caller in
/// one partition. Its comment promises that one noisy client cannot exhaust
/// the allowance for everyone, which is exactly what then happens: 300
/// requests a minute shared across all sign-ins, registrations and
/// kdf-parameters lookups, platform-wide. Nothing errors. Sign-in just starts
/// returning 429 under load that should be nothing.
/// </item>
/// <item>
/// <b>Middleware on, no proxy named.</b> ASP.NET trusts loopback by default,
/// so this usually does nothing at all — and if the defaults are widened it
/// hands every caller a free choice of audit IP and rate-limit bucket. Refused
/// here.
/// </item>
/// <item>
/// <b>Middleware on, wrong proxy named.</b> Silently ignores the header and
/// behaves exactly like the first case. Nothing distinguishes it from working
/// except looking at a recorded address, which is why the runbook says to look
/// at one on the first deployment.
/// </item>
/// </list>
/// </remarks>
public static class ForwardedHeadersConfiguration
{
    /// <summary>
    /// Returns the options, or null when no proxy is configured and the
    /// middleware should not be registered at all.
    /// </summary>
    /// <exception cref="InvalidOperationException">
    /// The section enables forwarding without naming who to trust, or names
    /// something that is not an address or a CIDR range.
    /// </exception>
    public static ForwardedHeadersOptions? Build(IConfiguration configuration)
    {
        var proxy = configuration.GetSection(ProxyOptions.SectionName)
            .Get<ProxyOptions>() ?? new ProxyOptions();

        if (!proxy.Enabled)
            return null;

        if (proxy.KnownProxies.Length == 0 && proxy.KnownNetworks.Length == 0)
        {
            throw new InvalidOperationException(
                $"{ProxyOptions.SectionName}:Enabled is true but neither "
                + $"{ProxyOptions.SectionName}:KnownProxies nor "
                + $"{ProxyOptions.SectionName}:KnownNetworks names anything. "
                + "Forwarded headers are attacker-controlled unless the hop "
                + "they arrive from is known, so this would let any caller "
                + "choose its own audit IP and rate-limit partition. Name the "
                + "proxy, or set Enabled to false.");
        }

        var options = new ForwardedHeadersOptions
        {
            ForwardedHeaders = Microsoft.AspNetCore.HttpOverrides.ForwardedHeaders.XForwardedFor
                | Microsoft.AspNetCore.HttpOverrides.ForwardedHeaders.XForwardedProto,
            ForwardLimit = proxy.ForwardLimit
        };

        /*  The defaults are loopback, and they are not what we want.

            A container behind a proxy on the host receives the connection from
            the bridge gateway — 172.17.0.1 and neighbours — so the loopback
            default trusts nobody who is actually there, drops the header, and
            leaves the deployment looking like the "middleware off" case. Clear
            them and use only what the operator named. */
        options.KnownProxies.Clear();
        options.KnownIPNetworks.Clear();

        foreach (var entry in proxy.KnownProxies)
        {
            if (!System.Net.IPAddress.TryParse(entry, out var address))
            {
                throw new InvalidOperationException(
                    $"{ProxyOptions.SectionName}:KnownProxies contains "
                    + $"'{entry}', which is not an IP address.");
            }

            options.KnownProxies.Add(address);
        }

        foreach (var entry in proxy.KnownNetworks)
        {
            /*  System.Net.IPNetwork, not the HttpOverrides one, which is
                deprecated in favour of it — and KnownIPNetworks above rather
                than KnownNetworks for the same reason. Both spellings still
                compile; only one does so without a warning. */
            if (!System.Net.IPNetwork.TryParse(entry, out var network))
            {
                throw new InvalidOperationException(
                    $"{ProxyOptions.SectionName}:KnownNetworks contains "
                    + $"'{entry}', which is not a CIDR range such as "
                    + "'172.17.0.0/16'.");
            }

            options.KnownIPNetworks.Add(network);
        }

        return options;
    }
}
