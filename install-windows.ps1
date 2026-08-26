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

# File tải về phải nguyên vẹn: có BOM UTF-8 và parse được bằng PowerShell —
# chống trường hợp CDN trả về bản cache cũ/hỏng
function Test-GoodScript([string]$path) {
  $bytes = [IO.File]::ReadAllBytes($path)
  if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
    return $false
  }
  $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errs)
  return (-not $errs)
}

$psFile = Join-Path $dest 'signal-manager.ps1'
$ok = $false
foreach ($try in 1..3) {
  # cache-buster: query khác nhau mỗi lần → CDN buộc phải lấy bản mới nhất
  $cb = [DateTime]::UtcNow.Ticks
  Invoke-WebRequest -UseBasicParsing -Uri "$repo/signal-manager.ps1?cb=$cb" -OutFile $psFile
  if (Test-GoodScript $psFile) { $ok = $true; break }
  Write-Host "File tải về chưa chuẩn (cache mạng?) — thử lại lần $try..."
  Start-Sleep -Seconds 3
}
if (-not $ok) {
  Write-Host '❌ Tải 3 lần vẫn lỗi — kiểm tra mạng rồi chạy lại lệnh cài.' -ForegroundColor Red
  return
}

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
