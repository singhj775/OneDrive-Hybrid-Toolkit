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
    [switch]$RealTimeCPU,
    [switch]$PostRebootCleanup,
    [switch]$ChracterCount,
    [switch]$LocalAccount,
    [switch]$LogsCollection,
    [switch]$FileExplorerThumbnail_IconCacheRepair,
	[switch]$SyncRepair,
	[switch]$RealTimeMonitor,
	[switch]$RestoreDefaultFoldersPostOneDrive,
	[switch]$JunctionRemover,
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
	Get-Process OneDrive* -ErrorAction SilentlyContinue | Stop-Process -Force
	taskkill /f /im onedrive.sync.service.exe
	sc stop "FileCoAuth" | Out-Null
    Get-Process filecoauth -ErrorAction SilentlyContinue | Stop-Process -Force
	Get-Service | Where-Object { $_.Name -like "*OneDrive*" } | ForEach-Object {
    sc stop $_.Name
    sc delete $_.Name
}

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
# --------------------------------------------------
# Locate SQLite Databases
# --------------------------------------------------

	Write-Log ""
	Write-Log "Scanning for SQLite databases..." -ForegroundColor Yellow

	$sqliteFiles = Get-ChildItem -Path $OneDrivePath -Recurse -Include *.sqlite -ErrorAction SilentlyContinue

	if ($sqliteFiles.Count -eq 0) {
   		Write-Log "No SQLite DB files found." -ForegroundColor Red
    	Add-Content $ReportPath "No SQLite DB files found."
	} 
	else {
    	Write-Log "$($sqliteFiles.Count) SQLite files found." -ForegroundColor Green
    	Add-Content $ReportPath "$($sqliteFiles.Count) SQLite files detected."
	}
}

# --------------------------------------------------
# Test DB File Access (Corruption / Lock Check)
# --------------------------------------------------
Write-Log ""
Write-Log "Testing DB file integrity..." -ForegroundColor Yellow

