param(

    [int]$DaysBack = 30,

    [string]$OutputRoot = "$env:USERPROFILE\Desktop\OD_Svchost_Delete_Forensics",

    [string]$OneDriveLogRoot = "$env:LOCALAPPDATA\Microsoft\OneDrive\logs",

    [string]$TargetPathRegex = "OneDrive|SkyDrive|Documents|Desktop|Pictures"

)


$ErrorActionPreference = "SilentlyContinue"


$RunStamp = Get-Date -Format "yyyyMMdd_HHmmss"

$OutDir = Join-Path $OutputRoot "Collection_$RunStamp"

$Dirs = @(

    $OutDir,

    (Join-Path $OutDir "Events"),

    (Join-Path $OutDir "OneDrive"),

    (Join-Path $OutDir "Services"),

    (Join-Path $OutDir "Drivers"),

    (Join-Path $OutDir "Timeline"),

    (Join-Path $OutDir "Summary")

)


foreach ($d in $Dirs) {

    New-Item -ItemType Directory -Path $d -Force | Out-Null

}


$StartTime = (Get-Date).AddDays(-1 * $DaysBack)

$EndTime = Get-Date


Start-Transcript -Path (Join-Path $OutDir "Transcript.txt") -Force | Out-Null


function Write-Section {

    param([string]$Text)

    Write-Host ""

    Write-Host "============================================================" -ForegroundColor Cyan

    Write-Host $Text -ForegroundColor Cyan

    Write-Host "============================================================" -ForegroundColor Cyan

}


function Export-SafeCsv {

    param(

        [object[]]$Data,

        [string]$Path

    )

    if ($null -eq $Data) { $Data = @() }

    $Data | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8

}


function Get-EventDataMap {

    param([System.Diagnostics.Eventing.Reader.EventRecord]$Event)


    $map = [ordered]@{}

    try {

        [xml]$xml = $Event.ToXml()

        foreach ($d in $xml.Event.EventData.Data) {

            $name = $d.Name

            if ([string]::IsNullOrWhiteSpace($name)) {

                $name = "Data"

            }

            $map[$name] = $d.'#text'

        }

    } catch {}

    return $map

}


function Convert-HexPidToInt {

    param([string]$PidValue)


    if ([string]::IsNullOrWhiteSpace($PidValue)) { return $null }


    try {

        if ($PidValue -match "^0x") {

            return [convert]::ToInt32($PidValue, 16)

        } else {

            return [int]$PidValue

        }

    } catch {

        return $null

    }

}


function Extract-DateFromLine {

    param([string]$Line, [datetime]$Fallback)


    $patterns = @(

        "\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z",

        "\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z",

        "\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+",

        "\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}"

    )


    foreach ($p in $patterns) {

        $m = [regex]::Match($Line, $p)

        if ($m.Success) {

            try {

                return [datetime]::Parse($m.Value).ToLocalTime()

            } catch {

                try { return [datetime]::Parse($m.Value) } catch {}

            }

        }

    }


    return $Fallback

}


function Extract-ProcessFromODLLine {

    param([string]$Line)


    $process = $null


    if ($Line -match "Process that initiated the delete:\s*([^\.\,\;\s]+\.exe)") {

        $process = $Matches[1]

    } elseif ($Line -match "initiated the delete:\s*([^\.\,\;\s]+\.exe)") {

        $process = $Matches[1]

    } elseif ($Line -match "ProcessName[=:]\s*([^\.\,\;\s]+\.exe)") {

        $process = $Matches[1]

    } elseif ($Line -match "svchost\.exe") {

        $process = "svchost.exe"

    }


    return $process

}


function Get-MessagePreview {

    param([string]$Message, [int]$Length = 350)


    if ([string]::IsNullOrWhiteSpace($Message)) { return "" }

    $oneLine = ($Message -replace "`r", " " -replace "`n", " ")

    if ($oneLine.Length -gt $Length) {

        return $oneLine.Substring(0, $Length)

    }

    return $oneLine

}


# ============================================================

# 1. Basic machine and OneDrive information

# ============================================================


Write-Section "Collecting basic machine and OneDrive data"


