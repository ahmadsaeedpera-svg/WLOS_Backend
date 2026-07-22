/* Required for filtered indexes and indexes on computed columns. Set here
   rather than relying on the client, so the scripts deploy identically from
   sqlcmd, SSMS, Azure Data Studio or a CI runner. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Schemas.

    Separated by bounded context rather than by object type. The practical
    payoff is permissions: the API's SQL login is granted EXECUTE on
    Health and Content and nothing else, so a compromised API credential
    cannot read Identity.PasswordHash or write Audit.AuditLog. That is not
    achievable with everything in dbo.
*/

IF SCHEMA_ID('Identity') IS NULL EXEC('CREATE SCHEMA [Identity]');
IF SCHEMA_ID('Health') IS NULL EXEC('CREATE SCHEMA [Health]');
IF SCHEMA_ID('Content') IS NULL EXEC('CREATE SCHEMA [Content]');
IF SCHEMA_ID('Administration') IS NULL EXEC('CREATE SCHEMA [Administration]');
IF SCHEMA_ID('Notifications') IS NULL EXEC('CREATE SCHEMA [Notifications]');
IF SCHEMA_ID('Reporting') IS NULL EXEC('CREATE SCHEMA [Reporting]');
IF SCHEMA_ID('Audit') IS NULL EXEC('CREATE SCHEMA [Audit]');
GO
