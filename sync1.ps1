<#
OneDrive Ultimate Repair & Diagnostic Toolkit
Windows 10 / 11
Author: Ultimate Sync Suite
Logs: C:\ProgramData\OneDriveToolkit\
#>

# ================================
# INIT LOGGING
# ================================

$BaseDir = "C:\ProgramData\OneDriveToolkit"
if (!(Test-Path $BaseDir)) {
    New-Item $BaseDir -ItemType Directory -Force | Out-Null
}

$LogFile = "$BaseDir\Session_$(Get-Date -Format yyyyMMdd_HHmmss).log"
Start-Transcript -Path $LogFile -Append

# ================================
# UTILITIES
# ================================

function Write-Title($text) {
    Write-Host "`n===================================" -ForegroundColor Cyan
    Write-Host $text -ForegroundColor Cyan
    Write-Host "===================================" -ForegroundColor Cyan
}

function Pause { Read-Host "`nPress Enter to continue" }

function Get-OneDrivePaths {
    return @(
        "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe",
        "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe",
        "$env:ProgramFiles(x86)\Microsoft OneDrive\OneDrive.exe"
    )
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

# ================================
# REAL-TIME DIAGNOSTIC
# ================================

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
# ================================
# FORENSIC COLLECTOR
# ================================

function ForensicCollector {

    Write-Title "Collecting Forensic Data"

    $OutDir = "$BaseDir\Forensic_$(Get-Date -Format yyyyMMdd_HHmmss)"
    New-Item $OutDir -ItemType Directory -Force | Out-Null

    reg export HKCU\Software\Microsoft\OneDrive "$OutDir\HKCU.reg" /y 2>$null
    reg export HKLM\Software\Microsoft\OneDrive "$OutDir\HKLM.reg" /y 2>$null
    ipconfig /all > "$OutDir\network.txt"

    Copy-Item "$env:LOCALAPPDATA\Microsoft\OneDrive\logs" "$OutDir\Logs" -Recurse -ErrorAction SilentlyContinue

    Write-Host "Forensic package saved to $OutDir" -ForegroundColor Green
}

# ================================
# DEEP SCANNER
# ================================

function DeepScanner {

    Write-Title "Deep Sync DB Scanner"

    $settings = "$env:LOCALAPPDATA\Microsoft\OneDrive\settings"

    if (Test-Path $settings) {

        $dbSize = (Get-ChildItem $settings -Recurse | Measure-Object Length -Sum).Sum

        if ($dbSize -eq 0) {
            Write-Host "Sync DB EMPTY → Corruption Likely" -ForegroundColor Red
        }
        elseif ($dbSize -gt 2GB) {
            Write-Host "Sync DB Very Large → Possible Loop" -ForegroundColor Yellow
        }
        else {
            Write-Host "DB Size Normal: $([math]::Round($dbSize/1MB,2)) MB" -ForegroundColor Green
        }
    }
    else {
        Write-Host "Settings folder missing" -ForegroundColor Red
    }
}

# ================================
# GHOST INSTALL KILLER
# ================================

function GhostInstallKiller {

    Write-Title "Ghost Install Killer"

    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force

    Start-Process "$env:SystemRoot\SysWOW64\OneDriveSetup.exe" -ArgumentList "/uninstall" -Wait -ErrorAction SilentlyContinue

    Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall" |
    Where-Object { (Get-ItemProperty $_.PSPath).DisplayName -like "*OneDrive*" } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    Remove-Item "$env:LOCALAPPDATA\Microsoft\OneDrive" -Recurse -Force -ErrorAction SilentlyContinue

    Start-Process "$env:SystemRoot\SysWOW64\OneDriveSetup.exe" -Wait

    Write-Host "Ghost install cleared." -ForegroundColor Green
}

# ================================
# AUTO REPAIR
# ================================

function AutoRepair {

    Write-Title "Automated Repair Started"

    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force

    Remove-Item "HKLM:\Software\Policies\Microsoft\Windows\OneDrive" -Recurse -Force -ErrorAction SilentlyContinue

    $paths = Get-OneDrivePaths
    foreach ($p in $paths) {
        if (Test-Path $p) {
            Start-Process $p -ArgumentList "/reset"
        }
    }

    ipconfig /flushdns | Out-Null
    netsh winsock reset | Out-Null

    Write-Host "Repair completed." -ForegroundColor Green
}

# ================================
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

# ================================
# PERSONAL VAULT DIAGNOSTIC
# ================================

function PersonalVaultDiagnostic {

    Write-Title "Personal Vault Diagnostic"

    $health = 100
    $vaultPath = "$env:USERPROFILE\OneDrive\Personal Vault"
    $policyPath = "HKLM:\Software\Policies\Microsoft\Windows\OneDrive"

    Write-Host "`nChecking OneDrive Process..."
    $proc = Get-Process OneDrive -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "OneDrive Running" -ForegroundColor Green
    } else {
        Write-Host "OneDrive NOT Running" -ForegroundColor Red
        $health -= 20
    }

    Write-Host "`nChecking Personal Vault Folder..."
    if (Test-Path $vaultPath) {
        Write-Host "Vault folder exists." -ForegroundColor Green

        try {
            Get-ChildItem $vaultPath -ErrorAction Stop | Out-Null
            Write-Host "Vault is UNLOCKED" -ForegroundColor Green
        }
        catch {
            Write-Host "Vault appears LOCKED or inaccessible" -ForegroundColor Yellow
            $health -= 10
        }
    }
    else {
        Write-Host "Vault folder NOT found." -ForegroundColor Red
        $health -= 25
    }

    Write-Host "`nChecking Policy Restrictions..."
    if (Test-Path $policyPath) {
        $policy = Get-ItemProperty $policyPath -ErrorAction SilentlyContinue
        if ($policy.DisablePersonalVault -eq 1) {
            Write-Host "Personal Vault is disabled by policy." -ForegroundColor Red
            $health -= 30
        }
        else {
            Write-Host "No blocking vault policy detected." -ForegroundColor Green
        }
    }
    else {
        Write-Host "No OneDrive policy registry found." -ForegroundColor Green
    }

    Write-Host "`nChecking Event Logs (Recent Vault Errors)..."
    $events = Get-WinEvent -LogName Application -MaxEvents 100 |
        Where-Object { $_.Message -match "Vault" -or $_.Message -match "OneDrive" }

    if ($events) {
        Write-Host "Recent vault-related events detected." -ForegroundColor Yellow
        $health -= 10
    }
    else {
        Write-Host "No recent vault errors found." -ForegroundColor Green
    }

    Write-Host "`nChecking Sync Database..."
    $settings = "$env:LOCALAPPDATA\Microsoft\OneDrive\settings"
    if (Test-Path $settings) {
        $dbSize = (Get-ChildItem $settings -Recurse | Measure-Object Length -Sum).Sum
        if ($dbSize -eq 0) {
            Write-Host "Sync DB empty → Possible corruption" -ForegroundColor Red
            $health -= 20
        }
        else {
            Write-Host "Sync DB healthy." -ForegroundColor Green
        }
    }

    Write-Host "`nChecking Credential Tokens..."
    $creds = cmdkey /list | Select-String "OneDrive"
    if ($creds) {
        Write-Host "Credential entries found." -ForegroundColor Green
    }
    else {
        Write-Host "No OneDrive credentials found." -ForegroundColor Yellow
        $health -= 10
    }

    Write-Host "`nPersonal Vault Health Score: $health / 100"

    if ($health -ge 80) {
        Write-Host "Vault Status: HEALTHY" -ForegroundColor Green
    }
    elseif ($health -ge 50) {
        Write-Host "Vault Status: WARNING" -ForegroundColor Yellow
    }
    else {
        Write-Host "Vault Status: CRITICAL" -ForegroundColor Red
    }
}

