-- Grain: one Pickup task in its source process and city.
WITH pickup AS (
    SELECT
        CONCAT('LADE-P|', UPPER(TRIM(p.city)), '|', p.source_order_id)
            AS task_key,
        'P' AS process_code,
        p.source_order_id,
        p.courier_id AS source_courier_id,
        p.region_id AS source_region_id,
        p.aoi_id AS source_aoi_id,
        p.aoi_type AS source_aoi_type,
        p.source_ds,

        c.city_key,
        co.courier_key,
        rg.region_key,
        ao.aoi_key,
        da.date_key AS accepted_date_key,
        dc.date_key AS completed_date_key,

        p.accepted_at,
        p.picked_up_at AS completed_at,
        CAST(1 AS INT) AS task_count,
        p.duration_seconds,
        CASE
            WHEN p.quality_status = 'VALID'
            THEN p.duration_seconds
            ELSE NULL
        END AS valid_duration_seconds,
        p.window_status,
        p.quality_status,
        p.accept_gps_status,
        p.pickup_gps_status

    FROM {{ ref('stg_pickup_tasks') }} AS p

    LEFT JOIN {{ ref('dim_city') }} AS c
        ON c.city_code = UPPER(TRIM(p.city))

    LEFT JOIN {{ ref('dim_date') }} AS da
        ON da.calendar_date = p.accepted_date

    LEFT JOIN {{ ref('dim_date') }} AS dc
        ON dc.calendar_date = p.pickup_date

    LEFT JOIN {{ ref('dim_courier') }} AS co
        ON co.process_code = 'P'
       AND co.city_code = UPPER(TRIM(p.city))
       AND co.source_courier_id = TRIM(p.courier_id)

    LEFT JOIN {{ ref('dim_region') }} AS rg
        ON rg.process_code = 'P'
       AND rg.city_code = UPPER(TRIM(p.city))
       AND rg.source_region_id = TRIM(p.region_id)

    LEFT JOIN {{ ref('dim_aoi') }} AS ao
        ON ao.process_code = 'P'
       AND ao.city_code = UPPER(TRIM(p.city))
       AND ao.source_aoi_id = TRIM(p.aoi_id)
)
SELECT *
FROM pickup
