#!/usr/bin/env bash
#
# signal-manager.sh — engine quản lý nhiều account Signal Desktop trên macOS.
# Mỗi account = 1 thư mục dữ liệu riêng (--user-data-dir), chạy song song được.
#
# GUI: Signal Manager.app (web dashboard local) — cài bằng: ./signal-manager.sh install
# Tool không chính thức, không liên quan Signal Messenger LLC.

set -euo pipefail

SIGNAL_APP="${SIGNAL_APP:-/Applications/Signal.app}"
SIGNAL_BIN="$SIGNAL_APP/Contents/MacOS/Signal"
BASE="$HOME/Library/Application Support"
PREFIX="Signal-"
LAUNCHER_DIR="$HOME/Applications"
AGENT_DIR="$HOME/Library/LaunchAgents"
NAME_RE='^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$'

err() { printf 'Lỗi: %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }

usage() {
  cat <<'EOF'
signal-manager.sh — quản lý nhiều account Signal Desktop (macOS)

Lệnh:
  menu               mở dashboard quản lý (web UI local)
  list               liệt kê account (dạng bảng, cho người đọc)
  state [--fast]     trạng thái dạng JSON (cho GUI; --fast bỏ qua tính dung lượng)
  add <tên>          tạo account mới, mở cửa sổ QR liên kết, tạo launcher
  autostart <tên> on|off   bật/tắt tự mở account khi đăng nhập Mac (default = bản chính)
  open <tên>         mở/focus account; "open all" tất cả; "open default" bản chính
  quit <tên>         tắt account; "quit all" tất cả; "quit default" bản chính
  remove <tên>       xóa vĩnh viễn dữ liệu account trên máy này (hỏi xác nhận, --yes để bỏ qua)
  launcher <tên>     tạo lại app launcher riêng cho account
  install            cài "Signal Manager.app" vào ~/Applications
  uninstall          gỡ app + launcher + autostart (KHÔNG đụng dữ liệu account)
  help               trợ giúp

Tên account: chữ/số/gạch ngang/gạch dưới, tối đa 32 ký tự.
Dữ liệu:  ~/Library/Application Support/Signal-<tên>
Lưu ý: mỗi account cần 1 số điện thoại riêng đã đăng ký Signal trên điện thoại.
EOF
}

check_signal() { [[ -x $SIGNAL_BIN ]] || die "không tìm thấy Signal.app trong /Applications"; }

validate_name() {
  [[ $1 =~ $NAME_RE ]] || die "tên '$1' không hợp lệ (chỉ chữ/số/-/_, tối đa 32 ký tự)"
}

profile_dir() { printf '%s/%s%s' "$BASE" "$PREFIX" "$1"; }

# Instance của profile đang chạy? (khớp trọn flag, tránh trùng tiền tố tên: Signal-2 vs Signal-22)
is_running() {
  local needle="--user-data-dir=$1" line
  while IFS= read -r line; do
    case "$line " in *"$needle "*) return 0 ;; esac
  done < <(ps ax -o command=)
  return 1
}

# Signal mặc định (không có --user-data-dir) đang chạy?
default_running() {
  local line
  while IFS= read -r line; do
    case $line in
      "$SIGNAL_BIN"*)
        case $line in *--user-data-dir=*) ;; *) return 0 ;; esac ;;
    esac
  done < <(ps ax -o command=)
  return 1
}

# PID các process chính (không phải Helper) của 1 profile ("default" = bản chính)
signal_pids() {
  local target=$1 pid cmd
  while read -r pid cmd; do
    case $cmd in
      "$SIGNAL_BIN"|"$SIGNAL_BIN "*)
        if [[ $target == default ]]; then
          case $cmd in *--user-data-dir=*) ;; *) printf '%s\n' "$pid" ;; esac
        else
          case "$cmd " in *"--user-data-dir=$target "*) printf '%s\n' "$pid" ;; esac
        fi ;;
    esac
  done < <(ps ax -o pid= -o command=)
}

# In danh sách tên profile (mỗi dòng một tên), không gồm profile mặc định
profile_names() {
  local d
  for d in "$BASE/$PREFIX"*/; do
    [[ -d $d ]] || continue
    d=${d%/}
    printf '%s\n' "${d##*/$PREFIX}"
  done
}

