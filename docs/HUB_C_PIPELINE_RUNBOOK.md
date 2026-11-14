# HUB C PIPELINE RUNBOOK — Generator → sim_raw → dbt Fact

**Owner:** C · **Branch:** `feature/hub-pipeline` · **Contract:** `docs/HUB_DATA_CONTRACT.md` v1.1\
**Phạm vi:** dữ liệu Hub **SIMULATED**. Không sửa model/test lõi LaDe, không chạy trên DB demo của nhóm trưởng.

## 1. File trong PR này

| File | Vai trò |
|---|---|
| `config/hub_simulation.example.yml` | Tham số kịch bản. **Bản trên `main` đang rỗng (0 byte)**; C đưa vào nguyên văn file B soạn trong `ExpressCourierDW_Hub_Handoff_v1.zip`, chỉ đổi `contract_version` 1.0 → 1.1 |
| `scripts/generate_hub_simulation.py` | Sinh `hubs.csv`, `shipments.csv`, `hub_events.csv`, `manifest.json`; deterministic; tự kiểm tra theo mục 10 |
| `sql/10_Create_Hub_SimRaw.sql` | DDL `sim_raw.Hubs/Shipments/HubEvents` + `audit.HubETLBatchLog` (PK, FK, UNIQUE, CHECK) |
| `scripts/load_hub_batches.py` | Batch ETL: kiểm SHA256 → nạp theo batch, mỗi batch 1 transaction, SKIP/REJECT, audit |
| `dbt/models/staging/_hub_sources.yml`, `stg_hub_*.sql`, `_hub_staging.yml` | Silver + tests |
| `dbt/models/marts/dim_hub.sql`, `dim_hub_event_type.sql`, `fact_hub_event.sql`, `_hub_gold.yml` | Gold + tests |
| `dbt/tests/assert_hub_*.sql`, `assert_fact_hub_event_reconciliation.sql` | Temporal, provenance, city, reconciliation, single-run |

Mọi model/test Hub có tag `hub` → chạy riêng bằng `--select tag:hub`, không build lại lõi.

## 2. Điều kiện trước khi chạy

1. DB dev của C có `dw.dim_city`, `dw.dim_date`, `dw.fact_pickup` (restore `.bak` của nhóm hoặc DB dev đúng cấu trúc) và schema `audit`.
2. `data/hub/pickup_reference.csv` do B xuất bằng `sql/HUB_EXPORT_PICKUP_REFERENCE.sql` (header `task_key,city_code,completed_at,quality_status`, `completed_at` dạng `YYYY-MM-DDTHH:MM:SS`). Không commit.
3. `dbt/profiles.yml` trỏ vào **DB dev của C**.

## 3. Chạy từng bước (PowerShell, project root)

```powershell
$PY = ".\.venv-dbt\Scripts\python.exe"
New-Item -ItemType Directory -Force evidence\hub | Out-Null

# 3.1 Kiểm tra input + config (không ghi gì)
& $PY scripts\generate_hub_simulation.py --input data\hub\pickup_reference.csv --config config\hub_simulation.example.yml --check-only

# 3.2 Sinh dữ liệu + log
& $PY scripts\generate_hub_simulation.py --input data\hub\pickup_reference.csv --config config\hub_simulation.example.yml 2>&1 | Tee-Object evidence\hub\01_generator.log

# 3.3 Chứng minh tái lập: sinh lại trong bộ nhớ, so SHA256 với manifest -> phải [PASS]
& $PY scripts\generate_hub_simulation.py --input data\hub\pickup_reference.csv --config config\hub_simulation.example.yml --verify data\hub\generated\manifest.json 2>&1 | Tee-Object evidence\hub\02_generator_replay.log
```

**3.4 SSMS:** mở `sql/10_Create_Hub_SimRaw.sql`, sửa dòng `USE` nếu DB dev tên khác, chạy F5. Chạy lại lần 2 vẫn không lỗi (idempotent).

```powershell
# 3.5 Kiểm tra file trước khi nạp (không kết nối DB)
& $PY scripts\load_hub_batches.py --input-dir data\hub\generated --check

# 3.6 Nạp tăng dần: batch 1 trước, sau đó phần còn lại (theo event time, không phải streaming/CDC)
& $PY scripts\load_hub_batches.py --input-dir data\hub\generated --load --until-batch HUB-V1-B001 --server ".\SQLEXPRESS" --database ExpressCourierDW 2>&1 | Tee-Object evidence\hub\03_load_part1.log
& $PY scripts\load_hub_batches.py --input-dir data\hub\generated --load --server ".\SQLEXPRESS" --database ExpressCourierDW 2>&1 | Tee-Object evidence\hub\04_load_rest.log

# 3.7 Replay: chạy lại toàn bộ -> mọi batch inserted 0, skipped = rows, tổng không đổi
& $PY scripts\load_hub_batches.py --input-dir data\hub\generated --load --server ".\SQLEXPRESS" --database ExpressCourierDW 2>&1 | Tee-Object evidence\hub\05_load_replay.log

# 3.8 Cùng event_id, payload khác -> phải REJECT, không ghi gì -> [PASS]
& $PY scripts\load_hub_batches.py --input-dir data\hub\generated --conflict-test --server ".\SQLEXPRESS" --database ExpressCourierDW 2>&1 | Tee-Object evidence\hub\06_conflict_test.log

# 3.9 dbt: chỉ module Hub (lõi đã có sẵn trong DB)
cd dbt
..\.venv-dbt\Scripts\dbt.exe build --select tag:hub --profiles-dir . 2>&1 | Tee-Object ..\evidence\hub\07_dbt_build_hub.log
cd ..
```

