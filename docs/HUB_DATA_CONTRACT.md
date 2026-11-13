# HUB DATA CONTRACT v1.1 — ExpressCourierDW

**Trạng thái:** DRAFT — cần B chốt nghiệp vụ và A/C review qua PR; chỉ ghi APPROVED sau khi cả ba thống nhất. V1.1 cập nhật phân công, không thay đổi dữ liệu nguồn/CSV contract.  
**Owner:** B (business, KPI, Mart). **C:** sở hữu Generator + Hub Batch ETL + dbt staging/Dimension/Fact. **A:** kiểm chứng DW lõi, replay/audit, benchmark và nghiệm thu tích hợp.  
**Ranh giới:** dữ liệu LaDe quan sát thật và dữ liệu Hub mô phỏng là hai provenance khác nhau. Không tạo shipment thật từ task LaDe. Thiết kế này là một **scenario** phục vụ kiểm chứng khả năng mở rộng Data Warehouse.

## 1. Sơ đồ dữ liệu, grain và tên file

```
dw.fact_pickup + dw.dim_city  -- read-only
   |  1 Pickup task đã chọn -> tối đa 1 SIM shipment (giả định mô phỏng)
   v
pickup_reference.csv [B xuất, C nhận, không commit] 
   v
[C Generator] -- hubs.csv, shipments.csv, hub_events.csv, manifest.json
   v
[C Batch ETL] -- sim_raw.Hubs, sim_raw.Shipments, sim_raw.HubEvents
   v
[C dbt stg + dw] -- dw.dim_hub, dw.dim_hub_event_type, dw.fact_hub_event
   v
[B dbt Mart] -- mart.mart_hub_daily_operations
   v
[BI] -- Hub Operations (SIMULATED)
```

`dw.fact_delivery` vẫn thuộc lõi thực và không có FK tới SIM Shipment.

## 2. Tập tham chiếu — `pickup_reference.csv` (dữ liệu **thật**, không commit)

| Tên cột | Kiểu logic / CSV | Ràng buộc | Ý nghĩa |
| --- | --- | --- | --- |
| `task_key` | string, UTF-8 | not null, unique, tiền tố `LADE-P\|`; FK tới `dw.fact_pickup.task_key` | Khóa định danh Pickup nguồn scoped by city/process |
| `city_code` | string uppercase | `JILIN` / `YANTAI`; đúng với DimCity của Pickup | Thành phố nguồn |
| `completed_at` | datetime local-naive ISO `YYYY-MM-DDTHH:MM:SS` | not null, thuộc năm 2022 | Thời điểm hoàn tất nhiệm vụ Pickup |
| `quality_status` | string | `VALID` | Trạng thái chất lượng Pickup |

Nguồn: `dw.fact_pickup AS f JOIN dw.dim_city AS c ON f.city_key=c.city_key`, lọc `quality_status='VALID'`, thời gian hợp lệ năm 2022. Mục tiêu MVP **tối đa 2.500 task/City**, sắp xếp hash cố định theo `task_key`; đây là mẫu cân bằng để kiểm chứng quy trình, **không đại diện đúng tỷ trọng nhiệm vụ thực Jilin/Yantai**. Nếu không đủ 2.500 mỗi City, ghi số thực vào manifest, không tự tạo thêm task. SQL trích nằm trong `sql/HUB_EXPORT_PICKUP_REFERENCE.sql`.

**Quy tắc provenance:** `task_key` là định danh của *task*, không phải shipment ID. Một dòng SIM Shipment chỉ liên kết đến task theo **giả định 1 task → tối đa 1 shipment trong kịch bản**, không phải sự thật nguồn.

## 3. Danh mục Hub — `hubs.csv` (**SIMULATED**, C tạo)

| Cột | Kiểu logic / CSV | Ràng buộc |
| --- | --- | --- |
| `hub_id` | string, ví dụ `SIMHUB-JILIN-01` | PK, không null, ổn định qua lần sinh |
| `city_code` | string | FK tới dim_city, `JILIN`/`YANTAI` |
| `hub_name` | string | Tên **giả lập**, không dùng tên cơ sở Hub thực nếu không xác minh |
| `data_origin` | string | luôn `SIMULATED` |

