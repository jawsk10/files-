#include "GameDetector.h"
#include <algorithm>
#include <iostream>
#include <dwmapi.h>
#include <tlhelp32.h>

#pragma comment(lib, "dwmapi.lib")

GameDetector::GameDetector() {
    m_lastDetectionTime = std::chrono::steady_clock::now() - std::chrono::seconds(10);
}

void GameDetector::Initialize(const std::vector<std::string>& gameList) {
    m_knownGames.clear();
    
    for (const auto& game : gameList) {
        std::wstring wgame(game.begin(), game.end());
        // Add both with and without .exe extension
        m_knownGames.insert(NormalizeProcessName(wgame));
        if (wgame.find(L".exe") == std::wstring::npos) {
            m_knownGames.insert(NormalizeProcessName(wgame + L".exe"));
        }
    }
    
    std::wcout << L"[GameDetector] Initialized with " << m_knownGames.size() << L" known games" << std::endl;
}

GameDetector::GameInfo GameDetector::DetectActiveGame() {
    // Cache detection for 1 second to avoid excessive CPU usage
    auto now = std::chrono::steady_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - m_lastDetectionTime).count();
    
    if (elapsed < 1000 && m_lastDetectedGame.processId != 0) {
        // Verify the cached game is still valid
        HWND currentForeground = GetForegroundWindowSafe();
        if (currentForeground == m_lastDetectedGame.windowHandle) {
            return m_lastDetectedGame;
        }
    }
    
    GameInfo info;
    
    // Get foreground window
    HWND hwnd = GetForegroundWindowSafe();
    if (!hwnd) {
        return info;
    }
    
    // Get process ID
    DWORD processId = 0;
    GetWindowThreadProcessId(hwnd, &processId);
    if (processId == 0) {
        return info;
    }
    
    // Get process name
    HANDLE hProcess = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, processId);
    if (!hProcess) {
        return info;
    }
    
    wchar_t processPath[MAX_PATH] = { 0 };
    DWORD size = MAX_PATH;
    
    if (QueryFullProcessImageNameW(hProcess, 0, processPath, &size)) {
        std::wstring fullPath(processPath);
        size_t pos = fullPath.find_last_of(L"\\/");
        if (pos != std::wstring::npos) {
            info.processName = fullPath.substr(pos + 1);
        } else {
            info.processName = fullPath;
        }
    }
    CloseHandle(hProcess);
    
    // Check if it's a known game OR likely a game window
    bool isKnownGame = IsKnownGame(info.processName);
    bool isLikelyGame = IsLikelyGameWindow(hwnd);
    
    if (!isKnownGame && !isLikelyGame) {
        return GameInfo(); // Return empty info
    }
    
    // Fill in the rest of the info
    info.processId = processId;
    info.windowHandle = hwnd;
    info.windowTitle = GetWindowTitle(hwnd);
    GetWindowRect(hwnd, &info.windowRect);
    info.isFullscreen = IsFullscreenWindow(hwnd);
    info.isBorderless = IsBorderlessWindow(hwnd);
    
    // Cache the result
    m_lastDetectedGame = info;
    m_lastDetectionTime = now;
    
    return info;
}

bool GameDetector::IsGameRunning(const std::wstring& gameName) {
    std::wstring normalized = NormalizeProcessName(gameName);
    
    // Check running processes
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) {
        return false;
    }
    
    PROCESSENTRY32W pe32;
    pe32.dwSize = sizeof(PROCESSENTRY32W);
    
    bool found = false;
    if (Process32FirstW(snapshot, &pe32)) {
        do {
            std::wstring processName = NormalizeProcessName(pe32.szExeFile);
            if (processName == normalized) {
                found = true;
                break;
            }
        } while (Process32NextW(snapshot, &pe32));
    }
    
    CloseHandle(snapshot);
    return found;
}

bool GameDetector::IsForegroundWindowGame() {
    GameInfo info = DetectActiveGame();
    return (info.processId != 0);
}

