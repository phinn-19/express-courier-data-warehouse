-- Grain: one row per completed calendar date and city.
-- Aggregate each Fact separately, then join at common conformed dimensions.
-- Never join raw Pickup and Delivery tasks by order_id.

WITH pickup_daily AS (
    SELECT
        completed_date_key AS date_key,
        city_key,
        COUNT_BIG(*) AS pickup_tasks,
        SUM(CASE WHEN quality_status = 'VALID'   THEN CAST(1 AS BIGINT) ELSE CAST(0 AS BIGINT) END) AS pickup_valid_tasks,
        SUM(CASE WHEN quality_status = 'REVIEW'  THEN CAST(1 AS BIGINT) ELSE CAST(0 AS BIGINT) END) AS pickup_review_tasks,
        SUM(CASE WHEN quality_status = 'INVALID' THEN CAST(1 AS BIGINT) ELSE CAST(0 AS BIGINT) END) AS pickup_invalid_tasks,
        SUM(CASE WHEN quality_status <> 'INVALID' AND window_status = 'EARLY'  THEN CAST(1 AS BIGINT) ELSE CAST(0 AS BIGINT) END) AS pickup_early_tasks,
        SUM(CASE WHEN quality_status <> 'INVALID' AND window_status = 'WITHIN' THEN CAST(1 AS BIGINT) ELSE CAST(0 AS BIGINT) END) AS pickup_within_tasks,
        SUM(CASE WHEN quality_status <> 'INVALID' AND window_status = 'LATE'   THEN CAST(1 AS BIGINT) ELSE CAST(0 AS BIGINT) END) AS pickup_late_tasks,
        SUM(CASE WHEN quality_status <> 'INVALID' AND window_status IN ('EARLY','WITHIN','LATE')
                 THEN CAST(1 AS BIGINT) ELSE CAST(0 AS BIGINT) END) AS pickup_window_eligible_tasks,
        SUM(CASE WHEN accept_gps_status = 'MISSING_GPS' THEN CAST(1 AS BIGINT) ELSE CAST(0 AS BIGINT) END) AS pickup_missing_accept_gps_tasks,
        SUM(CASE WHEN pickup_gps_status = 'MISSING_GPS' THEN CAST(1 AS BIGINT) ELSE CAST(0 AS BIGINT) END) AS pickup_missing_pickup_gps_tasks,
        SUM(COALESCE(CAST(valid_duration_seconds AS BIGINT), CAST(0 AS BIGINT))) AS pickup_valid_duration_seconds,
        COUNT_BIG(valid_duration_seconds) AS pickup_valid_duration_tasks
    FROM {{ ref('fact_pickup') }}
    GROUP BY completed_date_key, city_key
),

delivery_daily AS (
    SELECT
        completed_date_key AS date_key,
        city_key,
        COUNT_BIG(*) AS delivery_tasks,
        SUM(CASE WHEN quality_status = 'VALID'   THEN CAST(1 AS BIGINT) ELSE CAST(0 AS BIGINT) END) AS delivery_valid_tasks,
        SUM(CASE WHEN quality_status = 'REVIEW'  THEN CAST(1 AS BIGINT) ELSE CAST(0 AS BIGINT) END) AS delivery_review_tasks,
        SUM(CASE WHEN quality_status = 'INVALID' THEN CAST(1 AS BIGINT) ELSE CAST(0 AS BIGINT) END) AS delivery_invalid_tasks,
        SUM(CASE WHEN gps_status = 'MISSING_GPS' THEN CAST(1 AS BIGINT) ELSE CAST(0 AS BIGINT) END) AS delivery_missing_gps_tasks,
        SUM(COALESCE(CAST(valid_duration_seconds AS BIGINT), CAST(0 AS BIGINT))) AS delivery_valid_duration_seconds,
        COUNT_BIG(valid_duration_seconds) AS delivery_valid_duration_tasks
    FROM {{ ref('fact_delivery') }}
    GROUP BY completed_date_key, city_key
)

SELECT
    COALESCE(p.date_key, d.date_key) AS date_key,
    COALESCE(p.city_key, d.city_key) AS city_key,

    COALESCE(p.pickup_tasks, 0) AS pickup_tasks,
    COALESCE(p.pickup_valid_tasks, 0) AS pickup_valid_tasks,
    COALESCE(p.pickup_review_tasks, 0) AS pickup_review_tasks,
    COALESCE(p.pickup_invalid_tasks, 0) AS pickup_invalid_tasks,
    COALESCE(p.pickup_early_tasks, 0) AS pickup_early_tasks,
    COALESCE(p.pickup_within_tasks, 0) AS pickup_within_tasks,
    COALESCE(p.pickup_late_tasks, 0) AS pickup_late_tasks,
    COALESCE(p.pickup_window_eligible_tasks, 0) AS pickup_window_eligible_tasks,
    COALESCE(p.pickup_missing_accept_gps_tasks, 0) AS pickup_missing_accept_gps_tasks,
    COALESCE(p.pickup_missing_pickup_gps_tasks, 0) AS pickup_missing_pickup_gps_tasks,
    COALESCE(p.pickup_valid_duration_seconds, 0) AS pickup_valid_duration_seconds,
    COALESCE(p.pickup_valid_duration_tasks, 0) AS pickup_valid_duration_tasks,

    COALESCE(d.delivery_tasks, 0) AS delivery_tasks,
    COALESCE(d.delivery_valid_tasks, 0) AS delivery_valid_tasks,
    COALESCE(d.delivery_review_tasks, 0) AS delivery_review_tasks,
    COALESCE(d.delivery_invalid_tasks, 0) AS delivery_invalid_tasks,
    COALESCE(d.delivery_missing_gps_tasks, 0) AS delivery_missing_gps_tasks,
    COALESCE(d.delivery_valid_duration_seconds, 0) AS delivery_valid_duration_seconds,
    COALESCE(d.delivery_valid_duration_tasks, 0) AS delivery_valid_duration_tasks
FROM pickup_daily p
FULL OUTER JOIN delivery_daily d
    ON p.date_key = d.date_key
   AND p.city_key = d.city_key
