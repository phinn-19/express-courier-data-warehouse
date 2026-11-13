{{ config(tags=['hub']) }}
-- Silver: SIM Shipment (SIMULATED). Grain: 1 sim_shipment_id.
-- origin_pickup_task_key là task Pickup THẬT; liên kết 1 task -> 1 shipment chỉ là giả định kịch bản.
SELECT
    TRIM(sim_shipment_id) AS sim_shipment_id,
    TRIM(origin_pickup_task_key) AS origin_pickup_task_key,
    UPPER(TRIM(city_code)) AS city_code,
    TRIM(hub_id) AS hub_id,
    pickup_completed_at,
    simulation_run_id,
    data_origin,
    source_batch_id,
    loaded_at
FROM {{ source('hub_sim_raw', 'Shipments') }}
