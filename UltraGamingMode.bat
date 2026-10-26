@echo off
setlocal EnableDelayedExpansion

REM ============================================================
REM  Ultra Gaming Mode — Administrator Bootstrap Launcher  v2.8
REM  Universal Hardware Adaptive Tuning & Failsafe Suite
REM ============================================================

set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

REM 1. Guard against infinite elevation loops
if /i "%~1"=="ELEVATED" goto :start

REM 2. Check for Administrator privileges using fltmc (independent of LanmanServer/network services)
fltmc >nul 2>&1
if %errorLevel% EQU 0 goto :start

REM 3. Secondary check via whoami token group
whoami /groups 2>nul | find "S-1-16-12288" >nul 2>&1
if %errorLevel% EQU 0 goto :start

REM 4. Elevate process cleanly if not already running as admin (safe against apostrophes/special chars in path)
echo Requesting Administrator privileges...
set "UGM_SELF=%~f0"
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:ComSpec -ArgumentList @('/c', ('\"\"{0}\"\" ELEVATED' -f $env:UGM_SELF)) -Verb RunAs"
exit /b

:start
cd /d "%~dp0"
title Ultra Gaming Mode Controller v2.8

set "UPDATE_NOTIFICATION="
set "UPDATE_RELEASE_URL="
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action CheckUpdate -OnStartup
if !errorLevel! EQU 2 (
    if exist "%~dp0Backups\update_info.cmd" call :load_update_info "%~dp0Backups\update_info.cmd"
    if defined LATEST_VERSION (
        set "UPDATE_NOTIFICATION=   *** UPDATE AVAILABLE (!LATEST_VERSION!): Select [6] to update ***"
    ) else (
        set "UPDATE_NOTIFICATION=   *** UPDATE AVAILABLE: Select [6] to update ***"
    )
    if defined RELEASE_URL set "UPDATE_RELEASE_URL=   Release: !RELEASE_URL!"
)

:menu
cls
echo ============================================================
echo            ULTRA GAMING MODE CONTROLLER  v2.8
if defined UPDATE_NOTIFICATION echo !UPDATE_NOTIFICATION!
if defined UPDATE_RELEASE_URL echo !UPDATE_RELEASE_URL!
echo             Universal Hardware Adaptive Suite
echo ============================================================
echo.
echo   [1] Enable Gaming Mode (Arm for Next Boot)
echo   [2] Restore Normal Windows State
echo   [3] Flush RAM Cache Now (Standby List)
echo   [4] System Diagnostic ^& Hardware Check
echo   [5] Advanced Tools ^& Emergency Repairs --^>
echo   [6] Check for Updates (GitHub)
echo   [0] Exit
echo.
echo ============================================================
set /p choice="Select an option [0-6]: "
if defined choice set "choice=!choice: =!"

if "%choice%"=="1" (
    "%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action Enable -SkipUpdateCheck
    echo.
    pause
    goto menu
)
if "%choice%"=="2" (
    "%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action Restore -SkipUpdateCheck
    echo.
    pause
    goto menu
)
if "%choice%"=="3" (
    "%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action CleanMemory -SkipUpdateCheck
    echo.
    pause
    goto menu
)
if "%choice%"=="4" (
    "%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action Diagnostic -SkipUpdateCheck
    echo.
    pause
    goto menu
)
if "%choice%"=="5" (
    goto tools_menu
)
if "%choice%"=="6" (
    "%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action CheckUpdate -Force
    if !errorLevel! EQU 2 (
        if exist "%~dp0Backups\update_info.cmd" call :load_update_info "%~dp0Backups\update_info.cmd"
        if defined LATEST_VERSION (
            set "UPDATE_NOTIFICATION=   *** UPDATE AVAILABLE (!LATEST_VERSION!): Select [6] to update ***"
        ) else (
            set "UPDATE_NOTIFICATION=   *** UPDATE AVAILABLE: Select [6] to update ***"
        )
        if defined RELEASE_URL (
            set "UPDATE_RELEASE_URL=   Release: !RELEASE_URL!"
        ) else (
            set "UPDATE_RELEASE_URL="
        )
    ) else (
        set "UPDATE_NOTIFICATION="
        set "UPDATE_RELEASE_URL="
    )
    echo.
    pause
    goto menu
)
if "%choice%"=="0" (
    exit
)
if /i "%choice%"=="q" (
    exit
)

