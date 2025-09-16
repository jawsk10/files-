/**
 * patch.js - Function patcher for WinDbg
 * Patches kernel functions with RET (C3) instructions
 * 
 * Usage:
 *   .scriptload path\to\patch.js
 *   dx @$scriptContents.patchFunction("nt!FunctionName")     <- patch one function
 *   dx @$scriptContents.patchBatch()                         <- patch all functions in batch list
 */

"use strict";

function initializeScript() {
    return [
        new host.apiVersionSupport(1, 3),
        new host.functionAlias(patchFunction, "patch"),
        new host.functionAlias(patchBatch, "patchbatch")
    ];
}

// List of functions to patch in batch mode
const BATCH_FUNCTIONS = [
    "nt!KeBalanceSetManager",
    "nt!KiCheckForKernelApcDelivery", 
    "nt!PspSetContext",
    "nt!KiSystemServiceHandler",
    "nt!KeRemoveQueueEx",
    "nt!KeInsertQueue",
    "nt!KiDispatchInterrupt",
    "nt!KiInterruptDispatch",
    "nt!NtQuerySystemInformation"
];

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
 * Gets the address of a symbol
 */
function getSymbolAddress(symbolName) {
    try {
        // Try to resolve the symbol address
        let result = executeCommand(`? ${symbolName}`);
        
        // Look for address in various formats
        let addressMatch = result.match(/Evaluate expression: (\d+) = ([0-9a-fA-F`]+)/);
        if (addressMatch) {
            return addressMatch[2].replace(/`/g, ''); // Remove backticks
        }
        
        // Alternative format
        addressMatch = result.match(/([0-9a-fA-F`]+)/);
        if (addressMatch) {
            return addressMatch[1].replace(/`/g, '');
        }
        
        throw new Error("Could not parse symbol address");
    } catch (e) {
        throw new Error(`Symbol resolution failed: ${e.message}`);
    }
}

/**
 * Gets function size using disassembly approach
 */
function getFunctionSize(functionName) {
    try {
        // First, try to get function bounds using uf command
        let ufResult = executeCommand(`uf ${functionName}`);
        
        // If uf works, try to extract the range
        let lines = ufResult.split('\n');
        let addresses = [];
        
        for (let line of lines) {
            // Look for address patterns in disassembly
            let addrMatch = line.match(/^([0-9a-fA-F`]+)/);
            if (addrMatch) {
                addresses.push(addrMatch[1].replace(/`/g, ''));
            }
        }
        
        if (addresses.length >= 2) {
            let startAddr = parseInt(addresses[0], 16);
            let endAddr = parseInt(addresses[addresses.length - 1], 16);
            return Math.max(endAddr - startAddr + 16, 16); // Add some padding
        }
        
        // Fallback: use a reasonable default size
        host.diagnostics.debugLog(`[*] Using default size for ${functionName}\n`);
        return 32; // Default 32 bytes
        
    } catch (e) {
        host.diagnostics.debugLog(`[*] Size detection failed, using default: ${e.message}\n`);
        return 32;
    }
}

/**
 * Patches a single function with RET instructions
 * @param {string} functionName - The function name to patch (e.g., "nt!FunctionName")
 */
function patchFunction(functionName) {
    if (!functionName) {
        host.diagnostics.debugLog("[!] Error: Function name is required\n");
        return false;
    }

    host.diagnostics.debugLog(`[*] Single patch mode for: ${functionName}\n`);
    
    try {
        // First, verify the symbol exists
        let address = getSymbolAddress(functionName);
        host.diagnostics.debugLog(`[*] Function address: ${address}\n`);
        
        // Get function size
        let size = getFunctionSize(functionName);
        host.diagnostics.debugLog(`[*] Function size = ${size} bytes\n`);
        
        // Convert size to hex for the fill command
        let sizeHex = size.toString(16);
        
        // Patch the function with RET instructions (C3)
        let patchCommand = `f ${functionName} L${sizeHex} C3`;
        host.diagnostics.debugLog(`[*] Executing: ${patchCommand}\n`);
        
        executeCommand(patchCommand);
        host.diagnostics.debugLog(`[✔] Patched ${functionName} with RET instructions.\n`);
        
        // Verify the patch by reading back the first few bytes
        try {
            let verifyResult = executeCommand(`db ${functionName} L4`);
            if (verifyResult.includes('c3')) {
                host.diagnostics.debugLog(`[✔] Patch verification successful\n`);
            }
        } catch (verifyError) {
            host.diagnostics.debugLog(`[*] Could not verify patch: ${verifyError.message}\n`);
        }
        
        return true;
        
    } catch (error) {
        host.diagnostics.debugLog(`[!] Failed to patch ${functionName}. Error: ${error.message}\n`);
        
        // Try alternative approaches
        try {
            host.diagnostics.debugLog(`[*] Trying alternative approach...\n`);
            
            // Simple approach: try to patch first 16 bytes
            let simplePatchCommand = `eb ${functionName} c3`;
            executeCommand(simplePatchCommand);
            host.diagnostics.debugLog(`[✔] Simple patch applied to ${functionName}\n`);
            return true;
            
        } catch (altError) {
            host.diagnostics.debugLog(`[!] Alternative patch failed: ${altError.message}\n`);
            host.diagnostics.debugLog("[!] Possibly invalid symbol, insufficient permissions, or function not accessible.\n");
            return false;
        }
    }
}

/**
 * Patches all functions in the batch list
 */
function patchBatch() {
    host.diagnostics.debugLog("[*] Batch patch mode activated.\n");
    host.diagnostics.debugLog("[*] Patching all functions in list...\n");
    
    let successCount = 0;
    let failureCount = 0;
    
    for (let functionName of BATCH_FUNCTIONS) {
        host.diagnostics.debugLog("------------------------------------------------------------\n");
        host.diagnostics.debugLog(`[*] Attempting to patch: ${functionName}\n`);
        
        if (patchFunction(functionName)) {
            successCount++;
        } else {
            failureCount++;
        }
        
        // Small delay to prevent overwhelming the debugger
        try {
            executeCommand(".sleep 100");
        } catch (e) {
            // Sleep command might not be available, ignore
        }
    }
    
    host.diagnostics.debugLog("------------------------------------------------------------\n");
    host.diagnostics.debugLog(`[✓] Batch patch complete. Success: ${successCount}, Failed: ${failureCount}\n`);
    host.diagnostics.debugLog("------------------------------------------------------------\n");
    
    return { success: successCount, failed: failureCount };
}

/**
 * Test function to verify script is working
 */
function testScript() {
    host.diagnostics.debugLog("[*] Testing script functionality...\n");
    
    try {
        let result = executeCommand("? 1+1");
        host.diagnostics.debugLog(`[✔] Command execution test passed: ${result}\n`);
        
        // Test symbol resolution with a common kernel symbol
        try {
            let kernelBase = getSymbolAddress("nt");
            host.diagnostics.debugLog(`[✔] Symbol resolution test passed. nt base: ${kernelBase}\n`);
        } catch (e) {
            host.diagnostics.debugLog(`[!] Symbol resolution test failed: ${e.message}\n`);
        }
        
        return true;
    } catch (e) {
        host.diagnostics.debugLog(`[!] Script test failed: ${e.message}\n`);
        return false;
    }
}

/**
 * Helper function to list all available functions
 */
function listFunctions() {
    host.diagnostics.debugLog("Available functions:\n");
    host.diagnostics.debugLog("- patchFunction(functionName): Patch a single function\n");
    host.diagnostics.debugLog("- patchBatch(): Patch all functions in batch list\n");
    host.diagnostics.debugLog("- listBatchFunctions(): Show functions in batch list\n");
    host.diagnostics.debugLog("- testScript(): Test script functionality\n");
}

/**
 * Lists all functions that will be patched in batch mode
 */
function listBatchFunctions() {
    host.diagnostics.debugLog("Functions in batch list:\n");
    for (let i = 0; i < BATCH_FUNCTIONS.length; i++) {
        host.diagnostics.debugLog(`${i + 1}. ${BATCH_FUNCTIONS[i]}\n`);
    }
}

// Export functions for use in WinDbg
class PatchScript {
    get patchFunction() { return patchFunction; }
    get patchBatch() { return patchBatch; }
    get listFunctions() { return listFunctions; }
    get listBatchFunctions() { return listBatchFunctions; }
    get testScript() { return testScript; }
}

// Make functions available through the script contents
function invokeScript() {
    return new PatchScript();
}