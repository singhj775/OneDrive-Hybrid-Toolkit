<#
.SYNOPSIS
OneDrive Control Toolkit - Safe Remove/Reinstall
.DESCRIPTION
Consumer-friendly, fully automated or menu-driven OneDrive removal tool.
Safe by default. Requires Administrator rights. PowerShell 5.1 compatible.
.PARAMETER Remove
Run OneDrive removal.
.PARAMETER Reinstall
Reinstall OneDrive.
.PARAMETER Status
Show current OneDrive status.
.PARAMETER DeepClean
Remove leftover configuration folders.
.PARAMETER RemoveMyFiles
Delete local OneDrive folder (requires explicit YES confirmation).
.PARAMETER BlockReinstall
Block auto-reinstall via registry policy.
.PARAMETER PostRebootCleanup
Schedule cleanup of locked files after reboot.
.PARAMETER NoPrompt
Skip interactive prompts.
.EXAMPLE
.\OneDrive-Hybrid-Toolkit.ps1 -Remove -DeepClean
#>
[CmdletBinding()]
param(
    [switch]$Menu,
    [switch]$Remove,
    [switch]$Reinstall,
    [switch]$Status,
    [switch]$DeepClean,
    [switch]$RemoveMyFiles,
    [switch]$BlockReinstall,
    [switch]$RealTimeDiagnostic,
    [switch]$PostRebootCleanup,
    [switch]$ChracterCount,
    [switch]$LocalAccount,
    [switch]$LogsCollection,
    [switch]$NoPrompt

)

# ===== Configuration =====
$ScriptVersion = '2.2.1'
$LogDir = Join-Path $env:ProgramData 'OneDriveToolkit'
$LogPath = Join-Path $LogDir 'Toolkit.log'
$OneDriveCLSID = '{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
$PolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'
$TaskName = 'OneDrivePostCleanup'

# ===== Logging Setup =====
$ErrorActionPreference = 'Continue'
New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
Start-Transcript -Path (Join-Path $LogDir "log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt") -Append -WarningAction SilentlyContinue | Out-Null

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"
    $color = switch ($Level) {
        'INFO'    { 'Gray' }
        'WARN'    { 'Yellow' }
        'ERROR'   { 'Red' }
        'SUCCESS' { 'Green' }
        default   { 'White' }
    }
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $LogPath -Value $line
}