Đổi `--server` / `--database` cho đúng máy (giống cách chạy loader LaDe). Có thể đặt biến môi trường `SQL_SERVER`, `SQL_DATABASE` thay vì gõ mỗi lần.

**Lưu ý:** chỉ chạy `dbt build --select tag:hub` **sau khi nạp hết batch**. Nếu mới nạp một phần, `assert_hub_event_sequence` sẽ FAIL vì có shipment chưa có `HUB_RECEIVED`, và đó là hành vi đúng.

## 4. Kết quả mong đợi

Với `pickup_reference.csv` nhóm trưởng gửi ngày 13/11 (SHA256 `3541a77f9f5d30ee93bc468a148c0b909f327402bffadefbbd17b251cea09995`, 2.500 JILIN + 2.500 YANTAI) và config trong PR này, generator phải ra **đúng** các giá trị sau trên mọi máy:

| Đầu ra | Số dòng | SHA256 |
|---|---:|---|
| `simulation_run_id` | | `SIMRUN-3561f5dcca02ea977b93dd4a8451c8e94a16761b2f97336b40c8f7edf8e4456c` |
| `hubs.csv` | 4 | `e04ad13fd8ab94486beec08473710033027d1ee5a73d04ef693b5b2815fb6d54` |
| `shipments.csv` | 5.000 | `4c732e98acf28416a153e3439b1ef00466173c60ae9f99df644b42ef866f131c` |
| `hub_events.csv` | 15.000 | `4e59f9aaf313293a3878e791136fea53b505b8cee0149375abaad9023cfea5e7` |

3 batch: `HUB-V1-B001` (5.000 event, từ 2022-05-01), `HUB-V1-B002` (5.000), `HUB-V1-B003` (5.000, tới 2022-11-02). Không event nào bị cắt sau `as_of_ts`.

- Bước 3.3 in `[PASS] Sinh lại trùng byte với manifest.`
- Bước 3.6: lần 1 nạp 4 Hub + 5.000 Shipment + B001; lần 2 nạp B002, B003.
- Bước 3.7: các dòng `[SUCCESS] ... inserted 0, skipped N`; số dòng `sim_raw` giữ nguyên 4 / 5.000 / 15.000.
- Bước 3.8: `[PASS] Payload khác cùng event_id bị từ chối`; `audit.HubETLBatchLog` có 1 dòng `HUB-V1-CONFLICT-TEST` = FAILED (đó là bằng chứng, không phải lỗi).
- Bước 3.9: toàn bộ model + test tag `hub` PASS, 0 ERROR.

Kiểm tra nhanh trong SSMS (read-only):

```sql
SELECT batch_id, status, rows_read, rows_inserted, rows_skipped, rows_rejected, started_at
FROM audit.HubETLBatchLog ORDER BY log_id;

SELECT et.event_type, COUNT_BIG(*) AS events
FROM dw.fact_hub_event f JOIN dw.dim_hub_event_type et ON et.event_type_key = f.event_type_key
GROUP BY et.event_type;
```

## 5. Bàn giao cho A / B

- **B (Mart):** schema `dw.fact_hub_event` = `event_id, sim_shipment_id, origin_pickup_task_key, city_key, hub_key, event_type_key, event_date_key, event_ts, event_count, simulation_run_id, data_origin, source_batch_id`. `hub_key` = `hub_id` (chuỗi, vd `SIMHUB-JILIN-01`). `event_type_key`: 1 = HUB_RECEIVED, 2 = SORTING_COMPLETED, 3 = HUB_DEPARTED. Dwell = `departed_ts − received_ts` cùng `sim_shipment_id`.
- **A (kiểm chứng):** gửi qua kênh riêng `data/hub/generated/*` + thư mục `evidence/hub/` (không commit CSV). A chạy lại 3.3, 3.5–3.9 trên DB integration riêng và so `simulation_run_id`/SHA256 với manifest.

## 6. Quyết định C đã đưa ra (B/A xác nhận khi review PR)

1. Config dùng nguyên giá trị B soạn: seed `20261113`, `rules_version hub-scenario-v1`, `as_of_ts 2022-12-31T23:59:59`, 2 Hub/City, delay theo mục 5 contract, 5.000 event/batch, output `data/hub/generated`. Generator kiểm tra mọi mục `source/scenario/batching/output` và dừng nếu khác giá trị nó hỗ trợ.
2. Hub sinh theo `hubs_per_city`: `SIMHUB-<CITY>-01..NN`, tên `"<City> Simulated Hub NN"` (giả lập, không phải tên Hub thật).
3. `simulation_run_id` tính từ SHA256 **nội dung** pickup_reference đã sort theo `task_key` (không phải byte file), để kết quả không phụ thuộc thứ tự dòng/BOM/CRLF của file xuất từ SSMS. SHA256 byte file vẫn ghi trong manifest (`pickup_reference_sha256`).
4. `config_sha256` = SHA256 của config đã parse (JSON chuẩn hóa), nên sửa comment không làm đổi ID.
5. Sự kiện rơi sau `as_of_ts` không được sinh (shipment còn trong Hub); `HUB_RECEIVED` sau `as_of_ts` → generator dừng báo lỗi. Với dữ liệu hiện tại không có sự kiện nào bị cắt.
6. `hub_key` dùng mã `hub_id` (natural key ổn định), cùng kiểu khóa chuỗi với `courier_key`.
7. Source dbt Hub dùng `database: "{{ target.database }}"` thay vì ghi cứng `ExpressCourierDW`, để chạy được trên DB dev mang tên khác.
