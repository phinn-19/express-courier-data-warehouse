
{{ config(tags=['hub', 'hub_mart']) }}

-- Hub Operations SIMULATED
-- Grain: calendar_date x city_key x hub_key

WITH typed_events AS (
    SELECT
        f.sim_shipment_id,
        f.city_key,
        f.hub_key,
        f.event_date_key,
        f.event_ts,
        f.event_count,
        f.simulation_run_id,
        t.event_type
    FROM {{ ref('fact_hub_event') }} AS f
    INNER JOIN {{ ref('dim_hub_event_type') }} AS t
        ON t.event_type_key = f.event_type_key
),

scenario_bounds AS (
    SELECT
        MIN(CAST(event_ts AS DATE)) AS first_received_date
    FROM typed_events
    WHERE event_type = 'HUB_RECEIVED'
),

run_info AS (
    SELECT MAX(simulation_run_id) AS simulation_run_id
    FROM typed_events
),

date_hub_spine AS (
    SELECT
        d.date_key,
        d.calendar_date,
        h.city_key,
        h.hub_key
    FROM {{ ref('dim_date') }} AS d
    CROSS JOIN {{ ref('dim_hub') }} AS h
    CROSS JOIN scenario_bounds AS b
    WHERE d.calendar_date >= b.first_received_date
      AND d.calendar_date <= CAST(
          '{{ var("hub_as_of_ts", "2022-12-31T23:59:59") }}'
          AS DATE
      )
),

daily_event_counts AS (
    SELECT
        event_date_key AS date_key,
        city_key,
        hub_key,

        SUM(CASE
            WHEN event_type = 'HUB_RECEIVED'
            THEN CAST(event_count AS BIGINT)
            ELSE CAST(0 AS BIGINT)
        END) AS received_count,

        SUM(CASE
            WHEN event_type = 'SORTING_COMPLETED'
            THEN CAST(event_count AS BIGINT)
            ELSE CAST(0 AS BIGINT)
        END) AS sorted_count,

        SUM(CASE
            WHEN event_type = 'HUB_DEPARTED'
            THEN CAST(event_count AS BIGINT)
            ELSE CAST(0 AS BIGINT)
        END) AS departed_count

    FROM typed_events
    GROUP BY event_date_key, city_key, hub_key
),

shipment_timestamps AS (
    SELECT
        sim_shipment_id,
        city_key,
        hub_key,

        MAX(CASE
            WHEN event_type = 'HUB_RECEIVED'
            THEN event_ts
        END) AS received_ts,

        MAX(CASE
            WHEN event_type = 'HUB_DEPARTED'
            THEN event_ts
        END) AS departed_ts

    FROM typed_events
    GROUP BY sim_shipment_id, city_key, hub_key
),

daily_dwell AS (
    SELECT
        d.date_key,
        s.city_key,
        s.hub_key,

        COUNT_BIG(*) AS departed_shipments_with_dwell,

        SUM(
            DATEDIFF_BIG(
                SECOND,
                s.received_ts,
                s.departed_ts
            )
        ) AS total_dwell_seconds

    FROM shipment_timestamps AS s

    INNER JOIN {{ ref('dim_date') }} AS d
        ON d.calendar_date = CAST(s.departed_ts AS DATE)

    WHERE s.received_ts IS NOT NULL
      AND s.departed_ts IS NOT NULL
      AND s.departed_ts >= s.received_ts

    GROUP BY d.date_key, s.city_key, s.hub_key
),

combined AS (
    SELECT
        sp.date_key,
        sp.calendar_date,
        sp.city_key,
        sp.hub_key,

        COALESCE(
            c.received_count, CAST(0 AS BIGINT)
        ) AS received_count,

        COALESCE(
            c.sorted_count, CAST(0 AS BIGINT)
        ) AS sorted_count,

        COALESCE(
            c.departed_count, CAST(0 AS BIGINT)
        ) AS departed_count,

        COALESCE(
            dw.departed_shipments_with_dwell,
            CAST(0 AS BIGINT)
        ) AS departed_shipments_with_dwell,

        COALESCE(
            dw.total_dwell_seconds,
            CAST(0 AS BIGINT)
        ) AS total_dwell_seconds

    FROM date_hub_spine AS sp

    LEFT JOIN daily_event_counts AS c
        ON c.date_key = sp.date_key
       AND c.city_key = sp.city_key
       AND c.hub_key = sp.hub_key

    LEFT JOIN daily_dwell AS dw
        ON dw.date_key = sp.date_key
       AND dw.city_key = sp.city_key
       AND dw.hub_key = sp.hub_key
)

SELECT
    c.date_key,
    c.calendar_date,
    c.city_key,
    c.hub_key,

    c.received_count,
    c.sorted_count,
    c.departed_count,

    c.departed_shipments_with_dwell,
    c.total_dwell_seconds,

    CAST(
        CASE
            WHEN c.departed_shipments_with_dwell = 0
                THEN NULL
            ELSE
                CAST(
                    c.total_dwell_seconds AS DECIMAL(28,4)
                )
                / CAST(
                    c.departed_shipments_with_dwell AS DECIMAL(20,4)
                )
                / CAST(60.0 AS DECIMAL(5,1))
        END
        AS DECIMAL(18,4)
    ) AS avg_dwell_minutes,

    SUM(c.received_count - c.departed_count)
        OVER (
            PARTITION BY c.hub_key
            ORDER BY c.calendar_date
            ROWS BETWEEN UNBOUNDED PRECEDING
                     AND CURRENT ROW
        ) AS end_of_day_inventory,

    r.simulation_run_id,

    CAST('SIMULATED' AS VARCHAR(16)) AS data_origin

FROM combined AS c
CROSS JOIN run_info AS r
