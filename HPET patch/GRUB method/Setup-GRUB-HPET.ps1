#Requires -RunAsAdministrator
param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Status
)

$ErrorActionPreference = "Stop"

function Write-Info  { param([string]$M) Write-Host "  [i] $M" -ForegroundColor Cyan }
function Write-Ok    { param([string]$M) Write-Host "  [+] $M" -ForegroundColor Green }
function Write-Warn  { param([string]$M) Write-Host "  [!] $M" -ForegroundColor Yellow }
function Write-Err   { param([string]$M) Write-Host "  [X] $M" -ForegroundColor Red }

function Write-Banner {
    Write-Host ""
    Write-Host "  ==========================================================" -ForegroundColor Cyan
    Write-Host "  Disable HPET - GRUB ACPI Patcher" -ForegroundColor Cyan
    Write-Host "  No test signing | No watermark | Anti-cheat compatible" -ForegroundColor Cyan
    Write-Host "  ==========================================================" -ForegroundColor Cyan
    Write-Host ""
}

# =============================================================
# EFI PARTITION HELPERS (diskpart only, no Storage module)
# =============================================================

function Mount-EFIPartition {
    $dpList = "list disk" | diskpart
    $diskNums = @()
    foreach ($line in $dpList) {
        if ($line -match '^\s*Disk\s+(\d+)\s') { $diskNums += [int]$Matches[1] }
    }

    $efiDisk = -1
    $efiPart = -1
    foreach ($d in $diskNums) {
        $dp = @"
select disk $d
list partition
"@ | diskpart
        foreach ($line in $dp) {
            if ($line -match '^\s*Partition\s+(\d+)\s+System\s') {
                $efiDisk = $d
                $efiPart = [int]$Matches[1]
                break
            }
        }
        if ($efiDisk -ge 0) { break }
    }

    if ($efiDisk -lt 0) { throw "No EFI System Partition found" }
    Write-Info "Found EFI partition: Disk $efiDisk, Partition $efiPart"

    $letter = $null
    foreach ($l in [char[]]('Z','Y','X','W','V','U','T','S')) {
        if (-not (Test-Path ($l + ":"))) { $letter = $l; break }
    }
    if (-not $letter) { throw "No free drive letter available" }

    $dpAssign = @"
select disk $efiDisk
select partition $efiPart
assign letter=$letter
"@
    $dpAssign | diskpart | Out-Null
    Start-Sleep -Seconds 2

    $drv = $letter + ":"
    if (-not (Test-Path $drv)) { throw "Failed to mount EFI partition" }
    Write-Ok "Mounted EFI partition as $drv"
    return $drv
}

function Dismount-EFIPartition {
    param([string]$DriveLetter)
    $letter = $DriveLetter.TrimEnd(':')
    $dpScript = @"
select volume $letter
remove letter=$letter
"@
    $dpScript | diskpart 2>$null | Out-Null
}

# =============================================================
# DSDT EXTRACTION
# =============================================================

function Get-DSDT {
    # Extract DSDT from registry: HKLM:\HARDWARE\ACPI\DSDT\<OEM>\<Table>\<Rev>\00000000
    $basePath = "HKLM:\HARDWARE\ACPI\DSDT"
    if (-not (Test-Path $basePath)) {
        throw "DSDT registry path not found"
    }

    $oemKey = Get-ChildItem $basePath | Select-Object -First 1
    if (-not $oemKey) { throw "No OEM key under DSDT" }

    $tableKey = Get-ChildItem $oemKey.PSPath | Select-Object -First 1
    if (-not $tableKey) { throw "No table key under OEM" }

    $revKey = Get-ChildItem $tableKey.PSPath | Select-Object -First 1
    if (-not $revKey) { throw "No revision key under table" }

    $dsdt = (Get-ItemProperty $revKey.PSPath).'00000000'
    if (-not $dsdt -or $dsdt.Length -lt 100) {
        throw "DSDT data is empty or too small ($($dsdt.Length) bytes)"
    }

    # Validate DSDT signature
    $sig = [System.Text.Encoding]::ASCII.GetString($dsdt[0..3])
    if ($sig -ne "DSDT") {
        throw "Invalid DSDT signature: $sig"
    }

    return [byte[]]$dsdt
}

# =============================================================
# HPET PATCHING ENGINE
# =============================================================

function Find-AllOccurrences {
    param([byte[]]$Data, [byte[]]$Pattern)
    $results = @()
    for ($i = 0; $i -le $Data.Length - $Pattern.Length; $i++) {
        $match = $true
        for ($j = 0; $j -lt $Pattern.Length; $j++) {
            if ($Data[$i + $j] -ne $Pattern[$j]) { $match = $false; break }
        }
        if ($match) { $results += $i }
    }
    return $results
}

