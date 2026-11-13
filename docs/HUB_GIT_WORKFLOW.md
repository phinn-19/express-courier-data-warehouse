# GIT WORKFLOW v1.1 — Hub module / ExpressCourierDW

**Repository:** https://github.com/phinn-19/express-courier-data-warehouse  
**Nguyên tắc:** `main` ổn định; A/B/C làm trên branch riêng; PR trước merge. Merge Git không di chuyển dữ liệu SQL Server.

## 1. Clone repo (mỗi máy một bản)

```powershell
git clone https://github.com/phinn-19/express-courier-data-warehouse.git
cd express-courier-data-warehouse
git switch main
git pull --ff-only origin main
git rev-parse --short HEAD
```

Nếu repo đã clone: chỉ `cd` vào repo và `git pull --ff-only`; **không chạy `git init` hoặc clone chồng**. Muốn push được branch, cần được mời collaborator và nhận lời mời (hoặc dùng fork+PR). Đọc `docs/TEAM_SETUP.md` nếu phải chạy dbt, và xác nhận đúng database dev, không dùng DB demo của nhóm trưởng.

## 2. Branch & ownership (đã cập nhật phân công)

| Branch | Owner | Chỉ sửa phần của mình |
|---|---|---|
| `feature/hub-contract` | **B** | `docs/HUB_DATA_CONTRACT.md`, `docs/HUB_TEAM_HANDOFF.md`, `docs/HUB_GIT_WORKFLOW.md`, `sql/HUB_EXPORT_PICKUP_REFERENCE.sql`, `config/hub_simulation.example.yml`; sau đó bổ sung Bus Matrix, KPI rules |
| `feature/hub-pipeline` | **C** | `scripts/generate_hub_simulation.py`, `scripts/load_hub_batches.py`, `sql/10_Create_Hub_SimRaw.sql`, `dbt/models/staging/stg_hub_*.sql`, `dbt/models/marts/*hub*.sql`, tests |
| `feature/hub-business-mart` | **B** | `dbt/models/operations/mart_hub_daily_operations.sql`, KPI tests, docs KPI |
| `feature/hub-validation` | **A** | Regression/reconciliation/benchmark scripts, docs kiểm thử, log đã ẩn dữ liệu nhạy cảm |

Không đặt A phụ trách `load_hub_batches.py` nữa — C sở hữu Hub ETL hoàn chỉnh. C nên tạo YAML test Hub riêng để tránh cùng sửa `_schema.yml` của lõi.

## 3. Thứ tự hợp nhất

1. B mở PR contract DRAFT, A/C review; B cập nhật APPROVED sau khi đã thống nhất nội dung.
2. C triển khai Generator + ETL + dbt Fact trên branch của C; A xây validation song song.
3. B làm Mart theo schema Fact C đã thống nhất; dùng cập nhật `main` khi C merge để test trên DB dev.
4. A tích hợp `main` trên DB A, thử audit/replay/regression/benchmark và báo GO/NO-GO.

**Không chờ merge hết mới code**, có thể làm song song theo contract và fixture nhỏ. Không merge PR mà chưa đọc `Files changed` và log test liên quan.

## 4. Quy trình một người push branch

```powershell
git switch main
git pull --ff-only origin main
git switch -c feature/hub-contract   # B; C/A thay tên branch tương ứng
# sửa các file được giao
git status --short
git diff --check
git add docs/HUB_DATA_CONTRACT.md docs/HUB_TEAM_HANDOFF.md docs/HUB_GIT_WORKFLOW.md sql/HUB_EXPORT_PICKUP_REFERENCE.sql config/hub_simulation.example.yml
git diff --cached --name-only
git commit -m "Add Hub simulation contract and handoff"
git push -u origin feature/hub-contract
```

Mở Pull Request trên GitHub. Mỗi PR mô tả input, output, test chạy, kết quả và phạm vi tác động. Nếu branch đã có thì dùng `git switch <branch>` thay `git switch -c`. Trước khi tạo branch, **kiểm tra `git status` để không làm mất thay đổi đang dở**.

Khi nhánh khác merge, cập nhật branch đang làm:

```powershell
git fetch origin
git switch main
git pull --ff-only origin main
git switch feature/hub-business-mart
git merge main
```

Nếu có conflict, giải quyết file được báo rồi kiểm tra/test lại; không dùng `reset --hard` hay force push để lách conflict.

## 5. Không commit gì?

- **Không commit** `.bak`, `.mdf`, `.ldf`, dữ liệu LaDe/`pickup_reference.csv`, Hub CSV generated, manifest runtime, snapshots Gold, credentials, `.env`, `.venv`, `dbt/profiles.yml`.
- Đặt CSV dưới `data/hub/` (repo `.gitignore` đã bỏ qua `data/`); `.bak` ở thư mục backup ngoài repo.
- **Có thể commit:** `.md`, `.sql`, `.py`, `.yml` không chứa bí mật và không chứa dữ liệu nguồn. Stage chính xác file định đưa lên, không dùng `git add .` khi chưa xem staged files.

## 6. Chạy database an toàn

- DB gốc của nhóm trưởng là baseline/demo, không thử code mới trên đó.
- A và C dùng DB dev riêng (restore `.bak` trên mỗi máy hoặc C dựng DB dev nhỏ). Kiểm tra `server` và `database` trong `dbt/profiles.yml` trước `dbt build`.
- Merge trên Git chỉ hợp nhất code; muốn có schema và dữ liệu ở môi trường A, cần chạy DDL/loader/dbt trên **DB A**; phải đối soát trước khi demo.
