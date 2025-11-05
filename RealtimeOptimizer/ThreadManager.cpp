#include "ThreadManager.h"
#include <psapi.h>
#include <iostream>
#include <unordered_map>
#include <algorithm>

#pragma comment(lib, "ntdll.lib")
#pragma comment(lib, "psapi.lib")

// CooldownTracker implementation
bool CooldownTracker::CanApplyThreadBoost(DWORD threadId) {
    auto now = std::chrono::steady_clock::now();
    auto it = threadBoostCooldowns.find(threadId);
    if (it == threadBoostCooldowns.end()) {
        threadBoostCooldowns[threadId] = now;
        return true;
    }
    auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(now - it->second).count();
    if (elapsed >= 300) { // 300 second cooldown
        threadBoostCooldowns[threadId] = now;
        return true;
    }
    return false;
}

bool CooldownTracker::CanApplyThreadSuspend(DWORD threadId) {
    auto now = std::chrono::steady_clock::now();
    auto it = threadSuspendCooldowns.find(threadId);
    if (it == threadSuspendCooldowns.end()) {
        threadSuspendCooldowns[threadId] = now;
        return true;
    }
    auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(now - it->second).count();
    if (elapsed >= 40) { // 40 second cooldown
        threadSuspendCooldowns[threadId] = now;
        return true;
    }
    return false;
}

bool CooldownTracker::CanApplyProcessBoost(DWORD processId) {
    auto now = std::chrono::steady_clock::now();
    auto it = processBoostCooldowns.find(processId);
    if (it == processBoostCooldowns.end()) {
        processBoostCooldowns[processId] = now;
        return true;
    }
    auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(now - it->second).count();
    if (elapsed >= 30) { // 30 second cooldown
        processBoostCooldowns[processId] = now;
        return true;
    }
    return false;
}

// ThreadManager implementation
ThreadManager::ThreadManager() {
    HMODULE ntdll = GetModuleHandleA("ntdll.dll");
    if (ntdll) {
        ntQueryInformationThread_ = (NtQueryInformationThreadFunc)GetProcAddress(ntdll, "NtQueryInformationThread");
        ntSetInformationThread_ = (NtSetInformationThreadFunc)GetProcAddress(ntdll, "NtSetInformationThread");
    }
}

std::vector<ThreadInfo> ThreadManager::EnumerateProcessThreads(const std::string& processName) {
    std::vector<ThreadInfo> threads;
    
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (snapshot == INVALID_HANDLE_VALUE) {
        return threads;
    }
    
    THREADENTRY32 te32;
    te32.dwSize = sizeof(THREADENTRY32);
    
    if (!Thread32First(snapshot, &te32)) {
        CloseHandle(snapshot);
        return threads;
    }
    
    do {
        std::string threadProcessName = GetProcessName(te32.th32OwnerProcessID);
        
        if (_stricmp(threadProcessName.c_str(), processName.c_str()) != 0) {
            continue;
        }
        
        HANDLE hThread = OpenThread(THREAD_QUERY_INFORMATION, FALSE, te32.th32ThreadID);
        if (!hThread) {
            continue;
        }
        
        ThreadInfo info;
        info.threadId = te32.th32ThreadID;
        info.processId = te32.th32OwnerProcessID;
        info.processName = threadProcessName;
        info.startAddress = nullptr;
        info.currentPriority = GetThreadPriority(hThread);
        
        // Get thread start address
        if (ntQueryInformationThread_) {
            PVOID startAddr = nullptr;
            ULONG returnLength = 0;
            LONG status = ntQueryInformationThread_(
                hThread,
                9, // ThreadQuerySetWin32StartAddress
                &startAddr,
                sizeof(startAddr),
                &returnLength
            );
            
            if (status == 0) {
                info.startAddress = startAddr;
                info.moduleName = GetModuleNameForAddress(te32.th32OwnerProcessID, startAddr);
            }
        }
        
        // Get thread description
        PWSTR description = nullptr;
        typedef HRESULT(WINAPI* GetThreadDescriptionFunc)(HANDLE, PWSTR*);
        static GetThreadDescriptionFunc GetThreadDescriptionPtr = nullptr;
        
        if (!GetThreadDescriptionPtr) {
            HMODULE kernel32 = GetModuleHandleA("kernel32.dll");
            GetThreadDescriptionPtr = (GetThreadDescriptionFunc)GetProcAddress(kernel32, "GetThreadDescription");
        }
        
        if (GetThreadDescriptionPtr) {
            if (SUCCEEDED(GetThreadDescriptionPtr(hThread, &description))) {
                if (description && wcslen(description) > 0) {
                    int size = WideCharToMultiByte(CP_UTF8, 0, description, -1, nullptr, 0, nullptr, nullptr);
                    if (size > 0) {
                        std::vector<char> buffer(size);
                        WideCharToMultiByte(CP_UTF8, 0, description, -1, buffer.data(), size, nullptr, nullptr);
                        info.threadDesc = buffer.data();
                    }
                    LocalFree(description);
                }
            }
        }
        
        threads.push_back(info);
        CloseHandle(hThread);
        
    } while (Thread32Next(snapshot, &te32));
    
    CloseHandle(snapshot);
    return threads;
}

