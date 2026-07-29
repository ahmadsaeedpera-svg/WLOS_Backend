using System.Data;
using Dapper;
using Maren.Application.Abstractions;
using Maren.Application.Predicting;
using Maren.Contracts;

namespace Maren.Persistence;

/// <summary>
/// Reads predictions.
/// </summary>
/// <remarks>
/// Four procedures, no SQL. Every statement originates in
/// <c>Predict.fn_PredictFrom</c>, which attaches a window to a probability the
/// behaviour engine already observed. Nothing here computes one.
/// </remarks>
public sealed class PredictionRepository(IDbConnectionFactory factory)
    : IPredictionRepository
{
    public async Task<IReadOnlyList<Prediction>> ResolveAsync(
        Guid userId, DateOnly asOfDate, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        var rows = await connection.QueryAsync<PredictionRow>(new CommandDefinition(
            "[Predict].[usp_Prediction_Resolve]",
            new
            {
                UserId = userId,
                AsOfDate = asOfDate.ToDateTime(TimeOnly.MinValue),
                Persist = true,
            },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        return rows.Select(Map).ToList();
    }

    public async Task<IReadOnlyList<Prediction>> GetAsync(
        Guid userId, DateOnly asOfDate, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        var rows = await connection.QueryAsync<PredictionRow>(new CommandDefinition(
            "[Predict].[usp_Prediction_Get]",
            new { UserId = userId, AsOfDate = asOfDate.ToDateTime(TimeOnly.MinValue) },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        return rows.Select(Map).ToList();
    }

    public async Task<IReadOnlyList<PredictionTypeSummary>> ListTypesAsync(
        CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        var rows = await connection.QueryAsync<TypeRow>(new CommandDefinition(
            "[Predict].[usp_Prediction_ListTypes]",
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        return rows.Select(r => new PredictionTypeSummary(
            r.PredictionKey, r.DisplayName, r.Description, r.HorizonCode,
            r.HorizonName, r.PhraseText, r.WindowDays, r.SourceMeasureCode,
            r.SourceMeasureName, r.SourceFamily, r.SourceMinSpanDays,
            r.FramingPattern, r.MinConfidence, r.MinSupportDays, r.LifetimeHours,
            r.IsActive, r.SourceIsActive)).ToList();
    }

    public async Task<SimulatePredictionResponse> SimulateAsync(
        string observationCsv, int confidence, int defaultSpanDays,
        CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        /*  Two result sets: what would be said, then every prediction type with
            whether these observations produced it. The second answers "why is
            nothing shown", which the first cannot — and this engine withholds
            deliberately often enough that the question is the usual one. */
        using var multi = await connection.QueryMultipleAsync(new CommandDefinition(
            "[Dashboard].[usp_Inspector_SimulatePrediction]",
            new
            {
                ObservationCsv = observationCsv,
                Confidence = confidence,
                DefaultSpanDays = defaultSpanDays,
            },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        var predictions = (await multi.ReadAsync<PredictionRow>()).Select(Map).ToList();
        var considered = (await multi.ReadAsync<SimRow>()).Select(s =>
            new SimulatedPrediction(
                s.PredictionKey, s.DisplayName, s.SourceMeasureCode, s.HorizonCode,
                s.MinConfidence, s.MinSupportDays, s.IsActive, s.SubjectKey,
                s.SuppliedValue, s.SuppliedConfidence, s.SuppliedSpanDays,
                s.WasSupplied, s.IsPredicted, s.Explanation)).ToList();

        return new SimulatePredictionResponse(predictions, considered);
    }

    private static Prediction Map(PredictionRow r) => new(
        r.PredictionKey, r.DisplayName, r.SubjectKey, r.SubjectName,
        r.HorizonCode, r.HorizonName, r.WindowDays, r.ProbabilityPercent,
        r.SupportDays, r.Confidence, r.StatementText, Split(r.EvidenceCsv),
        r.SourceMeasureCode, r.ExpiresUtc, r.EngineVersion);

    private static IReadOnlyList<string> Split(string? csv) =>
        string.IsNullOrWhiteSpace(csv)
            ? []
            : csv.Split(',', StringSplitOptions.RemoveEmptyEntries
                          | StringSplitOptions.TrimEntries);

    private sealed class PredictionRow
    {
        public string PredictionKey { get; init; } = "";
        public string DisplayName { get; init; } = "";
        public string SubjectKey { get; init; } = "";
        public string SubjectName { get; init; } = "";
        public string HorizonCode { get; init; } = "";
        public string HorizonName { get; init; } = "";
        public int WindowDays { get; init; }
        public int ProbabilityPercent { get; init; }
        public int SupportDays { get; init; }
        public int Confidence { get; init; }
        public string StatementText { get; init; } = "";
        public string? EvidenceCsv { get; init; }
        public string SourceMeasureCode { get; init; } = "";
        public DateTime ExpiresUtc { get; init; }

        /*  The simulation result set carries no version — nothing was stored, so
            there is nothing to attribute. Defaulted rather than made nullable,
            so a client never has to branch on it. */
        public string EngineVersion { get; init; } = "simulated";
    }

    private sealed class TypeRow
    {
        public string PredictionKey { get; init; } = "";
        public string DisplayName { get; init; } = "";
        public string Description { get; init; } = "";
        public string HorizonCode { get; init; } = "";
        public string HorizonName { get; init; } = "";
        public string PhraseText { get; init; } = "";
        public int WindowDays { get; init; }
        public string SourceMeasureCode { get; init; } = "";
        public string SourceMeasureName { get; init; } = "";
        public string SourceFamily { get; init; } = "";
        public int SourceMinSpanDays { get; init; }
        public string FramingPattern { get; init; } = "";
        public int MinConfidence { get; init; }
        public int MinSupportDays { get; init; }
        public int LifetimeHours { get; init; }
        public bool IsActive { get; init; }
        public bool SourceIsActive { get; init; }
    }

    private sealed class SimRow
    {
        public string PredictionKey { get; init; } = "";
        public string DisplayName { get; init; } = "";
        public string SourceMeasureCode { get; init; } = "";
        public string HorizonCode { get; init; } = "";
        public int MinConfidence { get; init; }
        public int MinSupportDays { get; init; }
        public bool IsActive { get; init; }
        public string? SubjectKey { get; init; }
        public decimal? SuppliedValue { get; init; }
        public int? SuppliedConfidence { get; init; }
        public int? SuppliedSpanDays { get; init; }
        public bool WasSupplied { get; init; }
        public bool IsPredicted { get; init; }
        public string Explanation { get; init; } = "";
    }
}
