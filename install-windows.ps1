# Cài Signal Manager (BETA) lên Windows bằng 1 lệnh PowerShell:
#   irm https://raw.githubusercontent.com/dev-lo-18tuoi/multi-signal/main/install-windows.ps1 | iex
#
# Chỉ tải 1 file script về %LOCALAPPDATA%\SignalManager — không cài dịch vụ,
# không sửa hệ thống. Gỡ: xóa thư mục đó + chạy lệnh uninstall của script.

$ErrorActionPreference = 'Stop'
$repo = 'https://raw.githubusercontent.com/dev-lo-18tuoi/multi-signal/main'
$dest = Join-Path $env:LOCALAPPDATA 'SignalManager'

Write-Host '🔧 Signal Manager (Windows BETA) — cài đặt' -ForegroundColor Cyan

$signal = Join-Path $env:LOCALAPPDATA 'Programs\signal-desktop\Signal.exe'
if (-not (Test-Path $signal)) {
  Write-Host '❌ Chưa cài Signal Desktop. Tải tại: https://signal.org/download rồi chạy lại.' -ForegroundColor Red
  return
}

New-Item -ItemType Directory -Path $dest -Force | Out-Null
Invoke-WebRequest -UseBasicParsing -Uri "$repo/signal-manager.ps1" -OutFile (Join-Path $dest 'signal-manager.ps1')

# shim .cmd để gọi ngắn gọn từ mọi terminal
@"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\SignalManager\signal-manager.ps1" %*
"@ | Set-Content -Path (Join-Path $dest 'signal-manager.cmd') -Encoding ASCII

Write-Host ''
Write-Host '✅ Cài xong!' -ForegroundColor Green
Write-Host "Dùng ngay (hoặc thêm $dest vào PATH):"
Write-Host "  & `"$dest\signal-manager.cmd`" add congviec    # thêm account thứ 2"
Write-Host "  & `"$dest\signal-manager.cmd`" list            # xem trạng thái"
Write-Host "  & `"$dest\signal-manager.cmd`" help            # tất cả lệnh"
Write-Host ''
Write-Host 'Mỗi account Signal cần 1 số điện thoại riêng đã đăng ký trên điện thoại.'