MVP: B chốt **2 Hub giả lập/City**, ví dụ JILIN-01/02, YANTAI-01/02. Không gán tọa độ, Region, AOI thật cho Hub.

## 4. Danh sách SIM Shipment — `shipments.csv` (**SIMULATED**, C tạo)

| Cột | Kiểu logic / CSV | Ràng buộc |
| --- | --- | --- |
| `sim_shipment_id` | string, prefix `SIMSHIP-` + deterministic hex SHA-256 | PK, không null, unique |
| `origin_pickup_task_key` | string | FK tới `pickup_reference.task_key`; **unique** trong MVP |
| `city_code` | string | Phải trùng City của Pickup nguồn |
| `hub_id` | string | FK `hubs.hub_id`, Hub thuộc cùng City |
| `pickup_completed_at` | datetime ISO | Phải bằng `completed_at` của task nguồn |
| `simulation_run_id` | string | Cùng mã trong tất cả file của một phiên bản dataset |
| `data_origin` | string | luôn `SIMULATED` |

`sim_shipment_id` = `SIMSHIP-` + SHA256 của chuỗi chuẩn `hub-v1|<origin_pickup_task_key>` (full 64 hex, không cắt); không chứa đồng hồ hệ thống. `simulation_run_id` ổn định theo SHA256(input checksum + seed + config checksum + generator/rules version). Không để `generated_at` làm thay đổi ID hoặc hash đầu ra.

## 5. Event — `hub_events.csv` (**SIMULATED**, C tạo)

| Cột | Kiểu logic / CSV | Ràng buộc |
| --- | --- | --- |
| `event_id` | string, prefix `SIMEVT-` + SHA-256 | PK; ổn định qua replay |
| `sim_shipment_id` | string | FK `shipments.sim_shipment_id` |
| `event_type` | string | `HUB_RECEIVED`, `SORTING_COMPLETED`, `HUB_DEPARTED` |
| `event_ts` | datetime ISO | >= `pickup_completed_at`; <= `as_of_ts` |
| `batch_id` | string, ví dụ `HUB-V1-B001` | batch được C phân theo sort event_ts/event_id và C nạp theo thứ tự |
| `simulation_run_id` | string | Khớp `shipments` và manifest |
| `data_origin` | string | luôn `SIMULATED` |

`event_id` = `SIMEVT-` + SHA256(`hub-v1|<sim_shipment_id>|<event_type>`) full 64 hex. MVP tối đa **1 event cho mỗi `sim_shipment_id + event_type`**. Lần sửa nghiệp vụ làm tăng phiên bản rules, không reuse ID khác nghĩa.

**Trạng thái sự kiện:**
- Mỗi SIM Shipment có đúng 1 `HUB_RECEIVED` (trong dataset đạt chuẩn).
- `SORTING_COMPLETED` chỉ xảy ra sau `HUB_RECEIVED`.
- `HUB_DEPARTED` chỉ xảy ra sau `SORTING_COMPLETED`.
- Nếu chưa xuất tại một ngày `d`, shipment được tính vào tồn cuối ngày `d` sau khi đã nhận, chứ không phải một lỗi hàng tồn giả định.
- Không có scan lặp, chuyển Hub, mất hàng, trả hàng hoặc delivery trong MVP.

**Thời gian:** timestamp nguồn LaDe không có timezone xác nhận trong Fact; giữ cách biểu diễn time **local-naive** như Gold hiện tại, không tự chuyển sang UTC. Chỉ cộng/trừ các mốc trong **cùng City**. B chốt `as_of_ts` cố định và khoảng thời gian delay trong config; toàn bộ event phải nằm trong năm 2022 vì `dw.dim_date` hiện chỉ chứa 2022.

