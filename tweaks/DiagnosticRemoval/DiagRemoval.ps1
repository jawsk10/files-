#Requires -RunAsAdministrator
<#
.SYNOPSIS
    OS-Level Latency Amputation Script
    Goes beyond registry disables -- deletes services, removes binaries,
    kills ETW sessions, purges scheduled tasks, and cleans artifacts.

.DESCRIPTION
    Targets:
    Phase 1: Service Deletion (not just disable -- full sc delete)
    Phase 2: Binary Removal (executables and service DLLs)
    Phase 3: Scheduled Task Purge
    Phase 4: ETW Autologger Session Kill
    Phase 5: Per-User Service Template Neutering
    Phase 6: Compatibility Engine Cleanup
    Phase 7: Artifact Purge

.NOTES
    - Run from an elevated PowerShell prompt or via the .bat launcher
    - Reboot required after execution
    - Does NOT touch registry-only settings (assumed handled by NTLite/batch)
#>

param(
    [switch]$Force
)

$ErrorActionPreference = "Continue"
Set-StrictMode -Version Latest

# ============================================================================
#  Logging
# ============================================================================

$LogFile = "$PSScriptRoot\amputation_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$BackupDir = "$PSScriptRoot\amputation_backup"
New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    Write-Host $entry -ForegroundColor $(switch ($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        "OK"    { "Green" }
        "PHASE" { "Cyan" }
        default { "White" }
    })
    Add-Content -Path $LogFile -Value $entry
}

# ============================================================================
#  Helpers
# ============================================================================

function Take-Ownership {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    $null = cmd /c "takeown /f `"$Path`" >nul 2>&1"
    $null = cmd /c "icacls `"$Path`" /grant Administrators:F >nul 2>&1"
    return $true
}

function Remove-Binary {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path $Path)) {
        Write-Log "  [skip] $Label -- not found: $Path"
        return
    }
    $fileName = Split-Path $Path -Leaf
    $parentDir = (Split-Path $Path -Parent) | Split-Path -Leaf
    $backupName = "${parentDir}_${fileName}"

    Take-Ownership $Path | Out-Null
    Copy-Item $Path "$BackupDir\$backupName" -Force -ErrorAction SilentlyContinue

    try {
        # Kill any process using this binary
        $procName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        Get-Process -Name $procName -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Log "  Killing $($_.Name) (PID $($_.Id))"
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 300
        }
        Remove-Item $Path -Force -ErrorAction Stop
        Write-Log "  [del] $Label -- $Path" "OK"
    } catch {
        # Schedule for reboot deletion
        $null = cmd /c "del /f /q `"$Path`" >nul 2>&1"
        if (Test-Path $Path) {
            # Still locked -- use MoveFileEx via PendingFileRename
            $pendingKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
            $pending = @()
            $existingProps = Get-ItemProperty -Path $pendingKey -ErrorAction SilentlyContinue
            if ($existingProps -and ($existingProps.PSObject.Properties.Name -contains "PendingFileRenameOperations")) {
                $pending = @($existingProps.PendingFileRenameOperations)
            }
            $pending += "\??\$Path"
            $pending += ""
            Set-ItemProperty -Path $pendingKey -Name "PendingFileRenameOperations" -Value $pending -Type MultiString -Force
            Write-Log "  [reboot] $Label -- scheduled for deletion: $Path" "WARN"
        } else {
            Write-Log "  [del] $Label -- $Path (fallback)" "OK"
        }
    }
}

function Delete-Service {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.Status -ne "Stopped") {
            Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
        }
        $null = cmd /c "sc.exe delete `"$Name`" >nul 2>&1"
        if ($LASTEXITCODE -eq 0) {
            Write-Log "  [del] Service: $Name" "OK"
        } else {
            Write-Log "  [fail] Service: $Name -- sc delete returned $LASTEXITCODE" "WARN"
        }
    } else {
        Write-Log "  [skip] Service: $Name -- not found"
    }
}

