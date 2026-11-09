/*
STEP 02 | ExpressCourierDW | Verify Raw import
Only SELECT queries. No table modifications.
Expected: Pickup 261801, Delivery 31415 from locally profiled files.
*/
USE [ExpressCourierDW];
GO

-- 1. Check raw counts
SELECT 'raw.PickupTasks' AS table_name, COUNT_BIG(*) AS row_count
FROM raw.PickupTasks
UNION ALL
SELECT 'raw.DeliveryTasks', COUNT_BIG(*)
FROM raw.DeliveryTasks;
GO

-- 2. Check distinct source IDs within each process
SELECT 'Pickup' AS process_name,
       COUNT_BIG(*) AS total_rows,
       COUNT(DISTINCT NULLIF(LTRIM(RTRIM(order_id)), '')) AS distinct_order_id
FROM raw.PickupTasks
UNION ALL
SELECT 'Delivery', COUNT_BIG(*),
       COUNT(DISTINCT NULLIF(LTRIM(RTRIM(order_id)), ''))
FROM raw.DeliveryTasks;
GO

-- 3. Preserve originally missing GPS values (CSV empty fields are empty strings in Raw)
SELECT 'Pickup' AS process_name,
       SUM(CASE WHEN NULLIF(LTRIM(RTRIM(accept_gps_lng)), '') IS NULL THEN 1 ELSE 0 END) AS missing_accept_gps_lng,
       SUM(CASE WHEN NULLIF(LTRIM(RTRIM(pickup_gps_lng)), '') IS NULL THEN 1 ELSE 0 END) AS missing_completion_gps_lng
FROM raw.PickupTasks
UNION ALL
SELECT 'Delivery',
       SUM(CASE WHEN NULLIF(LTRIM(RTRIM(accept_gps_lng)), '') IS NULL THEN 1 ELSE 0 END),
       SUM(CASE WHEN NULLIF(LTRIM(RTRIM(delivery_gps_lng)), '') IS NULL THEN 1 ELSE 0 END)
FROM raw.DeliveryTasks;
GO

-- 4. Audit logs
SELECT TOP (10) run_id, pipeline_name, started_at, finished_at,
       rows_read, rows_loaded, rows_rejected, run_status, error_message
FROM audit.ETLRunLog
ORDER BY run_id DESC;
GO

-- 5. View a few unmodified source records
SELECT TOP (5) order_id, courier_id, accept_time, time_window_start,
               time_window_end, pickup_time, ds
FROM raw.PickupTasks;

SELECT TOP (5) order_id, courier_id, accept_time, delivery_time, ds
FROM raw.DeliveryTasks;
GO
