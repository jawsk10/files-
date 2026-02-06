@echo off
setlocal enabledelayedexpansion
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo  ERROR: Run this as Administrator!
    echo  Right-click and select "Run as administrator"
    pause
    exit /b 1
)

echo.
echo  ==========================================================
echo  ACPI Override Tool v2.1 - Full DSDT Replacement
echo  ==========================================================
echo.
echo  Choose an option:
echo.
echo  1 = Scan DSDT: show HPET info
echo  2 = Scan DSDT: list GPE handlers
echo  3 = Disable HPET only [recommended]
echo  4 = Disable HPET + stub all GPE [risky on laptops]
echo  5 = Uninstall (remove override, restore defaults)
echo.

REM Auto-detect DSDT.bin
set "DSDT_ARG="
for %%f in ("%~dp0DSDT.bin" "%~dp0DSDT.dat" "%~dp0dsdt.bin") do (
    if exist "%%~f" (
        set "DSDT_ARG=-DSDTPath "%%~f""
        echo  [i] Found DSDT: %%~f
        goto :found_dsdt
    )
)
echo  [i] No DSDT.bin found - will try auto-extract from registry.
echo      For best results, place DSDT.bin in the same folder.
:found_dsdt
echo.

set /p "choice=Enter 1-5: "

if "%choice%"=="1" (
    powershell -ExecutionPolicy Bypass -File "%~dp0Disable-HPET.ps1" %DSDT_ARG% -ListHPET
    pause
    exit /b 0
)
if "%choice%"=="2" (
    powershell -ExecutionPolicy Bypass -File "%~dp0Disable-HPET.ps1" %DSDT_ARG% -ListGPE
    pause
    exit /b 0
)
if "%choice%"=="3" (
    echo.
    echo  This will patch your full DSDT and deploy via acpitabl.dat.
    echo  Test signing will be enabled. Undo with option 5.
    echo.
    set /p "confirm=Continue? (Y/N): "
    if /i not "!confirm!"=="Y" (
        echo Cancelled.
        pause
        exit /b 0
    )
    powershell -ExecutionPolicy Bypass -File "%~dp0Disable-HPET.ps1" %DSDT_ARG% -DisableHPET -Install
    pause
    exit /b 0
)
if "%choice%"=="4" (
    echo.
    echo  WARNING: Stubbing all GPE handlers may break:
    echo   - Thermal management / fan control
    echo   - Battery reporting
    echo   - Lid switch / sleep / wake
    echo.
    echo  Only recommended for desktops after targeted testing.
    echo.
    set /p "confirm=Type YES to continue: "
    if /i not "!confirm!"=="YES" (
        echo Cancelled.
        pause
        exit /b 0
    )
    powershell -ExecutionPolicy Bypass -File "%~dp0Disable-HPET.ps1" %DSDT_ARG% -DisableHPET -StubAllGPE -Install
    pause
    exit /b 0
)
if "%choice%"=="5" (
    powershell -ExecutionPolicy Bypass -File "%~dp0Disable-HPET.ps1" -Uninstall
    pause
    exit /b 0
)

echo Invalid choice.
pause
