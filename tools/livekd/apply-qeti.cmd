@echo off
setlocal
set "TOOLDIR=%~dp0"
set "SYMROOT=C:\Symbols"
if not exist "%SYMROOT%" mkdir "%SYMROOT%"
set "_NT_SYMBOL_PATH=srv*%SYMROOT%*https://msdl.microsoft.com/download/symbols"

rem Run LiveKD (WinDbg GUI) and feed it our command script.
rem NOTE: If -c isn’t honored on your build, the window will open;
rem just paste the one-liner from the notes below.
pushd "%TOOLDIR%"
livekd.exe -w -k -c "$$><%TOOLDIR%qeti.wds"
popd
endlocal