function Remove-ScheduledTaskSafe {
    param([string]$TaskPath)
    $null = cmd /c "schtasks /Change /TN `"$TaskPath`" /Disable >nul 2>&1"
    $null = cmd /c "schtasks /Delete /TN `"$TaskPath`" /F >nul 2>&1"
    if ($LASTEXITCODE -eq 0) {
        Write-Log "  [del] Task: $TaskPath" "OK"
    } else {
        Write-Log "  [skip] Task: $TaskPath -- not found"
    }
}

# ============================================================================
#  Confirm
# ============================================================================

Write-Log "=== OS-Level Latency Amputation Starting ===" "PHASE"
Write-Log "Backup dir: $BackupDir"
Write-Log "Log: $LogFile"

if (-not $Force) {
    Write-Host ""
    Write-Host "This will DELETE services, binaries, scheduled tasks, and ETW sessions." -ForegroundColor Red
    Write-Host "Registry-only settings are NOT touched (assumed handled by NTLite/batch)." -ForegroundColor Yellow
    Write-Host ""
    $confirm = Read-Host "Type 'AMPUTATE' to proceed"
    if ($confirm -ne "AMPUTATE") {
        Write-Log "Aborted by user." "WARN"
        exit 0
    }
}

# ============================================================================
#  Phase 1: Service Deletion
# ============================================================================

Write-Log "" 
Write-Log "=== Phase 1: Service Deletion ===" "PHASE"
Write-Log "Deleting services entirely (not just disabling)..."

$servicesToDelete = @(
    # Diagnostic Policy Service
    "DPS",
    # Diagnostic Service Host
    "WdiServiceHost",
    # Diagnostic System Host  
    "WdiSystemHost",
    # Program Compatibility Assistant
    "PcaSvc",
    # Connected Devices Platform
    "CDPSvc",
    # Device Association Broker
    "DeviceAssociationBrokerSvc",
    # System Guard Runtime Monitor
    "SgrmBroker",
    # SgrmAgent
    "SgrmAgent",
    # Diagnostic Execution Service
    "diagsvc",
    # Diagnostic Hub Standard Collector
    "diagnosticshub.standardcollector.service",
    # Downloaded Maps Manager (periodic update checks)
    "MapsBroker",
    # Geolocation Service (periodic location polling)
    "lfsvc",
    # Windows Problem Reporting (WER companion)
    "wercplsupport",
    # Touch Keyboard and Handwriting (if desktop only)
    "TabletInputService",
    # Distributed Link Tracking (domain feature)
    "TrkWks",
    # IP Helper (IPv6 transition -- if pure IPv4)
    "iphlpsvc",
    # Phone Service
    "PhoneSvc",
    # Retail Demo
    "RetailDemo"
)

foreach ($svc in $servicesToDelete) {
    Delete-Service $svc
}

# Per-user service templates -- these auto-spawn per user session
$perUserTemplates = @(
    "CDPUserSvc",
    "DeviceAssociationBrokerSvc",
    "PimIndexMaintenanceSvc",
    "UnistoreSvc",
    "UserDataSvc",
    "WpnUserService",
    "DevicesFlowUserSvc",
    "PrintWorkflowUserSvc",
    "MessagingService",
    "OneSyncSvc",
    "CaptureService",
    "cbdhsvc"
)

Write-Log ""
Write-Log "Deleting per-user service templates..."

foreach ($template in $perUserTemplates) {
    # Delete the template itself
    Delete-Service $template

    # Find and delete all spawned instances (CDPUserSvc_1a2b3c etc)
    $instances = Get-Service -Name "${template}_*" -ErrorAction SilentlyContinue
    foreach ($inst in $instances) {
        Delete-Service $inst.Name
    }
}

# ============================================================================
#  Phase 2: Binary Removal
# ============================================================================

Write-Log ""
Write-Log "=== Phase 2: Binary Removal ===" "PHASE"
Write-Log "Removing executables and service DLLs..."

