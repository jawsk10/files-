/**
 * qpc_patch.js - Auto-detecting QPC Frequency Patcher
 * Automatically detects CPU frequency and patches KeQueryPerformanceCounter
 * 
 * Usage:
 *   .scriptload path\to\qpc_patch.js
 *   dx @$scriptContents.autoPatchQPC()        <- Automatic detection and patch
 *   dx @$scriptContents.patchQPC(4900000000)  <- Manual frequency override
 *   dx @$scriptContents.verifyQPC()           <- Verify patch
 */

"use strict";

function initializeScript() {
    return [
        new host.apiVersionSupport(1, 3),
        new host.functionAlias(autoPatchQPC, "autopatchqpc"),
        new host.functionAlias(patchQPC, "patchqpc"),
        new host.functionAlias(verifyQPC, "verifyqpc")
    ];
}

/**
 * Executes a WinDbg command and returns the output
 */
function executeCommand(command) {
    try {
        return host.namespace.Debugger.Utility.Control.ExecuteCommand(command);
    } catch (e) {
        throw new Error(`Command execution failed: ${command} - ${e.message}`);
    }
}

/**
 * Detects the CPU frequency from the system
 */
function detectCPUFrequency() {
    host.diagnostics.debugLog("[*] Detecting CPU frequency...\n");
    
    try {
        // Method 1: Try to read from KeQueryPerformanceCounter's current frequency
        let qpcResult = executeCommand("? poi(nt!KiCyclesPerClockQuantum)");
        host.diagnostics.debugLog(`[*] Checking KiCyclesPerClockQuantum: ${qpcResult}\n`);
        
        // Method 2: Read TSC frequency from processor info
        let tscResult = executeCommand("!cpuinfo");
        host.diagnostics.debugLog(`[*] CPU Info:\n${tscResult}\n`);
        
        // Method 3: Try reading from KeQueryPerformanceCounter directly
        let freqCheck = executeCommand("? nt!KeQueryPerformanceCounter");
        
        // Method 4: Check registry or ACPI for CPU speed
        let cpuSpeedResult = executeCommand("r $t0 = poi(nt!KeMaximumIncrement); ? @$t0");
        
        // Method 5: Most reliable - read from HalpPerformanceCounter
        try {
            let halpResult = executeCommand("dq nt!HalpPerformanceCounter L1");
            host.diagnostics.debugLog(`[*] HalpPerformanceCounter: ${halpResult}\n`);
        } catch (e) {
            host.diagnostics.debugLog(`[*] HalpPerformanceCounter not accessible: ${e.message}\n`);
        }
        
        // Try to parse TSC frequency from CPU info
        let freqMatch = tscResult.match(/(\d+)\s*MHz|(\d+\.\d+)\s*GHz/i);
        if (freqMatch) {
            let frequency;
            if (freqMatch[1]) {
                // MHz format
                frequency = parseInt(freqMatch[1]) * 1000000;
            } else if (freqMatch[2]) {
                // GHz format
                frequency = parseFloat(freqMatch[2]) * 1000000000;
            }
            
            if (frequency > 1000000000) { // Sanity check: > 1 GHz
                host.diagnostics.debugLog(`[✔] Detected CPU frequency: ${frequency} Hz (${(frequency / 1000000000).toFixed(2)} GHz)\n`);
                return frequency;
            }
        }
        
        // If detection fails, try reading CPUID
        try {
            let cpuidResult = executeCommand("!cpuid 0x15");
            host.diagnostics.debugLog(`[*] CPUID TSC info: ${cpuidResult}\n`);
        } catch (e) {
            // CPUID might not be available
        }
        
    } catch (error) {
        host.diagnostics.debugLog(`[!] Auto-detection error: ${error.message}\n`);
    }
    
    // If all detection methods fail, return null
    host.diagnostics.debugLog("[!] Could not auto-detect CPU frequency\n");
    host.diagnostics.debugLog("[*] Common frequencies:\n");
    host.diagnostics.debugLog("    4.0 GHz = 4000000000 Hz\n");
    host.diagnostics.debugLog("    4.5 GHz = 4500000000 Hz\n");
    host.diagnostics.debugLog("    4.9 GHz = 4900000000 Hz\n");
    host.diagnostics.debugLog("    5.0 GHz = 5000000000 Hz\n");
    host.diagnostics.debugLog("    5.5 GHz = 5500000000 Hz\n");
    host.diagnostics.debugLog("[*] Please use: dx @$scriptContents.patchQPC(YOUR_FREQUENCY_IN_HZ)\n");
    
    return null;
}

/**
 * Automatically detects CPU frequency and applies patch
 */
