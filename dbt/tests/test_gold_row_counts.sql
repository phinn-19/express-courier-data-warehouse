-- ============================================================
-- TEST ĐỐI SOÁT: silver (staging) vs gold (fact)
-- Mục đích: đảm bảo fact KHÔNG bị mất dòng khi build từ staging
--
-- Cách hoạt động (dbt singular test):
--   - Trả về 0 dòng → PASS  (số dòng khớp)
--   - Trả về >0 dòng → FAIL (có quy trình bị lệch dòng)
--
-- Khi FAIL nghĩa là: fact build bị mất dòng, thường do
--   INNER JOIN với dim thiếu key / WHERE filter / DISTINCT nhầm
-- ============================================================
--- đảm bảo toàn vẹn tham chiếu của star schema

WITH reconciliation AS (

    SELECT
        'PICKUP' AS process_name,

        (
            SELECT COUNT_BIG(*)
            FROM {{ ref('stg_pickup_tasks') }}
        ) AS silver_rows,

        (
            SELECT COUNT_BIG(*)
            FROM {{ ref('fact_pickup') }}
        ) AS gold_rows

    UNION ALL

    SELECT
        'DELIVERY',

        (
            SELECT COUNT_BIG(*)
            FROM {{ ref('stg_delivery_tasks') }}
        ),

        (
            SELECT COUNT_BIG(*)
            FROM {{ ref('fact_delivery') }}
        )
)

SELECT *
FROM reconciliation
WHERE silver_rows <> gold_rows