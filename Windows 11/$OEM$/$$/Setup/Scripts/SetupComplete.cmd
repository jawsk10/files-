@echo off

::Disable Hibernation...
powercfg /hibernate off

::[User Accounts]
CD /D "%~dp0dat\OOLE"
START /WAIT ".." OOLE.exe

:: Cleanup!
rd /q /s "%WINDIR%\Setup\Scripts\dat"
del /q /f "%WINDIR%\Setup\Scripts\SetupComplete.cmd"
EXIT
