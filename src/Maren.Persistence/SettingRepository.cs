using System.Data;
using Dapper;
using Maren.Application.Abstractions;
using Maren.Application.Config;
using Maren.Contracts;

namespace Maren.Persistence;

/// <summary>Remote configuration administration.</summary>
public sealed class SettingRepository(IAmbientConnection ambient) : ISettingRepository
{
    public async Task<PagedResult<SettingAdminDto>> SearchAsync(
        SettingSearchQuery criteria, CancellationToken ct)
    {
        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            var rows = (await connection.QueryAsync<SettingRow>(
                new CommandDefinition(
                    "[Administration].[usp_Setting_Search]",
                    new { criteria.Query, criteria.Category, criteria.Page, criteria.PageSize },
                    transaction, commandType: CommandType.StoredProcedure,
                    cancellationToken: ct))).ToList();

            var total = rows.Count == 0 ? 0 : rows[0].TotalCount;

            var items = rows.Select(r => new SettingAdminDto(
                r.SettingId, r.Key, r.Value, r.DataType, r.Category, r.Description,
                r.IsClientVisible, r.IsSecret, r.ModifiedOn, r.ModifiedBy,
                r.ModifiedByEmail)).ToList();

            return new PagedResult<SettingAdminDto>(
                items, criteria.Page, criteria.PageSize, total);
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    public Task<(bool Succeeded, string? FailureCode)> SaveAsync(
        SaveSettingRequest request, Guid? actorUserId, CancellationToken ct) =>
        ExecuteOutcomeAsync("[Administration].[usp_Setting_Save]", new
        {
            request.Key,
            request.Value,
            request.DataType,
            request.Category,
            request.Description,
            request.IsClientVisible,
            request.IsSecret,
            ActorUserId = actorUserId
        }, ct);

    public Task<(bool Succeeded, string? FailureCode)> DeleteAsync(
        string key, Guid? actorUserId, CancellationToken ct) =>
        ExecuteOutcomeAsync("[Administration].[usp_Setting_Delete]", new
        {
            Key = key, ActorUserId = actorUserId
        }, ct);

    private async Task<(bool Succeeded, string? FailureCode)> ExecuteOutcomeAsync(
        string procedure, object parameters, CancellationToken ct)
    {
        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            var row = await connection.QuerySingleOrDefaultAsync<OutcomeRow>(
                new CommandDefinition(
                    procedure, parameters, transaction,
                    commandType: CommandType.StoredProcedure,
                    cancellationToken: ct));

            return row is null ? (true, null) : (row.Succeeded, row.FailureCode);
        }
        catch (Microsoft.Data.SqlClient.SqlException ex)
        {
            return (false, SqlErrorMapper.Map(ex).FailureCode);
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    private sealed record SettingRow(
        int SettingId, string Key, string? Value, string DataType, string? Category,
        string? Description, bool IsClientVisible, bool IsSecret,
        DateTime ModifiedOn, Guid? ModifiedBy, string? ModifiedByEmail, int TotalCount);

    private sealed record OutcomeRow(bool Succeeded, string? FailureCode);
}
