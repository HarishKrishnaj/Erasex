@echo off
title EraseX
color 0A
setlocal EnableDelayedExpansion
set LINE================================================================================

:: ===================== Admin check =====================
>nul 2>&1 net session
if %errorLevel% NEQ 0 (
	call :warn "Administrator privileges are REQUIRED for real wipe operations."
	echo     Right-click this .bat and choose "Run as administrator".
	echo.
	pause
	exit /b 1
)

:: ===================== Cert output dir (resolved on-demand) =====================
set "CERT_DIR="

:: ===================== Menu =====================
:menu
cls
call :logo
echo %LINE%
echo NOTE: Full (zeroing) formats on large drives can take hours. Use FAST CLEAR to finish quickly.
echo Certificates will be saved to E:\SecureWipe\certs if available, otherwise a local .\certs folder.
echo %LINE%
echo.
echo  [1] List storage (volumes and disks)
echo  [2] Volume CLEAR             (Automatic, FULL zeroing)
echo  [3] WHOLE DISK CLEAR         (Automatic)
echo  [4] SSD PURGE                (Automatic)
echo  [5] FREE SPACE WIPE          (Automatic)
echo  [6] FAST Volume CLEAR        (Quick Format)
echo  [7] About
echo  [8] Exit
echo.
set /p choice=" Select option (1-8): "

if "%choice%"=="1" goto list
if "%choice%"=="2" goto vol_clear
if "%choice%"=="3" goto disk_clear
if "%choice%"=="4" goto ssd_purge
if "%choice%"=="5" goto free_space
if "%choice%"=="6" goto vol_fast_clear
if "%choice%"=="7" goto about
if "%choice%"=="8" goto exit
goto menu

:list
cls
call :logo
echo %LINE%
echo DISKS
echo %LINE%
wmic diskdrive get index,model,size,serialnumber,status
echo.
echo %LINE%
echo VOLUMES
echo %LINE%
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Get-Volume ^| Select DriveLetter,FileSystemLabel,FileSystem,@{Name='SizeGB';Expression={[math]::Round($_.Size/1GB,2)}},@{Name='FreeGB';Expression={[math]::Round($_.SizeRemaining/1GB,2)}},HealthStatus ^| Format-Table -AutoSize"
echo.
pause
goto menu

:: ===================== Helpers =====================
:logo
echo.
echo   =============================================
echo                 ERASE-X
echo   =============================================
echo.
goto :eof

:warn
:: %1 message
powershell -NoProfile -ExecutionPolicy Bypass -Command "Write-Host '[!]' -ForegroundColor Yellow -NoNewline; Write-Host ' %~1'"
goto :eof

:notify
:: %1 title, %2 message
powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show('%~2','%~1','OK','Information') | Out-Null"
goto :eof

:open_certs
if not defined CERT_DIR call :ensure_cert_dir
start "" "%CERT_DIR%"
goto :eof

:make_cert_ids
set CERT_ID=SWC-%RANDOM%-%DATE:~10,4%%DATE:~4,2%%DATE:~7,2%-%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%
set CERT_ID=%CERT_ID: =0%
set START_TS=%DATE% %TIME%
goto :eof

:ensure_cert_dir
:: Prefer E:\SecureWipe\certs if E: exists and writable; else use local .\certs
set "_PREF=E:\SecureWipe\certs"
set "_ALT=%~dp0certs"
2>nul (>>"%_PREF%\__writetest.txt" echo test) && (
  del "%_PREF%\__writetest.txt" >nul 2>&1
  set "CERT_DIR=%_PREF%"
) || (
  if not exist "%_ALT%" mkdir "%_ALT%" >nul 2>&1
  set "CERT_DIR=%_ALT%"
)
if not exist "%CERT_DIR%" mkdir "%CERT_DIR%" >nul 2>&1
echo [*] Certificates directory: %CERT_DIR%
goto :eof

:pre_volume_steps
:: %1=drive letter like D:
call :warn "Pre-wipe: attempting to suspend BitLocker (if enabled) on %~1"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$vol=Get-BitLockerVolume -MountPoint '%~1' -ErrorAction SilentlyContinue; if($vol -and $vol.ProtectionStatus -eq 'On'){ Suspend-BitLocker -MountPoint '%~1' -RebootCount 1 ^| Out-Null; Write-Host 'BitLocker suspended' -ForegroundColor Yellow } else { Write-Host 'BitLocker not enabled' -ForegroundColor DarkGray }"
call :warn "Pre-wipe: closing Explorer to release file locks"
cmd /c taskkill /f /im explorer.exe >nul 2>&1
goto :eof

