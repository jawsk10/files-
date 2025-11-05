#include "ProcessManager.h"
#include <iostream>
#include <algorithm>
#include <psapi.h>
#include <tlhelp32.h>

#pragma comment(lib, "ntdll.lib")

ProcessManager::ProcessManager() 
    : m_gameModeActive(false), 
      m_explorerKilled(false),
      m_activeGamePid(0),
      m_enableKillExplorer(false),
      m_explorerKillTimeout(60000),
      NtSuspendProcess(nullptr),
      NtResumeProcess(nullptr) {
    
    // Load NT functions for process suspension
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    if (ntdll) {
        NtSuspendProcess = (NtSuspendProcessFunc)GetProcAddress(ntdll, "NtSuspendProcess");
        NtResumeProcess = (NtResumeProcessFunc)GetProcAddress(ntdll, "NtResumeProcess");
    }
}

ProcessManager::~ProcessManager() {
    Cleanup();
}

void ProcessManager::Initialize(bool enableKillExplorer, 
                               int explorerKillTimeout,
                               const std::vector<std::string>& processesToSuspend,
                               const std::vector<std::string>& processesIdlePriority) {
    m_enableKillExplorer = enableKillExplorer;
    m_explorerKillTimeout = explorerKillTimeout;
    
    // Convert process names to wide strings
    m_processesToSuspend.clear();
    for (const auto& name : processesToSuspend) {
        std::wstring wname(name.begin(), name.end());
        m_processesToSuspend.push_back(wname);
    }
    
    m_processesIdlePriority.clear();
    for (const auto& name : processesIdlePriority) {
        std::wstring wname(name.begin(), name.end());
        m_processesIdlePriority.push_back(wname);
    }
}

bool ProcessManager::ActivateGameMode(DWORD gamePid, const std::wstring& gameExeName) {
    if (m_gameModeActive) {
        if (m_activeGamePid == gamePid) {
            return true; // Already active for this game
        }
        // Different game, deactivate first
        DeactivateGameMode();
    }
    
    std::wcout << L"[ProcessManager] Activating game mode for: " << gameExeName << L" (PID: " << gamePid << L")" << std::endl;
    
    m_activeGamePid = gamePid;
    m_activeGameName = gameExeName;
    m_gameModeActive = true;
    
    // Suspend configured processes
    if (!m_processesToSuspend.empty()) {
        SuspendProcesses();
    }
    
    // Set processes to idle priority
    if (!m_processesIdlePriority.empty()) {
        SetProcessesToIdlePriority();
    }
    
    // Kill Explorer if configured
    if (m_enableKillExplorer) {
        KillExplorer();
    }
    
    // Boost game process priority to HIGH
    SetProcessPriority(gamePid, HIGH_PRIORITY_CLASS);
    
    return true;
}

bool ProcessManager::DeactivateGameMode() {
    if (!m_gameModeActive) {
        return false;
    }
    
    std::wcout << L"[ProcessManager] Deactivating game mode" << std::endl;
    
    // Restore process priorities
    RestoreProcessPriorities();
    
    // Resume suspended processes
    ResumeProcesses();
    
    // Restore Explorer if it was killed
    if (m_explorerKilled) {
        RestoreExplorer();
    }
    
    // Reset game process priority to normal
    if (m_activeGamePid != 0) {
        SetProcessPriority(m_activeGamePid, NORMAL_PRIORITY_CLASS);
    }
    
    m_gameModeActive = false;
    m_activeGamePid = 0;
    m_activeGameName.clear();
    
    return true;
}

bool ProcessManager::KillExplorer() {
    if (m_explorerKilled) {
        return true;
    }
    
    std::wcout << L"[ProcessManager] Killing Explorer.exe" << std::endl;
    
    // Find and terminate all explorer.exe instances
    bool success = TerminateProcessByName(L"explorer.exe");
    
    if (success) {
        m_explorerKilled = true;
        m_explorerKillTime = std::chrono::steady_clock::now();
    }
    
    return success;
}

bool ProcessManager::RestoreExplorer() {
    if (!m_explorerKilled) {
        return true;
    }
    
    // Check if enough time has passed
    auto now = std::chrono::steady_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - m_explorerKillTime).count();
    
    if (elapsed < m_explorerKillTimeout) {
        std::wcout << L"[ProcessManager] Waiting to restore Explorer (" 
                   << (m_explorerKillTimeout - elapsed) << L"ms remaining)" << std::endl;
        return false;
    }
    
    std::wcout << L"[ProcessManager] Restoring Explorer.exe" << std::endl;
    
    // Start Explorer
    bool success = StartProcess(L"C:\\Windows\\explorer.exe");
    
    if (success) {
        m_explorerKilled = false;
    }
    
    return success;
}