$BasicInfo = [PSCustomObject]@{

    ComputerName      = $env:COMPUTERNAME

    UserName          = $env:USERNAME

    StartTime         = $StartTime

    EndTime           = $EndTime

    DaysBack          = $DaysBack

    OneDriveLogRoot   = $OneDriveLogRoot

    TargetPathRegex   = $TargetPathRegex

    IsAdmin           = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    OS                = (Get-CimInstance Win32_OperatingSystem).Caption

    OSVersion         = (Get-CimInstance Win32_OperatingSystem).Version

    BuildNumber       = (Get-CimInstance Win32_OperatingSystem).BuildNumber

    LastBootUpTime    = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime

}


$BasicInfo | Format-List | Out-File (Join-Path $OutDir "BasicInfo.txt") -Encoding UTF8


Get-Process OneDrive -ErrorAction SilentlyContinue |

    Select-Object Name, Id, StartTime, Path, Company, ProductVersion, FileVersion |

    Export-Csv (Join-Path $OutDir "OneDrive\OneDrive_ProcessInfo.csv") -NoTypeInformation -Encoding UTF8


$OneDriveExeCandidates = @(

    "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe",

    "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe",

    "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe"

)


$OneDriveBinaryInfo = foreach ($exe in $OneDriveExeCandidates) {

    if (Test-Path $exe) {

        $f = Get-Item $exe

        [PSCustomObject]@{

            Path         = $f.FullName

            FileVersion  = $f.VersionInfo.FileVersion

            ProductVer   = $f.VersionInfo.ProductVersion

            Company      = $f.VersionInfo.CompanyName

            ModifiedTime = $f.LastWriteTime

        }

    }

}


Export-SafeCsv $OneDriveBinaryInfo (Join-Path $OutDir "OneDrive\OneDrive_Binaries.csv")


# ============================================================

# 2. Current svchost -> service mapping

# ============================================================


Write-Section "Collecting current svchost/service mapping"


$Services = Get-CimInstance Win32_Service |

    Select-Object Name, DisplayName, State, StartMode, ProcessId, PathName


Export-SafeCsv $Services (Join-Path $OutDir "Services\All_Services_With_ProcessId.csv")


$ServiceDllRows = foreach ($svc in $Services) {

    $serviceDll = $null

    try {

        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)\Parameters"

        $serviceDll = (Get-ItemProperty -Path $regPath -Name ServiceDll -ErrorAction SilentlyContinue).ServiceDll

    } catch {}


    [PSCustomObject]@{

        Name        = $svc.Name

        DisplayName = $svc.DisplayName

        State       = $svc.State

        StartMode   = $svc.StartMode

        ProcessId   = $svc.ProcessId

        PathName    = $svc.PathName

        ServiceDll  = $serviceDll

    }

}


Export-SafeCsv $ServiceDllRows (Join-Path $OutDir "Services\Services_With_ServiceDll.csv")


$SvchostProcesses = Get-Process svchost -ErrorAction SilentlyContinue |

    Select-Object Id, ProcessName, StartTime, Path


Export-SafeCsv $SvchostProcesses (Join-Path $OutDir "Services\Svchost_Processes.csv")


$SvchostHosted = foreach ($p in $SvchostProcesses) {

    $hosted = $ServiceDllRows | Where-Object { $_.ProcessId -eq $p.Id }

    foreach ($h in $hosted) {

        [PSCustomObject]@{

            SvchostPid      = $p.Id

            SvchostStart    = $p.StartTime

            ServiceName     = $h.Name

            ServiceDisplay  = $h.DisplayName

            ServiceState    = $h.State

            ServiceStartMode= $h.StartMode

            ServiceDll      = $h.ServiceDll

            ServicePath     = $h.PathName

        }

    }

}


Export-SafeCsv $SvchostHosted (Join-Path $OutDir "Services\Svchost_Hosted_Services_With_DLLs.csv")


$InterestingRegex = "OneDrive|Cloud|CldFlt|Filter|Sync|Notification|Storage|StorSvc|Search|WSearch|Defender|Sense|WdFilter|Profile|ProfSvc|SysMain|Workstation|LanmanWorkstation"

$InterestingServices = $ServiceDllRows | Where-Object {

    $_.Name -match $InterestingRegex -or

    $_.DisplayName -match $InterestingRegex -or

    $_.ServiceDll -match $InterestingRegex

}