function Patch-DSDT {
    param([byte[]]$dsdt)

    $patched = [byte[]]$dsdt.Clone()
    $patchCount = 0

    # -------------------------------------------------------
    # STRATEGY: Find HPET device, then patch _STA to return 0
    # Also patch any HPTE variable references to disable
    # resource allocation and memory reservation.
    # -------------------------------------------------------

    # Step 1: Find HPET device in AML
    # Device() opcode = 5B 82, followed by PkgLength, then name "HPET" (48 50 45 54)
    $hpetNameBytes = [byte[]]@(0x48, 0x50, 0x45, 0x54) # "HPET"

    # Find all HPET name references to determine scope
    $hpetRefs = Find-AllOccurrences $patched $hpetNameBytes
    if ($hpetRefs.Count -eq 0) {
        throw "HPET device not found in DSDT. Your system may not have HPET or uses a different name."
    }
    Write-Info "Found $($hpetRefs.Count) HPET reference(s) in DSDT"

    # Step 2: Find the HPET enable variable name
    # Common names: HPTE, HPAS, HPEN - these control If() guards
    # We look for 4-byte names starting with HP that appear in If() conditions
    $hpetVarName = $null
    $hpetVarBytes = $null

    foreach ($candidate in @("HPTE", "HPEN", "HPAS")) {
        $cb = [System.Text.Encoding]::ASCII.GetBytes($candidate)
        $refs = Find-AllOccurrences $patched $cb
        if ($refs.Count -gt 0) {
            # Verify it appears in an If() context: A0 <len> <varname>
            foreach ($r in $refs) {
                if ($r -ge 2) {
                    # Check if preceded by If opcode (A0) + length byte
                    for ($lookback = 1; $lookback -le 4; $lookback++) {
                        if ($r - $lookback -ge 0 -and $patched[$r - $lookback] -eq 0xA0) {
                            $hpetVarName = $candidate
                            $hpetVarBytes = $cb
                            break
                        }
                    }
                }
                if ($hpetVarName) { break }
            }
        }
        if ($hpetVarName) { break }
    }

    if ($hpetVarName) {
        Write-Info "Found HPET enable variable: $hpetVarName"
    } else {
        Write-Info "No HPET enable variable found (will patch _STA directly)"
    }

    # Step 3: Patch all If(<HPET_VAR>) -> If(Zero) patterns
    # Pattern: A0 <len> <4-byte-varname> -> A0 <len> 00 A3 A3 A3
    # A3 = Noop (padding to maintain size)
    if ($hpetVarBytes) {
        for ($i = 0; $i -lt $patched.Length - 6; $i++) {
            if ($patched[$i] -eq 0xA0) {
                # Check if the variable name follows within 1-3 bytes (length encoding)
                for ($off = 2; $off -le 4; $off++) {
                    if (($i + $off + $hpetVarBytes.Length) -le $patched.Length) {
                        $nameMatch = $true
                        for ($j = 0; $j -lt $hpetVarBytes.Length; $j++) {
                            if ($patched[$i + $off + $j] -ne $hpetVarBytes[$j]) {
                                $nameMatch = $false
                                break
                            }
                        }
                        if ($nameMatch) {
                            # Replace variable name with Zero + Noops
                            $patched[$i + $off] = 0x00     # Zero
                            for ($j = 1; $j -lt $hpetVarBytes.Length; $j++) {
                                $patched[$i + $off + $j] = 0xA3  # Noop
                            }
                            $patchCount++
                            $addr = "0x{0:X}" -f $i
                            Write-Ok "Patched If($hpetVarName) -> If(Zero) at $addr"
                            break
                        }
                    }
                }
            }
        }

        # Also patch If(Not(<HPET_VAR>)) = If(LNot(<var>))
        # Pattern: A0 <len> 92 <4-byte-varname> -> A0 <len> 00 A3 A3 A3 A3
        # 92 = LNot opcode
        for ($i = 0; $i -lt $patched.Length - 8; $i++) {
            if ($patched[$i] -eq 0xA0) {
                for ($off = 2; $off -le 4; $off++) {
                    if (($i + $off + 1 + $hpetVarBytes.Length) -le $patched.Length) {
                        if ($patched[$i + $off] -eq 0x92) {
                            $nameMatch = $true
                            for ($j = 0; $j -lt $hpetVarBytes.Length; $j++) {
                                if ($patched[$i + $off + 1 + $j] -ne $hpetVarBytes[$j]) {
                                    $nameMatch = $false
                                    break
                                }
                            }
                            if ($nameMatch) {
                                $patched[$i + $off] = 0x00        # Zero
                                for ($j = 0; $j -lt $hpetVarBytes.Length; $j++) {
                                    $patched[$i + $off + 1 + $j] = 0xA3  # Noop
                                }
                                $patchCount++
                                $addr = "0x{0:X}" -f $i
                                Write-Ok "Patched If(!$hpetVarName) -> If(Zero) at $addr"
                                break
                            }
                        }
                    }
                }
            }
        }
    }

    # Step 4: Patch Return(0x0F) -> Return(0x00) in the HPET _STA region
    # _STA method: 14 <len> 5F 53 54 41 <flags>
    # We search near HPET device references
    $staBytes = [byte[]]@(0x5F, 0x53, 0x54, 0x41) # "_STA"

    foreach ($href in $hpetRefs) {
        # Search for _STA within 500 bytes after HPET name
        $searchEnd = [Math]::Min($href + 500, $patched.Length - 10)
        for ($i = $href; $i -lt $searchEnd; $i++) {
            $staMatch = $true
            for ($j = 0; $j -lt $staBytes.Length; $j++) {
                if ($patched[$i + $j] -ne $staBytes[$j]) { $staMatch = $false; break }
            }
            if ($staMatch) {
                # Found _STA near HPET. Look for Return(0x0F) within 30 bytes
                $retEnd = [Math]::Min($i + 30, $patched.Length - 3)
                for ($r = $i; $r -lt $retEnd; $r++) {
                    # A4 0A 0F = Return(0x0F)
                    if ($patched[$r] -eq 0xA4 -and $patched[$r+1] -eq 0x0A -and $patched[$r+2] -eq 0x0F) {
                        $patched[$r+2] = 0x00  # Return(0x00) instead
                        $patchCount++
                        $addr = "0x{0:X}" -f $r
                        Write-Ok "Patched _STA Return(0x0F) -> Return(0x00) at $addr"
                    }
                    # A4 0A 0B = Return(0x0B) (another common "present" value)
                    if ($patched[$r] -eq 0xA4 -and $patched[$r+1] -eq 0x0A -and $patched[$r+2] -eq 0x0B) {
                        $patched[$r+2] = 0x00
                        $patchCount++
                        $addr = "0x{0:X}" -f $r
                        Write-Ok "Patched _STA Return(0x0B) -> Return(0x00) at $addr"
                    }
                }
            }
        }
    }

    if ($patchCount -eq 0) {
        throw "No patchable HPET patterns found. Your DSDT may use an unsupported structure."
    }

    # Step 5: Fix ACPI checksum (byte at offset 9)
    $patched[9] = 0
    $sum = 0
    foreach ($b in $patched) { $sum = ($sum + $b) -band 0xFF }
    $patched[9] = (256 - $sum) -band 0xFF

    $verify = 0
    foreach ($b in $patched) { $verify = ($verify + $b) -band 0xFF }
    if ($verify -ne 0) {
        Write-Warn "Checksum verification failed (got $verify, expected 0)"
    } else {
        Write-Ok "ACPI checksum valid"
    }

    Write-Ok "Applied $patchCount patch(es) to DSDT ($($patched.Length) bytes)"
    return $patched
}

