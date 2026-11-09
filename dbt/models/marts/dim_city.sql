WITH source_cities AS (
    SELECT
        UPPER(TRIM(city)) AS city_code
    FROM {{ ref('stg_pickup_tasks') }}
    WHERE city IS NOT NULL

    UNION

    SELECT
        UPPER(TRIM(city)) AS city_code
    FROM {{ ref('stg_delivery_tasks') }}
    WHERE city IS NOT NULL
),

mapped AS (
    SELECT
        CASE city_code
            WHEN 'JILIN' THEN 1
            WHEN 'HANGZHOU' THEN 2
            WHEN 'SHANGHAI' THEN 3
            WHEN 'CHONGQING' THEN 4
            WHEN 'YANTAI' THEN 5
            ELSE NULL
        END AS city_key,

        city_code

    FROM source_cities
)

SELECT
    city_key,
    city_code
FROM mapped