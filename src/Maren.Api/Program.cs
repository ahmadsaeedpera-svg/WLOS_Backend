using System.Security.Claims;
using System.Threading.RateLimiting;
using System.Text;
using FluentValidation;
using Maren.Application.Abstractions;
using Maren.Application.Auth;
using Maren.Application.Behaviors;
using Maren.Infrastructure;
using Maren.Persistence;
using Maren.Shared;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using Scalar.AspNetCore;
using Serilog;

var builder = WebApplication.CreateBuilder(args);

Log.Logger = new LoggerConfiguration()
    .Enrich.FromLogContext()
    .WriteTo.Console()
    .CreateLogger();

builder.Host.UseSerilog();

builder.Services.Configure<JwtOptions>(
    builder.Configuration.GetSection(JwtOptions.SectionName));

builder.Services.AddMarenPersistence();
builder.Services.AddMarenInfrastructure();

builder.Services.AddMarenCaching();

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

var signingKey = builder.Configuration["Jwt:SigningKey"];
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
            ValidIssuer = builder.Configuration["Jwt:Issuer"],
            ValidAudience = builder.Configuration["Jwt:Audience"],
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

var app = builder.Build();

app.UseSerilogRequestLogging();
app.UseResponseCompression();
app.UseRateLimiter();
app.UseExceptionHandler(_ => { });

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.MapScalarApiReference();
}

app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

app.MapGet("/health", () =>
        Results.Ok(new { status = "ok", utc = DateTime.UtcNow }))
   .AllowAnonymous();

app.Run();

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
