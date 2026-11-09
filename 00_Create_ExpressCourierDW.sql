/*
PROJECT: DATA WAREHOUSE FOR EXPRESS COURIER OPERATIONS
DATABASE: ExpressCourierDW
SOURCE: Cainiao LaDe-P (Pickup) and LaDe-D (Delivery)
PURPOSE: Create a NEW database and its initial Raw/ETL logging structures.

SAFETY:
  - Does NOT rename, delete, or modify the existing CourierDW database.
  - Does NOT DROP/TRUNCATE/DELETE any table.
  - If ExpressCourierDW already exists, this script preserves it and
    creates only objects that are missing. Inspect existing structures
    before importing into an existing database.
  - Run in SQL Server Management Studio (SSMS).

MODEL NOTE:
  FactPickup, FactDelivery and shared Dimensions are intentionally NOT
  created in this initial script: their grain, keys and data contracts
  must be finalized before implementing the DW layer.
*/

/* ========== 1. CREATE DATABASE ========== */
USE [master];
GO

IF DB_ID(N'ExpressCourierDW') IS NULL
BEGIN
    CREATE DATABASE [ExpressCourierDW];
    PRINT N'CREATED: ExpressCourierDW';
END
ELSE
BEGIN
    PRINT N'NOTICE: ExpressCourierDW already exists. No database is overwritten.';
END;
GO

/* ========== 2. CREATE SCHEMAS ========== */
USE [ExpressCourierDW];
GO

IF SCHEMA_ID(N'raw') IS NULL EXEC(N'CREATE SCHEMA [raw]');
IF SCHEMA_ID(N'stg') IS NULL EXEC(N'CREATE SCHEMA [stg]');
IF SCHEMA_ID(N'dw') IS NULL EXEC(N'CREATE SCHEMA [dw]');
IF SCHEMA_ID(N'audit') IS NULL EXEC(N'CREATE SCHEMA [audit]');
GO

/* ========== 3. RAW PICKUP ========== */
-- 19 source fields, in the exact column order of pickup_jl.csv.
-- Raw values use NVARCHAR so invalid dates/numbers remain visible for DQ checks;
-- Staging will convert them to typed SQL values after validation.
IF OBJECT_ID(N'raw.PickupTasks', N'U') IS NULL
BEGIN
    CREATE TABLE [raw].[PickupTasks]
    (
        [order_id]             NVARCHAR(50)  NULL,
        [region_id]            NVARCHAR(50)  NULL,
        [city]                 NVARCHAR(100) NULL,
        [courier_id]           NVARCHAR(50)  NULL,
        [accept_time]          NVARCHAR(32)  NULL,
        [time_window_start]    NVARCHAR(32)  NULL,
        [time_window_end]      NVARCHAR(32)  NULL,
        [lng]                  NVARCHAR(50)  NULL,
        [lat]                  NVARCHAR(50)  NULL,
        [aoi_id]               NVARCHAR(50)  NULL,
        [aoi_type]             NVARCHAR(50)  NULL,
        [pickup_time]          NVARCHAR(32)  NULL,
        [pickup_gps_time]      NVARCHAR(32)  NULL,
        [pickup_gps_lng]       NVARCHAR(50)  NULL,
        [pickup_gps_lat]       NVARCHAR(50)  NULL,
        [accept_gps_time]      NVARCHAR(32)  NULL,
        [accept_gps_lng]       NVARCHAR(50)  NULL,
        [accept_gps_lat]       NVARCHAR(50)  NULL,
        [ds]                   NVARCHAR(12)  NULL
    );
    PRINT N'CREATED: raw.PickupTasks';
END;
GO

/* ========== 4. RAW DELIVERY ========== */
-- 17 source fields, in the exact column order of delivery_jl.csv.
IF OBJECT_ID(N'raw.DeliveryTasks', N'U') IS NULL
BEGIN
    CREATE TABLE [raw].[DeliveryTasks]
    (
        [order_id]             NVARCHAR(50)  NULL,
        [region_id]            NVARCHAR(50)  NULL,
        [city]                 NVARCHAR(100) NULL,
        [courier_id]           NVARCHAR(50)  NULL,
        [lng]                  NVARCHAR(50)  NULL,
        [lat]                  NVARCHAR(50)  NULL,
        [aoi_id]               NVARCHAR(50)  NULL,
        [aoi_type]             NVARCHAR(50)  NULL,
        [accept_time]          NVARCHAR(32)  NULL,
        [accept_gps_time]      NVARCHAR(32)  NULL,
        [accept_gps_lng]       NVARCHAR(50)  NULL,
        [accept_gps_lat]       NVARCHAR(50)  NULL,
        [delivery_time]        NVARCHAR(32)  NULL,
        [delivery_gps_time]    NVARCHAR(32)  NULL,
        [delivery_gps_lng]     NVARCHAR(50)  NULL,
        [delivery_gps_lat]     NVARCHAR(50)  NULL,
        [ds]                   NVARCHAR(12)  NULL
    );
    PRINT N'CREATED: raw.DeliveryTasks';
END;
GO

/* ========== 5. ETL RUN LOG (AUDIT) ========== */
-- This table is a LOG DESTINATION, not automatic SQL Server auditing.
-- Future SSIS/Python/SQL pipelines will write start/end/count/status rows.
IF OBJECT_ID(N'audit.ETLRunLog', N'U') IS NULL
BEGIN
    CREATE TABLE [audit].[ETLRunLog]
    (
        [run_id]          BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT [PK_ETLRunLog] PRIMARY KEY,
        [pipeline_name]   NVARCHAR(100) NOT NULL,
        [source_file]     NVARCHAR(260) NULL,
        [started_at]      DATETIME2(0) NOT NULL
            CONSTRAINT [DF_ETLRunLog_Started] DEFAULT (SYSDATETIME()),
        [finished_at]     DATETIME2(0) NULL,
        [rows_read]       BIGINT NULL,
        [rows_loaded]     BIGINT NULL,
        [rows_rejected]   BIGINT NULL,
        [run_status]      VARCHAR(20) NOT NULL
            CONSTRAINT [DF_ETLRunLog_Status] DEFAULT ('RUNNING'),
        [error_message]   NVARCHAR(2000) NULL,
        CONSTRAINT [CK_ETLRunLog_Status]
            CHECK ([run_status] IN ('RUNNING', 'SUCCESS', 'FAILED'))
    );
    PRINT N'CREATED: audit.ETLRunLog';
END;
GO

/* ========== 6. VERIFICATION ========== */
SELECT DB_NAME() AS [database_name];

SELECT [name] AS [schema_name]
FROM sys.schemas
WHERE [name] IN (N'raw', N'stg', N'dw', N'audit')
ORDER BY [name];

SELECT s.[name] AS [schema_name], t.[name] AS [table_name],
       COUNT(c.column_id) AS [column_count]
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
LEFT JOIN sys.columns AS c ON c.object_id = t.object_id
WHERE (s.[name] = N'raw' AND t.[name] IN (N'PickupTasks', N'DeliveryTasks'))
   OR (s.[name] = N'audit' AND t.[name] = N'ETLRunLog')
GROUP BY s.[name], t.[name]
ORDER BY s.[name], t.[name];

SELECT N'raw.PickupTasks' AS [table_name], COUNT_BIG(*) AS [row_count]
FROM [raw].[PickupTasks]
UNION ALL
SELECT N'raw.DeliveryTasks', COUNT_BIG(*)
FROM [raw].[DeliveryTasks];
GO
