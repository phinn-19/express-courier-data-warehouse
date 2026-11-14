{{ config(tags=['hub']) }}
-- DimHub (SIMULATED). Grain: 1 Hub giả lập.
-- hub_key = hub_id (mã nghiệp vụ ổn định SIMHUB-<CITY>-NN), cùng kiểu khóa chuỗi như courier_key.
-- Không gắn Region/AOI/tọa độ thật cho Hub.
SELECT
    h.hub_id AS hub_key,
    h.hub_id,
    c.city_key,
    h.city_code,
    h.hub_name,
    h.data_origin
FROM {{ ref('stg_hub_hubs') }} AS h
LEFT JOIN {{ ref('dim_city') }} AS c
    ON c.city_code = h.city_code
