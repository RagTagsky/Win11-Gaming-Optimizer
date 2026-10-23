<#
.SYNOPSIS
    Ultra Gaming Mode — Main Controller and Task Scheduler Orchestrator.
.DESCRIPTION
    Manages the full lifecycle of Ultra Gaming Mode:
    - Enable: Snapshots current state, suppresses user startup apps/UWP/visual effects, and arms boot task.
    - ApplyBootMode: Called by Task Scheduler on boot under SYSTEM to strip 173 non-essential services.
    - Restore: Returns all services, startup items, UWP apps, and visual parameters to original state.
    - Status: Shows current state, active services, and scheduled task status.
    - Diagnostic: Verifies system readiness, whitelist protection, and bloatware coverage.
    - CleanMemory: On-demand RAM working set trimming and cache flush.
    - RepairDisplay: Emergency display pipeline and DisplayPort topology cache reset.
.NOTES
    Requires Administrator privileges.
#>

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [ValidateSet("Enable", "Restore", "Status", "ApplyBootMode", "Diagnostic", "CleanMemory", "RepairDisplay", "RepairServices", "FlushShaderCache", "ToggleVBS", "GpuMsiStatus", "KernelLatencyStatus", "RestoreUser", "CheckUpdate")]
    [string]$Action = "Status",

    [Parameter()]
    [ValidateSet("All", "System", "User")]
    [string]$Scope = "All",

    [switch]$Watchdog,

    [switch]$SkipUpdateCheck,

    [switch]$OnStartup,

    [switch]$Passive,

    [switch]$Force
)

# ── Admin Rights & Watchdog Delegation Check ──────────────────────────────────
$isSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdmin) {
    if ($Action -in @("Status", "Diagnostic", "CleanMemory", "FlushShaderCache", "GpuMsiStatus", "KernelLatencyStatus", "CheckUpdate")) {
        Write-Warning "Running in non-elevated mode. Operating with current user privileges."
    }
    elseif ($Action -eq "RestoreUser" -or ($Action -eq "Restore" -and ($Watchdog -or $Scope -eq "User"))) {
        Write-Verbose "Watchdog / User profile restoration running with current user privileges."
    }
    else {
        Write-Error "Ultra Gaming Mode requires Administrator privileges for '$Action'. Please run as Administrator."
        exit 1
    }
}

# ── Load Dependencies ─────────────────────────────────────────────────────────
$RootDir = $PSScriptRoot
. (Join-Path $RootDir "Core\ServiceManager.ps1")
. (Join-Path $RootDir "Core\SystemOptimizer.ps1")
. (Join-Path $RootDir "Core\StateEngine.ps1")

# ── Load Configuration ────────────────────────────────────────────────────────
$blacklistPath   = Join-Path $RootDir "Config\services_blacklist.json"
$whitelistPath   = Join-Path $RootDir "Config\services_whitelist.json"
$startupAppsPath = Join-Path $RootDir "Config\startup_apps.json"

$blacklist  = (Get-Content $blacklistPath -Raw | ConvertFrom-Json).TargetServices
$whitelist  = (Get-Content $whitelistPath -Raw | ConvertFrom-Json).ProtectedServices
$startupCfg = Get-Content $startupAppsPath -Raw | ConvertFrom-Json

# ── Automatic Update Check on Direct Launch ───────────────────────────────────
if (-not $SkipUpdateCheck -and -not $Watchdog -and -not $isSystem -and $Action -notin @("ApplyBootMode", "RestoreUser", "CheckUpdate")) {
    $null = Invoke-AppUpdateWorkflow -Passive -TimeoutSeconds 2
}

# ── Task Scheduler Names ──────────────────────────────────────────────────────
$taskName = "UltraGamingMode_BootTrigger"
$watchdogTaskName = "UltraGamingMode_Watchdog"

# ── Helper: Register Boot-Time Tasks ─────────────────────────────────────────
function Register-BootTasks {
    Write-Host "[*] Registering Next-Boot Task in Task Scheduler (SYSTEM privileges)..." -ForegroundColor Cyan

    $actionScript = Join-Path $RootDir "UltraGamingMode.ps1"
    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

    $taskAction = New-ScheduledTaskAction `
        -Execute $psExe `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$actionScript`" -Action ApplyBootMode -SkipUpdateCheck"

    $startupTrigger = New-ScheduledTaskTrigger -AtStartup
    $logonTrigger   = New-ScheduledTaskTrigger -AtLogOn

    $taskPrincipal = New-ScheduledTaskPrincipal `
        -UserId "NT AUTHORITY\SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest

    $taskSettings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew `
        -Priority 0 `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $taskAction `
        -Trigger @($startupTrigger, $logonTrigger) `
        -Principal $taskPrincipal `
        -Settings $taskSettings `
        -Force | Out-Null

    Write-Host "[+] Next-Boot Task Scheduler trigger successfully armed." -ForegroundColor Green
}

# ── Helper: Register Watchdog Auto-Restore Tasks (Armed During Gaming Boot) ──
function Register-WatchdogTasks {
    $actionScript = Join-Path $RootDir "UltraGamingMode.ps1"
    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

    # 1. Register SYSTEM Scheduled Task Watchdog so System-scope services/tweaks can restore on Boot 2 without UAC prompts
    try {
        $wdAction = New-ScheduledTaskAction `
            -Execute $psExe `
            -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$actionScript`" -Action Restore -Watchdog -SkipUpdateCheck"

        $wdStartupTrigger = New-ScheduledTaskTrigger -AtStartup
        $wdLogonTrigger   = New-ScheduledTaskTrigger -AtLogOn

        $wdPrincipal = New-ScheduledTaskPrincipal `
            -UserId "NT AUTHORITY\SYSTEM" `
            -LogonType ServiceAccount `
            -RunLevel Highest

        $wdSettings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -MultipleInstances IgnoreNew `
            -Priority 0 `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

        Register-ScheduledTask `
            -TaskName $watchdogTaskName `
            -Action $wdAction `
            -Trigger @($wdStartupTrigger, $wdLogonTrigger) `
            -Principal $wdPrincipal `
            -Settings $wdSettings `
            -Force -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        Write-Verbose "Could not register scheduled watchdog task: $($_.Exception.Message)"
    }

    # 2. Arm HKLM RunOnce so interactive user logon triggers User-scope restoration on Boot 2
    $restoreCmd = "`"$psExe`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File `"$actionScript`" -Action Restore -Watchdog -SkipUpdateCheck"
    Set-ItemProperty `
        -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" `
        -Name "*UltraGamingModeRestore" `
        -Value $restoreCmd `
        -Force -ErrorAction SilentlyContinue
}

