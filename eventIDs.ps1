<#
.SYNOPSIS
    All-in-One Event Export: Biometric/Personal Vault, OneDrive Conflicts, Security & System Logs
.DESCRIPTION
    Fixed version: Uses safe querying, null-handling, and dynamic provider detection.
    Run as Administrator to access Security logs.
#>

# # Admin Check (works with irm | iex)
# $IsAdmin = ([Security.Principal.WindowsPrincipal] `
#     [Security.Principal.WindowsIdentity]::GetCurrent()
# ).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

# if (-not $IsAdmin) {
#     Write-Host "⛔ This script must be run as Administrator." -ForegroundColor Red
#     Write-Host "Please reopen PowerShell as Administrator and try again." -ForegroundColor Yellow
#     return
# }

param(
    [int]$DaysBack = 30,
    [string]$OutputFolder = "C:\EventExports_$(Get-Date -Format 'yyyyMMdd_HHmm')"
)

# Admin Check (works with irm | iex)
$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "⛔ This script must be run as Administrator." -ForegroundColor Red
    Write-Host "Please reopen PowerShell as Administrator and try again." -ForegroundColor Yellow
    return
}

# === SETUP ===
if (!(Test-Path $OutputFolder)) { New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null }
$StartTime = (Get-Date).AddDays(-$DaysBack)
Write-Host "🚀 Starting All-in-One Event Export Script..." -ForegroundColor Cyan
Write-Host "📅 Time Range: $($StartTime.ToString('yyyy-MM-dd HH:mm')) to Now" -ForegroundColor Cyan
Write-Host "📁 Output Directory: $OutputFolder`n" -ForegroundColor Cyan

# === 1. BIOMETRIC & PERSONAL VAULT UNLOCK EVENTS ===
Write-Host "🔐 [1/7] Exporting Biometric & Personal Vault Unlock Events..." -ForegroundColor Yellow
$BioEvents = @()
$BioProviders = @("Goodix", "Windows Biometric Framework", "Microsoft-Windows-HelloForBusiness")
foreach ($prov in $BioProviders) {
    try { $BioEvents += Get-WinEvent -FilterHashTable @{LogName="Application"; ProviderName=$prov; StartTime=$StartTime} -ErrorAction SilentlyContinue } catch {}
}
$OperationalLogs = @("Microsoft-Windows-Winlogon/Operational", "Microsoft-Windows-Biometrics/Operational")
foreach ($log in $OperationalLogs) {
    try {
        if (Get-WinEvent -ListLog $log -ErrorAction SilentlyContinue) {
            $BioEvents += Get-WinEvent -FilterHashTable @{LogName=$log; StartTime=$StartTime; Level=1,2,3,4,5} -ErrorAction SilentlyContinue
        }
    } catch {}
}
if ($BioEvents.Count -gt 0) {
    $BioEvents | Sort-Object TimeCreated | Select-Object TimeCreated, Id, LevelDisplayName, LogName, ProviderName, Message |
    Export-Csv "$OutputFolder\Biometric_PersonalVault.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "  ✅ Exported $($BioEvents.Count) biometric/Personal Vault events" -ForegroundColor Green
} else { Write-Host "  ⚠️ No biometric events found." -ForegroundColor DarkYellow }

# === 2. ONEDRIVE SYNC CONFLICTS & ERROR CODES ===
Write-Host "`n☁️ [2/6] Exporting OneDrive Sync Conflicts & Error Codes..." -ForegroundColor Yellow

# 2a. Safe Query: Filter at log level, then match Provider/Message in memory (avoids "parameter incorrect")
Write-Host "  📝 Querying: Application Log + OneDrive Conflict/Error Keywords..."
$AppBase = Get-WinEvent -FilterHashTable @{LogName="Application"; Level=1,2,3,4; StartTime=$StartTime} -ErrorAction SilentlyContinue
$OneDriveConflicts = $AppBase | Where-Object {
    ($_.ProviderName -like "*OneDrive*" -or $_.Source -like "*OneDrive*") -and
    ($_.Message -match "(?i)conflict|sync.*fail|rename.*copy|0x800[74]|access.*denied|file.*in.*use")
} | Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, 
              @{N='ErrorCode';E={if($_.Message -match '0x[0-9A-F]+'){$Matches[0]}else{'N/A'}}},
              Message

