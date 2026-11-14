
{{ config(tags=['hub', 'hub_mart']) }}

-- Compare Mart totals against Hub Fact
-- Expected: 0 rows

WITH fact_events AS (
    SELECT
        f.sim_shipment_id,
        f.event_ts,
        f.event_count,
        t.event_type
    FROM {{ ref('fact_hub_event') }} AS f
    JOIN {{ ref('dim_hub_event_type') }} AS t
        ON t.event_type_key = f.event_type_key
),

expected_counts AS (
    SELECT
        SUM(CASE WHEN event_type = 'HUB_RECEIVED'
            THEN CAST(event_count AS BIGINT)
            ELSE 0 END) AS received_count,

        SUM(CASE WHEN event_type = 'SORTING_COMPLETED'
            THEN CAST(event_count AS BIGINT)
            ELSE 0 END) AS sorted_count,

        SUM(CASE WHEN event_type = 'HUB_DEPARTED'
            THEN CAST(event_count AS BIGINT)
            ELSE 0 END) AS departed_count
    FROM fact_events
),

shipment_times AS (
    SELECT
        sim_shipment_id,
        MAX(CASE WHEN event_type = 'HUB_RECEIVED'
            THEN event_ts END) AS received_ts,
        MAX(CASE WHEN event_type = 'HUB_DEPARTED'
            THEN event_ts END) AS departed_ts
    FROM fact_events
    GROUP BY sim_shipment_id
),

expected_dwell AS (
    SELECT
        COUNT_BIG(*) AS dwell_shipments,
        SUM(DATEDIFF_BIG(
            SECOND, received_ts, departed_ts
        )) AS dwell_seconds
    FROM shipment_times
    WHERE received_ts IS NOT NULL
      AND departed_ts IS NOT NULL
      AND departed_ts >= received_ts
),

actual AS (
    SELECT
        SUM(received_count) AS received_count,
        SUM(sorted_count) AS sorted_count,
        SUM(departed_count) AS departed_count,
        SUM(departed_shipments_with_dwell)
            AS dwell_shipments,
        SUM(total_dwell_seconds) AS dwell_seconds
    FROM {{ ref('mart_hub_daily_operations') }}
),

checks AS (
    SELECT
        CAST('received_count' AS VARCHAR(64)) AS metric,
        e.received_count AS expected,
        a.received_count AS actual
    FROM expected_counts e CROSS JOIN actual a

    UNION ALL SELECT
        'sorted_count', e.sorted_count, a.sorted_count
    FROM expected_counts e CROSS JOIN actual a

    UNION ALL SELECT
        'departed_count', e.departed_count, a.departed_count
    FROM expected_counts e CROSS JOIN actual a

    UNION ALL SELECT
        'dwell_shipments', e.dwell_shipments, a.dwell_shipments
    FROM expected_dwell e CROSS JOIN actual a

    UNION ALL SELECT
        'total_dwell_seconds', e.dwell_seconds, a.dwell_seconds
    FROM expected_dwell e CROSS JOIN actual a
)

SELECT metric, expected, actual
FROM checks
WHERE expected <> actual
   OR expected IS NULL
   OR actual IS NULL
