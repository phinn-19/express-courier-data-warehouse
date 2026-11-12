# Thiết lập ExpressCourierDW trên máy mới (Windows)

> **Đây là hướng dẫn clone và chạy lại, không phải script tự copy database của nhóm trưởng.** Clone GitHub chỉ có code. Database và CSV cần được tạo/cung cấp riêng.

## 1. Chọn nhu cầu trước khi cài

| Bạn cần làm | Cần clone? | Cần SQL Server local? | Cần dữ liệu |
|---|---|---|---|
| Xem/sửa SQL, docs, Bus Matrix | Có | Không | Không bắt buộc |
| BI dùng bản Gold v2 | Có thể | Không | 7 CSV Gold + manifest do nhóm gửi riêng |
| Profile GPS / trajectory | Có | Không | File CSV nguồn được phép sử dụng |
| Chạy dbt test / sửa model | Có | Có hoặc DB dev riêng | Raw của các city đang thử |
| Benchmark / Index | Có | Có, và phải dùng dữ liệu/khối lượng tương đương | DB thích hợp, có quyền test |

**Không kết nối thẳng SQL Server laptop của người khác qua Internet.** Nếu thật sự cần chung DB, dùng môi trường mạng riêng và tài khoản giới hạn quyền. Đặc biệt dbt `build` có thể tạo/thay đổi các bảng trong `stg`, `dw`, `mart`, nên không chạy đồng thời trên database demo chính.

## 2. Yêu cầu hệ thống

- Windows 10/11 x64; Git; PowerShell; Python **3.12** (đã được nhóm dùng); ODBC Driver **18** for SQL Server.
- Nếu chạy DW: SQL Server 2022 Express/Developer và SSMS. Đảm bảo đủ dung lượng; bản Express có giới hạn kích thước database.
- Nếu làm BI: Power BI Desktop và đủ dung lượng cho 7 CSV Gold.

Đăng nhập GitHub nếu repository yêu cầu. Clone:

```powershell
git clone https://github.com/phinn-19/express-courier-data-warehouse.git
cd express-courier-data-warehouse
```

Không đặt code trong `D:\ExpressCourierDW` bắt buộc; path tương đối trong README hoạt động ở bất kỳ thư mục clone nào.

## 3. Cài Python và dbt

```powershell
py -3.12 -m venv .venv-dbt
.\.venv-dbt\Scripts\python.exe -m pip install --upgrade pip
.\.venv-dbt\Scripts\python.exe -m pip install -r requirements-dbt.txt
.\.venv-dbt\Scripts\dbt.exe --version
.\.venv-dbt\Scripts\python.exe -c "import pyodbc; print(pyodbc.drivers())"
```

Nếu chỉ nghiên cứu CSV, có thể dùng môi trường nhỏ hơn:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

Không yêu cầu mọi người kích hoạt cùng một môi trường; gọi thẳng `.venv-dbt\Scripts\python.exe` tránh lẫn Python.

## 4. Cấu hình SQL Server — đừng sửa các dbt model để đổi server

Cấu hình kết nối chính nằm tại **`dbt/profiles.yml`**. Chạy từ root:

```powershell
Copy-Item .\dbt\profiles.example.yml .\dbt\profiles.yml
notepad .\dbt\profiles.yml
```

**Mẫu mặc định giả định localhost:1433**, không chắc đúng với `SQLEXPRESS` của từng máy. Trong SSMS kiểm tra server name; với named instance SQL Express cần xem TCP/IP có bật và đang lắng nghe cổng nào. Nếu không có fixed port 1433, phải cấu hình theo instance thực, không ép thay bừa thành `localhost`. Nên sao chép cấu trúc từ **profiles.yml đã kết nối thành công trên chính máy đó**, không sao chép password hoặc đường dẫn riêng của nhóm trưởng. `windows_login: true` dùng Windows Authentication. `trust_cert: true` chỉ dùng cho môi trường local development với chứng chỉ tự ký; môi trường vận hành thực cần cấu hình TLS tin cậy.

