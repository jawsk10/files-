@echo off
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo   ERROR: Run this as Administrator
    echo   Right-click -^> Run as administrator
    echo.
    pause
    exit /b 1
)

:menu
cls
echo.
echo   ==========================================================
echo   GRUB HPET Patcher
echo   ==========================================================
echo.
echo   1. Install
echo   2. Uninstall
echo   3. Check Status
echo   4. Exit
echo.
set /p choice="  Choose [1-4]: "

if "%choice%"=="1" (
    powershell -ExecutionPolicy Bypass -File "%~dp0Setup-GRUB-HPET.ps1" -Install
    pause
    goto menu
)
if "%choice%"=="2" (
    powershell -ExecutionPolicy Bypass -File "%~dp0Setup-GRUB-HPET.ps1" -Uninstall
    pause
    goto menu
)
if "%choice%"=="3" (
    powershell -ExecutionPolicy Bypass -File "%~dp0Setup-GRUB-HPET.ps1" -Status
    pause
    goto menu
)
if "%choice%"=="4" exit /b 0

goto menu
