{{ config(tags=['hub']) }}
-- Temporal test (contract mục 10): Pickup complete <= Received <= Sorted <= Departed <= as_of_ts.
-- Mỗi shipment phải có HUB_RECEIVED; không có Departed khi chưa Sorted.
-- Chạy SAU KHI đã nạp hết các batch (nạp dở thì shipment chưa có event sẽ FAIL - đúng ý đồ).
-- Trả 0 dòng = PASS.
WITH per_shipment AS (
    SELECT
        s.sim_shipment_id,
        s.pickup_completed_at,
        MAX(CASE WHEN e.event_type = 'HUB_RECEIVED' THEN e.event_ts END) AS received_ts,
        MAX(CASE WHEN e.event_type = 'SORTING_COMPLETED' THEN e.event_ts END) AS sorted_ts,
        MAX(CASE WHEN e.event_type = 'HUB_DEPARTED' THEN e.event_ts END) AS departed_ts,
        MAX(e.event_ts) AS last_event_ts
    FROM {{ ref('stg_hub_shipments') }} AS s
    LEFT JOIN {{ ref('stg_hub_events') }} AS e
        ON e.sim_shipment_id = s.sim_shipment_id
    GROUP BY s.sim_shipment_id, s.pickup_completed_at
)
SELECT
    sim_shipment_id,
    pickup_completed_at,
    received_ts,
    sorted_ts,
    departed_ts,
    CASE
        WHEN received_ts IS NULL THEN 'MISSING_RECEIVED'
        WHEN received_ts < pickup_completed_at THEN 'RECEIVED_BEFORE_PICKUP'
        WHEN sorted_ts IS NULL AND departed_ts IS NOT NULL THEN 'DEPARTED_WITHOUT_SORT'
        WHEN sorted_ts < received_ts THEN 'SORTED_BEFORE_RECEIVED'
        WHEN departed_ts < sorted_ts THEN 'DEPARTED_BEFORE_SORTED'
        ELSE 'AFTER_AS_OF'
    END AS problem
FROM per_shipment
WHERE received_ts IS NULL
   OR received_ts < pickup_completed_at
   OR (sorted_ts IS NULL AND departed_ts IS NOT NULL)
   OR sorted_ts < received_ts
   OR departed_ts < sorted_ts
   OR last_event_ts > CAST('{{ var("hub_as_of_ts", "2022-12-31T23:59:59") }}' AS DATETIME2(0))