# ===== Admin Check & Auto-Elevate =====
function Test-Admin {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($user)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Log "Admin required. Relaunching..." 'WARN'
    $argsList = @()
    foreach ($key in $PSBoundParameters.Keys) {
        $val = $PSBoundParameters[$key]
        if ($val -is [switch] -and $val.IsPresent) { $argsList += "-$key" }
        elseif ($val -isnot [switch]) { $argsList += "-$key `"$val`"" }
    }
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`" $argsList" -Verb RunAs
    exit
}

# ===== Stop Processes =====
function Stop-OneDriveProcs {
    Write-Log "Stopping OneDrive processes..." 'INFO'
    @('OneDrive','FileSyncHelper','Update') | ForEach-Object {
        Get-Process -Name $_ -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
}

# ===== Run Uninstallers (Safe String Parsing) =====
function Run-Uninstallers {
    Write-Log "Running OneDrive uninstallers..." 'INFO'
    $paths = @(
        "$env:SystemRoot\System32\OneDriveSetup.exe",
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
        "$env:ProgramFiles\Microsoft Office\root\Integration\Addons\OneDriveSetup.exe",
        "${env:ProgramFiles(x86)}\Microsoft Office\root\Integration\Addons\OneDriveSetup.exe"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) {
            try {
                Write-Log "Uninstalling: $p" 'INFO'
                Start-Process -FilePath $p -ArgumentList "/uninstall" -Wait -NoNewWindow
                Write-Log "Success: $p" 'SUCCESS'
            } catch { Write-Log "Failed: $p - $_" 'ERROR' }
        }
    }
    # Registry fallback (Zero regex, pure string methods)
    $regPaths = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    foreach ($rp in $regPaths) {
        if (Test-Path $rp) {
            Get-ChildItem $rp -ErrorAction SilentlyContinue | Where-Object { $_.GetValue('DisplayName') -like 'OneDrive*' } | ForEach-Object {
                $us = $_.GetValue('UninstallString')
                if ($us) {
                    try {
                        $exe = $us
                        $arg = ""
                        if ($exe.StartsWith('"')) {
                            $endQuote = $exe.IndexOf('"', 1)
                            if ($endQuote -gt 0) {
                                $exe = $exe.Substring(1, $endQuote - 1)
                                $arg = $us.Substring($endQuote + 1).Trim()
                            }
                        } else {
                            $spaceIdx = $exe.IndexOf(' ')
                            if ($spaceIdx -gt 0) {
                                $arg = $exe.Substring($spaceIdx).Trim()
                                $exe = $exe.Substring(0, $spaceIdx)
                            }
                        }
                        if ($arg -notlike '*/uninstall*') { $arg = "$arg /uninstall" }
                        Start-Process -FilePath $exe -ArgumentList $arg -Wait
                        Write-Log "Registry uninstall succeeded" 'SUCCESS'
                    } catch { Write-Log "Registry uninstall failed: $_" 'ERROR' }
                }
            }
        }
    }
}

# ===== Remove AppX =====
function Remove-AppX {
    Write-Log "Removing AppX packages..." 'INFO'
    try {
        Get-AppxPackage -Name 'OneDrive' -ErrorAction Stop | Remove-AppxPackage -ErrorAction Stop
        Write-Log "User AppX removed" 'SUCCESS'
    } catch { Write-Log "No user AppX found" 'INFO' }
    try {
        Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object { $_.DisplayName -like 'OneDrive*' } | ForEach-Object {
            Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Stop
        }
        Write-Log "Provisioned AppX removed" 'SUCCESS'
    } catch { Write-Log "No provisioned AppX found" 'INFO' }
}

# ===== Registry Cleanup =====
function Clean-Registry {
    Write-Log "Cleaning registry..." 'INFO'
    $keys = @(
        'HKCU:\Software\Microsoft\OneDrive',
        'HKLM:\SOFTWARE\Microsoft\OneDrive',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\OneDrive',
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\$OneDriveCLSID",
        "Registry::HKEY_CLASSES_ROOT\CLSID\$OneDriveCLSID",
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run\OneDrive'
    )
    foreach ($k in $keys) {
        if (Test-Path $k) {
            try { Remove-Item -Path $k -Recurse -Force -ErrorAction Stop; Write-Log "Removed: $k" 'SUCCESS' }
            catch { Write-Log "Could not remove: $k" 'WARN' }
        }
    }
    Write-Log "Removing Broken Identity Cache..." 'INFO'

	Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue

Remove-Item "$env:LOCALAPPDATA\Microsoft\OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$env:LOCALAPPDATA\Microsoft\IdentityCache" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$env:LOCALAPPDATA\Microsoft\TokenBroker" -Recurse -Force -ErrorAction SilentlyContinue
Write-Log "Removed Broken Identity Cache..." 'INFO'

}

# ===== Folder Cleanup =====
function Clean-Folders {
    Write-Log "Cleaning folders..." 'INFO'
    $folders = @(
        "$env:LOCALAPPDATA\Microsoft\OneDrive",
        "$env:LOCALAPPDATA\OneDrive",
        "$env:APPDATA\Microsoft\OneDrive",
        "$env:ProgramFiles\Microsoft OneDrive",
        "${env:ProgramFiles(x86)}\Microsoft OneDrive",
        "C:\ProgramData\Microsoft OneDrive"
    )
    foreach ($f in $folders) {
        if (Test-Path $f) {
            if ($DeepClean) {
                try { Remove-Item -Path $f -Recurse -Force -ErrorAction Stop; Write-Log "Removed: $f" 'SUCCESS' }
                catch { Write-Log "Could not remove: $f" 'WARN' }
            } else { Write-Log "Skipped (use -DeepClean): $f" 'INFO' }
        }
    }
    $userOD = Join-Path $env:USERPROFILE 'OneDrive'
    if (Test-Path $userOD) {
        if ($RemoveMyFiles) {
            Write-Log "WARNING: Deleting user folder: $userOD" 'WARN'
            try { Remove-Item -Path $userOD -Recurse -Force -ErrorAction Stop; Write-Log "Deleted user folder" 'SUCCESS' }
            catch { Write-Log "Could not delete (locked): $userOD" 'ERROR' }
        } else { Write-Log "Keeping user folder: $userOD" 'INFO' }
    }
}

# ===== Post-Reboot Task =====
function New-PostRebootTask {
    Write-Log "Creating post-reboot cleanup task..." 'INFO'
    try {
        $cmd = 'cmd.exe /c "rmdir /s /q "%LOCALAPPDATA%\Microsoft\OneDrive" 2>nul & rmdir /s /q "%USERPROFILE%\OneDrive" 2>nul & schtasks /Delete /TN "' + $TaskName + '" /F 2>nul"'
        $action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c $cmd"
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable
        Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null
        Write-Log "Post-reboot task created" 'SUCCESS'
    } catch { Write-Log "Failed to create task: $_" 'ERROR' }
}

# ===== Policy Management =====
function Set-Policy {
    param([bool]$Block)
    if ($Block) {
        Write-Log "Blocking reinstall via policy..." 'INFO'
        if (-not (Test-Path $PolicyPath)) { New-Item -Path $PolicyPath -Force | Out-Null }
        New-ItemProperty -Path $PolicyPath -Name 'DisableFileSyncNGSC' -Value 1 -PropertyType DWord -Force | Out-Null
        Write-Log "Policy applied" 'SUCCESS'
    } else {
        Write-Log "Removing reinstall block..." 'INFO'
        if (Test-Path $PolicyPath) { Remove-Item -Path $PolicyPath -Recurse -Force -ErrorAction SilentlyContinue }
        Write-Log "Policy removed" 'SUCCESS'
    }
}

# ===== Status Check =====
function Get-Status {
    Write-Host "`nOneDrive Status " -ForegroundColor Cyan
    Write-Host "----------------" -ForegroundColor DarkGray
    $inst32 = Test-Path "$env:SystemRoot\System32\OneDriveSetup.exe"
    $blocked = Test-Path $PolicyPath
    $userFld = Test-Path (Join-Path $env:USERPROFILE 'OneDrive')
    Write-Host "Installer (System32): $(if($inst32){'YES'}else{'NO'})" -ForegroundColor $(if($inst32){'Green'}else{'DarkGray'})
    Write-Host "Blocked by Policy:    $(if($blocked){'YES'}else{'NO'})" -ForegroundColor $(if($blocked){'Yellow'}else{'Green'})
    Write-Host "User Folder Exists:   $(if($userFld){'YES'}else{'NO'})" -ForegroundColor $(if($userFld){'Cyan'}else{'Green'})
    Write-Host ""
}

# ===== Confirmation =====
function Confirm-DeleteFiles {
    if ($RemoveMyFiles) {
        Write-Host "`nWARNING: Delete personal OneDrive folder?" -ForegroundColor Red
        Write-Host "Path: $env:USERPROFILE\OneDrive" -ForegroundColor Yellow
        Write-Host "Type YES to confirm" -ForegroundColor Yellow
        $c = Read-Host ""
        if ($c -ne 'YES') { Write-Log "Cancelled by user" 'WARN'; return $false }
        return $true
    }
    return $true
}

# ===== Main Removal =====
function Do-Remove {
    if (-not (Confirm-DeleteFiles)) { Write-Host "Cancelled. Files safe." -ForegroundColor Green; return }
    Stop-OneDriveProcs
    Run-Uninstallers
    Remove-AppX
    Clean-Registry
    Clean-Folders
    if ($PostRebootCleanup) { New-PostRebootTask }
    if ($BlockReinstall) { Set-Policy -Block $true }
    Write-Log "Removal Complete" 'SUCCESS'
}

# ===== Reinstall =====
function Do-Reinstall {
    Write-Log "Reinstalling OneDrive..." 'INFO'
    if ($BlockReinstall) { Set-Policy -Block $false }
    $installer = "$env:SystemRoot\System32\OneDriveSetup.exe"
    if (Test-Path $installer) { Start-Process -FilePath $installer -Wait; Write-Log "Installer launched" 'SUCCESS' }
    else { Write-Log "Download from: https://www.microsoft.com/onedrive/download" 'WARN' }
}

# ===== Logs Collection =====
function logsCollection {
		try {
    $TimeStamp  = Get-Date -Format "yyyyMMdd_HHmmss"
    $TempRoot   = Join-Path $env:TEMP "OneDrive_Log_Collection_$TimeStamp"
    $ZipFile    = Join-Path $env:TEMP "OneDrive_Logs_$TimeStamp.zip"
    $ReportFile = Join-Path $TempRoot "Summary_Report.txt"

    New-Item -Path $TempRoot -ItemType Directory -Force | Out-Null
    Write-Host "Created temp collection folder: $TempRoot" -ForegroundColor Cyan

    # =========================
    # Collect System Info
    # =========================
    Write-Host "Collecting system information..." -ForegroundColor Cyan
    $OS = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $OneDriveExe = "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
    $ODVersion = if (Test-Path $OneDriveExe) { (Get-Item $OneDriveExe).VersionInfo.FileVersion } else { "Not Found" }

    @"
===== SYSTEM INFORMATION =====
Date: $(Get-Date)
Computer Name: $env:COMPUTERNAME
User: $env:USERNAME
OS: $($OS.Caption)
Version: $($OS.Version)
Build: $($OS.BuildNumber)
OneDrive Version: $ODVersion

"@ | Out-File -FilePath $ReportFile -Encoding UTF8 -Force

    # =========================
    # Known Log Paths
    # =========================
    Write-Host "Collecting OneDrive logs..." -ForegroundColor Cyan
    $LogPaths = @(
        "$env:LOCALAPPDATA\Microsoft\OneDrive",
        "$env:LOCALAPPDATA\Microsoft\OneDrive\logs",
        "$env:LOCALAPPDATA\Microsoft\OneDrive\setup\logs",
        "$env:LOCALAPPDATA\Microsoft\OneDrive\StandaloneUpdater\logs",
        "$env:PROGRAMDATA\Microsoft OneDrive\logs"
    )

    $AllLogs = @()
    foreach ($Path in $LogPaths) {
        if (Test-Path $Path) {
            $Destination = Join-Path $TempRoot (Split-Path $Path -Leaf)
            New-Item -Path $Destination -ItemType Directory -Force | Out-Null

            $Files = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue
            $Files | Copy-Item -Destination $Destination -Force -ErrorAction SilentlyContinue
            $AllLogs += $Files
        }
    }

    if ($AllLogs.Count -eq 0) {
        Write-Warning "No OneDrive log files found. Check if OneDrive is installed and running."
        Remove-Item -Path $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
        return
    }
    Write-Host "Found $($AllLogs.Count) log files." -ForegroundColor Green

    # =========================
    # Parse Common Issues
    # =========================
    Write-Host "Analyzing logs for common sync issues..." -ForegroundColor Cyan
    $Patterns = @{
        "Access Denied"        = "access denied"
        "File In Use"          = "in use"
        "Upload Blocked"       = "upload blocked"
        "Disk Full"            = "disk full"
        "Authentication Error" = "auth"
        "Quota Exceeded"       = "quota"
        "Network Error"        = "network"
        "Sync Paused"          = "paused"
        "Invalid Filename"     = "invalid"
        "SharePoint Error"     = "sharepoint"
    }

    "===== COMMON ISSUE ANALYSIS =====" | Add-Content -Path $ReportFile
    foreach ($Issue in $Patterns.Keys) {
        $Count = 0
        foreach ($Log in $AllLogs) {
            try {
                $Count += (Select-String -Path $Log.FullName -Pattern $Patterns[$Issue] -SimpleMatch -ErrorAction SilentlyContinue).Count
            } catch { $null }
        }
        "$Issue : $Count occurrences" | Add-Content -Path $ReportFile
    }
    "`n===== END OF REPORT =====" | Add-Content -Path $ReportFile

    # =========================
    # Compress Everything
    # =========================
    Write-Host "🗜️ Compressing logs and report..." -ForegroundColor Cyan
    if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }

    Compress-Archive -Path "$TempRoot\*" -DestinationPath $ZipFile -Force

    # Cleanup temp folder
    Remove-Item -Path $TempRoot -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "Collection Complete!" -ForegroundColor Green
    Write-Host "ZIP File: $ZipFile" -ForegroundColor White
    Write-Host "Attach this file to your support ticket." -ForegroundColor Gray
}
catch {
    Write-Error "Script failed: $_"
    if (Test-Path $TempRoot) {
        Remove-Item -Path $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

}



# ===== Local User Account =====
function NewLocalUserAccount {
        Write-Log "Creating account..." 'INFO'
   # Create new local user account with password
	net user test tet123 /add

# Add the user to Administrators group
	net localgroup Administrators test /add

        Write-Log "account created..." 'INFO'


}

# ===== Chracter Count =====
function ChracterCount {
# Detect current user profile and OneDrive path
$UserProfile = $env:USERPROFILE
$BaseFolder  = Join-Path $UserProfile "OneDrive"
$OutputCsv   = Join-Path $BaseFolder "CharacterCountResults.csv"

$results = @()

# Get all folders
Get-ChildItem -Path $BaseFolder -Recurse -Directory | ForEach-Object {
    $folderName      = $_.Name
    $folderCharCount = $folderName.Length
    $fullPathLength  = $_.FullName.Length
    $results += [PSCustomObject]@{
        Type           = "Folder"
        Path           = $_.FullName
        NameCharCount  = $folderCharCount
        FullPathLength = $fullPathLength
    }
}

# Get all files
Get-ChildItem -Path $BaseFolder -Recurse -File | ForEach-Object {
    $fileName        = $_.Name
    $fileCharCount   = $fileName.Length
    $fullPathLength  = $_.FullName.Length
    $results += [PSCustomObject]@{
        Type           = "File"
        Path           = $_.FullName
        NameCharCount  = $fileCharCount
        FullPathLength = $fullPathLength
    }
}

# Export to CSV
$results | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8

Write-Host "Scan complete. Results saved to $OutputCsv"

}



# ================================
# HEALTH SCORE
# ================================

function Get-HealthScore {

    $score = 100

    if (-not (Get-Process OneDrive -ErrorAction SilentlyContinue)) { $score -= 20 }
    if (-not (Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive")) { $score -= 20 }
    if (Test-Path "HKLM:\Software\Policies\Microsoft\Windows\OneDrive") { $score -= 20 }
    if (-not (Test-Connection 8.8.8.8 -Quiet -Count 1)) { $score -= 20 }
    if (-not (Test-Path "$env:USERPROFILE\OneDrive")) { $score -= 20 }

    return $score
}




# ===== Monitoring =====

function RealTimeDiagnostic {

    Write-Title "OneDrive Live Performance Monitor"

    $SampleInterval = 3
    $CpuThreshold = 70
    $SpikeDuration = 15
    $LogicalCPU = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
    $HighCpuTime = 0

    while ($true) {

        $p1 = Get-Process OneDrive -ErrorAction SilentlyContinue

        if (-not $p1) {
            Clear-Host
            Write-Host "Status: NOT RUNNING" -ForegroundColor Red
            Start-Sleep $SampleInterval
            continue
        }

        $cpu1 = ($p1 | Measure-Object CPU -Sum).Sum
        Start-Sleep $SampleInterval

        $p2 = Get-Process OneDrive -ErrorAction SilentlyContinue
        if (-not $p2) { continue }

        $cpu2 = ($p2 | Measure-Object CPU -Sum).Sum
        $mem  = ($p2 | Measure-Object WorkingSet64 -Sum).Sum

        $cpuPercent = ((($cpu2 - $cpu1) / $SampleInterval) / $LogicalCPU) * 100
        $cpuPercent = [math]::Round($cpuPercent,2)

        # ----- CPU BAR GRAPH -----
        $barLength = 30
        $filled = [math]::Round(($cpuPercent / 100) * $barLength)

        if ($filled -gt $barLength) { $filled = $barLength }
        if ($filled -lt 0) { $filled = 0 }

        $bar = ("#" * $filled).PadRight($barLength,"-")

        # ----- Color Logic -----
        if ($cpuPercent -lt 50) {
            $cpuColor = "Green"
        }
        elseif ($cpuPercent -lt 70) {
            $cpuColor = "Yellow"
        }
        else {
            $cpuColor = "Red"
        }

        # ----- Screen Render -----
        Clear-Host

        Write-Host "Time: $(Get-Date -Format HH:mm:ss)"
        Write-Host "Health Score: $(Get-HealthScore)/100"
        Write-Host ""

        Write-Host ("CPU: {0} %" -f $cpuPercent) -ForegroundColor $cpuColor
        Write-Host "[$bar]" -ForegroundColor $cpuColor
        Write-Host ""

        Write-Host ("Memory: {0} MB" -f [math]::Round($mem / 1MB,2))
        Write-Host "Processes: $($p2.Count)"
        Write-Host "Status: RUNNING" -ForegroundColor Green

        # ----- AUTO HEAL ENGINE -----
        if ($cpuPercent -gt $CpuThreshold) {

            $HighCpuTime += $SampleInterval

            if ($HighCpuTime -ge $SpikeDuration) {

                Write-Host ""
                Write-Host "[AUTO-HEAL] High CPU sustained. Restarting OneDrive..." -ForegroundColor Cyan

                try {
                    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force
                    Start-Sleep 3

                    $odPath = "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
                    if (Test-Path $odPath) {
                        Start-Process $odPath
                        Write-Host "Restart successful." -ForegroundColor Green
                    }
                }
                catch {
                    Write-Host "Auto-heal failed." -ForegroundColor Red
                }

                $HighCpuTime = 0
                Start-Sleep 3
            }
        }
        else {
            $HighCpuTime = 0
        }
    }
}

# ===== Menu =====
function Show-Menu {
    Clear-Host
    Write-Host "`nOneDrive Toolkit v$ScriptVersion" -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor DarkGray
    Get-Status
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "1. Remove OneDrive (Safe)"
    Write-Host "2. Remove + Deep Clean"
    Write-Host "3. Remove + Delete My Files"
    Write-Host "4. Reinstall OneDrive"
    Write-Host "5. Block Reinstall (Policy)"
    Write-Host "6. RealTimeDiagnostic"
    Write-Host "7. ChracterCount"
    Write-Host "8. New Local User Account"
    Write-Host "9. Logs Collection"
    Write-Host "10. Exit"
    Write-Host ""
}

function Run-Menu {
    do {
        Show-Menu
        $c = Read-Host "Select 1-10"
        switch ($c) {
            '1' { Do-Remove; Pause }
            '2' { $script:DeepClean=$true; Do-Remove; Pause }
            '3' { $script:DeepClean=$true; $script:RemoveMyFiles=$true; Do-Remove; Pause }
            '4' { Do-Reinstall; Pause }
            '5' { Set-Policy -Block $true; Pause }
	    '6' { RealTimeDiagnostic }
            '7' { ChracterCount; Pause }
	    '8' { NewLocalUserAccount; Pause }
	    '9' { LogsCollection; Pause }
            '10' { Write-Host "Exiting"; return }
            default { Write-Host "Invalid"; Start-Sleep 1 }
        }
    } while ($true)
}

# ===== Main Entry =====
Write-Log "Toolkit Started" 'INFO'
if ($Status) { Get-Status; if (-not $NoPrompt) { Pause }; exit }
if ($Remove) { Do-Remove }
elseif ($Reinstall) { Do-Reinstall }
elseif ($Menu -or $PSBoundParameters.Count -eq 0) { Run-Menu }

if (-not $NoPrompt) {
    Write-Host "`nReboot recommended." -ForegroundColor Cyan
    $ans = Read-Host "Restart now? (Y/N)"
    if ($ans -ieq 'y' -or $ans -ieq 'yes') { Restart-Computer -Force }
}
Stop-Transcript | Out-Null
Write-Host "Log: $LogPath" -ForegroundColor Cyan
