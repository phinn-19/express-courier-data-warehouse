-- No more than one row at Date x City grain.
SELECT date_key, city_key, COUNT_BIG(*) AS duplicate_rows
FROM {{ ref('mart_daily_operations') }}
GROUP BY date_key, city_key
HAVING COUNT_BIG(*) > 1