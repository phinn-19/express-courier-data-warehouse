# ExpressCourierDW — Hướng dẫn GitHub Private từ VS Code (Windows)

## Bước 0 — Những gì đưa lên GitHub

**ĐƯA LÊN:** Python ingest/export, SQL DDL, dbt models/tests/macros/dbt_project.yml, docs/README, các biểu đồ kiến trúc, project Power BI nếu kích thước phù hợp.

**KHÔNG ĐƯA LÊN:** raw CSV trong data/, bản CSV xuất bi/snapshots/, `.venv`, `.venv-dbt`, `dbt/profiles.yml`, file có mật khẩu/API keys, SQL Server `.bak/.mdf/.ldf`, các file cache/log.

Thêm vào `.gitignore` hiện có, KHÔNG thay thế nếu tệp đã có nội dung:

```gitignore
.venv/
.venv-dbt/
__pycache__/
*.pyc

data/
bi/snapshots/

dbt/target/
dbt/logs/
dbt/profiles.yml

.env
.env.*
*.pem
*.p8
*.key

*.bak
*.mdf
*.ldf

**/.pbi/localSettings.json
**/.pbi/cache.abf
```

Không đưa config có thông tin cá nhân/mật khẩu vào README. Có thể tạo `dbt/profiles.example.yml` dùng `<SERVER_NAME>` và ghi rõ ví dụ là placeholder.

## Bước 1 — Chuẩn bị thư mục

Từ `D:\ExpressCourierDW`, tạo `scripts/` và `docs/`. Copy:

- `scripts/export_powerbi_snapshot.py`
- `docs/POWERBI_HANDOFF.md`

Giữ nguyên các file dbt models đã hoàn thiện. Kiểm tra `.gitignore` trước khi stage.

## Bước 2 — Git lần đầu trên máy

Mở **VS Code → Terminal → New Terminal (PowerShell)** ở thư mục dự án:

```powershell
cd D:\ExpressCourierDW
git --version
git status
```

- Nếu `git status` báo `not a git repository`, chạy `git init`.
- Nếu đã là repository thì **KHÔNG** `git init` lại hoặc xóa `.git`.

```powershell
git check-ignore -v data/pickup_jl.csv dbt/profiles.yml bi/snapshots/fact_pickup.csv
git add .
git status --short
git diff --cached --name-only
```

**DỪNG nếu thấy** tên raw data, snapshot CSV, `.venv`, secrets, `dbt/profiles.yml` trong staged files. Bỏ stage bằng:

```powershell
git restore --staged <path-to-file>
```

Nếu file nhạy cảm **đã được theo dõi từ trước**, `.gitignore` không loại nó khỏi index; sau khi kiểm tra, dùng `git rm --cached <path-to-file>` để bỏ khỏi index mà vẫn giữ file trên máy. Nếu bí mật từng được commit/push, còn cần xử lý lịch sử và thay đổi credentials.

Sau khi chắc chắn chỉ có code/docs:

```powershell
git commit -m "Build LaDe Gold Jilin v1 and add BI handoff"
```

Nếu Git hỏi tên/email, cấu hình `git config --global user.name "<Ten GitHub>"` và `git config --global user.email "<Email cua m>"` (dùng email noreply GitHub nếu muốn bảo vệ email).

## Bước 3 — Tạo GitHub repository Private

1. Vào https://github.com/new → Repository name `ExpressCourierDW` → **Private**.
2. Với repository mới từ code local, **không tick** `Add a README`, `.gitignore`, `license` để tránh xung đột commit ban đầu.
3. Sao chép HTTPS URL thật từ trang repository vừa tạo, ví dụ `https://github.com/<ACCOUNT>/ExpressCourierDW.git` (thay `<ACCOUNT>` bằng username thực tế).

Tại terminal:

```powershell
git remote -v
```

Nếu **chưa** có `origin`:

```powershell
git remote add origin https://github.com/<ACCOUNT>/ExpressCourierDW.git
git branch -M main
git push -u origin main
```

Nếu **đã** có `origin`, kiểm tra đúng URL rồi dùng `git push -u origin main` trên branch mong muốn; đừng tự động ghi đè remote cũ.

Trình duyệt có thể bật trang đăng nhập GitHub để xác thực. **Không nhập mật khẩu GitHub vào URL remote.**

## Bước 4 — Mời bạn vào repo

GitHub Repository → **Settings → Collaborators** (hoặc Collaborators and teams) → **Add people** → nhập username bạn → gửi lời mời. Bạn nhận lời rồi clone repo:

```powershell
git clone https://github.com/<ACCOUNT>/ExpressCourierDW.git
```

**Lưu ý:** clone repo nhận code và báo cáo nếu có, **không** nhận database SQL Server ở laptop nhóm trưởng và **không** nhận 7 CSV đã bị ignore; chia sẻ snapshot qua Google Drive riêng tư.

## Bước 5 — Làm việc nhóm sau này

DE (máy m):

```powershell
git add dbt scripts docs
git commit -m "Add operations mart v1"
git push
```

Power BI: làm branch riêng (ví dụ `feature/powerbi`), commit báo cáo và ảnh; một người tích hợp file `.pbix`. Với `.pbip` có thể quản lý source report tốt hơn, nhưng vẫn cần phối hợp khi cùng sửa semantic model.

Nếu `pbix` lớn hơn **100 MiB**, Git thông thường không nhận; chia sẻ file qua Drive hoặc đánh giá PBIP/Git LFS. Đừng bỏ raw dataset lên GitHub chỉ để phục vụ Power BI.