Export-SafeCsv $InterestingServices (Join-Path $OutDir "Services\Interesting_Services.csv")


# ============================================================

# 3. Filter driver and Cloud Files driver state

# ============================================================


Write-Section "Collecting filter driver and Cloud Files state"


cmd /c fltmc > (Join-Path $OutDir "Drivers\fltmc.txt") 2>&1

cmd /c "sc qc cldflt" > (Join-Path $OutDir "Drivers\sc_qc_cldflt.txt") 2>&1

cmd /c "sc queryex cldflt" > (Join-Path $OutDir "Drivers\sc_queryex_cldflt.txt") 2>&1


# ============================================================

# 4. Windows Security deletion events

# ============================================================


Write-Section "Collecting historical Security deletion events"


$SecurityEventsRaw = Get-WinEvent -FilterHashtable @{

    LogName   = "Security"

    Id        = 4663,4660,4659,4688

    StartTime = $StartTime

    EndTime   = $EndTime

} -ErrorAction SilentlyContinue


$SecurityRows = foreach ($ev in $SecurityEventsRaw) {

    $m = Get-EventDataMap $ev


    $procIdRaw = $m["ProcessId"]

    $procIdInt = Convert-HexPidToInt $procIdRaw

    $processName = $m["ProcessName"]

    $objectName = $m["ObjectName"]

    $accessMask = $m["AccessMask"]

    $accessList = $m["AccessList"]

    $subjectUser = $m["SubjectUserName"]

    $subjectDomain = $m["SubjectDomainName"]

    $newProcessName = $m["NewProcessName"]

    $commandLine = $m["CommandLine"]


    $isDeleteSignal = $false


    if ($ev.Id -in 4659,4660) {

        $isDeleteSignal = $true

    }


    if ($ev.Id -eq 4663) {

        if ($accessMask -in @("0x10000","0x10080")) { $isDeleteSignal = $true }

        if ($accessList -match "DELETE|%%1537|%%4417") { $isDeleteSignal = $true }

        if ($ev.Message -match "DELETE|Delete") { $isDeleteSignal = $true }

    }


    if ($objectName -and ($objectName -notmatch $TargetPathRegex)) {

        # Keep all svchost/process rows, but mark relevance lower later.

    }


    [PSCustomObject]@{

        Source          = "Security"

        TimeCreated     = $ev.TimeCreated

        EventId         = $ev.Id

        Provider        = $ev.ProviderName

        SubjectUser     = "$subjectDomain\$subjectUser"

        ObjectName      = $objectName

        ProcessName     = $processName

        ProcessIdRaw    = $procIdRaw

        ProcessIdInt    = $procIdInt

        NewProcessName  = $newProcessName

        CommandLine     = $commandLine

        AccessMask      = $accessMask

        AccessList      = $accessList

        IsDeleteSignal  = $isDeleteSignal

        IsTargetPath    = if ($objectName -match $TargetPathRegex) { $true } else { $false }

        MessagePreview  = Get-MessagePreview $ev.Message

    }

}


Export-SafeCsv $SecurityRows (Join-Path $OutDir "Events\Security_File_Delete_And_Process_Events.csv")


$SecurityDeleteRows = $SecurityRows | Where-Object {

    $_.IsDeleteSignal -eq $true -and

    (

        $_.IsTargetPath -eq $true -or

        $_.ProcessName -match "OneDrive.exe|svchost.exe" -or

        $_.MessagePreview -match "OneDrive|SkyDrive|svchost.exe"

    )

}


Export-SafeCsv $SecurityDeleteRows (Join-Path $OutDir "Events\Security_Delete_Relevant.csv")


# ============================================================

# 5. System, CloudFiles, FilterManager and Notifications logs

# ============================================================


Write-Section "Collecting System / CloudFiles / FilterManager / Notifications logs"