cmd_list() {
  local name dir size state
  printf '%-14s %-10s %-8s %s\n' "TÊN" "TRẠNG THÁI" "DUNG LG" "THƯ MỤC"
  if [[ -d "$BASE/Signal" ]]; then
    if default_running; then state="đang chạy"; else state="tắt"; fi
    size=$(du -sh "$BASE/Signal" 2>/dev/null | cut -f1)
    printf '%-14s %-10s %-8s %s\n' "(chính)" "$state" "${size:-?}" "$BASE/Signal"
  fi
  while IFS= read -r name; do
    dir=$(profile_dir "$name")
    if is_running "$dir"; then state="đang chạy"; else state="tắt"; fi
    size=$(du -sh "$dir" 2>/dev/null | cut -f1)
    printf '%-14s %-10s %-8s %s\n' "$name" "$state" "${size:-?}" "$dir"
  done < <(profile_names)
}

# JSON cho GUI. Tên profile đã qua NAME_RE nên an toàn để nhúng thẳng.
cmd_state() {
  local fast=${1:-} name dir running size auto first=1
  json_entry() { # $1=name $2=dir $3=running $4=size_kb $5=is_default $6=autostart
    [[ $first == 1 ]] && first=0 || printf ','
    printf '{"name":"%s","dir":"%s","running":%s,"size_kb":%s,"is_default":%s,"autostart":%s}' \
      "$1" "${2//\"/\\\"}" "$3" "$4" "$5" "$6"
  }
  printf '['
  if [[ -d "$BASE/Signal" ]]; then
    if default_running; then running=true; else running=false; fi
    if [[ $fast == "--fast" ]]; then size=null; else size=$(du -sk "$BASE/Signal" 2>/dev/null | cut -f1); size=${size:-null}; fi
    if [[ -f $(agent_plist default) ]]; then auto=true; else auto=false; fi
    json_entry "__default__" "$BASE/Signal" "$running" "$size" true "$auto"
  fi
  while IFS= read -r name; do
    dir=$(profile_dir "$name")
    if is_running "$dir"; then running=true; else running=false; fi
    if [[ $fast == "--fast" ]]; then size=null; else size=$(du -sk "$dir" 2>/dev/null | cut -f1); size=${size:-null}; fi
    if [[ -f $(agent_plist "$name") ]]; then auto=true; else auto=false; fi
    json_entry "$name" "$dir" "$running" "$size" false "$auto"
  done < <(profile_names)
  printf ']\n'
}

# ---------- Tự mở khi đăng nhập (LaunchAgent) ----------

agent_plist() { printf '%s/local.signal-autostart.%s.plist' "$AGENT_DIR" "$1"; }

cmd_autostart() { # $1=tên|default $2=on|off
  local name=$1 mode=$2 dir plist
  [[ $mode == on || $mode == off ]] || die "dùng: autostart <tên|default> on|off"
  if [[ $name != default ]]; then
    validate_name "$name"
    dir=$(profile_dir "$name")
    [[ -d $dir ]] || die "account '$name' không tồn tại"
  fi
  plist=$(agent_plist "$name")
  if [[ $mode == off ]]; then
    rm -f "$plist"
    printf "Đã tắt tự mở cho '%s'.\n" "$name"
    return
  fi
  mkdir -p "$AGENT_DIR"
  {
    printf '<?xml version="1.0" encoding="UTF-8"?>\n'
    printf '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    printf '<plist version="1.0">\n<dict>\n'
    printf '  <key>Label</key><string>local.signal-autostart.%s</string>\n' "$name"
    printf '  <key>ProgramArguments</key>\n  <array>\n'
    printf '    <string>/usr/bin/open</string>\n'
    if [[ $name == default ]]; then
      printf '    <string>-a</string>\n    <string>%s</string>\n' "$SIGNAL_APP"
    else
      printf '    <string>-na</string>\n    <string>%s</string>\n' "$SIGNAL_APP"
      printf '    <string>--args</string>\n    <string>--user-data-dir=%s</string>\n' "$dir"
    fi
    printf '  </array>\n'
    printf '  <key>RunAtLoad</key><true/>\n'
    printf '</dict>\n</plist>\n'
  } > "$plist"
  printf "Đã bật tự mở cho '%s' — account sẽ tự chạy mỗi lần đăng nhập Mac.\n" "$name"
}