function autoPatchQPC() {
    host.diagnostics.debugLog("============================================================\n");
    host.diagnostics.debugLog(" Auto-Detecting QPC Frequency Patcher\n");
    host.diagnostics.debugLog("============================================================\n\n");
    
    let frequency = detectCPUFrequency();
    
    if (frequency === null) {
        host.diagnostics.debugLog("\n[!] Auto-detection failed. Please specify frequency manually:\n");
        host.diagnostics.debugLog("    dx @$scriptContents.patchQPC(4900000000)  // For 4.9 GHz\n");
        return false;
    }
    
    host.diagnostics.debugLog("\n[*] Proceeding with detected frequency...\n\n");
    return patchQPC(frequency);
}

/**
 * Converts a frequency value to little-endian hex bytes
 */
function frequencyToBytes(frequency) {
    let bytes = [];
    let value = frequency;
    
    for (let i = 0; i < 8; i++) {
        bytes.push((value & 0xFF).toString(16).padStart(2, '0'));
        value = Math.floor(value / 256);
    }
    
    return bytes;
}

/**
 * Patches KeQueryPerformanceCounter to report custom frequency
 * @param {number} cpuFrequency - CPU frequency in Hz (e.g., 4900000000 for 4.9 GHz)
 */
function patchQPC(cpuFrequency) {
    if (!cpuFrequency || cpuFrequency < 1000000) {
        host.diagnostics.debugLog("[!] Error: Invalid frequency. Please provide frequency in Hz (e.g., 4900000000 for 4.9 GHz)\n");
        return false;
    }

    host.diagnostics.debugLog("============================================================\n");
    host.diagnostics.debugLog(" QueryPerformanceCounter Frequency Patcher\n");
    host.diagnostics.debugLog(" WARNING: Experimental kernel modification!\n");
    host.diagnostics.debugLog("============================================================\n");
    host.diagnostics.debugLog(`[*] Target frequency: ${cpuFrequency} Hz (${(cpuFrequency / 1000000000).toFixed(2)} GHz)\n`);
    
    try {
        // Show original function
        host.diagnostics.debugLog("\n[*] Original KeQueryPerformanceCounter:\n");
        try {
            let originalFunc = executeCommand("u nt!KeQueryPerformanceCounter L8");
            host.diagnostics.debugLog(originalFunc + "\n");
        } catch (e) {
            host.diagnostics.debugLog("[*] Could not disassemble original function\n");
        }
        
        // Convert frequency to little-endian bytes
        let freqBytes = frequencyToBytes(cpuFrequency);
        host.diagnostics.debugLog(`[*] Frequency in hex: 0x${cpuFrequency.toString(16).toUpperCase()}\n`);
        host.diagnostics.debugLog(`[*] Little-endian bytes: ${freqBytes.join(' ').toUpperCase()}\n\n`);
        
        // Build the patch
        // Assembly for TSC-based QPC with custom frequency:
        // 0F 31                rdtsc                    ; Read TSC into EDX:EAX
        // 48 C1 E2 20          shl rdx, 20h            ; Shift high part left
        // 48 09 D0             or rax, rdx             ; Combine into RAX (full 64-bit TSC)
        // 48 85 C9             test rcx, rcx           ; Check if frequency pointer provided
        // 74 0C                jz short +12            ; Skip if NULL
        // 48 B8 XX XX XX XX XX mov rax, FREQUENCY      ; Load frequency into RAX
        // 48 89 01             mov [rcx], rax          ; Store frequency at pointer
        // C3                   ret                     ; Return
        
        let patchBytes = [
            "0F", "31",                             // rdtsc
            "48", "C1", "E2", "20",                // shl rdx, 20h
            "48", "09", "D0",                      // or rax, rdx
            "48", "85", "C9",                      // test rcx, rcx
            "74", "0C",                            // jz short +12
            "48", "B8", ...freqBytes,              // movabs rax, FREQUENCY (8 bytes)
            "48", "89", "01",                      // mov [rcx], rax
            "C3"                                    // ret
        ];
        
        let patchString = patchBytes.join(' ');
        host.diagnostics.debugLog("[*] Patch bytes (" + patchBytes.length + " bytes): " + patchString.toUpperCase() + "\n");
        
        // Apply the patch
        host.diagnostics.debugLog("\n[*] Applying patch...\n");
        let patchCommand = `eb nt!KeQueryPerformanceCounter ${patchString}`;
        executeCommand(patchCommand);
        
        host.diagnostics.debugLog("[✔] Patch applied successfully!\n\n");
        
        // Verify the patch
        host.diagnostics.debugLog("[*] Verifying patched function:\n");
        let patchedFunc = executeCommand("u nt!KeQueryPerformanceCounter L10");
        host.diagnostics.debugLog(patchedFunc + "\n");
        
        host.diagnostics.debugLog("\n[*] Memory dump:\n");
        let memDump = executeCommand("db nt!KeQueryPerformanceCounter L20");
        host.diagnostics.debugLog(memDump + "\n");
        
        // Check if patch was successful
        if (memDump.toLowerCase().includes('0f 31')) {
            host.diagnostics.debugLog("\n[✔] Verification: Patch starts with RDTSC instruction\n");
        }
        
        host.diagnostics.debugLog("============================================================\n");
        host.diagnostics.debugLog("[✔] QPC frequency patch complete!\n");
        host.diagnostics.debugLog(`[*] QueryPerformanceCounter will now report ${(cpuFrequency / 1000000000).toFixed(2)} GHz\n`);
        host.diagnostics.debugLog("[!] Remember: This patch is temporary and resets on reboot\n");
        host.diagnostics.debugLog("============================================================\n");
        
        return true;
        
    } catch (error) {
        host.diagnostics.debugLog(`[!] Failed to patch QPC. Error: ${error.message}\n`);
        host.diagnostics.debugLog("[*] Make sure you have write access to kernel memory\n");
        return false;
    }
}

