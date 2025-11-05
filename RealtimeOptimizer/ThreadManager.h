#pragma once
#include <windows.h>
#include <tlhelp32.h>
#include <string>
#include <vector>
#include <map>
#include <chrono>
#include "ConfigParser.h"
#include "CpuTopology.h"

// Thread information structure
struct ThreadInfo {
    DWORD threadId;
    DWORD processId;
    std::string processName;
    std::string moduleName;
    std::string threadDesc;
    PVOID startAddress;
    int currentPriority;
    DWORD_PTR affinityMask;
};

// Cooldown tracking for thread/process operations
struct CooldownTracker {
    std::map<DWORD, std::chrono::steady_clock::time_point> threadBoostCooldowns;
    std::map<DWORD, std::chrono::steady_clock::time_point> threadSuspendCooldowns;
    std::map<DWORD, std::chrono::steady_clock::time_point> processBoostCooldowns;
    
    bool CanApplyThreadBoost(DWORD threadId);
    bool CanApplyThreadSuspend(DWORD threadId);
    bool CanApplyProcessBoost(DWORD processId);
};

class ThreadManager {
public:
    ThreadManager();
    ~ThreadManager() = default;
    
    // Thread enumeration
    std::vector<ThreadInfo> EnumerateProcessThreads(const std::string& processName);
    
    // Thread matching
    std::vector<ThreadInfo> FindMatchingThreads(const std::vector<ThreadInfo>& threads, 
                                               const ThreadRule& rule);
    
    // Thread modification
    bool ApplyThreadRule(const ThreadInfo& thread, const ThreadRule& rule, 
                        const CpuTopology& topology, const std::vector<int>& occupiedCores,
                        CooldownTracker& cooldowns);
    
    // Process priority class
    bool ApplyProcessPriorityClass(DWORD processId, const std::string& priorityClass,
                                  CooldownTracker& cooldowns);

private:
    // NT API function pointers
    typedef LONG(NTAPI* NtQueryInformationThreadFunc)(
        HANDLE ThreadHandle,
        int ThreadInformationClass,
        PVOID ThreadInformation,
        ULONG ThreadInformationLength,
        PULONG ReturnLength
    );
    
    typedef LONG(NTAPI* NtSetInformationThreadFunc)(
        HANDLE ThreadHandle,
        int ThreadInformationClass,
        PVOID ThreadInformation,
        ULONG ThreadInformationLength
    );
    
    NtQueryInformationThreadFunc ntQueryInformationThread_;
    NtSetInformationThreadFunc ntSetInformationThread_;
    
    // Helper methods
    int MapPriorityValue(int priority);
    int SelectAutoCore(const CpuTopology& topology, const std::vector<int>& occupiedCores, 
                      bool isMainThread);
    std::string GetProcessName(DWORD processId);
    std::string GetModuleNameForAddress(DWORD processId, PVOID address);
};