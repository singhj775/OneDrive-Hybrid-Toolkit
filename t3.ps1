function Invoke-OneDriveDeepHealthCheck {
    <#
    .SYNOPSIS
        Comprehensive OneDrive Deep Health Check, Audit, and Remediation Tool.
    .DESCRIPTION
        Audits OneDrive installation, process, accounts, proxy, policies, FOD, network, 
        tokens, and event logs. Use -Fix to automatically remediate blocking policies, 
        run gpupdate, and restart the OneDrive process.
    .PARAMETER Fix
        Enables automatic remediation of blocking DWORD policies, runs gpupdate, and restarts OneDrive.
    #>
    [CmdletBinding()]
    param(
        [switch]$Fix,
        [string]$LogDirectory = $env:TEMP
    )

    # ==========================================================
    # 1. INITIALIZATION & LOGGING
    # ==========================================================
    if (-not (Test-Path $LogDirectory)) { New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null }
    $script:LogFile = Join-Path $LogDirectory ("OneDrive_DeepHealth_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

    function Write-ODLog {
        param([string]$Message, [string]$Level = "INFO")
        $Line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
        
        switch ($Level) {
            "ERROR"   { Write-Host $Line -ForegroundColor Red }
            "WARNING" { Write-Host $Line -ForegroundColor Yellow }
            "SUCCESS" { Write-Host $Line -ForegroundColor Green }
            "HEADER"  { Write-Host "`n$Line" -ForegroundColor Cyan; Add-Content -Path $script:LogFile -Value "`n$Line" }
            default   { Write-Host $Line -ForegroundColor Gray }
        }
        Add-Content -Path $script:LogFile -Value $Line -ErrorAction SilentlyContinue
    }

    $script:ChangesMade = $false
    $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    Write-ODLog "===========================================================" "HEADER"
    Write-ODLog "OneDrive Deep Health Check & Remediation" "HEADER"
    Write-ODLog "Mode: $(if($Fix){'REMEDIATION (FIX)'}else{'AUDIT ONLY'}) | Admin Rights: $IsAdmin" "HEADER"
    Write-ODLog "Log File: $script:LogFile" "HEADER"
    Write-ODLog "===========================================================" "HEADER"

    if ($Fix -and -not $IsAdmin) {
        Write-ODLog "CRITICAL: -Fix switch used without Administrator privileges. HKLM changes will fail." "ERROR"
    }

    # ==========================================================
    # 2. SYSTEM & ENVIRONMENT INFO
    # ==========================================================
    Write-ODLog "=== System Environment ===" "HEADER"
    try {
        $ComputerSystem = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        Write-ODLog "Computer Name : $($ComputerSystem.Name)"
        Write-ODLog "Domain Joined : $($ComputerSystem.PartOfDomain)"
    } catch { Write-ODLog "Failed to determine system info: $_" "ERROR" }

    # ==========================================================
    # 3. INSTALLATION & PROCESS CHECK
    # ==========================================================
    Write-ODLog "=== OneDrive Installation & Process ===" "HEADER"
    $OneDriveExe = Join-Path $env:LOCALAPPDATA "Microsoft\OneDrive\OneDrive.exe"

    if (Test-Path $OneDriveExe) {
        $Version = (Get-Item $OneDriveExe).VersionInfo.ProductVersion
        Write-ODLog "Path    : $OneDriveExe"
        Write-ODLog "Version : $Version" "SUCCESS"
    } else {
        Write-ODLog "OneDrive.exe not found at default path." "ERROR"
    }

    $Process = Get-Process OneDrive -ErrorAction SilentlyContinue
    if ($Process) {
        Write-ODLog "Process : Running (PID: $($Process.Id -join ', '))" "SUCCESS"
    } else {
        Write-ODLog "Process : NOT running." "WARNING"
    }

    # ==========================================================
    # 4. ACCOUNTS & SYNC ROOTS
    # ==========================================================
    Write-ODLog "=== Accounts & Sync Roots ===" "HEADER"
    $AccountRoot = "HKCU:\Software\Microsoft\OneDrive\Accounts"
    if (Test-Path $AccountRoot) {
        Get-ChildItem $AccountRoot -ErrorAction SilentlyContinue | ForEach-Object {
            $Account = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            Write-ODLog "Account Type : $($_.PSChildName)"
            foreach ($Field in @("UserEmail", "UserFolder", "ServiceEndpointUri", "AADUserId")) {
                if ($Account.$Field) { Write-ODLog "  $Field : $($Account.$Field)" }
            }
        }
    } else { Write-ODLog "No OneDrive account registry found." "WARNING" }

    $SyncRootPath = "HKCU:\Software\SyncEngines\Providers\OneDrive"
    if (Test-Path $SyncRootPath) {
        $Providers = Get-ChildItem -Path $SyncRootPath -ErrorAction SilentlyContinue
        Write-ODLog "Active Sync Roots: $($Providers.Count)"
    }

# ==========================================================
# 5. DEEP POLICY AUDIT & REMEDIATION (Policy + Consumer Sync)
# ==========================================================
Write-ODLog "=== Deep Policy Audit ===" "HEADER"

# Include both enterprise policy hives and consumer sync hives
$PolicyPaths = @(
    "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive",
    "HKCU:\SOFTWARE\Policies\Microsoft\OneDrive",
    "HKCU:\Software\Microsoft\OneDrive",
    "HKCU:\Software\SyncEngines\Providers\OneDrive"
)

# Policy-based checks (only apply to Policies\Microsoft\OneDrive hives)
$PolicyChecks = @(
    @{ Name = "DisableFileSync";              Expected = 0; Type = "DWord"; AutoFix = $true;  Desc = "Legacy: Prevent OneDrive from running" },
    @{ Name = "DisableFileSyncNGSC";          Expected = 0; Type = "DWord"; AutoFix = $true;  Desc = "Modern: Prevent the usage of OneDrive" },
    @{ Name = "DisablePersonalSync";          Expected = 0; Type = "DWord"; AutoFix = $true;  Desc = "Disable personal OneDrive accounts" },
    @{ Name = "BlockExternalSync";            Expected = 0; Type = "DWord"; AutoFix = $true;  Desc = "Block external sync providers" },
    @{ Name = "FilesOnDemandEnabled";         Expected = 1; Type = "DWord"; AutoFix = $true;  Desc = "Files On-Demand feature toggle" },
    @{ Name = "UseOneDriveFilesOnDemand";     Expected = 1; Type = "DWord"; AutoFix = $true;  Desc = "Use Files On-Demand" },
    @{ Name = "KFMSilentOptIn";               Expected = 1; Type = "DWord"; AutoFix = $true;  Desc = "KFM: Silent Opt-in Master Toggle" }
)

foreach ($Path in $PolicyPaths) {
    Write-ODLog "Scanning: $Path"

    if (-not (Test-Path $Path)) {
        Write-ODLog "Path not present."
        continue
    }

    # Handle consumer sync hive separately
    if ($Path -like "*SyncEngines*") {
        Write-ODLog "Consumer Sync Hive detected."
        Get-ChildItem $Path | ForEach-Object {
            $RegProps = Get-ItemProperty $_.PsPath
            Write-ODLog "Account GUID: $($_.PSChildName)"
            Write-ODLog "UserFolder: $($RegProps.UserFolder)"
            Write-ODLog "IsOfficeSyncIntegrationEnabled: $($RegProps.IsOfficeSyncIntegrationEnabled)"
        }
        continue
    }

    # Otherwise, treat as policy hive
    $RegProps = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue

    foreach ($Check in $PolicyChecks) {
        $Val = $RegProps.($Check.Name)
        if ($null -eq $Val) { continue }

        $isBlocking = $false
        if ($Check.Type -eq "DWord" -and $Val -ne $Check.Expected) { $isBlocking = $true }

        if ($isBlocking) {
            Write-ODLog "BLOCKER: $($Check.Desc) ($($Check.Name)) = $Val" "WARNING"
            if ($Fix -and $Check.AutoFix) {
                if (-not $IsAdmin -and $Path -like "HKLM:*") {
                    Write-ODLog "Cannot fix HKLM without Admin rights." "ERROR"
                    continue
                }
                try {
                    Set-ItemProperty -Path $Path -Name $Check.Name -Value $Check.Expected -Type $Check.Type -Force -ErrorAction Stop
                    Write-ODLog "FIXED: Set $($Check.Name) to $($Check.Expected)" "SUCCESS"
                    $script:ChangesMade = $true
                } catch {
                    Write-ODLog "Failed to fix $($Check.Name): $_" "ERROR"
                }
            }
        } else {
            Write-ODLog "$($Check.Name) : $Val (OK)" "SUCCESS"
        }
    }
}


    # ==========================================================
    # 6. FILES ON-DEMAND & PERSONAL VAULT
    # ==========================================================
    Write-ODLog "=== Files On-Demand & Personal Vault ===" "HEADER"
    $UserODPath = Join-Path $env:USERPROFILE "OneDrive"
    if (Test-Path $UserODPath) {
        $folderItem = Get-Item -Path $UserODPath -Force -ErrorAction SilentlyContinue
        $isCloud = ($folderItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq [IO.FileAttributes]::ReparsePoint
        Write-ODLog "OneDrive Folder FOD Status (Reparse Point): $isCloud"
    }

    $PVPath = "HKCU:\Software\Microsoft\OneDrive\PersonalVault"
    if (Test-Path $PVPath) { Write-ODLog "Personal Vault State: $((Get-ItemProperty $PVPath -ErrorAction SilentlyContinue).State)" }

    # ==========================================================
    # 7. NETWORK & PROXY AUDIT
    # ==========================================================
    Write-ODLog "=== Network & Proxy ===" "HEADER"
    Write-ODLog "WinHTTP Proxy Configuration:"
    try {
        $Proxy = netsh winhttp show proxy
        foreach ($Line in $Proxy) { if ($Line.Trim()) { Write-ODLog "  $Line" } }
    } catch { Write-ODLog "Failed to get WinHTTP proxy: $_" "ERROR" }

    Write-ODLog "Endpoint Connectivity (TCP 443):"
    $TestHosts = @("login.microsoftonline.com", "onedrive.live.com", "config.edge.skype.com")
    foreach ($HostToTest in $TestHosts) {
        try {
            $Result = Test-NetConnection -ComputerName $HostToTest -Port 443 -WarningAction SilentlyContinue -ErrorAction Stop
            $Status = if ($Result.TcpTestSucceeded) { "SUCCESS" } else { "ERROR" }
            Write-ODLog "  $HostToTest`: $($Result.TcpTestSucceeded)" $Status
        } catch { Write-ODLog "  $HostToTest`: Failed" "ERROR" }
    }

    # ==========================================================
    # 8. WAM / AAD TOKEN AUDIT
    # ==========================================================
    Write-ODLog "=== WAM/AAD Token Cache ===" "HEADER"
    $WamPaths = @("HKCU:\Software\Microsoft\Windows\CurrentVersion\AAD\TokenBroker\Cache", "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AAD\TokenBroker\Cache")
    foreach ($WPath in $WamPaths) {
        if (Test-Path $WPath) {
            $Tokens = Get-ChildItem -Path $WPath -ErrorAction SilentlyContinue
            Write-ODLog "Cache at $WPath contains $($Tokens.Count) entries."
        }
    }

    # ==========================================================
    # 9. EVENT LOG COLLECTION
    # ==========================================================
    Write-ODLog "=== Recent Event Logs ===" "HEADER"
    try {
        $AppEvents = Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddDays(-1)} -ErrorAction SilentlyContinue | Where-Object { $_.ProviderName -match 'OneDrive' } | Select-Object -First 5
        if ($AppEvents) { Write-ODLog "Application Log (Crashes/Errors):"
            foreach ($Evt in $AppEvents) { Write-ODLog "  [ID:$($Evt.Id)] $($Evt.Message.Substring(0, [Math]::Min(100, $Evt.Message.Length)))..." "ERROR" }
        }
    } catch {}

    try {
        $OpEvents = Get-WinEvent -LogName 'Microsoft-Windows-OneDrive/Operational' -MaxEvents 10 -ErrorAction Stop
        Write-ODLog "Operational Log (Sync Activity):"
        foreach ($Evt in $OpEvents) {
            $Lvl = switch($Evt.Level) { 2 {"ERROR"} 3 {"WARNING"} 4 {"INFO"} default {"VERBOSE"} }
            Write-ODLog "  [$Lvl] ID:$($Evt.Id) - $($Evt.Message.Substring(0, [Math]::Min(80, $Evt.Message.Length)))..."
        }
    } catch { Write-ODLog "Could not retrieve Operational logs." "WARNING" }

    # ==========================================================
    # 10. GPRESULT ANALYSIS
    # ==========================================================
    Write-ODLog "=== GPResult Summary ===" "HEADER"
    try {
        $GPTemp = Join-Path $env:TEMP "gpresult_od.txt"
        gpresult /R > $GPTemp 2>&1
        Get-Content $GPTemp | Select-Object -First 30 | ForEach-Object { Write-ODLog $_ }
        Remove-Item $GPTemp -Force -ErrorAction SilentlyContinue
    } catch { Write-ODLog "GPResult failed: $_" "ERROR" }

    # ==========================================================
    # 11. AUTOMATIC REMEDIATION EXECUTION
    # ==========================================================
    if ($Fix) {
        Write-ODLog "=== Automatic Remediation Execution ===" "HEADER"
        if ($script:ChangesMade) {
            Write-ODLog "Applying Group Policy Updates..."
            try { $null = gpupdate /force; Write-ODLog "GPUpdate completed." "SUCCESS" } catch { Write-ODLog "GPUpdate failed: $_" "ERROR" }

            Write-ODLog "Restarting OneDrive process..."
            try {
                Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue
                $proc = Get-Process -Name OneDrive -ErrorAction SilentlyContinue
                if ($proc) { $proc | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue }
                
                if (Test-Path $OneDriveExe) { Start-Process $OneDriveExe; Write-ODLog "OneDrive restarted successfully." "SUCCESS" }
                else { Write-ODLog "OneDrive.exe not found." "ERROR" }
            } catch { Write-ODLog "Failed to restart OneDrive: $_" "ERROR" }
        } else {
            Write-ODLog "No auto-fixable blocking policies were found. Skipping GPUpdate and Restart." "INFO"
        }
    }

    # ==========================================================
    # 12. FINAL SUMMARY
    # ==========================================================
    Write-ODLog "===========================================================" "HEADER"
    Write-ODLog "Health Check Complete. Log saved to: $script:LogFile" "HEADER"
    Write-ODLog "===========================================================" "HEADER"

    return $script:LogFile
}

# ==========================================================
# INTERACTIVE EXECUTION WRAPPER
# ==========================================================
function Start-OneDriveInteractiveHealthCheck {
    <#
    .SYNOPSIS
        Runs the Audit, then interactively asks the user if they want to run the Fix mode.
    #>
    
    # 1. Run Audit Mode
    Write-Host "`n[STEP 1] Running OneDrive Deep Health Check (AUDIT MODE)..." -ForegroundColor Cyan
    $LogFile = Invoke-OneDriveDeepHealthCheck

    # 2. Prompt for Fix Mode
    Write-Host "`n-------------------------------------------------------------------------" -ForegroundColor DarkGray
    $response = Read-Host "Would you like to apply automatic fixes for blocking policies and restart OneDrive? (Y/N)"
    Write-Host "-------------------------------------------------------------------------`n" -ForegroundColor DarkGray

    if ($response -eq 'Y' -or $response -eq 'y') {
        # Check for Admin rights before attempting fix
        $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        if (-not $IsAdmin) {
            Write-Host "[!] Administrator privileges are required to apply fixes." -ForegroundColor Red
            $elevate = Read-Host "Restart script as Administrator now? (Y/N)"
            if ($elevate -eq 'Y' -or $elevate -eq 'y') {
                $scriptPath = $MyInvocation.ScriptName
                if (-not $scriptPath) { $scriptPath = $PSCommandPath }
                
                if ($scriptPath) {
                    Start-Process powershell.exe -Verb RunAs -ArgumentList "-File `"$scriptPath`" -AutoFix"
                    exit
                } else {
                    Write-Host "Could not determine script path to elevate. Please run PowerShell as Admin and try again." -ForegroundColor Red
                }
            }
        } else {
            Write-Host "[STEP 2] Running OneDrive Deep Health Check (FIX MODE)..." -ForegroundColor Cyan
            Invoke-OneDriveDeepHealthCheck -Fix
        }
    } else {
        Write-Host "Skipping Fix Mode. Review the log file at: $LogFile" -ForegroundColor Yellow
    }
}

# Run the interactive wrapper
Start-OneDriveInteractiveHealthCheck