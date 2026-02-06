#Requires -RunAsAdministrator
<#
.SYNOPSIS
    HPET & GPE Disabler for Windows 10/11 via Full DSDT Override (acpitabl.dat)
    
.DESCRIPTION
    Disables the HPET device and optionally stubs GPE handlers by patching the
    full DSDT binary and deploying it via acpitabl.dat — Windows' native ACPI 
    table test/override mechanism.
    
    Unlike SSDT overlays (which cannot override methods already defined in the 
    DSDT), this replaces the entire DSDT so all patches take full effect.
    
    Generic — auto-detects HPET patterns from any motherboard's DSDT.

.PARAMETER DSDTPath
    Path to a DSDT.bin file (from RWEverything or similar). If omitted, the 
    script attempts to extract the DSDT from the Windows registry.

.PARAMETER ListHPET
    Scan the DSDT and display HPET device patterns without patching.
    
.PARAMETER ListGPE
    Scan the DSDT and list all GPE handler methods without patching.
    
.PARAMETER DisableHPET
    Patch HPET._STA to return 0 (device not present). Also patches related
    If(HPTE) conditionals in _CRS and PDRC to prevent resource claiming.

.PARAMETER HPETMinimal
    Only patch _STA return value (skip If(HPTE)/_CRS/PDRC patches). Use if
    the full patch causes issues on your specific board.
    
.PARAMETER StubGPE
    Comma-separated list of GPE method names to stub, e.g. "_L69,_L61".
    
.PARAMETER StubAllGPE
    Stub ALL detected GPE handler methods.

.PARAMETER Install
    Copy acpitabl.dat to System32 and enable test signing.
    
.PARAMETER Uninstall
    Remove acpitabl.dat from System32 and disable test signing.

.PARAMETER OutputPath
    Custom output path for the generated acpitabl.dat (default: script dir).

.EXAMPLE
    .\Disable-HPET.ps1 -DSDTPath .\DSDT.bin -DisableHPET -Install
    
.EXAMPLE
    .\Disable-HPET.ps1 -DSDTPath .\DSDT.bin -DisableHPET -StubGPE "_L69" -Install

.EXAMPLE
    .\Disable-HPET.ps1 -Uninstall
#>

