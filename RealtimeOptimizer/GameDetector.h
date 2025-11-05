#pragma once
#include <windows.h>
#include <string>
#include <vector>
#include <unordered_set>
#include <chrono>

class GameDetector {
public:
    struct GameInfo {
        DWORD processId;
        std::wstring processName;
        std::wstring windowTitle;
        HWND windowHandle;
        bool isFullscreen;
        bool isBorderless;
        RECT windowRect;
        
        GameInfo() : processId(0), windowHandle(nullptr), 
                    isFullscreen(false), isBorderless(false) {
            memset(&windowRect, 0, sizeof(windowRect));
        }
    };

    GameDetector();
    ~GameDetector() = default;

    // Initialize with game list from config
    void Initialize(const std::vector<std::string>& gameList);

    // Detection methods
    GameInfo DetectActiveGame();
    bool IsGameRunning(const std::wstring& gameName);
    bool IsForegroundWindowGame();
    
    // Check if a process is in the game list
    bool IsKnownGame(const std::wstring& processName) const;
    
    // Window analysis
    static bool IsFullscreenWindow(HWND hwnd);
    static bool IsBorderlessWindow(HWND hwnd);
    static bool IsLikelyGameWindow(HWND hwnd);
    
    // Get monitor info for blocking
    static int GetMonitorForWindow(HWND hwnd);
    static RECT GetMonitorRect(int monitorIndex);

private:
    // Known game process names (from config)
    std::unordered_set<std::wstring> m_knownGames;
    
    // Last detected game info (for caching)
    GameInfo m_lastDetectedGame;
    std::chrono::steady_clock::time_point m_lastDetectionTime;
    
    // Helper methods
    static HWND GetForegroundWindowSafe();
    static std::wstring GetWindowTitle(HWND hwnd);
    std::wstring NormalizeProcessName(const std::wstring& name) const;
    
    // Callback for monitor enumeration
    static BOOL CALLBACK MonitorEnumProc(HMONITOR hMonitor, HDC hdcMonitor, 
                                        LPRECT lprcMonitor, LPARAM dwData);
};
