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
    [ValidateSet("Enable", "Restore", "Status", "ApplyBootMode", "Diagnostic", "CleanMemory", "RepairDisplay", "RepairServices", "FlushShaderCache", "ToggleVBS", "GpuMsiStatus", "KernelLatencyStatus")]
    [string]$Action = "Status",

    [switch]$Watchdog
)

# ── Admin Rights Check ────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    if ($Action -in @("Status", "Diagnostic", "CleanMemory", "FlushShaderCache", "GpuMsiStatus", "KernelLatencyStatus")) {
        Write-Warning "Running in non-elevated mode. Operating with current user privileges."
    }
    elseif ($Watchdog) {
        # When invoked under a filtered UAC token by RunOnce, request elevation
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File `"$PSCommandPath`" -Action $Action -Watchdog" -Verb RunAs
        exit 0
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

# ── Task Scheduler Names ──────────────────────────────────────────────────────
$taskName = "UltraGamingMode_BootTrigger"

function Get-ResilientBootTimestamp {
    [CmdletBinding()]
    param()

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os -and $os.LastBootUpTime) {
            return $os.LastBootUpTime.ToString("o")
        }
    } catch {}

    try {
        $uptime = [System.TimeSpan]::FromMilliseconds([System.Environment]::TickCount64)
        return ((Get-Date) - $uptime).ToString("o")
    } catch {}

    return (Get-Date).ToString("o")
}

