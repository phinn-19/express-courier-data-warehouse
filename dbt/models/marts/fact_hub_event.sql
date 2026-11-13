{{ config(tags=['hub']) }}
-- FactHubEvent (SIMULATED). Grain: một event_id.
-- KHÔNG join trực tiếp với fact_pickup để cộng task_count (mỗi task có tới 3 event -> nhân ba).
-- Drill-across chỉ sau khi tổng hợp về cùng grain (vd Date x City).
SELECT
    e.event_id,
    e.sim_shipment_id,
    s.origin_pickup_task_key,
    c.city_key,
    h.hub_key,
    et.event_type_key,
    d.date_key AS event_date_key,
    e.event_ts,
    CAST(1 AS INT) AS event_count,
    e.simulation_run_id,
    e.data_origin,
    e.batch_id AS source_batch_id
FROM {{ ref('stg_hub_events') }} AS e
LEFT JOIN {{ ref('stg_hub_shipments') }} AS s
    ON s.sim_shipment_id = e.sim_shipment_id
LEFT JOIN {{ ref('dim_city') }} AS c
    ON c.city_code = s.city_code
LEFT JOIN {{ ref('dim_hub') }} AS h
    ON h.hub_id = s.hub_id
LEFT JOIN {{ ref('dim_hub_event_type') }} AS et
    ON et.event_type = e.event_type
LEFT JOIN {{ ref('dim_date') }} AS d
    ON d.calendar_date = e.event_date
