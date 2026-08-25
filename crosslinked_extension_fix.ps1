<#
.SYNOPSIS
    Intelligent TrID automation with real-time progress bar and enhanced dual reporting.
    Prompts for target directory if run manually, accepts parameters for automation.
#>
[CmdletBinding()]
param(
    [string]$TargetDir = "",
    [string]$OutputCsv = "TrID_Results.csv",
    [string]$SummaryReport = "TrID_Summary_Report.html",
    [switch]$Force,
    [switch]$HideConsole,
    [switch]$DryRun,
    [switch]$OpenReport
)

# ==================== GLOBAL SETUP ====================
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

if ($HideConsole -and $host.Name -eq 'ConsoleHost') {
    Add-Type -Name Win -Namespace Console -MemberDefinition '
        [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    '
    [Console.Win]::ShowWindow([Console.Win]::GetConsoleWindow(), 0)
}

$ScriptDir = $PSScriptRoot
$LogPath = Join-Path $ScriptDir "TrID_Python_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([Parameter(Mandatory)][string]$Message, [ValidateSet("INFO","WARN","ERROR","SUCCESS")][string]$Level = "INFO")
    "$((Get-Date -Format "yyyy-MM-dd HH:mm:ss")) [$Level] $Message" | Add-Content -Path $LogPath -Force
    if (-not $HideConsole) {
        $color = switch ($Level) { "ERROR" { "Red" } "WARN" { "Yellow" } "SUCCESS" { "Green" } default { "White" } }
        Write-Host "[$Level] $Message" -ForegroundColor $color
    }
}

Write-Log "=== TrID Python Automation Started ===" "INFO"

# ==================== 1. INTERACTIVE INPUT / VALIDATION ====================
if ([string]::IsNullOrWhiteSpace($TargetDir)) {
    if ($HideConsole) {
        Write-Log "ERROR: -TargetDir parameter is required when running silently." "ERROR"
        exit 1
    }
    Write-Host "`n[TrID Auto] Please enter the target directory path:" -ForegroundColor Cyan
    $TargetDir = Read-Host ">> Target Directory"
    if ([string]::IsNullOrWhiteSpace($TargetDir)) {
        Write-Log "ERROR: No directory provided. Exiting." "ERROR"
        exit 1
    }
}

$TargetDir = $TargetDir.Trim('"').Trim()
try { $TargetDir = [System.IO.Path]::GetFullPath($TargetDir) } catch { Write-Log "ERROR: Invalid path format." "ERROR"; exit 1 }

if (-not (Test-Path $TargetDir -PathType Container)) { Write-Log "ERROR: Target directory not found: $TargetDir" "ERROR"; exit 1 }
Write-Log "Target directory resolved to: $TargetDir" "INFO"

# ==================== 2. FIND OR INSTALL PYTHON ====================
function Find-SystemPython {
    $cmds = @("python", "python3", "py")
    foreach ($c in $cmds) {
        $found = Get-Command $c -ErrorAction SilentlyContinue
        if ($found) {
            $ver = & $found.Source --version 2>&1
            if ($ver -match "Python \d+\.\d+") { return $found.Source }
        }
    }
    return $null
}

$PythonExe = Find-SystemPython
if ($PythonExe -and -not $Force) {
    Write-Log "System Python found: $PythonExe" "INFO"
} else {
    $PythonDir = Join-Path $ScriptDir "Python"
    $PythonExe = Join-Path $PythonDir "python.exe"
    
    if ((-not (Test-Path $PythonExe)) -or $Force) {
        Write-Log "System Python not found. Installing embedded runtime..." "INFO"
        if (Test-Path $PythonDir) { Remove-Item $PythonDir -Recurse -Force }
        New-Item -ItemType Directory -Path $PythonDir -Force | Out-Null
        
        $PyUrl = "https://www.python.org/ftp/python/3.12.8/python-3.12.8-embed-amd64.zip"
        $PyZip = Join-Path $env:TEMP "py-embed.zip"
        try {
            Invoke-WebRequest -Uri $PyUrl -OutFile $PyZip -UseBasicParsing -ErrorAction Stop
            Expand-Archive -Path $PyZip -DestinationPath $PythonDir -Force
            Remove-Item $PyZip -Force -ErrorAction SilentlyContinue

            $PthPath = Join-Path $PythonDir "python312._pth"
            $CleanPth = "python312.zip`n.`n#import site"
            [System.IO.File]::WriteAllText($PthPath, $CleanPth, (New-Object System.Text.UTF8Encoding $false))
            
            $test = & $PythonExe -c "import encodings; print('BOOT_OK')" 2>&1
            if ($test -notmatch "BOOT_OK") { throw "Embedded Python failed verification: $test" }
            Write-Log "Embedded Python verified successfully." "SUCCESS"
        } catch { Write-Log "Embedded Python setup failed: $_" "ERROR"; exit 1 }
    } else { Write-Log "Embedded Python already present." "INFO" }
}

