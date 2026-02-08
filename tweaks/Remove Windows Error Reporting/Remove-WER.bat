@echo off
:: Self-elevate if not admin
net session >nul 2>nul
if %errorlevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "%~dp0Remove-WER.ps1" -Force -SkipRestorePoint
pause
