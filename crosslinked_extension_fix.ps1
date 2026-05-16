<#
.SYNOPSIS
    Fully silent TrID automation with real-time progress bar.
    Prompts for target directory if run manually, accepts -TargetDir for automation.
#>
[CmdletBinding()]
param(
    [string]$TargetDir = "",
    [string]$OutputCsv = "results.csv",
    [switch]$Force,
    [switch]$HideConsole
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
}

Write-Log "=== TrID Python Automation Started ===" "INFO"

# ==================== 1. INTERACTIVE INPUT / VALIDATION ====================
if ([string]::IsNullOrWhiteSpace($TargetDir)) {
    if ($HideConsole) {
        Write-Log "ERROR: -TargetDir parameter is required when running silently or via Task Scheduler." "ERROR"
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

# ==================== 4. EXECUTE TRID WITH PROGRESS BAR ====================
$OutputPath = Join-Path $ScriptDir $OutputCsv
Write-Log "Target: $TargetDir | Output: $OutputPath" "INFO"

$CmdArgs = @($TridPyPath, $TargetDir, "-ce", "-o", $OutputPath)
Write-Log "Executing: $PythonExe $($CmdArgs -join ' ')" "INFO"

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $PythonExe
$psi.Arguments = $CmdArgs -join ' '
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

# Real-time output reading + Progress Bar
while (-not $proc.HasExited) {
    try {
        if ($outReader.Peek() -ge 0) {
            $line = $outReader.ReadLine()
            if ($line) {
                $stdoutLog.AppendLine($line) | Out-Null
                $fileCount++
                # Update progress when trid.py outputs a file path
                if (-not $HideConsole -and $line -match "File:\s+(.+)") {
                    Write-Progress -Activity "TrID Extension Correction" `
                                   -Status "Analyzing: $($Matches[1])" `
                                   -CurrentOperation "Files processed: $fileCount"
                }
            }
        }
        if ($errReader.Peek() -ge 0) {
            $errLine = $errReader.ReadLine()
            if ($errLine) { $stderrLog.AppendLine($errLine) | Out-Null }
        }
    } catch { break } # Stream closed
    Start-Sleep -Milliseconds 50
}

# Flush remaining output after process exits
while (($line = $outReader.ReadLine()) -ne $null) { $stdoutLog.AppendLine($line) | Out-Null }
while (($errLine = $errReader.ReadLine()) -ne $null) { $stderrLog.AppendLine($errLine) | Out-Null }

# Complete progress bar
if (-not $HideConsole) { Write-Progress -Activity "TrID Extension Correction" -Completed }

$stdout = $stdoutLog.ToString().Trim()
$stderr = $stderrLog.ToString().Trim()

if ($stdout) { Write-Log "Python Output: $stdout" "INFO" }
if ($stderr) { Write-Log "Python Error: $stderr" "WARN" }

if ($proc.ExitCode -eq 0) {
    Write-Log "SUCCESS: Extension correction complete. Results: $OutputPath" "SUCCESS"
    if (Test-Path $OutputPath) {
        try {
            $Rows = (Import-Csv $OutputPath -ErrorAction SilentlyContinue).Count
            Write-Log "CSV contains $Rows processed files." "INFO"
        } catch { Write-Log "Could not count CSV rows." "WARN" }
    }
} else {
    Write-Log "WARNING: Process exited with code $($proc.ExitCode)." "WARN"
}

Write-Log "=== TrID Automation Finished ===" "INFO"
exit $proc.ExitCode
