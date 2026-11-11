SELECT
    process_code,
    date_key,
    city_key,
    region_key,
    aoi_key,
    COUNT_BIG(*) AS duplicate_count
FROM {{ ref('mart_area_performance') }}
GROUP BY
    process_code,
    date_key,
    city_key,
    region_key,
    aoi_key
HAVING COUNT_BIG(*) > 1