std::vector<ThreadInfo> ThreadManager::FindMatchingThreads(const std::vector<ThreadInfo>& threads, 
                                                          const ThreadRule& rule) {
    std::vector<ThreadInfo> matches;
    
    for (const auto& thread : threads) {
        bool match = false;
        
        if (!rule.moduleName.empty()) {
            if (_stricmp(thread.moduleName.c_str(), rule.moduleName.c_str()) == 0) {
                match = true;
            }
        }
        
        if (!rule.threadDesc.empty()) {
            if (!thread.threadDesc.empty() && thread.threadDesc.find(rule.threadDesc) != std::string::npos) {
                match = true;
            }
        }
        
        if (match) {
            matches.push_back(thread);
        }
    }
    
    return matches;
}

bool ThreadManager::ApplyThreadRule(const ThreadInfo& thread, const ThreadRule& rule, 
                                   const CpuTopology& topology, const std::vector<int>& occupiedCores,
                                   CooldownTracker& cooldowns) {
    HANDLE hThread = OpenThread(THREAD_SET_INFORMATION | THREAD_SUSPEND_RESUME | THREAD_TERMINATE, 
                               FALSE, thread.threadId);
    if (!hThread) {
        return false;
    }
    
    bool success = true;
    
    // Apply priority
    if (rule.priority != 0) {
        int priority = MapPriorityValue(rule.priority);
        if (!SetThreadPriority(hThread, priority)) {
            success = false;
        }
    }
    
    // Apply affinity mask
    if (!rule.affinityMask.empty()) {
        DWORD_PTR mask = 0;
        
        if (_stricmp(rule.affinityMask.c_str(), "auto") == 0) {
            // Auto-assign to free P-core or E-core
            int core = SelectAutoCore(topology, occupiedCores, rule.isMainThread);
            if (core >= 0) {
                mask = (1ULL << core);
            }
        } else {
            // Parse hex mask
            try {
                mask = std::stoull(rule.affinityMask, nullptr, 16);
            } catch (...) {
                success = false;
            }
        }
        
        if (mask != 0) {
            if (SetThreadAffinityMask(hThread, mask) == 0) {
                success = false;
            }
        }
    }
    
    // Apply ideal processor
    if (rule.idealProcessor >= -2) {
        DWORD ideal = 0;
        
        if (rule.idealProcessor == -2) {
            // Auto-select ideal processor
            int core = SelectAutoCore(topology, occupiedCores, rule.isMainThread);
            if (core >= 0) {
                ideal = static_cast<DWORD>(core);
                if (SetThreadIdealProcessor(hThread, ideal) == DWORD(-1)) {
                    success = false;
                }
            }
        } else if (rule.idealProcessor >= 0) {
            ideal = static_cast<DWORD>(rule.idealProcessor);
            if (SetThreadIdealProcessor(hThread, ideal) == DWORD(-1)) {
                success = false;
            }
        }
    }
    
    // Disable boost
    if (rule.disableBoost && cooldowns.CanApplyThreadBoost(thread.threadId)) {
        if (ntSetInformationThread_) {
            ULONG disableBoost = 1;
            ntSetInformationThread_(
                hThread,
                15, // ThreadPriorityBoost
                &disableBoost,
                sizeof(disableBoost)
            );
        }
    }
    
    // Suspend thread
    if (rule.suspend && cooldowns.CanApplyThreadSuspend(thread.threadId)) {
        SuspendThread(hThread);
    }
    
    // Terminate thread (use with caution!)
    if (rule.terminate) {
        TerminateThread(hThread, 0);
    }
    
    CloseHandle(hThread);
    return success;
}