Kiểm tra:

```powershell
cd dbt
..\.venv-dbt\Scripts\dbt.exe debug --profiles-dir .
cd ..
```

`All checks passed!` nghĩa là kết nối/config phù hợp, **không** nghĩa database đã có dữ liệu.

### Loader và exporter không dùng cùng cấu hình với dbt

`03_Load_Raw_Idempotent_v2.py`: hỗ trợ `--server`, `--database`; có biến `SQL_SERVER`, `SQL_DATABASE`. Ví dụ máy SQL Express local:

```powershell
$env:SQL_SERVER = '.\SQLEXPRESS'
$env:SQL_DATABASE = 'ExpressCourierDW'
```

`export_powerbi_snapshot.py` trên `main` dùng **`DW_SQL_SERVER`**; biến này không tự nhận `$env:SQL_SERVER`. Nếu cần chạy bản export cũ, dùng `$env:DW_SQL_SERVER` và nhớ manifest còn gắn nhãn Jilin v1. Chỉ dùng bản export multi-city đã được nhóm nghiệm thu để bàn giao dữ liệu Jilin+Yantai.

## 5. Chuẩn bị database local mới

**Cảnh báo:** chỉ thực hiện nếu cần dựng DW trên máy riêng. Không chạy các lệnh nạp lên database demo của nhóm mà không thống nhất.

Trong SSMS kết nối vào SQL Server local của bạn, chạy lần lượt:

1. `00_Create_ExpressCourierDW.sql` — tạo DB, bảng Raw và audit ban đầu, không xóa dữ liệu.
2. `03_Upgrade_ETLRunLog_v2.sql` — bổ sung cột audit và unique index cho v2.1.

`02_Verify_Raw_ExpressCourierDW.sql` có các ghi chú kỳ vọng từ Jilin v1, nên khi đã có hai thành phố hãy dùng truy vấn phân nhóm City để đối soát thay vì coi tổng Jilin là tổng DB.

