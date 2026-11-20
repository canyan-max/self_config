@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "ERRORLEVEL="
rem Read range comes from ; READ_START / ; READ_BYTES in flash.jlink.
set "READ_START="
set "READ_BYTES="
set "RESULT=1"
set "WORK_DIR="
set "COMMAND_FILE="
set "KEEP_READBACK="
set "PENDING_FILE="
set "TEMPLATE=%~dp0flash.jlink"
set "OUTPUT_DIR=%~dp0readback"

if not "%~1"=="" (
    echo [ERROR] This script takes no arguments. Double-click it to read Flash.
    goto finish
)
if not exist "%TEMPLATE%" (
    echo [ERROR] Missing chip configuration: "%TEMPLATE%"
    goto finish
)
rem Read configuration only; NEVER execute the programming template.
set "DEVICE="
set "DEVICE_COUNT=0"
set "DEVICE_INVALID=0"
for /f "usebackq tokens=1,2,*" %%A in ("%TEMPLATE%") do if /i "%%A"=="device" (
    set /a DEVICE_COUNT+=1 >nul
    set "DEVICE=%%B"
    if not "%%C"=="" set "DEVICE_INVALID=1"
)
if not "%DEVICE_COUNT%"=="1" goto invalid_device
if not "%DEVICE_INVALID%"=="0" goto invalid_device
if not defined DEVICE goto invalid_device
rem Semicolon metadata is already skipped by flash.bat's FOR /F reader.
rem Override EOL here so the read tool can parse those configuration lines.
set "READ_START_COUNT=0"
set "READ_BYTES_COUNT=0"
set "READ_RANGE_INVALID=0"
for /f "usebackq eol=| tokens=1,2,3,*" %%A in ("%TEMPLATE%") do if "%%A"==";" (
    if /i "%%B"=="READ_START" (
        set /a READ_START_COUNT+=1 >nul
        set "READ_START=%%C"
        if not "%%D"=="" set "READ_RANGE_INVALID=1"
    )
    if /i "%%B"=="READ_BYTES" (
        set /a READ_BYTES_COUNT+=1 >nul
        set "READ_BYTES=%%C"
        if not "%%D"=="" set "READ_RANGE_INVALID=1"
    )
)
if not "%READ_START_COUNT%"=="1" goto invalid_range
if not "%READ_BYTES_COUNT%"=="1" goto invalid_range
if not "%READ_RANGE_INVALID%"=="0" goto invalid_range
if not defined READ_START goto invalid_range
if not defined READ_BYTES goto invalid_range
rem Validate data through SET output before expanding it as arithmetic/code.
set READ_START | findstr /r /i /x /c:"READ_START=0x[0-9a-f][0-9a-f]*" >nul
if errorlevel 1 goto invalid_range
set READ_BYTES | findstr /r /i /x /c:"READ_BYTES=0x[0-9a-f][0-9a-f]*" >nul
if errorlevel 1 goto invalid_range
if not "%READ_START:~10%"=="" goto invalid_range
if not "%READ_BYTES:~10%"=="" goto invalid_range
set /a EXPECTED_SIZE=%READ_BYTES% >nul 2>&1
if errorlevel 1 goto invalid_range
if %EXPECTED_SIZE% leq 0 goto invalid_range

set "JLINK_EXE="
if exist "%~dp0JLink.exe" (
    set "JLINK_EXE=%~dp0JLink.exe"
) else (
    for /f "delims=" %%J in ('where JLink.exe 2^>nul') do if not defined JLINK_EXE set "JLINK_EXE=%%J"
)
if not defined JLINK_EXE (
    echo [ERROR] JLink.exe was not found. Add its installation folder to PATH.
    goto finish
)
if not defined TEMP (
    echo [ERROR] The TEMP environment variable is not configured.
    goto finish
)
if not exist "%TEMP%\" (
    echo [ERROR] TEMP must point to an existing writable folder.
    goto finish
)
if not exist "%OUTPUT_DIR%\" (
    mkdir "%OUTPUT_DIR%" 2>nul
    if errorlevel 1 (
        echo [ERROR] Could not create the readback output folder.
        goto finish
    )
)

