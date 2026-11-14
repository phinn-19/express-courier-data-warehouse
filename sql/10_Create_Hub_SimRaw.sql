/*
10_Create_Hub_SimRaw.sql — ExpressCourierDW (HUB_DATA_CONTRACT v1.1)

Tạo schema sim_raw (dữ liệu Hub SIMULATED) và bảng audit.HubETLBatchLog.
- Chạy trên DB DEV của bạn (C) hoặc DB integration của A, KHÔNG chạy trên DB demo.
- Idempotent: chỉ CREATE khi chưa có. Không DROP / DELETE / TRUNCATE.
- Không đụng tới raw.*, stg.*, dw.*, mart.* của lõi LaDe.
- Yêu cầu: schema audit đã tồn tại (tạo bởi 00_Create_ExpressCourierDW.sql).

Cách chạy: mở trong SSMS, kiểm tra USE đúng tên DB dev, F5.
Nếu DB dev của bạn tên khác, sửa dòng USE bên dưới.
*/
USE [ExpressCourierDW];
GO

IF SCHEMA_ID(N'audit') IS NULL
    THROW 50001, N'Chưa có schema audit. Chạy 00_Create_ExpressCourierDW.sql trước.', 1;
GO

IF SCHEMA_ID(N'sim_raw') IS NULL
BEGIN
    EXEC (N'CREATE SCHEMA [sim_raw] AUTHORIZATION [dbo];');
    PRINT N'CREATED: schema sim_raw';
END;
GO

/* ========== 1. sim_raw.Hubs ========== */
IF OBJECT_ID(N'sim_raw.Hubs', N'U') IS NULL
BEGIN
    CREATE TABLE [sim_raw].[Hubs]
    (
        [hub_id]          VARCHAR(40)   NOT NULL CONSTRAINT [PK_SimHubs] PRIMARY KEY,
        [city_code]       VARCHAR(20)   NOT NULL,
        [hub_name]        NVARCHAR(100) NOT NULL,
        [data_origin]     VARCHAR(20)   NOT NULL,
        [source_batch_id] VARCHAR(40)   NOT NULL,
        [loaded_at]       DATETIME2(0)  NOT NULL CONSTRAINT [DF_SimHubs_Loaded] DEFAULT (SYSDATETIME()),
        CONSTRAINT [CK_SimHubs_City]   CHECK ([city_code] IN ('JILIN', 'YANTAI')),
        CONSTRAINT [CK_SimHubs_Origin] CHECK ([data_origin] = 'SIMULATED'),
        CONSTRAINT [CK_SimHubs_IdCity] CHECK ([hub_id] LIKE 'SIMHUB-' + [city_code] + '-[0-9][0-9]')
    );
    PRINT N'CREATED: sim_raw.Hubs';
END;
GO

/* ========== 2. sim_raw.Shipments ========== */
IF OBJECT_ID(N'sim_raw.Shipments', N'U') IS NULL
BEGIN
    CREATE TABLE [sim_raw].[Shipments]
    (
        [sim_shipment_id]        VARCHAR(80)   NOT NULL CONSTRAINT [PK_SimShipments] PRIMARY KEY,
        [origin_pickup_task_key] NVARCHAR(200) NOT NULL,
        [city_code]              VARCHAR(20)   NOT NULL,
        [hub_id]                 VARCHAR(40)   NOT NULL,
        [pickup_completed_at]    DATETIME2(0)  NOT NULL,
        [simulation_run_id]      VARCHAR(80)   NOT NULL,
        [data_origin]            VARCHAR(20)   NOT NULL,
        [source_batch_id]        VARCHAR(40)   NOT NULL,
        [loaded_at]              DATETIME2(0)  NOT NULL CONSTRAINT [DF_SimShipments_Loaded] DEFAULT (SYSDATETIME()),
        CONSTRAINT [UQ_SimShipments_OriginTask] UNIQUE ([origin_pickup_task_key]),
        CONSTRAINT [FK_SimShipments_Hub] FOREIGN KEY ([hub_id]) REFERENCES [sim_raw].[Hubs] ([hub_id]),
        CONSTRAINT [CK_SimShipments_Id]     CHECK ([sim_shipment_id] LIKE 'SIMSHIP-%' AND LEN([sim_shipment_id]) = 72),
        CONSTRAINT [CK_SimShipments_City]   CHECK ([city_code] IN ('JILIN', 'YANTAI')),
        CONSTRAINT [CK_SimShipments_Task]   CHECK ([origin_pickup_task_key] LIKE N'LADE-P|%'),
        CONSTRAINT [CK_SimShipments_Origin] CHECK ([data_origin] = 'SIMULATED')
    );
    PRINT N'CREATED: sim_raw.Shipments';
