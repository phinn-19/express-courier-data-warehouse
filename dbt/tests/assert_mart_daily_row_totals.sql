-- A singular dbt test: it passes if it returns no rows.
WITH reconcile AS (
    SELECT
        'PICKUP' AS process_name,
        (SELECT COUNT_BIG(*) FROM {{ ref('fact_pickup') }}) AS fact_tasks,
        (SELECT COALESCE(SUM(pickup_tasks), 0) FROM {{ ref('mart_daily_operations') }}) AS mart_tasks
    UNION ALL
    SELECT
        'DELIVERY',
        (SELECT COUNT_BIG(*) FROM {{ ref('fact_delivery') }}),
        (SELECT COALESCE(SUM(delivery_tasks), 0) FROM {{ ref('mart_daily_operations') }})
)
SELECT *
FROM reconcile
WHERE fact_tasks <> mart_tasks
