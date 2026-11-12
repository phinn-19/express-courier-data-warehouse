# Cộng tác với ExpressCourierDW

## Trước khi sửa code

1. Clone repo; xem `README.md` và `docs/TEAM_SETUP.md`.
2. Chọn phạm vi: Core DW, Business/Performance, GPS/Research, hoặc Power BI.
3. Không chạy các lệnh `--load`, `dbt build` hoặc tạo Index lên **database demo chung** nếu chưa được người phụ trách DB xác nhận. Ưu tiên DB dev local.
4. **Tuyệt đối không** commit CSV Raw, Gold snapshot, SQL backups, mật khẩu, `dbt/profiles.yml` hay `.env`.

## Quy trình Git

```powershell
git switch main
git pull --ff-only origin main
git switch -c feature/ten-chuc-nang
# sửa code / docs
# chạy test phù hợp
git status --short
git diff --check
git add <duong-dan-file-da-kiem-tra>
git diff --cached --name-only
git commit -m "Describe change"
git push -u origin feature/ten-chuc-nang
```

Mở Pull Request vào `main`, kèm: mục tiêu, file thay đổi, lệnh kiểm thử, kết quả, rủi ro và ảnh kết quả nếu có. Ít nhất một thành viên khác review. Không commit tự động bằng `git add .` khi chưa kiểm tra `git status`.

## Quy ước kiểm thử

- Thay đổi staging/Gold/Mart → dbt build/test trên DB dev, đối soát City × Process.
- Thay đổi ingestion → --check trên CSV, xét checksum/audit, không phá dữ liệu Raw có sẵn.
- Thay đổi KPI → công thức, bộ lọc, mẫu số và test SQL–Power BI phải nhất quán.
- Nâng cấp GPS/trajectory → chứng minh nguồn, grain, mapping ID, thời gian, tọa độ; nếu chưa đủ, ghi HOLD/NO-GO, không ghép giả.
- Performance → cùng kết quả truy vấn, nhiều lần chạy, execution plan và IO/CPU/elapsed; không khẳng định Index tốt hơn khi chưa đo.

## Báo cáo và chứng cứ

Mỗi PR thay đổi nghiệp vụ/logic phải có phần 'Tại sao làm?' và 'Làm sao biết nó đúng?'. Các ảnh/log kết quả có thể đưa vào `docs/` sau khi loại thông tin nhạy cảm, không đẩy snapshot dữ liệu lớn lên repo công khai.
