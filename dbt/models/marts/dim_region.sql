-- Grain: 1 ma region / quy trinh / thanh pho

WITH source_regions AS (
    SELECT DISTINCT
        'P' AS process_code,
        NULLIF(UPPER(TRIM(city)), '') AS city_code,
        NULLIF(TRIM(region_id), '') AS source_region_id
    FROM {{ ref('stg_pickup_tasks') }}

    UNION

    SELECT DISTINCT
        'D' AS process_code,
        NULLIF(UPPER(TRIM(city)), '') AS city_code,
        NULLIF(TRIM(region_id), '') AS source_region_id
    FROM {{ ref('stg_delivery_tasks') }}
)

SELECT
    CONCAT(
        'LADE-', process_code,
        '|', city_code,
        '|', source_region_id
    ) AS region_key,

    process_code,
    city_code,
    source_region_id

FROM source_regions
WHERE city_code IS NOT NULL
  AND source_region_id IS NOT NULL