#requires -RunAsAdministrator
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
Write-Host "🔐 [1/6] Exporting Biometric & Personal Vault Unlock Events..." -ForegroundColor Yellow
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
$OneDriveErrorCodes = @('0x80070005','0x8007018b','0x8004de96','0x80010007','0x80040c81','0x80071128','0x80071129','0x8004def5','0x8004def7')
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
    $SystemEvents = Get-WinEvent -FilterHashTable @{LogName="System"; ID=7030,10000,100001,20001,20002,20003,24756,24577,24579; StartTime=$StartTime} -ErrorAction SilentlyContinue
    if ($SystemEvents.Count -gt 0) {
        $SystemEvents | Export-Csv "$OutputFolder\System_Events.csv" -NoTypeInformation -Encoding UTF8
        Write-Host "  ✅ System Events: $($SystemEvents.Count) exported" -ForegroundColor Green
    } else { Write-Host "  ℹ️  No System events matched in timeframe (normal if drivers/services were stable)." -ForegroundColor DarkYellow }
} catch { Write-Host "  ⚠️ System log query failed: $_" -ForegroundColor DarkYellow }

# === 5. INTERNAL ONEDRIVE LOGS ===
Write-Host "`n📂 [5/6] Exporting Internal OneDrive Logs (if available)..." -ForegroundColor Yellow
$InternalPaths = @("$env:LOCALAPPDATA\Microsoft\OneDrive\logs\Personal\*.log", "$env:LOCALAPPDATA\Microsoft\OneDrive\logs\Business1\*.log")
$InternalLogs = @()
foreach ($p in $InternalPaths) {
    if (Test-Path $p) {
        try {
            $InternalLogs += Get-Content $p -ErrorAction SilentlyContinue | Select-String -Pattern "(?i)error|conflict|fail|0x800" |
                ForEach-Object { [PSCustomObject]@{ SourceFile = Split-Path $p -Leaf; Timestamp = (Get-Date); RawLine = $_.Line } }
        } catch {}
    }
}
if ($InternalLogs.Count -gt 0) {
    $InternalLogs | Export-Csv "$OutputFolder\OneDrive_InternalLogs.csv" -NoTypeInformation -Encoding UTF8
    Write-Host "  ✅ Internal Logs: $($InternalLogs.Count) lines exported" -ForegroundColor Green
} else { Write-Host "  ℹ️  No internal OneDrive logs found." -ForegroundColor DarkYellow }

# === 6. SUMMARY ===
Write-Host "`n🎉 Export Complete!" -ForegroundColor Green
Write-Host "📁 Files saved to: $OutputFolder" -ForegroundColor Cyan
Write-Host "📊 File Summary:"
Get-ChildItem $OutputFolder -Filter *.csv | ForEach-Object { 
    Write-Host "  • $($_.Name) ($([math]::Round($_.Length/1KB, 2)) KB | $(Get-Date $_.LastWriteTime -Format 'yyyy-MM-dd HH:mm'))" 
}