function Export-EventLogGeneric {

    param(

        [string]$LogName,

        [string]$OutFile,

        [string]$ProviderRegex = "",

        [string]$MessageRegex = "",

        [int[]]$Ids = @()

    )


    try {

        if (-not ((wevtutil el) -contains $LogName)) {

            return

        }


        $filter = @{

            LogName   = $LogName

            StartTime = $StartTime

            EndTime   = $EndTime

        }


        if ($Ids.Count -gt 0) {

            $filter["Id"] = $Ids

        }


        $events = Get-WinEvent -FilterHashtable $filter -ErrorAction SilentlyContinue


        if ($ProviderRegex -ne "") {

            $events = $events | Where-Object { $_.ProviderName -match $ProviderRegex }

        }


        if ($MessageRegex -ne "") {

            $events = $events | Where-Object { $_.Message -match $MessageRegex }

        }


        $rows = $events | Select-Object TimeCreated, Id, ProviderName, LevelDisplayName,

            @{Name="MessagePreview";Expression={Get-MessagePreview $_.Message 700}}


        Export-SafeCsv $rows $OutFile

    } catch {}

}


Export-EventLogGeneric `

    -LogName "System" `

    -OutFile (Join-Path $OutDir "Events\System_Filter_Service_Events.csv") `

    -ProviderRegex "Service Control Manager|Microsoft-Windows-FilterManager|Microsoft-Windows-Ntfs|Microsoft-Windows-Kernel-PnP|Microsoft-Windows-CloudFiles" `

    -MessageRegex "svchost|OneDrive|Cloud|CldFlt|filter|delete|remove|service|driver|sync|placeholder|mount|disconnect|unregister|start|stop"


Export-EventLogGeneric `

    -LogName "Application" `

    -OutFile (Join-Path $OutDir "Events\Application_OneDrive_Related.csv") `

    -MessageRegex "OneDrive|svchost|delete|Cloud|CldFlt|sync|crash|fault"


Export-EventLogGeneric `

    -LogName "Microsoft-Windows-CloudFiles/Operational" `

    -OutFile (Join-Path $OutDir "Events\CloudFiles_Operational.csv") `

    -MessageRegex "OneDrive|delete|remove|placeholder|hydrate|dehydrate|sync|root|disconnect|unregister|fail|error|warning"


Export-EventLogGeneric `

    -LogName "Microsoft-Windows-FilterManager/Operational" `

    -OutFile (Join-Path $OutDir "Events\FilterManager_Operational.csv") `

    -MessageRegex "CldFlt|OneDrive|filter|detach|attach|disconnect|fail|error|warning"


Export-EventLogGeneric `

    -LogName "Microsoft-Windows-Notifications/Operational" `

    -OutFile (Join-Path $OutDir "Events\Notifications_OneDrive.csv") `

    -MessageRegex "OneDrive|delete|deleted|remove|removed"


