@echo off
setlocal EnableDelayedExpansion

REM ============================================================
REM  Ultra Gaming Mode — Administrator Bootstrap Launcher  v2.3
REM  Automatically elevates to admin safely with recursion guard.
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
title Ultra Gaming Mode Controller v2.3

:menu
cls
echo ============================================================
echo            ULTRA GAMING MODE CONTROLLER  v2.3
echo ============================================================
echo.
echo  [1] Arm Ultra Gaming Mode for Next Boot
echo  [2] Restore Normal Windows State Now
echo  [3] Flush and Clean RAM Cache Now (Standby List)
echo  [4] Run System Diagnostic / Pre-Flight Check
echo  [5] Repair Display + Reset DisplayPort Cache (Emergency Fix)
echo  [6] Repair Microphone, Steam + Core Services (Instant Fix)
echo  [7] Check Current Status
echo  [8] Exit
echo.
echo ============================================================
set /p choice="Select an option [1-8]: "

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
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action RepairDisplay
    echo.
    pause
    goto menu
)
if "%choice%"=="6" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action RepairServices
    echo.
    pause
    goto menu
)
if "%choice%"=="7" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0UltraGamingMode.ps1" -Action Status
    echo.
    pause
    goto menu
)
if "%choice%"=="8" (
    exit
)

echo Invalid selection. Please try again.
pause
goto menu
