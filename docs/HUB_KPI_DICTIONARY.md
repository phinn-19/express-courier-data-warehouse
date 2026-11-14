
# HUB KPI DICTIONARY — ExpressCourierDW

**Owner:** B  
**Trạng thái:** WORKING DRAFT  
**Nguồn:** dw.fact_hub_event và các Hub Dimensions  
**Phạm vi:** SIMULATED SCENARIO

## 1. Grain

Một ngày lịch × một thành phố × một Hub.

Mart bao gồm cả những ngày không phát sinh sự kiện.

## 2. Các KPI

| KPI | Định nghĩa |
|---|---|
| received_count | Số HUB_RECEIVED trong ngày |
| sorted_count | Số SORTING_COMPLETED trong ngày |
| departed_count | Số HUB_DEPARTED trong ngày |
| departed_shipments_with_dwell | Số shipment đã xuất và có đủ Received/Departed |
| total_dwell_seconds | Tổng thời gian từ Received đến Departed |
| avg_dwell_minutes | Tổng giây lưu Hub / Số shipment có dwell / 60 |
| end_of_day_inventory | Tổng Received lũy kế - Departed lũy kế |

## 3. Quy tắc nghiệp vụ

- Dwell được ghi nhận theo ngày Departed.
- Dwell chỉ tính shipment có đủ Received và Departed.
- Tồn cuối ngày không được âm.
- Inventory là semi-additive, không cộng qua nhiều ngày.
- Không coi dữ liệu Hub SIMULATED là hoạt động Hub thực tế.
- Không cộng Hub Shipment vào số task LaDe thực.

## 4. DAX cho Power BI

```dax
Hub Received =
SUM(mart_hub_daily_operations[received_count])

Hub Sorted =
SUM(mart_hub_daily_operations[sorted_count])

Hub Departed =
SUM(mart_hub_daily_operations[departed_count])

Hub Avg Dwell Minutes =
DIVIDE(
    SUM(mart_hub_daily_operations[total_dwell_seconds]),
    SUM(mart_hub_daily_operations[departed_shipments_with_dwell]) * 60
)

Hub Inventory End =
VAR LastVisibleDate = MAX(dim_date[calendar_date])
RETURN
    CALCULATE(
        SUM(mart_hub_daily_operations[end_of_day_inventory]),
        FILTER(
            ALL(dim_date[calendar_date]),
            dim_date[calendar_date] = LastVisibleDate
        )
    )
```

## 5. Kết quả đối soát dự kiến

Theo dataset của C:
- 4 Hub
- 5.000 SIM Shipment
- 15.000 Hub Events
- Received = 5.000
- Sorted = 5.000
- Departed = 5.000

Chỉ đánh dấu ACCEPTED sau khi chạy dbt tests
và nghiệm thu trên database integration.
