#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Complete WER (Windows Error Reporting) Amputation Script
    Removes all WER components, services, drivers, ETW providers, scheduled tasks,
    and replaces wer.dll with a compiled stub for app compatibility.

.DESCRIPTION
    This is the nuclear option. It:
    1. Stops and deletes the WerSvc service
    2. Disables all WER-related policies via registry
    3. Removes all WER scheduled tasks
    4. Unregisters WER ETW providers
    5. Removes WER binaries (WerFault, WerFaultSecure, wermgr, werui.dll)
    6. Replaces wer.dll with a stub DLL (must be pre-compiled)
    7. Disables werkernel.sys via registry (kept on disk for boot safety)
    8. Cleans up WER report stores and queues
    9. Disables WER optional feature

.NOTES
    - Run from an elevated PowerShell prompt
    - Place the compiled stub wer.dll in the same directory as this script
    - A system restore point is created before changes
    - Reboot required after execution
    - Test on a non-production system first
#>

param(
    [string]$StubDllPath = "$PSScriptRoot\wer.dll",
    [string]$Stub32DllPath = "$PSScriptRoot\wer32.dll",
    [switch]$SkipRestorePoint,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# ============================================================================
#  Logging
# ============================================================================

$LogFile = "$PSScriptRoot\wer_removal_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    Write-Host $entry -ForegroundColor $(switch ($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        "OK"    { "Green" }
        default { "White" }
    })
    Add-Content -Path $LogFile -Value $entry
}

# ============================================================================
#  Preflight Checks
# ============================================================================

Write-Log "=== WER Amputation Script Starting ==="
Write-Log "Logging to: $LogFile"

# Verify elevation
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "This script must be run as Administrator." "ERROR"
    exit 1
}

# Check for stub DLLs
if (-not (Test-Path $StubDllPath)) {
    Write-Log "x64 stub wer.dll not found at: $StubDllPath" "ERROR"
    Write-Log "Compile wer_stub.c first. See README.md for instructions." "ERROR"
    exit 1
}

if (-not (Test-Path $Stub32DllPath)) {
    Write-Log "x86 stub wer32.dll not found at: $Stub32DllPath" "WARN"
    Write-Log "32-bit apps that call WER may fail. Continuing with x64 stub only."
    Write-Log "To fix: compile an x86 version and place it as wer32.dll next to this script."
}

# Confirm
if (-not $Force) {
    Write-Host ""
    Write-Host "WARNING: This will permanently remove Windows Error Reporting." -ForegroundColor Red
    Write-Host "  - Crash dialogs will no longer appear"
    Write-Host "  - No crash dumps will be generated (kernel or user mode)"
    Write-Host "  - Windows Update servicing may flag missing components"
    Write-Host "  - A restore point will be created (unless -SkipRestorePoint)"
    Write-Host ""
    $confirm = Read-Host "Type 'AMPUTATE' to proceed"
    if ($confirm -ne "AMPUTATE") {
        Write-Log "Aborted by user." "WARN"
        exit 0
    }
}

# ============================================================================
#  Restore Point
# ============================================================================

if (-not $SkipRestorePoint) {
    Write-Log "Creating system restore point..."
    try {
        Checkpoint-Computer -Description "Pre-WER Amputation" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Log "Restore point created." "OK"
    } catch {
        Write-Log "Failed to create restore point: $_" "WARN"
        Write-Log "Continuing anyway..."
    }
}

# ============================================================================
#  Helper: Take ownership and grant full control
# ============================================================================

function Take-Ownership {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }

    $null = & takeown /f $Path 2>&1
    $null = & icacls $Path /grant "Administrators:F" 2>&1
    $null = & icacls $Path /grant "SYSTEM:F" 2>&1
    return $true
}

# ============================================================================
#  Helper: Kill processes using a file
# ============================================================================

function Stop-ProcessByPath {
    param([string]$Path)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Log "  Killing process: $($_.Name) (PID $($_.Id))"
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    }
}

# ============================================================================
#  Phase 1: Stop and Delete WerSvc Service
# ============================================================================

Write-Log "--- Phase 1: Service Removal ---"

