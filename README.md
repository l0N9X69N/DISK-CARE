# DISK-CARE

User-facing DISK-CARE release built from validated source artifact: `phase6_20260824_140503`.

---

# Tiếng Việt

## 1. Bắt đầu

Cách dùng đơn giản nhất:

1. Mở thư mục DISK-CARE.
2. Chạy `INDEX.cmd`.
3. Nhập số tương ứng với tính năng muốn sử dụng.
4. Nhấn **Enter**.
5. Xem kết quả trong thư mục `Output\`.

Người dùng thông thường **không cần chạy trực tiếp** các file bên trong `Execute\`.

## 2. Menu chính - chọn số nào để làm gì?

| Số | Tính năng | Tác dụng |
|---:|---|---|
| `1` | Quick Scan | Quét nhanh để xem tổng quan ổ đĩa và các thông tin dung lượng chính. Phù hợp để kiểm tra nhanh trước khi phân tích sâu hơn. |
| `2` | Full Scan | Chạy bộ quét đầy đủ hơn, thu thập nhiều thông tin về dung lượng, file lớn, cache và các khu vực đáng chú ý. |
| `3` | Deep Inventory | Quét sâu và lập inventory chi tiết. Dùng khi cần dữ liệu đầy đủ hơn để phân tích dung lượng. Reparse point/symlink được xử lý theo các guard an toàn của DISK-CARE. |
| `4` | Detailed Scan Tools | Mở menu các công cụ quét riêng lẻ, ví dụ Disk Summary, Top Folders, Large Files, Cache Candidates, Old Files, Recent Large Files, VHD Artifacts, Reparse Points và System Diagnostics. |
| `5` | Analyze Candidates | Phân tích dữ liệu quét và xác định các candidate cần xem xét. Đây là bước phân tích, không phải bước xóa file. |
| `6` | Build Cleanup Plan | Tạo kế hoạch cleanup từ dữ liệu đã phân tích. Kế hoạch được tạo để review trước, không tự động thực hiện xóa. |
| `7` | Harden Approved Plan | Kiểm tra/hardening kế hoạch đã được phê duyệt theo các safety gate của DISK-CARE. Các path không được chấp thuận hoặc không an toàn sẽ không được coi là executable. |
| `8` | Open Results | Mở thư mục `Output\` để xem các báo cáo đã tạo từ Scan, Analyze, Plan và Harden. |
| `9` | Verify Release Integrity | Kiểm tra tính toàn vẹn của release bằng manifest và SHA256. Dùng mục này để xác nhận các file immutable của DISK-CARE chưa bị thay đổi. |
| `0` | Exit | Thoát DISK-CARE. |

## 3. Detailed Scan Tools

Khi chọn `4`, DISK-CARE mở menu các công cụ scan riêng. Các công cụ này cho phép chạy đúng phần cần kiểm tra thay vì chạy toàn bộ Full Scan.

Các chức năng gồm:

- **Disk Summary** - tổng quan dung lượng ổ đĩa.
- **Top Folders** - tìm các thư mục chiếm nhiều dung lượng.
- **Large Files** - tìm các file lớn.
- **Cache Candidates** - liệt kê các vị trí/cache candidate để xem xét.
- **Old Files** - tìm các file cũ theo tiêu chí của công cụ.
- **Recent Large Files** - tìm các file lớn được tạo hoặc thay đổi gần đây.
- **VHD Artifacts** - kiểm tra các file/artifact liên quan đến VHD.
- **Reparse Points** - kiểm tra reparse point/junction/symlink liên quan.
- **System Diagnostics** - thu thập thông tin chẩn đoán hệ thống phục vụ việc đánh giá dung lượng.

## 4. Flow sử dụng khuyến nghị

Nếu chỉ muốn xem nhanh:

`1` -> `8`

Nếu muốn kiểm tra đầy đủ:

`2` -> `5` -> `6` -> `7` -> `8`

Nếu cần quét sâu:

`3` -> `5` -> `6` -> `7` -> `8`

Nếu chỉ muốn kiểm tra một vấn đề cụ thể:

`4` -> chọn công cụ cần dùng -> `8`

Để kiểm tra release có bị sửa hoặc hỏng file hay không:

`9`

## 5. Kết quả được lưu ở đâu?

Runtime report được ghi dưới:

```text
Output\
├─ Scan\
├─ Analyze\
├─ Plan\
└─ Harden\
```

`Output\` chỉ được tạo khi cần và không thuộc immutable release manifest.

## 6. Cấu trúc release

```text
DISK-CARE\
├─ INDEX.cmd
├─ README.md
├─ diskcare.config.json
├─ release_manifest.csv
├─ release_hashes.sha256
├─ Execute\
│  └─ các file CMD/PowerShell runtime
└─ Output\
   └─ được tạo khi chạy DISK-CARE
