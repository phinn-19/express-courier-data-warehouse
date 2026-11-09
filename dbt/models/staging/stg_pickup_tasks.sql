WITH source_data AS (
    SELECT
        NULLIF(TRIM(order_id), '') AS source_order_id,
        NULLIF(TRIM(city), '') AS city,
        NULLIF(TRIM(region_id), '') AS region_id,
        NULLIF(TRIM(courier_id), '') AS courier_id,

        -- thêm aoi_id phục vụ phân tích không gian, khu vực
        NULLIF(TRIM(aoi_id), '') AS aoi_id,
        NULLIF(TRIM(aoi_type), '') AS aoi_type,

        -- source_ds giúp đối chiếu ngày phân vùng nguồn
        NULLIF(TRIM(ds), '') AS source_ds,

        TRY_CONVERT(
            DATETIME2(0),
            '2022-' + NULLIF(TRIM(accept_time), ''),
            120
        ) AS accepted_at,

        TRY_CONVERT(
            DATETIME2(0),
            '2022-' + NULLIF(TRIM(pickup_time), ''),
            120
        ) AS picked_up_at,

        TRY_CONVERT(
            DATETIME2(0),
            '2022-' + NULLIF(TRIM(time_window_start), ''),
            120
        ) AS window_start_at,

        TRY_CONVERT(
            DATETIME2(0),
            '2022-' + NULLIF(TRIM(time_window_end), ''),
            120
        ) AS window_end_at,

        TRY_CONVERT(
            DATETIME2(0),
            '2022-' + NULLIF(TRIM(accept_gps_time), ''),
            120
        ) AS accept_gps_at,

        TRY_CONVERT(
            DATETIME2(0),
            '2022-' + NULLIF(TRIM(pickup_gps_time), ''),
            120
        ) AS pickup_gps_at,

        TRY_CONVERT(
            DECIMAL(12,8),
            NULLIF(NULLIF(LOWER(TRIM(lng)), 'nan'), '')
        ) AS task_lng,

        TRY_CONVERT(
            DECIMAL(12,8),
            NULLIF(NULLIF(LOWER(TRIM(lat)), 'nan'), '')
        ) AS task_lat,

        TRY_CONVERT(
            DECIMAL(12,8),
            NULLIF(NULLIF(LOWER(TRIM(accept_gps_lng)), 'nan'), '')
        ) AS accept_gps_lng,

        TRY_CONVERT(
            DECIMAL(12,8),
            NULLIF(NULLIF(LOWER(TRIM(accept_gps_lat)), 'nan'), '')
        ) AS accept_gps_lat,

        TRY_CONVERT(
            DECIMAL(12,8),
            NULLIF(NULLIF(LOWER(TRIM(pickup_gps_lng)), 'nan'), '')
        ) AS pickup_gps_lng,

        TRY_CONVERT(
            DECIMAL(12,8),
            NULLIF(NULLIF(LOWER(TRIM(pickup_gps_lat)), 'nan'), '')
        ) AS pickup_gps_lat

    FROM {{ source('lade_raw', 'PickupTasks') }}
),

calculated AS (
    SELECT
        *,
        CAST(accepted_at AS DATE) AS accepted_date,
        CAST(picked_up_at AS DATE) AS pickup_date,

        DATEDIFF_BIG(
            SECOND,
            accepted_at,
            picked_up_at
        ) AS duration_seconds

    FROM source_data
)

SELECT
    *,

    CASE
        WHEN accepted_at IS NULL
          OR picked_up_at IS NULL
          OR duration_seconds < 0
        THEN 'INVALID'

        WHEN duration_seconds = 0
          OR duration_seconds > 86400
        THEN 'REVIEW'

        ELSE 'VALID'
    END AS quality_status,

    CASE
        WHEN picked_up_at IS NULL
          OR window_start_at IS NULL
          OR window_end_at IS NULL
        THEN 'UNKNOWN'

        WHEN window_start_at > window_end_at
        THEN 'INVALID_WINDOW'

        WHEN picked_up_at < window_start_at
        THEN 'EARLY'

        WHEN picked_up_at > window_end_at
        THEN 'LATE'

        ELSE 'WITHIN'
    END AS window_status,

    CASE
        WHEN accept_gps_lng IS NULL
          OR accept_gps_lat IS NULL
        THEN 'MISSING_GPS'
        ELSE 'PRESENT'
    END AS accept_gps_status,

    CASE
        WHEN pickup_gps_lng IS NULL
          OR pickup_gps_lat IS NULL
        THEN 'MISSING_GPS'
        ELSE 'PRESENT'
    END AS pickup_gps_status

FROM calculated