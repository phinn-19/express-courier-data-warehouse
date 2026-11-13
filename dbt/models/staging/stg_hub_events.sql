{{ config(tags=['hub']) }}
-- Silver: sự kiện Hub (SIMULATED). Grain: 1 event_id.
-- Thời gian local-naive như Gold LaDe, không chuyển UTC.
SELECT
    TRIM(event_id) AS event_id,
    TRIM(sim_shipment_id) AS sim_shipment_id,
    UPPER(TRIM(event_type)) AS event_type,
    event_ts,
    CAST(event_ts AS DATE) AS event_date,
    batch_id,
    simulation_run_id,
    data_origin,
    loaded_at
FROM {{ source('hub_sim_raw', 'HubEvents') }}
