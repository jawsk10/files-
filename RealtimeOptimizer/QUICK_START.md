# RealtimeOptimizer - Quick Start Guide

## Files Included

All files have been fixed and are ready to compile:

### Source Files (.cpp):
- ✅ main.cpp - Main entry point and system tray
- ✅ ConfigParser.cpp - Configuration file parsing
- ✅ CPUTopology.cpp - CPU detection (P-cores, E-cores, SMT)
- ✅ GameDetector.cpp - Game window detection
- ✅ HookManager.cpp - Keyboard hooks and cursor clipping
- ✅ Logger.cpp - Logging system
- ✅ ProcessManager.cpp - Process suspension/priority management
- ✅ ThreadManager.cpp - Thread affinity and priority control

### Header Files (.h):
- ✅ All corresponding .h files for the above

### Configuration:
- ✅ config.ini - Application configuration

### Project Files:
- ✅ RealtimeOptimizer.sln - Visual Studio solution
- ✅ RealtimeOptimizer.vcxproj - Visual Studio project

## Quick Compilation Steps

### Method 1: Using Visual Studio (Recommended)

1. **Open the Solution**
   - Double-click `RealtimeOptimizer.sln`
   - Visual Studio 2022 will open

2. **Select Configuration**
   - Choose "Release" and "x64" from the toolbar dropdowns

3. **Build**
   - Press F7 or go to Build → Build Solution
   - Wait for compilation to complete

4. **Run**
   - The executable will be in `bin\Release\RealtimeOptimizer.exe`
   - Right-click the .exe → "Run as Administrator"

### Method 2: Using MSBuild (Command Line)

```cmd
# Open "Developer Command Prompt for VS 2022"

# Navigate to the project folder
cd C:\path\to\project

# Build Release version
msbuild RealtimeOptimizer.sln /p:Configuration=Release /p:Platform=x64

# The executable will be in bin\Release\
```

### Method 3: Manual Compilation

```cmd
# Open "Developer Command Prompt for VS 2022"

cl /EHsc /std:c++17 /DUNICODE /D_UNICODE /O2 ^
   ConfigParser.cpp CPUTopology.cpp GameDetector.cpp ^
   HookManager.cpp Logger.cpp main.cpp ^
   ProcessManager.cpp ThreadManager.cpp ^
   /link ntdll.lib dwmapi.lib psapi.lib ^
   /SUBSYSTEM:CONSOLE /MANIFESTUAC:level='requireAdministrator' ^
   /OUT:RealtimeOptimizer.exe
```

## What Was Fixed

All compilation errors have been resolved:

1. ✅ **Unicode String Issues** - All Windows API calls now use wide strings (L"...")
2. ✅ **Missing Headers** - Added `<windows.h>`, `<tlhelp32.h>` where needed
3. ✅ **Console Functions** - Added console color constants
4. ✅ **Type Redefinitions** - Fixed CPU topology structure definitions
5. ✅ **Unsafe Functions** - Replaced `localtime()` with `localtime_s()`
6. ✅ **String Functions** - Changed `strcpy_s()` to `wcscpy_s()` for Unicode

## First Run

After successful compilation:

1. **Copy config.ini** to the same folder as RealtimeOptimizer.exe
2. **Run as Administrator** (required for most features)
3. **Edit config.ini** to customize behavior

### Command Line Options:

```cmd
RealtimeOptimizer.exe             # Normal mode with console
RealtimeOptimizer.exe --silent    # Hide console window
RealtimeOptimizer.exe --tray      # Run in system tray
RealtimeOptimizer.exe --debug     # Enable debug logging
```

### System Tray Mode:
```cmd
RealtimeOptimizer.exe --tray
```
- Right-click tray icon for menu
- Left-click to show/hide console
- Select "Exit" to close

## Configuration

Edit `config.ini` to customize:

### Basic Settings:
```ini
[Settings]
UpdateTimeout=100                    # Check interval (ms)
EnableKillExplorer=false            # Kill Explorer during gaming
WinBlockKeys=true                   # Block Windows key
BlockNoGamingMonitor=0              # Gaming monitor index
```

### Add Your Games:
```ini
[Games]
YourGame.exe
AnotherGame.exe
```

### Process Management:
```ini
[ProcessesToSuspend]
Steam.exe
Discord.exe

[SetProcessesToIdlePriority]
OneDrive.exe
Dropbox.exe
```

### Advanced Thread Rules:
```ini
[YourGame]
module=YourGame.exe*, 2, [auto], priority_class=high
threaddesc=Main Thread, 2, [3]
threaddesc=Render, 2, [C]
```

## Troubleshooting

### "The application was unable to start correctly"
- **Solution:** Make sure you're running on Windows 10/11
- Ensure all Visual C++ Runtime libraries are installed

### "Access Denied" errors
- **Solution:** Run as Administrator
- Right-click → "Run as administrator"

### Game not detected
- **Solution:** Add game executable to [Games] section in config.ini
- Use exact filename (case-insensitive)

### No performance improvement
- **Solution:** 
  - Check if game mode is activating (console output)
  - Verify thread rules match your game
  - Enable debug mode to see detailed logs

### Antivirus blocking
- **Solution:** Add exception for RealtimeOptimizer.exe
- This is a false positive due to low-level system access

## Features

✅ **Game Detection** - Automatically detect when games are running
✅ **Process Management** - Suspend/resume background processes
✅ **Priority Control** - Boost game process priority
✅ **Thread Optimization** - Per-thread affinity and priority
✅ **CPU Topology** - P-core/E-core detection (Intel 12th gen+)
✅ **Keyboard Hooks** - Block Windows key during gaming
✅ **Cursor Clipping** - Lock cursor to game window
✅ **Explorer Control** - Optionally kill Explorer to free resources
✅ **System Tray** - Minimize to tray for background operation
✅ **Extensive Logging** - Debug and track all operations

## Performance Tips

1. **Use Release Build** - Much faster than Debug
2. **Run as Admin** - Required for most features
3. **Configure Your Games** - Add all games to config.ini
4. **Test Settings** - Use debug mode first to verify
5. **Monitor Logs** - Check RealtimeOptimizer.log for issues

## Support

For issues or questions, refer to:
- **COMPILATION_FIXES.md** - Detailed fix documentation
- **config.ini** - Commented configuration examples
- **RealtimeOptimizer.log** - Runtime log file

## Safety Notes

⚠️ **IMPORTANT:**
- This program modifies system-level processes
- Use at your own risk
- Test in Debug mode first
- Don't suspend critical system processes
- Keep backups of your configuration

## License

All source code provided as-is for educational purposes.

---

**Ready to optimize your gaming performance!** 🎮🚀
