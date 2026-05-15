<#
.SYNOPSIS
    Automates TrID to scan a directory and correct file extensions.
.DESCRIPTION
    Runs TrID on all files in the target directory, corrects extensions (-ce),
    exports results to CSV, and logs the process.
.PARAMETER TridPath
    Path to trid.exe (defaults to system PATH if available)
.PARAMETER TargetDir
    Directory containing files to scan
.PARAMETER OutputCsv
    Name of the output CSV file (saved in the script's directory)
#>

param(
    [string]$TridPath = "C:\TrID\trid.exe",
    [string]$TargetDir = "C:\test",
    [string]$OutputCsv = "results.csv"
)

# --- Logging Setup ---
$ScriptDir = $PSScriptRoot
$LogPath   = Join-Path $ScriptDir "TrID_Auto_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp [$Level] $Message" | Tee-Object -FilePath $LogPath -Append
}

Write-Log "=== TrID Automation Started ==="

# --- Validate TrID Executable ---
$TridExe = $null
if (Test-Path $TridPath) {
    $TridExe = Resolve-Path $TridPath
} else {
    $cmd = Get-Command $TridPath -ErrorAction SilentlyContinue
    if ($cmd) { $TridExe = $cmd.Source }
}

if (-not $TridExe) {
    Write-Log "ERROR: TrID executable not found. Provide full path or add to system PATH." "ERROR"
    exit 1
}

# --- Validate Target Directory ---
if (-not (Test-Path $TargetDir)) {
    Write-Log "ERROR: Target directory does not exist: $TargetDir" "ERROR"
    exit 1
}

# Resolve output path to script directory
$OutputPath = Join-Path $ScriptDir $OutputCsv

# --- Execute TrID ---
$ArgsList = @("$TargetDir\*", "-ce", "--out", $OutputPath)
Write-Log "Executing: & '$TridExe' $($ArgsList -join ' ')"

& $TridExe $ArgsList

# --- Check Result ---
if ($LASTEXITCODE -eq 0) {
    Write-Log "SUCCESS: TrID completed. Results saved to $OutputPath"
} else {
    Write-Log "WARNING: TrID exited with code $LASTEXITCODE. Check logs for details." "WARNING"
}

Write-Log "=== TrID Automation Finished ==="