END;
GO

/* ========== 3. sim_raw.HubEvents ========== */
IF OBJECT_ID(N'sim_raw.HubEvents', N'U') IS NULL
BEGIN
    CREATE TABLE [sim_raw].[HubEvents]
    (
        [event_id]          VARCHAR(80)  NOT NULL CONSTRAINT [PK_SimHubEvents] PRIMARY KEY,
        [sim_shipment_id]   VARCHAR(80)  NOT NULL,
        [event_type]        VARCHAR(30)  NOT NULL,
        [event_ts]          DATETIME2(0) NOT NULL,
        [batch_id]          VARCHAR(40)  NOT NULL,
        [simulation_run_id] VARCHAR(80)  NOT NULL,
        [data_origin]       VARCHAR(20)  NOT NULL,
        [loaded_at]         DATETIME2(0) NOT NULL CONSTRAINT [DF_SimHubEvents_Loaded] DEFAULT (SYSDATETIME()),
        CONSTRAINT [UQ_SimHubEvents_ShipmentType] UNIQUE ([sim_shipment_id], [event_type]),
        CONSTRAINT [FK_SimHubEvents_Shipment] FOREIGN KEY ([sim_shipment_id])
            REFERENCES [sim_raw].[Shipments] ([sim_shipment_id]),
        CONSTRAINT [CK_SimHubEvents_Id]     CHECK ([event_id] LIKE 'SIMEVT-%' AND LEN([event_id]) = 71),
        CONSTRAINT [CK_SimHubEvents_Type]   CHECK ([event_type] IN ('HUB_RECEIVED', 'SORTING_COMPLETED', 'HUB_DEPARTED')),
        CONSTRAINT [CK_SimHubEvents_Origin] CHECK ([data_origin] = 'SIMULATED')
    );
    CREATE INDEX [IX_SimHubEvents_Ts] ON [sim_raw].[HubEvents] ([event_ts], [event_id]);
    PRINT N'CREATED: sim_raw.HubEvents';
END;
GO

/* ========== 4. audit.HubETLBatchLog ========== */
IF OBJECT_ID(N'audit.HubETLBatchLog', N'U') IS NULL
BEGIN
    CREATE TABLE [audit].[HubETLBatchLog]
    (
        [log_id]             BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_HubETLBatchLog] PRIMARY KEY,
        [batch_id]           VARCHAR(40)    NOT NULL,
        [target_table]       VARCHAR(60)    NOT NULL,
        [source_file]        NVARCHAR(260)  NULL,
        [source_file_sha256] CHAR(64)       NULL,
        [batch_payload_sha256] CHAR(64)     NULL,
        [simulation_run_id]  VARCHAR(80)    NULL,
        [rows_read]          INT            NULL,
        [rows_inserted]      INT            NULL,
        [rows_skipped]       INT            NULL,
        [rows_rejected]      INT            NULL,
        [started_at]         DATETIME2(0)   NOT NULL CONSTRAINT [DF_HubETLBatchLog_Started] DEFAULT (SYSDATETIME()),
        [finished_at]        DATETIME2(0)   NULL,
        [status]             VARCHAR(20)    NOT NULL CONSTRAINT [DF_HubETLBatchLog_Status] DEFAULT ('RUNNING'),
        [error_message]      NVARCHAR(2000) NULL,
        CONSTRAINT [CK_HubETLBatchLog_Status] CHECK ([status] IN ('RUNNING', 'SUCCESS', 'FAILED'))
    );
    PRINT N'CREATED: audit.HubETLBatchLog';
END;
GO

/* ========== 5. VERIFICATION (read-only) ========== */
SELECT s.[name] AS [schema_name], t.[name] AS [table_name]
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
WHERE (s.[name] = N'sim_raw' AND t.[name] IN (N'Hubs', N'Shipments', N'HubEvents'))
   OR (s.[name] = N'audit' AND t.[name] = N'HubETLBatchLog')
ORDER BY s.[name], t.[name];

SELECT N'sim_raw.Hubs' AS [table_name], COUNT_BIG(*) AS [row_count] FROM [sim_raw].[Hubs]
UNION ALL SELECT N'sim_raw.Shipments', COUNT_BIG(*) FROM [sim_raw].[Shipments]
UNION ALL SELECT N'sim_raw.HubEvents', COUNT_BIG(*) FROM [sim_raw].[HubEvents];
GO
