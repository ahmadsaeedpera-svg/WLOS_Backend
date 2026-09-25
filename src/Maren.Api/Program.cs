using System.Globalization;
using System.Security.Claims;
using System.Threading.RateLimiting;
using System.Text;
using FluentValidation;
using Maren.Application;
using Maren.Application.Abstractions;
using Maren.Application.Auth;
using Maren.Application.Behaviors;
using Maren.Infrastructure;
using Maren.Api;
using Maren.Persistence;
using Maren.Shared;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using Scalar.AspNetCore;
using Serilog;

/*  The container health probe, before anything else is built.

    This must come first. The Dockerfile has always declared
    `dotnet Maren.Api.dll --healthcheck` as its HEALTHCHECK, and nothing
    implemented it — the argument fell through to the host builder, which
    ignored it and started a second complete API inside the container every
    thirty seconds. Returning here means the probe is a short-lived HTTP client
    and not a web host. */
if (args.Contains(HealthProbe.Flag))
    return await HealthProbe.RunAsync(args);

var builder = WebApplication.CreateBuilder(args);

Log.Logger = new LoggerConfiguration()
    .Enrich.FromLogContext()
    // Invariant culture: a log parsed by an aggregator must not change
    // shape with the host's locale.
    .WriteTo.Console(formatProvider: CultureInfo.InvariantCulture)
    .CreateLogger();

builder.Host.UseSerilog();

builder.Services.Configure<JwtOptions>(
    builder.Configuration.GetSection(JwtOptions.SectionName));

builder.Services.AddMarenPersistence();
builder.Services.AddMarenInfrastructure();

builder.Services.AddMarenCaching();
builder.Services.AddMarenSecurityStamps();

builder.Services.AddMediatR(cfg =>
{
    cfg.RegisterServicesFromAssembly(typeof(RegisterCommand).Assembly);

    // Order matters and runs outermost first. Logging wraps everything so a
    // rejected request still appears in the log; authorization runs before
    // validation so an unauthorised caller learns nothing about which fields
    // were wrong; the transaction opens last so it is held for the shortest
    // possible time.
    cfg.AddOpenBehavior(typeof(LoggingBehavior<,>));
    cfg.AddOpenBehavior(typeof(AuthorizationBehavior<,>));
    cfg.AddOpenBehavior(typeof(FeatureFlagBehavior<,>));
    cfg.AddOpenBehavior(typeof(ValidationBehavior<,>));
    cfg.AddOpenBehavior(typeof(CachingBehavior<,>));
    cfg.AddOpenBehavior(typeof(TransactionBehavior<,>));
});

builder.Services.AddValidatorsFromAssembly(typeof(RegisterCommand).Assembly);

builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<ICurrentUser, HttpCurrentUser>();

/*  Correlation. Singleton because SqlConnectionFactory is one, and safe as a
    singleton because both sources it reads are ambient per-operation rather
    than captured state. */
builder.Services.AddSingleton<IHttpCorrelationSource, HttpCorrelationSource>();
builder.Services.AddSingleton<ICorrelationContext, CorrelationContext>();

/*  Bound once, and used for both issuing and validating.

    The issuer the API *stamps* on a token and the issuer it *accepts* used to
    come from two different places. Issuing goes through JwtOptions, which
    defaults Issuer to "wlos.platform"; validation read Configuration["Jwt:Issuer"]
    directly and got null whenever nobody set it.

    A null ValidIssuer does not reject anything. IdentityModel 8.3 skips the
    check entirely — any issuer is accepted so long as the signature verifies —
    while ValidateIssuer above still reads true. ValidateAudience is the same.
    So a deployment supplying a connection string and a signing key and nothing
    else, which is what a container with two secrets in its environment looks
    like, ran with both checks off and no symptom of any kind: it starts, it
    issues tokens, it answers authenticated requests correctly. The only thing
    missing is a refusal that never happens.

    What that costs is cross-environment token reuse: any token signed with the
    key is accepted whoever minted it and whatever it was minted for. Sharing a
    key between environments is plausible here, because this same key is what
    HmacKdfDecoy derives the decoy-salt key from.

    Binding once removes the possibility. The two sides cannot disagree because
    there is only one side, and it is never null.
    TokenValidationConfigurationTests holds both halves of that. */
var jwt = builder.Configuration
    .GetSection(JwtOptions.SectionName)
    .Get<JwtOptions>() ?? new JwtOptions();

