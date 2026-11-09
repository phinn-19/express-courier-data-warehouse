-- Grain: one Delivery task in its source process and city.
WITH delivery AS (
    SELECT
        CONCAT('LADE-D|', UPPER(TRIM(d.city)), '|', d.source_order_id)
            AS task_key,
        'D' AS process_code,
        d.source_order_id,
        d.courier_id AS source_courier_id,
        d.region_id AS source_region_id,
        d.aoi_id AS source_aoi_id,
        d.aoi_type AS source_aoi_type,
        d.source_ds,

        c.city_key,
        co.courier_key,
        rg.region_key,
        ao.aoi_key,
        da.date_key AS accepted_date_key,
        dc.date_key AS completed_date_key,

        d.accepted_at,
        d.delivered_at AS completed_at,
        CAST(1 AS INT) AS task_count,
        d.duration_seconds,
        CASE
            WHEN d.quality_status = 'VALID'
            THEN d.duration_seconds
            ELSE NULL
        END AS valid_duration_seconds,
        d.quality_status,
        d.gps_status

    FROM {{ ref('stg_delivery_tasks') }} AS d

    LEFT JOIN {{ ref('dim_city') }} AS c
        ON c.city_code = UPPER(TRIM(d.city))

    LEFT JOIN {{ ref('dim_date') }} AS da
        ON da.calendar_date = d.accepted_date

    LEFT JOIN {{ ref('dim_date') }} AS dc
        ON dc.calendar_date = d.delivered_date

    LEFT JOIN {{ ref('dim_courier') }} AS co
        ON co.process_code = 'D'
       AND co.city_code = UPPER(TRIM(d.city))
       AND co.source_courier_id = TRIM(d.courier_id)

    LEFT JOIN {{ ref('dim_region') }} AS rg
        ON rg.process_code = 'D'
       AND rg.city_code = UPPER(TRIM(d.city))
       AND rg.source_region_id = TRIM(d.region_id)

    LEFT JOIN {{ ref('dim_aoi') }} AS ao
        ON ao.process_code = 'D'
       AND ao.city_code = UPPER(TRIM(d.city))
       AND ao.source_aoi_id = TRIM(d.aoi_id)
)
SELECT *
FROM delivery
