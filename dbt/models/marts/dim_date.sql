-- Dimension ngày của DW.
-- LaDe công bố dữ liệu trong năm 2022.

WITH digits AS (
    SELECT n
    FROM (VALUES
        (0),(1),(2),(3),(4),
        (5),(6),(7),(8),(9)
    ) AS d(n)
),

numbers AS (
    SELECT
        a.n + b.n * 10 + c.n * 100
            AS day_offset
    FROM digits a
    CROSS JOIN digits b
    CROSS JOIN digits c
),

calendar AS (
    SELECT
        DATEADD(
            DAY,
            day_offset,
            CAST('2022-01-01' AS DATE)
        ) AS calendar_date
    FROM numbers
)

SELECT
    -- LÝ DO 2: date_key dạng YYYYMMDD (vd 20220512) là khóa ổn định.
    -- Không dùng ROW_NUMBER() vì nếu sau này thêm ngày mới vào trước,
    -- số thứ tự sẽ đổi → fact đã nạp có nguy cơ tham chiếu sai.
    -- YYYYMMDD gắn với chính ngày đó, mở rộng data bao nhiêu cũng không đổi.
    -- Đây là khóa kỹ thuật xác định theo ngày, không phải mã nghiệp vụ từ LaDe.
    CAST(
        CONVERT(CHAR(8), calendar_date, 112)
        AS INT
    ) AS date_key,

    calendar_date,
    YEAR(calendar_date) AS year_number,
    DATEPART(QUARTER, calendar_date) AS quarter_number,
    MONTH(calendar_date) AS month_number,
    DAY(calendar_date) AS day_number,
    DATEPART(ISO_WEEK, calendar_date) AS iso_week_number

FROM calendar
-- LÝ DO 3: Chỉ tạo năm 2022 vì phạm vi LaDe đã được xác minh thuộc năm 2022.
-- Khi thêm nguồn dữ liệu năm khác, sẽ mở rộng khoảng ngày và kiểm thử độ bao phủ,
-- không tự động coi năm 2022 đúng với mọi dataset.
WHERE calendar_date < '2023-01-01'