# Stop WerSvc
$svc = Get-Service -Name "WerSvc" -ErrorAction SilentlyContinue
if ($svc) {
    if ($svc.Status -ne "Stopped") {
        Write-Log "Stopping WerSvc..."
        Stop-Service -Name "WerSvc" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    # Disable first (in case delete fails)
    $null = cmd /c "sc.exe config WerSvc start= disabled >nul 2>&1"
    # Delete the service
    $null = cmd /c "sc.exe delete WerSvc >nul 2>&1"
    Write-Log "WerSvc service deleted." "OK"
} else {
    Write-Log "WerSvc service not found (already removed)." "WARN"
}

# Also handle wersvc.dll (the service DLL)
$wersvcDll = "$env:SystemRoot\System32\wersvc.dll"
if (Test-Path $wersvcDll) {
    Take-Ownership $wersvcDll | Out-Null
    # Backup then delete
    Copy-Item $wersvcDll "$PSScriptRoot\backup_wersvc.dll" -Force -ErrorAction SilentlyContinue
    Remove-Item $wersvcDll -Force -ErrorAction SilentlyContinue
    Write-Log "wersvc.dll removed." "OK"
}

# ============================================================================
#  Phase 2: Registry -- Disable Everything
# ============================================================================

Write-Log "--- Phase 2: Registry Policies ---"

$regPaths = @(
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"; Name = "Disabled"; Value = 1; Type = "DWord" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"; Name = "DontShowUI"; Value = 1; Type = "DWord" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"; Name = "DontSendAdditionalData"; Value = 1; Type = "DWord" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"; Name = "LoggingDisabled"; Value = 1; Type = "DWord" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"; Name = "AutoApproveOSDumps"; Value = 0; Type = "DWord" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\Consent"; Name = "DefaultConsent"; Value = 0; Type = "DWord" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\Consent"; Name = "DefaultOverrideBehavior"; Value = 1; Type = "DWord" },
    # Disable crash dumps entirely
    @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl"; Name = "CrashDumpEnabled"; Value = 0; Type = "DWord" },
    @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl"; Name = "EnableLogFile"; Value = 0; Type = "DWord" },
    @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl"; Name = "AutoReboot"; Value = 1; Type = "DWord" },
    # Disable user-mode crash dumps
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps"; Name = "DumpCount"; Value = 0; Type = "DWord" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps"; Name = "DumpType"; Value = 0; Type = "DWord" },
    # GPO-style disable
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting"; Name = "Disabled"; Value = 1; Type = "DWord" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting"; Name = "DontSendAdditionalData"; Value = 1; Type = "DWord" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting"; Name = "DontShowUI"; Value = 1; Type = "DWord" },
    # Disable WER for the AeDebug (JIT debugger) path
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AeDebug"; Name = "Auto"; Value = "1"; Type = "String" }
)

foreach ($reg in $regPaths) {
    if (-not (Test-Path $reg.Path)) {
        New-Item -Path $reg.Path -Force | Out-Null
    }
    Set-ItemProperty -Path $reg.Path -Name $reg.Name -Value $reg.Value -Type $reg.Type -Force
    Write-Log "  Set: $($reg.Path)\$($reg.Name) = $($reg.Value)"
}

# Remove the JIT debugger pointing to WerFault
$aeDebugPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AeDebug"
$aeDebugProps = Get-ItemProperty -Path $aeDebugPath -ErrorAction SilentlyContinue
if ($aeDebugProps -and ($aeDebugProps.PSObject.Properties.Name -contains "Debugger")) {
    if ($aeDebugProps.Debugger -match "WerFault") {
        Remove-ItemProperty -Path $aeDebugPath -Name "Debugger" -Force -ErrorAction SilentlyContinue
        Write-Log "  Removed AeDebug WerFault debugger entry." "OK"
    }
}

# Same for WOW64
$aeDebugWow = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\AeDebug"
if (Test-Path $aeDebugWow) {
    $aeDebugWowProps = Get-ItemProperty -Path $aeDebugWow -ErrorAction SilentlyContinue
    if ($aeDebugWowProps -and ($aeDebugWowProps.PSObject.Properties.Name -contains "Debugger")) {
        if ($aeDebugWowProps.Debugger -match "WerFault") {
            Remove-ItemProperty -Path $aeDebugWow -Name "Debugger" -Force -ErrorAction SilentlyContinue
            Write-Log "  Removed WOW64 AeDebug WerFault debugger entry." "OK"
        }
    }
}

