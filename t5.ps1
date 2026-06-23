<#
===========================================================================
OneDrive High Churn / Sync Loop Detection Script
===========================================================================
 
Purpose:
- Detect files/folders changing continuously in OneDrive
- Identify filesystem churn
- Monitor actively modified files
- Help isolate sync loops, temp files, cache activity, build folders, etc.
 
Features:
- Real-time monitoring
- Top modified files
- Change frequency tracking
- Streamlined logging (Churn + Hotspots combined)
- CPU + OneDrive process visibility
- Timestamped console output
===========================================================================
#>
 
# ---------------- CONFIGURATION ---------------- #
 
$OneDrivePath = "$env:USERPROFILE\OneDrive"
 
# How often to refresh (seconds)
$RefreshInterval = 5
 
# Number of files to display
$TopFiles = 100000
 
# Enable logging to file
$EnableLogging = $true
 
# Log file location
$LogFile = "$env:USERPROFILE\Desktop\OneDrive_Churn_Log.txt"
 
# ------------------------------------------------ #
 
# Validate OneDrive Path
if (-not (Test-Path $OneDrivePath)) {
    Write-Host "ERROR: OneDrive path not found at '$OneDrivePath'" -ForegroundColor Red
    Write-Host "Please verify the path and try again." -ForegroundColor Red
    exit
}
 
# Create log file and add header if it doesn't exist
if ($EnableLogging -and !(Test-Path $LogFile)) {
    $Header = @"
==================================================
OneDrive Churn Detection Log Initialized
Started: $(Get-Date)
Monitoring: $OneDrivePath
==================================================
"@
    Add-Content -Path $LogFile -Value $Header
}
 
# Store previous snapshot
$PreviousSnapshot = @{}
 
Write-Host ""
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host " OneDrive High Churn Detection Monitor Started"
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Monitoring Path: $OneDrivePath"
Write-Host "Refresh Interval: $RefreshInterval seconds"
Write-Host "Log File: $LogFile"
Write-Host ""
 
Start-Sleep 2
 
while ($true) {
    Clear-Host
 
    $CurrentTime = Get-Date
 
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host " OneDrive Churn Analysis"
    Write-Host " Time: $CurrentTime"
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host ""
 
    # ---------------- PROCESS INFO ---------------- #
    try {
        $OneDriveProc = Get-Process OneDrive -ErrorAction Stop
        Write-Host "OneDrive Process Information" -ForegroundColor Yellow
        Write-Host "-------------------------------------------"
        foreach ($proc in $OneDriveProc) {
            $cpu = [math]::Round($proc.CPU, 2)
            $mem = [math]::Round($proc.WorkingSet64 / 1MB, 2)
            Write-Host ("PID: {0} | CPU Time: {1} | Memory(MB): {2}" -f $proc.Id, $cpu, $mem)
        }
        Write-Host ""
    }
    catch {
        Write-Host "OneDrive process not currently running." -ForegroundColor Red
        Write-Host ""
    }
 
    # ---------------- FILE ENUMERATION ---------------- #
    Write-Host "Scanning files..." -ForegroundColor Yellow
 
    try {
        $Files = Get-ChildItem $OneDrivePath -Recurse -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        $TopModified = $Files | Select-Object -First $TopFiles
 
        Write-Host ""
        Write-Host "Most Recently Modified Files" -ForegroundColor Green
        Write-Host "------------------------------------------------------------"
 
        $ChangeDetected = $false
        $LogBuffer = @() # Array to hold log entries for this cycle
 
        foreach ($file in $TopModified) {
            $SizeMB = [math]::Round($file.Length / 1MB, 2)
            Write-Host ""
            Write-Host "File      : $($file.FullName)" -ForegroundColor White
            Write-Host "Modified  : $($file.LastWriteTime)"
            Write-Host "Size (MB) : $SizeMB"
 
            # ---------------- CHANGE DETECTION ---------------- #
            if ($PreviousSnapshot.ContainsKey($file.FullName)) {
                # FIXED: Correctly retrieve the previous time from the dictionary
                $PreviousTime = $PreviousSnapshot[$file.FullName]
 
                if ($PreviousTime -ne $file.LastWriteTime) {
                    Write-Host "STATUS    : ACTIVE CHANGE DETECTED" -ForegroundColor Red
                    $ChangeDetected = $true
                    
                    if ($EnableLogging) {
                        $LogBuffer += "[CHURN DETECTED] $($file.FullName)"
                        $LogBuffer += "  Old Time: $PreviousTime"
                        $LogBuffer += "  New Time: $($file.LastWriteTime)"
                        $LogBuffer += "  Size: $SizeMB MB"
                    }
                }
            }
 
            # Store/Update snapshot
            $PreviousSnapshot[$file.FullName] = $file.LastWriteTime
        }
 
        # ---------------- DIRECTORY HOTSPOTS ---------------- #
        Write-Host ""
        Write-Host "------------------------------------------------------------"
        Write-Host "Potential Hot Directories"
        Write-Host "------------------------------------------------------------"
 
        $TopDirs = $Files | Group-Object DirectoryName | Sort-Object Count -Descending | Select-Object -First 10
 
        foreach ($dir in $TopDirs) {
            Write-Host ("{0} files -> {1}" -f $dir.Count, $dir.Name)
        }
 
        # ---------------- SUSPICIOUS FILE TYPES ---------------- #
        Write-Host ""
        Write-Host "------------------------------------------------------------"
        Write-Host "Potential Temp / Cache / Build Files"
        Write-Host "------------------------------------------------------------"
 
        $Suspicious = $Files | Where-Object {
            $_.Extension -match "\.tmp|\.temp|\.cache|\.log|\.etl|\.ds_store|\.ldb|\.sqlite|\.journal|\.part|\.download"
        } | Select-Object -First 20
 
        foreach ($item in $Suspicious) {
            Write-Host $item.FullName -ForegroundColor Magenta
        }
 
        # ---------------- STREAMLINED LOGGING ---------------- #
        # Only write to log if changes were detected to prevent massive log bloat
        if ($EnableLogging -and $ChangeDetected) {
            $LogBuffer += "--------------------------------------------------"
            $LogBuffer += "[TOP HOT DIRECTORIES (Context)]"
            
            $TopDirsForLog = $TopDirs | Select-Object -First 5
            foreach ($dir in $TopDirsForLog) {
                $LogBuffer += "  $($dir.Count) files -> $($dir.Name)"
            }
            $LogBuffer += "==================================================`r`n"
            
            # Append the combined log entry to the file
            Add-Content -Path $LogFile -Value ($LogBuffer -join "`r`n")
        }
 
    }
    catch {
        Write-Host ""
        Write-Host "Failed to scan OneDrive files." -ForegroundColor Red
        Write-Host $_.Exception.Message
    }
 
    Write-Host ""
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host " Refreshing in $RefreshInterval seconds..."
    Write-Host " Press CTRL + C to stop"
    Write-Host "===================================================" -ForegroundColor Cyan
 
    Start-Sleep -Seconds $RefreshInterval
}