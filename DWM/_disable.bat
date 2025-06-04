@echo off
setlocal EnabledelayedExpansion

:: Run Batch as Admin
set "params=%*"
cd /d "%~dp0" && ( if exist "%temp%\getadmin.vbs" del "%temp%\getadmin.vbs" ) && fsutil dirty query %systemdrive% 1>nul 2>nul || (  echo Set UAC = CreateObject^("Shell.Application"^) : UAC.ShellExecute "cmd.exe", "/k cd ""%~sdp0"" && %~s0 %params%", "", "runas", 1 >> "%temp%\getadmin.vbs" && "%temp%\getadmin.vbs" && exit /B )

echo ATTENTION if you run this script UAC will be "broken". To accept UAC requests from now on, you need to press 2x tab and than enter.
:PROMPT
SET /P AREYOUSURE=Do you still want to continue (Y/[N])?
IF /I "%AREYOUSURE%" NEQ "Y" GOTO END

:: Disable Fullscreenoptimization globally
:: https://docs.microsoft.com/de-de/windows/deployment/planning/compatibility-fixes-for-windows-8-windows-7-and-windows-vista
pushd
copy "Disable-Fullscreenoptimization-Globally.bat" "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
popd

:: DisableDWM10
:: Take Ownership
if exist %systemroot%\ImmersiveControlPanel takeown /F %systemroot%\ImmersiveControlPanel /R /A & icacls %systemroot%\ImmersiveControlPanel /grant "*S-1-5-32-544:(F)" /T
if exist %systemroot%\System32\Windows.UI.Logon.dll takeown /F %systemroot%\System32\Windows.UI.Logon.dll /A & icacls %systemroot%\System32\Windows.UI.Logon.dll /grant "*S-1-5-32-544:(F)"
if exist %systemroot%\System32\UIRibbon.dll takeown /F %systemroot%\System32\UIRibbon.dll /A & icacls %systemroot%\System32\UIRibbon.dll /grant "*S-1-5-32-544:(F)"
if exist %systemroot%\System32\UIRibbonRes.dll takeown /F %systemroot%\System32\UIRibbonRes.dll /A & icacls %systemroot%\System32\UIRibbonRes.dll /grant "*S-1-5-32-544:(F)"
if exist %systemroot%\System32\dwm.exe takeown /F %systemroot%\System32\dwm.exe /A & icacls %systemroot%\System32\dwm.exe /grant "*S-1-5-32-544:(F)"
if exist %systemroot%\System32\windows.immersiveshell.serviceprovider.dll takeown /F %systemroot%\System32\windows.immersiveshell.serviceprovider.dll /A & icacls %systemroot%\System32\windows.immersiveshell.serviceprovider.dll /grant "*S-1-5-32-544:(F)"
if exist %systemroot%\SystemApps\ShellExperienceHost_cw5n1h2txyewy takeown /F %systemroot%\SystemApps\ShellExperienceHost_cw5n1h2txyewy /R /A & icacls %systemroot%\SystemApps\ShellExperienceHost_cw5n1h2txyewy /grant "*S-1-5-32-544:(F)" /T
SetACL.exe -on "HKLM\Software\Microsoft\Windows\CurrentVersion\Control Panel\Settings\Network" -ot reg -actn setowner -ownr "n:S-1-5-32-544"
SetACL.exe -on "HKLM\Software\Microsoft\Windows\CurrentVersion\Control Panel\Settings\Network" -ot reg -actn ace -ace "n:S-1-5-32-544;p:full"
:: Taskkill
taskkill /F /IM ApplicationFrameHost.exe
taskkill /F /IM RuntimeBroker.exe
taskkill /F /IM ShellExperienceHost.exe
taskkill /F /IM SystemSettings.exe
if not exist %systemroot%\ImmersiveControlPanel.old if exist %systemroot%\ImmersiveControlPanel ren %systemroot%\ImmersiveControlPanel ImmersiveControlPanel.old
if exist %systemroot%\ImmersiveControlPanel.old if exist %systemroot%\ImmersiveControlPanel rmdir /S /Q %systemroot%\ImmersiveControlPanel
if not exist %systemroot%\System32\Windows.UI.Logon.dll.old if exist %systemroot%\System32\Windows.UI.Logon.dll ren %systemroot%\System32\Windows.UI.Logon.dll Windows.UI.Logon.dll.old
if exist %systemroot%\System32\Windows.UI.Logon.dll.old if exist %systemroot%\System32\Windows.UI.Logon.dll del /q %systemroot%\System32\Windows.UI.Logon.dll
if not exist %systemroot%\System32\UIRibbon.dll.old if exist %systemroot%\System32\UIRibbon.dll ren %systemroot%\System32\UIRibbon.dll UIRibbon.dll.old
if exist %systemroot%\System32\UIRibbon.dll.old if exist %systemroot%\System32\UIRibbon.dll del /q %systemroot%\System32\UIRibbon.dll
if not exist %systemroot%\System32\UIRibbonRes.dll.old if exist %systemroot%\System32\UIRibbonRes.dll ren %systemroot%\System32\UIRibbonRes.dll UIRibbonRes.dll.old
if exist %systemroot%\System32\UIRibbonRes.dll.old if exist %systemroot%\System32\UIRibbonRes.dll del /q %systemroot%\System32\UIRibbonRes.dll
if not exist %systemroot%\System32\windows.immersiveshell.serviceprovider.dll.old if exist %systemroot%\System32\windows.immersiveshell.serviceprovider.dll ren %systemroot%\System32\windows.immersiveshell.serviceprovider.dll windows.immersiveshell.serviceprovider.dll.old
if exist %systemroot%\System32\windows.immersiveshell.serviceprovider.dll.old if exist %systemroot%\System32\windows.immersiveshell.serviceprovider.dll del /q %systemroot%\System32\windows.immersiveshell.serviceprovider.dll
if not exist %systemroot%\SystemApps\ShellExperienceHost_cw5n1h2txyewy.old if exist %systemroot%\SystemApps\ShellExperienceHost_cw5n1h2txyewy ren %systemroot%\SystemApps\ShellExperienceHost_cw5n1h2txyewy ShellExperienceHost_cw5n1h2txyewy.old
if exist %systemroot%\ShellExperienceHost_cw5n1h2txyewy.old if exist %systemroot%\ShellExperienceHost_cw5n1h2txyewy rmdir /S /Q %systemroot%\ShellExperienceHost_cw5n1h2txyewy
:: Tweaks for classic UI
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer" /v "AltTabSettings" /t REG_DWORD /d "0" /f
reg add "HKCU\Software\Microsoft\Windows\DWM" /v "CompositionPolicy" /t REG_DWORD /d "0" /f
reg add "HKCU\Software\Microsoft\Windows\DWM" /v "Composition" /t REG_DWORD /d "0" /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DWM" /v "DisallowComposition" /t REG_DWORD /d "1" /f
reg add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\MTCUVC" /v "EnableMtcUvc" /t REG_DWORD /d "0" /f
reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\TestHooks" /v "ConsoleMode" /t REG_DWORD /d "1" /f
reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\TestHooks" /v "XamlCredUIAvailable" /t REG_DWORD /d "0" /f
reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\Control Panel\Settings\Network" /v "ReplaceVan" /t REG_DWORD /d "2" /f
reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\ImmersiveShell" /v "UseActionCenterExperience" /t REG_DWORD /d "0" /f
reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\ImmersiveShell" /v "UseWin32BatteryFlyout" /t REG_DWORD /d "1" /f
reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\ImmersiveShell" /v "UseWin32TrayClockExperience" /t REG_DWORD /d "1" /f
reg add "HKLM\System\CurrentControlSet\Services\Themes" /v "Start" /t REG_DWORD /d "4" /f
net stop Themes
:: Confuse Windows with a fake dwm.exe
if exist %systemroot%\System32\dwm.exe takeown /F %systemroot%\System32\dwm.exe /A & icacls %systemroot%\System32\dwm.exe /grant "*S-1-5-32-544:(F)"
if not exist %systemroot%\System32\dwm.exe.old if exist %systemroot%\System32\dwm.exe ren %systemroot%\System32\dwm.exe dwm.exe.old
if exist %systemroot%\System32\dwm.exe.old if exist %systemroot%\System32\dwm.exe del /q %systemroot%\System32\dwm.exe
echo N| copy/-Y "%systemroot%\System32\rundll32.exe" "%systemroot%\System32\dwm.exe"

:: Logout
echo Logging off in...
timeout /T 10
logoff

:END
endlocal