Write-Log "Registry policies applied." "OK"

# ============================================================================
#  Phase 3: Scheduled Tasks
# ============================================================================

Write-Log "--- Phase 3: Scheduled Task Removal ---"

$werTasks = @(
    "\Microsoft\Windows\Windows Error Reporting\QueueReporting"
)

# Also search for any other WER-related tasks
$allTasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
    $_.TaskPath -match "Error Reporting" -or $_.TaskName -match "WER" -or $_.TaskName -match "WerTask"
}

foreach ($task in $allTasks) {
    $fullPath = "$($task.TaskPath)$($task.TaskName)"
    if ($fullPath -notin $werTasks) { $werTasks += $fullPath }
}

foreach ($taskPath in $werTasks) {
    try {
        Disable-ScheduledTask -TaskPath ($taskPath -replace '[^\\]+$','') -TaskName ($taskPath -split '\\')[-1] -ErrorAction Stop | Out-Null
        Unregister-ScheduledTask -TaskPath ($taskPath -replace '[^\\]+$','') -TaskName ($taskPath -split '\\')[-1] -Confirm:$false -ErrorAction Stop
        Write-Log "  Removed task: $taskPath" "OK"
    } catch {
        # Fallback to schtasks — suppress all output including stderr
        $null = cmd /c "schtasks /Delete /TN `"$taskPath`" /F >nul 2>&1"
        if ($LASTEXITCODE -eq 0) {
            Write-Log "  Removed task (fallback): $taskPath" "OK"
        } else {
            Write-Log "  Task not found (already removed): $taskPath" "WARN"
        }
    }
}

# ============================================================================
#  Phase 4: ETW Provider Cleanup
# ============================================================================

Write-Log "--- Phase 4: ETW Provider Cleanup ---"

# Known WER ETW provider GUIDs
$werEtwProviders = @(
    "{E46EEAD8-0C54-4489-9898-8FA79D059E0E}",  # Microsoft-Windows-WindowsErrorReporting
    "{CC79CF77-70D9-4082-9B52-23F3A3E92FE4}",  # WER Diag
    "{1377561D-9312-452C-AD13-C4A1C9C906E0}",  # WER Helper
    "{3E0D88DE-AE5C-438A-BB1C-C2E627F8AECB}"   # WER SQM Upload
)

foreach ($guid in $werEtwProviders) {
    try {
        # Remove autologger entries
        $autoLoggerPath = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger"
        Get-ChildItem $autoLoggerPath -ErrorAction SilentlyContinue | ForEach-Object {
            $sessionPath = $_.PSPath
            Get-ChildItem $sessionPath -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.PSChildName -eq $guid) {
                    Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Log "  Removed ETW autologger entry: $guid from $($sessionPath | Split-Path -Leaf)"
                }
            }
        }
    } catch {
        Write-Log "  Warning processing ETW provider $guid : $_" "WARN"
    }
}

# Disable WER trace sessions
$werSessions = @("WerFaultTraceSession", "WerConsentTraceSession")
foreach ($session in $werSessions) {
    $sessionPath = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\$session"
    if (Test-Path $sessionPath) {
        Set-ItemProperty -Path $sessionPath -Name "Start" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Log "  Disabled ETW session: $session" "OK"
    }
}

Write-Log "ETW cleanup complete." "OK"

# ============================================================================
#  Phase 5: Binary Removal
# ============================================================================

Write-Log "--- Phase 5: Binary Removal ---"

# Kill any running WER processes first
$werProcesses = @("WerFault", "WerFaultSecure", "wermgr")
foreach ($proc in $werProcesses) {
    Stop-ProcessByPath "$env:SystemRoot\System32\$proc.exe"
}

# Binaries to remove entirely
$binariesToRemove = @(
    "$env:SystemRoot\System32\WerFault.exe",
    "$env:SystemRoot\System32\WerFaultSecure.exe",
    "$env:SystemRoot\System32\wermgr.exe",
    "$env:SystemRoot\System32\werui.dll",
    "$env:SystemRoot\System32\wersvc.dll",
    "$env:SystemRoot\System32\wer.dll",
    # SysWOW64 copies (32-bit)
    "$env:SystemRoot\SysWOW64\WerFault.exe",
    "$env:SystemRoot\SysWOW64\WerFaultSecure.exe",
    "$env:SystemRoot\SysWOW64\wermgr.exe",
    "$env:SystemRoot\SysWOW64\wer.dll",
    "$env:SystemRoot\SysWOW64\werui.dll"
)

$backupDir = "$PSScriptRoot\wer_backup"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

foreach ($binary in $binariesToRemove) {
    if (Test-Path $binary) {
        $fileName = Split-Path $binary -Leaf
        $parentDir = (Split-Path $binary -Parent) | Split-Path -Leaf
        $backupName = "${parentDir}_${fileName}"

        # Backup
        try {
            Take-Ownership $binary | Out-Null
            Copy-Item $binary "$backupDir\$backupName" -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Log "  Could not backup $binary (may be locked): $_" "WARN"
        }

        # Remove
        try {
            Remove-Item $binary -Force -ErrorAction Stop
            Write-Log "  Removed: $binary" "OK"
        } catch {
            # File may be in use -- schedule for deletion on reboot
            Write-Log "  File locked, scheduling removal on reboot: $binary" "WARN"
            $pendingKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
            $pending = (Get-ItemProperty -Path $pendingKey -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue).PendingFileRenameOperations
            if (-not $pending) { $pending = @() }
            $ntPath = "\??\$binary"
            $pending += $ntPath
            $pending += ""
            Set-ItemProperty -Path $pendingKey -Name "PendingFileRenameOperations" -Value $pending -Type MultiString -Force
        }
    } else {
        Write-Log "  Not found (skipped): $binary" "WARN"
    }
}

# ============================================================================
#  Phase 6: Deploy Stub DLL
# ============================================================================

Write-Log "--- Phase 6: Stub DLL Deployment ---"

# Deploy x64 stub to System32
$sys32Target = "$env:SystemRoot\System32\wer.dll"
try {
    Copy-Item $StubDllPath $sys32Target -Force -ErrorAction Stop
    Write-Log "  Deployed x64 stub: $sys32Target" "OK"
} catch {
    Write-Log "  Failed to deploy x64 stub -- scheduling reboot copy: $_" "WARN"
    $tempStub = "$env:SystemRoot\Temp\wer_stub64_$(Get-Random).dll"
    Copy-Item $StubDllPath $tempStub -Force
    $pendingKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    $pending = (Get-ItemProperty -Path $pendingKey -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue).PendingFileRenameOperations
    if (-not $pending) { $pending = @() }
    $pending += "\??\$tempStub"
    $pending += "\??\$sys32Target"
    Set-ItemProperty -Path $pendingKey -Name "PendingFileRenameOperations" -Value $pending -Type MultiString -Force
}

# Deploy x86 stub to SysWOW64 (if present and we have a 32-bit build)
if (Test-Path "$env:SystemRoot\SysWOW64") {
    $wow64Target = "$env:SystemRoot\SysWOW64\wer.dll"
    if (Test-Path $Stub32DllPath) {
        try {
            Copy-Item $Stub32DllPath $wow64Target -Force -ErrorAction Stop
            Write-Log "  Deployed x86 stub: $wow64Target" "OK"
        } catch {
            Write-Log "  Failed to deploy x86 stub -- scheduling reboot copy: $_" "WARN"
            $tempStub32 = "$env:SystemRoot\Temp\wer_stub32_$(Get-Random).dll"
            Copy-Item $Stub32DllPath $tempStub32 -Force
            $pendingKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
            $pending = (Get-ItemProperty -Path $pendingKey -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue).PendingFileRenameOperations
            if (-not $pending) { $pending = @() }
            $pending += "\??\$tempStub32"
            $pending += "\??\$wow64Target"
            Set-ItemProperty -Path $pendingKey -Name "PendingFileRenameOperations" -Value $pending -Type MultiString -Force
        }
    } else {
        Write-Log "  Skipped SysWOW64 -- no x86 stub (wer32.dll) provided." "WARN"
    }
}

# ============================================================================
#  Phase 7: Kernel Driver (werkernel.sys) -- Disable via Registry
#  NOTE: Binary is left on disk intentionally. Deleting kernel drivers can
#  cause boot failures if the boot manager validates driver presence before
#  honoring the Start value. Setting Start=4 (Disabled) and ErrorControl=0
#  (Ignore) achieves the same effect safely.
# ============================================================================

Write-Log "--- Phase 7: Kernel Driver Disable ---"

$driverSvcPath = "HKLM:\SYSTEM\CurrentControlSet\Services\WerKernel"
if (Test-Path $driverSvcPath) {
    Set-ItemProperty -Path $driverSvcPath -Name "Start" -Value 4 -Type DWord -Force
    Set-ItemProperty -Path $driverSvcPath -Name "ErrorControl" -Value 0 -Type DWord -Force
    Write-Log "  werkernel: Start=4 (Disabled), ErrorControl=0 (Ignore)" "OK"
} else {
    Write-Log "  werkernel service entry not found (not present on this build)." "WARN"
}

# ============================================================================
#  Phase 8: Report Store Cleanup
# ============================================================================

Write-Log "--- Phase 8: Report Store Cleanup ---"

$reportStores = @(
    "$env:ProgramData\Microsoft\Windows\WER",
    "$env:LOCALAPPDATA\Microsoft\Windows\WER",
    "$env:LOCALAPPDATA\CrashDumps",
    "$env:SystemRoot\LiveKernelReports",
    "$env:SystemRoot\Minidump",
    "$env:SystemRoot\MEMORY.DMP"
)

foreach ($store in $reportStores) {
    if (Test-Path $store) {
        try {
            if ((Get-Item $store) -is [System.IO.DirectoryInfo]) {
                Remove-Item $store -Recurse -Force -ErrorAction Stop
            } else {
                Remove-Item $store -Force -ErrorAction Stop
            }
            Write-Log "  Cleaned: $store" "OK"
        } catch {
            Write-Log "  Could not clean $store : $_" "WARN"
        }
    }
}

# Also handle all user profiles
$userProfiles = Get-ChildItem "$env:SystemDrive\Users" -Directory -ErrorAction SilentlyContinue
foreach ($profile in $userProfiles) {
    $userWer = "$($profile.FullName)\AppData\Local\Microsoft\Windows\WER"
    $userCrash = "$($profile.FullName)\AppData\Local\CrashDumps"
    foreach ($p in @($userWer, $userCrash)) {
        if (Test-Path $p) {
            Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "  Cleaned user store: $p" "OK"
        }
    }
}

# ============================================================================
#  Phase 9: Windows Feature Disable (if applicable)
# ============================================================================

Write-Log "--- Phase 9: Optional Feature Disable ---"

try {
    $werFeature = Get-WindowsOptionalFeature -Online -FeatureName "Windows-Error-Reporting" -ErrorAction SilentlyContinue
    if ($werFeature -and $werFeature.State -eq "Enabled") {
        Disable-WindowsOptionalFeature -Online -FeatureName "Windows-Error-Reporting" -NoRestart -ErrorAction Stop | Out-Null
        Write-Log "  Disabled Windows-Error-Reporting optional feature." "OK"
    }
} catch {
    Write-Log "  Optional feature not found or already disabled." "WARN"
}

# ============================================================================
#  Summary
# ============================================================================

Write-Log ""
Write-Log "=== WER Amputation Complete ===" "OK"
Write-Log ""
Write-Log "Backups saved to: $backupDir"
Write-Log "Log file: $LogFile"
Write-Log ""
Write-Log "REBOOT REQUIRED to complete removal of locked files." "WARN"
Write-Log ""

$reboot = Read-Host "Reboot now? (y/N)"
if ($reboot -eq "y" -or $reboot -eq "Y") {
    Write-Log "Rebooting..."
    Restart-Computer -Force
}