bool ProcessManager::SuspendProcesses() {
    if (!NtSuspendProcess) {
        std::wcout << L"[ProcessManager] NtSuspendProcess not available" << std::endl;
        return false;
    }
    
    int suspendedCount = 0;
    
    for (const auto& processName : m_processesToSuspend) {
        auto pids = FindProcessesByName(processName);
        
        for (DWORD pid : pids) {
            // Skip if already suspended
            if (m_suspendedProcesses.find(pid) != m_suspendedProcesses.end()) {
                continue;
            }
            
            if (SuspendProcess(pid)) {
                ProcessInfo info;
                info.pid = pid;
                info.name = processName;
                info.isSuspended = true;
                m_suspendedProcesses[pid] = info;
                suspendedCount++;
                std::wcout << L"  Suspended: " << processName << L" (PID: " << pid << L")" << std::endl;
            }
        }
    }
    
    std::wcout << L"[ProcessManager] Suspended " << suspendedCount << L" processes" << std::endl;
    return suspendedCount > 0;
}

bool ProcessManager::ResumeProcesses() {
    if (!NtResumeProcess) {
        return false;
    }
    
    int resumedCount = 0;
    
    for (auto& pair : m_suspendedProcesses) {
        if (pair.second.isSuspended) {
            if (ResumeProcess(pair.first)) {
                pair.second.isSuspended = false;
                resumedCount++;
                std::wcout << L"  Resumed: " << pair.second.name << L" (PID: " << pair.first << L")" << std::endl;
            }
        }
    }
    
    m_suspendedProcesses.clear();
    std::wcout << L"[ProcessManager] Resumed " << resumedCount << L" processes" << std::endl;
    return resumedCount > 0;
}

bool ProcessManager::SetProcessesToIdlePriority() {
    int modifiedCount = 0;
    
    for (const auto& processName : m_processesIdlePriority) {
        auto pids = FindProcessesByName(processName);
        
        for (DWORD pid : pids) {
            // Skip if already modified
            if (m_modifiedPriorities.find(pid) != m_modifiedPriorities.end()) {
                continue;
            }
            
            DWORD originalPriority = GetProcessPriority(pid);
            if (SetProcessPriority(pid, IDLE_PRIORITY_CLASS)) {
                m_modifiedPriorities[pid] = originalPriority;
                modifiedCount++;
                std::wcout << L"  Set to IDLE: " << processName << L" (PID: " << pid << L")" << std::endl;
            }
        }
    }
    
    std::wcout << L"[ProcessManager] Set " << modifiedCount << L" processes to idle priority" << std::endl;
    return modifiedCount > 0;
}

bool ProcessManager::RestoreProcessPriorities() {
    int restoredCount = 0;
    
    for (const auto& pair : m_modifiedPriorities) {
        if (SetProcessPriority(pair.first, pair.second)) {
            restoredCount++;
        }
    }
    
    m_modifiedPriorities.clear();
    std::wcout << L"[ProcessManager] Restored " << restoredCount << L" process priorities" << std::endl;
    return restoredCount > 0;
}

bool ProcessManager::IsGameWindow(HWND hwnd) {
    if (!IsWindowVisible(hwnd)) {
        return false;
    }
    
    // Get window class name
    wchar_t className[256];
    GetClassNameW(hwnd, className, 256);
    
    // Common game window classes
    std::wstring classStr(className);
    if (classStr == L"UnrealWindow" || 
        classStr == L"UnityWndClass" ||
        classStr == L"CryENGINE" ||
        classStr == L"D3D Window" ||
        classStr.find(L"Direct3D") != std::wstring::npos) {
        return true;
    }
    
    // Check window size (likely fullscreen or large window)
    RECT rect;
    GetWindowRect(hwnd, &rect);
    int width = rect.right - rect.left;
    int height = rect.bottom - rect.top;
    
    // Get screen size
    int screenWidth = GetSystemMetrics(SM_CXSCREEN);
    int screenHeight = GetSystemMetrics(SM_CYSCREEN);
    
    // Consider it a game if window is at least 80% of screen size
    if (width >= screenWidth * 0.8 && height >= screenHeight * 0.8) {
        return true;
    }
    
    return false;
}