# ================================
# ADVANCED VAULT REPAIR ENGINE
# ================================

function AdvancedVaultRepair {

    Write-Title "Advanced Personal Vault Repair Engine"

    $vaultPath = "$env:USERPROFILE\OneDrive\Personal Vault"
    $policyPath = "HKLM:\Software\Policies\Microsoft\Windows\OneDrive"

    Write-Host "`nStopping OneDrive..."
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force

    Write-Host "Removing blocking policies..."
    Remove-ItemProperty -Path $policyPath -Name DisablePersonalVault -ErrorAction SilentlyContinue

    Write-Host "Clearing cached credentials..."
    cmdkey /list | Select-String "OneDrive" | ForEach-Object {
        $target = ($_ -split ":")[1].Trim()
        cmdkey /delete:$target 2>$null
    }

    Write-Host "Repairing Sync DB..."
    $settings = "$env:LOCALAPPDATA\Microsoft\OneDrive\settings"
    if (Test-Path $settings) {
        Rename-Item $settings "$settings.bak_$(Get-Date -Format HHmmss)" -ErrorAction SilentlyContinue
    }

    Write-Host "Resetting OneDrive..."
    $paths = Get-OneDrivePaths
    foreach ($p in $paths) {
        if (Test-Path $p) {
            Start-Process $p -ArgumentList "/reset"
        }
    }

    Start-Sleep 5

    Write-Host "Restarting OneDrive..."
    foreach ($p in $paths) {
        if (Test-Path $p) {
            Start-Process $p
            break
        }
    }

    Write-Host "`nVault repair process completed." -ForegroundColor Green
}


