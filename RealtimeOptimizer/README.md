- **main.cpp** - Main application with system tray support
- **ConfigParser.cpp/.h** - INI file configuration parser
- **CPUTopology.cpp/.h** - CPU detection (P-cores, E-cores, HT)
- **GameDetector.cpp/.h** - Automatic game window detection
- **HookManager.cpp/.h** - Windows key blocking & cursor management
- **Logger.cpp/.h** - Async logging system with file rotation
- **ProcessManager.cpp/.h** - Process suspension & priority control
- **ThreadManager.cpp/.h** - Thread affinity & priority optimization

### Configuration
- **config.ini** - Main configuration file with examples

### Project Files
- **RealtimeOptimizer.sln** - Visual Studio 2022 solution
- **RealtimeOptimizer.vcxproj** - VS project (pre-configured)

### Documentation
- **QUICK_START.md** - Fast compilation guide
- **COMPILATION_FIXES.md** - Detailed list of all fixes

## 🚀 Quick Start (3 Steps)

### Step 1: Open in Visual Studio
```
Double-click: RealtimeOptimizer.sln
```

### Step 2: Build
```
Press F7 or Build → Build Solution
Configuration: Release | x64
```

### Step 3: Run
```
bin\Release\RealtimeOptimizer.exe
(Right-click → Run as Administrator)
```

## 📋 Build Requirements

### Required:
- ✅ Visual Studio 2022 (v143 toolset)
- ✅ Windows SDK 10.0 or later
- ✅ C++17 standard
- ✅ x64 platform

### Libraries Linked:
- ntdll.lib
- dwmapi.lib
- psapi.lib
- kernel32.lib
- user32.lib

## 🎮 Features

### Game Mode
- ✅ Automatic game detection (fullscreen, borderless, known games)
- ✅ Process priority boosting (game → HIGH_PRIORITY)
- ✅ Background process suspension (Steam, Discord, etc.)
- ✅ Idle priority for non-essential processes
- ✅ Optional Explorer.exe termination (maximum performance)

### Thread Optimization
- ✅ Per-thread priority control (-15 to +15)
- ✅ Thread affinity assignment (pin to specific cores)
- ✅ Ideal processor selection (P-core vs E-core)
- ✅ Priority boost disable for system threads
- ✅ Thread suspension/termination support

### CPU Detection
- ✅ P-core and E-core detection (Intel 12th gen+)
- ✅ Hyper-Threading / SMT detection
- ✅ Dual-CCD detection (AMD Ryzen)
- ✅ Automatic core assignment based on thread type

### Input Protection
- ✅ Windows key blocking during gaming
- ✅ Win+Tab, Win+D blocking
- ✅ Cursor clipping to game window/monitor
- ✅ Per-monitor input blocking

### System Integration
- ✅ System tray operation
- ✅ Silent background mode
- ✅ Real-time process monitoring
- ✅ Async logging with rotation
- ✅ Graceful shutdown handling

## 💻 Usage

### Basic Usage:
```cmd
# Normal mode (with console)
RealtimeOptimizer.exe

# System tray mode (background)
RealtimeOptimizer.exe --tray

# Debug mode (verbose logging)
RealtimeOptimizer.exe --debug

# Silent mode (no console)
RealtimeOptimizer.exe --silent
```

### Configuration:
Edit `config.ini` to customize behavior:

```ini
[Settings]
UpdateTimeout=100              # Polling interval (ms)
EnableKillExplorer=false       # Kill Explorer during gaming
WinBlockKeys=true              # Block Windows key
BlockNoGamingMonitor=0         # Which monitor for input blocking

[Games]
# Add your games here
csgo.exe
valorant.exe
apex_legends.exe

[ProcessesToSuspend]
# Processes to suspend during gaming
Discord.exe
Chrome.exe

[SetProcessesToIdlePriority]
# Set to idle priority during gaming
OneDrive.exe
Dropbox.exe
```

## 📊 Advanced Thread Rules

Configure per-process thread optimization:

```ini
[MyGame]
# Boost main thread to P-core 3
module=MyGame.exe*, 2, [8], (3), priority_class=high

# Render threads to P-cores
threaddesc=Render, 2, [F0]

# Background threads to E-cores  
threaddesc=Worker, -1, [F00]

# Suspend resource-heavy threads
threaddesc=Telemetry, 300
```

### Thread Rule Format:
```
module=name OR threaddesc=description, priority, [affinity], (ideal), flags
```

- **Priority**: -15 (lowest) to 15 (highest), 200 (terminate), 300 (suspend)
- **Affinity**: [hex mask] or [auto] for automatic assignment
- **Ideal**: (core number) or (auto)
- **Flags**: disableboost, disableclones, priority_class=name

## 🛡️ Administrator Rights

**This program requires administrator privileges** to:
- Modify process priorities
- Set thread affinity
- Suspend/resume processes
- Install keyboard hooks
- Kill Explorer.exe (if enabled)

Always run as Administrator for full functionality.

## ⚠️ Safety & Warnings

### Important Notes:
1. **System Stability**: Improper thread rules can cause game crashes
2. **Test First**: Use debug mode to verify rules before deployment
3. **Backup Config**: Keep a working config.ini backup
4. **Antivirus**: May flag as false positive (low-level system access)
5. **Core 0**: Automatically avoided for game threads (reserved for OS)

### Safe Defaults:
- Start with empty thread rules
- Enable features one at a time
- Monitor logs for errors
- Don't suspend system-critical processes

## 📝 Logging

Logs are written to `RealtimeOptimizer.log`:

```
2025-10-13 11:30:45.123 [INFO ] Monitoring loop started
2025-10-13 11:31:02.456 [INFO ] Game detected: csgo.exe (PID: 12345)
2025-10-13 11:31:02.478 [INFO ] Activating game mode
2025-10-13 11:31:02.501 [INFO ] Suspended 8 processes
2025-10-13 11:35:15.789 [INFO ] Game no longer active, deactivating
```

Log levels: DEBUG, INFO, WARN, ERROR, CRIT

## 🔗 Dependencies

### Runtime:
- Windows 10/11 (x64)
- Visual C++ Redistributable 2022

### Build Time:
- Visual Studio 2022
- Windows SDK 10.0+
- C++17 compiler

### Libraries:
- ntdll.dll (NT API)
- dwmapi.dll (Desktop Window Manager)
- psapi.dll (Process Status API)

Provided as-is for educational and personal use.
