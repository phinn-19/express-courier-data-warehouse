
WITH task_rows AS (

    -- Pickup
    SELECT
        CAST('P' AS VARCHAR(1)) AS process_code,
        completed_date_key AS date_key,
        city_key,
        courier_key,

        CAST(task_count AS BIGINT) AS task_count,

        CASE
            WHEN valid_duration_seconds IS NOT NULL
            THEN 1 ELSE 0
        END AS valid_duration_task_count,

        COALESCE(valid_duration_seconds, 0)
            AS valid_duration_seconds,

        CASE WHEN quality_status = 'REVIEW'
            THEN 1 ELSE 0 END AS review_tasks,

        CASE WHEN quality_status = 'INVALID'
            THEN 1 ELSE 0 END AS invalid_tasks,

        CASE
            WHEN window_status = 'LATE'
             AND quality_status <> 'INVALID'
            THEN 1 ELSE 0
        END AS pickup_late_tasks,

        CASE
            WHEN window_status IN ('EARLY', 'WITHIN', 'LATE')
             AND quality_status <> 'INVALID'
            THEN 1 ELSE 0
        END AS pickup_window_eligible_tasks

    FROM {{ ref('fact_pickup') }}

    UNION ALL

    -- Delivery
    SELECT
        CAST('D' AS VARCHAR(1)) AS process_code,
        completed_date_key,
        city_key,
        courier_key,

        CAST(task_count AS BIGINT),

        CASE
            WHEN valid_duration_seconds IS NOT NULL
            THEN 1 ELSE 0
        END,

        COALESCE(valid_duration_seconds, 0),

        CASE WHEN quality_status = 'REVIEW'
            THEN 1 ELSE 0 END,

        CASE WHEN quality_status = 'INVALID'
            THEN 1 ELSE 0 END,

        0, -- Delivery khong co Pickup window
        0

    FROM {{ ref('fact_delivery') }}
)

SELECT
    process_code,
    date_key,
    city_key,
    courier_key,

    SUM(task_count) AS total_tasks,
    SUM(valid_duration_task_count) AS valid_duration_tasks,
    SUM(valid_duration_seconds) AS total_valid_duration_seconds,
    SUM(review_tasks) AS review_tasks,
    SUM(invalid_tasks) AS invalid_tasks,
    SUM(pickup_late_tasks) AS pickup_late_tasks,
    SUM(pickup_window_eligible_tasks) AS pickup_window_eligible_tasks

FROM task_rows

GROUP BY
    process_code,
    date_key,
    city_key,
    courier_key
