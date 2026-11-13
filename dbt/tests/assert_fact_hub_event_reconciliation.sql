{{ config(tags=['hub']) }}
-- Reconciliation (contract mục 10): sim_raw -> stg -> Fact không mất/nhân dòng,
-- tổng theo event_type khớp, shipment count = distinct Pickup reference (MVP 1:1),
-- unique (sim_shipment_id, event_type), sum(event_count) = số dòng.
-- Trả 0 dòng = PASS.
WITH raw_types AS (
    SELECT event_type, COUNT_BIG(*) AS n
    FROM {{ source('hub_sim_raw', 'HubEvents') }}
    GROUP BY event_type
),
fact_types AS (
    SELECT et.event_type, COUNT_BIG(*) AS n
    FROM {{ ref('fact_hub_event') }} AS f
    JOIN {{ ref('dim_hub_event_type') }} AS et
        ON et.event_type_key = f.event_type_key
    GROUP BY et.event_type
),
checks AS (
    SELECT
        CAST('raw_events_vs_fact_rows' AS VARCHAR(60)) AS check_name,
        (SELECT COUNT_BIG(*) FROM {{ source('hub_sim_raw', 'HubEvents') }}) AS expected_value,
        (SELECT COUNT_BIG(*) FROM {{ ref('fact_hub_event') }}) AS actual_value

    UNION ALL
    SELECT 'stg_events_vs_fact_rows',
        (SELECT COUNT_BIG(*) FROM {{ ref('stg_hub_events') }}),
        (SELECT COUNT_BIG(*) FROM {{ ref('fact_hub_event') }})

    UNION ALL
    SELECT 'fact_rows_vs_sum_event_count',
        (SELECT COUNT_BIG(*) FROM {{ ref('fact_hub_event') }}),
        (SELECT CAST(SUM(event_count) AS BIGINT) FROM {{ ref('fact_hub_event') }})

    UNION ALL
    SELECT 'shipments_vs_distinct_fact_shipments',
        (SELECT COUNT_BIG(*) FROM {{ ref('stg_hub_shipments') }}),
        (SELECT COUNT_BIG(DISTINCT sim_shipment_id) FROM {{ ref('fact_hub_event') }})

    UNION ALL
    SELECT 'shipments_vs_distinct_origin_tasks',
        (SELECT COUNT_BIG(*) FROM {{ ref('stg_hub_shipments') }}),
        (SELECT COUNT_BIG(DISTINCT origin_pickup_task_key) FROM {{ ref('stg_hub_shipments') }})

    UNION ALL
    SELECT 'fact_rows_vs_distinct_shipment_type',
        (SELECT COUNT_BIG(*) FROM {{ ref('fact_hub_event') }}),
        (SELECT COUNT_BIG(*) FROM (
            SELECT DISTINCT sim_shipment_id, event_type_key
            FROM {{ ref('fact_hub_event') }}
        ) AS d)

    UNION ALL
    SELECT CAST(CONCAT('type:', COALESCE(r.event_type, f.event_type)) AS VARCHAR(60)),
        COALESCE(r.n, 0),
        COALESCE(f.n, 0)
    FROM raw_types AS r
    FULL OUTER JOIN fact_types AS f
        ON f.event_type = r.event_type
)
SELECT check_name, expected_value, actual_value
FROM checks
WHERE expected_value <> actual_value
   OR expected_value IS NULL
   OR actual_value IS NULL