$binariesToRemove = @(
    # Diagnostic hosts
    @{ Path = "$env:SystemRoot\System32\DiagSvcs\DiagnosticsHub.StandardCollector.Service.exe"; Label = "DiagHub Collector" },
    @{ Path = "$env:SystemRoot\System32\DiagSvcs\DiagnosticsHub.StandardCollector.Proxy.dll"; Label = "DiagHub Proxy" },
    @{ Path = "$env:SystemRoot\System32\diaghost.exe"; Label = "Diagnostic Host" },
    @{ Path = "$env:SystemRoot\System32\dps.dll"; Label = "DPS Service DLL" },

    # PCA
    @{ Path = "$env:SystemRoot\System32\pcasvc.dll"; Label = "PCA Service DLL" },
    @{ Path = "$env:SystemRoot\System32\pcaui.exe"; Label = "PCA UI" },
    @{ Path = "$env:SystemRoot\System32\pcaui.dll"; Label = "PCA UI DLL" },

    # SgrmBroker
    @{ Path = "$env:SystemRoot\System32\SgrmBroker.exe"; Label = "SgrmBroker" },
    @{ Path = "$env:SystemRoot\System32\SgrmAgent.exe"; Label = "SgrmAgent" },

    # Connected Devices Platform
    @{ Path = "$env:SystemRoot\System32\CDPSvc.dll"; Label = "CDP Service DLL" },

    # Device Association
    @{ Path = "$env:SystemRoot\System32\DasHost.exe"; Label = "Device Association Host" },

    # Maps Broker
    @{ Path = "$env:SystemRoot\System32\MapsBroker.dll"; Label = "Maps Broker DLL" },

    # Problem Reports (WER companion UI)
    @{ Path = "$env:SystemRoot\System32\wercplsupport.dll"; Label = "WER CPL Support" },

    # Compatibility Appraiser (telemetry + compat scanning)
    @{ Path = "$env:SystemRoot\System32\CompatTelRunner.exe"; Label = "Compat Telemetry Runner" },
    @{ Path = "$env:SystemRoot\System32\devicecensus.exe"; Label = "Device Census" },

    # Diagnostic Tracking (if service already gone, remove binary too)
    @{ Path = "$env:SystemRoot\System32\utc.dll"; Label = "DiagTrack UTC DLL" },

    # Inventory collectors
    @{ Path = "$env:SystemRoot\System32\InventoryAgent.dll"; Label = "Inventory Agent" }
)

foreach ($item in $binariesToRemove) {
    Remove-Binary -Path $item.Path -Label $item.Label
}

# ============================================================================
#  Phase 3: Scheduled Task Purge
# ============================================================================

Write-Log ""
Write-Log "=== Phase 3: Scheduled Task Purge ===" "PHASE"
Write-Log "Removing latency-relevant scheduled tasks..."

