
-- Grain:
-- Process x CompletedDate x City x Region x AOI

WITH all_tasks AS (

    -- Nhiem vu Pickup
    SELECT
        CAST('P' AS VARCHAR(1)) AS process_code,
        completed_date_key AS date_key,
        city_key,
        region_key,
        aoi_key,

        CAST(task_count AS BIGINT) AS task_count,
        valid_duration_seconds,

        quality_status,

        CASE
            WHEN window_status = 'LATE'
             AND quality_status <> 'INVALID'
            THEN 1 ELSE 0
        END AS late_pickup,

        CASE
            WHEN window_status IN ('EARLY', 'WITHIN', 'LATE')
             AND quality_status <> 'INVALID'
            THEN 1 ELSE 0
        END AS window_eligible

    FROM {{ ref('fact_pickup') }}

    UNION ALL

    -- Nhiem vu Delivery
    SELECT
        CAST('D' AS VARCHAR(1)),
        completed_date_key,
        city_key,
        region_key,
        aoi_key,

        CAST(task_count AS BIGINT),
        valid_duration_seconds,

        quality_status,

        0 AS late_pickup,
        0 AS window_eligible

    FROM {{ ref('fact_delivery') }}
)

SELECT
    process_code,
    date_key,
    city_key,
    region_key,
    aoi_key,

    SUM(task_count) AS total_tasks,

    SUM(
        CASE WHEN valid_duration_seconds IS NOT NULL
             THEN 1 ELSE 0 END
    ) AS valid_duration_tasks,

    SUM(
        COALESCE(valid_duration_seconds, 0)
    ) AS total_valid_duration_seconds,

    SUM(
        CASE WHEN quality_status = 'VALID'
             THEN 1 ELSE 0 END
    ) AS valid_tasks,

    SUM(
        CASE WHEN quality_status = 'REVIEW'
             THEN 1 ELSE 0 END
    ) AS review_tasks,

    SUM(
        CASE WHEN quality_status = 'INVALID'
             THEN 1 ELSE 0 END
    ) AS invalid_tasks,

    SUM(late_pickup) AS pickup_late_tasks,

    SUM(window_eligible) AS pickup_window_eligible_tasks

FROM all_tasks

GROUP BY
    process_code,
    date_key,
    city_key,
    region_key,
    aoi_key
