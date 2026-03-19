powershell kill -name atieclxx
powershell kill -name atiesrxx
powershell kill -name amdfendrsr
DEL C:\ATIECLXX.EXE /S /F
DEL C:\ATIESRXX.EXE /S /F
DEL C:\AMDFENDRSR.EXE /S /F
DEL C:\ATIEAH64.EXE /S /F
DEL C:\ATIEAH32.EXE /S /F
DEL C:\DGTRAYICON.EXE /S /F
DEL C:\AMDFENDR.CTZ /S /F
DEL C:\AMDFENDR.ITZ /S /F
DEL C:\AMDFENDR.STZ /S /F
DEL C:\AMDLOGUM.EXE /S /F
DEL C:\RAPIDFIRE.DLL /S /F
DEL C:\RAPIDFIRE64.DLL /S /F
DEL C:\RAPIDFIRESERVER.DLL /S /F
DEL C:\RAPIDFIRESERVER64.DLL /S /F
del c:\amdfendrmgr.stz /s /f
del c:\amdfendrsr.etz /s /f
del c:\amdkernelevents.mc /s /f
del c:\eeurestart.exe /s /f
del c:\regamdcomp.exe /s /f
del c:\vulkaninfo32.exe /s /f
del c:\vulkaninfo64.exe /s /f
del c:\clinfo.exe /s /f
del c:\amdsmi.exe /s /f
del c:\amdbugreporttool.exe /s /f
del c:\vulkaninfo.exe /s /f
del c:\vulkaninfo-1-999-0-0-0.exe /s /f
del c:\atihdwt6.sys /s /f
sc stop amdfendr
sc stop amdfendrmgr
del c:\amdfendr.sys /s /f
del c:\amdfendrmgr.sys /s /f
REG ADD HKLM\SOFTWARE\AMD\EEU /V AMDLOGINSTALLSTATUS /T REG_DWORD /D 0 /F
REG DELETE "HKLM\SOFTWARE\AMDLOG" /F
DEL C:\ATI2EREC.DLL /S /F
DEL C:\AMDXE.SYS /S /F
DEL C:\OPENCL.DLL /S /F
REG DELETE "HKLM\SYSTEM\CONTROLSET001\CONTROL\CLASS\{4D36E968-E325-11CE-BFC1-08002BE10318}\0000\UMD\AMDLOG" /F
SC DELETE AMDXE
SC DELETE AMDFENDR
SC DELETE AMDFENDRMGR
REG DELETE "HKLM\SYSTEM\DRIVERDATABASE\DEVICEIDS\ROOT\AMDLOG" /F
REG DELETE "HKLM\SYSTEM\DRIVERDATABASE\DEVICEIDS\ROOT\AMDXE" /F
powershell del 'hklm:\system\driverdatabase\driverpackages\amdfendr*' -recurse
powershell del 'hklm:\system\driverdatabase\driverpackages\amdxe*' -recurse
REG DELETE HKLM\SOFTWARE\MICROSOFT\WINDOWS\CURRENTVERSION\SETUP\PNPLOCKDOWNFILES /V SOURCE /F
REG DELETE HKLM\SOFTWARE\MICROSOFT\WINDOWS\CURRENTVERSION\SETUP\PNPLOCKDOWNFILES /V OWNERS /F
REG ADD HKLM\SYSTEM\CONTROLSET001\CONTROL\CLASS\{4D36E968-E325-11CE-BFC1-08002BE10318}\0000 /V KMD_ENABLEAMDFENDROPTIONS /T REG_DWORD /D 0 /F
POWERSHELL DEL 'HKLM:\SYSTEM\CONTROLSET001\SERVICES\AMD CRASH*' -RECURSE
POWERSHELL DEL 'HKLM:\SYSTEM\CONTROLSET001\SERVICES\AMD EXTERNAL*' -RECURSE
POWERSHELL DEL 'HKLM:\SYSTEM\CONTROLSET001\SERVICES\ATIHD*' -RECURSE
POWERSHELL DEL 'HKLM:\SYSTEM\CONTROLSET001\SERVICES\ATIEREC*' -RECURSE
powershell "Get-ItemProperty -Path 'HKLM:\SYSTEM\DriverDatabase\DriverInfFiles\*' -Name Configurations | Where-Object Configurations -eq 'amdfender_Install' | RemoveItem"
powershell "Get-ItemProperty -Path 'HKLM:\SYSTEM\DriverDatabase\DriverInfFiles\*' -Name Configurations | Where-Object Configurations -eq 'amdafd_Install' | Remove-Item"
powershell "Get-ItemProperty -Path 'HKLM:\SYSTEM\DriverDatabase\DriverInfFiles\*' -Name Configurations | Where-Object Configurations -eq 'AMDSMBus64' | Remove-Item"
powershell "Get-ItemProperty -Path 'HKLM:\SYSTEM\DriverDatabase\DriverInfFiles\*' -Name Configurations | Where-Object Configurations -eq 'AMDXE.NT' | Remove-Item"
powershell del 'hklm:\system\driverdatabase\driverpackages\amdafd*' -recurse
powershell del 'hklm:\system\driverdatabase\driverpackages\amdpcidev*' -recurse

