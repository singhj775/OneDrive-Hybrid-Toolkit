#requires -RunAsAdministrator
<#
.SYNOPSIS
    OneDrive Network Trace and Fiddler Configuration Tool
.DESCRIPTION
    Menu-driven script to configure WinHTTP proxy, disable HTTP/3/QUIC,
    revert changes, and capture dual traces (netsh .etl + Fiddler .saz).
#>

# Admin Check
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "This script requires Administrator privileges. Right-click PowerShell and select 'Run as Administrator'."
    Read-Host "Press Enter to exit"
    exit
}

function Show-Menu {
    Clear-Host
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "  OneDrive Network Trace and Fiddler Tool" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host "  [1] Bypass System Proxy and Route to Fiddler"
    Write-Host "  [2] Disable HTTP/3 and QUIC (Force HTTP/1.1/2)"
    Write-Host "  [3] Revert All Changes (Proxy, QUIC, Fiddler Cert)"
    Write-Host "  [4] Start Dual Capture (netsh .etl + Fiddler .saz)"
    Write-Host "  [5] Exit"
    Write-Host "==================================================" -ForegroundColor Cyan
}

function Set-FiddlerProxy {
    Write-Host "`n[1] Configuring WinHTTP Proxy for Fiddler..." -ForegroundColor Yellow
    netsh winhttp import proxy source=ie
    netsh winhttp set proxy 127.0.0.1:8888
    
    Write-Host "`nCurrent WinHTTP Proxy Settings:" -ForegroundColor Green
    netsh winhttp show proxy
    Read-Host "`nPress Enter to return to menu"
}

function Disable-Http3Quic {
    Write-Host "`n[2] Disabling HTTP/3 and QUIC for WinHTTP..." -ForegroundColor Yellow
    
    $path1 = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp"
    $path2 = "HKLM:\SYSTEM\CurrentControlSet\Services\WinHttp\Parameters"

    if (-not (Test-Path $path1)) { New-Item -Path $path1 -Force | Out-Null }
    if (-not (Test-Path $path2)) { New-Item -Path $path2 -Force | Out-Null }

    Set-ItemProperty -Path $path1 -Name "EnableHttp2Tls" -Value 1 -Type DWord
    Set-ItemProperty -Path $path2 -Name "EnableAutoHttp3" -Value 0 -Type DWord
    
    Write-Host "HTTP/3 disabled. HTTP/2 forced over TLS." -ForegroundColor Green
    Write-Host "Restart OneDrive to apply: taskkill /F /IM OneDrive.exe ; start OneDrive.exe" -ForegroundColor DarkYellow
    Read-Host "`nPress Enter to return to menu"
}

function Revert-Changes {
    Write-Host "`n[3] Reverting all configuration changes..." -ForegroundColor Yellow
    
    netsh winhttp reset proxy | Out-Null
    Write-Host "  WinHTTP proxy reset to direct connection." -ForegroundColor Green

    $regPaths = @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp\EnableHttp2Tls",
        "HKLM:\SYSTEM\CurrentControlSet\Services\WinHttp\Parameters\EnableAutoHttp3"
    )
    foreach ($reg in $regPaths) {
        if (Test-Path $reg) {
            Remove-Item -Path $reg -Force -ErrorAction SilentlyContinue
            Write-Host "  Removed: $reg" -ForegroundColor Green
        }
    }

    Write-Host "  Attempting to remove Fiddler Root CA..."
    certutil -delstore "Root" "DO_NOT_TRUST_FiddlerRoot" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Fiddler Root CA successfully removed." -ForegroundColor Green
    } else {
        Write-Host "  Fiddler Root CA was not found or already removed." -ForegroundColor DarkYellow
    }
    Read-Host "`nPress Enter to return to menu"
}

function Start-DualCapture {
    Write-Host "`n[4] Starting Dual Capture (netsh + Fiddler)..." -ForegroundColor Yellow
    
    $OutputFolder = "C:\OneDriveTraces"
    if (!(Test-Path $OutputFolder)) { New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $etlFile = "$OutputFolder\OD_Trace_$timestamp.etl"
    $sazFile = "$OutputFolder\OD_Trace_$timestamp.saz"

    # 1. Start netsh trace
    Write-Host "  Starting netsh trace..." -ForegroundColor Cyan
    netsh trace start capture=yes tracefile=$etlFile maxsize=500 | Out-Null

    # 2. Start FiddlerCore capture
    $fiddlerDll = "C:\Program Files (x86)\Fiddler\FiddlerCore.dll"
    $fiddlerLoaded = $false
    try {
        if (Test-Path $fiddlerDll) {
            Add-Type -Path $fiddlerDll
            [Fiddler.FiddlerApplication]::Startup(8888, $false, $false)
            $fiddlerLoaded = $true
            Write-Host "  FiddlerCore listening on port 8888" -ForegroundColor Green
        } else {
            Write-Warning "  FiddlerCore.dll not found. Install Fiddler Classic for .saz export."
        }
    } catch {
        Write-Warning "  Fiddler startup failed: $_"
    }

    Write-Host "`n  TRACE IS RUNNING. Reproduce your OneDrive issue now." -ForegroundColor Red
    Write-Host "  (Upload, download, unlock Personal Vault, sync conflicts, etc.)" -ForegroundColor DarkYellow
    Read-Host "`n  Press Enter to STOP both captures and export files"

    # Stop netsh
    Write-Host "  Stopping netsh trace..." -ForegroundColor Yellow
    netsh trace stop | Out-Null
    if (Test-Path $etlFile) {
        $etlSize = [math]::Round((Get-Item $etlFile).Length / 1MB, 2)
        Write-Host "  netsh .etl saved: $etlFile ($etlSize MB)" -ForegroundColor Green
        Write-Host "  Note: A companion .cab file was also auto-generated by Windows." -ForegroundColor DarkYellow
    }

    # Stop Fiddler & Export .saz
    if ($fiddlerLoaded) {
        Write-Host "  Stopping Fiddler and exporting .saz..." -ForegroundColor Yellow
        try {
            [Fiddler.FiddlerApplication]::SaveSessionArchive($sazFile, $true)
            [Fiddler.FiddlerApplication]::Shutdown()
            if (Test-Path $sazFile) {
                $sazSize = [math]::Round((Get-Item $sazFile).Length / 1MB, 2)
                Write-Host "  Fiddler .saz saved: $sazFile ($sazSize MB)" -ForegroundColor Green
            }
        } catch {
            Write-Warning "  Fiddler export failed: $_"
            Write-Warning "  You can manually export in Fiddler: Ctrl+A -> File -> Export Sessions -> Selected Sessions -> .saz"
        }
    }
    Read-Host "`n  Press Enter to return to menu"
}

# === MAIN MENU LOOP ===
do {
    Show-Menu
    $choice = Read-Host "Select an option [1-5]"

    switch ($choice) {
        "1" { Set-FiddlerProxy }
        "2" { Disable-Http3Quic }
        "3" { Revert-Changes }
        "4" { Start-DualCapture }
        "5" { 
            Write-Host "`nExiting script. Happy troubleshooting!" -ForegroundColor Cyan
            break 
        }
        default { 
            Write-Host "`nInvalid option. Please select 1-5." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} while ($choice -ne "5")