# =============================================================
# STATUS
# =============================================================
if ($Status) {
    Write-Banner
    Write-Host "  Checking status..." -ForegroundColor White
    Write-Host ""

    # Check Device Manager for HPET
    $hpetDev = Get-CimInstance Win32_PnPEntity -EA SilentlyContinue |
               Where-Object { $_.Name -like "*High Precision*" -or $_.Name -like "*HPET*" }
    if ($hpetDev) {
        Write-Warn "HPET is ACTIVE in Device Manager: $($hpetDev.Name)"
        Write-Info "Status: $($hpetDev.Status) | Error: $($hpetDev.ConfigManagerErrorCode)"
    } else {
        Write-Ok "HPET not found in Device Manager (disabled or removed)"
    }

    try {
        $efiDrive = Mount-EFIPartition
        $dsdtAml = Join-Path $efiDrive "EFI\acpi\dsdt.aml"
        $grubEfi = Join-Path $efiDrive "EFI\Microsoft\Boot\bootmgfw.efi"
        $bootEfi = Join-Path $efiDrive "EFI\BOOT\BOOTx64.efi"

        if (Test-Path $dsdtAml) {
            $sz = (Get-Item $dsdtAml).Length
            Write-Ok "Patched DSDT present ($sz bytes)"
        } else {
            Write-Info "No patched DSDT on EFI partition"
        }

        if (Test-Path $grubEfi) {
            $sz = (Get-Item $grubEfi).Length
            if ($sz -gt 2MB -and $sz -lt 5MB) {
                Write-Ok "GRUB is installed as bootmgfw.efi"
            } else {
                Write-Info "bootmgfw.efi present ($sz bytes)"
            }
        }

        if (Test-Path $bootEfi) {
            Write-Ok "Windows fallback bootloader present (BOOTx64.efi)"
        }

        Dismount-EFIPartition $efiDrive
    } catch {
        Write-Err "EFI check failed: $_"
    }
    Write-Host ""
    exit 0
}

