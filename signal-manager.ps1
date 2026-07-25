# signal-manager.ps1 — quản lý nhiều account Signal Desktop trên Windows (BETA).
# Mỗi account = 1 thư mục dữ liệu riêng (--user-data-dir), chạy song song được.
#
# Dùng:  .\signal-manager.ps1 <lệnh> [tên] [-Yes]
# Lệnh:  list | add <tên> | open <tên>|all|default | quit <tên>|all|default
#        remove <tên> [-Yes] | shortcut <tên> | autostart <tên>|default on|off
#        uninstall | help
#
# Tool không chính thức, không liên quan Signal Messenger LLC.

[CmdletBinding()]
param(
  [Parameter(Position = 0)] [string]$Command = 'help',
  [Parameter(Position = 1)] [string]$Name,
  [Parameter(Position = 2)] [string]$Mode,
  [switch]$Yes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:SignalExe = Join-Path $env:LOCALAPPDATA 'Programs\signal-desktop\Signal.exe'
if ($env:SIGNAL_BIN) { $script:SignalExe = $env:SIGNAL_BIN }
$script:Base = $env:APPDATA
$script:Prefix = 'Signal-'
$script:NameRe = '^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$'
$script:RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

function Show-Usage {
  @'
signal-manager.ps1 (BETA) — nhiều account Signal Desktop trên Windows

  list                      bảng account + trạng thái
  add <tên>                 tạo account mới (hiện QR liên kết) + shortcut Desktop
  open <tên>|all|default    mở / focus account
  quit <tên>|all|default    tắt account (đóng êm)
  remove <tên> [-Yes]       xóa vĩnh viễn dữ liệu account trên máy này
  shortcut <tên>            tạo lại shortcut Desktop + Start Menu
  autostart <tên>|default on|off   tự mở khi đăng nhập Windows
  uninstall                 gỡ shortcut + autostart (GIỮ dữ liệu account)

Dữ liệu: %APPDATA%\Signal-<tên> · Mỗi account cần 1 số điện thoại riêng.
'@ | Write-Output
}

function Assert-Signal {
  if (-not (Test-Path $script:SignalExe)) {
    throw "Không tìm thấy Signal Desktop tại $script:SignalExe — cài từ https://signal.org/download (hoặc đặt biến SIGNAL_BIN)."
  }
}

function Assert-ProfileName([string]$n) {
  if (-not $n) { throw 'Thiếu tên account.' }
  if ($n -notmatch $script:NameRe) { throw "Tên '$n' không hợp lệ (chỉ chữ/số/-/_, tối đa 32 ký tự)." }
}

function Get-ProfileDir([string]$n) { Join-Path $script:Base ($script:Prefix + $n) }

function Get-ProfileNames {
  Get-ChildItem -Path $script:Base -Directory -Filter ($script:Prefix + '*') -ErrorAction SilentlyContinue |
    ForEach-Object { $_.Name.Substring($script:Prefix.Length) }
}

# PID các process CHÍNH của Signal (loại helper --type=...) theo profile.
# $Target = đường dẫn profile, hoặc 'default' cho bản chính.
function Get-SignalMainPids([string]$Target) {
  $procs = Get-CimInstance Win32_Process -Filter "Name = 'Signal.exe'" -ErrorAction SilentlyContinue
  $result = @()
  foreach ($p in $procs) {
    $cl = $p.CommandLine
    if (-not $cl) { continue }
    if ($cl -match ' --type=') { continue }              # bỏ qua process phụ
    $hasFlag = $cl -match '--user-data-dir='
    if ($Target -eq 'default') {
      if (-not $hasFlag) { $result += $p.ProcessId }
    } else {
      # khớp trọn đường dẫn (kèm dấu " đóng hoặc hết chuỗi) tránh trùng tiền tố
      if ($cl.Contains('--user-data-dir="' + $Target + '"') -or
          $cl.TrimEnd().EndsWith('--user-data-dir=' + $Target)) {
        $result += $p.ProcessId
      }
    }
  }
  $result
}

function Test-ProfileRunning([string]$Target) { @(Get-SignalMainPids $Target).Count -gt 0 }

function Start-SignalProfile([string]$dir) {
  Assert-Signal
  Start-Process -FilePath $script:SignalExe -ArgumentList ('--user-data-dir="' + $dir + '"')
}

function Show-ProfileList {
  $rows = @()
  $defaultDir = Join-Path $script:Base 'Signal'
  if (Test-Path $defaultDir) {
    $state = if (Test-ProfileRunning 'default') { 'đang chạy' } else { 'tắt' }
    $rows += [pscustomobject]@{ TEN = '(chính)'; TRANG_THAI = $state; THU_MUC = $defaultDir }
  }
  foreach ($n in Get-ProfileNames) {
    $d = Get-ProfileDir $n
    $state = if (Test-ProfileRunning $d) { 'đang chạy' } else { 'tắt' }
    $rows += [pscustomobject]@{ TEN = $n; TRANG_THAI = $state; THU_MUC = $d }
  }
  if ($rows.Count -eq 0) { Write-Output 'Chưa có account nào (dùng: add <tên>).'; return }
  $rows | Format-Table -AutoSize
}

function Add-SignalProfile([string]$n) {
  Assert-ProfileName $n
  $d = Get-ProfileDir $n
  if (Test-Path $d) { throw "Account '$n' đã tồn tại (dùng: open $n)." }
  New-Item -ItemType Directory -Path $d -Force | Out-Null
  Start-SignalProfile $d
  New-ProfileShortcut $n
  @"
Đã tạo account '$n'. Cửa sổ Signal mới sẽ hiện mã QR.
Trên điện thoại giữ số của account này:
  Signal → Cài đặt → Thiết bị đã liên kết → Liên kết thiết bị mới → quét QR.
Shortcut 'Signal $n' đã có trên Desktop.
"@ | Write-Output
}

function Open-SignalProfile([string]$n) {
  switch ($n) {
    'all' {
      Assert-Signal
      if (Test-Path (Join-Path $script:Base 'Signal')) { Start-Process -FilePath $script:SignalExe }
      foreach ($p in Get-ProfileNames) { Start-SignalProfile (Get-ProfileDir $p); Start-Sleep 1 }
      return
    }
    'default' { Assert-Signal; Start-Process -FilePath $script:SignalExe; return }
  }
  Assert-ProfileName $n
  $d = Get-ProfileDir $n
  if (-not (Test-Path $d)) { throw "Account '$n' chưa tồn tại (dùng: add $n)." }
  Start-SignalProfile $d   # đã chạy thì Signal tự focus cửa sổ cũ
}

function Stop-SignalProfile([string]$n) {
  $targets = @()
  switch ($n) {
    'all' {
      $targets += ,'default'
      foreach ($p in Get-ProfileNames) { $targets += (Get-ProfileDir $p) }
    }
    'default' { $targets = @('default') }
    default {
      Assert-ProfileName $n
      $targets = @((Get-ProfileDir $n))
    }
  }
  $count = 0
  foreach ($t in $targets) {
    foreach ($procId in Get-SignalMainPids $t) {
      $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
      if ($proc) {
        $null = $proc.CloseMainWindow()   # đóng êm, dữ liệu an toàn
        $count++
      }
    }
  }
  if ($count -eq 0) { Write-Output 'Không có instance nào đang chạy.' }
  else { Write-Output "Đã gửi lệnh tắt ($count cửa sổ)." }
}

function New-ProfileShortcut([string]$n) {
  Assert-ProfileName $n
  Assert-Signal
  $d = Get-ProfileDir $n
  $shell = New-Object -ComObject WScript.Shell
  $places = @(
    [Environment]::GetFolderPath('Desktop'),
    (Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs')
  )
  foreach ($place in $places) {
    $lnk = Join-Path $place "Signal $n.lnk"
    $sc = $shell.CreateShortcut($lnk)
    $sc.TargetPath = $script:SignalExe
    $sc.Arguments = '--user-data-dir="' + $d + '"'
    $sc.WorkingDirectory = Split-Path $script:SignalExe
    $sc.IconLocation = "$script:SignalExe,0"
    $sc.Save()
    Write-Output "Shortcut: $lnk"
  }
}

function Set-ProfileAutostart([string]$n, [string]$m) {
  if ($m -notin @('on', 'off')) { throw 'Dùng: autostart <tên>|default on|off' }
  $keyName = "SignalManager-$n"
  if ($n -eq 'default') {
    $value = '"' + $script:SignalExe + '"'
  } else {
    Assert-ProfileName $n
    $d = Get-ProfileDir $n
    if (-not (Test-Path $d)) { throw "Account '$n' không tồn tại." }
    $value = '"' + $script:SignalExe + '" --user-data-dir="' + $d + '"'
  }
  if ($m -eq 'on') {
    Set-ItemProperty -Path $script:RunKey -Name $keyName -Value $value
    Write-Output "Đã bật tự mở cho '$n' khi đăng nhập Windows."
  } else {
    Remove-ItemProperty -Path $script:RunKey -Name $keyName -ErrorAction SilentlyContinue
    Write-Output "Đã tắt tự mở cho '$n'."
  }
}

function Remove-SignalProfile([string]$n, [bool]$Confirmed) {
  Assert-ProfileName $n
  $d = Get-ProfileDir $n
  if (-not (Test-Path $d)) { throw "Account '$n' không tồn tại." }
  $expected = Join-Path $script:Base ($script:Prefix + $n)
  if ($d -ne $expected) { throw 'Kiểm tra đường dẫn thất bại, hủy thao tác.' }
  if (Test-ProfileRunning $d) { throw "Account '$n' đang chạy — tắt trước: quit $n" }
  if (-not $Confirmed) {
    Write-Output "Xóa VĨNH VIỄN toàn bộ dữ liệu '$n' trên máy này: $d"
    $answer = Read-Host 'Gõ lại tên account để xác nhận'
    if ($answer -ne $n) { throw 'Tên không khớp, không xóa gì cả.' }
  }
  Remove-Item -LiteralPath $d -Recurse -Force
  foreach ($place in @(
      [Environment]::GetFolderPath('Desktop'),
      (Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs'))) {
    Remove-Item -LiteralPath (Join-Path $place "Signal $n.lnk") -Force -ErrorAction SilentlyContinue
  }
  Remove-ItemProperty -Path $script:RunKey -Name "SignalManager-$n" -ErrorAction SilentlyContinue
  Write-Output "Đã xóa account '$n' (kèm shortcut + autostart)."
  Write-Output 'Nhớ gỡ liên kết trên điện thoại: Cài đặt → Thiết bị đã liên kết.'
}

function Uninstall-SignalManager {
  foreach ($n in Get-ProfileNames) {
    foreach ($place in @(
        [Environment]::GetFolderPath('Desktop'),
        (Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs'))) {
      Remove-Item -LiteralPath (Join-Path $place "Signal $n.lnk") -Force -ErrorAction SilentlyContinue
    }
    Remove-ItemProperty -Path $script:RunKey -Name "SignalManager-$n" -ErrorAction SilentlyContinue
  }
  Remove-ItemProperty -Path $script:RunKey -Name 'SignalManager-default' -ErrorAction SilentlyContinue
  Write-Output 'Đã gỡ shortcut + autostart. DỮ LIỆU account (Signal-*) vẫn còn nguyên.'
}

switch ($Command) {
  'list'      { Show-ProfileList }
  'add'       { Add-SignalProfile $Name }
  'open'      { if (-not $Name) { throw 'Dùng: open <tên>|all|default' }; Open-SignalProfile $Name }
  'quit'      { if (-not $Name) { throw 'Dùng: quit <tên>|all|default' }; Stop-SignalProfile $Name }
  'remove'    { Remove-SignalProfile $Name $Yes.IsPresent }
  'shortcut'  { New-ProfileShortcut $Name }
  'autostart' { Set-ProfileAutostart $Name $Mode }
  'uninstall' { Uninstall-SignalManager }
  default     { Show-Usage }
}
