// RealtimeOptimizer - Final Complete Implementation
// Combines all phases into a single executable

#include <windows.h>
#include <shellapi.h>
#include <iostream>
#include <thread>
#include <chrono>
#include <atomic>
#include <csignal>
#include <memory>

// Include all component headers
#include "ConfigParser.h"
#include "CpuTopology.h"
#include "ThreadManager.h"
#include "GameDetector.h"
#include "ProcessManager.h"
#include "HookManager.h"
#include "Logger.h"

// Resource IDs for tray icon
#define ID_TRAY_APP_ICON    1001
#define ID_TRAY_EXIT        1002
#define ID_TRAY_TOGGLE      1003
#define ID_TRAY_SHOW        1004
#define WM_TRAYICON         (WM_USER + 1)

// Global variables
std::atomic<bool> g_shouldExit(false);
std::atomic<bool> g_enabled(true);
HWND g_hiddenWindow = nullptr;
NOTIFYICONDATA g_notifyIconData;

// Forward declarations
LRESULT CALLBACK WindowProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam);
void CreateTrayIcon(HWND hwnd);
void RemoveTrayIcon();
void ShowTrayMenu(HWND hwnd);

// Signal handler for graceful shutdown
void SignalHandler(int signal) {
    if (signal == SIGINT || signal == SIGTERM) {
        LOG_INFO("Shutdown signal received");
        g_shouldExit = true;
    }
}

// Check if running as administrator
bool IsRunningAsAdmin() {
    BOOL isAdmin = FALSE;
    PSID administratorsGroup = NULL;
    SID_IDENTIFIER_AUTHORITY ntAuthority = SECURITY_NT_AUTHORITY;
    
    if (AllocateAndInitializeSid(&ntAuthority, 2, SECURITY_BUILTIN_DOMAIN_RID,
                                  DOMAIN_ALIAS_RID_ADMINS, 0, 0, 0, 0, 0, 0, &administratorsGroup)) {
        CheckTokenMembership(NULL, administratorsGroup, &isAdmin);
        FreeSid(administratorsGroup);
    }
    
    return isAdmin != FALSE;
}

// Main monitoring loop
void MonitoringLoop(ConfigParser& config, CpuTopology& topology, 
                   ThreadManager& threadManager, GameDetector& gameDetector,
                   ProcessManager& processManager, HookManager& hookManager,
                   CooldownTracker& cooldowns) {
    
    LOG_INFO("Monitoring loop started");
    
    int updateTimeout = config.GetUpdateTimeout();
    if (updateTimeout <= 0) updateTimeout = 100;
    
    bool wasGameActive = false;
    DWORD lastGamePid = 0;
    
    while (!g_shouldExit) {
        if (!g_enabled) {
            std::this_thread::sleep_for(std::chrono::milliseconds(1000));
            continue;
        }
        
        // Check for active game
        auto gameInfo = gameDetector.DetectActiveGame();
        bool isGameActive = (gameInfo.processId != 0);
        
        // Handle game mode transitions
        if (isGameActive && !wasGameActive) {
            // Game started
            Logger::GetInstance().LogF(LogLevel::Info, "Game detected: %ls (PID: %d)", 
                                      gameInfo.processName.c_str(), gameInfo.processId);
            
            // Activate game mode
            processManager.ActivateGameMode(gameInfo.processId, gameInfo.processName);
            
            // Install keyboard hook if configured
            hookManager.SetBlockingEnabled(true);
            hookManager.InstallKeyboardHook();
            
            // Clip cursor to game window/monitor
            if (gameInfo.isFullscreen || gameInfo.isBorderless) {
                hookManager.ClipCursorToWindow(gameInfo.windowHandle);
            }
            
            wasGameActive = true;
            lastGamePid = gameInfo.processId;
        }
        else if (!isGameActive && wasGameActive) {
            // Game ended
            LOG_INFO("Game no longer active, deactivating game mode");
            
            processManager.DeactivateGameMode();
            hookManager.SetBlockingEnabled(false);
            hookManager.UninstallKeyboardHook();
            hookManager.ReleaseCursorClip();
            
            wasGameActive = false;
            lastGamePid = 0;
        }
        else if (isGameActive && wasGameActive && gameInfo.processId != lastGamePid) {
            // Different game started
            Logger::GetInstance().LogF(LogLevel::Info, "Switching to different game: %ls", 
                                      gameInfo.processName.c_str());
            
            processManager.DeactivateGameMode();
            processManager.ActivateGameMode(gameInfo.processId, gameInfo.processName);
            
            // Update cursor clipping
            hookManager.ReleaseCursorClip();
            if (gameInfo.isFullscreen || gameInfo.isBorderless) {
                hookManager.ClipCursorToWindow(gameInfo.windowHandle);
            }
            
            lastGamePid = gameInfo.processId;
        }
        
        // Apply thread rules periodically
        auto processSections = config.GetProcessSections();
        auto occupiedCores = config.GetOccupiedAffinityCores();
        
        for (const auto& processName : processSections) {
            std::string fullProcessName = processName + ".exe";
            auto threads = threadManager.EnumerateProcessThreads(fullProcessName);
            
            if (threads.empty()) {
                continue;
            }
            
            auto rules = config.GetThreadRules(processName);
            
            // Apply process priority class if specified
            for (const auto& rule : rules) {
                if (!rule.priorityClass.empty()) {
                    threadManager.ApplyProcessPriorityClass(threads[0].processId, 
                                                           rule.priorityClass, cooldowns);
                    break;
                }
            }
            
            // Apply thread rules
            for (const auto& rule : rules) {
                auto matches = threadManager.FindMatchingThreads(threads, rule);
                
                // Handle disableclones
                if (rule.disableClones && matches.size() > 1) {
                    // Keep only the first matching thread, suspend others
                    for (size_t i = 1; i < matches.size(); i++) {
                        ThreadRule cloneRule = rule;
                        cloneRule.suspend = true;
                        threadManager.ApplyThreadRule(matches[i], cloneRule, topology, 
                                                     occupiedCores, cooldowns);
                    }
                    matches.resize(1);
                }
                
                // Apply rule to remaining threads
                for (const auto& thread : matches) {
                    threadManager.ApplyThreadRule(thread, rule, topology, 
                                                 occupiedCores, cooldowns);
                }
            }
        }
        
        std::this_thread::sleep_for(std::chrono::milliseconds(updateTimeout));
    }
    
    LOG_INFO("Monitoring loop ended");
}

