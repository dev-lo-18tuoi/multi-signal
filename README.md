# Signal Manager

**Chạy nhiều account Signal Desktop song song trên một máy Mac — có dashboard quản lý tử tế.**

Signal Desktop chính thức chỉ cho 1 account. Tool này tạo cho mỗi account một
thư mục dữ liệu riêng (`--user-data-dir`, cơ chế Electron hỗ trợ sẵn) để bạn chạy
2, 3, 5… account cùng lúc, mỗi account một cửa sổ độc lập.

> 🇬🇧 English summary at the bottom.

## Tính năng

- 🖥 **Dashboard quản lý**: mỗi account một card — avatar màu riêng, nickname tự đặt,
  trạng thái chạy/tắt realtime, dung lượng dữ liệu
- ▶ **Mở / Focus / Tắt** từng account hoặc tất cả bằng 1 click
- ➕ **Thêm account**: tự tạo profile + hiện QR + hướng dẫn liên kết 3 bước
- ⚡ **Tự mở khi bật máy** (bật/tắt riêng từng account)
- 🚀 **Launcher riêng** cho từng account trong `~/Applications` (kéo vào Dock được)
- 🗑 **Xóa an toàn**: xác nhận 2 lớp, chặn xóa khi đang chạy, không bao giờ đụng account chính
- 🔒 Server chỉ chạy nội bộ (`127.0.0.1` + token phiên), không gửi gì ra ngoài

## Yêu cầu

| Thứ | Ghi chú |
|---|---|
| macOS + [Signal Desktop](https://signal.org/download) | Cài Signal trước |
| Command Line Tools | Có `python3` — nếu thiếu chạy `xcode-select --install` |
| **Mỗi account = 1 số điện thoại riêng** | Đã đăng ký Signal trên điện thoại (bản Desktop luôn là *thiết bị liên kết*, quét QR từ điện thoại). Không có cách nào tạo 2 account từ 1 số — đây là kiến trúc của Signal, không tool nào vượt được. |

## Cài đặt (1 lệnh)

```bash
curl -fsSL https://raw.githubusercontent.com/dev-lo-18tuoi/multi-signal/main/install.sh | bash
```

App `Signal Manager.app` xuất hiện trong `~/Applications` và tự mở.
**Không bị Gatekeeper chặn** vì app được tạo cục bộ ngay trên máy bạn, không phải
binary tải về. Muốn cập nhật phiên bản mới: chạy lại đúng lệnh trên.

Cài từ source:

```bash
git clone https://github.com/dev-lo-18tuoi/multi-signal && cd multi-signal && ./install.sh
```

### Hoặc qua Homebrew

```bash
brew install dev-lo-18tuoi/signal-manager/signal-manager
signal-manager install
```

(Formula nằm tại tap `dev-lo-18tuoi/homebrew-signal-manager` — xem `packaging/homebrew/`.)

## 🪟 Windows (BETA)

Chạy trong PowerShell:

```powershell
irm https://raw.githubusercontent.com/dev-lo-18tuoi/multi-signal/main/install-windows.ps1 | iex
```

Bản Windows hiện là **CLI beta** (`add / open / quit / list / autostart / remove` + shortcut
Desktop cho từng account, tự mở khi đăng nhập qua registry Run). Cùng cơ chế
`--user-data-dir` như bản Mac. Dashboard web sẽ lên Windows ở bản sau.
Beta = chưa test trên máy Windows thật — gặp lỗi xin mở issue kèm log.

## Dùng CLI (tùy chọn)

```text
./signal-manager.sh list                # bảng trạng thái
./signal-manager.sh add congviec        # thêm account
./signal-manager.sh open all            # mở tất cả
./signal-manager.sh quit congviec       # tắt 1 account
./signal-manager.sh autostart congviec on
./signal-manager.sh remove congviec     # xóa (hỏi xác nhận)
./signal-manager.sh uninstall           # gỡ tool, GIỮ dữ liệu account
```

## Bảo mật & giới hạn cần biết

- Thư mục `~/Library/Application Support/Signal-*` chứa **khóa và tin nhắn đã giải mã
  cục bộ** — bảo vệ như chính máy của bạn, đừng đồng bộ lên cloud công cộng.
- **Không copy profile sang máy khác** — khóa mã hóa gắn với Keychain của từng máy Mac.
- Khi Signal ra bản mới (~2 tuần/lần), auto-updater có thể tự đóng các cửa sổ để
  cài đặt — mở lại bằng dashboard hoặc launcher là xong, dữ liệu không mất.
- Trên cùng máy, xóa account chỉ xóa dữ liệu cục bộ; tin nhắn trên điện thoại còn nguyên.
  Nhớ gỡ thiết bị cũ trong điện thoại: *Cài đặt → Thiết bị đã liên kết*.

## Gỡ cài đặt

```bash
"$HOME/Applications/Signal Manager.app/Contents/Resources/signal-manager.sh" uninstall
```

Dữ liệu account không bị đụng tới.

---

## English summary

Run multiple Signal Desktop accounts side-by-side on one Mac. Each account gets its
own data directory via Electron's `--user-data-dir`; a local web dashboard
(127.0.0.1 + session token, zero external calls) manages them: open/focus/quit,
add with QR-link guidance, per-account login autostart, colored avatars &
nicknames, safe two-step delete. Install with one command (see above) — the app
bundle is generated locally so Gatekeeper never complains. Each account requires
its own phone number registered in Signal on a phone (Desktop is always a linked
device — that's Signal's architecture, not a tool limitation).

## Credits & prior art

Cơ chế `--user-data-dir` được cộng đồng dùng từ lâu:
[kmille/signal-account-switcher](https://github.com/kmille/signal-account-switcher),
[phx/signal-multi-account](https://github.com/phx/signal-multi-account),
[blanchardjeremy/signal-multiple-desktop-mac](https://github.com/blanchardjeremy/signal-multiple-desktop-mac).
Tool này viết mới hoàn toàn (clean-room), tập trung vào UX + an toàn.

## Giấy phép & miễn trừ

MIT License — xem [LICENSE](LICENSE).
Dự án không chính thức, không liên kết, không được bảo trợ bởi Signal Messenger LLC
hay Signal Foundation. "Signal" là nhãn hiệu của Signal Messenger LLC.