# =============================================================
# UNINSTALL
# =============================================================
if ($Uninstall) {
    Write-Banner
    Write-Host "  Uninstalling HPET Patcher" -ForegroundColor White
    Write-Host ""
    try {
        $efiDrive = Mount-EFIPartition

        # Remove GRUB from bootmgfw.efi
        $grubEfi = Join-Path $efiDrive "EFI\Microsoft\Boot\bootmgfw.efi"
        if (Test-Path $grubEfi) {
            Remove-Item $grubEfi -Force
            Write-Ok "Removed GRUB (bootmgfw.efi)"
        }

        # Remove patched DSDT
        $acpiDir = Join-Path $efiDrive "EFI\acpi"
        if (Test-Path $acpiDir) {
            Remove-Item $acpiDir -Recurse -Force
            Write-Ok "Removed patched DSDT"
        }

        # Ensure real bootloader is at BOOTx64.efi
        $bootEfi = Join-Path $efiDrive "EFI\BOOT\BOOTx64.efi"
        $winBootSrc = Join-Path $env:SystemRoot "Boot\EFI\bootmgfw.efi"
        if (Test-Path $winBootSrc) {
            Copy-Item $winBootSrc $bootEfi -Force
            Write-Ok "Ensured real Windows bootloader at BOOTx64.efi"
        }

        # Remove OpenCore leftovers
        $ocDir = Join-Path $efiDrive "EFI\OC"
        if (Test-Path $ocDir) {
            Remove-Item $ocDir -Recurse -Force
            Write-Ok "Removed leftover OpenCore folder"
        }

        # Remove old acpitabl.dat method
        $acpiDat = Join-Path $env:SystemRoot "System32\acpitabl.dat"
        if (Test-Path $acpiDat) {
            Remove-Item $acpiDat -Force
            bcdedit /set testsigning off 2>$null | Out-Null
            Write-Ok "Removed acpitabl.dat and disabled test signing"
        }

        Dismount-EFIPartition $efiDrive
        Write-Host ""
        Write-Ok "Uninstalled. Reboot to boot Windows normally."
        Write-Host ""
    } catch {
        Write-Err "Uninstall failed: $_"
    }
    exit 0
}

# =============================================================
# INSTALL
# =============================================================
if (-not $Install) {
    Write-Banner
    Write-Host "  Usage:" -ForegroundColor White
    Write-Host ""
    Write-Host "    .\Setup-GRUB-HPET.ps1 -Install" -ForegroundColor Yellow
    Write-Host "    .\Setup-GRUB-HPET.ps1 -Uninstall" -ForegroundColor Yellow
    Write-Host "    .\Setup-GRUB-HPET.ps1 -Status" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  What this does:" -ForegroundColor Gray
    Write-Host "    Extracts your DSDT, patches HPET to disabled, and installs" -ForegroundColor Gray
    Write-Host "    a GRUB bootloader that loads the patched table before Windows." -ForegroundColor Gray
    Write-Host "    No test signing needed. Works with BattlEye/EAC." -ForegroundColor Gray
    Write-Host ""
    exit 0
}

Write-Banner

# ---- Locate GRUB binary ----
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
if ([string]::IsNullOrEmpty($scriptDir)) { $scriptDir = Get-Location }

$grubSrc = Join-Path $scriptDir "grubx64.efi"
if (-not (Test-Path $grubSrc)) {
    Write-Err "grubx64.efi not found next to this script"
    exit 1
}
Write-Ok "Found grubx64.efi"

# ---- Verify Windows bootloader exists ----
$winBootSrc = Join-Path $env:SystemRoot "Boot\EFI\bootmgfw.efi"
if (-not (Test-Path $winBootSrc)) {
    Write-Err "Cannot find Windows bootloader at $winBootSrc"
    Write-Err "This tool requires a UEFI Windows installation."
    exit 1
}
Write-Ok "Found Windows bootloader"

# ---- Extract and patch DSDT ----
Write-Host ""
Write-Host "  Extracting and Patching DSDT" -ForegroundColor White