// System tray window procedure
LRESULT CALLBACK WindowProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam) {
    switch (uMsg) {
        case WM_TRAYICON:
            switch (lParam) {
                case WM_RBUTTONUP:
                    ShowTrayMenu(hwnd);
                    break;
                case WM_LBUTTONDBLCLK:
                    ShowWindow(GetConsoleWindow(), SW_SHOW);
                    break;
            }
            break;
            
        case WM_COMMAND:
            switch (LOWORD(wParam)) {
                case ID_TRAY_EXIT:
                    g_shouldExit = true;
                    break;
                case ID_TRAY_TOGGLE:
                    g_enabled = !g_enabled;
                    if (g_enabled) {
                        LOG_INFO("Optimization enabled");
                    } else {
                        LOG_INFO("Optimization disabled");
                    }
                    break;
                case ID_TRAY_SHOW:
                    ShowWindow(GetConsoleWindow(), SW_SHOW);
                    break;
            }
            break;
            
        case WM_DESTROY:
            PostQuitMessage(0);
            break;
            
        default:
            return DefWindowProc(hwnd, uMsg, wParam, lParam);
    }
    return 0;
}

void CreateTrayIcon(HWND hwnd) {
    memset(&g_notifyIconData, 0, sizeof(NOTIFYICONDATA));
    
    g_notifyIconData.cbSize = sizeof(NOTIFYICONDATA);
    g_notifyIconData.hWnd = hwnd;
    g_notifyIconData.uID = ID_TRAY_APP_ICON;
    g_notifyIconData.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    g_notifyIconData.uCallbackMessage = WM_TRAYICON;
    // Load system application icon (avoids MAKEINTRESOURCE truncation warning)
    g_notifyIconData.hIcon = LoadIconW(NULL, IDI_APPLICATION);
    wcscpy_s(g_notifyIconData.szTip, L"RealtimeOptimizer - Running");
    
    Shell_NotifyIcon(NIM_ADD, &g_notifyIconData);
}

void RemoveTrayIcon() {
    Shell_NotifyIcon(NIM_DELETE, &g_notifyIconData);
}

void ShowTrayMenu(HWND hwnd) {
    POINT pt;
    GetCursorPos(&pt);
    
    HMENU hMenu = CreatePopupMenu();
    AppendMenuW(hMenu, MF_STRING, ID_TRAY_SHOW, L"Show Console");
    AppendMenuW(hMenu, MF_STRING, ID_TRAY_TOGGLE, g_enabled ? L"Disable" : L"Enable");
    AppendMenuW(hMenu, MF_SEPARATOR, 0, NULL);
    AppendMenuW(hMenu, MF_STRING, ID_TRAY_EXIT, L"Exit");
    
    SetForegroundWindow(hwnd);
    TrackPopupMenu(hMenu, TPM_BOTTOMALIGN | TPM_LEFTALIGN, pt.x, pt.y, 0, hwnd, NULL);
    DestroyMenu(hMenu);
}

