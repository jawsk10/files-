takeown /f %SystemRoot%\System32\drivers\Acpidev.sys
takeown /f %SystemRoot%\System32\drivers\Acpipagr.sys
takeown /f %SystemRoot%\System32\drivers\Acpitime.sys
takeown /f %SystemRoot%\System32\drivers\Acpipmi.sys

icacls %SystemRoot%\System32\drivers\Acpidev.sys /grant %username%:F
icacls %SystemRoot%\System32\drivers\Acpipagr.sys /grant %username%:F
icacls %SystemRoot%\System32\drivers\Acpitime.sys /grant %username%:F
icacls %SystemRoot%\System32\drivers\Acpipmi.sys /grant %username%:F

ren %SystemRoot%\System32\drivers\Acpidev.sys AcpidevBACKUP.sys
ren %SystemRoot%\System32\drivers\Acpipagr.sys AcpipagrBACKUP.sys
ren %SystemRoot%\System32\drivers\Acpitime.sys AcpitimeBACKUP.sys
ren %SystemRoot%\System32\drivers\Acpipmi.sys AcpipmiBACKUP.sys