if ($OneDriveConflicts.Count -gt 0) {
    $OneDriveConflicts | Export-Csv "$OutputFolder\OneDrive_SyncConflicts.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "    ✅ Sync Conflicts: $($OneDriveConflicts.Count) events" -ForegroundColor Green
} else { Write-Host "    ℹ️  No sync conflicts found." -ForegroundColor DarkYellow }

# 2b. Known HRESULT Error Codes via XPath
Write-Host "  📝 Querying: Known OneDrive HRESULT Error Codes..."
$OneDriveErrorCodes = @('0x80070005','0x8007018b','0x8004de96','0x80010007','0x80040c81','0x80071128','0x80071129','0x8004def5','0x8004def7', '0xc0000005', '0xe06d7363')
$XPathFilter = @"
<QueryList>
  <Query Id="0" Path="Application">
    <Select Path="Application">*[System[Provider[@Name='OneDrive'] and (Level=1 or Level=2 or Level=3)]] and *[EventData[Data and (Data='$($OneDriveErrorCodes -join "' or Data='")')]]</Select>
  </Query>
</QueryList>
"@
try {
    $OneDriveKnownErrors = Get-WinEvent -FilterXml $XPathFilter -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, LevelDisplayName, Message
    if ($OneDriveKnownErrors.Count -gt 0) {
        $OneDriveKnownErrors | Export-Csv "$OutputFolder\OneDrive_KnownErrors.csv" -NoTypeInformation -Encoding UTF8
        Write-Host "    ✅ Known Errors: $($OneDriveKnownErrors.Count) events" -ForegroundColor Green
    } else { Write-Host "    ℹ️  No structured HRESULT matches found." -ForegroundColor DarkYellow }
} catch { Write-Host "    ⚠️ XPath query skipped (provider not registered for structured filtering)." -ForegroundColor DarkYellow }

# 2c. Broad Conflict Keyword Search
Write-Host "  📝 Querying: Broad Conflict Keyword Search..."
$ConflictKeywords = "conflict|conflicting|renamed to resolve|copy of|version conflict|sync error|cannot sync|file name contains|invalid character"
$OneDriveBroad = $AppBase | Where-Object {
    ($_.ProviderName -like "*OneDrive*" -or $_.Source -like "*OneDrive*") -and ($_.Message -match "(?i)$ConflictKeywords")
} | Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message

if ($OneDriveBroad.Count -gt 0) {
    $OneDriveBroad | Export-Csv "$OutputFolder\OneDrive_ConflictSearch.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "    ✅ Broad Search: $($OneDriveBroad.Count) events" -ForegroundColor Green
} else { Write-Host "    ℹ️  No broad conflict matches found." -ForegroundColor DarkYellow }

# 2d. General OneDrive Events (App + Operational)
Write-Host "  📝 Querying: All OneDrive Events (App + Operational)..."
$OneDriveAll = @()
$OneDriveAll += $AppBase | Where-Object { $_.ProviderName -like "*OneDrive*" -or $_.Source -like "*OneDrive*" }
try {
    if (Get-WinEvent -ListLog "Microsoft-OneDrive/Operational" -ErrorAction SilentlyContinue) {
        $OneDriveAll += Get-WinEvent -FilterHashTable @{LogName="Microsoft-OneDrive/Operational"; Level=2,3,4,5; StartTime=$StartTime} -ErrorAction SilentlyContinue
    }
} catch {}
if ($OneDriveAll.Count -gt 0) {
    $OneDriveAll | Sort-Object TimeCreated | Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message, MachineName |
    Export-Csv "$OutputFolder\OneDrive_AllEvents.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "    ✅ All OneDrive: $($OneDriveAll.Count) events" -ForegroundColor Green
} else { Write-Host "    ℹ️  No general OneDrive events found." -ForegroundColor DarkYellow }