echo Invalid selection. Please try again.
pause
goto menu

:tools_menu
cls
echo ============================================================
echo            ADVANCED TOOLS ^& EMERGENCY REPAIRS
echo ============================================================
echo.
echo   [1] Reset DisplayPort ^& Monitor Topology Cache
echo   [2] Repair Microphone, Steam ^& Audio Services
echo   [3] Purge Universal GPU Shader Cache (AMD / NVIDIA / Intel / DirectX)
echo   [4] Check ^& Toggle VBS / Core Isolation
echo   [5] Check GPU MSI ^& IRQ Priority Status
echo   [6] Check Kernel DPC, Input Buffer ^& Timer Status
echo   [7] View Full Mode Status
echo   [8] Check for Updates (GitHub)
echo   [0] <-- Back to Main Menu
echo.
echo ============================================================
set /p tool_choice="Select a tool [0-8]: "
if defined tool_choice set "tool_choice=!tool_choice: =!"

if "%tool_choice%"=="1" (
    "%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action RepairDisplay -SkipUpdateCheck
    echo.
    pause
    goto tools_menu
)
if "%tool_choice%"=="2" (
    "%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action RepairServices -SkipUpdateCheck
    echo.
    pause
    goto tools_menu
)
if "%tool_choice%"=="3" (
    "%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action FlushShaderCache -SkipUpdateCheck
    echo.
    pause
    goto tools_menu
)
if "%tool_choice%"=="4" (
    "%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action ToggleVBS -SkipUpdateCheck
    echo.
    pause
    goto tools_menu
)
if "%tool_choice%"=="5" (
    "%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action GpuMsiStatus -SkipUpdateCheck
    echo.
    pause
    goto tools_menu
)
if "%tool_choice%"=="6" (
    "%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action KernelLatencyStatus -SkipUpdateCheck
    echo.
    pause
    goto tools_menu
)
if "%tool_choice%"=="7" (
    "%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action Status -SkipUpdateCheck
    echo.
    pause
    goto tools_menu
)
if "%tool_choice%"=="8" (
    "%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action CheckUpdate -Force
    if !errorLevel! EQU 2 (
        if exist "%~dp0Backups\update_info.cmd" call :load_update_info "%~dp0Backups\update_info.cmd"
        if defined LATEST_VERSION (
            set "UPDATE_NOTIFICATION=   *** UPDATE AVAILABLE (!LATEST_VERSION!): Select [6] to update ***"
        ) else (
            set "UPDATE_NOTIFICATION=   *** UPDATE AVAILABLE: Select [6] to update ***"
        )
        if defined RELEASE_URL (
            set "UPDATE_RELEASE_URL=   Release: !RELEASE_URL!"
        ) else (
            set "UPDATE_RELEASE_URL="
        )
    ) else (
        set "UPDATE_NOTIFICATION="
        set "UPDATE_RELEASE_URL="
    )
    echo.
    pause
    goto tools_menu
)
if "%tool_choice%"=="0" (
    goto menu
)
if /i "%tool_choice%"=="q" (
    goto menu
)

echo Invalid selection. Please try again.
pause
goto tools_menu

:load_update_info
set "LATEST_VERSION="
set "RELEASE_URL="
if not exist "%~1" exit /b 0
for /f "usebackq tokens=1,* delims==" %%A in ("%~1") do (
    set "_line_key=%%~A"
    set "_line_val=%%~B"
    if defined _line_val set "_line_val=!_line_val:"=!"
    if /i "!_line_key!"=="@set \"LATEST_VERSION" set "LATEST_VERSION=!_line_val!"
    if /i "!_line_key!"=="@set LATEST_VERSION" set "LATEST_VERSION=!_line_val!"
    if /i "!_line_key!"=="LATEST_VERSION" set "LATEST_VERSION=!_line_val!"
    if /i "!_line_key!"=="@set \"RELEASE_URL" set "RELEASE_URL=!_line_val!"
    if /i "!_line_key!"=="@set RELEASE_URL" set "RELEASE_URL=!_line_val!"
    if /i "!_line_key!"=="RELEASE_URL" set "RELEASE_URL=!_line_val!"
)
exit /b 0
