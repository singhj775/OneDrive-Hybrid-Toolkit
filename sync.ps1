<#
Fix-OneDriveSync.ps1
Deep OneDrive Sync Repair Script
Supports Windows 10 & 11
Logs to: C:\ProgramData\OneDriveFix\
#>

#region Init
$LogDir = "C:\ProgramData\OneDriveFix"
$LogFile = "$LogDir\FixLog_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

if (!(Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

Start-Transcript -Path $LogFile -Append
Write-Host "==== OneDrive Deep Sync Repair Started ====" -ForegroundColor Cyan
#endregion

function Write-Step($msg) {
    Write-Host "`n[+] $msg" -ForegroundColor Yellow
}

#----------------------------------------------------------
# 1. Kill OneDrive
#----------------------------------------------------------
Write-Step "Stopping OneDrive processes"
Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force
Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

#----------------------------------------------------------
# 2. Remove Sync Policies
#----------------------------------------------------------
Write-Step "Removing OneDrive policy restrictions"
Remove-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "HKCU:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Recurse -Force -ErrorAction SilentlyContinue

#----------------------------------------------------------
# 3. Reset OneDrive
#----------------------------------------------------------
Write-Step "Attempting OneDrive reset"
$ResetPaths = @(
    "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe /reset",
    "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe /reset",
    "$env:ProgramFiles(x86)\Microsoft OneDrive\OneDrive.exe /reset"
)

foreach ($cmd in $ResetPaths) {
    try {
        Start-Process "cmd.exe" "/c $cmd" -WindowStyle Hidden
    } catch {}
}

Start-Sleep -Seconds 5

#----------------------------------------------------------
# 4. Clear OneDrive Cache
#----------------------------------------------------------
Write-Step "Clearing OneDrive cache folders"
$CachePaths = @(
    "$env:LOCALAPPDATA\Microsoft\OneDrive\logs",
    "$env:LOCALAPPDATA\Microsoft\OneDrive\settings",
    "$env:LOCALAPPDATA\Microsoft\OneDrive\cache"
)

foreach ($path in $CachePaths) {
    if (Test-Path $path) {
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

#----------------------------------------------------------
# 5. Remove Ghost CLSID (Explorer Fix)
#----------------------------------------------------------
Write-Step "Removing OneDrive from Explorer Navigation Pane (if ghosted)"

$CLSIDKeys = @(
    "HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}",
    "HKCR:\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
)

foreach ($key in $CLSIDKeys) {
    if (Test-Path $key) {
        Set-ItemProperty -Path $key -Name "System.IsPinnedToNameSpaceTree" -Value 0 -ErrorAction SilentlyContinue
    }
}

#----------------------------------------------------------
# 6. Network Reset (Fix Stuck Sync)
#----------------------------------------------------------
Write-Step "Resetting network stack"
ipconfig /flushdns
netsh winsock reset
netsh int ip reset
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#----------------------------------------------------------
# 7. Remove Broken Install State
#----------------------------------------------------------
Write-Step "Cleaning OneDrive uninstall registry entries"

$UninstallPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

foreach ($path in $UninstallPaths) {
    Get-ChildItem $path -ErrorAction SilentlyContinue | ForEach-Object {
        $display = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName
        if ($display -like "*OneDrive*") {
            Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

#----------------------------------------------------------
# 8. Reinstall OneDrive
#----------------------------------------------------------
Write-Step "Reinstalling OneDrive"

$SetupPaths = @(
    "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
    "$env:SystemRoot\System32\OneDriveSetup.exe"
)

foreach ($setup in $SetupPaths) {
    if (Test-Path $setup) {
        Start-Process $setup -ArgumentList "/allusers" -Wait
    }
}

#----------------------------------------------------------
# 9. Restart OneDrive (Smart Detection)
#----------------------------------------------------------
Write-Step "Starting OneDrive"

$PossiblePaths = @(
    "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe",
    "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe",
    "$env:ProgramFiles(x86)\Microsoft OneDrive\OneDrive.exe"
)

$Started = $false

foreach ($path in $PossiblePaths) {
    if (Test-Path $path) {
        Start-Process $path
        Write-Host "OneDrive started from: $path" -ForegroundColor Green
        $Started = $true
        break
    }
}

if (-not $Started) {
    Write-Host "OneDrive executable not found. Reinstall may have failed." -ForegroundColor Red
}

Write-Host " OneDrive Repair Completed" -ForegroundColor Green
Write-Host "Log saved at: $LogFile" -ForegroundColor Cyan

Stop-Transcript