bool GameDetector::IsKnownGame(const std::wstring& processName) const {
    std::wstring normalized = NormalizeProcessName(processName);
    return (m_knownGames.find(normalized) != m_knownGames.end());
}

bool GameDetector::IsFullscreenWindow(HWND hwnd) {
    if (!hwnd || !IsWindowVisible(hwnd)) {
        return false;
    }
    
    // Get window style
    LONG style = GetWindowLongW(hwnd, GWL_STYLE);
    LONG exStyle = GetWindowLongW(hwnd, GWL_EXSTYLE);
    
    // Check for typical fullscreen styles
    bool hasCaption = (style & WS_CAPTION) != 0;
    bool hasBorder = (style & WS_BORDER) != 0;
    bool isPopup = (style & WS_POPUP) != 0;
    bool isTopmost = (exStyle & WS_EX_TOPMOST) != 0;
    
    if (isPopup && !hasCaption && !hasBorder) {
        // Check if window covers entire screen
        RECT windowRect;
        GetWindowRect(hwnd, &windowRect);
        
        HMONITOR hMonitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
        MONITORINFO mi = { sizeof(mi) };
        GetMonitorInfoW(hMonitor, &mi);
        
        // Compare window size with monitor size
        if (windowRect.left == mi.rcMonitor.left &&
            windowRect.top == mi.rcMonitor.top &&
            windowRect.right == mi.rcMonitor.right &&
            windowRect.bottom == mi.rcMonitor.bottom) {
            return true;
        }
    }
    
    return false;
}

bool GameDetector::IsBorderlessWindow(HWND hwnd) {
    if (!hwnd || !IsWindowVisible(hwnd)) {
        return false;
    }
    
    // Get window style
    LONG style = GetWindowLongW(hwnd, GWL_STYLE);
    
    // Check for borderless windowed mode characteristics
    bool hasCaption = (style & WS_CAPTION) != 0;
    bool hasBorder = (style & WS_BORDER) != 0;
    
    if (!hasCaption && !hasBorder) {
        // Check if it covers most of the screen but not exactly fullscreen
        RECT windowRect;
        GetWindowRect(hwnd, &windowRect);
        
        int width = windowRect.right - windowRect.left;
        int height = windowRect.bottom - windowRect.top;
        
        // Get screen dimensions
        int screenWidth = GetSystemMetrics(SM_CXSCREEN);
        int screenHeight = GetSystemMetrics(SM_CYSCREEN);
        
        // Consider borderless if it's at least 90% of screen size
        if (width >= screenWidth * 0.9 && height >= screenHeight * 0.9) {
            return true;
        }
    }
    
    return false;
}

bool GameDetector::IsLikelyGameWindow(HWND hwnd) {
    if (!hwnd || !IsWindowVisible(hwnd)) {
        return false;
    }
    
    // Check window class name for common game engines
    wchar_t className[256] = { 0 };
    GetClassNameW(hwnd, className, 256);
    std::wstring classStr(className);
    
    // Common game window classes
    const wchar_t* gameClasses[] = {
        L"UnrealWindow", L"UnityWndClass", L"CryENGINE",
        L"D3D Window", L"SDL_app", L"LWJGL", L"GLFW",
        L"Chrome_WidgetWin_0", // For Electron-based games
        L"RiotWindowClass", L"LaunchUnrealUWindowsClient"
    };
    
    for (const wchar_t* gameClass : gameClasses) {
        if (classStr.find(gameClass) != std::wstring::npos) {
            return true;
        }
    }
    
    // Check for DirectX/OpenGL indicators
    if (classStr.find(L"Direct3D") != std::wstring::npos ||
        classStr.find(L"OpenGL") != std::wstring::npos ||
        classStr.find(L"Vulkan") != std::wstring::npos) {
        return true;
    }
    
    // Check window size
    RECT rect;
    GetWindowRect(hwnd, &rect);
    int width = rect.right - rect.left;
    int height = rect.bottom - rect.top;
    
    int screenWidth = GetSystemMetrics(SM_CXSCREEN);
    int screenHeight = GetSystemMetrics(SM_CYSCREEN);
    
    // Large window (at least 75% of screen)
    if (width >= screenWidth * 0.75 && height >= screenHeight * 0.75) {
        // Additional checks for game-like behavior
        LONG style = GetWindowLongW(hwnd, GWL_STYLE);
        LONG exStyle = GetWindowLongW(hwnd, GWL_EXSTYLE);
        
        // Games often use these styles
        bool isPopup = (style & WS_POPUP) != 0;
        bool hasMinBox = (style & WS_MINIMIZEBOX) != 0;
        bool hasMaxBox = (style & WS_MAXIMIZEBOX) != 0;
        bool isTopmost = (exStyle & WS_EX_TOPMOST) != 0;
        
        // Heuristic: large window that's either popup or lacks standard buttons
        if (isPopup || (!hasMinBox && !hasMaxBox) || isTopmost) {
            return true;
        }
    }
    
    return false;
}