int main(int argc, char* argv[]) {
    // Parse command line arguments
    bool silentMode = false;
    bool debugMode = false;
    bool trayMode = false;
    
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--silent") == 0 || strcmp(argv[i], "-s") == 0) {
            silentMode = true;
        }
        if (strcmp(argv[i], "--debug") == 0 || strcmp(argv[i], "-d") == 0) {
            debugMode = true;
        }
        if (strcmp(argv[i], "--tray") == 0 || strcmp(argv[i], "-t") == 0) {
            trayMode = true;
            silentMode = true; // Tray mode implies silent
        }
    }
    
    // Initialize logger
    Logger::GetInstance().Initialize(
        "RealtimeOptimizer.log",
        debugMode ? LogLevel::Debug : LogLevel::Info,
        !silentMode,  // Console output
        10 * 1024 * 1024  // 10MB max file size
    );
    
    LOG_INFO("========================================================");
    LOG_INFO("    REALTIME OPTIMIZER v1.0 - Final Release");
    LOG_INFO("========================================================");
    
    // Set up signal handlers
    signal(SIGINT, SignalHandler);
    signal(SIGTERM, SignalHandler);
    
    // Check for admin privileges
    if (!IsRunningAsAdmin()) {
        LOG_WARNING("Not running as Administrator!");
        LOG_WARNING("Many features require admin privileges to work properly");
        
        if (!silentMode) {
            std::cout << "\nPress Enter to continue anyway, or close this window..." << std::endl;
            std::cin.get();
        }
    }
    
    // Initialize CPU topology
    LOG_INFO("Detecting CPU topology...");
    CpuTopology topology;
    if (!topology.Initialize()) {
        LOG_CRITICAL("Failed to initialize CPU topology");
        return 1;
    }
    
    if (debugMode) {
        topology.PrintTopology();
    }
    
    Logger::GetInstance().LogF(LogLevel::Info, "CPU: %d logical cores, %d physical cores", 
                              topology.GetLogicalCoreCount(), topology.GetPhysicalCoreCount());
    
    // Load configuration
    LOG_INFO("Loading configuration...");
    ConfigParser config;
    if (!config.LoadFromFile("config.ini")) {
        LOG_CRITICAL("Failed to load config.ini");
        return 1;
    }
    
    // Initialize components
    LOG_INFO("Initializing components...");
    
    ThreadManager threadManager;
    CooldownTracker cooldowns;
    
    GameDetector gameDetector;
    gameDetector.Initialize(config.GetGames());
    
    ProcessManager processManager;
    processManager.Initialize(
        config.GetEnableKillExplorer(),
        config.GetExplorerKillTimeout(),
        config.GetProcessesToSuspend(),
        config.GetProcessesIdlePriority()
    );
    
    HookManager hookManager;
    hookManager.Initialize(config.GetWinBlockKeys(), config.GetBlockNoGamingMonitor());
    
    LOG_INFO("All components initialized successfully");
    
    // Create hidden window for tray icon if in tray mode
    HWND hiddenWindow = nullptr;
    std::thread trayThread;
    
    if (trayMode) {
        LOG_INFO("Starting in system tray mode");
        
        trayThread = std::thread([]() {
            // Register window class
            WNDCLASSW wc = { 0 };
            wc.lpfnWndProc = WindowProc;
            wc.hInstance = GetModuleHandle(NULL);
            wc.lpszClassName = L"RealtimeOptimizerTray";
            RegisterClassW(&wc);
            
            // Create hidden window
            g_hiddenWindow = CreateWindowW(
                L"RealtimeOptimizerTray", L"RealtimeOptimizer",
                WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT,
                CW_USEDEFAULT, CW_USEDEFAULT, NULL, NULL,
                GetModuleHandle(NULL), NULL
            );
            
            CreateTrayIcon(g_hiddenWindow);
            
            // Message loop
            MSG msg;
            while (GetMessage(&msg, NULL, 0, 0) && !g_shouldExit) {
                TranslateMessage(&msg);
                DispatchMessage(&msg);
            }
            
            RemoveTrayIcon();
        });
    }
    
    // Hide console window in silent/tray mode
    if (silentMode) {
        ShowWindow(GetConsoleWindow(), SW_HIDE);
    }
    
    // Start monitoring loop
    LOG_INFO("Starting monitoring loop...");
    
    try {
        MonitoringLoop(config, topology, threadManager, gameDetector, 
                      processManager, hookManager, cooldowns);
    }
    catch (const std::exception& e) {
        Logger::GetInstance().LogF(LogLevel::Critical, "Exception in monitoring loop: %s", e.what());
    }
    
    // Cleanup
    LOG_INFO("Shutting down...");
    
    processManager.Cleanup();
    hookManager.Cleanup();
    
    if (trayMode && trayThread.joinable()) {
        PostMessage(g_hiddenWindow, WM_DESTROY, 0, 0);
        trayThread.join();
    }
    
    LOG_INFO("RealtimeOptimizer stopped successfully");
    Logger::GetInstance().Shutdown();
    
    if (!silentMode) {
        std::cout << "\nPress Enter to exit..." << std::endl;
        std::cin.get();
    }
    
    return 0;
}