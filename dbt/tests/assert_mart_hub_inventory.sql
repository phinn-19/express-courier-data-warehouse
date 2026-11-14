
{{ config(tags=['hub', 'hub_mart']) }}

-- Validate daily inventory roll-forward
-- Expected: 0 rows

WITH stock_rollforward AS (
    SELECT
        date_key,
        city_key,
        hub_key,
        received_count,
        sorted_count,
        departed_count,
        departed_shipments_with_dwell,
        total_dwell_seconds,
        avg_dwell_minutes,
        end_of_day_inventory,

        LAG(
            end_of_day_inventory,
            1,
            CAST(0 AS BIGINT)
        ) OVER (
            PARTITION BY hub_key
            ORDER BY date_key
        ) AS prior_inventory

    FROM {{ ref('mart_hub_daily_operations') }}
)

SELECT *
FROM stock_rollforward

WHERE end_of_day_inventory <>
      prior_inventory + received_count - departed_count

   OR end_of_day_inventory < 0

   OR received_count < 0
   OR sorted_count < 0
   OR departed_count < 0

   OR departed_shipments_with_dwell < 0
   OR total_dwell_seconds < 0

   OR departed_shipments_with_dwell > departed_count

   OR (
       departed_shipments_with_dwell = 0
       AND avg_dwell_minutes IS NOT NULL
   )

   OR (
       departed_shipments_with_dwell > 0
       AND avg_dwell_minutes IS NULL
   )