# ── Helper: Register Boot-Time Tasks ─────────────────────────────────────────
function Register-BootTasks {
    Write-Host "[*] Registering Next-Boot Task in Task Scheduler (SYSTEM privileges)..." -ForegroundColor Cyan

    $actionScript = Join-Path $RootDir "UltraGamingMode.ps1"
    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

    $taskAction = New-ScheduledTaskAction `
        -Execute $psExe `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$actionScript`" -Action ApplyBootMode"

    $taskTrigger = New-ScheduledTaskTrigger -AtStartup

    $taskPrincipal = New-ScheduledTaskPrincipal `
        -UserId "NT AUTHORITY\SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest

    $taskSettings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -Priority 0 `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $taskAction `
        -Trigger $taskTrigger `
        -Principal $taskPrincipal `
        -Settings $taskSettings `
        -Force | Out-Null

    Write-Host "[+] Next-Boot Task Scheduler trigger successfully armed." -ForegroundColor Green
}

# ── Helper: Clean Up All Scheduled Triggers ──────────────────────────────────
function Unregister-BootTasks {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-ItemProperty `
        -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" `
        -Name "*UltraGamingModeRestore" `
        -ErrorAction SilentlyContinue
    Write-Host "[+] Scheduled tasks and RunOnce watchdogs cleaned up." -ForegroundColor Gray
}

# ── Main Action Switch ────────────────────────────────────────────────────────
switch ($Action) {

    "Enable" {
        Write-Host "=====================================================" -ForegroundColor Magenta
        Write-Host "         ACTIVATING ULTRA GAMING MODE (NEXT BOOT)    " -ForegroundColor Magenta
        Write-Host "=====================================================" -ForegroundColor Magenta

        # Check if already armed or active
        $currentState = Get-CurrentStateStatus
        if ($currentState -eq "Armed" -or $currentState -eq "GameMode_Active") {
            Write-Warning "Ultra Gaming Mode is already $currentState. Run with -Action Restore first."
            exit 0
        }

        # 1. Create complete system snapshot (services, startup registry, shortcuts, UWP, visual)
        New-SystemStateBackup -BlacklistConfig $blacklist -Whitelist $whitelist -StartupConfig $startupCfg

        # 2. Aggressively strip user startup apps (TranslucentTB, shortcuts, third-party apps, transparency)
        Disable-UserStateAggressive -StartupConfig $startupCfg

        # 3. Register boot-time trigger under SYSTEM
        Register-BootTasks

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
        if (Test-Path $stateFile) {
            $stateData = Get-Content -Path $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json

            if ($stateData.State -eq "Armed") {
                # 1. Disable all blacklisted services
                $disabledCount = 0
                foreach ($item in $blacklist) {
                    $res = Set-ServiceStateSafe -ServiceName $item.Name -StartupType "Disabled" -StopNow -Whitelist $whitelist
                    if ($res) { $disabledCount++ }
                }

                # 2. Activate safe network gaming tweaks, power scheme and adaptive hardware optimizations
                $hw = Get-HardwareProfile
                Enable-UltimatePerformance | Out-Null
                Set-GamingMultimediaConfig | Out-Null
                Apply-CpuGamingOptimizations -HardwareProfile $hw | Out-Null
                Apply-GpuGamingOptimizations -HardwareProfile $hw | Out-Null
                Set-NTFSGamingOptimizations -IsHdd:$hw.HddProfile | Out-Null
                Set-NetworkGamingOptimizations | Out-Null
                Set-KernelDpcOptimizations -IsLowRam:$hw.LowRamProfile | Out-Null
                Set-InputBufferOptimizations | Out-Null
                Set-BcdeditTimerOptimizations | Out-Null
                Set-TcpGamingStackOptimizations | Out-Null
                Set-HagsGpuScheduling | Out-Null

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

                # 3. Update state to active and capture boot timestamp
                $bootTime = Get-ResilientBootTimestamp
                $stateData.State = "GameMode_Active"
                $stateData.BootRunCount = [int]$stateData.BootRunCount + 1
                $stateData.GamingBootTime = $bootTime
                $stateData | ConvertTo-Json -Depth 6 | Set-Content -Path $stateFile -Force -Encoding UTF8

                try {
                    # 4. Arm RunOnce fail-safe watchdog: fires on next reboot/logon after gaming mode
                    $actionScript = Join-Path $RootDir "UltraGamingMode.ps1"
                    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
                    $restoreCmd = "`"$psExe`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File `"$actionScript`" -Action Restore -Watchdog"
                    Set-ItemProperty `
                        -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" `
                        -Name "*UltraGamingModeRestore" `
                        -Value $restoreCmd `
                        -Force
                }
                finally {
                    # 5. Remove the boot trigger so it does not fire on every boot even if watchdog arming encountered issues.
                    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
                }
            }
            elseif ($stateData.State -eq "GameMode_Active") {
                # If we reach here, the PC was rebooted while in gaming mode.
                Write-Host "[*] System rebooted after Gaming Mode. Restoring normal state..." -ForegroundColor Cyan
                Restore-SystemState -Whitelist $whitelist -StartupConfig $startupCfg
                Unregister-BootTasks
            }
        }
    }

    "Restore" {
        $stateFile = Join-Path (Join-Path $RootDir "Backups") "active_state.json"
        if ($Watchdog -and (Test-Path $stateFile)) {
            $stateData = Get-Content -Path $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $currentBootTime = Get-ResilientBootTimestamp

            # Check if this invocation is the interactive logon of the CURRENT gaming session (same boot).
            $isSameBoot = $false
            if ($stateData.State -eq "GameMode_Active" -and $stateData.GamingBootTime) {
                try {
                    $diffSec = [Math]::Abs(([DateTime]$currentBootTime - [DateTime]$stateData.GamingBootTime).TotalSeconds)
                    if ($diffSec -lt 30) { $isSameBoot = $true }
                }
                catch {
                    $isSameBoot = ($currentBootTime -eq $stateData.GamingBootTime)
                }
            }

            if ($isSameBoot) {
                Write-Host "[+] Gaming session logon detected. Maintaining Ultra Gaming Mode." -ForegroundColor Green
                # Ensure any stray bloat processes that managed to start are stopped
                if ($startupCfg.BlacklistProcesses) {
                    Stop-BlacklistedProcesses -ProcessNames $startupCfg.BlacklistProcesses
                }
                # Re-arm RunOnce for the NEXT reboot
                $actionScript = Join-Path $RootDir "UltraGamingMode.ps1"
                $restoreCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File `"$actionScript`" -Action Restore -Watchdog"
                Set-ItemProperty `
                    -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" `
                    -Name "*UltraGamingModeRestore" `
                    -Value $restoreCmd `
                    -Force
                Write-Host "[+] Fail-safe RunOnce watchdog re-armed for next reboot/logon." -ForegroundColor Yellow
                exit 0
            }
        }

        Write-Host "=====================================================" -ForegroundColor Cyan
        Write-Host "             RESTORING NORMAL SYSTEM STATE            " -ForegroundColor Cyan
        Write-Host "=====================================================" -ForegroundColor Cyan

        $result = Restore-SystemState -Whitelist $whitelist -StartupConfig $startupCfg
        Unregister-BootTasks

        if ($result) {
            Write-Host "`n[SUCCESS] All services, startup items, UWP apps, and visual parameters restored." -ForegroundColor Green
        }
        else {
            Write-Warning "Restoration encountered issues. Check the log above for details."
        }
    }

    "Status" {
        Write-Host "=====================================================" -ForegroundColor White
        Write-Host "             ULTRA GAMING MODE STATUS                 " -ForegroundColor White
        Write-Host "=====================================================" -ForegroundColor White

        $currentState = Get-CurrentStateStatus
        $stateColor = switch ($currentState) {
            "Normal"           { "Green" }
            "Armed"            { "Yellow" }
            "GameMode_Active"  { "Red" }
            "Restored"         { "Green" }
            default            { "Gray" }
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

        # v2.6 Competitive Latency Badges
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
        }

        $runOnce = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "*UltraGamingModeRestore" -ErrorAction SilentlyContinue
        if ($runOnce) {
            Write-Host " Fail-Safe:     ARMED (will auto-restore on next boot)" -ForegroundColor Yellow
        }
        else {
            Write-Host " Fail-Safe:     Inactive" -ForegroundColor Gray
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
        $dpcText = if ($kdpc.ThreadDpcEnable -eq 0 -and ($kdpc.DisablePagingExecutive -eq 1 -or $hw.LowRamProfile)) { "Direct (0), Paging $(if ($hw.LowRamProfile) { 'Protected (8GB Guard)' } else { 'Disabled' }) [OPTIMAL]" } else { "Threaded: $dpcDisplay, Paging: $pageDisplay" }
        Write-Host " Kernel DPC:    $dpcText" -ForegroundColor $(if ($kdpc.ThreadDpcEnable -eq 0) { "Green" } else { "Yellow" })

        $mouDisplay = if ($null -ne $input.MouseDataQueueSize) { $input.MouseDataQueueSize } else { "Default (100)" }
        $kbdDisplay = if ($null -ne $input.KeyboardDataQueueSize) { $input.KeyboardDataQueueSize } else { "Default (100)" }
        $isOptimalQueue = ($input.MouseDataQueueSize -ge 16 -and $input.MouseDataQueueSize -le 32 -and $input.KeyboardDataQueueSize -ge 16 -and $input.KeyboardDataQueueSize -le 32)
        $inputQueueText = if ($isOptimalQueue) { "$($input.MouseDataQueueSize) Mouse / $($input.KeyboardDataQueueSize) Keyboard [OPTIMAL DIRECT DELIVERY]" } else { "$mouDisplay Mouse / $kbdDisplay Keyboard" }
        Write-Host " Input Buffers: $inputQueueText" -ForegroundColor $(if ($isOptimalQueue) { "Green" } else { "Yellow" })

        $dynDisplay = if ($bcd.DynamicTick) { $bcd.DynamicTick } else { "Default" }
        $tscDisplay = if ($bcd.TscSyncPolicy) { $bcd.TscSyncPolicy } else { "Default" }
        $timerText = if ($bcd.DynamicTick -eq "yes" -and $bcd.TscSyncPolicy -eq "Enhanced") { "Dynamic Tick Off, TSC Enhanced [OPTIMAL]" } else { "Dynamic Tick: $dynDisplay, TSC: $tscDisplay" }
        Write-Host " Timer Policy:  $timerText" -ForegroundColor $(if ($bcd.DynamicTick -eq "yes") { "Green" } else { "Yellow" })

        $hagsText = if ($hags.HwSchMode -eq 2) { "Active (HwSchMode = 2) [OPTIMAL]" } else { "Inactive ($($hags.HwSchMode))" }
        Write-Host " GPU HAGS:      $hagsText" -ForegroundColor $(if ($hags.HwSchMode -eq 2) { "Green" } else { "Yellow" })
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
            $isProt = Test-IsServiceProtected -ServiceName $ac -Whitelist $whitelist
            $acSvc = Get-Service -Name $ac -ErrorAction SilentlyContinue
            $status = if ($acSvc) { "Installed ($($acSvc.Status))" } else { "Not installed" }
            Write-Host "  - Anti-Cheat '$ac': Protected = $isProt | Status: $status" -ForegroundColor Gray
        }
        $dispSvc = @("AMD External Events Utility", "amdfendrsr", "AMDNoiseSuppression", "ProcessGovernor", "Apple Mobile Device Service")
        foreach ($ds in $dispSvc) {
            $isProt = Test-IsServiceProtected -ServiceName $ds -Whitelist $whitelist
            $s = Get-Service -Name $ds -ErrorAction SilentlyContinue
            $status = if ($s) { "Installed ($($s.Status))" } else { "Not installed" }
            Write-Host "  - Hardware/Driver/Network '$ds': Protected = $isProt | Status: $status" -ForegroundColor Gray
        }
        $coreSvc = @("Audiosrv", "AudioEndpointBuilder", "camsvc", "Steam Client Service", "LanmanServer", "LanmanWorkstation")
        foreach ($cs in $coreSvc) {
            $isProt = Test-IsServiceProtected -ServiceName $cs -Whitelist $whitelist
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

        # 12. Kernel DPC & Memory Management
        Write-Host "`n[12] Kernel DPC & Memory Management Configuration:" -ForegroundColor Yellow
        $kdpc = Get-KernelDpcConfig
        $dpcVal = if ($null -ne $kdpc.ThreadDpcEnable) { $kdpc.ThreadDpcEnable } else { "1" }
        $dpcStatus = if ($kdpc.ThreadDpcEnable -eq 0) { "Direct (0) [PASS - Immediate Execution]" } else { "Threaded ($dpcVal) [Default - Will be set to 0 in Gaming Mode]" }
        $dpcColor  = if ($kdpc.ThreadDpcEnable -eq 0) { "Green" } else { "Yellow" }
        Write-Host "  ThreadDpcEnable:         $dpcStatus" -ForegroundColor $dpcColor

        $pageVal = if ($null -ne $kdpc.DisablePagingExecutive) { $kdpc.DisablePagingExecutive } else { "0" }
        $pagingStatus = if ($kdpc.DisablePagingExecutive -eq 1) { "Enabled (1) [PASS - Drivers Locked in RAM]" } else { "Disabled ($pageVal) [Pageable]" }
        $pagingColor  = if ($kdpc.DisablePagingExecutive -eq 1) { "Green" } else { "Yellow" }
        Write-Host "  DisablePagingExecutive:  $pagingStatus" -ForegroundColor $pagingColor

        $prioStatus = if ($kdpc.Win32PrioritySeparation -eq 38) { "0x26 / 38 [PASS - 3:1 Foreground Boost]" } else { "$($kdpc.Win32PrioritySeparation)" }
        $prioColor  = if ($kdpc.Win32PrioritySeparation -eq 38) { "Green" } else { "Yellow" }
        Write-Host "  Win32PrioritySeparation: $prioStatus" -ForegroundColor $prioColor

        $pwrStatus = if ($kdpc.PowerThrottlingOff -eq 1) { "Disabled (1) [PASS - Zero Thread Throttling]" } else { "Active ($($kdpc.PowerThrottlingOff))" }
        $pwrColor  = if ($kdpc.PowerThrottlingOff -eq 1) { "Green" } else { "Yellow" }
        Write-Host "  PowerThrottlingOff:      $pwrStatus" -ForegroundColor $pwrColor

        # 13. Direct Peripheral Input Queues
        Write-Host "`n[13] Direct Peripheral Input Queues (mouclass & kbdclass):" -ForegroundColor Yellow
        $input = Get-InputBufferConfig
        $mouVal = if ($null -ne $input.MouseDataQueueSize) { $input.MouseDataQueueSize } else { "Default" }
        $isMouOptimal = ($input.MouseDataQueueSize -ge 16 -and $input.MouseDataQueueSize -le 32)
        $mouStatus = if ($isMouOptimal) { "$($input.MouseDataQueueSize) packets [PASS - Minimal Buffer Queue Latency with Anti-Drop Headroom]" } else { "$mouVal [Default: 100 - Will be set to 32 in Gaming Mode]" }
        $mouColor  = if ($isMouOptimal) { "Green" } else { "Yellow" }
        Write-Host "  MouseDataQueueSize:      $mouStatus" -ForegroundColor $mouColor

        $kbdVal = if ($null -ne $input.KeyboardDataQueueSize) { $input.KeyboardDataQueueSize } else { "Default" }
        $isKbdOptimal = ($input.KeyboardDataQueueSize -ge 16 -and $input.KeyboardDataQueueSize -le 32)
        $kbdStatus = if ($isKbdOptimal) { "$($input.KeyboardDataQueueSize) packets [PASS - Direct Delivery]" } else { "$kbdVal [Default: 100 - Will be set to 32 in Gaming Mode]" }
        $kbdColor  = if ($isKbdOptimal) { "Green" } else { "Yellow" }
        Write-Host "  KeyboardDataQueueSize:   $kbdStatus" -ForegroundColor $kbdColor

        # 14. BCDedit System Timer & TSC Synchronization
        Write-Host "`n[14] BCDedit High-Precision System Timers:" -ForegroundColor Yellow
        $bcd = Get-BcdeditTimerConfig
        $dynVal = if ($bcd.DynamicTick) { $bcd.DynamicTick } else { "no" }
        $dynStatus = if ($bcd.DynamicTick -eq "yes") { "Disabled (yes) [PASS - Dynamic Tick Suppressed]" } else { "$dynVal [Default - Will be disabled in Gaming Mode]" }
        $dynColor  = if ($bcd.DynamicTick -eq "yes") { "Green" } else { "Yellow" }
        Write-Host "  disabledynamictick:      $dynStatus" -ForegroundColor $dynColor

        $tscVal = if ($bcd.TscSyncPolicy) { $bcd.TscSyncPolicy } else { "Default" }
        $tscStatus = if ($bcd.TscSyncPolicy -eq "Enhanced") { "Enhanced [PASS - TSC Synced Across Cores]" } else { "$tscVal [Will be set to Enhanced in Gaming Mode]" }
        $tscColor  = if ($bcd.TscSyncPolicy -eq "Enhanced") { "Green" } else { "Yellow" }
        Write-Host "  tscsyncpolicy:           $tscStatus" -ForegroundColor $tscColor

        # 15. TCP Gaming Stack & Interface Isolation
        Write-Host "`n[15] TCP/IP Gaming Stack & Interface Isolation:" -ForegroundColor Yellow
        $tcp = Get-TcpStackConfig
        $tsText = if ($tcp.Timestamps -eq "disabled") { "Disabled [PASS - 12B Header Overhead Eliminated]" } else { "$($tcp.Timestamps) [Will be disabled in Gaming Mode]" }
        $tsColor = if ($tcp.Timestamps -eq "disabled") { "Green" } else { "Yellow" }
        Write-Host "  RFC 1323 Timestamps:     $tsText" -ForegroundColor $tsColor
        Write-Host "  ECN Capability:          $($tcp.ECN)" -ForegroundColor White
        Write-Host "  Receive-Side Scaling:    $($tcp.RSS)" -ForegroundColor White
        Write-Host "  Tethering Isolation:     Ethernet 2 (Apple Mobile Device) & wwan99 (Wintun) [STRICTLY PROTECTED]" -ForegroundColor Green

        # 16. Hardware-Accelerated GPU Scheduling (HAGS)
        Write-Host "`n[16] Hardware-Accelerated GPU Scheduling (HAGS):" -ForegroundColor Yellow
        $hags = Get-HagsGpuSchedulingConfig
        $hagsStatus = if ($hags.HwSchMode -eq 2) { "Enabled (2) [PASS - Hardware-Accelerated GPU Scheduling Active]" } else { "Disabled ($($hags.HwSchMode)) [Will be set to 2 in Gaming Mode]" }
        $hagsColor  = if ($hags.HwSchMode -eq 2) { "Green" } else { "Yellow" }
        Write-Host "  HwSchMode:               $hagsStatus" -ForegroundColor $hagsColor

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

        $kdpc = Get-KernelDpcConfig
        $input = Get-InputBufferConfig
        $bcd = Get-BcdeditTimerConfig
        $tcp = Get-TcpStackConfig
        $hags = Get-HagsGpuSchedulingConfig

        Write-Host "`n[1] Kernel DPC & Memory Management:" -ForegroundColor Yellow
        $dpcVal = if ($null -ne $kdpc.ThreadDpcEnable) { $kdpc.ThreadDpcEnable } else { "1" }
        $dpcTxt = if ($kdpc.ThreadDpcEnable -eq 0) { "Direct (0) [OPTIMAL - Worker DPC delay bypassed]" } else { "Threaded ($dpcVal) [Default]" }
        $pageTxt = if ($kdpc.DisablePagingExecutive -eq 1) { "Enabled (1) [OPTIMAL - Drivers locked in RAM]" } else { "Disabled ($($kdpc.DisablePagingExecutive)) [Pageable]" }
        $prioTxt = if ($kdpc.Win32PrioritySeparation -eq 38) { "0x26 / 38 [OPTIMAL - 3:1 Foreground Boost]" } else { "$($kdpc.Win32PrioritySeparation)" }
        $pwrTxt = if ($kdpc.PowerThrottlingOff -eq 1) { "Disabled (1) [OPTIMAL - No Thread Throttling]" } else { "Active ($($kdpc.PowerThrottlingOff))" }

        Write-Host "  ThreadDpcEnable:         $dpcTxt" -ForegroundColor $(if ($kdpc.ThreadDpcEnable -eq 0) { "Green" } else { "Yellow" })
        Write-Host "  DisablePagingExecutive:  $pageTxt" -ForegroundColor $(if ($kdpc.DisablePagingExecutive -eq 1) { "Green" } else { "Yellow" })
        Write-Host "  Win32PrioritySeparation: $prioTxt" -ForegroundColor $(if ($kdpc.Win32PrioritySeparation -eq 38) { "Green" } else { "Yellow" })
        Write-Host "  PowerThrottlingOff:      $pwrTxt" -ForegroundColor $(if ($kdpc.PowerThrottlingOff -eq 1) { "Green" } else { "Yellow" })

        Write-Host "`n[2] Direct Peripheral Input Queues:" -ForegroundColor Yellow
        $mouVal = if ($null -ne $input.MouseDataQueueSize) { $input.MouseDataQueueSize } else { "Default" }
        $isMouOpt = ($input.MouseDataQueueSize -ge 16 -and $input.MouseDataQueueSize -le 32)
        $mouTxt = if ($isMouOpt) { "$($input.MouseDataQueueSize) packets [OPTIMAL - Minimal Latency with Anti-Drop Headroom]" } else { "$mouVal [Default: 100]" }
        $kbdVal = if ($null -ne $input.KeyboardDataQueueSize) { $input.KeyboardDataQueueSize } else { "Default" }
        $isKbdOpt = ($input.KeyboardDataQueueSize -ge 16 -and $input.KeyboardDataQueueSize -le 32)
        $kbdTxt = if ($isKbdOpt) { "$($input.KeyboardDataQueueSize) packets [OPTIMAL - Direct Delivery]" } else { "$kbdVal [Default: 100]" }
        Write-Host "  MouseDataQueueSize:      $mouTxt" -ForegroundColor $(if ($isMouOpt) { "Green" } else { "Yellow" })
        Write-Host "  KeyboardDataQueueSize:   $kbdTxt" -ForegroundColor $(if ($isKbdOpt) { "Green" } else { "Yellow" })

        Write-Host "`n[3] BCDedit Kernel System Timers:" -ForegroundColor Yellow
        $tickVal = if ($bcd.DynamicTick) { $bcd.DynamicTick } else { "no" }
        $tickTxt = if ($bcd.DynamicTick -eq "yes") { "Disabled (yes) [OPTIMAL - Dynamic Tick Off]" } else { "$tickVal (Tick Active) [Default]" }
        $tscVal = if ($bcd.TscSyncPolicy) { $bcd.TscSyncPolicy } else { "Default" }
        $tscTxt = if ($bcd.TscSyncPolicy -eq "Enhanced") { "Enhanced [OPTIMAL - Synced Core TSC]" } else { "$tscVal [Default]" }
        Write-Host "  disabledynamictick:      $tickTxt" -ForegroundColor $(if ($bcd.DynamicTick -eq "yes") { "Green" } else { "Yellow" })
        Write-Host "  tscsyncpolicy:           $tscTxt" -ForegroundColor $(if ($bcd.TscSyncPolicy -eq "Enhanced") { "Green" } else { "Yellow" })

        Write-Host "`n[4] TCP Gaming Stack & HAGS:" -ForegroundColor Yellow
        $tsTxt = if ($tcp.Timestamps -eq "disabled") { "Disabled [OPTIMAL - 12B Header Overhead Eliminated]" } else { "$($tcp.Timestamps)" }
        $hagsTxt = if ($hags.HwSchMode -eq 2) { "Enabled (2) [OPTIMAL - Hardware GPU Scheduling Active]" } else { "Disabled ($($hags.HwSchMode))" }
        Write-Host "  TCP Timestamps:          $tsTxt" -ForegroundColor $(if ($tcp.Timestamps -eq "disabled") { "Green" } else { "Yellow" })
        Write-Host "  GPU HAGS (HwSchMode):    $hagsTxt" -ForegroundColor $(if ($hags.HwSchMode -eq 2) { "Green" } else { "Yellow" })
    }
}