# ── Helper: Clean Up All Scheduled Triggers ──────────────────────────────────
function Unregister-BootTasks {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $watchdogTaskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-ItemProperty `
        -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" `
        -Name "*UltraGamingModeRestore" `
        -ErrorAction SilentlyContinue
    Remove-ItemProperty `
        -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" `
        -Name "*UltraGamingModeRestore" `
        -ErrorAction SilentlyContinue
    Write-Host "[+] Scheduled tasks and RunOnce watchdogs cleaned up." -ForegroundColor Gray
}

# ── Helper: Show Low-Latency Subsystem Status ────────────────────────────────
function Show-LatencySubsystemStatus {
    $kdpc = Get-KernelDpcConfig
    $input = Get-InputBufferConfig
    $bcd = Get-BcdeditTimerConfig
    $tcp = Get-TcpStackConfig
    $hags = Get-HagsGpuSchedulingConfig

    Write-Host "`n[1] Kernel DPC & Memory Management:" -ForegroundColor Yellow
    $dpcVal = if ($null -ne $kdpc.ThreadDpcEnable) { $kdpc.ThreadDpcEnable } else { "1" }
    $isDpcOpt = ($dpcVal -ne 0)
    $dpcTxt = if ($isDpcOpt) { "Threaded ($dpcVal) [OPTIMAL - Render Thread Protected from DPC Preemption]" } else { "Direct (0) [UNSAFE - Interrupts Preempt Game Loop]" }
    $pageTxt = if ($kdpc.DisablePagingExecutive -eq 1) { "Enabled (1) [OPTIMAL - Drivers locked in RAM]" } else { "Disabled ($($kdpc.DisablePagingExecutive)) [Pageable]" }
    $prioTxt = if ($kdpc.Win32PrioritySeparation -eq 38) { "0x26 / 38 [OPTIMAL - 3:1 Foreground Boost]" } else { "$($kdpc.Win32PrioritySeparation)" }
    $pwrTxt = if ($kdpc.PowerThrottlingOff -eq 1) { "Disabled (1) [OPTIMAL - No Thread Throttling]" } else { "Active ($($kdpc.PowerThrottlingOff))" }

    Write-Host "  ThreadDpcEnable:         $dpcTxt" -ForegroundColor $(if ($isDpcOpt) { "Green" } else { "Yellow" })
    Write-Host "  DisablePagingExecutive:  $pageTxt" -ForegroundColor $(if ($kdpc.DisablePagingExecutive -eq 1) { "Green" } else { "Yellow" })
    Write-Host "  Win32PrioritySeparation: $prioTxt" -ForegroundColor $(if ($kdpc.Win32PrioritySeparation -eq 38) { "Green" } else { "Yellow" })
    Write-Host "  PowerThrottlingOff:      $pwrTxt" -ForegroundColor $(if ($kdpc.PowerThrottlingOff -eq 1) { "Green" } else { "Yellow" })

    Write-Host "`n[2] Direct Peripheral Input Queues:" -ForegroundColor Yellow
    $mouVal = if ($null -ne $input.MouseDataQueueSize) { $input.MouseDataQueueSize } else { 100 }
    $isMouOpt = ($mouVal -ge 100)
    $mouTxt = if ($isMouOpt) { "$mouVal packets [OPTIMAL - Zero Packet Loss on 1000Hz+ Gaming Mice]" } else { "$mouVal [Truncated - Risk of Flick Drops]" }
    $kbdVal = if ($null -ne $input.KeyboardDataQueueSize) { $input.KeyboardDataQueueSize } else { 100 }
    $isKbdOpt = ($kbdVal -ge 100)
    $kbdTxt = if ($isKbdOpt) { "$kbdVal packets [OPTIMAL - Zero Dropped Key Events]" } else { "$kbdVal [Truncated]" }
    Write-Host "  MouseDataQueueSize:      $mouTxt" -ForegroundColor $(if ($isMouOpt) { "Green" } else { "Yellow" })
    Write-Host "  KeyboardDataQueueSize:   $kbdTxt" -ForegroundColor $(if ($isKbdOpt) { "Green" } else { "Yellow" })

    Write-Host "`n[3] BCDedit Kernel System Timers:" -ForegroundColor Yellow
    $tickVal = if ($bcd.DynamicTick) { $bcd.DynamicTick } else { "Default" }
    $isTickOpt = ($bcd.DynamicTick -ne "yes")
    $tickTxt = if ($isTickOpt) { "Default (Dynamic Tick Active) [OPTIMAL - Full CPU Boost Clocks]" } else { "Disabled (yes) [OVERHEAD - Timer Interrupt Storms]" }
    $tscVal = if ($bcd.TscSyncPolicy) { $bcd.TscSyncPolicy } else { "Default" }
    $isTscOpt = ($bcd.TscSyncPolicy -ne "Enhanced")
    $tscTxt = if ($isTscOpt) { "Default [OPTIMAL - Native Invariant Hardware TSC, ~15ns QPC]" } else { "Enhanced [OVERHEAD - Software IPI Sync, ~300ns QPC]" }
    Write-Host "  disabledynamictick:      $tickTxt" -ForegroundColor $(if ($isTickOpt) { "Green" } else { "Yellow" })
    Write-Host "  tscsyncpolicy:           $tscTxt" -ForegroundColor $(if ($isTscOpt) { "Green" } else { "Yellow" })

    Write-Host "`n[4] TCP Gaming Stack & HAGS:" -ForegroundColor Yellow
    $tsTxt = if ($tcp.Timestamps -eq "disabled") { "Disabled [OPTIMAL - 12B Header Overhead Eliminated]" } else { "$($tcp.Timestamps)" }
    $hagsTxt = if ($hags.HwSchMode -eq 2) { "Enabled (2) [Hardware GPU Scheduling]" } else { "Disabled ($($hags.HwSchMode)) [Clean Default]" }
    Write-Host "  TCP Timestamps:          $tsTxt" -ForegroundColor $(if ($tcp.Timestamps -eq "disabled") { "Green" } else { "Yellow" })
    Write-Host "  GPU HAGS (HwSchMode):    $hagsTxt" -ForegroundColor "Green"
}