```

- `INDEX.cmd` - launcher/menu chính.
- `Execute\` - runtime dạng phẳng, chỉ chứa các script CMD và PowerShell cần thiết.
- `diskcare.config.json` - cấu hình runtime/hardening.
- `release_manifest.csv` - danh sách file immutable, kích thước và SHA256.
- `release_hashes.sha256` - danh sách SHA256 dùng để verify release.

Tên file runtime mô tả tính năng thực tế. Tên phase phát triển, acceptance check, regression test và historical report launcher không nằm trong user-facing runtime.

## 7. An toàn

Execution mode của release: `USER_RELEASE_ONLY`.

Release packaging không thực hiện hành động xóa hoặc cleanup.

`Deletion/Cleanup actions = 0`

Các bước Analyze, Plan và Harden được tách riêng để người dùng có thể review dữ liệu/kế hoạch trước khi có bất kỳ quyết định quản lý dung lượng nào.

---

# English

## 1. Getting started

The simplest way to use DISK-CARE:

1. Open the DISK-CARE folder.
2. Run `INDEX.cmd`.
3. Enter the number for the feature you want.
4. Press **Enter**.
5. Review generated reports under `Output\`.

Normal users **do not need to run files inside `Execute\` directly**.

## 2. Main menu - what does each number do?

| Number | Feature | Purpose |
|---:|---|---|
| `1` | Quick Scan | Performs a fast disk overview and collects the main storage information. Use this for a quick check before deeper analysis. |
| `2` | Full Scan | Runs a more complete scan and gathers broader information about disk usage, large files, cache candidates and other notable areas. |
| `3` | Deep Inventory | Performs a deeper inventory for more detailed storage analysis. Reparse points/symlinks are handled according to DISK-CARE safety guards. |
| `4` | Detailed Scan Tools | Opens a submenu of individual scan tools such as Disk Summary, Top Folders, Large Files, Cache Candidates, Old Files, Recent Large Files, VHD Artifacts, Reparse Points and System Diagnostics. |
| `5` | Analyze Candidates | Analyzes scan data and identifies candidates that may require review. This is an analysis step, not a file-deletion step. |
| `6` | Build Cleanup Plan | Builds a cleanup plan from analyzed data. The plan is produced for review and does not automatically delete files. |
| `7` | Harden Approved Plan | Validates/hardens an approved plan using DISK-CARE safety gates. Unapproved or unsafe paths are not treated as executable. |
| `8` | Open Results | Opens the `Output\` folder so you can review Scan, Analyze, Plan and Harden reports. |
| `9` | Verify Release Integrity | Verifies the release against its manifest and SHA256 hashes. Use this to confirm that immutable DISK-CARE files have not been modified. |
| `0` | Exit | Exits DISK-CARE. |

## 3. Detailed Scan Tools

Selecting `4` opens the individual scan-tools menu. These tools let you run only the inspection you need instead of running the entire Full Scan.

Available functions include:

- **Disk Summary** - shows an overview of disk capacity and usage.
- **Top Folders** - identifies folders consuming the most storage.
- **Large Files** - finds large files.
- **Cache Candidates** - lists cache/candidate locations for review.
- **Old Files** - finds older files according to the tool criteria.
- **Recent Large Files** - finds large files created or modified recently.
- **VHD Artifacts** - inspects VHD-related files/artifacts.
- **Reparse Points** - inspects relevant reparse points, junctions and symlinks.
- **System Diagnostics** - collects system diagnostic information useful for storage analysis.

## 4. Recommended workflows

For a quick check:

`1` -> `8`

For a more complete review:

`2` -> `5` -> `6` -> `7` -> `8`

For deep inventory:

`3` -> `5` -> `6` -> `7` -> `8`

For one specific inspection:

`4` -> choose the required scan tool -> `8`

To verify that the release has not been modified or corrupted:

`9`

## 5. Where are reports stored?

Runtime reports are written below:

```text
Output\
├─ Scan\
├─ Analyze\
├─ Plan\
└─ Harden\
```

`Output\` is created only when needed and is not part of the immutable release manifest.

## 6. Release layout

```text
DISK-CARE\
├─ INDEX.cmd
├─ README.md
├─ diskcare.config.json
├─ release_manifest.csv
├─ release_hashes.sha256
├─ Execute\
│  └─ runtime CMD/PowerShell files
└─ Output\
   └─ created when DISK-CARE runs
```

- `INDEX.cmd` - main interactive launcher/menu.
- `Execute\` - flat runtime directory containing only the required CMD and PowerShell scripts.
- `diskcare.config.json` - runtime/hardening configuration.
- `release_manifest.csv` - immutable release file list, sizes and SHA256 hashes.
- `release_hashes.sha256` - SHA256 list used to verify release integrity.

Runtime filenames describe their actual features. Development phase numbers, acceptance checks, regression tests and historical report launchers are not part of the user-facing runtime.

## 7. Safety

Release execution mode: `USER_RELEASE_ONLY`.

Release packaging performs no deletion or cleanup actions.

`Deletion/Cleanup actions = 0`

Analyze, Plan and Harden are separated so users can review collected data and plans before making storage-management decisions.
