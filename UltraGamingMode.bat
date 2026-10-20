@echo off
setlocal EnableDelayedExpansion

REM ============================================================
REM  Ultra Gaming Mode — Administrator Bootstrap Launcher  v2.7
REM  Universal Hardware Adaptive Tuning & Failsafe Suite
REM ============================================================

REM 1. Guard against infinite elevation loops
if /i "%~1"=="ELEVATED" goto :start

REM 2. Check for Administrator privileges using fltmc (independent of LanmanServer/network services)
fltmc >nul 2>&1
if %errorLevel% EQU 0 goto :start

REM 3. Secondary check via whoami token group
whoami /groups 2>nul | find "S-1-16-12288" >nul 2>&1
if %errorLevel% EQU 0 goto :start

REM 4. Elevate process cleanly if not already running as admin
echo Requesting Administrator privileges...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\" ELEVATED' -Verb RunAs"
exit /b

:start
cd /d "%~dp0"
title Ultra Gaming Mode Controller v2.7

:menu
cls
echo ============================================================
echo            ULTRA GAMING MODE CONTROLLER  v2.7
echo             Universal Hardware Adaptive Suite
echo ============================================================
echo.
echo   [1] Enable Gaming Mode (Arm for Next Boot)
echo   [2] Restore Normal Windows State
echo   [3] Flush RAM Cache Now (Standby List)
echo   [4] System Diagnostic ^& Hardware Check
echo   [5] Advanced Tools ^& Emergency Repairs --^>
echo   [0] Exit
echo.
echo ============================================================
set /p choice="Select an option [0-5]: "

if "%choice%"=="1" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action Enable
    echo.
    pause
    goto menu
)
if "%choice%"=="2" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action Restore
    echo.
    pause
    goto menu
)
if "%choice%"=="3" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action CleanMemory
    echo.
    pause
    goto menu
)
if "%choice%"=="4" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action Diagnostic
    echo.
    pause
    goto menu
)
if "%choice%"=="5" (
    goto tools_menu
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
echo   [0] ^<-- Back to Main Menu
echo.
echo ============================================================
set /p tool_choice="Select a tool [0-7]: "

if "%tool_choice%"=="1" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action RepairDisplay
    echo.
    pause
    goto tools_menu
)
if "%tool_choice%"=="2" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action RepairServices
    echo.
    pause
    goto tools_menu
)
if "%tool_choice%"=="3" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action FlushShaderCache
    echo.
    pause
    goto tools_menu
)
if "%tool_choice%"=="4" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action ToggleVBS
    echo.
    pause
    goto tools_menu
)
if "%tool_choice%"=="5" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action GpuMsiStatus
    echo.
    pause
    goto tools_menu
)
if "%tool_choice%"=="6" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action KernelLatencyStatus
    echo.
    pause
    goto tools_menu
)
if "%tool_choice%"=="7" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action Status
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