DWORD ProcessManager::GetForegroundProcessId() {
    HWND hwnd = GetForegroundWindow();
    if (!hwnd) {
        return 0;
    }
    
    DWORD processId = 0;
    GetWindowThreadProcessId(hwnd, &processId);
    return processId;
}

std::wstring ProcessManager::GetProcessName(DWORD processId) {
    HANDLE hProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, processId);
    if (!hProcess) {
        return L"";
    }
    
    wchar_t processName[MAX_PATH] = { 0 };
    DWORD size = MAX_PATH;
    
    if (QueryFullProcessImageNameW(hProcess, 0, processName, &size)) {
        std::wstring fullPath(processName);
        size_t pos = fullPath.find_last_of(L"\\/");
        if (pos != std::wstring::npos) {
            fullPath = fullPath.substr(pos + 1);
        }
        CloseHandle(hProcess);
        return fullPath;
    }
    
    CloseHandle(hProcess);
    return L"";
}

void ProcessManager::Cleanup() {
    if (m_gameModeActive) {
        DeactivateGameMode();
    }
}

// Private helper methods

bool ProcessManager::SuspendProcess(DWORD processId) {
    if (!NtSuspendProcess) {
        return false;
    }
    
    HANDLE hProcess = OpenProcess(PROCESS_SUSPEND_RESUME, FALSE, processId);
    if (!hProcess) {
        return false;
    }
    
    LONG status = NtSuspendProcess(hProcess);
    CloseHandle(hProcess);
    
    return (status == 0);
}

bool ProcessManager::ResumeProcess(DWORD processId) {
    if (!NtResumeProcess) {
        return false;
    }
    
    HANDLE hProcess = OpenProcess(PROCESS_SUSPEND_RESUME, FALSE, processId);
    if (!hProcess) {
        return false;
    }
    
    LONG status = NtResumeProcess(hProcess);
    CloseHandle(hProcess);
    
    return (status == 0);
}

bool ProcessManager::SetProcessPriority(DWORD processId, DWORD priority) {
    HANDLE hProcess = OpenProcess(PROCESS_SET_INFORMATION, FALSE, processId);
    if (!hProcess) {
        return false;
    }
    
    BOOL result = SetPriorityClass(hProcess, priority);
    CloseHandle(hProcess);
    
    return (result != 0);
}

DWORD ProcessManager::GetProcessPriority(DWORD processId) {
    HANDLE hProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, processId);
    if (!hProcess) {
        return NORMAL_PRIORITY_CLASS;
    }
    
    DWORD priority = GetPriorityClass(hProcess);
    CloseHandle(hProcess);
    
    return priority;
}

std::vector<DWORD> ProcessManager::FindProcessesByName(const std::wstring& processName) {
    std::vector<DWORD> pids;
    
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) {
        return pids;
    }
    
    PROCESSENTRY32W pe32;
    pe32.dwSize = sizeof(PROCESSENTRY32W);
    
    if (Process32FirstW(snapshot, &pe32)) {
        do {
            if (_wcsicmp(pe32.szExeFile, processName.c_str()) == 0) {
                pids.push_back(pe32.th32ProcessID);
            }
        } while (Process32NextW(snapshot, &pe32));
    }
    
    CloseHandle(snapshot);
    return pids;
}

bool ProcessManager::TerminateProcessByName(const std::wstring& processName) {
    auto pids = FindProcessesByName(processName);
    bool success = false;
    
    for (DWORD pid : pids) {
        HANDLE hProcess = OpenProcess(PROCESS_TERMINATE, FALSE, pid);
        if (hProcess) {
            if (TerminateProcess(hProcess, 0)) {
                success = true;
            }
            CloseHandle(hProcess);
        }
    }
    
    return success;
}

bool ProcessManager::StartProcess(const std::wstring& exePath, const std::wstring& args) {
    STARTUPINFOW si = { sizeof(si) };
    PROCESS_INFORMATION pi = { 0 };
    
    std::wstring cmdLine = exePath;
    if (!args.empty()) {
        cmdLine += L" " + args;
    }
    
    BOOL result = CreateProcessW(
        nullptr,
        const_cast<LPWSTR>(cmdLine.c_str()),
        nullptr,
        nullptr,
        FALSE,
        0,
        nullptr,
        nullptr,
        &si,
        &pi
    );
    
    if (result) {
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
        return true;
    }
    
    return false;
}