$dsdt = Get-DSDT
$oemId = [System.Text.Encoding]::ASCII.GetString($dsdt[10..15]).Trim()
$tableId = [System.Text.Encoding]::ASCII.GetString($dsdt[16..23]).Trim()
Write-Info "DSDT: $oemId / $tableId ($($dsdt.Length) bytes)"

$patchedDsdt = Patch-DSDT $dsdt

# Save to temp for installation
$tempDsdt = Join-Path $env:TEMP "dsdt_hpet_patched.aml"
[System.IO.File]::WriteAllBytes($tempDsdt, $patchedDsdt)

# ---- Mount EFI and install ----
Write-Host ""
Write-Host "  Installing to EFI Partition" -ForegroundColor White

$efiDrive = Mount-EFIPartition

$bootTarget = Join-Path $efiDrive "EFI\BOOT"
$msBootFolder = Join-Path $efiDrive "EFI\Microsoft\Boot"
$acpiFolder = Join-Path $efiDrive "EFI\acpi"

foreach ($dir in @($bootTarget, $msBootFolder, $acpiFolder)) {
    if (-not (Test-Path $dir)) {
        New-Item $dir -ItemType Directory -Force | Out-Null
    }
}

# ==============================================================
# LAYOUT:
#   \EFI\Microsoft\Boot\bootmgfw.efi  = GRUB (firmware loads this)
#   \EFI\BOOT\BOOTx64.efi             = Real Windows bootloader
#   \EFI\acpi\dsdt.aml                = Patched DSDT (HPET disabled)
#
# Firmware -> GRUB -> load DSDT -> chainload Windows -> done
# ==============================================================

# Step 1: Real Windows bootloader at fallback path
$bootEfiDest = Join-Path $bootTarget "BOOTx64.efi"
Copy-Item $winBootSrc $bootEfiDest -Force
Write-Ok "Windows bootloader -> EFI\BOOT\BOOTx64.efi"

# Step 2: GRUB as bootmgfw.efi
$msBootEfi = Join-Path $msBootFolder "bootmgfw.efi"
Copy-Item $grubSrc $msBootEfi -Force
Write-Ok "GRUB -> EFI\Microsoft\Boot\bootmgfw.efi"

# Step 3: Patched DSDT
$dsdtDest = Join-Path $acpiFolder "dsdt.aml"
Copy-Item $tempDsdt $dsdtDest -Force
Write-Ok "Patched DSDT -> EFI\acpi\dsdt.aml"

# Step 4: Remove old approaches
$ocDir = Join-Path $efiDrive "EFI\OC"
if (Test-Path $ocDir) {
    Remove-Item $ocDir -Recurse -Force
    Write-Ok "Removed old OpenCore folder"
}

$acpiDat = Join-Path $env:SystemRoot "System32\acpitabl.dat"
if (Test-Path $acpiDat) {
    Remove-Item $acpiDat -Force
    bcdedit /set testsigning off 2>$null | Out-Null
    Write-Ok "Removed old acpitabl.dat"
}

# Cleanup temp
Remove-Item $tempDsdt -Force -EA SilentlyContinue

Dismount-EFIPartition $efiDrive

# ---- Done ----
Write-Host ""
Write-Host "  ==========================================================" -ForegroundColor Green
Write-Host "  INSTALLED - REBOOT NOW" -ForegroundColor Green
Write-Host "  ==========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Boot chain:" -ForegroundColor Cyan
Write-Host "    Firmware -> GRUB (invisible) -> patches DSDT -> Windows" -ForegroundColor Cyan
Write-Host ""
Write-Host "  After reboot, verify:" -ForegroundColor White
Write-Host "    - Device Manager: HPET should show error or be missing" -ForegroundColor Gray
Write-Host "    - Run LatencyMon to check DPC/ISR improvement" -ForegroundColor Gray
Write-Host ""
Write-Host "  EMERGENCY RECOVERY (UEFI Shell or Windows Recovery USB):" -ForegroundColor Yellow
Write-Host "    Delete \EFI\Microsoft\Boot\bootmgfw.efi from EFI partition" -ForegroundColor Gray
Write-Host "    Windows will boot from \EFI\BOOT\BOOTx64.efi as fallback" -ForegroundColor Gray
Write-Host ""

$r = Read-Host "  Reboot now? (Y/N)"
if ($r -eq 'Y' -or $r -eq 'y') {
    Write-Info "Rebooting in 5 seconds..."
    Start-Sleep 5
    Restart-Computer -Force
} else {
    Write-Info "Remember to reboot manually."
}