Export-EventLogGeneric `

    -LogName "Setup" `

    -OutFile (Join-Path $OutDir "Events\Setup_Update_Install.csv") `

    -MessageRegex "OneDrive|update|install|Windows Update|driver|Cloud|CldFlt"


# ============================================================

# 6. Sysmon if present

# ============================================================


Write-Section "Collecting Sysmon data if present"


$SysmonLog = "Microsoft-Windows-Sysmon/Operational"


if ((wevtutil el) -contains $SysmonLog) {

    $SysmonEvents = Get-WinEvent -FilterHashtable @{

        LogName   = $SysmonLog

        StartTime = $StartTime

        EndTime   = $EndTime

    } -ErrorAction SilentlyContinue | Where-Object {

        $_.Message -match "OneDrive|svchost.exe|Delete|FileDelete|CldFlt|Cloud"

    }


    $SysmonRows = $SysmonEvents | Select-Object TimeCreated, Id, ProviderName, LevelDisplayName,

        @{Name="MessagePreview";Expression={Get-MessagePreview $_.Message 1000}}


    Export-SafeCsv $SysmonRows (Join-Path $OutDir "Events\Sysmon_Relevant.csv")

} else {

    "Sysmon log not found on this machine." | Out-File (Join-Path $OutDir "Events\Sysmon_Not_Found.txt") -Encoding UTF8

}


# ============================================================

# 7. OneDrive ODL deletion signal scan

# ============================================================


Write-Section "Scanning OneDrive ODL logs for deletion signals"


$OdlSignalRegex = "DeleteValidator|MatchingPersistedDeleteNotificationExists|Process that initiated the delete|Found matching delete notification|Found deleted file in sweep|SweepDriveContents|PerformFSIDLookupForDeletionsDCIWorkItem|OnDeleteCompletion|RemoveFolder|Recycle|setLocalMassDeleteDetectedTime|LocalMassDelete|told to remove file|DriveChange::MarkDeleted|isLocalChange=False|local:False|OnNotificationReceived|SetServerRefreshNeeded|CleanupMountPoint|DisconnectFromSyncRoot|UnregisterSyncRoot|placeholder|CldFlt|svchost.exe"


$OdlRows = @()


if (Test-Path $OneDriveLogRoot) {

    $LogFiles = Get-ChildItem -Path $OneDriveLogRoot -Recurse -File -ErrorAction SilentlyContinue |

        Where-Object {

            $_.Extension -match "\.odl|\.txt|\.log|\.odlsent|\.aodl" -or

            $_.Name -match "SyncDiagnostics|SyncEngine|Telemetry|Business|Personal"

        }


    $LogInventory = $LogFiles | Select-Object FullName, Name, Length, LastWriteTime

    Export-SafeCsv $LogInventory (Join-Path $OutDir "OneDrive\OneDrive_Log_File_Inventory.csv")


    foreach ($file in $LogFiles) {

        try {

            $matches = Select-String -Path $file.FullName -Pattern $OdlSignalRegex -SimpleMatch:$false -ErrorAction SilentlyContinue

            foreach ($match in $matches) {

                $line = $match.Line

                $lineTime = Extract-DateFromLine -Line $line -Fallback $file.LastWriteTime

                $proc = Extract-ProcessFromODLLine -Line $line


                $classification = "ODL_Delete_Signal"

                if ($line -match "Process that initiated the delete") { $classification = "ODL_Process_Initiated_Delete" }

                elseif ($line -match "Found deleted file in sweep") { $classification = "ODL_Deleted_File_In_Sweep" }

                elseif ($line -match "setLocalMassDeleteDetectedTime|LocalMassDelete") { $classification = "ODL_Local_Mass_Delete" }

                elseif ($line -match "told to remove file") { $classification = "ODL_Service_Delete_Synced_Locally" }

                elseif ($line -match "CleanupMountPoint|DisconnectFromSyncRoot|UnregisterSyncRoot") { $classification = "ODL_SyncRoot_Filter_Change" }


                $OdlRows += [PSCustomObject]@{

                    Source         = "OneDrive_ODL"

                    TimeCreated    = $lineTime

                    FileName       = $file.Name

                    FullName       = $file.FullName

                    LineNumber     = $match.LineNumber

                    Classification = $classification

                    ProcessName    = $proc

                    ContainsSvchost= if ($line -match "svchost.exe") { $true } else { $false }

                    MessagePreview = Get-MessagePreview $line 1000

                }

            }

        } catch {}

    }

} else {

    "OneDrive log root not found: $OneDriveLogRoot" | Out-File (Join-Path $OutDir "OneDrive\OneDrive_LogRoot_NotFound.txt") -Encoding UTF8

}


Export-SafeCsv $OdlRows (Join-Path $OutDir "OneDrive\ODL_Delete_Signals.csv")


# ============================================================

# 8. Build merged timeline

# ============================================================


Write-Section "Building merged timeline"


$Timeline = @()


foreach ($r in $OdlRows) {

    $Timeline += [PSCustomObject]@{

        TimeCreated    = $r.TimeCreated

        Source         = $r.Source

        EventId        = ""

        Classification = $r.Classification

        ProcessName    = $r.ProcessName

        ProcessId      = ""

        ObjectName     = ""

        ServiceName    = ""

        ServiceDisplay = ""

        Confidence     = if ($r.ContainsSvchost) { "High ODL signal: svchost mentioned" } else { "ODL signal" }

        Details        = $r.MessagePreview

        SourceFile     = $r.FullName

    }

}


foreach ($r in $SecurityDeleteRows) {

    $matchedServices = @()


    if ($r.ProcessName -match "svchost.exe" -and $r.ProcessIdInt) {

        $matchedServices = $SvchostHosted | Where-Object { $_.SvchostPid -eq $r.ProcessIdInt }

    }


    if ($matchedServices.Count -gt 0) {

        foreach ($s in $matchedServices) {

            $Timeline += [PSCustomObject]@{

                TimeCreated    = $r.TimeCreated

                Source         = "Security"

                EventId        = $r.EventId

                Classification = "Security_Delete_Event"

                ProcessName    = $r.ProcessName

                ProcessId      = $r.ProcessIdInt

                ObjectName     = $r.ObjectName

                ServiceName    = $s.ServiceName

                ServiceDisplay = $s.ServiceDisplay

                Confidence     = "Possible only: current PID maps to service; verify reboot/PID reuse"

                Details        = $r.MessagePreview

                SourceFile     = "Security Event Log"

            }

        }

    } else {

        $Timeline += [PSCustomObject]@{

            TimeCreated    = $r.TimeCreated

            Source         = "Security"

            EventId        = $r.EventId

            Classification = "Security_Delete_Event"

            ProcessName    = $r.ProcessName

            ProcessId      = $r.ProcessIdInt

            ObjectName     = $r.ObjectName

            ServiceName    = ""

            ServiceDisplay = ""

            Confidence     = if ($r.ProcessName -match "svchost.exe") { "svchost delete seen, service not mapped from retained logs" } else { "Process identified" }

            Details        = $r.MessagePreview

            SourceFile     = "Security Event Log"

        }

    }

}


# Add generic event logs to timeline

$GenericEventFiles = @(

    "System_Filter_Service_Events.csv",

    "Application_OneDrive_Related.csv",

    "CloudFiles_Operational.csv",

    "FilterManager_Operational.csv",

    "Notifications_OneDrive.csv",

    "Setup_Update_Install.csv",

    "Sysmon_Relevant.csv"

)


foreach ($gef in $GenericEventFiles) {

    $path = Join-Path $OutDir "Events\$gef"

    if (Test-Path $path) {

        try {

            $items = Import-Csv $path

            foreach ($i in $items) {

                $Timeline += [PSCustomObject]@{

                    TimeCreated    = $i.TimeCreated

                    Source         = ($gef -replace ".csv","")

                    EventId        = $i.Id

                    Classification = "Supporting_Event"

                    ProcessName    = ""

                    ProcessId      = ""

                    ObjectName     = ""

                    ServiceName    = ""

                    ServiceDisplay = ""

                    Confidence     = "Supporting timeline signal"

                    Details        = $i.MessagePreview

                    SourceFile     = $gef

                }

            }

        } catch {}

    }

}


$TimelineSorted = $Timeline | Sort-Object {[datetime]$_.TimeCreated}


Export-SafeCsv $TimelineSorted (Join-Path $OutDir "Timeline\Merged_Timeline.csv")


# ============================================================

# 9. Suspect service summary

# ============================================================


Write-Section "Creating suspect service summary"


$SuspectRows = @()


$SvchostSecurityRows = $SecurityDeleteRows | Where-Object { $_.ProcessName -match "svchost.exe" }


foreach ($r in $SvchostSecurityRows) {

    $servicesAtCurrentPid = @()

    if ($r.ProcessIdInt) {

        $servicesAtCurrentPid = $SvchostHosted | Where-Object { $_.SvchostPid -eq $r.ProcessIdInt }

    }


    if ($servicesAtCurrentPid.Count -gt 0) {

        foreach ($s in $servicesAtCurrentPid) {

            $SuspectRows += [PSCustomObject]@{

                Reason          = "Security delete event shows svchost.exe and current PID maps to hosted service"

                TimeCreated     = $r.TimeCreated

                ProcessId       = $r.ProcessIdInt

                ServiceName     = $s.ServiceName

                ServiceDisplay  = $s.ServiceDisplay

                ServiceDll      = $s.ServiceDll

                ObjectName      = $r.ObjectName

                Confidence      = "Medium - validate PID reuse and reboot timing"

                NextValidation  = "Check LastBootUpTime, svchost StartTime, System Service Control Manager events, Sysmon process creation"

            }

        }

    } else {

        $SuspectRows += [PSCustomObject]@{

            Reason          = "Security delete event shows svchost.exe but service could not be mapped"

            TimeCreated     = $r.TimeCreated

            ProcessId       = $r.ProcessIdInt

            ServiceName     = ""

            ServiceDisplay  = ""

            ServiceDll      = ""

            ObjectName      = $r.ObjectName

            Confidence      = "Low/Unknown - missing retained service/PID evidence"

            NextValidation  = "Need Sysmon Event ID 1/23/26, Process Monitor boot logging, or Windows event telemetry from incident time"

        }

    }

}


# Add ODL svchost signals

$OdlSvchostRows = $OdlRows | Where-Object { $_.ContainsSvchost -eq $true }


foreach ($r in $OdlSvchostRows) {

    $SuspectRows += [PSCustomObject]@{

        Reason          = "OneDrive ODL line mentions svchost.exe as delete initiator"

        TimeCreated     = $r.TimeCreated

        ProcessId       = ""

        ServiceName     = ""

        ServiceDisplay  = ""

        ServiceDll      = ""

      n  = "Correlate same timestamp with Security 4663/Sysmon/CloudFiles/FilterManager/System events"

    }

}


Export-SafeCsv $SuspectRows (Join-Path $OutDir "Summary\Suspect_Service_Summary.csv")


# ============================================================

# 10. Generate human-readable report

# ============================================================


Write-Section "Generating final report"


$SecurityDeleteCount = ($SecurityDeleteRows | Measure-Object).Count

$OdlSignalCount = ($OdlRows | Measure-Object).Count

$OdlSvchostCount = ($OdlSvchostRows | Measure-Object).Count

$MappedSuspects = ($SuspectRows | Where-Object { $_.ServiceName -ne "" } | Measure-Object).Count


$Report = @"

OneDrive svchost.exe Delete Investigation Report

Generated: $(Get-Date)

Computer: $env:COMPUTERNAME

User: $env:USERNAME

Analysis Window: $StartTime to $EndTime

DaysBack: $DaysBack


SUMMARY

-------

Security deletion rows found:

$SecurityDeleteCount


OneDrive ODL deletion signal rows found:

$OdlSignalCount


ODL rows mentioning svchost.exe:

$OdlSvchostCount


Suspect services mapped from current svchost PID:

$MappedSuspects


IMPORTANT INTERPRETATION

------------------------

1. If Security 4663/4660/4659 events were not enabled before the deletion,

   Windows may not have retained process-level delete evidence.

2. If the deletion happened before last reboot, current svchost PID mapping

   may not match the historical svchost instance due to PID reuse.

3. If ODL shows "Process that initiated the delete: svchost.exe" but there is

   no Security/Sysmon PID match, the conclusion should be:

   "svchost.exe involved; exact hosted service not proven from retained logs."

4. For exact future proof, enable Sysmon/FileDelete or ProcMon boot logging

   before next repro.


MOST IMPORTANT OUTPUTS

----------------------

1. Timeline\Merged_Timeline.csv

2. Summary\Suspect_Service_Summary.csv

3. Events\Security_Delete_Relevant.csv

4. OneDrive\ODL_Delete_Signals.csv

5. Services\Svchost_Hosted_Services_With_DLLs.csv

6. Services\Interesting_Services.csv

7. Drivers\fltmc.txt

8. Events\CloudFiles_Operational.csv

9. Events\FilterManager_Operational.csv

10. Events\System_Filter_Service_Events.csv


RECOMMENDED REVIEW ORDER

------------------------

1. Open Summary\Suspect_Service_Summary.csv

2. Open Timeline\Merged_Timeline.csv

3. Filter timeline around the ODL DeleteValidator timestamp

4. Check if Security event shows ProcessName = svchost.exe

5. Check ProcessIdInt and compare with Services\Svchost_Hosted_Services_With_DLLs.csv

6. Check same timestamp in CloudFiles/FilterManager/System events

7. If exact service is missing, mark as "inconclusive due to missing historical PID/service telemetry"


"@


$Report | Out-File (Join-Path $OutDir "README_ANALYSIS_GUIDE.txt") -Encoding UTF8


Stop-Transcript | Out-Null


Write-Host ""

Write-Host "DONE" -ForegroundColor Green

Write-Host "Output folder:" -ForegroundColor Cyan

Write-Host $OutDir -ForegroundColor Yellow

Write-Host ""

Write-Host "Open first:" -ForegroundColor Cyan

Write-Host "1. Summary\Suspect_Service_Summary.csv"

Write-Host "2. Timeline\Merged_Timeline.csv"

Write-Host "3. README_ANALYSIS_GUIDE.txt"
 