/*
ExpressCourierDW - Ingestion v2 audit migration

PURPOSE:
  Reuse audit.ETLRunLog from 00_Create_ExpressCourierDW.sql.
  Track one complete CSV snapshot per (process, city).

SAFETY:
  - No DROP / DELETE / TRUNCATE of any table.
  - Existing log rows are preserved.
  - Re-running this migration is safe (checks column/index existence).
  - This migration does NOT import files or update raw tables.
*/
USE [ExpressCourierDW];
GO

IF OBJECT_ID(N'audit.ETLRunLog', N'U') IS NULL
    THROW 51001, N'Khong tim thay audit.ETLRunLog: chay file tao DB goc truoc.', 1;
GO

IF COL_LENGTH(N'audit.ETLRunLog', N'process_code') IS NULL
    ALTER TABLE [audit].[ETLRunLog] ADD [process_code] NVARCHAR(1) NULL;
GO
IF COL_LENGTH(N'audit.ETLRunLog', N'city_code') IS NULL
    ALTER TABLE [audit].[ETLRunLog] ADD [city_code] NVARCHAR(100) NULL;
GO
IF COL_LENGTH(N'audit.ETLRunLog', N'file_sha256') IS NULL
    ALTER TABLE [audit].[ETLRunLog] ADD [file_sha256] CHAR(64) NULL;
GO
IF COL_LENGTH(N'audit.ETLRunLog', N'source_bytes') IS NULL
    ALTER TABLE [audit].[ETLRunLog] ADD [source_bytes] BIGINT NULL;
GO
IF COL_LENGTH(N'audit.ETLRunLog', N'origin_mode') IS NULL
    ALTER TABLE [audit].[ETLRunLog] ADD [origin_mode] VARCHAR(30) NULL;
GO
IF COL_LENGTH(N'audit.ETLRunLog', N'ingestion_version') IS NULL
    ALTER TABLE [audit].[ETLRunLog] ADD [ingestion_version] VARCHAR(20) NULL;
GO

/* Only one successfully accepted complete-file snapshot for a process/city.
   Historical v1 records have NULL process_code/city_code and are not affected.
   No same-city append/correction supported in this conservative v2. */
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'audit.ETLRunLog')
      AND name = N'UX_ETLRunLog_V2_SuccessProcessCity'
)
BEGIN
    CREATE UNIQUE INDEX [UX_ETLRunLog_V2_SuccessProcessCity]
    ON [audit].[ETLRunLog] ([process_code], [city_code])
    WHERE [run_status] = 'SUCCESS'
      AND [process_code] IS NOT NULL
      AND [city_code] IS NOT NULL;
END;
GO

SELECT c.name AS column_name, ty.name AS data_type
FROM sys.columns AS c
JOIN sys.types AS ty ON c.user_type_id = ty.user_type_id
WHERE c.object_id = OBJECT_ID(N'audit.ETLRunLog')
ORDER BY c.column_id;

SELECT TOP (10)
    run_id, pipeline_name, source_file, run_status, rows_read,
    rows_loaded, process_code, city_code, file_sha256, origin_mode
FROM audit.ETLRunLog
ORDER BY run_id DESC;
GO