Dữ liệu nguồn không được commit. Lấy từ nguồn chính thức [Cainiao-AI/LaDe](https://huggingface.co/datasets/Cainiao-AI/LaDe), xác minh quyền sử dụng, hash/header; để tại:

```text
data/
  pickup_jl.csv
  delivery_jl.csv
  pickup_yt.csv
  delivery_yt.csv
```

Tên file này là quy ước ví dụ. Không có file thì bước `--check`/`--load` không thể chạy.

## 6. Nạp dữ liệu an toàn

**Các lệnh chỉ dành cho DB local MỚI, Raw chưa có dữ liệu tại city/process:**

```powershell
.\.venv-dbt\Scripts\python.exe .\scripts\03_Load_Raw_Idempotent_v2.py --process pickup --city Jilin --file .\data\pickup_jl.csv --check
.\.venv-dbt\Scripts\python.exe .\scripts\03_Load_Raw_Idempotent_v2.py --process pickup --city Jilin --file .\data\pickup_jl.csv --load

.\.venv-dbt\Scripts\python.exe .\scripts\03_Load_Raw_Idempotent_v2.py --process delivery --city Jilin --file .\data\delivery_jl.csv --check
.\.venv-dbt\Scripts\python.exe .\scripts\03_Load_Raw_Idempotent_v2.py --process delivery --city Jilin --file .\data\delivery_jl.csv --load

.\.venv-dbt\Scripts\python.exe .\scripts\03_Load_Raw_Idempotent_v2.py --process pickup --city Yantai --file .\data\pickup_yt.csv --check
.\.venv-dbt\Scripts\python.exe .\scripts\03_Load_Raw_Idempotent_v2.py --process pickup --city Yantai --file .\data\pickup_yt.csv --load

.\.venv-dbt\Scripts\python.exe .\scripts\03_Load_Raw_Idempotent_v2.py --process delivery --city Yantai --file .\data\delivery_yt.csv --check
.\.venv-dbt\Scripts\python.exe .\scripts\03_Load_Raw_Idempotent_v2.py --process delivery --city Yantai --file .\data\delivery_yt.csv --load
```

Loader **không hỗ trợ append/thay thế file cùng process-city** và không được chạy nhiều phiên song song. `--check` kiểm tra CSV và đọc trạng thái DB; **không phải chỉ kiểm tra CSV offline**.

Nếu DB đã có Raw nhưng audit v2 chưa có SUCCESS, **KHÔNG** chạy `--load` hay xóa dữ liệu. Chỉ dùng `--register-existing` khi đã đối chiếu toàn bộ CSV với Raw theo logic của script. Nếu báo audit SUCCESS và checksum khớp, lần nạp lại sẽ SKIP; không cố ép nạp lại.

## 7. Build dbt và đối soát

```powershell
cd dbt
..\.venv-dbt\Scripts\dbt.exe debug --profiles-dir .
..\.venv-dbt\Scripts\dbt.exe build --profiles-dir .
cd ..
```

`dbt build` tạo bảng ở `stg`, `dw`, `mart` và chạy tests. Nếu có lỗi, lưu phần log cuối, không thử thay mãng dữ liệu thủ công. Sau đó chạy trong SSMS:

```sql
USE ExpressCourierDW;
SELECT c.city_code, 'PICKUP' AS process_code, COUNT_BIG(*) AS task_rows
FROM dw.fact_pickup AS f JOIN dw.dim_city AS c ON f.city_key = c.city_key
GROUP BY c.city_code
UNION ALL
SELECT c.city_code, 'DELIVERY', COUNT_BIG(*)
FROM dw.fact_delivery AS f JOIN dw.dim_city AS c ON f.city_key = c.city_key
GROUP BY c.city_code
ORDER BY city_code, process_code;
```

Nếu đúng đủ bốn file nguồn như nhóm đã profile, kỳ vọng: JILIN/PICKUP 261801, JILIN/DELIVERY 31415, YANTAI/PICKUP 1146781, YANTAI/DELIVERY 206431. Cần kiểm chứng thêm Raw, Silver, các Mart và audit. **Không suy ra 1,646,428 vận đơn duy nhất.**

## 8. Dành cho bạn Power BI

Người phụ trách dữ liệu gửi riêng bộ **Gold v2** gồm 7 CSV (`dim_date`, `dim_city`, `dim_courier`, `dim_region`, `dim_aoi`, `fact_pickup`, `fact_delivery`) và `manifest.json`. Không lấy `bi/snapshots.zip` trong repo làm bản Jilin+Yantai nếu không kiểm tra, vì bộ đó có thể là Jilin v1. Import từng bảng, kiểm tra datatype và relationships, tạo báo cáo theo tài liệu handoff. Không cần kết nối trực tiếp SQL Server chính.

## 9. Lỗi hay gặp

| Hiện tượng | Cách kiểm tra |
|---|---|
| `dbt: command not found` | Dùng `..\.venv-dbt\Scripts\dbt.exe` từ thư mục dbt |
| `profiles.yml not found` | Copy `dbt/profiles.example.yml` thành `dbt/profiles.yml` (bản thật bị ignore) |
| `Login failed` / `08001` | Kiểm tra instance, TCP port, SQL Server service, Windows login, ODBC Driver 18 |
| `Invalid object name raw.PickupTasks` | Chạy SQL bootstrap trên DB local được chọn |
| `CSV file not found` | Data không nằm trong repo; kiểm tra đường dẫn `data/...` |
| `dbt build` không có cùng 85 PASS | Có thể chưa nạp đủ 2 thành phố, code/test khác phiên bản hoặc database khác |
| `Duplicate city already loaded` | Không nạp lại cùng city/process; xem audit/--check |
| `Encryption/certificate error` | Kiểm tra trust config trong dev; không tắt TLS bừa bãi trên môi trường thật |

**Nguồn xác minh:** [dbt SQL Server setup](https://docs.getdbt.com/docs/local/connect-data-platform/mssql-setup), [LaDe](https://huggingface.co/datasets/Cainiao-AI/LaDe).
