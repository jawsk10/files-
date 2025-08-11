@echo off
REM This script searches all registry hives for the DWORD value
REM "WppRecorder_UseTimeStamp" and sets its data to 0 wherever it is found.
REM Run this script with administrative privileges.

setlocal enabledelayedexpansion

REM List of root hives to search. You can add or remove hives as needed.
for %%H in (HKLM HKCU HKCR HKU) do (
    echo Searching %%H ...
    REM Query for keys containing the value name and parse only lines starting with "HKEY"
    for /f "delims=" %%K in ('reg query "%%H" /f WppRecorder_UseTimeStamp /s /t REG_DWORD 2^>nul ^| findstr /r /i "^HKEY"') do (
        echo    Updating %%K
        reg add "%%K" /v WppRecorder_UseTimeStamp /t REG_DWORD /d 0 /f >nul
    )
)

echo.
echo All occurrences of WppRecorder_UseTimeStamp have been set to 0.
pause
endlocal