# ==================== 3. DOWNLOAD TRID.PY & DEFINITIONS ====================
$TridPyPath = Join-Path $ScriptDir "trid.py"
$DefsZipUrl = "https://mark0.net/download/triddefs.zip"
$DefsZipPath = Join-Path $ScriptDir "triddefs.zip"
$DefsPath = Join-Path $ScriptDir "triddefs.trd"

if ($Force -or -not (Test-Path $TridPyPath)) {
    Write-Log "Downloading trid.py..." "INFO"
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/singhj775/OneDrive-Hybrid-Toolkit/main/trid.py" -OutFile $TridPyPath -UseBasicParsing -ErrorAction Stop
}

if ($Force -or -not (Test-Path $DefsPath)) {
    Write-Log "Downloading TrID definitions (ZIP)..." "INFO"
    try {
        Invoke-WebRequest -Uri $DefsZipUrl -OutFile $DefsZipPath -UseBasicParsing -ErrorAction Stop
        Expand-Archive -Path $DefsZipPath -DestinationPath $ScriptDir -Force
        Remove-Item $DefsZipPath -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $DefsPath)) { throw "triddefs.trd missing after extraction" }
        Write-Log "Definitions ready." "SUCCESS"
    } catch { Write-Log "Defs download failed: $_" "ERROR"; exit 1 }
} else { Write-Log "Definitions already present." "INFO" }

# ==================== 4. SMART PRE-COUNT FOR PROGRESS BAR ====================
Write-Log "Counting files in target directory for smart progress tracking..." "INFO"
if (-not $HideConsole) { Write-Progress -Activity "Preparing" -Status "Counting files..." }
$totalFiles = (Get-ChildItem -Path $TargetDir -File -Recurse -ErrorAction SilentlyContinue).Count
if (-not $HideConsole) { Write-Progress -Activity "Preparing" -Completed }

if ($totalFiles -eq 0) {
    Write-Log "No files found in target directory. Exiting." "WARN"
    exit 0
}
Write-Log "Found $totalFiles files to process." "INFO"

# ==================== 5. EXECUTE TRID WITH PROGRESS BAR ====================
$OutputPath = Join-Path $ScriptDir $OutputCsv
Write-Log "Target: $TargetDir | Output CSV: $OutputPath" "INFO"

# SMART FIX: Build arguments array dynamically using += to avoid fixed-size array errors
$cmdArgs = @(
    "`"$TridPyPath`"",
    "`"$TargetDir`""
)

if (-not $DryRun) {
    $cmdArgs += "-ce"
    Write-Log "Mode: LIVE (Extensions will be changed)" "INFO"
} else {
    Write-Log "Mode: DRY RUN (Extensions will NOT be changed, report only)" "WARN"
}

$cmdArgs += @(
    "-o",
    "`"$OutputPath`""
)

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $PythonExe
$psi.Arguments = $cmdArgs -join " "
$psi.WorkingDirectory = $ScriptDir
$psi.WindowStyle = "Hidden"
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true

$proc = [System.Diagnostics.Process]::Start($psi)
$outReader = $proc.StandardOutput
$errReader = $proc.StandardError
$stdoutLog = [System.Text.StringBuilder]::new()
$stderrLog = [System.Text.StringBuilder]::new()
$fileCount = 0

# Real-time output reading + Smart Progress Bar
while (-not $proc.HasExited) {
    try {
        if ($outReader.Peek() -ge 0) {
            $line = $outReader.ReadLine()
            if ($line) {
                $stdoutLog.AppendLine($line) | Out-Null
                if ($line -match "File:\s+(.+)") {
                    $fileCount++
                    $percentComplete = [math]::Round(($fileCount / $totalFiles) * 100, 2)
                    if (-not $HideConsole) {
                        Write-Progress -Activity "TrID Extension Correction" `
                                       -Status "Analyzing: $($Matches[1])" `
                                       -PercentComplete $percentComplete `
                                       -CurrentOperation "Files processed: $fileCount of $totalFiles ($percentComplete%)"
                    }
                }
            }
        }
        if ($errReader.Peek() -ge 0) {
            $errLine = $errReader.ReadLine()
            if ($errLine) { $stderrLog.AppendLine($errLine) | Out-Null }
        }
    } catch { break }
    Start-Sleep -Milliseconds 50
}

