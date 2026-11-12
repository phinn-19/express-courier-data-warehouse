/*
ExpressCourierDW - MULTI-CITY PREFLIGHT (READ ONLY)
Run in SSMS before loading a second city.
Does not INSERT/UPDATE/DELETE/TRUNCATE/DROP/ALTER any object.
The results are intended to inform changes to dbt models before loading.
*/
USE [ExpressCourierDW];
GO

-- A. Verify current city-level Raw counts, not just whole-table totals.
SELECT 'Pickup' AS process_name,
       UPPER(LTRIM(RTRIM(city))) AS city_code,
       COUNT_BIG(*) AS raw_rows
FROM raw.PickupTasks
GROUP BY UPPER(LTRIM(RTRIM(city)))
UNION ALL
SELECT 'Delivery',
       UPPER(LTRIM(RTRIM(city))),
       COUNT_BIG(*)
FROM raw.DeliveryTasks
GROUP BY UPPER(LTRIM(RTRIM(city)))
ORDER BY process_name, city_code;
GO

-- B. Inspect city surrogate keys and calendar coverage.
SELECT city_key, city_code FROM dw.dim_city ORDER BY city_key;
SELECT COUNT_BIG(*) AS dates_in_dim,
       MIN(calendar_date) AS earliest_date,
       MAX(calendar_date) AS latest_date
FROM dw.dim_date;
GO

-- C. Check uniqueness at the recommended source-scoped grain:
-- one task within each (process, city, order_id).
-- A result with zero rows means no collisions at this grain.
WITH source_tasks AS (
    SELECT 'P' AS process_code,
           UPPER(LTRIM(RTRIM(city))) AS city_code,
           LTRIM(RTRIM(order_id)) AS source_order_id
    FROM raw.PickupTasks
    UNION ALL
    SELECT 'D',
           UPPER(LTRIM(RTRIM(city))),
           LTRIM(RTRIM(order_id))
    FROM raw.DeliveryTasks
)
SELECT process_code, city_code, source_order_id,
       COUNT_BIG(*) AS duplicate_count
FROM source_tasks
GROUP BY process_code, city_code, source_order_id
HAVING COUNT_BIG(*) > 1;
GO

-- D. Observe where Silver believes the data came from.
-- If adding cities later, a hardcoded 'pickup_jl.csv' / 'delivery_jl.csv'
-- for ALL rows would be misleading; check model SQL before re-build.
IF COL_LENGTH('stg.stg_pickup_tasks', 'source_file') IS NOT NULL
    EXEC('SELECT TOP (10) city, source_file, COUNT_BIG(*) AS rows_in_stg
          FROM stg.stg_pickup_tasks
          GROUP BY city, source_file
          ORDER BY rows_in_stg DESC');
ELSE PRINT 'stg_pickup_tasks has no source_file column; inspect its model SQL.';

IF COL_LENGTH('stg.stg_delivery_tasks', 'source_file') IS NOT NULL
    EXEC('SELECT TOP (10) city, source_file, COUNT_BIG(*) AS rows_in_stg
          FROM stg.stg_delivery_tasks
          GROUP BY city, source_file
          ORDER BY rows_in_stg DESC');
ELSE PRINT 'stg_delivery_tasks has no source_file column; inspect its model SQL.';
GO

-- E. Verify old file registration in v2.1 audit.
SELECT TOP (12)
       run_id, process_code, city_code, run_status,
       origin_mode, rows_read, rows_loaded, ingestion_version
FROM audit.ETLRunLog
WHERE ingestion_version = '2.1'
ORDER BY run_id DESC;
GO
