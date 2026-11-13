{{ config(tags=['hub']) }}
-- DimHubEventType. Danh mục tĩnh theo HUB_DATA_CONTRACT v1.1 (rules hub-rules-v1).
-- event_sequence = thứ tự nghiệp vụ bắt buộc: nhận -> phân loại xong -> xuất.
SELECT
    event_type_key,
    event_type,
    event_type_name,
    event_sequence
FROM (VALUES
    (1, 'HUB_RECEIVED',      N'Hub đã nhận',          1),
    (2, 'SORTING_COMPLETED', N'Phân loại hoàn tất',   2),
    (3, 'HUB_DEPARTED',      N'Rời Hub',              3)
) AS t (event_type_key, event_type, event_type_name, event_sequence)
