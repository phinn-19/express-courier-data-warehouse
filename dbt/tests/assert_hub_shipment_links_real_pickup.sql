{{ config(tags=['hub']) }}
-- Referential + provenance (contract mục 10): mỗi SIM Shipment trỏ tới đúng 1 Pickup task THẬT,
-- cùng City, cùng completed_at, quality VALID. Không sửa dữ liệu lõi, chỉ đọc.
-- Trả 0 dòng = PASS.
SELECT
    s.sim_shipment_id,
    s.origin_pickup_task_key,
    s.city_code AS shipment_city,
    c.city_code AS pickup_city,
    s.pickup_completed_at,
    f.completed_at AS pickup_completed_at_source,
    f.quality_status
FROM {{ ref('stg_hub_shipments') }} AS s
LEFT JOIN {{ ref('fact_pickup') }} AS f
    ON f.task_key = s.origin_pickup_task_key
LEFT JOIN {{ ref('dim_city') }} AS c
    ON c.city_key = f.city_key
WHERE f.task_key IS NULL
   OR c.city_code IS NULL
   OR c.city_code <> s.city_code
   OR f.completed_at IS NULL
   OR f.completed_at <> s.pickup_completed_at
   OR f.quality_status <> 'VALID'
