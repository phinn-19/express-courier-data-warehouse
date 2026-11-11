
WITH expected AS (
    SELECT 'P' AS process_code,
           COUNT_BIG(*) AS expected_tasks
    FROM {{ ref('fact_pickup') }}

    UNION ALL

    SELECT 'D',
           COUNT_BIG(*)
    FROM {{ ref('fact_delivery') }}
),

actual AS (
    SELECT
        process_code,
        SUM(total_tasks) AS actual_tasks
    FROM {{ ref('mart_courier_performance') }}
    GROUP BY process_code
)

SELECT
    e.process_code,
    e.expected_tasks,
    COALESCE(a.actual_tasks, 0) AS actual_tasks
FROM expected e
LEFT JOIN actual a
    ON e.process_code = a.process_code
WHERE e.expected_tasks <> COALESCE(a.actual_tasks, 0)
