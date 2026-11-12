WITH tasks AS (
    SELECT
        'P' AS process_code,
        UPPER(TRIM(city)) AS city_code,
        source_order_id
    FROM {{ ref('stg_pickup_tasks') }}

    UNION ALL

    SELECT
        'D',
        UPPER(TRIM(city)),
        source_order_id
    FROM {{ ref('stg_delivery_tasks') }}
)

SELECT
    process_code,
    city_code,
    source_order_id,
    COUNT_BIG(*) AS duplicate_count
FROM tasks
GROUP BY process_code, city_code, source_order_id
HAVING COUNT_BIG(*) > 1