param(
    [string]$DSDTPath,
    [switch]$ListHPET,
    [switch]$ListGPE,
    [switch]$DisableHPET,
    [switch]$HPETMinimal,
    [string]$StubGPE,
    [switch]$StubAllGPE,
    [switch]$Install,
    [switch]$Uninstall,
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"
$ScriptVersion = "2.1.0"

# ============================================================
# HELPERS
# ============================================================

function Write-Banner {
    Write-Host ""
    Write-Host "  ==========================================================" -ForegroundColor Cyan
    Write-Host "  ACPI Override Tool v$ScriptVersion — Full DSDT Replacement" -ForegroundColor Cyan
    Write-Host "  HPET Disabler + GPE Stubber via acpitabl.dat" -ForegroundColor Cyan
    Write-Host "  Works on Windows 10/11 — No bootloader required" -ForegroundColor Cyan
    Write-Host "  ==========================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Info  { param([string]$M) Write-Host "  [i] $M" -ForegroundColor Cyan }
function Write-Ok    { param([string]$M) Write-Host "  [+] $M" -ForegroundColor Green }
function Write-Warn  { param([string]$M) Write-Host "  [!] $M" -ForegroundColor Yellow }
function Write-Err   { param([string]$M) Write-Host "  [X] $M" -ForegroundColor Red }
function Write-Step  { param([string]$M) Write-Host "" ; Write-Host "  --- $M ---" -ForegroundColor White }

function Find-Pattern {
    param([byte[]]$Buf, [byte[]]$Pat, [int]$Start = 0)
    for ($i = $Start; $i -le ($Buf.Length - $Pat.Length); $i++) {
        $ok = $true
        for ($j = 0; $j -lt $Pat.Length; $j++) {
            if ($Buf[$i + $j] -ne $Pat[$j]) { $ok = $false; break }
        }
        if ($ok) { return $i }
    }
    return -1
}

function Find-AllPatterns {
    param([byte[]]$Buf, [byte[]]$Pat)
    $hits = @()
    $start = 0
    while ($true) {
        $idx = Find-Pattern -Buf $Buf -Pat $Pat -Start $start
        if ($idx -eq -1) { break }
        $hits += $idx
        $start = $idx + 1
    }
    return $hits
}

function Get-U32LE { param([byte[]]$B, [int]$O) return [BitConverter]::ToUInt32($B, $O) }

function Fix-ACPIChecksum {
    param([byte[]]$Data, [int]$TableLen)
    $Data[9] = 0
    $sum = 0
    for ($i = 0; $i -lt $TableLen; $i++) { $sum = ($sum + $Data[$i]) -band 0xFF }
    $Data[9] = ((-$sum) -band 0xFF)
}

function Verify-ACPIChecksum {
    param([byte[]]$Data, [int]$TableLen)
    $sum = 0
    for ($i = 0; $i -lt $TableLen; $i++) { $sum = ($sum + $Data[$i]) -band 0xFF }
    return $sum
}

# ============================================================
# DSDT LOADING
# ============================================================

function Get-DSDTFromRegistry {
    Write-Info "Extracting DSDT from registry..."
    $basePath = "HKLM:\HARDWARE\ACPI\DSDT"
    if (-not (Test-Path $basePath)) { throw "Registry path $basePath not found" }
    
    foreach ($oemKey in (Get-ChildItem $basePath)) {
        foreach ($tableKey in (Get-ChildItem $oemKey.PSPath -EA SilentlyContinue)) {
            foreach ($revKey in (Get-ChildItem $tableKey.PSPath -EA SilentlyContinue)) {
                $props = Get-ItemProperty $revKey.PSPath -EA SilentlyContinue
                foreach ($name in @("00000000", "(Default)")) {
                    try {
                        $val = $props.$name
                        if ($val -is [byte[]] -and $val.Length -gt 36) {
                            $sig = [System.Text.Encoding]::ASCII.GetString($val[0..3])
                            if ($sig -eq "DSDT") {
                                Write-Ok "Extracted DSDT from registry ($($val.Length) bytes)"
                                return $val
                            }
                        }
                    } catch {}
                }
            }
        }
    }
    throw "Could not find DSDT in registry"
}

function Get-DSDTBytes {
    param([string]$Path)
    if (-not [string]::IsNullOrEmpty($Path)) {
        if (-not (Test-Path $Path)) { throw "File not found: $Path" }
        $data = [System.IO.File]::ReadAllBytes($Path)
        $sig = [System.Text.Encoding]::ASCII.GetString($data[0..3])
        if ($sig -ne "DSDT") { throw "Not a DSDT (signature: '$sig')" }
        Write-Ok "Loaded DSDT from file ($($data.Length) bytes)"
        return $data
    }
    try { return Get-DSDTFromRegistry }
    catch {
        Write-Err "Could not auto-extract DSDT: $_"
        Write-Warn "Please provide a DSDT.bin file using -DSDTPath"
        Write-Warn "Extract with RWEverything: ACPI > Save DSDT as .bin"
        throw "No DSDT available"
    }
}

# ============================================================
# HPET PATCHING — BINARY LEVEL
# ============================================================

function Patch-HPETSta {
    param([byte[]]$D)
    
    # Strategy: Find HPET ASCII in a Device() context, then locate _STA
    # method nearby, find Return(0x0F) pattern [A4 0A 0F], change 0F->00.
    #
    # This is generic — works regardless of namespace path.
    
    $hpetASCII = [byte[]]@(0x48, 0x50, 0x45, 0x54)  # "HPET"
    $hpetHits = Find-AllPatterns -Buf $D -Pat $hpetASCII
    
    if ($hpetHits.Count -eq 0) { throw "No HPET device found in DSDT" }
    
    foreach ($hpetOff in $hpetHits) {
        # Look for _STA nearby (within ~128 bytes forward)
        $staPattern = [byte[]]@(0x5F, 0x53, 0x54, 0x41)
        $staOff = Find-Pattern -Buf $D -Pat $staPattern -Start $hpetOff
        
        if ($staOff -eq -1 -or ($staOff - $hpetOff) -gt 128) { continue }
        
        # Look for Return(0x0F) within ~32 bytes of _STA
        $ret0F = [byte[]]@(0xA4, 0x0A, 0x0F)
        $retOff = Find-Pattern -Buf $D -Pat $ret0F -Start $staOff
        
        if ($retOff -eq -1 -or ($retOff - $staOff) -gt 32) { continue }
        
        $patchOff = $retOff + 2  # offset of the 0x0F byte
        $D[$patchOff] = 0x00
        
        Write-Ok "Patched HPET._STA: Return(0x0F) -> Return(0x00) at 0x$($patchOff.ToString('X'))"
        return $patchOff
    }
    
    throw "Found HPET but could not locate Return(0x0F) in _STA"
}

function Patch-IfHPTE {
    param([byte[]]$D)
    
    # If(HPTE) in _STA: A0 08 48 50 54 45
    # Replace HPTE with Zero + Noops to preserve byte count
    $pat = [byte[]]@(0xA0, 0x08, 0x48, 0x50, 0x54, 0x45)
    $off = Find-Pattern -Buf $D -Pat $pat
    if ($off -eq -1) { return $false }
    
    $D[$off + 2] = 0x00  # Zero
    $D[$off + 3] = 0xA3  # Noop
    $D[$off + 4] = 0xA3  # Noop
    $D[$off + 5] = 0xA3  # Noop
    Write-Ok "Patched If(HPTE) -> If(Zero) at 0x$($off.ToString('X'))"
    return $true
}

function Patch-CRSIfHPTE {
    param([byte[]]$D)
    
    # _CRS If(HPTE): 43 52 53 08 A0 19 48 50 54 45
    $pat = [byte[]]@(0x43, 0x52, 0x53, 0x08, 0xA0, 0x19, 0x48, 0x50, 0x54, 0x45)
    $off = Find-Pattern -Buf $D -Pat $pat
    if ($off -eq -1) { return $false }
    
    $p = $off + 6
    $D[$p]     = 0x00
    $D[$p + 1] = 0xA3
    $D[$p + 2] = 0xA3
    $D[$p + 3] = 0xA3
    Write-Ok "Patched _CRS If(HPTE) -> If(Zero) at 0x$($off.ToString('X'))"
    return $true
}

function Patch-IfNotHPTE {
    param([byte[]]$D)
    
    # If(!HPTE): A0 xx 92 48 50 54 45
    # The xx byte varies by DSDT, so we search for the LNot(HPTE) part
    $lnotHPTE = [byte[]]@(0x92, 0x48, 0x50, 0x54, 0x45)
    $hits = Find-AllPatterns -Buf $D -Pat $lnotHPTE
    
    $patched = 0
    foreach ($hit in $hits) {
        # Check if preceded by If opcode (A0) within 2 bytes back
        if ($hit -ge 2 -and $D[$hit - 2] -eq 0xA0) {
            $p = $hit
            $D[$p]     = 0x00  # Replace LNot(HPTE) with Zero + Noops
            $D[$p + 1] = 0xA3
            $D[$p + 2] = 0xA3
            $D[$p + 3] = 0xA3
            $D[$p + 4] = 0xA3
            Write-Ok "Patched If(!HPTE) -> If(Zero) at 0x$(($hit - 2).ToString('X'))"
            $patched++
        }
    }
    return ($patched -gt 0)
}

# ============================================================
# GPE PATCHING
# ============================================================

function Find-GPEMethods {
    param([byte[]]$D)
    
    $methods = @()
    $methodOp = 0x14
    
    for ($i = 36; $i -lt ($D.Length - 8); $i++) {
        if ($D[$i] -ne $methodOp) { continue }
        
        $pkgOff = $i + 1
        $b0 = $D[$pkgOff]
        $follow = ($b0 -shr 6) -band 3
        
        if ($follow -eq 0) { $pkgLen = $b0 -band 0x3F; $pkgSize = 1 }
        else {
            $pkgLen = $b0 -band 0x0F
            for ($k = 1; $k -le $follow; $k++) {
                $pkgLen = $pkgLen -bor ($D[$pkgOff + $k] -shl (4 + 8*($k-1)))
            }
            $pkgSize = 1 + $follow
        }
        
        $nameOff = $pkgOff + $pkgSize
        if (($nameOff + 5) -ge $D.Length) { continue }
        
        $n = $D[$nameOff..($nameOff + 3)]
        
        # _Lxx or _Exx where xx = hex
        if ($n[0] -ne 0x5F) { continue }
        if ($n[1] -ne 0x4C -and $n[1] -ne 0x45) { continue }
        
        $validHex = $true
        for ($c = 2; $c -le 3; $c++) {
            $ch = $n[$c]
            if (-not (($ch -ge 0x30 -and $ch -le 0x39) -or ($ch -ge 0x41 -and $ch -le 0x46))) {
                $validHex = $false; break
            }
        }
        if (-not $validHex) { continue }
        
        $bodyOff = $nameOff + 5  # name(4) + flags(1)
        $endOff = $i + 1 + $pkgLen
        $bodyLen = $endOff - $bodyOff
        
        $methods += @{
            Name = [System.Text.Encoding]::ASCII.GetString($n)
            Offset = $i
            BodyOffset = $bodyOff
            BodyLength = $bodyLen
        }
    }
    return $methods
}

function Stub-GPEMethod {
    param([byte[]]$D, [int]$BodyOff, [int]$BodyLen)
    
    if ($BodyLen -lt 2) {
        $D[$BodyOff] = 0xA3  # Noop
        return
    }
    
    $D[$BodyOff]     = 0xA4  # ReturnOp
    $D[$BodyOff + 1] = 0x00  # Zero
    for ($k = $BodyOff + 2; $k -lt ($BodyOff + $BodyLen); $k++) {
        $D[$k] = 0xA3  # Noop
    }
}

# ============================================================
# INSTALL / UNINSTALL
# ============================================================

function Install-AcpiDat {
    param([string]$SourcePath)
    
    $target = "$env:SystemRoot\System32\acpitabl.dat"
    
    if (Test-Path $target) {
        $bak = "$env:SystemRoot\System32\acpitabl.dat.bak"
        Write-Warn "Existing acpitabl.dat found — backing up"
        Copy-Item $target $bak -Force
    }
    
    Copy-Item $SourcePath $target -Force
    $sz = (Get-Item $target).Length
    Write-Ok "Installed acpitabl.dat to System32 ($sz bytes)"
    
    Write-Info "Enabling test signing..."
    $r = & bcdedit /set testsigning on 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Failed: $r"
        Write-Warn "Disable Secure Boot in BIOS first, then re-run."
    } else {
        Write-Ok "Test signing enabled"
    }
}

function Uninstall-AcpiDat {
    Write-Step "Removing ACPI Override"
    
    $target = "$env:SystemRoot\System32\acpitabl.dat"
    if (Test-Path $target) {
        Remove-Item $target -Force
        Write-Ok "Removed acpitabl.dat"
    } else {
        Write-Warn "acpitabl.dat not found (already removed?)"
    }
    
    # Clean legacy registry override too
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\ACPI\Parameters"
    if (Test-Path $regPath) {
        $props = Get-ItemProperty $regPath -EA SilentlyContinue
        if ($null -ne $props.DSDT) {
            Remove-ItemProperty -Path $regPath -Name "DSDT" -Force -EA SilentlyContinue
            Write-Ok "Removed legacy DSDT registry override"
        }
        if ($null -ne $props.ACPIEnable) {
            Remove-ItemProperty -Path $regPath -Name "ACPIEnable" -Force -EA SilentlyContinue
        }
    }
    
    Write-Info "Disabling test signing..."
    & bcdedit /set testsigning off 2>&1 | Out-Null
    Write-Ok "Test signing disabled"
    
    Write-Ok "Done — reboot to restore original DSDT."
}

# ============================================================
# MAIN
# ============================================================

Write-Banner

if ($Uninstall) { Uninstall-AcpiDat; exit 0 }

# Show help if no actions
if (-not $DisableHPET -and -not $ListGPE -and -not $ListHPET -and 
    [string]::IsNullOrEmpty($StubGPE) -and -not $StubAllGPE) {
    Write-Host "  Usage:" -ForegroundColor White
    Write-Host ""
    Write-Host "    .\Disable-HPET.ps1 -DSDTPath .\DSDT.bin -ListHPET" -ForegroundColor Yellow
    Write-Host "    .\Disable-HPET.ps1 -DSDTPath .\DSDT.bin -ListGPE" -ForegroundColor Yellow
    Write-Host "    .\Disable-HPET.ps1 -DSDTPath .\DSDT.bin -DisableHPET -Install" -ForegroundColor Yellow
    Write-Host '    .\Disable-HPET.ps1 -DSDTPath .\DSDT.bin -DisableHPET -StubGPE "_L69" -Install' -ForegroundColor Yellow
    Write-Host "    .\Disable-HPET.ps1 -Uninstall" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  If -DSDTPath is omitted, DSDT is extracted from registry." -ForegroundColor Gray
    Write-Host ""
    exit 0
}

# Load DSDT
Write-Step "Loading DSDT"
try { $dsdt = [byte[]](Get-DSDTBytes -Path $DSDTPath) }
catch { Write-Err $_; exit 1 }

$tableLen = Get-U32LE -B $dsdt -O 4
$oemId = [System.Text.Encoding]::ASCII.GetString($dsdt[10..15]).Trim("`0"," ")
$tableId = [System.Text.Encoding]::ASCII.GetString($dsdt[16..23]).Trim("`0"," ")
$chkOk = (Verify-ACPIChecksum -Data $dsdt -TableLen $tableLen) -eq 0
Write-Info "OEM: $oemId / $tableId ($tableLen bytes, checksum: $(if($chkOk){'OK'}else{'INVALID'}))"

if (-not $chkOk) {
    Write-Warn "Original DSDT checksum is invalid — patching anyway"
}

# ---- LIST modes ----

if ($ListHPET) {
    Write-Step "HPET Scan Results"
    
    $hpetHits = Find-AllPatterns -Buf $dsdt -Pat ([byte[]]@(0x48, 0x50, 0x45, 0x54))
    Write-Host "  HPET references: $($hpetHits.Count)" -ForegroundColor Cyan
    foreach ($h in ($hpetHits | Select-Object -First 8)) {
        $ctx = $dsdt[([Math]::Max(0,$h-8))..([Math]::Min($dsdt.Length-1,$h+16))]
        $hex = ($ctx | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
        Write-Host "    0x$($h.ToString('X5')): $hex" -ForegroundColor Gray
    }
    
    $ret0F = Find-AllPatterns -Buf $dsdt -Pat ([byte[]]@(0xA4, 0x0A, 0x0F))
    Write-Host "  Return(0x0F) patterns: $($ret0F.Count)" -ForegroundColor Cyan
    
    $ifHPTE = Find-AllPatterns -Buf $dsdt -Pat ([byte[]]@(0xA0, 0x08, 0x48, 0x50, 0x54, 0x45))
    Write-Host "  If(HPTE) patterns: $($ifHPTE.Count)" -ForegroundColor Cyan
    
    $lnotHPTE = Find-AllPatterns -Buf $dsdt -Pat ([byte[]]@(0x92, 0x48, 0x50, 0x54, 0x45))
    Write-Host "  LNot(HPTE) patterns: $($lnotHPTE.Count)" -ForegroundColor Cyan
    
    Write-Host ""
    exit 0
}

if ($ListGPE) {
    Write-Step "GPE Handler Scan"
    $gpe = Find-GPEMethods -D $dsdt
    if ($gpe.Count -eq 0) {
        Write-Warn "No _Lxx/_Exx methods found"
    } else {
        Write-Ok "Found $($gpe.Count) GPE handler(s):"
        foreach ($m in $gpe) {
            $type = if ($m.Name[1] -eq 'L') {"Level"} else {"Edge"}
            Write-Host "    $($m.Name)  ($type, $($m.BodyLength) bytes)" -ForegroundColor Cyan
        }
    }
    Write-Host ""
    exit 0
}

# ---- PATCH mode ----

$patchCount = 0

if ($DisableHPET) {
    Write-Step "Patching HPET"
    
    try {
        Patch-HPETSta -D $dsdt
        $patchCount++
    } catch {
        Write-Err "HPET._STA patch failed: $_"
        exit 1
    }
    
    if (-not $HPETMinimal) {
        # These are optional hardening patches — warn but don't fail
        if (Patch-IfHPTE -D $dsdt) { $patchCount++ }
        else { Write-Warn "If(HPTE) pattern not found (may not exist on this board)" }
        
        if (Patch-CRSIfHPTE -D $dsdt) { $patchCount++ }
        else { Write-Warn "_CRS If(HPTE) pattern not found" }
        
        if (Patch-IfNotHPTE -D $dsdt) { $patchCount++ }
        else { Write-Warn "If(!HPTE) pattern not found" }
    } else {
        Write-Info "Minimal mode: only _STA return value patched"
    }
}

if ($StubAllGPE -or -not [string]::IsNullOrEmpty($StubGPE)) {
    Write-Step "Patching GPE Handlers"
    
    $gpe = Find-GPEMethods -D $dsdt
    
    $targets = @()
    if ($StubAllGPE) {
        $targets = $gpe
    } else {
        $names = $StubGPE.Split(',') | ForEach-Object { $_.Trim() }
        foreach ($n in $names) {
            $found = $gpe | Where-Object { $_.Name -eq $n }
            if ($found) { $targets += $found }
            else { Write-Warn "GPE handler '$n' not found in DSDT" }
        }
    }
    
    foreach ($t in $targets) {
        if ($t.BodyLength -gt 0) {
            Stub-GPEMethod -D $dsdt -BodyOff $t.BodyOffset -BodyLen $t.BodyLength
            Write-Ok "Stubbed $($t.Name) ($($t.BodyLength) bytes -> Return Zero)"
            $patchCount++
        }
    }
    
    if ($targets.Count -gt 0) {
        Write-Warn "GPE stubbing can break thermal, battery, lid, and sleep features."
    }
}

if ($patchCount -eq 0) {
    Write-Warn "No patches were applied."
    exit 0
}

# Fix checksum
Fix-ACPIChecksum -Data $dsdt -TableLen $tableLen
$verify = Verify-ACPIChecksum -Data $dsdt -TableLen $tableLen
Write-Ok "Applied $patchCount patch(es), new checksum: 0x$($dsdt[9].ToString('X2')) (verify: 0x$($verify.ToString('X2')))"

if ($verify -ne 0) {
    Write-Err "CHECKSUM MISMATCH — this should not happen. Aborting."
    exit 1
}

# Save output
if ([string]::IsNullOrEmpty($OutputPath)) {
    $OutputPath = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) "acpitabl.dat"
    # Fallback to current directory
    if ([string]::IsNullOrEmpty((Split-Path $MyInvocation.MyCommand.Path -Parent))) {
        $OutputPath = Join-Path (Get-Location) "acpitabl.dat"
    }
}

[System.IO.File]::WriteAllBytes($OutputPath, $dsdt)
Write-Ok "Saved patched DSDT as: $OutputPath ($($dsdt.Length) bytes)"

# Install
if ($Install) {
    Write-Step "Installing to System32"
    Install-AcpiDat -SourcePath $OutputPath
    
    Write-Host ""
    Write-Host "  ==========================================================" -ForegroundColor Green
    Write-Host "  DONE — REBOOT NOW" -ForegroundColor Green
    Write-Host "  ==========================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  After reboot:" -ForegroundColor Cyan
    Write-Host "    - 'Test Mode' watermark is expected" -ForegroundColor Cyan
    if ($DisableHPET) {
        Write-Host "    - Device Manager > System Devices > HPET: error or missing" -ForegroundColor Cyan
    }
    Write-Host "    - Use LatencyMon to verify improvement" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  To undo:  .\Disable-HPET.ps1 -Uninstall  (then reboot)" -ForegroundColor Yellow
    Write-Host ""
    
    $r = Read-Host "  Reboot now? (Y/N)"
    if ($r -eq 'Y' -or $r -eq 'y') {
        Write-Info "Rebooting in 5 seconds..."
        Start-Sleep 5
        Restart-Computer -Force
    } else {
        Write-Info "Remember to reboot manually."
    }
} else {
    Write-Host ""
    Write-Info "Patched DSDT saved but NOT installed."
    Write-Info "To install: re-run with -Install, or manually:"
    Write-Host "    copy `"$OutputPath`" `"$env:SystemRoot\System32\acpitabl.dat`"" -ForegroundColor Yellow
    Write-Host "    bcdedit /set testsigning on" -ForegroundColor Yellow
    Write-Host "    :: reboot" -ForegroundColor Yellow
    Write-Host ""
}
