# ExpressCourierDW

**Data Warehouse phân tích hoạt động giao nhận chặng cuối (Last-mile Pickup & Delivery)**  
**Case study:** dữ liệu nghiên cứu [Cainiao LaDe](https://huggingface.co/datasets/Cainiao-AI/LaDe) · **SQL Server + Python + dbt + Power BI**

> **Trạng thái tham chiếu (12/11/2026):** mô hình DW đã được xây dựng cho Jilin và Yantai. Ở môi trường của nhóm: 1.408.582 task Pickup + 237.846 task Delivery; lần chạy gần nhất ghi nhận 12 dbt table models và 73 tests đều PASS. Đây là **kết quả kiểm thử được nhóm báo cáo**, không có nghĩa clone repo sẽ có sẵn dữ liệu hoặc đạt đúng các số này.

## 1. Dự án giải quyết bài toán gì?

Kho dữ liệu hỗ trợ so sánh quy mô công việc, thời gian xử lý, cửa sổ Pickup, chất lượng dữ liệu và phân bố theo ngày, thành phố, courier, region và AOI. **Phạm vi đang triển khai là Pickup và Delivery**, không phải toàn bộ hệ thống đơn hàng, kho phân loại, thanh toán hoặc COD của một doanh nghiệp thực.

**Nguyên tắc diễn giải:** một dòng Fact là **một task thuộc một quy trình và một thành phố**, không phải một bưu gửi xuyên suốt. Không nối `fact_pickup` với `fact_delivery` bằng `source_order_id`. Courier/Region/AOI ID được scope theo **process + city**; không giả định chúng là cùng đối tượng giữa hai quy trình.

## 2. Kiến trúc

```text
Cainiao LaDe CSV (Pickup / Delivery, Jilin / Yantai)
      │
      ▼
Python ingestion v2.1  ───► audit.ETLRunLog
      │
      ▼
SQL Server raw.PickupTasks / raw.DeliveryTasks
      │
      ▼
dbt staging (stg) ──► dimensional Gold (dw)
                      ├── dim_date, dim_city, dim_courier, dim_region, dim_aoi
                      └── fact_pickup, fact_delivery
                              │
                              ▼
           mart_daily_operations / mart_courier_performance /
                          mart_area_performance
                              │
                              ▼
                   Power BI (CSV snapshot)
```

Các bảng `stg`, `dw` và `mart` được xây bởi dbt; không có trong script tạo Raw ban đầu. GPS/Trajectory hiện là **hướng nghiên cứu**, chưa coi là Fact đã được triển khai.

## 3. Cấu trúc repo

| Đường dẫn | Chức năng |
| --- | --- |
| `00_Create_ExpressCourierDW.sql` | Khởi tạo DB, schemas Raw và bảng audit ban đầu |
| `03_Upgrade_ETLRunLog_v2.sql` | Mở rộng audit cho ingestion v2.1 |
| `scripts/03_Load_Raw_Idempotent_v2.py` | Kiểm tra / nạp snapshot CSV theo process và city, tránh nạp trùng |
| `04_Preflight_Multicity_ExpressCourierDW.sql` | Kiểm tra read-only trước/sau mở rộng thành phố |
| `dbt/models/staging/` | Chuẩn hóa thời gian, tọa độ, quality status |
| `dbt/models/marts/` | 5 Dimension và 2 Fact |
| `dbt/models/operations/` | 3 Operations Mart |
| `dbt/tests/` | Kiểm thử dữ liệu và đối soát |
| `scripts/export_powerbi_snapshot.py` | Xuất 7 bảng Gold (xem **lưu ý bản Jilin v1** bên dưới) |
| `docs/TEAM_SETUP.md` | Hướng dẫn từng nhóm người dùng cài đặt, chạy từ đầu, xử lý lỗi |
| `docs/CONTRIBUTING.md` | Quy tắc branch, PR và bảo vệ dữ liệu |

## 4. Clone và chọn cách bắt đầu

```powershell
git clone https://github.com/phinn-19/express-courier-data-warehouse.git
cd express-courier-data-warehouse
```

**Clone đã hoạt động.** Nhưng clone **không tải** database SQL Server, dữ liệu LaDe thô hoặc bản Gold v2 hai thành phố. Chọn một đường đi:

- **BI / người chỉ xem phân tích:** nhận 7 CSV Gold v2 + `manifest.json` riêng từ nhóm; không cần SQL Server. Làm theo tài liệu bàn giao Power BI.
- **Nghiên cứu GPS / CSV:** tạo Python virtualenv, nhận CSV nguồn đúng từ LaDe; không cần DB cho bước profiling read-only.
- **DE / người chạy dbt, test, benchmark:** cần SQL Server local có dữ liệu hoặc một môi trường SQL riêng do nhóm cấp. Xem [hướng dẫn setup chi tiết](docs/TEAM_SETUP.md).

## 5. Cài Python trên Windows

Yêu cầu: Python 3.12, Git, PowerShell. Để chạy SQL/dbt thêm SQL Server 2022 Express/Developer, ODBC Driver 18 for SQL Server và SSMS (hoặc công cụ SQL tương đương).

```powershell
py -3.12 -m venv .venv-dbt
.\.venv-dbt\Scripts\python.exe -m pip install --upgrade pip
.\.venv-dbt\Scripts\python.exe -m pip install -r requirements-dbt.txt
.\.venv-dbt\Scripts\python.exe -m pip show dbt-sqlserver pyodbc
```

Công cụ khảo sát CSV có thể dùng `.venv` riêng với `pip install -r requirements.txt`; không bắt buộc duy trì cả hai môi trường. Môi trường `.venv-dbt` đã chứa cả dependencies từ `requirements.txt`.

## 6. Dựng DW từ đầu (dành cho người có SQL Server)

**Đọc `docs/TEAM_SETUP.md` trước khi `--load`**, đặc biệt nếu database đã có dữ liệu. Trình tự chuẩn với **database local mới**:

1. SSMS: chạy `00_Create_ExpressCourierDW.sql`, sau đó `03_Upgrade_ETLRunLog_v2.sql` (đúng thứ tự).
2. Tải CSV **đúng nguồn LaDe** rồi đặt tại `data/pickup_jl.csv`, `data/delivery_jl.csv`, `data/pickup_yt.csv`, `data/delivery_yt.csv` (tên file chỉ là quy ước local). Kiểm tra header trước khi nạp. Không commit dữ liệu nguồn.
3. Chạy `--check` cho từng CSV; sau đó chỉ chạy `--load` cho process-city **chưa có Raw / audit SUCCESS**. Ví dụ:

```powershell
.\.venv-dbt\Scripts\python.exe .\scripts\03_Load_Raw_Idempotent_v2.py --process pickup --city Jilin --file .\data\pickup_jl.csv --check
.\.venv-dbt\Scripts\python.exe .\scripts\03_Load_Raw_Idempotent_v2.py --process pickup --city Jilin --file .\data\pickup_jl.csv --load
```

Thực hiện tuần tự cho Delivery Jilin, Pickup Yantai và Delivery Yantai. Không chạy hai loader đồng thời. Nếu Raw đã có mà chưa đăng ký audit, **không dùng `--load`**: tham khảo quy trình `--register-existing` và xác minh đối soát trong hướng dẫn chi tiết.

4. Copy `dbt/profiles.example.yml` thành **`dbt/profiles.yml`**, chỉnh `server/port/driver` theo máy. File thật bị Git bỏ qua.
5. Kiểm tra kết nối và build:

```powershell
cd dbt
..\.venv-dbt\Scripts\dbt.exe debug --profiles-dir .
..\.venv-dbt\Scripts\dbt.exe build --profiles-dir .
```

Sau khi build, chạy SQL đối soát/kiểm thử. Không kỳ vọng con số 85 tests hoặc 1,65 triệu task nếu chỉ nạp một thành phố hoặc thay đổi nguồn.

## 7. Lưu ý cấu hình kết nối

- **Loader v2.1:** `--server` và `--database` (mặc định `SQL_SERVER` / `SQL_DATABASE` env, fallback `.\SQLEXPRESS` / `ExpressCourierDW`).
- **dbt:** `dbt/profiles.yml`, không tự sử dụng biến `SQL_SERVER` của loader.
- **Exporter hiện có trong `main`:** dùng biến `DW_SQL_SERVER`, mặc định `.\SQLEXPRESS`, và **manifest vẫn ghi `Jilin Gold v1`**. Không lấy file `bi/snapshots.zip` hoặc manifest v1 để bàn giao với nhãn Jilin+Yantai. Bản snapshot Gold v2 phải được kiểm tra số dòng và metadata trước khi chia sẻ.

Chi tiết cấu hình SQL Server và lỗi thường gặp: [TEAM_SETUP.md](docs/TEAM_SETUP.md).

## 8. Kiểm chứng và giới hạn

Nếu nạp đủ 4 CSV đã được nhóm khảo sát, số dòng **kỳ vọng** theo City × Process:

| City | Pickup | Delivery |
|---|---:|---:|
| JILIN | 261.801 | 31.415 |
| YANTAI | 1.146.781 | 206.431 |

Các số trên cần được đối soát giữa Raw, dbt Gold và Mart trước khi công bố. Khối lượng `Total Tasks` = Pickup + Delivery task, **không** phải số bưu gửi duy nhất. Pickup `window_status` **không** phải Delivery SLA. Không giả định dữ liệu Trajectory ghép được với `courier_id` trước khi xác minh ID, hệ tọa độ và thời gian.

## 9. Đóng góp

Làm trên branch riêng, mở Pull Request vào `main`. Không commit `data/`, `bi/snapshots/`, `.venv*`, `dbt/profiles.yml`, mật khẩu và file database. Xem [CONTRIBUTING.md](docs/CONTRIBUTING.md).

**Tài liệu nguồn:** [LaDe (Cainiao)](https://huggingface.co/datasets/Cainiao-AI/LaDe), [dbt-sqlserver setup](https://docs.getdbt.com/docs/local/connect-data-platform/mssql-setup), [repo dự án](https://github.com/phinn-19/express-courier-data-warehouse).
