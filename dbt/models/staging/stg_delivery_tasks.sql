WITH source_data AS (
    SELECT
        NULLIF(TRIM(order_id), '') AS source_order_id,
        NULLIF(TRIM(city), '') AS city,
        NULLIF(TRIM(region_id), '') AS region_id,
        NULLIF(TRIM(courier_id), '') AS courier_id,
        NULLIF(TRIM(aoi_id), '') AS aoi_id,
        NULLIF(TRIM(aoi_type), '') AS aoi_type,
        NULLIF(TRIM(ds), '') AS source_ds,

        TRY_CONVERT(
            DATETIME2(0),
            '2022-' + NULLIF(TRIM(accept_time), ''),
            120
        ) AS accepted_at,

        TRY_CONVERT(
            DATETIME2(0),
            '2022-' + NULLIF(TRIM(delivery_time), ''),
            120
        ) AS delivered_at,

        TRY_CONVERT(
            DECIMAL(12, 8),
            NULLIF(NULLIF(LOWER(TRIM(lng)), 'nan'), '')
        ) AS task_lng,

        TRY_CONVERT(
            DECIMAL(12, 8),
            NULLIF(NULLIF(LOWER(TRIM(lat)), 'nan'), '')
        ) AS task_lat,

        TRY_CONVERT(
            DECIMAL(12, 8),
            NULLIF(NULLIF(LOWER(TRIM(accept_gps_lng)), 'nan'), '')
        ) AS accept_gps_lng,

        TRY_CONVERT(
            DECIMAL(12, 8),
            NULLIF(NULLIF(LOWER(TRIM(accept_gps_lat)), 'nan'), '')
        ) AS accept_gps_lat,

        TRY_CONVERT(
            DECIMAL(12, 8),
            NULLIF(NULLIF(LOWER(TRIM(delivery_gps_lng)), 'nan'), '')
        ) AS delivery_gps_lng,

        TRY_CONVERT(
            DECIMAL(12, 8),
            NULLIF(NULLIF(LOWER(TRIM(delivery_gps_lat)), 'nan'), '')
        ) AS delivery_gps_lat

    FROM {{ source('lade_raw', 'DeliveryTasks') }}
),

calculated AS (
    SELECT
        *,
        DATEDIFF_BIG(
            SECOND, accepted_at, delivered_at
        ) AS duration_seconds
    FROM source_data
)

SELECT
    *,
    CAST(accepted_at AS DATE) AS accepted_date,
    CAST(delivered_at AS DATE) AS delivered_date,

    CASE
        WHEN accepted_at IS NULL
          OR delivered_at IS NULL
          OR duration_seconds < 0
        THEN 'INVALID'

        WHEN duration_seconds = 0
          OR duration_seconds > 86400
        THEN 'REVIEW'

        ELSE 'VALID'
    END AS quality_status,

    CASE
        WHEN accept_gps_lng IS NULL
          OR accept_gps_lat IS NULL
          OR delivery_gps_lng IS NULL
          OR delivery_gps_lat IS NULL
        THEN 'MISSING_GPS'

        ELSE 'PRESENT'
    END AS gps_status

FROM calculated