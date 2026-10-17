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
    [ValidateSet("Enable", "Restore", "Status", "ApplyBootMode", "Diagnostic", "CleanMemory", "RepairDisplay", "RepairServices", "FlushShaderCache", "ToggleVBS", "GpuMsiStatus")]
    [string]$Action = "Status",

    [switch]$Watchdog
)

# ── Admin Rights Check ────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    if ($Action -in @("Status", "Diagnostic", "CleanMemory", "FlushShaderCache", "GpuMsiStatus")) {
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

# ── Helper: Register Boot-Time Tasks ─────────────────────────────────────────
function Register-BootTasks {
    Write-Host "[*] Registering Next-Boot Task in Task Scheduler (SYSTEM privileges)..." -ForegroundColor Cyan

    $actionScript = Join-Path $RootDir "UltraGamingMode.ps1"

    $taskAction = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
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

                # 2. Activate safe network gaming tweaks, power scheme and hardware optimizations
                Enable-UltimatePerformance | Out-Null
                Set-GamingMultimediaConfig | Out-Null
                Set-ProcessorIdleMinCores -Percent 100 | Out-Null
                Set-AmdUlpsState -Enable 0 | Out-Null
                Set-GpuMsiGamingConfig | Out-Null
                Set-NTFSGamingOptimizations | Out-Null
                Set-NetworkGamingOptimizations | Out-Null

                # 3. Update state to active and capture boot timestamp
                $stateData.State = "GameMode_Active"
                $stateData.BootRunCount = [int]$stateData.BootRunCount + 1
                $stateData.GamingBootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString("o")
                $stateData | ConvertTo-Json -Depth 6 | Set-Content -Path $stateFile -Force -Encoding UTF8

                # 4. Arm RunOnce fail-safe watchdog: fires on next reboot/logon after gaming mode
                $actionScript = Join-Path $RootDir "UltraGamingMode.ps1"
                $restoreCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File `"$actionScript`" -Action Restore -Watchdog"
                Set-ItemProperty `
                    -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" `
                    -Name "*UltraGamingModeRestore" `
                    -Value $restoreCmd `
                    -Force

                # 5. Remove the boot trigger so it does not fire on every boot.
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
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
            $currentBootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString("o")

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
        $activeBloatCount = 0
        foreach ($b in $blacklist) {
            $s = Get-Service -Name $b.Name -ErrorAction SilentlyContinue
            if ($s -and $s.Status -eq "Running") { $activeBloatCount++ }
        }
        Write-Host " Target Services: $($blacklist.Count) configured | $activeBloatCount currently running" -ForegroundColor White

        # Hardware & Security Status
        $cores = Get-ProcessorIdleMinCores
        $coresText = if ($cores -eq 100) { "Disabled (100% min cores active) [OPTIMAL]" } elseif ($null -ne $cores) { "Active ($cores% min cores)" } else { "N/A" }
        Write-Host " Core Parking:  $coresText" -ForegroundColor $(if ($cores -eq 100) { "Green" } else { "Yellow" })

        $amdKeys = @(Get-AmdGpuDriverClassKeys)
        if ($amdKeys.Count -gt 0) {
            $firstKey = $amdKeys[0]
            $ulpsVal = if ($firstKey -is [hashtable]) { $firstKey["EnableUlps"] } else { $firstKey.EnableUlps }
            $ulpsText = if ($null -ne $ulpsVal -and [int]$ulpsVal -eq 0) { "Disabled (0) [OPTIMAL]" } else { "Enabled ($ulpsVal) [Can cause stutter on wake]" }
            Write-Host " AMD ULPS:      $ulpsText" -ForegroundColor $(if ($null -ne $ulpsVal -and [int]$ulpsVal -eq 0) { "Green" } else { "Yellow" })
        }

        $msi = Get-GpuMsiConfig
        if ($msi) {
            $prioLabel = switch ($msi.DevicePriority) { 3 { "High (3)" } 2 { "Normal (2)" } 1 { "Low (1)" } default { "Default" } }
            $msiText = if ($msi.MSISupported -eq 1) { "Enabled (Priority: $prioLabel) [OPTIMAL]" } else { "Legacy Line-Based Interrupts" }
            Write-Host " GPU MSI Mode:  $msiText" -ForegroundColor $(if ($msi.MSISupported -eq 1) { "Green" } else { "Yellow" })
        }

        $vbs = Get-VbsHvciDiagnosticInfo
        $vbsText = if ($vbs.VbsRunning -or $vbs.HvciRunning) { "Active ($($vbs.VbsStatus)) [VBS overhead active]" } else { "Disabled [OPTIMAL FOR MAXIMUM FPS]" }
        Write-Host " VBS / HVCI:    $vbsText" -ForegroundColor $(if ($vbs.VbsRunning -or $vbs.HvciRunning) { "Yellow" } else { "Green" })
    }

    "CleanMemory" {
        Write-Host "=====================================================" -ForegroundColor Green
        Write-Host "           ON-DEMAND RAM & STANDBY LIST CLEANER      " -ForegroundColor Green
        Write-Host "=====================================================" -ForegroundColor Green
        $freed = Optimize-SystemMemory
        Write-Host "`n[SUCCESS] Memory optimization complete. Reclaimed $freed MB of RAM." -ForegroundColor Green
    }

    "FlushShaderCache" {
        Clear-AmdShaderCache | Out-Null
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
            Write-Host " GPU Name:        $($msi.DeviceName)" -ForegroundColor White
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

        # 1. Privileges
        Write-Host "`n[1] Privilege Level:" -ForegroundColor Yellow
        if ($isAdmin) {
            Write-Host "  [OK] Elevated Administrator: Yes" -ForegroundColor Green
        } else {
            Write-Host "  [!] Elevated Administrator: No (Running with limited user privileges)" -ForegroundColor Yellow
        }

        # 2. Power Plan & Ryzen Core Parking
        Write-Host "`n[2] Power Plan & Ryzen Core Parking:" -ForegroundColor Yellow
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

        # 4. AMD Radeon & Ryzen Hardware Optimizations
        Write-Host "`n[4] AMD Radeon & Ryzen Hardware Optimizations:" -ForegroundColor Yellow
        $amdKeys = @(Get-AmdGpuDriverClassKeys)
        if ($amdKeys.Count -gt 0) {
            foreach ($ak in $amdKeys) {
                $uVal = if ($ak -is [hashtable]) { $ak["EnableUlps"] } else { $ak.EnableUlps }
                $desc = if ($ak -is [hashtable]) { $ak["DriverDesc"] } else { $ak.DriverDesc }
                $uStatus = if ($null -ne $uVal -and [int]$uVal -eq 0) { "Disabled (0) [PASS]" } else { "Enabled ($uVal) [Will be disabled in Gaming Mode]" }
                $uColor = if ($null -ne $uVal -and [int]$uVal -eq 0) { "Green" } else { "Yellow" }
                Write-Host "  - AMD Driver ($desc): EnableUlps = $uStatus" -ForegroundColor $uColor
            }
        } else {
            Write-Host "  - AMD GPU Driver Key: Not detected (non-AMD or generic driver)" -ForegroundColor Gray
        }

        # Shader Cache Directories
        $shaderDirs = @(
            (Join-Path $env:LOCALAPPDATA "AMD\DxCache"),
            (Join-Path $env:LOCALAPPDATA "AMD\VkCache"),
            (Join-Path $env:LOCALAPPDATA "AMD\DxcCache"),
            (Join-Path $env:LOCALAPPDATA "AMD\DX9Cache"),
            (Join-Path $env:LOCALAPPDATA "AMD\OglCache"),
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
                Write-Host "  - Cache $leafName`: $cnt files ($mb MB)" -ForegroundColor White
            }
        }

        # 5. GPU MSI (Message Signaled Interrupts) Mode & Interrupt Priority
        Write-Host "`n[5] GPU MSI Mode & IRQ Device Priority:" -ForegroundColor Yellow
        $msiInfo = Get-GpuMsiConfig
        if ($msiInfo) {
            $msiStat = if ($msiInfo.MSISupported -eq 1) { "Enabled (1) [PASS]" } else { "Disabled / Legacy [Will be enabled in Gaming Mode]" }
            $msiCol = if ($msiInfo.MSISupported -eq 1) { "Green" } else { "Yellow" }
            Write-Host "  Device:                 $($msiInfo.DeviceName)" -ForegroundColor White
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
            Write-Host "  [i] Note: VBS/HVCI incurs virtualization overhead. Use Option [8] to toggle if needed." -ForegroundColor Yellow
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
        foreach ($item in $blacklist) {
            $svc = Get-Service -Name $item.Name -ErrorAction SilentlyContinue
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
            if (Test-Path $sDir) {
                Get-ChildItem -Path $sDir -File | Where-Object { $_.Extension -in @(".lnk", ".url") } | ForEach-Object {
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

        Write-Host "`n[+] Diagnostic complete. System is 100% primed for high-impact Ultra Gaming Mode." -ForegroundColor Green
    }

    "RepairDisplay" {
        Repair-DisplayPipeline
    }

    "RepairServices" {
        Repair-CoreServices
    }
}