:new_temp
set "RUN_ID=%RANDOM%_%RANDOM%"
set "WORK_NAME=mppt_read_%RUN_ID%"
set "WORK_DIR=%TEMP%\%WORK_NAME%"
set "OUTPUT_FILE=%OUTPUT_DIR%\flash_%RUN_ID%.bin"
set "PENDING_FILE=%OUTPUT_FILE%.part"
if exist "%WORK_DIR%" goto new_temp
if exist "%OUTPUT_FILE%" goto new_temp
if exist "%PENDING_FILE%" goto new_temp
mkdir "%WORK_DIR%" 2>nul
if errorlevel 1 (
    set "WORK_DIR="
    echo [ERROR] Could not create the temporary working folder.
    goto finish
)
set "COMMAND_FILE=%WORK_DIR%\read.jlink"
rem Only connection, halt, memory read, resume and exit commands are emitted.
rem ASCII relative paths also work when TEMP contains Chinese characters.
(
    echo device %DEVICE%
    echo si SWD
    echo speed 4000
    echo connect
    echo h
    echo savebin "%WORK_NAME%\flash.bin" %READ_START% %READ_BYTES%
    echo g
    echo exit
) > "%COMMAND_FILE%"
if errorlevel 1 (
    echo [ERROR] Could not create the temporary read command file.
    goto finish
)
echo Device: "%DEVICE%"
echo Read start: %READ_START%
echo Read size: %READ_BYTES% ^(%EXPECTED_SIZE% bytes^)
echo Output: "%OUTPUT_FILE%"
echo.
rem Keep the known working connection options used by flash.bat.
rem Never enter the per-run folder that must be removed after reading.
pushd "%TEMP%"
if errorlevel 1 (
    echo [ERROR] Could not open the TEMP folder.
    goto finish
)
"%JLINK_EXE%" -device "%DEVICE%" -if SWD -speed 4000 -autoconnect 1 -ExitOnError 1 -NoGui 1 -CommanderScript "%WORK_NAME%\read.jlink"
set "RESULT=%ERRORLEVEL%"
popd
if not "%RESULT%"=="0" (
    echo [ERROR] Read failed. J-Link exit code: %RESULT%
    echo [NOTE] If the target remains halted, power-cycle it before reuse.
    goto finish
)
rem A zero exit status alone is insufficient: require the complete BIN.
set "RESULT=1"
if not exist "%WORK_DIR%\flash.bin" (
    echo [ERROR] J-Link did not produce a readback file.
    goto finish
)
set "ACTUAL_SIZE="
for %%F in ("%WORK_DIR%\flash.bin") do set "ACTUAL_SIZE=%%~zF"
if not "%ACTUAL_SIZE%"=="%EXPECTED_SIZE%" (
    echo [ERROR] Readback length mismatch: expected %EXPECTED_SIZE%, got %ACTUAL_SIZE%.
    goto finish
)
rem Verify a staged output before publishing it as a BIN.
rem REN refuses an existing destination, so earlier readouts stay intact.
copy /b /-Y "%WORK_DIR%\flash.bin" "%PENDING_FILE%" <nul >nul 2>&1
if errorlevel 1 goto save_failed
fc /b "%WORK_DIR%\flash.bin" "%PENDING_FILE%" >nul 2>&1
if errorlevel 1 goto save_failed
ren "%PENDING_FILE%" "flash_%RUN_ID%.bin" >nul 2>&1
if errorlevel 1 goto save_failed
set "RESULT=0"
echo.
echo [OK] Flash read completed. %EXPECTED_SIZE% bytes saved.
echo BIN: "%OUTPUT_FILE%"
goto finish

:save_failed
set "KEEP_READBACK=1"
echo [ERROR] Could not save a verified BIN without overwriting an earlier file.
echo [NOTE] Complete readback retained at: "%WORK_DIR%\flash.bin"
goto finish

:invalid_device
echo [ERROR] flash.jlink must contain exactly one line: device CHIP_NAME
goto finish

:invalid_range
echo [ERROR] flash.jlink must contain one ; READ_START 0x00000000 line
echo [ERROR] and one ; READ_BYTES 0x00010000 line. Use hexadecimal values.
echo [ERROR] Set the range for your chip; READ_BYTES must be positive.

:finish
if defined WORK_DIR call :cleanup_temp
echo.
pause
exit /b %RESULT%

:cleanup_temp
set "CLEANUP_TRIES=0"
:cleanup_retry
if defined COMMAND_FILE if exist "%COMMAND_FILE%" del /q "%COMMAND_FILE%" 2>nul
if defined PENDING_FILE if exist "%PENDING_FILE%" del /q "%PENDING_FILE%" 2>nul
if defined KEEP_READBACK exit /b 0
if exist "%WORK_DIR%\flash.bin" del /q "%WORK_DIR%\flash.bin" 2>nul
if exist "%WORK_DIR%\" rd "%WORK_DIR%" 2>nul
if not exist "%WORK_DIR%\" exit /b 0
set /a CLEANUP_TRIES+=1 >nul
if %CLEANUP_TRIES% geq 4 goto cleanup_busy
ping -n 2 127.0.0.1 >nul 2>&1
goto cleanup_retry

:cleanup_busy
echo [WARNING] Could not remove temporary folder: "%WORK_DIR%"
echo [WARNING] Cleanup was skipped. The read result above is unchanged.
exit /b 0