$tasksToRemove = @(
    # Diagnostics
    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticResolver",
    "\Microsoft\Windows\MemoryDiagnostic\ProcessMemoryDiagnosticEvents",
    "\Microsoft\Windows\MemoryDiagnostic\RunFullMemoryDiagnostic",
    "\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem",

    # Application Experience / PCA
    "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
    "\Microsoft\Windows\Application Experience\PcaPatchDbTask",
    "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
    "\Microsoft\Windows\Application Experience\StartupAppTask",
    "\Microsoft\Windows\Application Experience\AitAgent",

    # Customer Experience / Telemetry
    "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
    "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
    "\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask",

    # Autochk
    "\Microsoft\Windows\Autochk\Proxy",

    # Device Census
    "\Microsoft\Windows\Device Information\Device",
    "\Microsoft\Windows\Device Information\Device User",

    # Cloud Experience
    "\Microsoft\Windows\CloudExperienceHost\CreateObjectTask",

    # Feedback
    "\Microsoft\Windows\Feedback\Siuf\DmClient",
    "\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload",

    # File History (periodic backup scan)
    "\Microsoft\Windows\FileHistory\File History (maintenance mode)",

    # Flighting (Insider telemetry)
    "\Microsoft\Windows\Flighting\FeatureConfig\ReconcileFeatures",
    "\Microsoft\Windows\Flighting\FeatureConfig\UsageDataFlushing",
    "\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReporting",
    "\Microsoft\Windows\Flighting\OneSettings\RefreshCache",

    # Location
    "\Microsoft\Windows\Location\Notifications",
    "\Microsoft\Windows\Location\WindowsActionDialog",

    # Maps
    "\Microsoft\Windows\Maps\MapsToastTask",
    "\Microsoft\Windows\Maps\MapsUpdateTask",

    # Maintenance
    "\Microsoft\Windows\Diagnosis\Scheduled",
    "\Microsoft\Windows\Diagnosis\RecommendedTroubleshootingScanner",

    # PI (Inventory)
    "\Microsoft\Windows\PI\Sqm-Tasks",

    # Push Notifications
    "\Microsoft\Windows\PushToInstall\LoginCheck",
    "\Microsoft\Windows\PushToInstall\Registration",

    # Setup / post-OOBE
    "\Microsoft\Windows\Setup\SetupCleanupTask",
    "\Microsoft\Windows\Setup\SnappyOOBECleanup",

    # System Guard
    "\Microsoft\Windows\System Guard\VerifiedAccess_AtLogin",
    "\Microsoft\Windows\System Guard\VerifiedAccess_Periodic",

    # Trace
    "\Microsoft\Windows\Wininet\CacheTask",

    # Work Folders (domain)
    "\Microsoft\Windows\Work Folders\Work Folders Logon Synchronization",
    "\Microsoft\Windows\Work Folders\Work Folders Maintenance Work",

    # Workplace Join (domain)
    "\Microsoft\Windows\Workplace Join\Automatic-Device-Join",
    "\Microsoft\Windows\Workplace Join\Recovery-Check",

    # Windows Defender (if already stripped)
    "\Microsoft\Windows\Windows Defender\Windows Defender Cache Maintenance",
    "\Microsoft\Windows\Windows Defender\Windows Defender Cleanup",
    "\Microsoft\Windows\Windows Defender\Windows Defender Scheduled Scan",
    "\Microsoft\Windows\Windows Defender\Windows Defender Verification",

    # Clip (cloud clipboard sync)
    "\Microsoft\Windows\Clip\License Validation",

    # Speech
    "\Microsoft\Windows\Speech\SpeechModelDownloadTask",
    "\Microsoft\Windows\Speech\HeardActivityLookback",

    # International
    "\Microsoft\Windows\International\Synchronize Language Settings",

    # Management
    "\Microsoft\Windows\Management\Provisioning\Cellular",
    "\Microsoft\Windows\Management\Provisioning\Logon"
)

foreach ($task in $tasksToRemove) {
    Remove-ScheduledTaskSafe $task
}

# Also sweep for any remaining telemetry/diagnostic tasks dynamically
Write-Log ""
Write-Log "Sweeping for remaining diagnostic/telemetry tasks..."

$sweepPatterns = @(
    "Compat", "Ceip", "Telemetry", "DiagTrack", "Consolidator",
    "DeviceCensus", "Sqm", "Feedback", "Flighting"
)

$taskListRaw = cmd /c "schtasks /Query /FO CSV /NH 2>nul"
if ($taskListRaw) {
    $taskListRaw | ForEach-Object {
        $fields = $_ -split '","'
        if ($fields.Count -ge 1) {
            $taskFullName = $fields[0].Trim('"')
            foreach ($pattern in $sweepPatterns) {
                if ($taskFullName -match $pattern -and $taskFullName -notin $tasksToRemove) {
                    Remove-ScheduledTaskSafe $taskFullName
                    break
                }
            }
        }
    }
}