# === 3. SECURITY LOG EVENTS ===
Write-Host "`n🛡️ [3/6] Exporting Security Log Events..." -ForegroundColor Yellow
try {
    $SecurityEvents = Get-WinEvent -FilterHashTable @{LogName="Security"; ID=4625,4674,4720,4722,4738,4732,1102,5157,4624,4648,4800,4672; StartTime=$StartTime} -Oldest -ErrorAction SilentlyContinue
    if ($SecurityEvents.Count -gt 0) {
        $SecurityEvents | Export-Csv "$OutputFolder\Security_Events.csv" -NoTypeInformation -Encoding UTF8
        Write-Host "  ✅ Security Events: $($SecurityEvents.Count) exported" -ForegroundColor Green
    } else { Write-Host "  ℹ️  No Security events matched in timeframe." -ForegroundColor DarkYellow }
} catch { Write-Host "  ⛔ Failed: Ensure PowerShell is running as Administrator." -ForegroundColor Red }

# === 4. SYSTEM LOG EVENTS ===
Write-Host "`n💻 [4/6] Exporting System Log Events..." -ForegroundColor Yellow
try {
    $SystemEvents = Get-WinEvent -FilterHashTable @{LogName="System"; ID=3,7030,10000,100001,20001,20002,20003,24756,24577,24579; StartTime=$StartTime} -ErrorAction SilentlyContinue
    if ($SystemEvents.Count -gt 0) {
        $SystemEvents | Export-Csv "$OutputFolder\System_Events.csv" -NoTypeInformation -Encoding UTF8
        Write-Host "  ✅ System Events: $($SystemEvents.Count) exported" -ForegroundColor Green
    } else { Write-Host "  ℹ️  No System events matched in timeframe (normal if drivers/services were stable)." -ForegroundColor DarkYellow }
} catch { Write-Host "  ⚠️ System log query failed: $_" -ForegroundColor DarkYellow }

# === 5. Application LOG EVENTS ===
Write-Host "`n💻 [5/6] Exporting Application & System Log Events..." -ForegroundColor Yellow
try {
    # 1. Application Log (App crashes, .NET errors, OneDrive)
    $AppEvents = Get-WinEvent -FilterHashTable @{LogName="Application"; ID=1000,1001,1002,1026,1005; StartTime=$StartTime} -ErrorAction SilentlyContinue

    # 2. System Log (DCOM, Schannel, Network, Service events)
    $SysEvents = Get-WinEvent -FilterHashTable @{LogName="System"; ID=1000,1001,10001,6100,6101,36887; StartTime=$StartTime} -ErrorAction SilentlyContinue

    # Combine & sort chronologically
    $AllEvents = @($AppEvents) + @($SysEvents) | Sort-Object TimeCreated

    if ($AllEvents.Count -gt 0) {
        # Optional: Filter specifically for OneDrive-related crashes
        $OneDriveEvents = $AllEvents | Where-Object {
            $_.Message -match 'OneDrive\.exe|FileSyncClient\.dll|Microsoft\.SharePoint\.exe|onedrive'
        }

        # Export full set
        $AllEvents | Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, LogName, Message | 
            Export-Csv "$OutputFolder\AppSys_Events.csv" -NoTypeInformation -Encoding UTF8

        # Export OneDrive-specific subset (if any)
        if ($OneDriveEvents.Count -gt 0) {
            $OneDriveEvents | Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message | 
                Export-Csv "$OutputFolder\OneDrive_Crashes.csv" -NoTypeInformation -Encoding UTF8
            Write-Host "  ✅ Total Events: $($AllEvents.Count) | 🎯 OneDrive Matches: $($OneDriveEvents.Count)" -ForegroundColor Green
        } else {
            Write-Host "  ✅ Total Events: $($AllEvents.Count) exported (No OneDrive-specific crashes found)" -ForegroundColor Green
        }
    } else {
        Write-Host "  ℹ️  No matching events found in timeframe." -ForegroundColor DarkYellow
    }
} catch {
    Write-Host "  ⚠️ Log query failed: $_" -ForegroundColor DarkYellow
}

