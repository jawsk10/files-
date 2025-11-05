#pragma once
#include <windows.h>
#include <atomic>
#include <string>
#include <vector>
#include <thread>
#include <memory>

class HookManager {
public:
    HookManager();
    ~HookManager();

    // Initialize hooks with configuration
    void Initialize(bool blockWinKey, const std::string& blockNoGamingMonitor);

    // Keyboard hook management
    bool InstallKeyboardHook();
    bool UninstallKeyboardHook();
    bool IsKeyboardHookActive() const { return m_keyboardHookActive; }

    // Mouse/cursor management
    bool ClipCursorToWindow(HWND hwnd);
    bool ClipCursorToMonitor(int monitorIndex);
    bool ReleaseCursorClip();
    bool IsCursorClipped() const { return m_cursorClipped; }

    // Enable/disable blocking
    void SetBlockingEnabled(bool enabled) { m_blockingEnabled = enabled; }
    bool IsBlockingEnabled() const { return m_blockingEnabled; }

    // Set target monitor for gaming
    void SetGamingMonitor(int monitorIndex) { m_gamingMonitorIndex = monitorIndex; }

    // Cleanup all hooks
    void Cleanup();

private:
    // Hook procedures
    static LRESULT CALLBACK LowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam);
    
    // Static instance pointer for hook callbacks
    static HookManager* s_instance;

    // Hook thread function
    void HookThreadProc();

    // Helper functions
    bool IsWindowOnGamingMonitor(HWND hwnd) const;
    int GetMonitorForPoint(POINT pt) const;
    RECT GetMonitorRect(int monitorIndex) const;
    std::vector<HMONITOR> EnumerateMonitors() const;

    // Configuration
    bool m_blockWinKey;
    int m_gamingMonitorIndex;
    std::string m_blockNoGamingMonitor;
    
    // State
    std::atomic<bool> m_blockingEnabled;
    std::atomic<bool> m_keyboardHookActive;
    std::atomic<bool> m_cursorClipped;
    
    // Hooks
    HHOOK m_keyboardHook;
    RECT m_clipRect;
    
    // Hook thread
    std::unique_ptr<std::thread> m_hookThread;
    std::atomic<bool> m_hookThreadRunning;
    DWORD m_hookThreadId;
    
    // Message window for hook thread
    HWND m_messageWindow;
};
