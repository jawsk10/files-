#include "HookManager.h"
#include <iostream>
#include <vector>

// Static instance pointer for hook callbacks
HookManager* HookManager::s_instance = nullptr;

HookManager::HookManager() 
    : m_blockWinKey(false),
      m_gamingMonitorIndex(0),
      m_blockingEnabled(false),
      m_keyboardHookActive(false),
      m_cursorClipped(false),
      m_keyboardHook(nullptr),
      m_hookThreadRunning(false),
      m_hookThreadId(0),
      m_messageWindow(nullptr) {
    
    s_instance = this;
    memset(&m_clipRect, 0, sizeof(m_clipRect));
}

HookManager::~HookManager() {
    Cleanup();
    s_instance = nullptr;
}

void HookManager::Initialize(bool blockWinKey, const std::string& blockNoGamingMonitor) {
    m_blockWinKey = blockWinKey;
    m_blockNoGamingMonitor = blockNoGamingMonitor;
    
    // Parse monitor setting
    if (!blockNoGamingMonitor.empty() && blockNoGamingMonitor != "false") {
        try {
            m_gamingMonitorIndex = std::stoi(blockNoGamingMonitor);
        } catch (...) {
            m_gamingMonitorIndex = 0;
        }
    }
    
    std::cout << "[HookManager] Initialized - Win key blocking: " 
              << (m_blockWinKey ? "enabled" : "disabled")
              << ", Gaming monitor: " << m_gamingMonitorIndex << std::endl;
}

bool HookManager::InstallKeyboardHook() {
    if (m_keyboardHookActive) {
        return true;
    }
    
    if (!m_blockWinKey) {
        return false; // No need for hook if not blocking Win key
    }
    
    // Create hook thread
    m_hookThreadRunning = true;
    m_hookThread = std::make_unique<std::thread>(&HookManager::HookThreadProc, this);
    
    // Wait for hook to be installed
    int attempts = 0;
    while (!m_keyboardHookActive && attempts < 50) {
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
        attempts++;
    }
    
    if (m_keyboardHookActive) {
        std::cout << "[HookManager] Keyboard hook installed successfully" << std::endl;
        return true;
    } else {
        std::cout << "[HookManager] Failed to install keyboard hook" << std::endl;
        m_hookThreadRunning = false;
        if (m_hookThread && m_hookThread->joinable()) {
            m_hookThread->join();
        }
        return false;
    }
}

bool HookManager::UninstallKeyboardHook() {
    if (!m_keyboardHookActive) {
        return true;
    }
    
    // Signal thread to stop
    m_hookThreadRunning = false;
    
    // Post quit message to hook thread
    if (m_hookThreadId != 0) {
        PostThreadMessage(m_hookThreadId, WM_QUIT, 0, 0);
    }
    
    // Wait for thread to finish
    if (m_hookThread && m_hookThread->joinable()) {
        m_hookThread->join();
    }
    
    m_keyboardHookActive = false;
    std::cout << "[HookManager] Keyboard hook uninstalled" << std::endl;
    return true;
}

bool HookManager::ClipCursorToWindow(HWND hwnd) {
    if (!hwnd || !IsWindow(hwnd)) {
        return false;
    }
    
    RECT windowRect;
    if (!GetWindowRect(hwnd, &windowRect)) {
        return false;
    }
    
    // Adjust for window borders if present
    LONG style = GetWindowLong(hwnd, GWL_STYLE);
    if (style & WS_CAPTION) {
        RECT clientRect;
        GetClientRect(hwnd, &clientRect);
        POINT clientOrigin = {0, 0};
        ClientToScreen(hwnd, &clientOrigin);
        
        windowRect.left = clientOrigin.x;
        windowRect.top = clientOrigin.y;
        windowRect.right = windowRect.left + clientRect.right;
        windowRect.bottom = windowRect.top + clientRect.bottom;
    }
    
    if (ClipCursor(&windowRect)) {
        m_clipRect = windowRect;
        m_cursorClipped = true;
        std::cout << "[HookManager] Cursor clipped to window" << std::endl;
        return true;
    }
    
    return false;
}

bool HookManager::ClipCursorToMonitor(int monitorIndex) {
    RECT monitorRect = GetMonitorRect(monitorIndex);
    
    if (monitorRect.right == monitorRect.left) {
        return false; // Invalid monitor
    }
    
    if (ClipCursor(&monitorRect)) {
        m_clipRect = monitorRect;
        m_cursorClipped = true;
        std::cout << "[HookManager] Cursor clipped to monitor " << monitorIndex << std::endl;
        return true;
    }
    
    return false;
}