# === 6. INTERNAL ONEDRIVE LOGS ===
Write-Host "`n📂 [6/6] Exporting Internal OneDrive Consumer Logs..." -ForegroundColor Yellow

Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Write-Host "ODC Stopped..." -ForegroundColor red

$ConsumerLogRoot = Join-Path $env:LOCALAPPDATA "Microsoft\OneDrive\logs"
$TargetFiles = @()

# 1️⃣ Strictly target CONSUMER/Personal logs
if (Test-Path (Join-Path $ConsumerLogRoot "Personal")) {
    $TargetFiles += Get-ChildItem -Path (Join-Path $ConsumerLogRoot "Personal") -Filter "*.odl" -File -ErrorAction SilentlyContinue
} else {
    # Fallback: scan root logs but EXPLICITLY exclude Business folders
    $TargetFiles += Get-ChildItem -Path $ConsumerLogRoot -Filter "*.odl" -Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -notmatch '\\Business\d+\\' }
}

$ParsedLogs = @()
# 🔍 Regex to extract structured fields from .odl lines
$LogRegex = [regex]'^\s*(?<Timestamp>\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d{3})\s+\[PID:(?<PID>\d+)\s+TID:(?<TID>\d+)\]\s+(?:\[[^\]]+\]\s+)?(?:Level:\s*)?(?<Level>[A-Za-z]+)\s+(?<Message>.+)$'
# ⚡ Fast pre-filter to avoid parsing millions of clean lines
$ErrorFilter = "(?i)\b(ERROR|FAIL|CONFLICT|0x80|EXCEPTION|ACCESS DENIED|SYNC FAILED)\b"

foreach ($file in $TargetFiles) {
    if ($file.Length -gt 100MB) { continue } # Skip bloated logs to prevent memory spikes
    try {
        $Matches = Select-String -Path $file.FullName -Pattern $ErrorFilter -ErrorAction SilentlyContinue
        if ($Matches) {
            foreach ($m in $Matches) {
                $line = $m.Line.Trim()
                $rg = $LogRegex.Match($line)
                
                $ParsedLogs += if ($rg.Success) {
                    [PSCustomObject]@{
                        SourceFile = $file.Name
                        Timestamp  = [datetime]$rg.Groups['Timestamp'].Value
                        PID        = $rg.Groups['PID'].Value
                        TID        = $rg.Groups['TID'].Value
                        Level      = $rg.Groups['Level'].Value.ToUpper()
                        Message    = $rg.Groups['Message'].Value.Trim()
                        ExportTime = Get-Date
                    }
                } else {
                    # Fallback for malformed lines that still contain error keywords
                    [PSCustomObject]@{
                        SourceFile = $file.Name
                        Timestamp  = "Unknown"
                        PID        = "N/A"
                        TID        = "N/A"
                        Level      = "UNPARSED"
                        Message    = $line
                        ExportTime = Get-Date
                    }
                }
            }
        }
    } catch {
        # Silently skip locked/inaccessible files (normal when OneDrive is running)
    }
}

if ($ParsedLogs.Count -gt 0) {
    $ParsedLogs | Sort-Object Timestamp | Export-Csv "$OutputFolder\OneDrive_Consumer_Errors.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "  ✅ Parsed $($ParsedLogs.Count) consumer error lines from .odl logs" -ForegroundColor Green
} else {
    Write-Host "  ℹ️  No consumer OneDrive errors found. (Personal account may not be active/syncing)" -ForegroundColor DarkYellow
}

# === 7. SUMMARY ===
Write-Host "`n🎉 Export Complete!" -ForegroundColor Green
Write-Host "📁 Files saved to: $OutputFolder" -ForegroundColor Cyan
Write-Host "📊 File Summary:"
Get-ChildItem $OutputFolder -Filter *.csv | ForEach-Object { 
    Write-Host "  • $($_.Name) ($([math]::Round($_.Length/1KB, 2)) KB | $(Get-Date $_.LastWriteTime -Format 'yyyy-MM-dd HH:mm'))" 
}