# ============================================================================
#  Phase 4: ETW Autologger Session Kill
# ============================================================================

Write-Log ""
Write-Log "=== Phase 4: ETW Autologger Session Kill ===" "PHASE"
Write-Log "Disabling non-essential autologger sessions..."

# These are sessions we DISABLE (set Start=0) and also remove their provider
# registrations to prevent buffer allocation at boot.

$autologgersToKill = @(
    "AppModel",
    "CloudExperienceHostOobe",
    "DiagLog",
    "Diagtrack-Listener",
    "LwtNetLog",
    "Microsoft-Windows-Setup",
    "NtfsLog",
    "RadioMgr",
    "ReadyBoot",
    "SetupPlatformTel",
    "SpoolerLogger",
    "SQMLogger",
    "UBPM",
    "WdiContextLog",
    "WiFiSession",
    "WiFiDriverIHVSession",
    "WiFiDriverIHVSessionRepro",
    "Circular Kernel Context Logger",
    "FaceRecoTel",
    "FaceUnlock",
    "MeasuredBoot",
    "RdrLog",
    "Tpm",
    "TileStore",
    "WFP-IPsec Diagnostics",
    "WindowsUpdate-Diagnostics",
    "AutoLogger-Diagtrack-Listener",
    "DefenderApiLogger",
    "DefenderAuditLogger"
)

$autoLoggerRoot = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger"

foreach ($session in $autologgersToKill) {
    $sessionPath = "$autoLoggerRoot\$session"
    if (Test-Path $sessionPath) {
        # Disable the session
        Set-ItemProperty -Path $sessionPath -Name "Start" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        
        # Remove all provider sub-keys (these cause buffer alloc even with Start=0 on some builds)
        $providers = Get-ChildItem $sessionPath -ErrorAction SilentlyContinue
        $providerCount = 0
        foreach ($provider in $providers) {
            Remove-Item $provider.PSPath -Recurse -Force -ErrorAction SilentlyContinue
            $providerCount++
        }
        
        Write-Log "  [kill] $session (disabled + $providerCount providers removed)" "OK"
    } else {
        Write-Log "  [skip] $session -- not found"
    }
}

# Also disable any remaining autologger sessions that have "Diag" or "Telemetry" in the name
Write-Log ""
Write-Log "Sweeping for remaining diagnostic autologgers..."