# ================================
# AUTOMATED VAULT RECOVERY
# ================================

function AutomatedVaultRecovery {

    Write-Title "Automated Personal Vault Recovery"

    $backupDir = "C:\ProgramData\OneDriveToolkit\VaultBackup_$(Get-Date -Format yyyyMMdd_HHmmss)"
    New-Item $backupDir -ItemType Directory -Force | Out-Null

    $vaultMeta = "$env:LOCALAPPDATA\Microsoft\OneDrive"
    $vaultPath = "$env:USERPROFILE\OneDrive\Personal Vault"

    Write-Host "`nStopping OneDrive..."
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force

    Write-Host "Backing up metadata..."
    Copy-Item $vaultMeta $backupDir -Recurse -ErrorAction SilentlyContinue

    Write-Host "Flushing network stack..."
    ipconfig /flushdns | Out-Null
    netsh winsock reset | Out-Null

    Write-Host "Removing corrupted sync DB..."
    Remove-Item "$env:LOCALAPPDATA\Microsoft\OneDrive\settings" -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "Clearing OneDrive tokens..."
    cmdkey /list | Select-String "OneDrive" | ForEach-Object {
        $target = ($_ -split ":")[1].Trim()
        cmdkey /delete:$target 2>$null
    }

    Write-Host "Reinitializing OneDrive..."
    $paths = Get-OneDrivePaths
    foreach ($p in $paths) {
        if (Test-Path $p) {
            Start-Process $p -ArgumentList "/reset"
            Start-Sleep 3
            Start-Process $p
            break
        }
    }

    Write-Host "`nRecovery process completed."
    Write-Host "Metadata backup saved to: $backupDir" -ForegroundColor Cyan
}