bool HookManager::ReleaseCursorClip() {
    if (!m_cursorClipped) {
        return true;
    }
    
    if (ClipCursor(nullptr)) {
        m_cursorClipped = false;
        memset(&m_clipRect, 0, sizeof(m_clipRect));
        std::cout << "[HookManager] Cursor clip released" << std::endl;
        return true;
    }
    
    return false;
}

void HookManager::Cleanup() {
    UninstallKeyboardHook();
    ReleaseCursorClip();
    m_blockingEnabled = false;
}

LRESULT CALLBACK HookManager::LowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) {
    if (nCode >= 0 && s_instance && s_instance->m_blockingEnabled) {
        KBDLLHOOKSTRUCT* pKeyboard = (KBDLLHOOKSTRUCT*)lParam;
        
        // Block Windows key combinations
        if (s_instance->m_blockWinKey) {
            // Check for Windows key
            if (pKeyboard->vkCode == VK_LWIN || pKeyboard->vkCode == VK_RWIN) {
                // Check if we should block based on monitor
                if (!s_instance->m_blockNoGamingMonitor.empty()) {
                    POINT cursorPos;
                    GetCursorPos(&cursorPos);
                    int currentMonitor = s_instance->GetMonitorForPoint(cursorPos);
                    
                    // Only block if on gaming monitor
                    if (currentMonitor == s_instance->m_gamingMonitorIndex) {
                        return 1; // Block the key
                    }
                } else {
                    return 1; // Always block
                }
            }
            
            // Block common Win+X combinations
            if (GetAsyncKeyState(VK_LWIN) & 0x8000 || GetAsyncKeyState(VK_RWIN) & 0x8000) {
                switch (pKeyboard->vkCode) {
                    case 'D':     // Win+D (Show desktop)
                    case 'L':     // Win+L (Lock)
                    case 'M':     // Win+M (Minimize all)
                    case VK_TAB:  // Win+Tab (Task view)
                    case VK_SPACE: // Win+Space (Language)
                        return 1; // Block these combinations
                }
            }
        }
    }
    
    return CallNextHookEx(nullptr, nCode, wParam, lParam);
}

void HookManager::HookThreadProc() {
    m_hookThreadId = GetCurrentThreadId();
    
    // Install low-level keyboard hook
    m_keyboardHook = SetWindowsHookEx(
        WH_KEYBOARD_LL,
        LowLevelKeyboardProc,
        GetModuleHandle(nullptr),
        0
    );
    
    if (m_keyboardHook) {
        m_keyboardHookActive = true;
        
        // Message loop for hook thread
        MSG msg;
        while (m_hookThreadRunning && GetMessage(&msg, nullptr, 0, 0)) {
            if (msg.message == WM_QUIT) {
                break;
            }
            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }
        
        // Unhook
        UnhookWindowsHookEx(m_keyboardHook);
        m_keyboardHook = nullptr;
    }
    
    m_keyboardHookActive = false;
    m_hookThreadId = 0;
}

bool HookManager::IsWindowOnGamingMonitor(HWND hwnd) const {
    if (!hwnd) {
        return false;
    }
    
    HMONITOR hMonitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    auto monitors = EnumerateMonitors();
    
    for (size_t i = 0; i < monitors.size(); i++) {
        if (monitors[i] == hMonitor) {
            return (static_cast<int>(i) == m_gamingMonitorIndex);
        }
    }
    
    return false;
}

int HookManager::GetMonitorForPoint(POINT pt) const {
    HMONITOR hMonitor = MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST);
    auto monitors = EnumerateMonitors();
    
    for (size_t i = 0; i < monitors.size(); i++) {
        if (monitors[i] == hMonitor) {
            return static_cast<int>(i);
        }
    }
    
    return 0;
}

RECT HookManager::GetMonitorRect(int monitorIndex) const {
    RECT rect = {0, 0, 0, 0};
    auto monitors = EnumerateMonitors();
    
    if (monitorIndex >= 0 && monitorIndex < static_cast<int>(monitors.size())) {
        MONITORINFO mi = { sizeof(mi) };
        if (GetMonitorInfo(monitors[monitorIndex], &mi)) {
            rect = mi.rcMonitor;
        }
    }
    
    return rect;
}

std::vector<HMONITOR> HookManager::EnumerateMonitors() const {
    std::vector<HMONITOR> monitors;
    
    EnumDisplayMonitors(nullptr, nullptr, 
        [](HMONITOR hMonitor, HDC, LPRECT, LPARAM dwData) -> BOOL {
            auto* pMonitors = reinterpret_cast<std::vector<HMONITOR>*>(dwData);
            pMonitors->push_back(hMonitor);
            return TRUE;
        }, 
        reinterpret_cast<LPARAM>(&monitors));
    
    return monitors;
}