Get-ChildItem $autoLoggerRoot -ErrorAction SilentlyContinue | ForEach-Object {
    $name = $_.PSChildName
    if ($name -match "Diag|Telemetry|Census|SQM|Ceip|Feedback" -and $name -notin $autologgersToKill) {
        Set-ItemProperty -Path $_.PSPath -Name "Start" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        $providers = Get-ChildItem $_.PSPath -ErrorAction SilentlyContinue
        foreach ($p in $providers) {
            Remove-Item $p.PSPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Log "  [kill] $name (sweep)" "OK"
    }
}

# ============================================================================
#  Phase 5: Per-User Service Template Neutering
# ============================================================================

Write-Log ""
Write-Log "=== Phase 5: Per-User Service Template Neutering ===" "PHASE"
Write-Log "Removing per-user service template DLLs..."

# Per-user services auto-spawn from templates in System32.
# Deleting the service above prevents new instances, but the template
# DLLs can still be loaded. Remove the binaries too.

$perUserBinaries = @(
    @{ Path = "$env:SystemRoot\System32\CDPUserSvc.dll"; Label = "CDPUserSvc DLL" },
    @{ Path = "$env:SystemRoot\System32\PimIndexMaintenanceSvc.dll"; Label = "PIM Index DLL" },
    @{ Path = "$env:SystemRoot\System32\UnistoreSvc.dll"; Label = "Unified Store DLL" },
    @{ Path = "$env:SystemRoot\System32\UserDataSvc.dll"; Label = "User Data DLL" },
    @{ Path = "$env:SystemRoot\System32\WpnUserService.dll"; Label = "Push Notification DLL" },
    @{ Path = "$env:SystemRoot\System32\DevicesFlowUserSvc.dll"; Label = "Devices Flow DLL" },
    @{ Path = "$env:SystemRoot\System32\cbdhsvc.dll"; Label = "Clipboard User DLL" },
    @{ Path = "$env:SystemRoot\System32\CaptureService.dll"; Label = "Capture Service DLL" },
    @{ Path = "$env:SystemRoot\System32\MessagingService.dll"; Label = "Messaging Service DLL" }
)

foreach ($item in $perUserBinaries) {
    Remove-Binary -Path $item.Path -Label $item.Label
}

# ============================================================================
#  Phase 6: Compatibility Engine Cleanup
# ============================================================================

Write-Log ""
Write-Log "=== Phase 6: Compatibility Engine Cleanup ===" "PHASE"
Write-Log "Purging compatibility databases and shim cache..."

# Clear the shim cache (PCA lookup database)
$shimCachePath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\AppCompatCache"
$shimProps = Get-ItemProperty -Path $shimCachePath -ErrorAction SilentlyContinue
if ($shimProps -and ($shimProps.PSObject.Properties.Name -contains "AppCompatCache")) {
    Remove-ItemProperty -Path $shimCachePath -Name "AppCompatCache" -Force -ErrorAction SilentlyContinue
    Write-Log "  [del] AppCompatCache shim cache purged" "OK"
}

# Clear compatibility layers
$layersPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
if (Test-Path $layersPath) {
    Remove-Item $layersPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "  [del] AppCompatFlags\Layers cleared" "OK"
}

# Clear compatibility store
$compatStorePaths = @(
    "$env:ProgramData\Microsoft\Windows\AppRepository\Packages\*compat*",
    "$env:SystemRoot\AppPatch\sysmain.sdb"
)

foreach ($p in $compatStorePaths) {
    $items = Get-Item $p -ErrorAction SilentlyContinue
    foreach ($item in $items) {
        Take-Ownership $item.FullName | Out-Null
        # Backup sdb files -- they're small and recoverable
        if ($item.Extension -eq ".sdb") {
            Copy-Item $item.FullName "$BackupDir\$($item.Name)" -Force -ErrorAction SilentlyContinue
        }
        Remove-Item $item.FullName -Force -ErrorAction SilentlyContinue
        Write-Log "  [del] $($item.FullName)" "OK"
    }
}

# Remove Compatibility Telemetry runner and appraiser directories
$appraiserDir = "$env:SystemRoot\System32\appraiser"
if (Test-Path $appraiserDir) {
    Take-Ownership $appraiserDir | Out-Null
    # Need to recurse ownership for directory contents
    $null = cmd /c "takeown /f `"$appraiserDir`" /r /d y >nul 2>&1"
    $null = cmd /c "icacls `"$appraiserDir`" /grant Administrators:F /t >nul 2>&1"
    Remove-Item $appraiserDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "  [del] Appraiser directory" "OK"
}

# ============================================================================
#  Phase 7: Artifact Purge
# ============================================================================

Write-Log ""
Write-Log "=== Phase 7: Artifact Purge ===" "PHASE"
Write-Log "Cleaning leftover data stores and caches..."

$artifactPaths = @(
    # Diagnostic data
    "$env:ProgramData\Microsoft\Diagnosis",
    # SQM data
    "$env:ProgramData\Microsoft\Windows\Sqm",
    # Setup telemetry
    "$env:ProgramData\Microsoft\Windows\Setup\Telemetry",
    # Compatible appraiser data
    "$env:ProgramData\Microsoft\Windows\Appraiser",
    # Connected Devices Platform data
    "$env:ProgramData\Microsoft\Windows\ConnectedDevicesPlatform",
    # Device Census data
    "$env:ProgramData\Microsoft\Windows\DeviceCensus",
    # Maps data
    "$env:ProgramData\Microsoft\Windows\Maps",
    # Location data
    "$env:ProgramData\Microsoft\Windows\Location",
    # Push notifications cache
    "$env:ProgramData\Microsoft\Windows\PushNotifications",
    # ETW trace files
    "$env:ProgramData\Microsoft\Diagnosis\ETLLogs\AutoLogger",
    # Feedback data
    "$env:ProgramData\Microsoft\SiufData",
    # ReadyBoot trace
    "$env:SystemRoot\Prefetch\ReadyBoot\*.fx",
    # Live kernel reports
    "$env:SystemRoot\LiveKernelReports",
    # Mini dumps
    "$env:SystemRoot\Minidump",
    # Full dump
    "$env:SystemRoot\MEMORY.DMP"
)

foreach ($path in $artifactPaths) {
    # Handle wildcard paths
    $items = @()
    if ($path -match '\*') {
        $items = Get-Item $path -ErrorAction SilentlyContinue
    } elseif (Test-Path $path) {
        $items = @(Get-Item $path)
    }

    foreach ($item in $items) {
        try {
            if ($item.PSIsContainer) {
                Remove-Item $item.FullName -Recurse -Force -ErrorAction Stop
            } else {
                Remove-Item $item.FullName -Force -ErrorAction Stop
            }
            Write-Log "  [del] $($item.FullName)" "OK"
        } catch {
            Write-Log "  [warn] Could not clean: $($item.FullName)" "WARN"
        }
    }
}

# Clean per-user artifact stores
Write-Log ""
Write-Log "Cleaning per-user artifacts..."

$userProfiles = Get-ChildItem "$env:SystemDrive\Users" -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notin @("Public", "Default", "Default User", "All Users") }