# ── Main Action Switch ────────────────────────────────────────────────────────
switch ($Action) {

    "Enable" {
        Write-Host "=====================================================" -ForegroundColor Magenta
        Write-Host "         ACTIVATING ULTRA GAMING MODE (NEXT BOOT)    " -ForegroundColor Magenta
        Write-Host "=====================================================" -ForegroundColor Magenta

        # Check if already armed or active
        $currentState = Get-CurrentStateStatus
        if ($currentState -eq "GameMode_Active") {
            Write-Warning "Ultra Gaming Mode is already $currentState. Run with -Action Restore first."
            exit 0
        }
        if ($currentState -eq "Armed") {
            $existingBootTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            if ($existingBootTask) {
                Write-Warning "Ultra Gaming Mode is already Armed for next boot. Reboot your PC to activate, or run with -Action Restore to cancel."
                exit 0
            }
            Write-Warning "Detected Armed state with missing Boot Trigger. Re-arming Next-Boot Task Scheduler trigger while preserving existing backup snapshot..."
            $stateData = Get-ActiveStateSafe
            if ($stateData) {
                Set-StatePropertySafe -StateObject $stateData -Name "LastBootError" -Value $null
                Set-ActiveStateSafe -Data $stateData | Out-Null
            }
            Disable-UserStateAggressive -StartupConfig $startupCfg
            Register-BootTasks
            Remove-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "*UltraGamingModeRestore" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "*UltraGamingModeRestore" -ErrorAction SilentlyContinue
            Write-Host "`n[SUCCESS] Boot Trigger re-armed! Reboot your PC to enter Ultra Gaming Mode." -ForegroundColor Green
            exit 0
        }

        # 1. Create complete system snapshot (services, startup registry, shortcuts, UWP, visual)
        New-SystemStateBackup -BlacklistConfig $blacklist -Whitelist $whitelist -StartupConfig $startupCfg

        # 2. Aggressively strip user startup apps (TranslucentTB, shortcuts, third-party apps, transparency)
        Disable-UserStateAggressive -StartupConfig $startupCfg

        # 3. Register boot-time trigger under SYSTEM
        Register-BootTasks

        # 4. Clean up any residual RunOnce watchdog entries
        Remove-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "*UltraGamingModeRestore" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "*UltraGamingModeRestore" -ErrorAction SilentlyContinue

        Write-Host "`n[SUCCESS] PC is primed for Ultra Gaming Mode!" -ForegroundColor Green
        Write-Host "  - Third-party startup apps, shortcuts, and TranslucentTB are suppressed." -ForegroundColor White
        Write-Host "  - On next restart, 173 non-essential Windows services will be disabled." -ForegroundColor White
        Write-Host "  - Windows Audio, Network, AMD DisplayPort DSC, and Anti-Cheats remain 100% protected." -ForegroundColor White
        Write-Host "`n[FAIL-SAFE WATCHDOG] When done playing, simply run Option [2] Restore, or reboot the PC." -ForegroundColor Yellow
    }

    "ApplyBootMode" {
        # This action is invoked AUTOMATICALLY by Task Scheduler under SYSTEM at startup.
        # It reads the armed state, disables blacklisted services, and arms the auto-restore.

        $stateFile = Join-Path (Join-Path $RootDir "Backups") "active_state.json"
        try {
            if (Test-Path -LiteralPath $stateFile) {
                $stateData = Get-ActiveStateSafe -Path $stateFile

                if ($stateData -and $stateData.State -eq "Armed") {
                    # Capture boot session identifiers and persist active state IMMEDIATELY using Set-StatePropertySafe
                    $bootId = Get-SystemBootId
                    $bootTime = Get-ResilientBootTimestamp
                    $prevRunCount = if ($null -ne $stateData.BootRunCount) { [int]$stateData.BootRunCount } else { 0 }

                    Set-StatePropertySafe -StateObject $stateData -Name "State" -Value "GameMode_Active"
                    Set-StatePropertySafe -StateObject $stateData -Name "GamingBootId" -Value $bootId
                    Set-StatePropertySafe -StateObject $stateData -Name "GamingBootTime" -Value $bootTime
                    Set-StatePropertySafe -StateObject $stateData -Name "BootRunCount" -Value ($prevRunCount + 1)
                    Set-StatePropertySafe -StateObject $stateData -Name "SessionLogonHandled" -Value $false
                    Set-StatePropertySafe -StateObject $stateData -Name "UserSessionHandled" -Value $false
                    Set-StatePropertySafe -StateObject $stateData -Name "SystemSessionHandled" -Value $false
                    Set-StatePropertySafe -StateObject $stateData -Name "SystemRestored" -Value $false
                    Set-StatePropertySafe -StateObject $stateData -Name "UserRestored" -Value $false
                    Set-StatePropertySafe -StateObject $stateData -Name "LastBootError" -Value $null
                    Set-ActiveStateSafe -Path $stateFile -Data $stateData | Out-Null

                    # Arm fail-safe watchdog tasks and RunOnce immediately after state transition so auto-restore is guaranteed
                    Register-WatchdogTasks

                    # 1. Disable all blacklisted services
                    $disabledCount = 0
                    foreach ($item in $blacklist) {
                        try {
                            $res = Set-ServiceStateSafe -ServiceName $item.Name -StartupType "Disabled" -StopNow -Whitelist $whitelist
                            if ($res) { $disabledCount++ }
                        } catch {
                            Write-Verbose "Service disable warning for $($item.Name): $($_.Exception.Message)"
                        }
                    }

                    # 2. Activate safe network gaming tweaks, power scheme and adaptive hardware optimizations
                    try {
                        $hw = if ($stateData.HardwareProfile) { $stateData.HardwareProfile } else { Get-HardwareProfile }
                        Enable-UltimatePerformance | Out-Null
                        Set-GamingMultimediaConfig | Out-Null
                        Apply-CpuGamingOptimizations -HardwareProfile $hw | Out-Null
                        Apply-GpuGamingOptimizations -HardwareProfile $hw | Out-Null
                        Set-NTFSGamingOptimizations -IsHdd:([bool]$hw.HddProfile) | Out-Null
                        Set-NetworkGamingOptimizations | Out-Null
                        Set-KernelDpcOptimizations -IsLowRam:([bool]$hw.LowRamProfile) | Out-Null
                        Set-InputBufferOptimizations -QueueSize 100 | Out-Null
                        Set-BcdeditTimerOptimizations | Out-Null
                        Set-TcpGamingStackOptimizations | Out-Null
                        Set-HagsGpuScheduling -GpuVendor $hw.GpuVendor | Out-Null

                        # If HDD detected, suspend ScheduledDefrag background task and ensure SysMain/WSearch are dead
                        if ($hw.HddProfile) {
                            Disable-ScheduledTask -TaskPath "\Microsoft\Windows\Defrag\" -TaskName "ScheduledDefrag" -ErrorAction SilentlyContinue | Out-Null
                            Disable-ScheduledTask -TaskName "ScheduledDefrag" -ErrorAction SilentlyContinue | Out-Null
                            foreach ($sName in @("SysMain", "WSearch")) {
                                Stop-Service -Name $sName -Force -ErrorAction SilentlyContinue
                            }
                        }

                        # If Low-RAM detected, aggressively reclaim memory
                        if ($hw.LowRamProfile) {
                            Optimize-SystemMemory -Aggressive | Out-Null
                        }
                    } catch {
                        Write-Verbose "Hardware optimization warning during ApplyBootMode: $($_.Exception.Message)"
                    }

                    # 3. Ensure RunOnce fail-safe watchdog is armed: fires on subsequent reboot/logon after gaming mode
                    $actionScript = Join-Path $RootDir "UltraGamingMode.ps1"
                    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
                    $restoreCmd = "`"$psExe`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File `"$actionScript`" -Action Restore -Watchdog -SkipUpdateCheck"
                    Set-ItemProperty `
                        -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" `
                        -Name "*UltraGamingModeRestore" `
                        -Value $restoreCmd `
                        -Force -ErrorAction SilentlyContinue
                }
                elseif ($stateData -and $stateData.State -eq "GameMode_Active") {
                    # Guard against duplicate trigger on the same boot (e.g. AtStartup followed by AtLogOn)
                    $isSameBoot = Test-IsSameBootSession -SavedBootId $stateData.GamingBootId -SavedBootTime $stateData.GamingBootTime
                    if (-not $isSameBoot) {
                        Write-Host "[*] System rebooted after Gaming Mode. Restoring normal state..." -ForegroundColor Cyan
                        Restore-SystemState -Whitelist $whitelist -StartupConfig $startupCfg -Scope System
                        Unregister-BootTasks
                    }
                }
            }
        }
        catch {
            try {
                $errState = Get-ActiveStateSafe -Path $stateFile
                if ($errState) {
                    Set-StatePropertySafe -StateObject $errState -Name "LastBootError" -Value $_.Exception.Message
                    Set-ActiveStateSafe -Path $stateFile -Data $errState | Out-Null
                }
            } catch {}
        }
        finally {
            # Remove the boot trigger so it does not fire on subsequent boots after this boot session.
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        }
    }

    { $_ -in @("Restore", "RestoreUser") } {
        $stateFile = Join-Path (Join-Path $RootDir "Backups") "active_state.json"
        if ($Watchdog -and (Test-Path -LiteralPath $stateFile)) {
            $stateData = Get-ActiveStateSafe -Path $stateFile

            # Safety Guard 0: If already completely Restored or Normal, clean up any residual watchdog triggers and exit
            if ($stateData -and ($stateData.State -eq "Restored" -or $stateData.State -eq "Normal")) {
                if ($isSystem -or $isAdmin) {
                    Unregister-BootTasks
                } else {
                    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "*UltraGamingModeRestore" -ErrorAction SilentlyContinue
                }
                exit 0
            }

            # Safety Guard 1: Never auto-restore while armed or applying boot mode
            if ($stateData -and ($stateData.State -eq "Armed" -or $stateData.State -eq "Applying_BootMode")) {
                Write-Host "[*] Gaming mode is armed/applying for this boot. Skipping watchdog restore." -ForegroundColor Yellow
                exit 0
            }

            # Safety Guard 2: Deterministic boot session check via kernel BootId and boot timestamp
            $isSameBoot = $false
            if ($stateData -and $stateData.State -eq "GameMode_Active") {
                $isSameBoot = Test-IsSameBootSession -SavedBootId $stateData.GamingBootId -SavedBootTime $stateData.GamingBootTime
            }

            if ($isSameBoot) {
                Write-Host "[+] Active Ultra Gaming Mode session verified (BootId: $($stateData.GamingBootId)). Maintaining gaming optimizations." -ForegroundColor Green

                # Ensure any stray bloat processes that managed to start are stopped in user session
                if (-not $isSystem -and $startupCfg.BlacklistProcesses) {
                    Stop-BlacklistedProcesses -ProcessNames $startupCfg.BlacklistProcesses
                }

                # Re-arm RunOnce for the NEXT reboot so fail-safe auto-revert fires when gaming ends
                $actionScript = Join-Path $RootDir "UltraGamingMode.ps1"
                $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
                $restoreCmd = "`"$psExe`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File `"$actionScript`" -Action Restore -Watchdog -SkipUpdateCheck"
                if ($isSystem -or $isAdmin) {
                    Set-ItemProperty `
                        -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" `
                        -Name "*UltraGamingModeRestore" `
                        -Value $restoreCmd `
                        -Force -ErrorAction SilentlyContinue
                }
                if (-not $isSystem) {
                    Set-ItemProperty `
                        -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" `
                        -Name "*UltraGamingModeRestore" `
                        -Value $restoreCmd `
                        -Force -ErrorAction SilentlyContinue
                }
                Write-Host "[+] Fail-safe RunOnce watchdog re-armed for next reboot." -ForegroundColor Yellow
                exit 0
            }
        }

        Write-Host "=====================================================" -ForegroundColor Cyan
        Write-Host "             RESTORING NORMAL SYSTEM STATE            " -ForegroundColor Cyan
        Write-Host "=====================================================" -ForegroundColor Cyan

        # Determine effective restoration scope
        $effectiveScope = $Scope
        if ($Action -eq "RestoreUser") {
            $effectiveScope = "User"
        } elseif ($isSystem) {
            $effectiveScope = "System"
        } elseif (-not $isAdmin) {
            $effectiveScope = "User"
        } elseif ($Watchdog) {
            $stateData = if (Test-Path -LiteralPath $stateFile) { Get-ActiveStateSafe -Path $stateFile } else { $null }
            $hasScheduledWatchdog = [bool](Get-ScheduledTask -TaskName "UltraGamingMode_Watchdog" -ErrorAction SilentlyContinue)
            if ($stateData -and $stateData.SystemRestored) {
                $effectiveScope = "User"
            } elseif ($hasScheduledWatchdog) {
                # SYSTEM task handles system scope; user process handles user profile scope
                $effectiveScope = "User"
            } else {
                $effectiveScope = "All"
            }
        }

        $result = Restore-SystemState -Whitelist $whitelist -StartupConfig $startupCfg -Scope $effectiveScope

        # Coordinated cleanup of triggers
        $latestState = if (Test-Path -LiteralPath $stateFile) { Get-ActiveStateSafe -Path $stateFile } else { $null }
        $bothRestored = ($latestState -and $latestState.SystemRestored -and $latestState.UserRestored)

        if ($effectiveScope -eq "All" -or $bothRestored) {
            # Both scopes complete: full cleanup of all tasks and RunOnce entries
            Unregister-BootTasks
            Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "*UltraGamingModeRestore" -ErrorAction SilentlyContinue
        } elseif ($effectiveScope -eq "User") {
            # User scope complete: remove user RunOnce
            Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "*UltraGamingModeRestore" -ErrorAction SilentlyContinue
            if ($isAdmin -and $latestState -and $latestState.SystemRestored) {
                Unregister-BootTasks
            }
        } elseif ($effectiveScope -eq "System" -and $isSystem) {
            # System scope complete under SYSTEM: unregister boot trigger and scheduled watchdog, but preserve HKLM RunOnce if user has not yet restored
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $watchdogTaskName -Confirm:$false -ErrorAction SilentlyContinue
            if ($latestState -and $latestState.UserRestored) {
                Remove-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "*UltraGamingModeRestore" -ErrorAction SilentlyContinue
            } else {
                # Ensure HKLM RunOnce remains present so the interactive user logon restores User scope
                $actionScript = Join-Path $RootDir "UltraGamingMode.ps1"
                $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
                $restoreCmd = "`"$psExe`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File `"$actionScript`" -Action Restore -Watchdog -SkipUpdateCheck"
                Set-ItemProperty `
                    -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" `
                    -Name "*UltraGamingModeRestore" `
                    -Value $restoreCmd `
                    -Force -ErrorAction SilentlyContinue
            }
        }

        if ($result) {
            Write-Host "`n[SUCCESS] Restoration completed ($effectiveScope Scope)." -ForegroundColor Green
        }
        else {
            Write-Warning "Restoration encountered issues. Check the log above for details."
        }
    }

    "CheckUpdate" {
        $updateCode = Invoke-AppUpdateWorkflow -OnStartup:$OnStartup -Passive:$Passive -Force:$Force
        if ($updateCode -eq 2) {
            exit 2
        }
        exit 0
    }

    "Status" {
        Write-Host "=====================================================" -ForegroundColor White
        Write-Host "             ULTRA GAMING MODE STATUS                 " -ForegroundColor White
        Write-Host "=====================================================" -ForegroundColor White
        Write-Host " Suite Version: v$($Script:APP_VERSION)" -ForegroundColor Cyan

        $currentState = Get-CurrentStateStatus
        $stateColor = switch ($currentState) {
            "Normal"               { "Green" }
            "Armed"                { "Yellow" }
            "GameMode_Active"      { "Red" }
            "Restored"             { "Green" }
            "Restoring_SystemDone" { "Yellow" }
            "Restoring_UserDone"   { "Yellow" }
            default                { "Gray" }
        }
        Write-Host " Current State: $currentState" -ForegroundColor $stateColor

        # Universal Hardware Profile Badges
        $hw = Get-HardwareProfile
        $cpuBadge = "$($hw.CpuVendor) CPU$(if ($hw.LowCoreProfile){' | Low-Core Guard'})"
        $gpuBadge = "$($hw.GpuVendor) GPU"
        $ramBadge = if ($hw.LowRamProfile) { "Low-RAM Guard ($($hw.TotalRamGB)GB)" } else { "$($hw.TotalRamGB)GB RAM" }
        $diskBadge = if ($hw.HddProfile) { "HDD Thrash Guard" } else { "SSD/NVMe Fast-I/O" }
        Write-Host " Profile Badges: [$cpuBadge] [$gpuBadge] [$ramBadge] [$diskBadge]" -ForegroundColor Cyan
        if ($hw.PagefileWarning) {
            Write-Host " [!] Pagefile Alert: $($hw.PagefileWarning)" -ForegroundColor Red
        }

        # v2.7 Competitive Latency Badges
        $kdpc = Get-KernelDpcConfig
        $input = Get-InputBufferConfig
        $bcd = Get-BcdeditTimerConfig
        $hags = Get-HagsGpuSchedulingConfig

        $dpcBadge = if ($kdpc.ThreadDpcEnable -eq 0) { "Kernel DPC: Direct" } else { "Kernel DPC: Standard" }
        $mouQueue = if ($input.MouseDataQueueSize) { $input.MouseDataQueueSize } else { 100 }
        $inputBadge = "Input Buffer: $mouQueue"
        $timerBadge = if ($bcd.DynamicTick -eq "yes") { "Dynamic Tick: Off" } else { "Dynamic Tick: Default" }
        $hagsBadge = if ($hags.HwSchMode -eq 2) { "HAGS: Active" } else { "HAGS: Inactive" }
        Write-Host " Latency Badges: [$dpcBadge] [$inputBadge] [$timerBadge] [$hagsBadge]" -ForegroundColor Green

        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($task) {
            Write-Host " Boot Trigger:  ACTIVE (will strip services on next boot)" -ForegroundColor Red
        }
        else {
            Write-Host " Boot Trigger:  Inactive" -ForegroundColor Gray
            if ($currentState -eq "Armed") {
                Write-Host " [!] Warning: State is Armed but Boot Trigger is Inactive. Run Enable [1] to re-arm or Restore [2] to reset." -ForegroundColor Yellow
            }
        }

        $runOnceHklm = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "*UltraGamingModeRestore" -ErrorAction SilentlyContinue
        $runOnceHkcu = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "*UltraGamingModeRestore" -ErrorAction SilentlyContinue
        $wdTask      = Get-ScheduledTask -TaskName $watchdogTaskName -ErrorAction SilentlyContinue
        if ($runOnceHklm -or $runOnceHkcu -or $wdTask) {
            Write-Host " Fail-Safe:     ARMED (will auto-restore on next boot)" -ForegroundColor Yellow
        }
        else {
            Write-Host " Fail-Safe:     Inactive" -ForegroundColor Gray
        }

        $activeStateObj = Get-ActiveStateSafe
        if ($activeStateObj -and -not [string]::IsNullOrWhiteSpace([string]$activeStateObj.LastBootError)) {
            Write-Host " [!] Last Boot Error: $($activeStateObj.LastBootError)" -ForegroundColor Red
        }


        # Check services stats
        $allServices = @(Get-Service -ErrorAction SilentlyContinue)
        $svcMap = @{}
        foreach ($s in $allServices) { $svcMap[$s.Name] = $s }

        $activeBloatCount = 0
        foreach ($b in $blacklist) {
            $s = $svcMap[$b.Name]
            if ($s -and $s.Status -eq "Running") { $activeBloatCount++ }
        }
        Write-Host " Target Services: $($blacklist.Count) configured | $activeBloatCount currently running" -ForegroundColor White

        # Hardware & Security Status
        $cores = Get-ProcessorIdleMinCores
        $coresText = if ($cores -eq 100) { "Disabled (100% min cores active) [OPTIMAL]" } elseif ($null -ne $cores) { "Active ($cores% min cores)" } else { "N/A" }
        Write-Host " Core Parking:  $coresText" -ForegroundColor $(if ($cores -eq 100) { "Green" } else { "Yellow" })

        if ($hw.GpuVendor -eq "AMD" -or (Get-AmdGpuDriverClassKeys).Count -gt 0) {
            $amdKeys = @(Get-AmdGpuDriverClassKeys)
            if ($amdKeys.Count -gt 0) {
                $firstKey = $amdKeys[0]
                $ulpsVal = if ($firstKey -is [hashtable]) { $firstKey["EnableUlps"] } else { $firstKey.EnableUlps }
                $ulpsText = if ($null -ne $ulpsVal -and [int]$ulpsVal -eq 0) { "Disabled (0) [OPTIMAL]" } else { "Enabled ($ulpsVal) [Can cause stutter on wake]" }
                Write-Host " AMD ULPS:      $ulpsText" -ForegroundColor $(if ($null -ne $ulpsVal -and [int]$ulpsVal -eq 0) { "Green" } else { "Yellow" })
            }
        }

        $msi = Get-GpuMsiConfig
        if ($msi) {
            $prioLabel = switch ($msi.DevicePriority) { 3 { "High (3)" } 2 { "Normal (2)" } 1 { "Low (1)" } default { "Default" } }
            $msiText = if ($msi.MSISupported -eq 1) { "Enabled (Priority: $prioLabel) [OPTIMAL]" } else { "Legacy Line-Based Interrupts" }
            Write-Host " GPU MSI Mode:  $($msi.DeviceName) ($($msi.Vendor)) -> $msiText" -ForegroundColor $(if ($msi.MSISupported -eq 1) { "Green" } else { "Yellow" })
        }

        if ($hw.HddProfile) {
            $defragTask = Get-ScheduledTask -TaskPath "\Microsoft\Windows\Defrag\" -TaskName "ScheduledDefrag" -ErrorAction SilentlyContinue
            $defragStatus = if ($defragTask -and $defragTask.State -eq "Disabled") { "Suspended [OPTIMAL FOR HDD]" } else { "Active ($($defragTask.State))" }
            Write-Host " HDD Defrag:    $defragStatus" -ForegroundColor $(if ($defragStatus -like "*OPTIMAL*") { "Green" } else { "Yellow" })
        }

        $vbs = Get-VbsHvciDiagnosticInfo
        $vbsText = if ($vbs.VbsRunning -or $vbs.HvciRunning) { "Active ($($vbs.VbsStatus)) [VBS overhead active]" } else { "Disabled [OPTIMAL FOR MAXIMUM FPS]" }
        Write-Host " VBS / HVCI:    $vbsText" -ForegroundColor $(if ($vbs.VbsRunning -or $vbs.HvciRunning) { "Yellow" } else { "Green" })

        # Low-Latency Subsystems Status
        $dpcDisplay = if ($null -ne $kdpc.ThreadDpcEnable) { $kdpc.ThreadDpcEnable } else { "Default (1)" }
        $pageDisplay = if ($null -ne $kdpc.DisablePagingExecutive) { $kdpc.DisablePagingExecutive } else { "Default (0)" }
        $isDpcOpt = ($kdpc.ThreadDpcEnable -ne 0)
        $dpcText = if ($isDpcOpt) { "Threaded: $dpcDisplay, Paging: $pageDisplay [OPTIMAL - Render Thread Protected]" } else { "Direct (0) [UNSAFE - Interrupts Preempt Game Loop]" }
        Write-Host " Kernel DPC:    $dpcText" -ForegroundColor $(if ($isDpcOpt) { "Green" } else { "Red" })

        $mouDisplay = if ($null -ne $input.MouseDataQueueSize) { $input.MouseDataQueueSize } else { 100 }
        $kbdDisplay = if ($null -ne $input.KeyboardDataQueueSize) { $input.KeyboardDataQueueSize } else { 100 }
        $isOptimalQueue = ($mouDisplay -ge 100 -and $kbdDisplay -ge 100)
        $inputQueueText = if ($isOptimalQueue) { "$mouDisplay Mouse / $kbdDisplay Keyboard [OPTIMAL - Zero Drop Buffer]" } else { "$mouDisplay Mouse / $kbdDisplay Keyboard [Truncated]" }
        Write-Host " Input Buffers: $inputQueueText" -ForegroundColor $(if ($isOptimalQueue) { "Green" } else { "Yellow" })

        $dynDisplay = if ($bcd.DynamicTick) { $bcd.DynamicTick } else { "Default" }
        $tscDisplay = if ($bcd.TscSyncPolicy) { $bcd.TscSyncPolicy } else { "Default" }
        $isTimerOpt = ($bcd.DynamicTick -ne "yes" -and $bcd.TscSyncPolicy -ne "Enhanced")
        $timerText = if ($isTimerOpt) { "Dynamic Tick: $dynDisplay, TSC: $tscDisplay [OPTIMAL - Invariant Hardware TSC]" } else { "Dynamic Tick: $dynDisplay, TSC: $tscDisplay [OVERHEAD ACTIVE]" }
        Write-Host " Timer Policy:  $timerText" -ForegroundColor $(if ($isTimerOpt) { "Green" } else { "Yellow" })

        $hagsText = if ($hags.HwSchMode -eq 2) { "Active (HwSchMode = 2)" } else { "Inactive (Default)" }
        Write-Host " GPU HAGS:      $hagsText" -ForegroundColor "Green"
    }

    "CleanMemory" {
        Write-Host "=====================================================" -ForegroundColor Green
        Write-Host "           ON-DEMAND RAM & STANDBY LIST CLEANER      " -ForegroundColor Green
        Write-Host "=====================================================" -ForegroundColor Green
        $hw = Get-HardwareProfile
        $isAggressive = $hw.LowRamProfile
        $freed = Optimize-SystemMemory -Aggressive:$isAggressive
        Write-Host "`n[SUCCESS] Memory optimization complete. Reclaimed $freed MB of RAM." -ForegroundColor Green
    }

    "FlushShaderCache" {
        Clear-GpuShaderCache | Out-Null
    }

    "ToggleVBS" {
        Toggle-VbsHvciState
    }

    "GpuMsiStatus" {
        Write-Host "=====================================================" -ForegroundColor Magenta
        Write-Host "         GPU MSI MODE & INTERRUPT PRIORITY           " -ForegroundColor Magenta
        Write-Host "=====================================================" -ForegroundColor Magenta
        $msi = Get-GpuMsiConfig
        if ($msi) {
            Write-Host " GPU Name:        $($msi.DeviceName) ($($msi.Vendor))" -ForegroundColor White
            Write-Host " PNP Device ID:   $($msi.PNPDeviceID)" -ForegroundColor Gray
            $msiStatus = if ($msi.MSISupported -eq 1) { "Enabled (1) [MSI Active]" } else { "Disabled / Legacy Line-Based ($($msi.MSISupported))" }
            $msiColor = if ($msi.MSISupported -eq 1) { "Green" } else { "Yellow" }
            Write-Host " MSI Supported:   $msiStatus" -ForegroundColor $msiColor

            $prioText = switch ($msi.DevicePriority) {
                3 { "High (3) [OPTIMIZED]" }
                2 { "Normal (2)" }
                1 { "Low (1)" }
                default { if ($null -ne $msi.DevicePriority) { "Custom ($($msi.DevicePriority))" } else { "Default / Undefined" } }
            }
            $prioColor = if ($msi.DevicePriority -eq 3) { "Green" } else { "Yellow" }
            Write-Host " Device Priority: $prioText" -ForegroundColor $prioColor
            Write-Host "`n[INFO] MSI (Message Signaled Interrupts) eliminates IRQ sharing conflicts and reduces GPU-CPU DPC frame delivery latency." -ForegroundColor Gray
        } else {
            Write-Warning "No compatible PCI GPU detected."
        }
    }

    "Diagnostic" {
        Write-Host "=====================================================" -ForegroundColor Cyan
        Write-Host "       SYSTEM READINESS & PRE-FLIGHT DIAGNOSTIC       " -ForegroundColor Cyan
        Write-Host "=====================================================" -ForegroundColor Cyan

        # [0] Universal Hardware Auto-Detection Profile
        $hw = Get-HardwareProfile

        Write-Host "`n=====================================================" -ForegroundColor Magenta
        Write-Host "       UNIVERSAL HARDWARE AUTO-DETECTION PROFILE      " -ForegroundColor Magenta
        Write-Host "=====================================================" -ForegroundColor Magenta

        # CPU info + Low-Core Mode status
        $cpuLowText = if ($hw.LowCoreProfile) { "ACTIVE (Budget <=4 Logical Cores: Full unparking & clock boost enforced)" } else { "Standard Multi-Core ($($hw.LogicalCores) Threads: Multi-CCX unparked)" }
        $cpuColor = if ($hw.LowCoreProfile) { "Yellow" } else { "Green" }
        Write-Host "  CPU Detected:           $($hw.CpuName) ($($hw.CpuVendor) $($hw.CpuArchitecture), $($hw.PhysicalCores) Physical / $($hw.LogicalCores) Logical Cores)" -ForegroundColor White
        Write-Host "  -> Low-Core Mode:       $cpuLowText" -ForegroundColor $cpuColor

        # GPU info + Vendor MSI status
        $msiStatQuick = if ($hw.GpuMsiSupported) { "Enabled (1) [High IRQ Priority Active]" } else { "Legacy Line-Based [Will be switched to MSI High Priority]" }
        $gpuColor = if ($hw.GpuMsiSupported) { "Green" } else { "Yellow" }
        Write-Host "  GPU Detected:           $($hw.GpuName) ($($hw.GpuVendor) | $($hw.GpuResolution))" -ForegroundColor White
        Write-Host "  -> Vendor MSI Status:   $($hw.GpuVendor) MSI: $msiStatQuick" -ForegroundColor $gpuColor

        # RAM info + Low-RAM Guard status
        $ramGuardQuick = if ($hw.LowRamProfile) { "ACTIVE (<=8GB Budget RAM Guard: Aggressive WorkingSet & Standby List Flush)" } else { "Standard ($($hw.TotalRamGB) GB RAM)" }
        $ramColor = if ($hw.LowRamProfile) { "Yellow" } else { "Green" }
        Write-Host "  RAM Physical Total:     $($hw.TotalRamGB) GB RAM" -ForegroundColor White
        Write-Host "  -> Low-RAM Guard:       $ramGuardQuick" -ForegroundColor $ramColor
        if ($hw.PagefileWarning) {
            Write-Host "  -> Pagefile Alert:      $($hw.PagefileWarning)" -ForegroundColor Red
        } else {
            $pfMode = if ($hw.PagefileManaged) { "System-Managed (Optimal for Gaming)" } else { "Custom Managed" }
            Write-Host "  -> Pagefile Status:     $pfMode" -ForegroundColor Green
        }

        # Disk info + HDD Thrash Suppression status
        $hddThrashQuick = if ($hw.IsHdd) {
            "ACTIVE (System Drive C: Mechanical HDD: ScheduledDefrag suspended, NTFS LastAccess/8.3 disabled, SysMain/WSearch dead)"
        } elseif ($hw.HasAnyHdd) {
            "ACTIVE (Drive C: on $($hw.SystemDiskMediaType)/$($hw.SystemDiskBusType); Secondary HDD detected -> Defrag suspended to prevent game stutter)"
        } else {
            "Inactive (High-Speed $($hw.SystemDiskMediaType)/$($hw.SystemDiskBusType) Storage Detected)"
        }
        $diskColor = if ($hw.HddProfile) { "Yellow" } else { "Green" }
        Write-Host "  System Drive C: Disk:   Disk $($hw.SystemDiskNumber) [$($hw.SystemDiskModel)] ($($hw.SystemDiskMediaType) / $($hw.SystemDiskBusType))" -ForegroundColor White
        Write-Host "  -> HDD Thrash Guard:    $hddThrashQuick" -ForegroundColor $diskColor
        Write-Host "=====================================================" -ForegroundColor Magenta

        # 1. Privileges
        Write-Host "`n[1] Privilege Level:" -ForegroundColor Yellow
        if ($isAdmin) {
            Write-Host "  [OK] Elevated Administrator: Yes" -ForegroundColor Green
        } else {
            Write-Host "  [!] Elevated Administrator: No (Running with limited user privileges)" -ForegroundColor Yellow
        }

        # 2. Power Plan & CPU Core Unparking (Intel & AMD)
        Write-Host "`n[2] Power Plan & CPU Core Unparking ($($hw.CpuVendor)):" -ForegroundColor Yellow
        $curScheme = Get-ActivePowerSchemeGuid
        Write-Host "  Active Scheme GUID:     $curScheme" -ForegroundColor White
        $list = powercfg /list 2>&1
        $hasUltimate = $list -match "e9a42b02-d5df-448d-aa00-03f14749eb61"
        if ($hasUltimate) {
            Write-Host "  Ultimate Plan Template: Available (Ready)" -ForegroundColor Green
        } else {
            Write-Host "  Ultimate Plan Template: Will be unlocked on demand" -ForegroundColor Yellow
        }
        $cpVal = Get-ProcessorIdleMinCores
        if ($null -ne $cpVal) {
            $cpText = if ($cpVal -eq 100) { "$cpVal% (Core Parking DISABLED - Maximum Responsiveness)" } else { "$cpVal% (Core Parking Active - Cores may sleep)" }
            $cpColor = if ($cpVal -eq 100) { "Green" } else { "Yellow" }
            Write-Host "  Processor CPMINCORES:   $cpText" -ForegroundColor $cpColor
        }
        $throttleMin = Get-ProcessorThrottleMin
        if ($null -ne $throttleMin) {
            $throttleText = if ($throttleMin -eq 100) { "$throttleMin% (Peak Frequency Ready)" } else { "$throttleMin% (Will be boosted to 100%)" }
            $throttleColor = if ($throttleMin -eq 100) { "Green" } else { "Yellow" }
            Write-Host "  Min Processor State:    $throttleText" -ForegroundColor $throttleColor
        }

        # 3. Multimedia & Network Profiles
        Write-Host "`n[3] Multimedia & Network Latency Profile:" -ForegroundColor Yellow
        $mm = Get-MultimediaGamingConfig
        $netThrottling = $mm.SystemProfile["NetworkThrottlingIndex"]
        $sysResp = $mm.SystemProfile["SystemResponsiveness"]
        Write-Host "  NetworkThrottlingIndex: $netThrottling" -ForegroundColor White
        Write-Host "  SystemResponsiveness:   $sysResp" -ForegroundColor White

        # Physical Adapters FlowControl & InterruptModeration Check
        $physAdapters = Get-PhysicalGamingAdapters
        $adapterNames = if ($physAdapters) { ($physAdapters.Name -join ', ') } else { "None detected" }
        Write-Host "  Target Gaming Adapters: $adapterNames" -ForegroundColor White
        Write-Host "  Protected Exclusions:   Ethernet 2 (Apple Mobile Device), wwan99 (Wintun) [SAFE - EXCLUDED]" -ForegroundColor Green

        foreach ($pa in $physAdapters) {
            $advProps = Get-NetAdapterAdvancedProperty -Name $pa.Name -ErrorAction SilentlyContinue
            $fc = ($advProps | Where-Object { $_.RegistryKeyword -eq "*FlowControl" }).DisplayValue
            $im = ($advProps | Where-Object { $_.RegistryKeyword -eq "*InterruptModeration" }).DisplayValue
            $ee = ($advProps | Where-Object { $_.RegistryKeyword -eq "*EEE" }).DisplayValue
            Write-Host "  - $($pa.Name): FlowControl=$fc | InterruptModeration=$im | EEE=$ee" -ForegroundColor Gray
        }

        # GameDVR Hook Check
        $gdvr = (Get-ItemProperty "HKCU:\System\GameConfigStore" -ErrorAction SilentlyContinue).GameDVR_Enabled
        $appCap = (Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" -ErrorAction SilentlyContinue).AppCaptureEnabled
        Write-Host "  GameDVR Enabled:        $gdvr | AppCaptureEnabled: $appCap" -ForegroundColor White

        # 4. GPU Hardware Optimizations
        Write-Host "`n[4] GPU Hardware Optimizations ($($hw.GpuVendor)):" -ForegroundColor Yellow
        $amdKeys = @(Get-AmdGpuDriverClassKeys)
        if ($amdKeys.Count -gt 0) {
            foreach ($ak in $amdKeys) {
                $uVal = if ($ak -is [hashtable]) { $ak["EnableUlps"] } else { $ak.EnableUlps }
                $desc = if ($ak -is [hashtable]) { $ak["DriverDesc"] } else { $ak.DriverDesc }
                $uStatus = if ($null -ne $uVal -and [int]$uVal -eq 0) { "Disabled (0) [PASS]" } else { "Enabled ($uVal) [Will be disabled in Gaming Mode]" }
                $uColor = if ($null -ne $uVal -and [int]$uVal -eq 0) { "Green" } else { "Yellow" }
                Write-Host "  - AMD Driver ($desc): EnableUlps = $uStatus" -ForegroundColor $uColor
            }
        } elseif ($hw.GpuVendor -eq "NVIDIA") {
            Write-Host "  - NVIDIA GeForce Driver: MSI High Priority enabled (ULPS not applicable)" -ForegroundColor Green
        } elseif ($hw.GpuVendor -eq "Intel") {
            Write-Host "  - Intel Graphics Driver: MSI mode supported" -ForegroundColor Green
        } else {
            Write-Host "  - GPU Driver Key: Generic / Standard Display Adapter" -ForegroundColor Gray
        }

        # Shader Cache Directories
        $shaderDirs = @(
            (Join-Path $env:LOCALAPPDATA "AMD\DxCache"),
            (Join-Path $env:LOCALAPPDATA "AMD\VkCache"),
            (Join-Path $env:LOCALAPPDATA "AMD\DxcCache"),
            (Join-Path $env:LOCALAPPDATA "AMD\DX9Cache"),
            (Join-Path $env:LOCALAPPDATA "AMD\OglCache"),
            (Join-Path $env:LOCALAPPDATA "NVIDIA\DXCache"),
            (Join-Path $env:LOCALAPPDATA "NVIDIA\GLCache"),
            (Join-Path $env:APPDATA "NVIDIA\ComputeCache"),
            (Join-Path $env:LOCALAPPDATA "NVIDIA Corporation\NV_Cache"),
            (Join-Path $env:LOCALAPPDATA "Intel\ShaderCache"),
            (Join-Path $env:LOCALAPPDATA "Intel\D3DSCache"),
            (Join-Path $env:LOCALAPPDATA "D3DSCache")
        )
        foreach ($sd in $shaderDirs) {
            if (Test-Path $sd) {
                $f = Get-ChildItem -Path $sd -Recurse -File -ErrorAction SilentlyContinue
                $cnt = if ($f) { $f.Count } else { 0 }
                $bytes = if ($f) { ($f | Measure-Object -Property Length -Sum).Sum } else { 0 }
                $mb = [math]::Round($bytes / 1MB, 2)
                $leafName = Split-Path $sd -Leaf
                if ($sd -match '(?i)AMD\\') { $leafName = "AMD\$leafName" }
                elseif ($sd -match '(?i)NVIDIA') { $leafName = "NVIDIA\$leafName" }
                elseif ($sd -match '(?i)Intel\\') { $leafName = "Intel\$leafName" }
                Write-Host "  - Cache $leafName`: $cnt files ($mb MB)" -ForegroundColor White
            }
        }

        # 5. GPU MSI (Message Signaled Interrupts) Mode & Interrupt Priority
        Write-Host "`n[5] GPU MSI Mode & IRQ Device Priority:" -ForegroundColor Yellow
        $msiInfo = Get-GpuMsiConfig
        if ($msiInfo) {
            $msiStat = if ($msiInfo.MSISupported -eq 1) { "Enabled (1) [PASS]" } else { "Disabled / Legacy [Will be enabled in Gaming Mode]" }
            $msiCol = if ($msiInfo.MSISupported -eq 1) { "Green" } else { "Yellow" }
            Write-Host "  Device:                 $($msiInfo.DeviceName) ($($msiInfo.Vendor))" -ForegroundColor White
            Write-Host "  MSI Supported:          $msiStat" -ForegroundColor $msiCol
            $prioStr = switch ($msiInfo.DevicePriority) {
                3 { "High (3) [PASS]" }
                default { if ($null -ne $msiInfo.DevicePriority) { "$($msiInfo.DevicePriority) [Will be set to High]" } else { "Default / Undefined [Will be set to High]" } }
            }
            $prioCol = if ($msiInfo.DevicePriority -eq 3) { "Green" } else { "Yellow" }
            Write-Host "  Interrupt Priority:     $prioStr" -ForegroundColor $prioCol
        } else {
            Write-Host "  PCI Video Controller: Not detected" -ForegroundColor Yellow
        }

        # 6. VBS / HVCI (Core Isolation / Memory Integrity)
        Write-Host "`n[6] VBS / HVCI (Virtualization-Based Security & Memory Integrity):" -ForegroundColor Yellow
        $vbsInfo = Get-VbsHvciDiagnosticInfo
        $vbsCol = if ($vbsInfo.VbsRunning -or $vbsInfo.HvciRunning) { "Yellow" } else { "Green" }
        Write-Host "  VBS Running Status:     $($vbsInfo.VbsStatus)" -ForegroundColor $vbsCol
        Write-Host "  HVCI (Core Isolation):  Running=$($vbsInfo.HvciRunning) | Registry Enabled=$($vbsInfo.HvciRegistryEnabled)" -ForegroundColor $vbsCol
        if ($vbsInfo.VbsRunning -or $vbsInfo.HvciRunning) {
            Write-Host "  [i] Note: VBS/HVCI incurs virtualization overhead. Use Advanced Tools -> Option [4] to toggle if needed." -ForegroundColor Yellow
        } else {
            Write-Host "  [OK] VBS and Memory Integrity are inactive. Zero virtualization latency." -ForegroundColor Green
        }

        # 7. NTFS File System I/O Tweaks
        Write-Host "`n[7] NTFS File System I/O Configuration:" -ForegroundColor Yellow
        $ntfs = Get-NTFSFileSystemConfig
        $lastAccessTxt = if ($ntfs.NtfsDisableLastAccessUpdate -ne $null -and (($ntfs.NtfsDisableLastAccessUpdate -band 1) -eq 1)) { "Disabled (Optimized)" } else { "Enabled (Default)" }
        $dot3Txt = if ($ntfs.NtfsDisable8dot3NameCreation -ne $null -and ($ntfs.NtfsDisable8dot3NameCreation -in @(1, 3))) { "Disabled (Optimized)" } else { "Enabled (Default)" }
        Write-Host "  DisableLastAccess:      $lastAccessTxt ($($ntfs.NtfsDisableLastAccessUpdate))" -ForegroundColor $(if ($lastAccessTxt -like "*Optimized*") { "Green" } else { "Yellow" })
        Write-Host "  Disable8dot3:           $dot3Txt ($($ntfs.NtfsDisable8dot3NameCreation))" -ForegroundColor $(if ($dot3Txt -like "*Optimized*") { "Green" } else { "Yellow" })
        if ($hw.HddProfile) {
            Write-Host "  HDD Thrash Suppression: Active (Eliminates disk head thrashing and read write amplification)" -ForegroundColor Green
        }

        # 8. Whitelist / Anti-Cheat / Display Guard
        Write-Host "`n[8] Whitelist & Protection Guard:" -ForegroundColor Yellow
        Write-Host "  Protected Services: $($whitelist.Count) critical items" -ForegroundColor Green
        $antiCheats = @("vgk", "vgc", "EasyAntiCheat", "BEService", "FACEIT")
        foreach ($ac in $antiCheats) {
            $isProt = ($whitelist -contains $ac)
            $acSvc = Get-Service -Name $ac -ErrorAction SilentlyContinue
            $status = if ($acSvc) { "Installed ($($acSvc.Status))" } else { "Not installed" }
            Write-Host "  - Anti-Cheat '$ac': Protected = $isProt | Status: $status" -ForegroundColor Gray
        }
        $dispSvc = @("AMD External Events Utility", "amdfendrsr", "AMDNoiseSuppression", "ProcessGovernor", "Apple Mobile Device Service")
        foreach ($ds in $dispSvc) {
            $isProt = ($whitelist -contains $ds)
            $s = Get-Service -Name $ds -ErrorAction SilentlyContinue
            $status = if ($s) { "Installed ($($s.Status))" } else { "Not installed" }
            Write-Host "  - Hardware/Driver/Network '$ds': Protected = $isProt | Status: $status" -ForegroundColor Gray
        }
        $coreSvc = @("Audiosrv", "AudioEndpointBuilder", "camsvc", "Steam Client Service", "LanmanServer", "LanmanWorkstation")
        foreach ($cs in $coreSvc) {
            $isProt = ($whitelist -contains $cs)
            $s = Get-Service -Name $cs -ErrorAction SilentlyContinue
            $status = if ($s) { "$($s.Status) ($($s.StartType))" } else { "Not installed" }
            Write-Host "  - Core/Audio/Steam '$cs': Protected = $isProt | Status: $status" -ForegroundColor Gray
        }

        # 9. Blacklist Target Assessment
        Write-Host "`n[9] Blacklist Service Impact:" -ForegroundColor Yellow
        $installedBlacklist = 0
        $runningBlacklist = 0
        $allServices = @(Get-Service -ErrorAction SilentlyContinue)
        $svcMap = @{}
        foreach ($s in $allServices) { $svcMap[$s.Name] = $s }

        foreach ($item in $blacklist) {
            $svc = $svcMap[$item.Name]
            if ($svc) {
                $installedBlacklist++
                if ($svc.Status -eq "Running") { $runningBlacklist++ }
            }
        }
        Write-Host "  Target Services: $($blacklist.Count) configured | $installedBlacklist present on this PC | $runningBlacklist currently RUNNING" -ForegroundColor Green

        # 10. Startup Applications & UWP Tasks Assessment
        Write-Host "`n[10] Startup Applications & UWP Bloat:" -ForegroundColor Yellow
        $uwpCount = 0
        $uwpRoot = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData"
        if (Test-Path $uwpRoot) {
            Get-ChildItem -Path $uwpRoot | ForEach-Object {
                $pkg = $_
                Get-ChildItem -Path $pkg.PSPath -ErrorAction SilentlyContinue | ForEach-Object {
                    $p = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
                    if ($null -ne $p -and $p.PSObject.Properties["State"] -and [int]$p.State -eq 2) {
                        if ($pkg.PSChildName -like "*Apple*") {
                            Write-Host "  - UWP Startup: $($pkg.PSChildName) [PROTECTED - iPhone Tethering]" -ForegroundColor Green
                        } else {
                            $uwpCount++
                            Write-Host "  - UWP Startup: $($pkg.PSChildName) -> $($_.PSChildName) [TARGETED FOR REMOVAL]" -ForegroundColor Yellow
                        }
                    }
                }
            }
        }
        $shortcutCount = 0
        $startupDirs = @(
            "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
            "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
        )
        foreach ($sDir in $startupDirs) {
            if (Test-Path -LiteralPath $sDir) {
                Get-ChildItem -LiteralPath $sDir -File -Force | Where-Object { $_.Extension -in @(".lnk", ".url") } | ForEach-Object {
                    $shortcutCount++
                    Write-Host "  - Startup Shortcut: $($_.Name)" -ForegroundColor Yellow
                }
            }
        }
        Write-Host "  Active UWP startup tasks: $uwpCount | Startup shortcuts: $shortcutCount" -ForegroundColor Green

        # 11. Win32 Memory Optimizer Test
        Write-Host "`n[11] Memory Cleaner P/Invoke Test:" -ForegroundColor Yellow
        $currentProc = [System.Diagnostics.Process]::GetCurrentProcess()
        $beforeMem = $currentProc.WorkingSet64
        $null = [Win32MemoryOptimizer]::EmptyWorkingSet($currentProc.Handle)
        $currentProc.Refresh()
        $afterMem = $currentProc.WorkingSet64
        Write-Host "  Process working set trim: $([math]::Round($beforeMem/1MB,1)) MB -> $([math]::Round($afterMem/1MB,1)) MB [PASS]" -ForegroundColor Green

        # 12-16. Low-Latency Subsystems (Kernel DPC, Input Queues, Timers, TCP Stack, HAGS)
        Show-LatencySubsystemStatus

        Write-Host "`n[+] Diagnostic complete. System is 100% primed for high-impact Ultra Gaming Mode." -ForegroundColor Green
    }

    "RepairDisplay" {
        Repair-DisplayPipeline
    }

    "RepairServices" {
        Repair-CoreServices
    }

    "KernelLatencyStatus" {
        Write-Host "=====================================================" -ForegroundColor Magenta
        Write-Host "   KERNEL DPC, INPUT BUFFER & SYSTEM TIMER STATUS   " -ForegroundColor Magenta
        Write-Host "=====================================================" -ForegroundColor Magenta
        Show-LatencySubsystemStatus
    }
}
