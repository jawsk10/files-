@echo off
setlocal EnabledelayedExpansion

:: Run Batch as Admin
set "params=%*"
cd /d "%~dp0" && ( if exist "%temp%\getadmin.vbs" del "%temp%\getadmin.vbs" ) && fsutil dirty query %systemdrive% 1>nul 2>nul || (  echo Set UAC = CreateObject^("Shell.Application"^) : UAC.ShellExecute "cmd.exe", "/k cd ""%~sdp0"" && %~s0 %params%", "", "runas", 1 >> "%temp%\getadmin.vbs" && "%temp%\getadmin.vbs" && exit /B )

:: Revert Fullscreenoptimization to default settings
REG delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /F /V __COMPAT_LAYER
pushd
DEL "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Disable-Fullscreenoptimization-Globally.bat"
popd

:: EnableDWM10
if not exist %systemroot%\ImmersiveControlPanel if exist %systemroot%\ImmersiveControlPanel.old ren %systemroot%\ImmersiveControlPanel.old ImmersiveControlPanel
if exist %systemroot%\ImmersiveControlPanel if exist %systemroot%\ImmersiveControlPanel.old rmdir /S /Q %systemroot%\ImmersiveControlPanel.old
if not exist %systemroot%\System32\Windows.UI.Logon.dll if exist %systemroot%\System32\Windows.UI.Logon.dll.old ren %systemroot%\System32\Windows.UI.Logon.dll.old Windows.UI.Logon.dll
if exist %systemroot%\System32\Windows.UI.Logon.dll if exist %systemroot%\System32\Windows.UI.Logon.dll.old del /q %systemroot%\System32\Windows.UI.Logon.dll.old
if not exist %systemroot%\System32\UIRibbon.dll if exist %systemroot%\System32\UIRibbon.dll.old ren %systemroot%\System32\UIRibbon.dll.old UIRibbon.dll
if exist %systemroot%\System32\UIRibbon.dll if exist %systemroot%\System32\UIRibbon.dll.old del /q %systemroot%\System32\UIRibbon.dll.old
if not exist %systemroot%\System32\UIRibbonRes.dll if exist %systemroot%\System32\UIRibbonRes.dll.old ren %systemroot%\System32\UIRibbonRes.dll.old UIRibbonRes.dll
if exist %systemroot%\System32\UIRibbonRes.dll if exist %systemroot%\System32\UIRibbonRes.dll.old del /q %systemroot%\System32\UIRibbonRes.dll.old
if not exist %systemroot%\System32\windows.immersiveshell.serviceprovider.dll if exist %systemroot%\System32\windows.immersiveshell.serviceprovider.dll.old ren %systemroot%\System32\windows.immersiveshell.serviceprovider.dll.old windows.immersiveshell.serviceprovider.dll
if exist %systemroot%\System32\windows.immersiveshell.serviceprovider.dll if exist %systemroot%\System32\windows.immersiveshell.serviceprovider.dll.old del /q %systemroot%\System32\windows.immersiveshell.serviceprovider.dll.old
if not exist %systemroot%\SystemApps\ShellExperienceHost_cw5n1h2txyewy if exist %systemroot%\SystemApps\ShellExperienceHost_cw5n1h2txyewy.old ren %systemroot%\SystemApps\ShellExperienceHost_cw5n1h2txyewy.old ShellExperienceHost_cw5n1h2txyewy
if exist %systemroot%\ShellExperienceHost_cw5n1h2txyewy if exist %systemroot%\ShellExperienceHost_cw5n1h2txyewy.old rmdir /S /Q %systemroot%\ShellExperienceHost_cw5n1h2txyewy.old
:: Revert classic UI tweaks
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer" /v "AltTabSettings" /f
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\MTCUVC" /v "EnableMtcUvc" /f
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\TestHooks" /v "ConsoleMode" /f
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\TestHooks" /v "XamlCredUIAvailable" /f
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\ImmersiveShell" /v "UseActionCenterExperience" /f
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\ImmersiveShell" /v "UseWin32BatteryFlyout" /f
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\ImmersiveShell" /v "UseWin32TrayClockExperience" /f
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\DWM" /v "DisallowComposition" /f
reg delete "HKCU\Software\Microsoft\Windows\DWM" /v "CompositionPolicy" /f
reg add "HKCU\Software\Microsoft\Windows\DWM" /v "Composition" /t REG_DWORD /d "1" /f
reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\Control Panel\Settings\Network" /v "ReplaceVan" /t REG_DWORD /d "0" /f
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Themes" /v "Start" /t REG_DWORD /d "2" /f
net start Themes
:: Revert DWM.exe changes
if exist %systemroot%\System32\dwm.exe.old takeown /F %systemroot%\System32\dwm.exe.old /A & icacls %systemroot%\System32\dwm.exe.old /grant "*S-1-5-32-544:(F)"
if exist %systemroot%\System32\dwm.exe if exist %systemroot%\System32\dwm.exe.old del /q %systemroot%\System32\dwm.exe
if not exist %systemroot%\System32\dwm.exe if exist %systemroot%\System32\dwm.exe.old ren %systemroot%\System32\dwm.exe.old dwm.exe

:: Logout
echo Logging off in...
timeout /T 10
logoff