function Invoke-CPUHealing {

    param(
        [int]$CpuThreshold = 80,
        [int]$RecheckDelaySeconds = 5
    )

    Write-Log "Starting CPU Spike Monitor..."

    $procs = Get-Process -Name OneDrive -ErrorAction SilentlyContinue

    if (-not $procs) {
        Write-Log "OneDrive not running. No CPU healing needed."
        return
    }

    # Get total CPU value
    $cpuTotal = ($procs | Measure-Object -Property CPU -Sum).Sum

    Write-Log "Current CPU value: $cpuTotal"

    if ($cpuTotal -gt $CpuThreshold) {

        Write-Log "CPU spike detected. Waiting $RecheckDelaySeconds seconds before action..."
        Start-Sleep -Seconds $RecheckDelaySeconds

        $recheck = Get-Process -Name OneDrive -ErrorAction SilentlyContinue
        $cpuRecheck = ($recheck | Measure-Object -Property CPU -Sum).Sum

        Write-Log "Rechecked CPU value: $cpuRecheck"

        if ($cpuRecheck -gt $CpuThreshold) {

            Write-Log "Persistent CPU spike confirmed. Initiating self-healing..."

            # Graceful stop
            Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3

            # Restart OneDrive
            $exePath = "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"

            if (Test-Path $exePath) {
                Start-Process $exePath
                Write-Log "OneDrive restarted successfully."
            } else {
                Write-Log "OneDrive executable not found!"
            }

            $Global:HealthScore -= 10

        }
        else {
            Write-Log "CPU spike was temporary. No action taken."
        }

    }
    else {
        Write-Log "CPU within normal range."
    }
}

# ================================
# REAL TIME MONITOR
# ================================

function Start-RealtimeMonitor {

    Write-Log "Starting Real-Time Monitor..."

    while ($true) {

        Clear-Host
        Write-Host "==== OneDrive Live Monitor ===="

        $proc = Get-Process -Name OneDrive -ErrorAction SilentlyContinue

        if ($proc) {

            $cpu = ($proc | Measure-Object CPU -Sum).Sum
            $mem = ($proc | Measure-Object WorkingSet64 -Sum).Sum

            Write-Host "Status: RUNNING" -ForegroundColor Green
            Write-Host ("CPU: {0}" -f [math]::Round($cpu,2))
            Write-Host ("Memory: {0} MB" -f [math]::Round($mem/1MB,2))

            Invoke-CPUHealing -CpuThreshold 80

        }
        else {
            Write-Host "Status: NOT RUNNING" -ForegroundColor Red
            $Global:HealthScore -= 20
        }

        Write-Host ("Health Score: {0}/100" -f $Global:HealthScore)

        Start-Sleep 5
    }
}


# ================================
# MENU
# ================================

function Show-Menu {

    Clear-Host
    Write-Title "OneDrive Ultimate Toolkit"

    Write-Host "1. Health Score"
    Write-Host "2. Real-Time Diagnostic"
    Write-Host "3. Deep Health Scanner"
    Write-Host "4. Forensic Collector"
    Write-Host "5. Automated Repair"
    Write-Host "6. Ghost Install Killer"
    Write-Host "7. Real-Time Folder Monitor"
    Write-Host "8. Personal Vault Diagnostic"
    Write-Host "9. Advanced Vault Repair Engine"
    Write-Host "10. Automated Vault Recovery"
    Write-Host "11. Real-Time Monitor"
    Write-Host "0. Exit"
}

# ================================
# MAIN LOOP
# ================================

do {
    Show-Menu
    $choice = Read-Host "`nSelect Option"

    switch ($choice) {
        "1" { Write-Host "Health Score: $(Get-HealthScore)/100"; Pause }
        "2" { RealTimeDiagnostic }
        "3" { DeepScanner; Pause }
        "4" { ForensicCollector; Pause }
        "5" { AutoRepair; Pause }
        "6" { GhostInstallKiller; Pause }
        "7" { RealTimeMonitor }
	"8" { PersonalVaultDiagnostic; Pause }
	"9" { AdvancedVaultRepair; Pause }
	"10" { AutomatedVaultRecovery; Pause }
        "11" { RealTimeMonitor }
        "0" { break }
        default { Write-Host "Invalid choice"; Pause }
    }

} while ($choice -ne "0")

Stop-Transcript
Write-Host "`nSession log saved at: $LogFile" -ForegroundColor Green