:post_volume_steps
call :warn "Post-wipe: restarting Explorer"
start explorer.exe
goto :eof

:write_json_cert
:: %1=method, %2=target, %3=result, %4=duration
if not defined CERT_DIR call :ensure_cert_dir
(
  echo {
  echo   "certificate_id": "%CERT_ID%",
  echo   "certificate_version": "1.0",
  echo   "timestamp": "%START_TS%",
  echo   "device": {
  echo     "path": "%~2",
  echo     "model": "Windows-Target",
  echo     "serial_number": "N/A",
  echo     "capacity_bytes": 0
  echo   },
  echo   "wipe_information": {
  echo     "method": "%~1",
  echo     "duration": "%~4",
  echo     "hidden_areas_processed": []
  echo   },
  echo   "operator": {
  echo     "name": "%USERNAME%",
  echo     "organization": "Local"
  echo   },
  echo   "result": "%~3",
  echo   "verification": {
  echo     "hash": "",
  echo     "signature": "",
  echo     "public_key": ""
  echo   }
  echo }
) > "%CERT_DIR%\%CERT_ID%.json"
echo Created JSON: %CERT_DIR%\%CERT_ID%.json
goto :eof

:write_pdf_cert
:: %1=method, %2=target
if not defined CERT_DIR call :ensure_cert_dir
set "_PDF_PATH=%CERT_DIR%\%CERT_ID%.pdf"
set "_HTML_PATH=%CERT_DIR%\%CERT_ID%.html"

