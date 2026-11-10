-- All KPI components should be coherent within their grain.
SELECT date_key, city_key
FROM {{ ref('mart_daily_operations') }}
WHERE pickup_valid_tasks + pickup_review_tasks + pickup_invalid_tasks <> pickup_tasks
   OR delivery_valid_tasks + delivery_review_tasks + delivery_invalid_tasks <> delivery_tasks
   OR pickup_early_tasks + pickup_within_tasks + pickup_late_tasks <> pickup_window_eligible_tasks
   OR pickup_window_eligible_tasks > pickup_tasks
   OR pickup_valid_duration_tasks > pickup_valid_tasks
   OR delivery_valid_duration_tasks > delivery_valid_tasks
   OR pickup_missing_accept_gps_tasks > pickup_tasks
   OR pickup_missing_pickup_gps_tasks > pickup_tasks
   OR delivery_missing_gps_tasks > delivery_tasks
