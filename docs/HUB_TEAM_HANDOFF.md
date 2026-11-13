# HUB TEAM HANDOFF v1.1 — ExpressCourierDW

**Ngày:** 13/11/2026 · **Trạng thái:** phân công hiện hành cho module Hub mô phỏng  
**Chú ý:** tài liệu v1 trong ZIP cũ đã lỗi thời ở phần phân công ETL. **C phụ trách Hub ETL**, không phải A. Data Contract v1.1 trong gói này là DRAFT chờ A/B/C review, còn nghiệp vụ/định dạng cơ bản không đổi.

## 1. Phạm vi và ranh giới

- Lõi giữ nguyên: LaDe Pickup/Delivery, 2 Fact, 5 Dimension, 3 Mart, Jilin/Yantai.
- Mới: Hub Intake / Sorting / Outbound **SIMULATED**, bắt nguồn từ mẫu Pickup task có thật; không suy ra liên kết shipment thật Pickup–Delivery.
- Đầu ra MVP: `sim_raw.Hubs/Shipments/HubEvents`, `dw.dim_hub`, `dw.dim_hub_event_type`, `dw.fact_hub_event`, `mart.mart_hub_daily_operations` và tests.
- `fact_hub_inventory_daily_snapshot` là phần mở rộng *tùy chọn*, chỉ sau khi lõi mới đã PASS.

## 2. Chia việc hiện hành

| Owner | Đầu vào | Việc cần làm | Đầu ra/kiểm chứng |
|---|---|---|---|
| **A — Core Validation & Integration** | Repo, backup `.bak`/SHA256, contract, kết quả C | Restore DB dev A; kiểm tra DW Pickup/Delivery; xây regression/reconciliation; benchmark; kiểm tra độc lập generator/ETL Hub replay; tích hợp toàn kho trên DB A | DB restore và `dbt debug` PASS; đếm 2 Fact cũ; logs tests/replay/benchmark; kết quả `dbt build` tích hợp; báo cáo GO/NO-GO |
| **B — Business, KPI, Mart & Report** | Repo, contract, mẫu Pickup đã chọn, schema Fact do C xác nhận, logs A/C | Chốt business rules; duyệt contract với A/C; Bus Matrix, KPI Dictionary; SQL/dbt Mart Hub; test KPI; tổng hợp báo cáo, bàn giao BI | PR contract; docs Business/KPI/Bus Matrix; `mart_hub_daily_operations.sql`; SQL reconciliation và kết quả; báo cáo |
| **C — Hub Pipeline End-to-End** | Repo, `pickup_reference.csv`, contract/config, DB dev C có SQL Server và Dimension lõi (nhận `.bak` hoặc dựng dev nhỏ) | Generator deterministic; tạo CSV/manifest; **Hub Python ETL + audit/replay + DDL `sim_raw`**; dbt staging/Dimension/Fact/tests trên DB C | `generate_hub_simulation.py`, `load_hub_batches.py`, SQL DDL, config, CSV/manifest gửi riêng, dbt models/tests, log generator & ETL & dbt |
| **BI** | Gold LaDe đã kiểm chứng; sau khi GO nhận Mart/Dim Hub có nhãn SIMULATED và KPI Dictionary | Giữ 4 trang lõi; trang Hub thứ năm chỉ khi Hub PASS | PBIX, kết quả đối soát KPI và ảnh dashboard |

A không cần viết lại loader Hub của C. A vẫn chịu trách nhiệm kiểm chứng ETL toàn kho và tích hợp cuối.

## 3. File bàn giao / cách dùng

- `README.md`, `docs/TEAM_SETUP.md`, `docs/CONTRIBUTING.md` đang có trên `main`: onboarding và Git hiện hữu.
- `docs/HUB_DATA_CONTRACT.md` trong gói: B quản lý; A/C review. Chỉ sau review mới đánh dấu APPROVED.
- `sql/HUB_EXPORT_PICKUP_REFERENCE.sql`: B chạy **read-only** trên database gốc để chọn tối đa 2.500 Pickup VALID/City; CSV có header `task_key,city_code,completed_at,quality_status`, lưu `data/hub/pickup_reference.csv`, gửi riêng C (không commit).
- `config/hub_simulation.example.yml`: tham số mẫu, C copy thành config không chứa bí mật, B kiểm duyệt trước khi chạy đầy đủ.
- `.bak` + SHA256: A/C restore **trên máy riêng**, tên DB dev của từng máy; không cần nạp lại 4 CSV LaDe trên DB đã restore. C chỉ bắt buộc có DB dev tương thích để chạy full SQL/dbt, không bắt buộc nhận `.bak` nếu đã có dev DB đúng cấu trúc.
- CSV Hub/manifest C tạo: chỉ gửi qua kênh riêng, không commit repo.

## 4. Trình tự triển khai giảm chờ đợi

1. **Song song ngày 13/11:** B chốt contract; A restore DB và đo baseline; C bắt đầu generator/DDL/dbt dựa trên contract, thử fixture nhỏ.
2. **Ngày 14/11:** C tự chạy Generator → CSV → Hub ETL → `sim_raw` → dbt Fact trên DB C. A xây bộ regression/benchmark và đọc log C. B hoàn thiện Bus Matrix/KPI và viết Mart dựa trên schema Fact đã chốt.
3. **Ngày 15/11:** C bàn giao schema/Fact/tests; B chạy Mart và KPI tests; A chạy tích hợp `main` trên DB A, thử replay (không nhân đôi), kiểm tra DW lõi không đổi, GO/NO-GO.
4. **Ngày 16/11:** Freeze code, hoàn tất Power BI/báo cáo/demo; ngày 17/11 trình bày.

Không để B chờ model C mới bắt đầu KPI Dictionary; B có thể mô tả công thức và grain ngay. Không để C chờ A viết loader; C tự làm Hub loader.

## 5. Điều kiện nghiệm thu

**C:** CSV/manifest đúng contract, seed/version tái lập, Hub events hợp thời gian, `sim_raw` và Fact chạy trên DB C, audit + replay + dbt tests có log.  
**B:** Mart đúng grain Ngày×City×Hub; received/sorted/departed và tồn theo ngày đối soát được; dwell chỉ tính shipment đã xuất; ghi nhãn SIMULATED và giới hạn chọn mẫu.  
**A:** DB integration riêng restore được; 2 Fact LaDe và các Mart lõi không đổi ngoài ý muốn; pipeline Hub chạy lại và test PASS; benchmark có bằng chứng; trình bày kết quả cuối.

**GO** khi cả ba nghiệm thu. **NO-GO** nếu không có khóa/provenance rõ, event thời gian sai, ETL replay nhân dòng, KPI tồn âm hoặc làm ảnh hưởng lõi. Không đưa module chưa đạt chuẩn vào dashboard/demo chính.

## 6. Git và an toàn

Mỗi người clone repo và làm branch riêng. B dùng `feature/hub-contract` rồi `feature/hub-business-mart`; C `feature/hub-pipeline`; A `feature/hub-validation`. Dùng PR, reviewer khác người code, không commit `data/`, `.bak`, `.venv/`, `dbt/profiles.yml`, mật khẩu/credentials. Mỗi người trỏ `dbt/profiles.yml` vào DB dev **của mình** trước khi chạy dbt. `git merge` chỉ trộn code, không tự chuyển DB vật lý từ máy C/A sang máy m.