$perUserArtifacts = @(
    "AppData\Local\ConnectedDevicesPlatform",
    "AppData\Local\Diagnostics",
    "AppData\Local\Microsoft\Windows\Diagnosis",
    "AppData\Local\Microsoft\Windows\1033\StructuredQuerySchema.bin",
    "AppData\Local\Microsoft\Windows\WebCache",
    "AppData\Local\Microsoft\Windows\Explorer\thumbcache_*.db"
)

foreach ($profile in $userProfiles) {
    foreach ($relPath in $perUserArtifacts) {
        $fullPath = Join-Path $profile.FullName $relPath
        $items = Get-Item $fullPath -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            try {
                if ($item.PSIsContainer) {
                    Remove-Item $item.FullName -Recurse -Force -ErrorAction Stop
                } else {
                    Remove-Item $item.FullName -Force -ErrorAction Stop
                }
                Write-Log "  [del] $($item.FullName)" "OK"
            } catch {
                # Silently skip locked user files
            }
        }
    }
}

# ============================================================================
#  Summary
# ============================================================================

Write-Log ""
Write-Log "=== Amputation Complete ===" "PHASE"
Write-Log ""
Write-Log "Backups: $BackupDir"
Write-Log "Log: $LogFile"
Write-Log ""

# Count what we did
$logContent = Get-Content $LogFile -ErrorAction SilentlyContinue
$delCount = ($logContent | Select-String "\[del\]").Count
$rebootCount = ($logContent | Select-String "\[reboot\]").Count
$skipCount = ($logContent | Select-String "\[skip\]").Count
$warnCount = ($logContent | Select-String "\[warn\]").Count

Write-Log "Deleted: $delCount items" "OK"
Write-Log "Scheduled for reboot: $rebootCount items" "WARN"
Write-Log "Skipped (not found): $skipCount items"
Write-Log "Warnings: $warnCount items"
Write-Log ""
Write-Log "REBOOT REQUIRED" "WARN"
Write-Log ""

$reboot = Read-Host "Reboot now? (y/N)"
if ($reboot -eq "y" -or $reboot -eq "Y") {
    Write-Log "Rebooting..."
    Restart-Computer -Force
}
