reg add hklm\system\controlset001\services\gpsvc /v "Start" /t REG_dword /d 4 /f
reg add hklm\system\currentcontrolset\services\gpsvc /v "Start" /t REG_dword /d 4 /f