{{ config(tags=['hub']) }}
-- Silver: Hub giả lập (SIMULATED). Grain: 1 hub_id.
SELECT
    TRIM(hub_id) AS hub_id,
    UPPER(TRIM(city_code)) AS city_code,
    TRIM(hub_name) AS hub_name,
    data_origin,
    source_batch_id,
    loaded_at
FROM {{ source('hub_sim_raw', 'Hubs') }}