foreach ($db in $sqliteFiles) {
    try {
        $stream = [System.IO.File]::Open($db.FullName, 'Open', 'ReadWrite', 'None')
        $stream.Close()
        Write-Log "OK: $($db.Name)" -ForegroundColor Green
        Add-Content $ReportPath "OK: $($db.FullName)"
    }
    catch {
        Write-Log "LOCKED or CORRUPTED: $($db.Name)" -ForegroundColor Red
        Add-Content $ReportPath "LOCKED or CORRUPTED: $($db.FullName)"
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


	Write-Log "Starting OneDrive AppX cleanup and re-registration..." 'INFO'
 
try {
    Write-Output "Removing OneDriveSync AppX package..."
 
    $packages = Get-AppxPackage *OneDriveSync* -AllUsers -ErrorAction Stop
 
    if ($packages) {
        foreach ($pkg in $packages) {
            try {
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                Write-Log "Successfully removed package: $($pkg.PackageFullName)" 'SUCCESS'
            }
            catch {
                Write-Log "Failed to remove package: $($pkg.PackageFullName). Error: $($_.Exception.Message)" 'WARN'
            }
        }
    }
    else {
        Write-Log "No OneDriveSync AppX packages found." 'INFO'
    }
}
catch {
    Write-Log "Error while fetching/removing AppX package: $($_.Exception.Message)" 'ERROR'
}
 
try {
    Write-Log "Cleaning leftover ApplicationData folder..." 'INFO'
 
    $path = "C:\ProgramData\Microsoft\Windows\AppRepository\Families\ApplicationData\Microsoft.OneDriveSync_8wekyb3d8bbwe"
 
    if (Test-Path $path) {
        Remove-Item -Recurse -Force $path -ErrorAction Stop
        Write-Log "Successfully removed folder: $path" 'SUCCESS'
    }
    else {
        Write-Log "Path not found, skipping cleanup: $path" 'INFO'
    }
}
catch {
    Write-Log "Failed to clean ApplicationData folder: $($_.Exception.Message)" 'WARN'
}
 
try {
    Write-Log "Re-registering all AppX packages..." 'INFO'
 
    Get-AppXPackage -AllUsers -ErrorAction Stop | ForEach-Object {
        try {
            Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" -ErrorAction Stop
        }
        catch {
            Write-Log "Failed to register package: $($_.Name). Error: $($_.Exception.Message)" 'WARN'
        }
    }
 
    Write-Log "AppX re-registration completed." 'SUCCESS'
}
catch {
    Write-Log "Error during AppX re-registration: $($_.Exception.Message)" 'WARN'
}
 
try {
    Write-Log "Verifying remaining OneDriveSync packages..." 'INFO'
 
    $remaining = Get-AppxPackage *OneDriveSync* -AllUsers -ErrorAction Stop
 
    if ($remaining) {
        Write-Log "Some OneDriveSync packages still exist:" 'WARN'
        $remaining | Select Name, PackageFullName
    }
    else {
        Write-Log "No OneDriveSync packages found. Cleanup successful." 'SUCCESS'
    }
}
catch {
    Write-Log "Error during final verification: $($_.Exception.Message)" 'WARN'
}
 
Write-Log "Script execution completed." 'SUCCESS'


	
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
    Stop-Process -Name TokenBroker -Force -ErrorAction SilentlyContinue
    Stop-Process -Name IdentityCRL -Force -ErrorAction SilentlyContinue
	sc stop "OneDrive Sync Service" | Out-Null
	Get-Process filecoauth -ErrorAction SilentlyContinue | Stop-Process -Force

	taskkill /IM explorer.exe /F
    Stop-Process -Name explorer -Force

	Write-Log "Removed Broken Identity Cache..." 'SUCCESS'


}

# ===== Folder Cleanup =====
function Clean-Folders {
    Write-Log "Cleaning folders..." 'INFO'
	takeown /f "C:\Program Files\Microsoft OneDrive" /r /d y
    icacls "C:\Program Files\Microsoft OneDrive" /grant administrators:F /t
	takeown /f "$env:LOCALAPPDATA\Microsoft\OneDrive" /r /d y
    icacls "$env:LOCALAPPDATA\Microsoft\OneDrive" /grant administrators:F /t
	
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
                try { 
					Remove-Item -Path $f -Recurse -Force -ErrorAction Stop; Write-Log "Removed: $f" 'SUCCESS' 
					Remove-Item "$env:LOCALAPPDATA\Microsoft\OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
					Remove-Item "$env:LOCALAPPDATA\Microsoft\IdentityCache" -Recurse -Force -ErrorAction SilentlyContinue
					Remove-Item "$env:LOCALAPPDATA\Microsoft\TokenBroker" -Recurse -Force -ErrorAction SilentlyContinue
					Remove-Item "$env:ProgramFiles\Microsoft OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
}
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

	Write-Log "Creating post-reboot cleanup task1..." 'INFO'
	Start-Process explorer.exe
    try {
        $cmd = 'cmd.exe /c "rmdir /s /q "%LOCALAPPDATA%\Microsoft\OneDrive" 2>nul & rmdir /s /q "%USERPROFILE%\OneDrive" 2>nul & schtasks /Delete /TN "' + $TaskName + '" /F 2>nul"'
        $action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c $cmd"
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable
        Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null
        Write-Log "Post-reboot task created1" 'SUCCESS'
    } catch { Write-Log "Failed to create task: $_" 'ERROR' }

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
    if (Test-Path $installer) {
        # Launch installer without -Wait so script continues
        Start-Process -FilePath $installer
        Write-Log "Installer launched" 'SUCCESS'
    } else {
        Write-Log "Installer not found locally. Please download manually." 'WARN'
        return
    }

    # Allow installer to spawn processes
    Start-Sleep -Seconds 15

    # Stop any leftover OneDrive processes
    Get-Process OneDrive* -ErrorAction SilentlyContinue | Stop-Process -Force

    # Apply ACL changes AFTER reinstall completes
    icacls "$env:LOCALAPPDATA\Microsoft\OneDrive\Update" /deny "*S-1-1-0:(W)"
    icacls "$env:ProgramFiles\Microsoft OneDrive\Update" /deny "*S-1-1-0:(W)"

    $updaterPaths = @(
        "$env:ProgramFiles\Microsoft OneDrive\Update\OneDriveSetup.exe",
        "$env:ProgramFiles\Microsoft OneDrive\Update\OneDriveUpdater.exe",
        "$env:ProgramFiles\Microsoft OneDrive\OneDriveStandaloneUpdater.exe"
    )

    foreach ($path in $updaterPaths) {
        if (Test-Path $path) {
            Rename-Item $path "$path.bak" -Force
            Write-Log "Renamed $path to $path.bak"
        } else {
            Write-Log "Updater not found at $path"
        }
    }
}

# ===== ODC Repair =====
function SyncRepair {
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

}


# ===== Icon Repair =====
function IconRepair {
    ie4uinit.exe -show
    taskkill /IM explorer.exe /F
    Stop-Process -Name explorer -Force

    Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations\f01b4d95cf55d32a*" -Force -ErrorAction SilentlyContinue
    del %AppData%\Microsoft\Windows\Recent\AutomaticDestinations\*



    # Delete icon cache files properly in PowerShell
    Remove-Item "$env:localappdata\IconCache.db" -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:localappdata\Microsoft\Windows\Explorer\iconcache*" -Force -Recurse -ErrorAction SilentlyContinue

    start explorer.exe

    $path = "$env:USERPROFILE\OneDrive\Personal Vault"
try {
    [System.IO.Directory]::GetFiles($path) | Out-Null
    Write-Host "ACCESS GRANTED (Vault should be locked)" -ForegroundColor Red
} catch {
    Write-Host "ACCESS DENIED (Expected when locked): $($_.Exception.Message)" -ForegroundColor Green
}

    Write-Log "Icon repair completed..." 'SUCCESS'
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
param (
        [string]$ReportPath = "C:\Temp\OneDrive_Full_Diagnostic_Report.txt",
        [int]$MaxPathLength = 240
    )

    "===== OneDrive Full Diagnostic Report =====" | Out-File $ReportPath
    "Generated: $(Get-Date)" | Out-File -Append $ReportPath
    "`n--- Configured Accounts ---" | Out-File -Append $ReportPath

    $Accounts = Get-ItemProperty "HKCU:\Software\Microsoft\OneDrive\Accounts\*" -ErrorAction SilentlyContinue

    if (!$Accounts) {
        "❌ No OneDrive accounts configured" | Out-File -Append $ReportPath
        return [PSCustomObject]@{
            AccountsScanned = 0
            TotalItems      = 0
            TotalIssues     = 0
            ReportPath      = $ReportPath
            Accounts        = @()
        }
    }

    $SummaryAccounts = @()
    $GrandTotalItems = 0
    $GrandTotalIssues = 0
    $TotalAccounts = 0

    foreach ($Acc in $Accounts) {
        $TotalAccounts++

        "Account: $($Acc.DisplayName)" | Out-File -Append $ReportPath
        "Email  : $($Acc.UserEmail)"   | Out-File -Append $ReportPath
        "Folder : $($Acc.UserFolder)"  | Out-File -Append $ReportPath

        # Guard against null or empty UserFolder
        if ([string]::IsNullOrWhiteSpace($Acc.UserFolder)) {
            "⚠️ Reason: Sync folder not set → Fix: Re-link OneDrive" | Out-File -Append $ReportPath
            $SummaryAccounts += [PSCustomObject]@{
                DisplayName = $Acc.DisplayName
                Email       = $Acc.UserEmail
                Folder      = $Acc.UserFolder
                ItemsScanned= 0
                IssuesFound = 0
            }
            continue
        }

        if (!(Test-Path -LiteralPath $Acc.UserFolder)) {
            "⚠️ Reason: Sync folder missing → Fix: Re-link OneDrive" | Out-File -Append $ReportPath
            $SummaryAccounts += [PSCustomObject]@{
                DisplayName = $Acc.DisplayName
                Email       = $Acc.UserEmail
                Folder      = $Acc.UserFolder
                ItemsScanned= 0
                IssuesFound = 0
            }
            continue
        }

        $RootPath = $Acc.UserFolder
        "`n--- File Scan ($RootPath) ---" | Out-File -Append $ReportPath

        $InvalidChars = '[\"*:<>?/\\|]'
        $Reserved = @("CON","PRN","AUX","NUL","COM1","COM2","COM3","COM4","COM5","COM6","COM7","COM8","COM9","LPT1","LPT2","LPT3","LPT4","LPT5","LPT6","LPT7","LPT8","LPT9")

        $IssueCount = 0
        $ItemCount = 0

        $Files = Get-ChildItem -LiteralPath $RootPath -Recurse -Force -ErrorAction SilentlyContinue

        foreach ($File in $Files) {
            $ItemCount++
            $Issues = @()

            $Name = $File.Name
            $FullPath = $File.FullName

            if ($FullPath.Length -ge $MaxPathLength) {
                $Issues += "LongPath → Reason: Exceeds $MaxPathLength characters → Fix: Shorten path"
            }
            if ($Name -match $InvalidChars) {
                $Issues += "InvalidChar → Reason: Unsupported characters → Fix: Rename"
            }
            if ($Name -match '(^\s)|(\s$)|(\.$)') {
                $Issues += "NamingIssue → Reason: Leading/trailing space or dot → Fix: Rename"
            }
            $Base = [System.IO.Path]::GetFileNameWithoutExtension($Name)
            if ($Reserved -contains $Base.ToUpper()) {
                $Issues += "ReservedName → Reason: Windows reserved name → Fix: Rename"
            }
            if ($File.Attributes -match "System") {
                $Issues += "SystemFile → Reason: System attribute may block sync → Fix: attrib -s"
            }
            if ($Name -like "~$*") {
                $Issues += "TempFile → Reason: Temporary Office file → Fix: Close app/delete"
            }
            if ($File.Extension -in ".ini",".db") {
                $Issues += "Metadata → Reason: App/system file → Fix: Move outside OneDrive"
            }
            if ($Name -match '[\x00-\x1F]') {
                $Issues += "InvalidUnicode → Reason: Control characters → Fix: Rename"
            }

            if ($Issues.Count -gt 0) {
                $IssueCount++
                "$FullPath --> $($Issues -join ' | ')" | Out-File -Append $ReportPath
            }
        }

        "Scanned: $ItemCount items" | Out-File -Append $ReportPath
        "Issues : $IssueCount found" | Out-File -Append $ReportPath

        $GrandTotalItems += $ItemCount
        $GrandTotalIssues += $IssueCount

        $SummaryAccounts += [PSCustomObject]@{
            DisplayName = $Acc.DisplayName
            Email       = $Acc.UserEmail
            Folder      = $Acc.UserFolder
            ItemsScanned= $ItemCount
            IssuesFound = $IssueCount
        }
    }

    return [PSCustomObject]@{
        AccountsScanned = $TotalAccounts
        TotalItems      = $GrandTotalItems
        TotalIssues     = $GrandTotalIssues
        ReportPath      = $ReportPath
        Accounts        = $SummaryAccounts
    }
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

function RealTimeCPU {

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


 ================================
# REAL-TIME FOLDER MONITOR
# ================================

function RealTimeMonitor {

    Write-Title "Monitoring OneDrive Folder"

    $Path = "$env:USERPROFILE\OneDrive"

    $watcher = New-Object IO.FileSystemWatcher $Path -Property @{
        IncludeSubdirectories = $true
        EnableRaisingEvents = $true
    }

    Register-ObjectEvent $watcher Changed -Action {
        Write-Host "Changed: $($Event.SourceEventArgs.FullPath)"
    }

    Register-ObjectEvent $watcher Created -Action {
        Write-Host "Created: $($Event.SourceEventArgs.FullPath)"
    }

    while ($true) { Start-Sleep 5 }
}


function RestoreDefaultFoldersPostOneDrive{
    # --- Logging Setup ---
       $logFile = "$env:USERPROFILE\ResetShellFolders.log"
    function Write-Log {
        param(
            [string]$Message,
            [string]$Level = "INFO"
        )
        $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $entry = "[$timestamp] [$Level] $Message"
        Add-Content -Path $logFile -Value $entry
        Write-Host $entry
    }

    Write-Log "Starting Reset-UserShellFolders script"

    # --- Elevate Script if Not Running as Admin ---
    If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "Not running as admin, relaunching..." "WARN"
        Start-Process powershell.exe "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        Exit
    }

    # --- Stop explorer.exe ---
    try {
        Stop-Process -Name explorer -Force
        Write-Log "Stopped explorer.exe"
    } catch {
        Write-Log "Failed to stop explorer.exe: $_" "ERROR"
    }
    Start-Sleep -Seconds 2

    # --- Folder Definitions ---
    $folders = @{
        "Desktop"     = "Desktop"
        "Personal"    = "Documents"
        "Downloads"   = "Downloads"
        "My Music"    = "Music"
        "My Pictures" = "Pictures"
        "My Video"    = "Videos"
        "Favorites"   = "Favorites"
        "Contacts"    = "Contacts"
        "Links"       = "Links"
        "SavedGames"  = "Saved Games"
        "Searches"    = "Searches"
        "3D Objects"  = "3D Objects"
    }

    # --- Process Each Folder ---
    foreach ($regName in $folders.Keys) {
        $relativePath = $folders[$regName]
        $fullPath     = Join-Path $env:USERPROFILE $relativePath

        if (-Not (Test-Path $fullPath)) {
            New-Item -ItemType Directory -Path $fullPath | Out-Null
            Write-Log "Created missing folder: $fullPath"
        } else {
            Write-Log "Folder exists: $fullPath"
        }

        try {
            Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" `
                -Name $regName -Value $fullPath -ErrorAction Stop
            Write-Log "Updated Shell Folders registry for ${regName}"
        } catch {
            Write-Log "Could not write Shell Folders registry for ${regName}: $_" "WARN"
        }

        try {
            Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" `
                -Name $regName -Value "%USERPROFILE%\$relativePath" -ErrorAction Stop
            Write-Log "Updated User Shell Folders registry for ${regName}"
        } catch {
            Write-Log "Could not write User Shell Folders registry for ${regName}: $_" "WARN"
        }

        try {
            cmd /c "attrib +r -s -h `"$fullPath`" /S /D"
            Write-Log "Applied attributes to ${fullPath}"
        } catch {
            Write-Log "Failed to apply attributes to ${fullPath}: $_" "ERROR"
        }
    }

    # --- Restart Explorer ---
    Start-Sleep -Seconds 1
    try {
        Start-Process explorer.exe
        Write-Log "Restarted explorer.exe"
    } catch {
        Write-Log "Failed to restart explorer.exe: $_" "ERROR"
    }

    # --- Validation Section ---
    Write-Log "Validating registry and folder paths..."
    foreach ($regName in $folders.Keys) {
        $expectedPath = Join-Path $env:USERPROFILE $folders[$regName]

        $shellValue = (Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" -Name $regName -ErrorAction SilentlyContinue).$regName
        $userShellValue = (Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -Name $regName -ErrorAction SilentlyContinue).$regName

        if ($shellValue -eq $expectedPath) {
            Write-Log "Shell Folders registry correct for ${regName}: $shellValue"
        } else {
            Write-Log "Shell Folders registry mismatch for ${regName}: $shellValue (expected $expectedPath)" "WARN"
        }

        if ($userShellValue -eq "%USERPROFILE%\$($folders[$regName])") {
            Write-Log "User Shell Folders registry correct for ${regName}: $userShellValue"
        } else {
            Write-Log "User Shell Folders registry mismatch for ${regName}: $userShellValue (expected %USERPROFILE%\$($folders[$regName]))" "WARN"
        }

        if (Test-Path $expectedPath) {
            Write-Log "Folder exists for ${regName}: $expectedPath"
        } else {
            Write-Log "Folder missing for ${regName}: $expectedPath" "ERROR"
        }
    }

    Write-Log "Completed Reset-UserShellFolders script"
}

# ===== Junction Remover =====
function JunctionRemover {
    param (
        [string[]]$Folders = @("Desktop","Documents","Downloads","Music","Pictures","Videos"),
        [string]$UserProfile = $env:USERPROFILE,
        [string]$OneDrivePath = $env:OneDrive,
        [string]$LogFile = "$env:USERPROFILE\MoveJunctionLog_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').txt"
    )

    # Start log file
    Add-Content -Path $LogFile -Value "=== Move-AndJunctionUserFolders Log Started $(Get-Date) ==="

    foreach ($folder in $Folders) {
        $userFolder = Join-Path $UserProfile $folder
        $oneDriveFolder = Join-Path $OneDrivePath $folder

        if ((Test-Path $userFolder) -and -not ((Get-Item $userFolder).Attributes.ToString().Contains("ReparsePoint"))) {
            
            # Safety check: see if any process is locking files in this folder
            $inUse = Get-Process | ForEach-Object {
                try {
                    $_.Modules | Where-Object { $_.FileName -like "$userFolder*" }
                } catch { }
            }

            if ($inUse) {
                $msg = "⚠ Skipped $folder because it is currently in use."
                Write-Warning $msg
                Add-Content -Path $LogFile -Value $msg
                continue
            }

            # Ensure OneDrive folder exists
            New-Item -Path $oneDriveFolder -ItemType Directory -Force -ErrorAction SilentlyContinue

            # Move contents
            Move-Item -Path "$userFolder\*" -Destination $oneDriveFolder -Force -ErrorAction SilentlyContinue

            # Create junction
            New-Item -ItemType Junction -Path $userFolder -Value $oneDriveFolder -Force -ErrorAction SilentlyContinue

            $msg = "✔ Moved and linked $folder"
            Write-Host $msg
            Add-Content -Path $LogFile -Value $msg
        }
        else {
            $msg = "ℹ Skipped $folder (already junction or missing)"
            Write-Host $msg
            Add-Content -Path $LogFile -Value $msg
        }
    }

    Add-Content -Path $LogFile -Value "=== Log Ended $(Get-Date) ==="
    Write-Host "📂 Log saved to $LogFile"
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
    Write-Host "6. ODC CPU Monitor"
    Write-Host "7. ChracterCount"
    Write-Host "8. New Local User Account"
    Write-Host "9. Logs Collection"    
    Write-Host "10. Icon repair"
	Write-Host "11. Sync repair"
	Write-Host "1A. RealTime Folder Monitor"
	Write-Host "1B. Restore-Default-Folders-Post-OneDrive"
	Write-Host "1C. Junction Remover"
    Write-Host "0. Exit"
    Write-Host ""
}

function Run-Menu {
    do {
        Show-Menu
        $c = Read-Host "Select 0-11"
        switch ($c) {
            '1' { Do-Remove; Pause }
            '2' { $script:DeepClean=$true; Do-Remove; Pause }
            '3' { $script:DeepClean=$true; $script:RemoveMyFiles=$true; Do-Remove; Pause }
            '4' { Do-Reinstall; Pause }
            '5' { Set-Policy -Block $true; Pause }
	        '6' { RealTimeCPU }
            '7' { ChracterCount; Pause }
	        '8' { NewLocalUserAccount; Pause }
	        '9' { LogsCollection; Pause }
            '10' { IconRepair; Pause }
			'11' { SyncRepair; Pause }
			"1A" { RealTimeMonitor; pause }
			"1B" {RestoreDefaultFoldersPostOneDrive; pause}
			"1C" {JunctionRemover; pause }
            '0' { Write-Host "Exiting"; return }
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