cmd_uninstall() {
  local name
  rm -rf "$LAUNCHER_DIR/Signal Manager.app"
  rm -f "$(agent_plist default)"
  while IFS= read -r name; do
    rm -rf "$LAUNCHER_DIR/Signal $name.app"
    rm -f "$(agent_plist "$name")"
  done < <(profile_names)
  pkill -f signal_manager_server.py 2>/dev/null || true
  rm -rf "$BASE/Signal Manager"
  cat <<'EOF'
Đã gỡ Signal Manager (app, launcher, autostart, server).
DỮ LIỆU các account (Signal-*) vẫn còn nguyên — Signal vẫn dùng được qua lệnh:
  open -na Signal --args --user-data-dir="$HOME/Library/Application Support/Signal-<tên>"
EOF
}

launch_profile() { # mở hoặc focus (singleton lock per-dir tự focus cửa sổ cũ)
  check_signal
  open -na "$SIGNAL_APP" --args --user-data-dir="$1"
}

cmd_open() {
  local name=$1 dir
  case $name in
    all)
      check_signal
      [[ -d "$BASE/Signal" ]] && open -a "$SIGNAL_APP"
      while IFS= read -r name; do
        launch_profile "$(profile_dir "$name")"
        sleep 1
      done < <(profile_names)
      return ;;
    default)
      check_signal
      open -a "$SIGNAL_APP"
      return ;;
  esac
  validate_name "$name"
  dir=$(profile_dir "$name")
  [[ -d $dir ]] || die "account '$name' chưa tồn tại (dùng: add $name)"
  launch_profile "$dir"
}

cmd_quit() {
  local name=$1 dir pids
  case $name in
    all)
      pids=$(signal_pids default || true)
      while IFS= read -r n; do
        pids+=$'\n'"$(signal_pids "$(profile_dir "$n")" || true)"
      done < <(profile_names)
      ;;
    default) pids=$(signal_pids default || true) ;;
    *)
      validate_name "$name"
      dir=$(profile_dir "$name")
      [[ -d $dir ]] || die "account '$name' không tồn tại"
      pids=$(signal_pids "$dir" || true)
      ;;
  esac
  pids=$(printf '%s\n' "$pids" | grep -E '^[0-9]+$' || true)
  [[ -n $pids ]] || { printf 'Không có instance nào đang chạy.\n'; return 0; }
  # SIGTERM = quit êm (Electron xử lý before-quit, dữ liệu an toàn)
  printf '%s\n' "$pids" | xargs kill 2>/dev/null || true
  printf 'Đã gửi lệnh tắt.\n'
}

cmd_add() {
  local name=$1 dir
  validate_name "$name"
  dir=$(profile_dir "$name")
  [[ -e $dir ]] && die "account '$name' đã tồn tại (dùng: open $name)"
  mkdir -p "$dir"
  chmod 700 "$dir"
  launch_profile "$dir"
  make_launcher "$name" >/dev/null
  cat <<EOF
Đã tạo account '$name'. Cửa sổ Signal mới sẽ hiện mã QR.
Trên điện thoại giữ số của account này:
  Signal → Cài đặt → Thiết bị đã liên kết → Liên kết thiết bị mới → quét QR.
Mở lại sau này: ~/Applications/Signal $name.app
EOF
}

# Màu đại diện theo tên account (ổn định, khớp tinh thần bảng màu dashboard)
profile_color() {
  local palette=("#3A76F0" "#34C759" "#FF9F0A" "#FF453A" "#BF5AF2" "#5AC8FA" "#E6B800" "#FF2D55")
  local sum
  sum=$(printf '%s' "$1" | cksum | cut -d' ' -f1)
  printf '%s' "${palette[$((sum % 8))]}"
}

