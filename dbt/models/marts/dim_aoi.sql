-- Grain: one AOI per process and city.
-- Khong dua region_key vao DimAOI.

WITH source_aois AS (
    SELECT
        'P' AS process_code,
        NULLIF(UPPER(TRIM(city)), '') AS city_code,
        NULLIF(TRIM(aoi_id), '') AS source_aoi_id,
        NULLIF(UPPER(TRIM(aoi_type)), '') AS aoi_type
    FROM {{ ref('stg_pickup_tasks') }}

    UNION ALL

    SELECT
        'D' AS process_code,
        NULLIF(UPPER(TRIM(city)), '') AS city_code,
        NULLIF(TRIM(aoi_id), '') AS source_aoi_id,
        NULLIF(UPPER(TRIM(aoi_type)), '') AS aoi_type
    FROM {{ ref('stg_delivery_tasks') }}
),

aoi_summary AS (
    SELECT
        process_code,
        city_code,
        source_aoi_id,

        COUNT(DISTINCT aoi_type)
            AS aoi_type_variant_count,

        SUM(
            CASE WHEN aoi_type IS NULL THEN 1 ELSE 0 END
        ) AS missing_aoi_type_rows,

        CASE
            WHEN COUNT(DISTINCT aoi_type) = 1
            THEN MIN(aoi_type)
            ELSE NULL
        END AS aoi_type

    FROM source_aois
    WHERE city_code IS NOT NULL
      AND source_aoi_id IS NOT NULL

    GROUP BY process_code, city_code, source_aoi_id
)

SELECT
    CONCAT(
        'LADE-', process_code,
        '|', city_code,
        '|', source_aoi_id
    ) AS aoi_key,

    process_code,
    city_code,
    source_aoi_id,
    aoi_type,
    aoi_type_variant_count,
    missing_aoi_type_rows

FROM aoi_summary