/**
 * Verifies the current QPC patch status
 */
function verifyQPC() {
    host.diagnostics.debugLog("============================================================\n");
    host.diagnostics.debugLog(" QPC Patch Verification\n");
    host.diagnostics.debugLog("============================================================\n");
    
    try {
        // Show current function
        host.diagnostics.debugLog("[*] Current KeQueryPerformanceCounter:\n");
        let currentFunc = executeCommand("u nt!KeQueryPerformanceCounter L10");
        host.diagnostics.debugLog(currentFunc + "\n");
        
        // Check memory
        host.diagnostics.debugLog("\n[*] Memory dump:\n");
        let memDump = executeCommand("db nt!KeQueryPerformanceCounter L20");
        host.diagnostics.debugLog(memDump + "\n");
        
        // Check if patched
        if (memDump.toLowerCase().includes('0f 31')) {
            host.diagnostics.debugLog("\n[✔] QPC appears to be patched (starts with RDTSC)\n");
            
            // Try to extract the frequency from the patch
            try {
                let bytes = memDump.match(/[0-9a-f]{2}/gi);
                if (bytes && bytes.length >= 22) {
                    // Frequency bytes start at offset 14 (after the movabs rax instruction prefix)
                    let freqBytes = bytes.slice(14, 22);
                    // Convert little-endian to frequency
                    let frequency = 0;
                    for (let i = 0; i < 8; i++) {
                        frequency += parseInt(freqBytes[i], 16) * Math.pow(256, i);
                    }
                    host.diagnostics.debugLog(`[*] Detected frequency in patch: ${frequency} Hz (${(frequency / 1000000000).toFixed(2)} GHz)\n`);
                }
            } catch (e) {
                host.diagnostics.debugLog("[*] Could not extract frequency from patch\n");
            }
        } else {
            host.diagnostics.debugLog("\n[!] QPC does not appear to be patched (original code present)\n");
        }
        
        host.diagnostics.debugLog("============================================================\n");
        
    } catch (error) {
        host.diagnostics.debugLog(`[!] Verification failed: ${error.message}\n`);
    }
}

/**
 * Show usage information
 */
function showHelp() {
    host.diagnostics.debugLog("============================================================\n");
    host.diagnostics.debugLog(" QPC Frequency Patcher - Usage\n");
    host.diagnostics.debugLog("============================================================\n");
    host.diagnostics.debugLog("AUTOMATIC (Recommended):\n");
    host.diagnostics.debugLog("  dx @$scriptContents.autoPatchQPC()         - Auto-detect and patch\n\n");
    host.diagnostics.debugLog("MANUAL:\n");
    host.diagnostics.debugLog("  dx @$scriptContents.patchQPC(4900000000)   - Patch for 4.9 GHz\n");
    host.diagnostics.debugLog("  dx @$scriptContents.patchQPC(5200000000)   - Patch for 5.2 GHz\n\n");
    host.diagnostics.debugLog("VERIFY:\n");
    host.diagnostics.debugLog("  dx @$scriptContents.verifyQPC()            - Check patch status\n\n");
    host.diagnostics.debugLog("Common CPU frequencies:\n");
    host.diagnostics.debugLog("  4.0 GHz = 4000000000 Hz\n");
    host.diagnostics.debugLog("  4.5 GHz = 4500000000 Hz\n");
    host.diagnostics.debugLog("  4.9 GHz = 4900000000 Hz\n");
    host.diagnostics.debugLog("  5.0 GHz = 5000000000 Hz\n");
    host.diagnostics.debugLog("  5.5 GHz = 5500000000 Hz\n");
    host.diagnostics.debugLog("  6.0 GHz = 6000000000 Hz\n");
    host.diagnostics.debugLog("============================================================\n");
}

// Export functions
class QPCPatchScript {
    get autoPatchQPC() { return autoPatchQPC; }
    get patchQPC() { return patchQPC; }
    get verifyQPC() { return verifyQPC; }
    get showHelp() { return showHelp; }
}

function invokeScript() {
    return new QPCPatchScript();
}