# Install Signal Manager (Windows BETA) with one PowerShell command:
#   irm https://raw.githubusercontent.com/dev-lo-18tuoi/multi-signal/main/install-windows.ps1 | iex
# File nay thuan ASCII co chu dich: an toan cho ca `irm | iex` lan che do ANSI.
# Moi thong bao tieng Viet co dau nam trong signal-manager.ps1 (co BOM, chay qua -File).

$ErrorActionPreference = 'Stop'
$repo = 'https://raw.githubusercontent.com/dev-lo-18tuoi/multi-signal/main'
$dest = Join-Path $env:LOCALAPPDATA 'SignalManager'

Write-Host 'Signal Manager (Windows BETA) - dang cai dat...' -ForegroundColor Cyan

$signal = Join-Path $env:LOCALAPPDATA 'Programs\signal-desktop\Signal.exe'
if (-not (Test-Path $signal)) {
  Write-Host 'CHUA CAI SIGNAL DESKTOP. Tai tai: https://signal.org/download roi chay lai lenh nay.' -ForegroundColor Red
  return
}

New-Item -ItemType Directory -Path $dest -Force | Out-Null

# File tai ve phai nguyen ven: co BOM UTF-8 va parse duoc - chong CDN cache cu/hong
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
foreach ($i in 1..3) {
  $cb = [DateTime]::UtcNow.Ticks
  Invoke-WebRequest -UseBasicParsing -Uri "$repo/signal-manager.ps1?cb=$cb" -OutFile $psFile
  if (Test-GoodScript $psFile) { $ok = $true; break }
  Write-Host "File tai ve chua chuan (cache mang?) - thu lai lan $i..."
  Start-Sleep -Seconds 3
}
if (-not $ok) {
  Write-Host 'Tai 3 lan van loi - kiem tra mang roi chay lai lenh cai.' -ForegroundColor Red
  return
}

@"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\SignalManager\signal-manager.ps1" %*
"@ | Set-Content -Path (Join-Path $dest 'signal-manager.cmd') -Encoding ASCII

Write-Host ''
Write-Host 'CAI XONG!' -ForegroundColor Green
Write-Host 'Them account thu 2 (doi "congviec" thanh ten ban thich, dan 1 dong):'
Write-Host "  & `"$dest\signal-manager.cmd`" add congviec"
Write-Host 'Cac lenh khac:'
Write-Host "  & `"$dest\signal-manager.cmd`" list    # xem trang thai"
Write-Host "  & `"$dest\signal-manager.cmd`" help    # tat ca lenh"
Write-Host ''
Write-Host 'Moi account Signal can 1 so dien thoai rieng da dang ky tren dien thoai.'