# Icon .icns riêng cho account: squircle màu riêng + nhãn tên to — nhìn Dock là
# phân biệt được ngay, không nhầm với Signal thật. Cần qlmanage/sips/iconutil
# (đều có sẵn macOS); lỗi thì caller tự fallback icon Signal.
make_profile_icon() { # $1=tên $2=đường dẫn .icns đích
  local name=$1 dest=$2 color label size tmp s d
  color=$(profile_color "$name")
  label=$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]' | cut -c1-3)
  case ${#label} in 1) size=430 ;; 2) size=330 ;; *) size=230 ;; esac
  tmp=$(mktemp -d) || return 1
  cat > "$tmp/icon.svg" <<EOF
<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="$color"/>
      <stop offset="1" stop-color="#141021"/>
    </linearGradient>
    <clipPath id="sq"><rect x="100" y="100" width="824" height="824" rx="186"/></clipPath>
  </defs>
  <rect x="100" y="100" width="824" height="824" rx="186" fill="url(#g)"/>
  <g clip-path="url(#sq)">
    <g fill="none" stroke="#ffffff" stroke-linecap="round">
      <path d="M 736,236 A 56,56 0 0 1 792,292" stroke-width="24" opacity="0.85"/>
      <path d="M 736,200 A 92,92 0 0 1 828,292" stroke-width="22" opacity="0.5"/>
    </g>
    <text x="512" y="540" font-family="Menlo, monospace" font-size="$size" font-weight="bold"
          fill="#ffffff" text-anchor="middle" dominant-baseline="central">$label</text>
    <path d="M100,762 Q 260,722 420,762 T 740,762 T 1060,762 L 1060,924 L 100,924 Z" fill="#000" opacity="0.28"/>
  </g>
</svg>
EOF
  qlmanage -t -s 1024 -o "$tmp" "$tmp/icon.svg" >/dev/null 2>&1
  [[ -f "$tmp/icon.svg.png" ]] || { rm -rf "$tmp"; return 1; }
  mkdir -p "$tmp/i.iconset"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" "$tmp/icon.svg.png" --out "$tmp/i.iconset/icon_${s}x${s}.png" >/dev/null 2>&1
    d=$((s*2))
    sips -z "$d" "$d" "$tmp/icon.svg.png" --out "$tmp/i.iconset/icon_${s}x${s}@2x.png" >/dev/null 2>&1
  done
  iconutil -c icns "$tmp/i.iconset" -o "$dest" 2>/dev/null || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
}

make_launcher() { # tạo ~/Applications/Signal <tên>.app
  local name=$1 app icns
  check_signal
  app="$LAUNCHER_DIR/Signal $name.app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cat > "$app/Contents/MacOS/launcher" <<EOF
#!/bin/sh
exec "$SIGNAL_BIN" --user-data-dir="\$HOME/Library/Application Support/$PREFIX$name"
EOF
  chmod +x "$app/Contents/MacOS/launcher"
  # icon màu riêng theo account; lỗi thì dùng icon Signal
  if ! make_profile_icon "$name" "$app/Contents/Resources/icon.icns"; then
    icns=$(find "$SIGNAL_APP/Contents/Resources" -maxdepth 1 -name '*.icns' -print -quit)
    [[ -n $icns ]] && cp "$icns" "$app/Contents/Resources/icon.icns"
  fi
  write_plist "$app" "Signal $name" "local.signal-profile.$name"
  printf 'Launcher: %s\n' "$app"
}

write_plist() { # $1=app $2=tên hiển thị $3=bundle id
  cat > "$1/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>launcher</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>CFBundleIdentifier</key><string>$3</string>
  <key>CFBundleName</key><string>$2</string>
  <key>CFBundlePackageType</key><string>APPL</string>
</dict>
</plist>
EOF
}

cmd_remove() {
  local name=$1 confirm=${2:-} dir answer
  validate_name "$name"
  dir=$(profile_dir "$name")
  [[ -d $dir ]] || die "account '$name' không tồn tại"
  [[ $dir == "$BASE/$PREFIX$name" ]] || die "kiểm tra đường dẫn thất bại, hủy thao tác"
  is_running "$dir" && die "account '$name' đang chạy — tắt nó trước (quit $name)"
  if [[ $confirm != "--yes" ]]; then
    printf "Xóa VĨNH VIỄN toàn bộ dữ liệu '%s' trên máy này:\n  %s\nGõ lại tên để xác nhận: " "$name" "$dir"
    read -r answer
    [[ $answer == "$name" ]] || die "tên không khớp, không xóa gì cả"
  fi
  rm -rf -- "$dir"
  rm -rf -- "$LAUNCHER_DIR/Signal $name.app"
  printf "Đã xóa account '%s' và launcher.\n" "$name"
  printf "Nhớ gỡ liên kết trên điện thoại: Cài đặt → Thiết bị đã liên kết.\n"
}

cmd_menu() { # mở dashboard: ủy quyền cho server Python nằm cùng thư mục
  local here
  here="$(cd "$(dirname "$0")" && pwd)"
  [[ -f "$here/signal_manager_server.py" ]] || die "thiếu signal_manager_server.py cạnh script"
  exec /usr/bin/env python3 "$here/signal_manager_server.py" --launch
}

