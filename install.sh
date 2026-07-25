#!/bin/bash
#
# Cài Signal Manager lên macOS bằng 1 lệnh:
#   curl -fsSL https://raw.githubusercontent.com/dev-lo-18tuoi/multi-signal/main/install.sh | bash
#
# App được TẠO CỤC BỘ trên máy bạn (không tải app đóng gói sẵn) nên không bị
# Gatekeeper chặn. Chạy lại lệnh này bất kỳ lúc nào để cập nhật phiên bản mới.

set -euo pipefail

REPO="${SIGNAL_MANAGER_REPO:-https://raw.githubusercontent.com/dev-lo-18tuoi/multi-signal/main}"
FILES=(signal-manager.sh signal_manager_server.py signal-manager-ui.html)

say() { printf '%s\n' "$*"; }

say "🔧 Signal Manager — cài đặt"

# --- kiểm tra môi trường ---
[[ "$(uname -s)" == "Darwin" ]] || { say "❌ Chỉ hỗ trợ macOS."; exit 1; }

if [[ ! -d "/Applications/Signal.app" ]]; then
  say "❌ Chưa cài Signal Desktop. Tải tại: https://signal.org/download"
  say "   Cài Signal xong, chạy lại lệnh này."
  exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
  say "❌ Máy thiếu Command Line Tools (cần cho python3)."
  say "   Chạy:  xcode-select --install   → bấm Install trong hộp thoại, chờ xong rồi chạy lại lệnh này."
  exit 1
fi

# --- lấy source: ưu tiên file cạnh script (chạy từ repo), không thì tải từ GitHub ---
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [[ -n "$HERE" && -f "$HERE/signal-manager.sh" && -f "$HERE/signal_manager_server.py" ]]; then
  say "→ Dùng source local: $HERE"
  for f in "${FILES[@]}"; do cp "$HERE/$f" "$TMP/$f"; done
else
  say "→ Tải từ: $REPO"
  for f in "${FILES[@]}"; do
    curl -fsSL "$REPO/$f" -o "$TMP/$f" || { say "❌ Tải $f thất bại."; exit 1; }
  done
fi

chmod +x "$TMP/signal-manager.sh"
"$TMP/signal-manager.sh" install

say ""
say "✅ Cài xong! App: ~/Applications/Signal Manager.app (kéo vào Dock cho tiện)"
say "   Mỗi account Signal cần 1 số điện thoại riêng đã đăng ký trên điện thoại."
open -a "$HOME/Applications/Signal Manager.app" 2>/dev/null || true
