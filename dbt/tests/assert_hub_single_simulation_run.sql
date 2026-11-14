{{ config(tags=['hub']) }}
-- Chỉ một simulation_run_id trong Shipments + Events: không trộn hai phiên bản dataset.
-- Trả 0 dòng = PASS.
WITH runs AS (
    SELECT simulation_run_id FROM {{ ref('stg_hub_shipments') }}
    UNION
    SELECT simulation_run_id FROM {{ ref('stg_hub_events') }}
)
SELECT COUNT(*) AS distinct_run_count
FROM runs
HAVING COUNT(*) > 1