bool ThreadManager::ApplyProcessPriorityClass(DWORD processId, const std::string& priorityClass,
                                             CooldownTracker& cooldowns) {
    if (!cooldowns.CanApplyProcessBoost(processId)) {
        return false;
    }
    
    HANDLE hProcess = OpenProcess(PROCESS_SET_INFORMATION, FALSE, processId);
    if (!hProcess) {
        return false;
    }
    
    DWORD priority = NORMAL_PRIORITY_CLASS;
    std::string lower = priorityClass;
    std::transform(lower.begin(), lower.end(), lower.begin(), ::tolower);
    
    if (lower == "idle") priority = IDLE_PRIORITY_CLASS;
    else if (lower == "belownormal") priority = BELOW_NORMAL_PRIORITY_CLASS;
    else if (lower == "normal") priority = NORMAL_PRIORITY_CLASS;
    else if (lower == "abovenormal") priority = ABOVE_NORMAL_PRIORITY_CLASS;
    else if (lower == "high") priority = HIGH_PRIORITY_CLASS;
    else if (lower == "realtime") priority = REALTIME_PRIORITY_CLASS;
    
    bool success = SetPriorityClass(hProcess, priority) != 0;
    CloseHandle(hProcess);
    return success;
}

int ThreadManager::MapPriorityValue(int priority) {
    // Map -15 to 15 range to Windows thread priority constants
    if (priority == -15) return THREAD_PRIORITY_IDLE;
    if (priority == -2) return THREAD_PRIORITY_LOWEST;
    if (priority == -1) return THREAD_PRIORITY_BELOW_NORMAL;
    if (priority == 0) return THREAD_PRIORITY_NORMAL;
    if (priority == 1) return THREAD_PRIORITY_ABOVE_NORMAL;
    if (priority == 2) return THREAD_PRIORITY_HIGHEST;
    if (priority == 15) return THREAD_PRIORITY_TIME_CRITICAL;
    
    // For other values, approximate
    if (priority < -2) return THREAD_PRIORITY_LOWEST;
    if (priority > 2 && priority < 15) return THREAD_PRIORITY_HIGHEST;
    return THREAD_PRIORITY_NORMAL;
}

int ThreadManager::SelectAutoCore(const CpuTopology& topology, const std::vector<int>& occupiedCores, 
                                 bool isMainThread) {
    // Build set of occupied cores for quick lookup
    std::unordered_map<int, bool> occupied;
    for (int core : occupiedCores) {
        occupied[core] = true;
    }
    
    // Always exclude core 0
    occupied[0] = true;
    
    auto pCores = topology.GetPCores();
    auto eCores = topology.GetECores();
    
    // For main threads, prefer P-cores
    if (isMainThread && !pCores.empty()) {
        for (int core : pCores) {
            if (!occupied[core]) {
                return core;
            }
        }
    }
    
    // For background threads, prefer E-cores
    if (!isMainThread && !eCores.empty()) {
        for (int core : eCores) {
            if (!occupied[core]) {
                return core;
            }
        }
    }
    
    // Fallback: any P-core
    for (int core : pCores) {
        if (!occupied[core]) {
            return core;
        }
    }
    
    // Last resort: any E-core
    for (int core : eCores) {
        if (!occupied[core]) {
            return core;
        }
    }
    
    return -1; // No free core available
}

std::string ThreadManager::GetProcessName(DWORD processId) {
    HANDLE hProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, processId);
    if (!hProcess) {
        return "";
    }
    
    char processName[MAX_PATH] = { 0 };
    DWORD size = MAX_PATH;
    
    if (QueryFullProcessImageNameA(hProcess, 0, processName, &size)) {
        std::string fullPath(processName);
        size_t pos = fullPath.find_last_of("\\/");
        if (pos != std::string::npos) {
            fullPath = fullPath.substr(pos + 1);
        }
        CloseHandle(hProcess);
        return fullPath;
    }
    
    CloseHandle(hProcess);
    return "";
}

std::string ThreadManager::GetModuleNameForAddress(DWORD processId, PVOID address) {
    if (!address) {
        return "";
    }
    
    HANDLE hProcess = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, processId);
    if (!hProcess) {
        return "";
    }
    
    HMODULE hMods[1024];
    DWORD cbNeeded;
    
    if (EnumProcessModules(hProcess, hMods, sizeof(hMods), &cbNeeded)) {
        for (unsigned int i = 0; i < (cbNeeded / sizeof(HMODULE)); i++) {
            MODULEINFO modInfo;
            if (GetModuleInformation(hProcess, hMods[i], &modInfo, sizeof(modInfo))) {
                LPVOID modBase = modInfo.lpBaseOfDll;
                SIZE_T modSize = modInfo.SizeOfImage;
                
                if (address >= modBase && address < (LPVOID)((BYTE*)modBase + modSize)) {
                    char modName[MAX_PATH];
                    if (GetModuleBaseNameA(hProcess, hMods[i], modName, sizeof(modName))) {
                        CloseHandle(hProcess);
                        return std::string(modName);
                    }
                }
            }
        }
    }
    
    CloseHandle(hProcess);
    return "";
}