var signingKey = jwt.SigningKey;
if (string.IsNullOrWhiteSpace(signingKey) || signingKey.Length < 32)
{
    // Fail at startup rather than at first request. A short or missing signing
    // key produces tokens anyone can forge, and discovering that in production
    // is discovering it too late.
    throw new InvalidOperationException(
        "Jwt:SigningKey must be configured and at least 32 characters.");
}

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = jwt.Issuer,
            ValidAudience = jwt.Audience,
            IssuerSigningKey = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(signingKey)),
            // No grace period. The default five minutes is a meaningful
            // extension of a fifteen-minute token's life.
            ClockSkew = TimeSpan.Zero
        };
    });

builder.Services.AddAuthorization(options =>
{
    // One policy per permission, generated from the codes the seed defines.
    // Controllers never name a role — a role is a bundle of permissions that
    // an administrator can change, and code that checks for "Publisher"
    // breaks the moment somebody creates a second role that should publish.
    foreach (var permission in PlatformPermissions.All)
    {
        options.AddPolicy(permission, policy =>
            policy.RequireClaim("perm", permission));
    }
});

builder.Services.AddControllers();
builder.Services.AddResponseCompression(options =>
{
    options.EnableForHttps = true;
});

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;

    // Anonymous callers are bucketed by IP; authenticated ones by user, so one
    // noisy client cannot exhaust the allowance for everyone behind the same
    // NAT.
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(
        context => RateLimitPartition.GetFixedWindowLimiter(
            context.User.FindFirst("sub")?.Value
                ?? context.Connection.RemoteIpAddress?.ToString()
                ?? "unknown",
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 300,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0
            }));
});
builder.Services.AddEndpointsApiExplorer();

// .NET 10 ships OpenAPI document generation in the framework. Swashbuckle is
// deliberately not used: it pulls Microsoft.OpenApi 1.x, which conflicts with
// the 2.x the framework package already brings in.
builder.Services.AddOpenApi(options =>
{
    options.AddDocumentTransformer((document, _, _) =>
    {
        document.Info = new Microsoft.OpenApi.OpenApiInfo
        {
            Title = "Maren Platform API",
            Version = "v1",
            Description = "Backend for the Maren mobile app and admin portal."
        };
        return Task.CompletedTask;
    });
});

/*  CORS for the admin portal only.
    
    Named origins, never AllowAnyOrigin: the portal sends a bearer token, and
    a wildcard origin with credentials is exactly the configuration that lets
    any site a signed-in editor visits drive this API as them. The allowed
    origins come from configuration so staging and production do not need a
    code change. */
builder.Services.AddCors(options =>
{
    options.AddPolicy("admin-portal", policy => policy
        .WithOrigins(
            builder.Configuration.GetSection("Cors:AdminPortalOrigins")
                .Get<string[]>() ?? ["http://localhost:5173"])
        .AllowAnyHeader()
        .AllowAnyMethod()
        .WithExposedHeaders("ETag", "X-Total-Count", "X-Total-Pages"));
});

builder.Services.AddExceptionHandler<MarenExceptionHandler>();
builder.Services.AddProblemDetails();

var app = builder.Build();

/*  First. Everything downstream — request logging, the audit rows a handler
    writes, the security event a refusal writes on its own connection — reads
    what this establishes, so anything registered above it would be
    uncorrelated. */
app.UseMiddleware<CorrelationMiddleware>();

app.UseSerilogRequestLogging();
app.UseResponseCompression();
app.UseRateLimiter();
app.UseExceptionHandler(_ => { });

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.MapScalarApiReference();
}

app.UseCors("admin-portal");
app.UseAuthentication();

/*  After authentication so the claims exist, before authorization so a revoked
    token never reaches a permission check. */
app.UseMiddleware<SecurityStampMiddleware>();

app.UseAuthorization();
app.MapControllers();

app.MapMarenHealth();

app.Run();

/*  Reached only on a clean shutdown. Present because the health probe above
    returns an exit code, and once any path returns a value every path must. */
return 0;

/// <summary>Reads the caller out of the current HTTP context.</summary>
internal sealed class HttpCurrentUser(IHttpContextAccessor accessor) : ICurrentUser
{
    private HttpContext? Context => accessor.HttpContext;

    public Guid? UserId =>
        Guid.TryParse(
            Context?.User.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? Context?.User.FindFirstValue("sub"),
            out var id)
            ? id
            : null;

    public string? IpAddress => Context?.Connection.RemoteIpAddress?.ToString();

    public string? UserAgent => Context?.Request.Headers.UserAgent.ToString();

    public IReadOnlyList<string> Permissions =>
        Context?.User.FindAll("perm").Select(c => c.Value).ToList() ?? [];

    public bool Has(string permission) => Permissions.Contains(permission);
}

/// <summary>Exposed so an integration test project can reference the host.</summary>
public partial class Program;