# Flush remaining output
while (($line = $outReader.ReadLine()) -ne $null) { $stdoutLog.AppendLine($line) | Out-Null }
while (($errLine = $errReader.ReadLine()) -ne $null) { $stderrLog.AppendLine($errLine) | Out-Null }

if (-not $HideConsole) { Write-Progress -Activity "TrID Extension Correction" -Completed }

$stdout = $stdoutLog.ToString().Trim()
$stderr = $stderrLog.ToString().Trim()

if ($stdout) { Write-Log "Python Output: $stdout" "INFO" }
if ($stderr) { Write-Log "Python Error: $stderr" "WARN" }

# ==================== 6. GENERATE ENHANCED REPORTS ====================
if ($proc.ExitCode -eq 0) {
    Write-Log "SUCCESS: Analysis complete." "SUCCESS"
    
    if (Test-Path $OutputPath) {
        try {
            $data = Import-Csv -Path $OutputPath -ErrorAction Stop
            $total = $data.Count
            $unknown = ($data | Where-Object { $_.'TrID-Score' -eq "0" -or [string]::IsNullOrWhiteSpace($_.Filetype) }).Count
            $processedLabel = if ($DryRun) { "Identified (No changes made)" } else { "Identified & Processed" }
            $processedCount = $total - $unknown
            
            $topTypes = $data | Where-Object { $_.Filetype -ne "" } | Group-Object Filetype | Sort-Object Count -Descending | Select-Object -First 5
            
            $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 40px; color: #333; background: #fcfcfc; }
        h1 { color: #2c3e50; border-bottom: 2px solid #3498db; padding-bottom: 10px; }
        .summary-box { display: flex; gap: 20px; margin-bottom: 30px; flex-wrap: wrap; }
        .card { background: #fff; padding: 25px; border-radius: 8px; flex: 1; min-width: 200px; text-align: center; box-shadow: 0 4px 6px rgba(0,0,0,0.05); border-top: 4px solid #3498db; }
        .card h2 { margin: 0; font-size: 2.5em; color: #2c3e50; }
        .card p { margin: 10px 0 0; color: #7f8c8d; font-weight: 600; text-transform: uppercase; font-size: 0.9em; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; background: #fff; box-shadow: 0 4px 6px rgba(0,0,0,0.05); }
        th, td { padding: 14px; text-align: left; border-bottom: 1px solid #eee; }
        th { background-color: #2c3e50; color: white; font-weight: 600; }
        tr:hover { background-color: #f8f9fa; }
        .footer { margin-top: 40px; color: #95a5a6; font-size: 0.9em; }
    </style>
</head>
<body>
    <h1>TrID Analysis Summary Report</h1>
    <p><strong>Generated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")<br>
    <strong>Target Directory:</strong> $TargetDir<br>
    <strong>Mode:</strong> $(if ($DryRun) { "Dry Run (Read-Only)" } else { "Live (Extensions Changed)" })</p>
    
    <div class="summary-box">
        <div class="card">
            <h2>$total</h2>
            <p>Total Files Scanned</p>
        </div>
        <div class="card" style="border-top-color: #27ae60;">
            <h2 style="color: #27ae60;">$processedCount</h2>
            <p>$processedLabel</p>
        </div>
        <div class="card" style="border-top-color: #e74c3c;">
            <h2 style="color: #e74c3c;">$unknown</h2>
            <p>Unknown / Unmatched</p>
        </div>
    </div>

    <h3>Top 5 Detected File Types</h3>
    <table>
        <tr><th>File Type</th><th>Count</th><th>Percentage</th></tr>
"@
            foreach ($type in $topTypes) {
                $pct = [math]::Round(($type.Count / $total) * 100, 1)
                $html += "        <tr><td>$($type.Name)</td><td>$($type.Count)</td><td>$pct%</td></tr>`n"
            }
            $html += @"
    </table>
    <div class="footer">
        <p><em>Detailed row-by-row results are available in:</em><br><strong>$OutputPath</strong></p>
    </div>
</body>
</html>
"@
            $htmlPath = Join-Path $ScriptDir $SummaryReport
            $html | Out-File -FilePath $htmlPath -Encoding UTF8 -Force
            Write-Log "Summary report generated: $htmlPath" "SUCCESS"
            
            if ($OpenReport) {
                Write-Log "Opening summary report..." "INFO"
                Invoke-Item -Path $htmlPath
            }
        } catch {
            Write-Log "Failed to generate summary report: $_" "WARN"
        }
    }
} else {
    Write-Log "WARNING: Process exited with code $($proc.ExitCode)." "WARN"
}

Write-Log "=== TrID Automation Finished ===" "INFO"
exit $proc.ExitCode
