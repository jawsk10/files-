# WER Amputation Kit

## For those who don't want to build the .dll files manually, skip to Step 2.

Complete removal of Windows Error Reporting from Windows 11.

## Files

| File | Purpose |
|------|---------|
| `Remove-WER.ps1` | Main removal script (run as admin) |
| `wer_stub.c` | Stub DLL source — drop-in wer.dll replacement |
| `wer_stub.def` | Module definition file for exports |

## Step 1: Compile the Stub DLL

You need both an **x64** and **x86** build of the stub if you're on a 64-bit system.

### MSVC (Developer Command Prompt)

**x64** (from x64 Native Tools Command Prompt):
```
cl /c /O1 /GS- wer_stub.c
link /dll /ENTRY:DllMain /DEF:wer_stub.def /NODEFAULTLIB kernel32.lib wer_stub.obj /out:wer.dll
```

**x86** (from x86 Native Tools Command Prompt):
```
cl /c /O1 /GS- wer_stub.c
link /dll /ENTRY:DllMain /DEF:wer_stub.def /NODEFAULTLIB kernel32.lib wer_stub.obj /out:wer32.dll
```

### MinGW

**x64**:
```
x86_64-w64-mingw32-gcc -shared -O2 -s -o wer.dll wer_stub.c wer_stub.def -lkernel32
```

**x86**:
```
i686-w64-mingw32-gcc -shared -O2 -s -o wer32.dll wer_stub.c wer_stub.def -lkernel32
```

## Step 2: Run the Removal Script

Your folder should look like this before running:

```
WER_Amputation_Kit\
├── Remove-WER.ps1      (the script)
├── wer.dll              (x64 stub you compiled)
├── wer32.dll            (x86 stub you compiled)
├── wer_stub.c           (source — not needed at runtime)
└── wer_stub.def         (source — not needed at runtime)
```

### Running the script

### Simply run Remove-WER.bat<br>

or

1. Right-click the **Start** button → **Terminal (Admin)** or **PowerShell (Admin)**
2. `cd` into the folder containing the script and DLLs:
   ```powershell
   cd "C:\path\to\Remove Windows Error Reporting"
   ```
3. Allow the script to run (one-time, current session only):
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process
   ```
4. Run it:
   ```powershell
   .\Remove-WER.ps1
   ```
5. Type `AMPUTATE` when prompted and press Enter
6. Wait for all 10 phases to complete
7. Type `y` when asked to reboot, or reboot manually later

### Flags

| Flag | Effect |
|------|--------|
| `-Force` | Skip the `AMPUTATE` confirmation prompt |
| `-SkipRestorePoint` | Don't create a system restore point before changes |
| `-StubDllPath "C:\other\wer.dll"` | Custom path to x64 stub (default: same folder as script) |
| `-Stub32DllPath "C:\other\wer32.dll"` | Custom path to x86 stub (default: same folder as script) |

Example with flags:
```powershell
.\Remove-WER.ps1 -Force -SkipRestorePoint
```

## What Gets Removed

- **WerSvc** service (stopped, disabled, deleted)
- **WerFault.exe**, **WerFaultSecure.exe**, **wermgr.exe** (deleted)
- **wer.dll** (replaced with stub), **werui.dll**, **wersvc.dll** (deleted)
- **werkernel.sys** kernel driver (deleted, service disabled)
- All WER **registry policies** set to disabled
- WER **scheduled tasks** removed
- WER **ETW providers** and autologger sessions disabled
- All **crash dump stores** cleaned (ProgramData, AppData, Minidump, MEMORY.DMP)
- **IFEO redirects** set to block resurrection of WerFault/wermgr
- **AeDebug** (JIT debugger) WerFault entries removed
- Kernel **CrashDumpEnabled** set to 0

## Reverting

Backups of all removed binaries are saved to `.\wer_backup\`. To restore:

1. Delete the IFEO entries under `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\WerFault.exe` (and siblings)
2. Copy backups from `.\wer_backup\` back to `C:\Windows\System32\`
3. Run `sfc /scannow` to let Windows repair component store references
4. Re-enable WerSvc: `sc.exe config WerSvc start= demand`

Or just restore the system restore point that was created before removal.