cmd_install() {
  local app="$LAUNCHER_DIR/Signal Manager.app" here icns f native=0
  here="$(cd "$(dirname "$0")" && pwd)"
  for f in signal-manager.sh signal_manager_server.py signal-manager-ui.html; do
    [[ -f "$here/$f" ]] || die "thiếu file $f trong $here"
  done
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  for f in signal-manager.sh signal_manager_server.py signal-manager-ui.html SignalManagerApp.swift; do
    [[ -f "$here/$f" ]] && cp "$here/$f" "$app/Contents/Resources/$f"
  done
  chmod +x "$app/Contents/Resources/signal-manager.sh"
  # Ưu tiên launcher native (cửa sổ WKWebView riêng) — compile cục bộ nên không
  # dính Gatekeeper. Thiếu swiftc/compile lỗi → fallback mở dashboard qua browser.
  if command -v swiftc >/dev/null 2>&1 && [[ -f "$app/Contents/Resources/SignalManagerApp.swift" ]]; then
    printf 'Đang biên dịch cửa sổ native (lần đầu có thể mất ~20s)...\n'
    if swiftc -O "$app/Contents/Resources/SignalManagerApp.swift" \
        -o "$app/Contents/MacOS/launcher" \
        -framework Cocoa -framework WebKit 2>/tmp/signal-manager-swiftc.log; then
      native=1
    else
      printf 'Biên dịch native thất bại (xem /tmp/signal-manager-swiftc.log) — dùng chế độ trình duyệt.\n'
    fi
  fi
  if [[ $native -eq 0 ]]; then
    cat > "$app/Contents/MacOS/launcher" <<'EOF'
#!/bin/sh
exec /usr/bin/env python3 "$(dirname "$0")/../Resources/signal_manager_server.py" --launch
EOF
    chmod +x "$app/Contents/MacOS/launcher"
  fi
  # icon riêng của Signal Manager (vịt) — tránh nhầm với Signal thật;
  # tìm ở assets/ (chạy từ repo) hoặc ngay cạnh script (chạy từ bundle đã cài)
  if [[ -f "$here/assets/signal-manager.icns" ]]; then
    cp "$here/assets/signal-manager.icns" "$app/Contents/Resources/icon.icns"
    cp "$here/assets/signal-manager.icns" "$app/Contents/Resources/signal-manager.icns"
  elif [[ -f "$here/signal-manager.icns" ]]; then
    cp "$here/signal-manager.icns" "$app/Contents/Resources/icon.icns"
    cp "$here/signal-manager.icns" "$app/Contents/Resources/signal-manager.icns"
  else
    icns=$(find "$SIGNAL_APP/Contents/Resources" -maxdepth 1 -name '*.icns' -print -quit 2>/dev/null)
    [[ -n $icns ]] && cp "$icns" "$app/Contents/Resources/icon.icns"
  fi
  cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>launcher</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>CFBundleIdentifier</key><string>local.signal-manager</string>
  <key>CFBundleName</key><string>Signal Manager</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
EOF
  if [[ $native -eq 1 ]]; then
    printf 'Đã cài (cửa sổ NATIVE): %s\n' "$app"
  else
    printf 'Đã cài (chế độ trình duyệt): %s\n' "$app"
  fi
  printf '(chạy lại "install" sau khi sửa code để cập nhật app)\n'
}

main() {
  local cmd=${1:-menu}
  shift || true
  case $cmd in
    menu)      cmd_menu ;;
    list|ls)   cmd_list ;;
    state)     cmd_state "${1:-}" ;;
    add)       [[ $# -ge 1 ]] || die "dùng: add <tên>";      cmd_add "$1" ;;
    open)      [[ $# -ge 1 ]] || die "dùng: open <tên>|all|default"; cmd_open "$1" ;;
    quit)      [[ $# -ge 1 ]] || die "dùng: quit <tên>|all|default"; cmd_quit "$1" ;;
    remove|rm) [[ $# -ge 1 ]] || die "dùng: remove <tên> [--yes]"; cmd_remove "$@" ;;
    autostart) [[ $# -ge 2 ]] || die "dùng: autostart <tên>|default on|off"; cmd_autostart "$1" "$2" ;;
    launcher)  [[ $# -ge 1 ]] || die "dùng: launcher <tên>"; validate_name "$1"; make_launcher "$1" ;;
    install)   cmd_install ;;
    uninstall) cmd_uninstall ;;
    help|-h|--help) usage ;;
    *) err "lệnh lạ '$cmd'"; usage >&2; exit 1 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