int GameDetector::GetMonitorForWindow(HWND hwnd) {
    if (!hwnd) {
        return 0;
    }
    
    HMONITOR hMonitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    
    // Enumerate monitors to find index
    struct MonitorSearchData {
        HMONITOR targetMonitor;
        int currentIndex;
        int foundIndex;
    } searchData = { hMonitor, 0, -1 };
    
    EnumDisplayMonitors(nullptr, nullptr, MonitorEnumProc, (LPARAM)&searchData);
    
    return (searchData.foundIndex >= 0) ? searchData.foundIndex : 0;
}

RECT GameDetector::GetMonitorRect(int monitorIndex) {
    struct MonitorData {
        int targetIndex;
        int currentIndex;
        RECT rect;
    } data = { monitorIndex, 0, {0, 0, 0, 0} };
    
    EnumDisplayMonitors(nullptr, nullptr, 
        [](HMONITOR hMonitor, HDC, LPRECT, LPARAM dwData) -> BOOL {
            auto* data = (MonitorData*)dwData;
            if (data->currentIndex == data->targetIndex) {
                MONITORINFO mi = { sizeof(mi) };
                GetMonitorInfoW(hMonitor, &mi);
                data->rect = mi.rcMonitor;
                return FALSE; // Stop enumeration
            }
            data->currentIndex++;
            return TRUE;
        }, (LPARAM)&data);
    
    return data.rect;
}

HWND GameDetector::GetForegroundWindowSafe() {
    HWND hwnd = GetForegroundWindow();
    if (!hwnd || !IsWindow(hwnd)) {
        return nullptr;
    }
    return hwnd;
}

std::wstring GameDetector::GetWindowTitle(HWND hwnd) {
    if (!hwnd) {
        return L"";
    }
    
    int length = GetWindowTextLengthW(hwnd);
    if (length == 0) {
        return L"";
    }
    
    std::vector<wchar_t> buffer(length + 1);
    GetWindowTextW(hwnd, buffer.data(), length + 1);
    return std::wstring(buffer.data());
}

std::wstring GameDetector::NormalizeProcessName(const std::wstring& name) const {
    std::wstring normalized = name;
    
    // Convert to lowercase
    std::transform(normalized.begin(), normalized.end(), normalized.begin(), ::towlower);
    
    // Remove path if present
    size_t pos = normalized.find_last_of(L"\\/");
    if (pos != std::wstring::npos) {
        normalized = normalized.substr(pos + 1);
    }
    
    return normalized;
}

BOOL CALLBACK GameDetector::MonitorEnumProc(HMONITOR hMonitor, HDC, LPRECT, LPARAM dwData) {
    struct MonitorSearchData {
        HMONITOR targetMonitor;
        int currentIndex;
        int foundIndex;
    };
    
    auto* searchData = (MonitorSearchData*)dwData;
    
    if (hMonitor == searchData->targetMonitor) {
        searchData->foundIndex = searchData->currentIndex;
        return FALSE; // Stop enumeration
    }
    
    searchData->currentIndex++;
    return TRUE; // Continue enumeration
}