**Ví dụ cấu hình giả định (B phải công bố):** Pickup complete → Received sau 0.5–8h; Received → Sorted sau 0.25–12h; Sorted → Departed sau 0.25–24h. Đây chỉ là phân bố *giả định để test*, không được gọi là số liệu trung bình Hub thực tế. Sinh theo seed+hash deterministic (không phụ thuộc row input order).

## 6. `manifest.json` (C sinh, dùng để kiểm toán)

**Bắt buộc có:**
- `contract_version`, `rules_version`, `generator_version`, `seed`, `as_of_ts`.
- `pickup_reference_sha256`, `config_sha256`, `simulation_run_id`.
- `files`: tên CSV, số dòng, sha256, list header.
- `source_city_counts` và `shipment_city_counts`, `events_by_type`.
- `data_origin: SIMULATED` và ghi chú phạm vi giả lập.

`generated_at` là metadata phi quyết định, có thể nằm trong manifest, **không được đưa vào input để sinh ID/CSV**. C so sánh hash trước khi nạp; A kiểm tra độc lập khi nghiệm thu. C chuẩn hóa UTF-8, newline `\n`, header cố định, thứ tự sort theo PK, timestamp giây để bảo đảm đầu ra trùng byte.

## 7. Batch semantics & ETL (C phụ trách; A kiểm thử độc lập)

- Nạp `Hubs` và `Shipments` trước sự kiện. Với event, nạp `batch_id` tuần tự theo danh sách manifest.
- `event_id` có unique key hoặc cơ chế `MERGE/INSERT WHERE NOT EXISTS` được kiểm chứng; **cùng event_id + cùng payload** = SKIP; cùng event_id nhưng payload khác = REJECT/FAIL, không âm thầm ghi đè.
- `audit.HubETLBatchLog` ghi `batch_id`, `source_file_sha256`, `rows_read/inserted/skipped/rejected`, `started_at/finished_at`, `status`, `error_message`, `simulation_run_id`.
- Transaction đủ để batch lỗi không nạp dở dang. Replay cùng batch không nhân đôi. Chỉ báo SUCCESS sau commit.
- Nạp theo `event_ts` để demo tăng dần nhưng **không nói là streaming/CDC thực tế**. Optional: thử batch đến muộn và xác nhận tái tính tồn bằng `event_ts` (event time), không theo load time.
- Không sử dụng loader LaDe `03_Load_Raw_Idempotent_v2.py` cho Hub; loader cũ chỉ chấp nhận `pickup/delivery` và 1 complete snapshot per Process–City.

## 8. dbt & DW (C phụ trách)

**Source:** `sim_raw.Hubs`, `sim_raw.Shipments`, `sim_raw.HubEvents` được C tạo/nạp trên DB dev C và khai báo trong dbt `sources.yml`; A kiểm thử triển khai lại trên DB integration riêng.  
**Staging:** `stg_hub_hubs`, `stg_hub_shipments`, `stg_hub_events`.  
**Dimensions:** `dw.dim_hub`, `dw.dim_hub_event_type` (mới), dùng lại `dw.dim_city` và `dw.dim_date`.  
**Fact:** `dw.fact_hub_event` — **grain = một event_id**, giữ `event_id`, `sim_shipment_id`, `origin_pickup_task_key`, `city_key`, `hub_key`, `event_type_key`, `event_date_key`, `event_ts`, `event_count=1`, `simulation_run_id`, `data_origin`, `source_batch_id`.

`dim_hub` có `hub_key`, `hub_id`, `city_key`, `hub_name`, `data_origin`; `dim_hub_event_type` có `event_type_key`, `event_type`, `event_type_name`. Các surrogate key phải ổn định/idempotent trong mô hình; có thể dùng natural business code làm khóa logic nếu đủ ràng buộc. `dim_hub` không được gắn Region/AOI thật.

**Không** trực tiếp JOIN Fact Hub Event với Fact Pickup ở mức các dòng sự kiện để cộng task_count: mỗi task có thể tạo 3 sự kiện, sẽ nhân ba task. Drill-across chỉ sau khi tổng hợp về đúng chung grain; hoặc chỉ hiển thị Hub KPI riêng với nhãn scenario.