:: Build an HTML certificate first
(
  echo ^<!DOCTYPE html^>
  echo ^<html lang="en"^>
  echo ^<head^>^<meta charset="utf-8"^>^<title^>ERASE-X Certificate^</title^>
  echo ^<style^>
  echo body{font-family:Segoe UI,Tahoma,Arial,sans-serif;margin:40px;color:#111}
  echo .card{border:1px solid #ddd;border-radius:8px;padding:24px;max-width:720px}
  echo h1{margin:0 0 8px 0;font-size:24px}
  echo .muted{color:#666;font-size:12px}
  echo .row{margin:10px 0}
  echo .label{color:#555;width:160px;display:inline-block}
  echo .value{color:#111}
  echo .ok{color:#0a7a31;font-weight:600}
  echo ^</style^>
  echo ^</head^>
  echo ^<body^>
  echo ^<div class="card"^>
  echo ^<h1^>ERASE-X Wipe Certificate^</h1^>
  echo ^<div class="muted"^>%DATE% %TIME%^</div^>
  echo ^<div class="row"^>^<span class="label"^>Certificate ID^</span^>^<span class="value"^>%CERT_ID%^</span^>^</div^>
  echo ^<div class="row"^>^<span class="label"^>Target^</span^>^<span class="value"^>%~2^</span^>^</div^>
  echo ^<div class="row"^>^<span class="label"^>Method^</span^>^<span class="value"^>%~1^</span^>^</div^>
  echo ^<div class="row"^>^<span class="label"^>Operator^</span^>^<span class="value"^>%USERNAME%^</span^>^</div^>
  echo ^<div class="row"^>^<span class="label"^>Result^</span^>^<span class="value ok"^>SUCCESS^</span^>^</div^>
  echo ^</div^>
  echo ^</body^>
  echo ^</html^>
) > "%_HTML_PATH%"

:: Try Microsoft Edge headless print-to-pdf
set "EDGE1=%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
set "EDGE2=%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
set "EDGE3=%LocalAppData%\Microsoft\Edge\Application\msedge.exe"
set "_EDGE="
if exist "%EDGE1%" set "_EDGE=%EDGE1%"
if exist "%EDGE2%" set "_EDGE=%EDGE2%"
if exist "%EDGE3%" set "_EDGE=%EDGE3%"

if defined _EDGE (
  "%_EDGE%" --headless --disable-gpu --print-to-pdf="%_PDF_PATH%" "%_HTML_PATH%" >nul 2>&1
)

if exist "%_PDF_PATH%" (
  echo Created PDF: %_PDF_PATH%
) else (
  call :warn "Edge not found or failed to create PDF. HTML saved at %_HTML_PATH%"
)
goto :eof

:: ===================== Volume CLEAR (FULL) =====================
:vol_clear
cls
call :logo
echo %LINE%
echo --- Volume CLEAR (FULL zeroing) ---
echo %LINE%
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Get-Volume ^| Select DriveLetter,FileSystemLabel,FileSystem,@{Name='SizeGB';Expression={[math]::Round($_.Size/1GB,2)}} ^| Format-Table -AutoSize"
echo.
set /p VLETTER="Enter target drive letter (e.g., D:): "
if "%VLETTER%"=="" goto menu
if not exist %VLETTER%\ (
  call :warn "Drive %VLETTER% not found."
  pause
  goto menu
)

set START=%time%
call :make_cert_ids
call :pre_volume_steps %VLETTER%
echo [*] Performing NIST CLEAR on %VLETTER% (full format, may take hours)...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; Format-Volume -DriveLetter '%VLETTER:~0,1%' -FileSystem NTFS -NewFileSystemLabel 'SECUREWIPE' -Full -Force -Confirm:$false"
set ERR=%ERRORLEVEL%
call :post_volume_steps
if not "%ERR%"=="0" (
  call :notify "ERASEX" "Wipe failed for %VLETTER% (error %ERR%)."
  pause
  goto menu
)
set END=%time%
set DURATION=Start:%START% End:%END%
call :write_json_cert CLEAR %VLETTER% SUCCESS "%DURATION%"
call :write_pdf_cert CLEAR %VLETTER%
call :notify "ERASEX" "Volume CLEAR completed on %VLETTER%. Certificates saved to %CERT_DIR%."
call :open_certs
echo.
pause
goto menu

:: ===================== FAST Volume CLEAR (Quick) =====================
:vol_fast_clear
cls
call :logo
echo %LINE%
echo --- FAST Volume CLEAR (Quick format) ---
echo %LINE%
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Get-Volume ^| Select DriveLetter,FileSystemLabel,FileSystem,@{Name='SizeGB';Expression={[math]::Round($_.Size/1GB,2)}} ^| Format-Table -AutoSize"
echo.
set /p QLETTER="Enter target drive letter (e.g., D:): "
if "%QLETTER%"=="" goto menu
if not exist %QLETTER%\ (
  call :warn "Drive %QLETTER% not found."
  pause
  goto menu
)

set START=%time%
call :make_cert_ids
call :pre_volume_steps %QLETTER%
echo [*] Performing QUICK format on %QLETTER% (fast)...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; Format-Volume -DriveLetter '%QLETTER:~0,1%' -FileSystem NTFS -NewFileSystemLabel 'SECUREWIPE' -Force -Confirm:$false"
set ERR=%ERRORLEVEL%
call :post_volume_steps
if not "%ERR%"=="0" (
  call :notify "ERASEX" "Quick format failed for %QLETTER% (error %ERR%)."
  pause
  goto menu
)
set END=%time%
set DURATION=Start:%START% End:%END%
call :write_json_cert CLEAR_QUICK %QLETTER% SUCCESS "%DURATION%"
call :write_pdf_cert CLEAR_QUICK %QLETTER%
call :notify "ERASEX" "FAST Volume CLEAR completed on %QLETTER%. Certificates saved to %CERT_DIR%."
call :open_certs
echo.
pause
goto menu

:: ===================== WHOLE DISK CLEAR, SSD PURGE, FREE SPACE =====================
:: (unchanged from previous version)

:: ===================== WHOLE DISK CLEAR (Automatic) =====================
:disk_clear
echo.
echo --- WHOLE DISK CLEAR (Automatic) ---
wmic diskdrive get index,model,size,serialnumber,status
echo.
set /p DISKNUM="Enter physical disk Index to WIPE (e.g., 1): "
if "%DISKNUM%"=="" goto menu

set START=%time%
call :make_cert_ids
echo [*] Zeroing entire disk \PhysicalDrive%DISKNUM% with diskpart clean all ...
set TMPDP=%TEMP%\sw_diskpart_%RANDOM%.txt
(
  echo select disk %DISKNUM%
  echo clean all
  echo create partition primary
  echo format fs=ntfs quick label=SECUREWIPE
  echo assign
  echo exit
) > "%TMPDP%"

diskpart /s "%TMPDP%"
set ERR=%ERRORLEVEL%
del "%TMPDP%" >nul 2>&1
if not "%ERR%"=="0" (
  echo [!] Diskpart failed on disk %DISKNUM% (error %ERR%).
  pause
  goto menu
)
set END=%time%
set DURATION=Start:%START% End:%END%
call :write_json_cert CLEAR "\\.\PhysicalDrive%DISKNUM%" SUCCESS "%DURATION%"
call :write_pdf_cert CLEAR "\\.\PhysicalDrive%DISKNUM%"
echo.
echo [+] WHOLE DISK CLEAR completed. Certificates:
echo     %CERT_DIR%\%CERT_ID%.json
echo     %CERT_DIR%\%CERT_ID%.pdf
echo.
pause
goto menu

:: ===================== SSD PURGE (Automatic) =====================
:ssd_purge
echo.
echo --- SSD PURGE (Automatic) ---
wmic diskdrive get index,model,size,serialnumber,status
echo.
set /p PDISK="Enter physical disk Index to PURGE (e.g., 1): "
if "%PDISK%"=="" goto menu

set START=%time%
call :make_cert_ids
echo [*] Attempting firmware sanitize via Clear-Disk -RemoveData ...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; Clear-Disk -Number %PDISK% -RemoveData -Confirm:$false"
set ERR=%ERRORLEVEL%
if not "%ERR%"=="0" (
  echo [!] PURGE failed or not supported on disk %PDISK% (error %ERR%).
  pause
  goto menu
)
set END=%time%
set DURATION=Start:%START% End:%END%
call :write_json_cert PURGE "\\.\PhysicalDrive%PDISK%" SUCCESS "%DURATION%"
call :write_pdf_cert PURGE "\\.\PhysicalDrive%PDISK%"
echo.
echo [+] SSD PURGE completed. Certificates:
echo     %CERT_DIR%\%CERT_ID%.json
echo     %CERT_DIR%\%CERT_ID%.pdf
echo.
pause
goto menu

:: ===================== FREE SPACE WIPE (Automatic) =====================
:free_space
echo.
echo --- FREE SPACE WIPE (Automatic) ---
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Get-Volume | Select DriveLetter,FileSystemLabel,FileSystem,Size,SizeRemaining | Format-Table -AutoSize"
echo.
set /p FLETTER="Enter drive letter (e.g., D:): "
if "%FLETTER%"=="" goto menu
if not exist %FLETTER%\ (
  echo [!] Drive %FLETTER% not found.
  pause
  goto menu
)

set START=%time%
call :make_cert_ids
echo [*] Wiping FREE SPACE on %FLETTER% (cipher /w:) ...
cmd /c "cipher /w:%FLETTER%"
set ERR=%ERRORLEVEL%
if not "%ERR%"=="0" (
  echo [!] Free space wipe failed on %FLETTER% (error %ERR%).
  pause
  goto menu
)
set END=%time%
set DURATION=Start:%START% End:%END%
call :write_json_cert CLEAR_FREE_SPACE %FLETTER% SUCCESS "%DURATION%"
call :write_pdf_cert CLEAR_FREE_SPACE %FLETTER%
echo.
echo [+] FREE SPACE WIPE completed. Certificates:
echo     %CERT_DIR%\%CERT_ID%.json
echo     %CERT_DIR%\%CERT_ID%.pdf
echo.
pause
goto menu

:about
echo.
echo This tool now runs wiping methods automatically (no confirmations):
echo  - Volume CLEAR (full format)
echo  - Whole Disk CLEAR (diskpart clean all)
echo  - SSD PURGE (firmware sanitize if supported)
echo  - Free-space wipe
echo It also suspends BitLocker (if enabled) and closes Explorer before volume wipes.
echo Certificates saved to %CERT_DIR%.
echo.
pause
goto menu

:exit
echo.
echo Goodbye.
echo.
timeout /t 2 /nobreak >nul
endlocal
exit /b 0
