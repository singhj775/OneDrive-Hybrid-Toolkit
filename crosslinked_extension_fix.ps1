<#
.SYNOPSIS
    Fully silent TrID automation. Checks for system Python first.
    If missing, installs embedded Python, fixes BOM crash, runs trid.py.
#>
[CmdletBinding()]
param(
    [string]$TargetDir = "C:\Users\singh\OneDrive\Documents\test",
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

# ==================== 1. FIND OR INSTALL PYTHON ====================
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
$UseEmbedded = $false

if ($PythonExe -and -not $Force) {
    Write-Log "System Python found: $PythonExe" "INFO"
} else {
    $UseEmbedded = $true
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

            # CRITICAL BOM FIX: Overwrite .pth with clean, BOM-free content
            $PthPath = Join-Path $PythonDir "python312._pth"
            $CleanPth = "python312.zip`n.`n#import site"
            [System.IO.File]::WriteAllText($PthPath, $CleanPth, (New-Object System.Text.UTF8Encoding $false))
            Write-Log "python312._pth configured (BOM removed, site enabled)." "INFO"

            # Verify Python actually boots
            $test = & $PythonExe -c "import encodings; print('BOOT_OK')" 2>&1
            if ($test -notmatch "BOOT_OK") { throw "Embedded Python failed verification: $test" }
            Write-Log "Embedded Python verified successfully." "SUCCESS"
        } catch {
            Write-Log "Embedded Python setup failed: $_" "ERROR"
            exit 1
        }
    } else {
        Write-Log "Embedded Python already present." "INFO"
    }
}

# ==================== 2. DOWNLOAD TRID.PY & DEFINITIONS ====================
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

# ==================== 3. VALIDATE & EXECUTE ====================
if (-not (Test-Path $TargetDir)) { Write-Log "ERROR: Target directory not found: $TargetDir" "ERROR"; exit 1 }

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
$stdout = $proc.StandardOutput.ReadToEnd()
$stderr = $proc.StandardError.ReadToEnd()
$proc.WaitForExit()

if ($stdout) { Write-Log "Python Output: $($stdout.Trim())" "INFO" }
if ($stderr) { Write-Log "Python Error: $($stderr.Trim())" "WARN" }

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