## 9. Mart (B phụ trách)

`mart.mart_hub_daily_operations`: grain `calendar_date × city_key × hub_key`.

| KPI | Công thức/điều kiện |
| --- | --- |
| `received_count` | Count `HUB_RECEIVED` theo ngày/Hub |
| `sorted_count` | Count `SORTING_COMPLETED` theo ngày/Hub |
| `departed_count` | Count `HUB_DEPARTED` theo ngày/Hub |
| `end_of_day_inventory` | Cộng dồn Received−Departed đến cuối ngày; >=0 |
| `avg_dwell_minutes` | AVG(`departed_ts−received_ts`) **chỉ** shipment đã Departed trong kỳ; `NULL` khi mẫu số 0 |

Nếu chỉ lấy ngày có event để tạo Mart, phải vẫn có ngày tồn dương **không có sự kiện**: cần khung Date × Hub cho ngày hiệu lực của kịch bản, hoặc điều chỉnh truy vấn snapshot. Không cộng số tồn cuối ngày qua nhiều ngày. Chỉ so sánh các hub và city của **mẫu mô phỏng**, không suy rộng thành hiệu quả Hub thực tế.

**Optional** `dw.fact_hub_inventory_daily_snapshot`: grain `Hub × calendar_date cuối ngày`, cùng nguồn là event tính lại, đo `end_of_day_inventory` bán cộng (semi-additive). Chỉ làm khi Fact Event, Mart và QA đã PASS.

## 10. Các test bắt buộc và nghiệm thu

**Data contract:** Header/type đúng, UTF-8, file hash đúng, `data_origin=SIMULATED` cho 100% nguồn mới, không NULL key.

**Referential:** SIM Shipment → task Pickup thật; shipment.city=pickup.city; shipment.hub.city=shipment.city; Event → SIM Shipment; Date/City/Hub/Event Type FK đều hợp lệ.

**Grain:** Unique pickup task trong sample, unique sim shipment, unique Hub, unique event_id, unique `(sim_shipment_id,event_type)`.

**Temporal:** Pickup complete <= receive <= sort <= depart <= `as_of_ts`; không event sai thứ tự, không âm; event date nằm trong DimDate.

**Reconciliation:** Shipment count = distinct Pickup references (MVP 1:1); each shipment 3 events nếu chọn kịch bản hoàn chỉnh; sum event type counts = event rows; tồn cuối ngày bằng cumulative inbound−outbound, tồn không âm, mỗi shipment <=1 đơn vị tồn.

**Replay:** Nạp hai lần cùng batch không làm thay đổi tổng event; khác payload cùng event_id bị fail. CSV sinh lại với input/seed/config giống nhau cùng SHA256.

**Real data integrity (A phụ trách kiểm chứng):** Đếm `dw.fact_pickup`, `dw.fact_delivery`, 5 Dim và 3 Mart trước/sau chạy, xác nhận không có thay đổi ngoài ý muốn (và chạy lại bộ test lõi).

## 11. Kiểm duyệt contract (điền trước code)

- [ ] B xác nhận 2.500 task/City là **mẫu thử cân bằng**, không dùng để ước lượng sản lượng thực.
- [ ] B xác nhận mỗi shipment có đủ 3 event và khoảng delay giả định, hoặc ghi rõ quy tắc event dở dang nếu thay đổi.
- [ ] B xác nhận `as_of_ts` trong năm 2022 và các mốc event đều nằm trong DimDate.
- [ ] C xác nhận Python sinh ID/file deterministic, header không khác contract.
- [ ] C xác nhận SQL DDL, batch ETL và audit đọc đúng tên/kiểu/khóa; A xác nhận bộ test replay/reconciliation trên DB integration riêng.
- [ ] C/B thống nhất tên các model, KPI và grain với script/BI.

**Ký duyệt nội bộ:** B (business/Mart) __________; C (Generator/ETL/dbt) __________; A (Validation/Integration) __________; version/hash contract __________.
