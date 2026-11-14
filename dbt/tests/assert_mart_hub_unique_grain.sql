
{{ config(tags=['hub', 'hub_mart']) }}

-- Mart grain = calendar day x city x hub
-- Expected: 0 rows

SELECT
    date_key,
    city_key,
    hub_key,
    COUNT_BIG(*) AS duplicate_rows

FROM {{ ref('mart_hub_daily_operations') }}

GROUP BY date_key, city_key, hub_key

HAVING COUNT_BIG(*) > 1
