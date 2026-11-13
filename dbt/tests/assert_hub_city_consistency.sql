{{ config(tags=['hub']) }}
-- shipment.hub.city = shipment.city; Fact city_key = city_key của Hub.
-- Trả 0 dòng = PASS.
SELECT
    'SHIPMENT_HUB_CITY' AS check_name,
    s.sim_shipment_id AS object_id
FROM {{ ref('stg_hub_shipments') }} AS s
JOIN {{ ref('stg_hub_hubs') }} AS h
    ON h.hub_id = s.hub_id
WHERE h.city_code <> s.city_code

UNION ALL

SELECT
    'FACT_HUB_CITY',
    f.event_id
FROM {{ ref('fact_hub_event') }} AS f
JOIN {{ ref('dim_hub') }} AS h
    ON h.hub_key = f.hub_key
WHERE h.city_key <> f.city_key
