-- Grain: 1 ma courier / quy trinh / thanh pho

WITH source_couriers AS (
    SELECT DISTINCT
        'P' AS process_code,
        NULLIF(UPPER(TRIM(city)), '') AS city_code,
        NULLIF(TRIM(courier_id), '') AS source_courier_id
    FROM {{ ref('stg_pickup_tasks') }}

    UNION

    SELECT DISTINCT
        'D' AS process_code,
        NULLIF(UPPER(TRIM(city)), '') AS city_code,
        NULLIF(TRIM(courier_id), '') AS source_courier_id
    FROM {{ ref('stg_delivery_tasks') }}
)

SELECT
    CONCAT(
        'LADE-', process_code,
        '|', city_code,
        '|', source_courier_id
    ) AS courier_key,

    process_code,
    city_code,
    source_courier_id

FROM source_couriers
WHERE city_code IS NOT NULL
  AND source_courier_id IS NOT NULL