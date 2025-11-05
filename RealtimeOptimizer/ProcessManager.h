#pragma once
#include <windows.h>
#include <tlhelp32.h>
#include <string>
#include <vector>
#include <unordered_map>
#include <unordered_set>
#include <memory>
#include <chrono>

class ProcessManager {
public:
    struct ProcessInfo {
        DWORD pid;
        std::wstring name;
        DWORD originalPriority;
        bool isSuspended;
        HANDLE processHandle;
        
        ProcessInfo() : pid(0), originalPriority(NORMAL_PRIORITY_CLASS), 
                       isSuspended(false), processHandle(nullptr) {}
    };

    ProcessManager();
    ~ProcessManager();

    // Initialize with config settings
    void Initialize(bool enableKillExplorer, 
                   int explorerKillTimeout,
                   const std::vector<std::string>& processesToSuspend,
                   const std::vector<std::string>& processesIdlePriority);

    // Game mode activation/deactivation
    bool ActivateGameMode(DWORD gamePid, const std::wstring& gameExeName);
    bool DeactivateGameMode();
    bool IsGameModeActive() const { return m_gameModeActive; }
    DWORD GetActiveGamePid() const { return m_activeGamePid; }

    // Explorer management
    bool KillExplorer();
    bool RestoreExplorer();
    bool IsExplorerKilled() const { return m_explorerKilled; }

    // Process suspension/resumption
    bool SuspendProcesses();
    bool ResumeProcesses();

    // Priority management
    bool SetProcessesToIdlePriority();
    bool RestoreProcessPriorities();

    // Window detection
    static bool IsGameWindow(HWND hwnd);
    static DWORD GetForegroundProcessId();
    static std::wstring GetProcessName(DWORD processId);

    // Cleanup
    void Cleanup();

private:
    // Helper functions
    bool SuspendProcess(DWORD processId);
    bool ResumeProcess(DWORD processId);
    bool SetProcessPriority(DWORD processId, DWORD priority);
    DWORD GetProcessPriority(DWORD processId);
    std::vector<DWORD> FindProcessesByName(const std::wstring& processName);
    bool TerminateProcessByName(const std::wstring& processName);
    bool StartProcess(const std::wstring& exePath, const std::wstring& args = L"");
    
    // NT API for process suspension
    typedef LONG(NTAPI* NtSuspendProcessFunc)(HANDLE ProcessHandle);
    typedef LONG(NTAPI* NtResumeProcessFunc)(HANDLE ProcessHandle);
    
    NtSuspendProcessFunc NtSuspendProcess;
    NtResumeProcessFunc NtResumeProcess;

    // Configuration
    bool m_enableKillExplorer;
    int m_explorerKillTimeout;
    std::vector<std::wstring> m_processesToSuspend;
    std::vector<std::wstring> m_processesIdlePriority;

    // State tracking
    bool m_gameModeActive;
    bool m_explorerKilled;
    DWORD m_activeGamePid;
    std::wstring m_activeGameName;
    
    // Suspended processes tracking
    std::unordered_map<DWORD, ProcessInfo> m_suspendedProcesses;
    
    // Priority-modified processes tracking
    std::unordered_map<DWORD, DWORD> m_modifiedPriorities;
    
    // Explorer restore timer
    std::chrono::steady_clock::time_point m_explorerKillTime;
};
