/*
HUB EXPORT: LẤY MẪU PICKUP THẬT CHO GENERATOR MÔ PHỎNG HUB
Readonly. KHÔNG UPDATE / INSERT / DELETE.

Nguồn: dw.fact_pickup + dw.dim_city, đã được kiểm chứng trong repo.
Lấy tối đa 2.500 task VALID mỗi thành phố, sắp thứ tự hash ổn định.
Tổng tối đa 5.000, không bảo đảm đủ nếu số task eligible thấp hơn.

Cột xuất CSV, theo đúng thứ tự:
task_key,city_code,completed_at,quality_status

Lưu ý: mẫu cân bằng 50/50 KHÔNG đại diện tỷ trọng task thật Jilin/Yantai.
Đặt file CSV xuất vào data/hub/pickup_reference.csv (không commit).
*/
USE [ExpressCourierDW];
GO

WITH eligible AS (
    SELECT
        CAST(f.task_key AS NVARCHAR(200)) AS task_key,
        CAST(c.city_code AS NVARCHAR(20)) AS city_code,
        f.completed_at,
        f.quality_status,
        ROW_NUMBER() OVER (
            PARTITION BY c.city_code
            ORDER BY
                HASHBYTES('SHA2_256', CONCAT(N'hub-ref-v1|', f.task_key)),
                f.task_key
        ) AS sample_rank
    FROM dw.fact_pickup AS f
    INNER JOIN dw.dim_city AS c
        ON f.city_key = c.city_key
    WHERE c.city_code IN (N'JILIN', N'YANTAI')
      AND f.quality_status = N'VALID'
      AND f.completed_at IS NOT NULL
      AND f.completed_at >= '2022-01-01T00:00:00'
      AND f.completed_at < '2022-12-25T00:00:00'
)
SELECT
    task_key,
    city_code,
    CONVERT(VARCHAR(19), completed_at, 126) AS completed_at,
    quality_status
FROM eligible
WHERE sample_rank <= 2500
ORDER BY city_code, task_key;
GO

/*
Sau khi xuất CSV: xác minh số dòng thực tế theo City, SHA256 của file,
encoding UTF-8 và giữ đúng header. Không dùng kết quả này suy ra số
shipment thật hay hiệu quả hub thật.
*/
