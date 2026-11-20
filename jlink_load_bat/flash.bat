@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem Do not let an inherited variable mask CMD's actual exit status.
set "ERRORLEVEL="
rem Double-click: use the only HEX beside this BAT.
rem Multiple HEX files: drag the desired HEX onto this BAT.
set "HEX_FILE="
set "RESULT=1"
set "COMMAND_FILE="
set "WORK_DIR="
set "TEMPLATE=%~dp0flash.jlink"

if not "%~2"=="" (
    echo [ERROR] Select only one HEX file at a time.
    goto finish
)
if not "%~1"=="" goto explicit_hex
for %%F in ("%~dp0*.hex") do if exist "%%~fF" if not exist "%%~fF\" (
    if defined HEX_FILE goto multiple_hex
    set "HEX_FILE=%%~fF"
)
if not defined HEX_FILE goto no_hex
goto selected

:explicit_hex
if /i not "%~x1"==".hex" (
    echo [ERROR] Please select a .hex file.
    goto finish
)
set "HEX_FILE=%~f1"
if not exist "%HEX_FILE%" goto missing_hex
if exist "%HEX_FILE%\" goto missing_hex

:selected
for %%F in ("%HEX_FILE%") do if %%~zF equ 0 (
    echo [ERROR] The selected HEX file is empty.
    goto finish
)
if not exist "%TEMPLATE%" (
    echo [ERROR] Missing command template: "%TEMPLATE%"
    goto finish
)
rem Require one device selection and one HEX placeholder before connecting.
set "DEVICE="
set "DEVICE_COUNT=0"
set "DEVICE_INVALID=0"
set "HEX_MARKERS=0"
for /f "usebackq tokens=1,2,*" %%A in ("%TEMPLATE%") do if /i "%%A"=="device" (
    set /a DEVICE_COUNT+=1 >nul
    set "DEVICE=%%B"
    if not "%%C"=="" set "DEVICE_INVALID=1"
)
if not "%DEVICE_COUNT%"=="1" goto invalid_device
if not "%DEVICE_INVALID%"=="0" goto invalid_device
if not defined DEVICE goto invalid_device
for /f "usebackq delims=" %%L in ("%TEMPLATE%") do if "%%L"=="@HEX_FILE@" set /a HEX_MARKERS+=1 >nul
if not "%HEX_MARKERS%"=="1" (
    echo [ERROR] flash.jlink must contain exactly one @HEX_FILE@ line.
    goto finish
)
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

:new_temp
set "WORK_NAME=mppt_flash_%RANDOM%_%RANDOM%"
set "WORK_DIR=%TEMP%\%WORK_NAME%"
if exist "%WORK_DIR%" goto new_temp
mkdir "%WORK_DIR%" 2>nul
if errorlevel 1 (
    set "WORK_DIR="
    echo [ERROR] Could not create the temporary working folder.
    goto finish
)
set "COMMAND_FILE=%WORK_DIR%\commands.jlink"
rem Stage the HEX under a fixed name, independent of the source filename.
copy /b "%HEX_FILE%" "%WORK_DIR%\firmware.hex" >nul
if errorlevel 1 (
    echo [ERROR] Could not copy the selected HEX.
    goto finish
)
(
    for /f "usebackq delims=" %%L in ("%TEMPLATE%") do (
        if "%%L"=="@HEX_FILE@" (
            echo loadfile "%WORK_NAME%\firmware.hex"
        ) else (
            echo %%L
        )
    )
) > "%COMMAND_FILE%"
if errorlevel 1 (
    echo [ERROR] Could not create the temporary command file.
    goto finish
)
echo Device: "%DEVICE%"
echo HEX: "%HEX_FILE%"
echo.
rem Use the TEMP parent as CWD; never enter the folder we must delete.
rem Relative ASCII paths also avoid command-file encoding issues.
pushd "%TEMP%"
if errorlevel 1 (
    echo [ERROR] Could not open the TEMP folder.
    goto finish
)
"%JLINK_EXE%" -device "%DEVICE%" -if SWD -speed 4000 -autoconnect 1 -ExitOnError 1 -NoGui 1 -CommanderScript "%WORK_NAME%\commands.jlink"
set "RESULT=%ERRORLEVEL%"
popd
if "%RESULT%"=="0" (
    echo.
    echo [OK] Programming completed.
) else (
    echo.
    echo [ERROR] Programming failed. J-Link exit code: %RESULT%
)
goto finish

:no_hex
echo [ERROR] No .hex file was found beside this BAT.
echo Put one HEX in this folder, or drag a HEX onto this BAT.
goto finish

:multiple_hex
echo [ERROR] More than one HEX was found. No device was programmed.
echo.
dir /b /a-d "%~dp0*.hex"
echo.
echo Keep only one HEX, or drag the desired HEX onto this BAT.
goto finish

:invalid_device
echo [ERROR] flash.jlink must contain exactly one line: device CHIP_NAME
goto finish

:missing_hex
echo [ERROR] File not found: "%HEX_FILE%"

:finish
if defined WORK_DIR call :cleanup_temp
echo.
pause
exit /b %RESULT%

:cleanup_temp
rem Allow a brief file or directory lock to clear after J-Link exits.
set "CLEANUP_TRIES=0"
:cleanup_retry
if defined COMMAND_FILE if exist "%COMMAND_FILE%" del /q "%COMMAND_FILE%" 2>nul
if exist "%WORK_DIR%\firmware.hex" del /q "%WORK_DIR%\firmware.hex" 2>nul
if exist "%WORK_DIR%\" rd "%WORK_DIR%" 2>nul
if not exist "%WORK_DIR%\" exit /b 0
set /a CLEANUP_TRIES+=1 >nul
if %CLEANUP_TRIES% geq 4 goto cleanup_busy
rem Wait about one second; also works with redirected input.
ping -n 2 127.0.0.1 >nul 2>&1
goto cleanup_retry

:cleanup_busy
echo [WARNING] Could not remove temporary folder: "%WORK_DIR%"
echo [WARNING] Cleanup was skipped. The programming result above is unchanged.
exit /b 0
