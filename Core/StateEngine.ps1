<#
.SYNOPSIS
    Manages system state snapshots, JSON persistence, and aggressive state transitions for Ultra Gaming Mode.
.DESCRIPTION
    Creates timestamped backup snapshots of service configurations, startup apps, UWP AppModel tasks,
    visual/DWM effects, telemetry tasks, AMD hardware settings, MSI IRQ configuration, NTFS options,
    network adapter properties, and restores them cleanly when exiting Gaming Mode.
#>

# Resolve the Backups directory relative to the project root
$Script:BackupDir = Join-Path -Path $PSScriptRoot -ChildPath "..\Backups"
if (-not (Test-Path $Script:BackupDir)) {
    New-Item -ItemType Directory -Path $Script:BackupDir -Force | Out-Null
}
$Script:ActiveStateFile = Join-Path -Path $Script:BackupDir -ChildPath "active_state.json"

function Get-ActiveStateSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path = $Script:ActiveStateFile
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    for ($i = 0; $i -lt 5; $i++) {
        try {
            return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
        } catch {
            Start-Sleep -Milliseconds 100
        }
    }
    return $null
}

function Set-ActiveStateSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path = $Script:ActiveStateFile,

        [Parameter(Mandatory = $true)]
        [object]$Data
    )

    for ($i = 0; $i -lt 5; $i++) {
        try {
            $Data | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path -Force -Encoding UTF8
            return $true
        } catch {
            Start-Sleep -Milliseconds 100
        }
    }
    return $false
}

# Load optimizer module with include guard
if (-not (Get-Command Get-HardwareProfile -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "SystemOptimizer.ps1")
}

function Stop-BlacklistedProcesses {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ProcessNames
    )

    foreach ($name in $ProcessNames) {
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
        if ($procs) {
            foreach ($p in $procs) {
                try {
                    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                    Write-Host "  [x] Terminated running bloat process: $name (PID: $($p.Id))" -ForegroundColor Yellow
                }
                catch {
                    Write-Verbose "Could not terminate process $($p.Id): $($_.Exception.Message)"
                }
            }
        }
    }
}

function New-SystemStateBackup {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$BlacklistConfig,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Whitelist,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$StartupConfig
    )

    Write-Host "`n[*] Creating pre-gaming system snapshot..." -ForegroundColor Cyan

    $transparencyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    $origTransparency = 1
    if (Test-Path $transparencyPath) {
        $val = (Get-ItemProperty -Path $transparencyPath -Name "EnableTransparency" -ErrorAction SilentlyContinue).EnableTransparency
        if ($null -ne $val) { $origTransparency = [int]$val }
    }

    $metricsPath = "HKCU:\Control Panel\Desktop\WindowMetrics"
    $origMinAnimate = "1"
    if (Test-Path $metricsPath) {
        $val = (Get-ItemProperty -Path $metricsPath -Name "MinAnimate" -ErrorAction SilentlyContinue).MinAnimate
        if ($null -ne $val) { $origMinAnimate = [string]$val }
    }

    $hwProfile = Get-HardwareProfile

    $snapshot = @{
        Version                  = "2.6"
        Timestamp                = (Get-Date).ToString("o")
        State                    = "Armed"
        BootRunCount             = 0
        SessionLogonHandled      = $false
        UserSessionHandled       = $false
        SystemSessionHandled     = $false
        SystemRestored           = $false
        UserRestored             = $false
        HardwareProfile          = $hwProfile
        PowerScheme              = (Get-ActivePowerSchemeGuid)
        MultimediaConfig         = (Get-MultimediaGamingConfig)
        VisualConfig             = @{
            EnableTransparency = $origTransparency
            MinAnimate         = $origMinAnimate
        }
        Services                 = @()
        StartupItems             = @()
        StartupShortcuts         = @()
        AppModelStartupTasks     = @()
        ScheduledTasks           = @()
        NetworkLatencyConfig     = @()
        NetworkAdapterProperties = @()
        GameDVRConfig            = @{}
        CoreParkingMinCores      = $null
        ProcessorThrottleMin     = (Get-ProcessorThrottleMin)
        UlpsConfig               = @()
        MSIConfig                = $null
        NTFSConfig               = $null
        KernelDpcConfig          = $null
        InputBufferConfig        = $null
        BcdeditConfig            = $null
        TcpStackConfig           = $null
        HagsConfig               = $null
    }

    # 1. Services Snapshot
    foreach ($item in $BlacklistConfig) {
        $sName = $item.Name
        # Skip whitelisted services entirely
        if ($Whitelist -contains $sName) { continue }

        $svc = Get-Service -Name $sName -ErrorAction SilentlyContinue
        if ($svc) {
            $wmiSvc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$sName'" -ErrorAction SilentlyContinue
            $startMode = if ($wmiSvc) { $wmiSvc.StartMode } else { "Manual" }

            $snapshot.Services += @{
                Name                = $sName
                DisplayName         = $svc.DisplayName
                OriginalStartupType = $startMode
                OriginalStatus      = $svc.Status.ToString()
            }
        }
    }

    # 2. HKCU & HKLM Run Registry Items Snapshot
    $runHives = @(
        @{ Scope = "HKCU"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" },
        @{ Scope = "HKLM"; Path = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" }
    )
    foreach ($hive in $runHives) {
        if (Test-Path $hive.Path) {
            $props = Get-ItemProperty -Path $hive.Path
            $props.PSObject.Properties | Where-Object {
                $_.Name -notmatch '^(PS(Path|ParentPath|ChildName|Drive|Provider))$'
            } | ForEach-Object {
                $snapshot.StartupItems += @{
                    Name  = $_.Name
                    Value = $_.Value
                    Scope = $hive.Scope
                }
            }
        }
    }

    # 3. Startup Folder Shortcuts (.lnk / .url) Snapshot
    $quarantineDir = Join-Path $Script:BackupDir "QuarantinedShortcuts"
    $userQuarantineDir = Join-Path $quarantineDir "User"
    $commonQuarantineDir = Join-Path $quarantineDir "ProgramData"
    if (-not (Test-Path -LiteralPath $userQuarantineDir)) { New-Item -ItemType Directory -Path $userQuarantineDir -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $commonQuarantineDir)) { New-Item -ItemType Directory -Path $commonQuarantineDir -Force | Out-Null }

    $startupDirs = @(
        @{ Dir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Target = $userQuarantineDir; Tag = "User" },
        @{ Dir = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"; Target = $commonQuarantineDir; Tag = "ProgramData" }
    )
    foreach ($sd in $startupDirs) {
        $sDir = $sd.Dir
        $qTarget = $sd.Target
        if (Test-Path -LiteralPath $sDir) {
            Get-ChildItem -LiteralPath $sDir -File -Force | Where-Object { $_.Extension -in @(".lnk", ".url", ".ugm_backup") } | ForEach-Object {
                $cleanName = $_.Name -replace '\.ugm_backup$', ''
                $snapshot.StartupShortcuts += @{
                    Name           = $cleanName
                    FolderTag      = $sd.Tag
                    OriginalFolder = $sDir
                    OriginalPath   = Join-Path $sDir $cleanName
                    QuarantinePath = Join-Path $qTarget $cleanName
                }
            }
        }
    }

    # 4. UWP AppModel Startup Tasks Snapshot (TranslucentTB, etc.)
    $uwpRoot = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData"
    if (Test-Path $uwpRoot) {
        Get-ChildItem -Path $uwpRoot | ForEach-Object {
            $pkg = $_
            if ($pkg.PSChildName -like "*Apple*") { return }

            Get-ChildItem -Path $pkg.PSPath -ErrorAction SilentlyContinue | ForEach-Object {
                $task = $_
                if ($task.PSChildName -like "*Apple*") { return }

                $props = Get-ItemProperty -Path $task.PSPath -ErrorAction SilentlyContinue
                if ($null -ne $props -and $props.PSObject.Properties["State"]) {
                    $curState = [int]$props.State
                    if ($curState -eq 2) { # 2 = Enabled
                        $snapshot.AppModelStartupTasks += @{
                            Package       = $pkg.PSChildName
                            TaskId        = $task.PSChildName
                            RegistryPath  = $task.PSPath
                            OriginalState = $curState
                        }
                    }
                }
            }
        }
    }

    # 5. Telemetry & Maintenance Scheduled Tasks Snapshot
    $tasksToSnapshot = @(
        @{ Name = "MapsToastTask"; Path = "\Microsoft\Windows\Maps\" },
        @{ Name = "ShowFeedbackToast"; Path = "\Microsoft\Windows\Feedback\Siuf\" },
        @{ Name = "SustainabilityTelemetry"; Path = "\Microsoft\Windows\Customer Experience Improvement Program\" }
    )
    if ($hwProfile.HddProfile) {
        $tasksToSnapshot += @{ Name = "ScheduledDefrag"; Path = "\Microsoft\Windows\Defrag\" }
    }
    foreach ($tItem in $tasksToSnapshot) {
        $task = if ($tItem.Path) {
            Get-ScheduledTask -TaskPath $tItem.Path -TaskName $tItem.Name -ErrorAction SilentlyContinue
        } else {
            Get-ScheduledTask -TaskName $tItem.Name -ErrorAction SilentlyContinue
        }
        if ($task -and $task.State -ne "Disabled") {
            $snapshot.ScheduledTasks += @{
                TaskName      = $tItem.Name
                TaskPath      = $task.TaskPath
                OriginalState = $task.State.ToString()
            }
        }
    }

    # 6. Network Latency Interfaces Snapshot
    $interfacesPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    if (Test-Path $interfacesPath) {
        Get-ChildItem -Path $interfacesPath | ForEach-Object {
            $props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
            if ($props.DhcpIPAddress -or $props.IPAddress) {
                $snapshot.NetworkLatencyConfig += @{
                    Guid            = $_.PSChildName
                    TcpAckFrequency = $props.TcpAckFrequency
                    TCPNoDelay      = $props.TCPNoDelay
                }
            }
        }
    }

    # 7. Physical Network Adapters Advanced Gaming Properties Snapshot
    $snapshot.NetworkAdapterProperties = @(Get-NetworkAdapterGamingProperties)

    # 8. GameDVR Snapshot
    $gameDvrPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR"
    if (Test-Path $gameDvrPath) {
        $props = Get-ItemProperty -Path $gameDvrPath -ErrorAction SilentlyContinue
        $snapshot.GameDVRConfig["AppCaptureEnabled"] = $props.AppCaptureEnabled
    }
    $configStorePath = "HKCU:\System\GameConfigStore"
    if (Test-Path $configStorePath) {
        $props = Get-ItemProperty -Path $configStorePath -ErrorAction SilentlyContinue
        $snapshot.GameDVRConfig["GameDVR_Enabled"] = $props.GameDVR_Enabled
        $snapshot.GameDVRConfig["GameDVR_FSEBehaviorMode"] = $props.GameDVR_FSEBehaviorMode
    }
    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
    if (Test-Path $policyPath) {
        $snapshot.GameDVRConfig["AllowGameDVR"] = (Get-ItemProperty -Path $policyPath -Name "AllowGameDVR" -ErrorAction SilentlyContinue).AllowGameDVR
    }

    # 9. Ryzen Core Parking Snapshot
    $snapshot.CoreParkingMinCores = Get-ProcessorIdleMinCores

    # 10. AMD ULPS Snapshot
    $snapshot.UlpsConfig = @(Get-AmdGpuDriverClassKeys)

    # 11. GPU MSI & Device Priority Snapshot
    $snapshot.MSIConfig = Get-GpuMsiConfig

    # 12. NTFS File System I/O Snapshot
    $snapshot.NTFSConfig = Get-NTFSFileSystemConfig

    # 13. Kernel DPC & Memory Management Snapshot
    $snapshot.KernelDpcConfig = Get-KernelDpcConfig

    # 14. Input Buffer Queues Snapshot
    $snapshot.InputBufferConfig = Get-InputBufferConfig

    # 15. BCDedit System Timer Snapshot
    $snapshot.BcdeditConfig = Get-BcdeditTimerConfig

    # 16. TCP/IP Gaming Stack Snapshot
    $snapshot.TcpStackConfig = Get-TcpStackConfig

    # 17. HAGS GPU Scheduling Snapshot
    $snapshot.HagsConfig = Get-HagsGpuSchedulingConfig

    # Write snapshot to disk
    $snapshot | ConvertTo-Json -Depth 6 | Set-Content -Path $Script:ActiveStateFile -Force -Encoding UTF8
    Write-Host "[+] Snapshot securely saved to '$Script:ActiveStateFile'." -ForegroundColor Green
    return $Script:ActiveStateFile
}

function Disable-UserStateAggressive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$StartupConfig
    )

    Write-Host "`n[*] Suppressing user-level startup applications and visual bloat..." -ForegroundColor Cyan

    $protectedStartup = $StartupConfig.ProtectedStartupNames

    # 1. Suppress HKCU / HKLM Run items (preserving only protected items like ctfmon, AMDNoiseSuppression)
    $runHives = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
    )
    foreach ($regPath in $runHives) {
        if (-not (Test-Path $regPath)) { continue }
        $props = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        if (-not $props) { continue }

        $props.PSObject.Properties | Where-Object {
            $_.Name -notmatch '^(PS(Path|ParentPath|ChildName|Drive|Provider))$'
        } | ForEach-Object {
            $propName = $_.Name
            $isProtected = $false
            foreach ($prot in $protectedStartup) {
                if ($propName -like "*$prot*") { $isProtected = $true; break }
            }
            if (-not $isProtected) {
                Remove-ItemProperty -Path $regPath -Name $propName -ErrorAction SilentlyContinue
                Write-Host "  [x] Removed startup entry: $propName" -ForegroundColor Yellow
            }
            else {
                Write-Host "  [v] Retained protected startup entry: $propName" -ForegroundColor Green
            }
        }
    }

    # 2. Quarantine Startup folder shortcuts (Move completely out of Startup folder to eliminate "Open With .ugm" dialogs)
    $quarantineDir = Join-Path $Script:BackupDir "QuarantinedShortcuts"
    $userQuarantineDir = Join-Path $quarantineDir "User"
    $commonQuarantineDir = Join-Path $quarantineDir "ProgramData"
    if (-not (Test-Path -LiteralPath $userQuarantineDir)) { New-Item -ItemType Directory -Path $userQuarantineDir -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $commonQuarantineDir)) { New-Item -ItemType Directory -Path $commonQuarantineDir -Force | Out-Null }

    $startupDirs = @(
        @{ Dir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Target = $userQuarantineDir },
        @{ Dir = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"; Target = $commonQuarantineDir }
    )
    foreach ($sd in $startupDirs) {
        $sDir = $sd.Dir
        $qTarget = $sd.Target
        if (Test-Path -LiteralPath $sDir) {
            Get-ChildItem -LiteralPath $sDir -File -Force | Where-Object { $_.Extension -in @(".lnk", ".url", ".ugm_backup") } | ForEach-Object {
                $cleanName = $_.Name -replace '\.ugm_backup$', ''
                $destPath = Join-Path $qTarget $cleanName
                Move-Item -LiteralPath $_.FullName -Destination $destPath -Force -ErrorAction SilentlyContinue
                Write-Host "  [x] Quarantined startup shortcut: $cleanName ($($sd.Target | Split-Path -Leaf))" -ForegroundColor Yellow
            }
        }
    }

    # 3. Suppress UWP AppModel Startup Tasks (TranslucentTB, etc.)
    $uwpRoot = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData"
    if (Test-Path $uwpRoot) {
        Get-ChildItem -Path $uwpRoot | ForEach-Object {
            $pkg = $_
            if ($pkg.PSChildName -like "*Apple*") { return }

            Get-ChildItem -Path $pkg.PSPath -ErrorAction SilentlyContinue | ForEach-Object {
                $task = $_
                if ($task.PSChildName -like "*Apple*") { return }

                $props = Get-ItemProperty -Path $task.PSPath -ErrorAction SilentlyContinue
                if ($null -ne $props -and $props.PSObject.Properties["State"]) {
                    if ([int]$props.State -eq 2) {
                        # 1 = Disabled by user in Windows Task Manager / Settings
                        Set-ItemProperty -Path $task.PSPath -Name "State" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                        Write-Host "  [x] Disabled UWP AppModel startup task: $($task.PSChildName)" -ForegroundColor Yellow
                    }
                }
            }
        }
    }

    # 4. Disable Desktop DWM Transparency & Minimize Animations
    $transparencyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    if (Test-Path $transparencyPath) {
        Set-ItemProperty -Path $transparencyPath -Name "EnableTransparency" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Host "  [+] DWM transparency disabled for minimum compositor latency." -ForegroundColor Green
    }

    $metricsPath = "HKCU:\Control Panel\Desktop\WindowMetrics"
    if (Test-Path $metricsPath) {
        Set-ItemProperty -Path $metricsPath -Name "MinAnimate" -Value "0" -Type String -Force -ErrorAction SilentlyContinue
        Write-Host "  [+] Window animation latency disabled." -ForegroundColor Green
    }

    # 5. Disable Telemetry & Scheduled Maintenance Tasks (suspend defrag on HDD)
    $hw = Get-HardwareProfile
    $tasksToDisable = @(
        @{ Name = "MapsToastTask"; Path = "\Microsoft\Windows\Maps\" },
        @{ Name = "ShowFeedbackToast"; Path = "\Microsoft\Windows\Feedback\Siuf\" },
        @{ Name = "SustainabilityTelemetry"; Path = "\Microsoft\Windows\Customer Experience Improvement Program\" }
    )
    if ($hw.HddProfile) {
        $tasksToDisable += @{ Name = "ScheduledDefrag"; Path = "\Microsoft\Windows\Defrag\" }
    }
    foreach ($t in $tasksToDisable) {
        $task = if ($t.Path) {
            Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue
        } else {
            Get-ScheduledTask -TaskName $t.Name -ErrorAction SilentlyContinue
        }
        if ($task -and $task.State -ne "Disabled") {
            if ($t.Path) {
                Disable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue | Out-Null
            } else {
                Disable-ScheduledTask -TaskName $t.Name -ErrorAction SilentlyContinue | Out-Null
            }
            if ($t.Name -eq "ScheduledDefrag") {
                Write-Host "  [x] HDD Protection: Suspended ScheduledDefrag background task (eliminates 100% disk freeze)." -ForegroundColor Yellow
            } else {
                Write-Host "  [x] Disabled telemetry task: $($t.Name)" -ForegroundColor Yellow
            }
        }
    }

    # If HDD Profile is active, strictly terminate SysMain & WSearch immediately
    if ($hw.HddProfile) {
        Write-Host "  [*] HDD Profile Active: Enforcing disk thrash suppression..." -ForegroundColor Cyan
        foreach ($sName in @("SysMain", "WSearch")) {
            $svc = Get-Service -Name $sName -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq "Running") {
                try {
                    Stop-Service -Name $sName -Force -ErrorAction SilentlyContinue
                    Write-Host "  [x] Stopped disk-thrashing service: $sName (HDD Protection)." -ForegroundColor Yellow
                } catch {
                    Write-Verbose "Could not stop service $sName`: $($_.Exception.Message)"
                }
            }
        }
    }

    # If LowRamProfile, warn if pagefile missing and run aggressive memory trim
    if ($hw.LowRamProfile) {
        if ($hw.PagefileWarning) {
            Write-Host "  [!] Low-RAM Guard Warning: $($hw.PagefileWarning)" -ForegroundColor Red
        }
        Optimize-SystemMemory -Aggressive | Out-Null
    }

    # 6. Terminate Running Bloat Processes Immediately
    if ($StartupConfig.BlacklistProcesses) {
        Stop-BlacklistedProcesses -ProcessNames $StartupConfig.BlacklistProcesses
    }

    # 7. Apply Deep GameDVR and Ultra Low Latency Network (TCPNoDelay, FlowControl=0, InterruptModeration=0)
    Set-DeepGameDVROptimizations | Out-Null
    Set-NetworkGamingOptimizations | Out-Null

    # 8. Apply Defender, Widgets & Focus Assist optimizations
    Set-DefenderGamingState -Disable $true | Out-Null
    Set-WindowsWidgetsAndSearchGamingState -Disable $true | Out-Null
    Set-FocusAssistAndSoundsGamingState -EnableFocusAssist $true | Out-Null

    # 9. Apply Adaptive CPU, GPU & NTFS Optimizations
    Apply-CpuGamingOptimizations -HardwareProfile $hw | Out-Null
    Apply-GpuGamingOptimizations -HardwareProfile $hw | Out-Null
    Set-NTFSGamingOptimizations -IsHdd:$hw.HddProfile | Out-Null

    # 10. Apply Low-Latency Kernel DPC, Input Buffer Queues, Timers & HAGS (takes effect on reboot)
    Set-KernelDpcOptimizations -IsLowRam:$hw.LowRamProfile | Out-Null
    Set-InputBufferOptimizations | Out-Null
    Set-BcdeditTimerOptimizations | Out-Null
    Set-HagsGpuScheduling | Out-Null

    Write-Host "[+] User startup environment completely stripped and optimized for gaming." -ForegroundColor Green
}

function Restore-QuarantinedShortcuts {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$QuarantineDir = (Join-Path $Script:BackupDir "QuarantinedShortcuts"),

        [Parameter(Mandatory = $false)]
        [string]$UserStartup = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",

        [Parameter(Mandatory = $false)]
        [string]$CommonStartup = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup",

        [Parameter(Mandatory = $false)]
        [PSCustomObject]$StateData = $null,

        [Parameter(Mandatory = $false)]
        [ValidateSet("All", "System", "User")]
        [string]$Scope = "All"
    )

    if (-not (Test-Path -LiteralPath $QuarantineDir)) {
        return
    }

    $userDir = Join-Path $QuarantineDir "User"
    $commonDir = Join-Path $QuarantineDir "ProgramData"

    # 1. Restore segregated User startup shortcuts
    if ($Scope -in @("All", "User") -and (Test-Path -LiteralPath $userDir)) {
        if (-not (Test-Path -LiteralPath $UserStartup)) {
            New-Item -ItemType Directory -Path $UserStartup -Force | Out-Null
        }
        Get-ChildItem -LiteralPath $userDir -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $destName = $_.Name -replace '\.ugm_backup$', ''
            Move-Item -LiteralPath $_.FullName -Destination (Join-Path $UserStartup $destName) -Force -ErrorAction SilentlyContinue
            Write-Host "  [+] Restored user startup shortcut: $destName" -ForegroundColor Green
        }
        $remUser = Get-ChildItem -LiteralPath $userDir -Force -ErrorAction SilentlyContinue
        if (-not $remUser -or $remUser.Count -eq 0) {
            Remove-Item -LiteralPath $userDir -Force -ErrorAction SilentlyContinue
        }
    }

    # 2. Restore segregated Common / ProgramData startup shortcuts
    if ($Scope -in @("All", "System") -and (Test-Path -LiteralPath $commonDir)) {
        if (-not (Test-Path -LiteralPath $CommonStartup)) {
            New-Item -ItemType Directory -Path $CommonStartup -Force | Out-Null
        }
        Get-ChildItem -LiteralPath $commonDir -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $destName = $_.Name -replace '\.ugm_backup$', ''
            Move-Item -LiteralPath $_.FullName -Destination (Join-Path $CommonStartup $destName) -Force -ErrorAction SilentlyContinue
            Write-Host "  [+] Restored common startup shortcut: $destName" -ForegroundColor Green
        }
        $remCommon = Get-ChildItem -LiteralPath $commonDir -Force -ErrorAction SilentlyContinue
        if (-not $remCommon -or $remCommon.Count -eq 0) {
            Remove-Item -LiteralPath $commonDir -Force -ErrorAction SilentlyContinue
        }
    }

    # 3. Restore unsegregated and legacy shortcuts sitting directly in the root of QuarantineDir
    # (e.g. from prior versions or backups like active_state.json)
    $rootFiles = Get-ChildItem -LiteralPath $QuarantineDir -File -Force -ErrorAction SilentlyContinue | Where-Object {
        $_.Extension -in @(".lnk", ".url", ".ugm_backup")
    }
    if ($rootFiles -and $rootFiles.Count -gt 0) {
        Write-Host "  [*] Scanning unsegregated / legacy shortcuts in quarantine root..." -ForegroundColor Cyan
        foreach ($rf in $rootFiles) {
            $cleanName = $rf.Name -replace '\.ugm_backup$', ''
            $destFolder = $UserStartup
            $destScope = "User"

            if ($StateData -and $StateData.StartupShortcuts) {
                $matched = $StateData.StartupShortcuts | Where-Object {
                    $_.Name -eq $cleanName -or
                    $_.Name -eq $rf.Name -or
                    ($_.QuarantinePath -and (($_.QuarantinePath | Split-Path -Leaf) -eq $cleanName -or ($_.QuarantinePath | Split-Path -Leaf) -eq $rf.Name)) -or
                    ($_.OriginalPath -and (($_.OriginalPath | Split-Path -Leaf) -eq $cleanName -or ($_.OriginalPath | Split-Path -Leaf) -eq $rf.Name))
                } | Select-Object -First 1

                if ($matched) {
                    if ($matched.FolderTag -eq "ProgramData" -or ($matched.OriginalFolder -and $matched.OriginalFolder -like "*ProgramData*")) {
                        $destFolder = $CommonStartup
                        $destScope = "System"
                    } elseif ($matched.OriginalFolder) {
                        $destFolder = $matched.OriginalFolder
                        $destScope = "User"
                    }
                }
            }

            if ($Scope -eq "All" -or $Scope -eq $destScope) {
                if (-not (Test-Path -LiteralPath $destFolder)) {
                    New-Item -ItemType Directory -Path $destFolder -Force -ErrorAction SilentlyContinue | Out-Null
                }
                $destPath = Join-Path $destFolder $cleanName
                Move-Item -LiteralPath $rf.FullName -Destination $destPath -Force -ErrorAction SilentlyContinue
                Write-Host "  [+] Restored root quarantined shortcut: $cleanName -> $destFolder" -ForegroundColor Green
            }
        }
    }

    # 4. Clean up any empty subdirectories in QuarantineDir (bottom-up recursion)
    Get-ChildItem -LiteralPath $QuarantineDir -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        Sort-Object -Property FullName -Descending | ForEach-Object {
            $subRemaining = Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            if (-not $subRemaining -or $subRemaining.Count -eq 0) {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }

    # 5. ONLY delete QuarantineDir if it is completely empty
    $rootRemaining = Get-ChildItem -LiteralPath $QuarantineDir -Force -ErrorAction SilentlyContinue
    if (-not $rootRemaining -or $rootRemaining.Count -eq 0) {
        Remove-Item -LiteralPath $QuarantineDir -Force -ErrorAction SilentlyContinue
        Write-Host "  [+] Quarantine directory completely emptied and removed." -ForegroundColor Gray
    } else {
        Write-Verbose "Quarantine directory '$QuarantineDir' contains $($rootRemaining.Count) unhandled item(s). Retained for data safety."
    }
}

function Restore-UserProfileState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [PSCustomObject]$StateData = $null,

        [Parameter(Mandatory = $false)]
        [PSCustomObject]$StartupConfig = $null
    )

    $isSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
    if ($isSystem) {
        Write-Warning "Cannot restore User Profile state under NT AUTHORITY\SYSTEM (HKCU maps to .DEFAULT and APPDATA maps to systemprofile). Must run in interactive user context."
        return $false
    }

    if (-not $StateData) {
        $StateData = Get-ActiveStateSafe
    }

    Write-Host "`n[*] Restoring interactive user profile desktop state..." -ForegroundColor Cyan

    # 1. Restore HKCU Run items
    if ($StateData -and $StateData.StartupItems) {
        Write-Host "  [*] Restoring user registry startup items (HKCU)..." -ForegroundColor Gray
        foreach ($item in $StateData.StartupItems) {
            if ($item.Scope -eq "HKCU") {
                $hive = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
                if (Test-Path -LiteralPath $hive) {
                    Set-ItemProperty -Path $hive -Name $item.Name -Value $item.Value -Force -ErrorAction SilentlyContinue
                    Write-Host "  [+] Restored user startup entry: $($item.Name) [HKCU]" -ForegroundColor Green
                }
            }
        }
    }

    # 2. Restore User Quarantined Startup Shortcuts & Root Quarantined Shortcuts
    $quarantineDir = Join-Path $Script:BackupDir "QuarantinedShortcuts"
    $userStartup = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    Restore-QuarantinedShortcuts -QuarantineDir $quarantineDir -UserStartup $userStartup -StateData $StateData -Scope "User"

    # 3. Clean up legacy *.ugm_backup files in user startup folder
    if (Test-Path -LiteralPath $userStartup) {
        Get-ChildItem -LiteralPath $userStartup -File -Filter "*.ugm_backup" -ErrorAction SilentlyContinue | ForEach-Object {
            $origName = $_.Name -replace '\.ugm_backup$', ''
            Rename-Item -LiteralPath $_.FullName -NewName $origName -Force -ErrorAction SilentlyContinue
            Write-Host "  [+] Restored legacy backup shortcut: $origName" -ForegroundColor Green
        }
    }

    # 4. Restore UWP AppModel Startup Tasks (TranslucentTB, etc.)
    if ($StateData -and $StateData.AppModelStartupTasks) {
        Write-Host "  [*] Restoring UWP AppModel startup tasks (TranslucentTB, etc.)..." -ForegroundColor Gray
        foreach ($uwpEntry in $StateData.AppModelStartupTasks) {
            if ($uwpEntry.RegistryPath -and (Test-Path -LiteralPath $uwpEntry.RegistryPath)) {
                Set-ItemProperty -Path $uwpEntry.RegistryPath -Name "State" -Value $uwpEntry.OriginalState -Type DWord -Force -ErrorAction SilentlyContinue
                Write-Host "  [+] Restored UWP startup task: $($uwpEntry.TaskId) -> State $($uwpEntry.OriginalState)" -ForegroundColor Green
            }
        }
    }

    # 5. Restore Visual / DWM Settings (EnableTransparency, MinAnimate)
    if ($StateData -and $StateData.VisualConfig) {
        Write-Host "  [*] Restoring visual effects & DWM transparency..." -ForegroundColor Gray
        $transparencyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        if (Test-Path -LiteralPath $transparencyPath) {
            Set-ItemProperty -Path $transparencyPath -Name "EnableTransparency" -Value $StateData.VisualConfig.EnableTransparency -Type DWord -Force -ErrorAction SilentlyContinue
        }
        $metricsPath = "HKCU:\Control Panel\Desktop\WindowMetrics"
        if (Test-Path -LiteralPath $metricsPath) {
            Set-ItemProperty -Path $metricsPath -Name "MinAnimate" -Value $StateData.VisualConfig.MinAnimate -Type String -Force -ErrorAction SilentlyContinue
        }
        Write-Host "  [+] Visual transparency & animations restored in user profile." -ForegroundColor Green
    }

    # 6. Restore GameDVR User Settings
    if ($StateData -and $StateData.GameDVRConfig) {
        $gdvr = $StateData.GameDVRConfig
        $gameDvrPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR"
        $configStorePath = "HKCU:\System\GameConfigStore"
        if (-not (Test-Path -LiteralPath $gameDvrPath)) { New-Item -Path $gameDvrPath -Force -ErrorAction SilentlyContinue | Out-Null }
        if (-not (Test-Path -LiteralPath $configStorePath)) { New-Item -Path $configStorePath -Force -ErrorAction SilentlyContinue | Out-Null }
        if ($null -ne $gdvr.AppCaptureEnabled) {
            Set-ItemProperty -Path $gameDvrPath -Name "AppCaptureEnabled" -Value $gdvr.AppCaptureEnabled -Type DWord -Force -ErrorAction SilentlyContinue
        }
        if ($null -ne $gdvr.GameDVR_Enabled) {
            Set-ItemProperty -Path $configStorePath -Name "GameDVR_Enabled" -Value $gdvr.GameDVR_Enabled -Type DWord -Force -ErrorAction SilentlyContinue
        }
        if ($null -ne $gdvr.GameDVR_FSEBehaviorMode) {
            Set-ItemProperty -Path $configStorePath -Name "GameDVR_FSEBehaviorMode" -Value $gdvr.GameDVR_FSEBehaviorMode -Type DWord -Force -ErrorAction SilentlyContinue
        }
        Write-Host "  [+] GameDVR user registry parameters restored." -ForegroundColor Green
    }

    # Update active state file: mark UserRestored = $true atomically with latest state from disk
    $latest = Get-ActiveStateSafe
    if ($latest) {
        $latest.UserRestored = $true
        if ($latest.SystemRestored) {
            $latest.State = "Restored"
        } else {
            $latest.State = "Restoring_UserDone"
        }
        Set-ActiveStateSafe -Data $latest | Out-Null
    }

    return $true
}

function Restore-SystemState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$Whitelist = @(),

        [Parameter(Mandatory = $false)]
        [PSCustomObject]$StartupConfig = $null,

        [Parameter(Mandatory = $false)]
        [ValidateSet("All", "System", "User")]
        [string]$Scope = "All"
    )

    $isSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
    if ($isSystem -and $Scope -eq "All") {
        Write-Warning "Restore-SystemState running under NT AUTHORITY\SYSTEM. Automatically scoping down to 'System' to preserve user profile integrity."
        $Scope = "System"
    }

    $stateData = Get-ActiveStateSafe
    if (-not $stateData) {
        Write-Warning "No active backup state file found at '$Script:ActiveStateFile'. Checking for residual backup shortcuts..."
    }

    if ($Scope -eq "User") {
        return (Restore-UserProfileState -StateData $stateData -StartupConfig $StartupConfig)
    }

    Write-Host "`n[*] Restoring system services to original state..." -ForegroundColor Cyan

    $restoredCount = 0
    $failedCount = 0

    if ($stateData -and $stateData.Services) {
        foreach ($svcEntry in $stateData.Services) {
            $sName = $svcEntry.Name
            $origMode = switch ($svcEntry.OriginalStartupType) {
                "Auto"      { "Automatic" }
                "Automatic" { "Automatic" }
                "Manual"    { "Manual" }
                "Disabled"  { "Disabled" }
                default     { "Manual" }
            }

            Write-Host "  [*] Restoring '$sName' -> $origMode..." -ForegroundColor Gray
            $result = Set-ServiceStateSafe -ServiceName $sName -StartupType $origMode -Whitelist $Whitelist -IsRestoring

            if ($result) {
                $restoredCount++
                if ($svcEntry.OriginalStatus -eq "Running") {
                    Start-Service -Name $sName -ErrorAction SilentlyContinue
                }
            }
            else {
                $failedCount++
            }
        }
    }

    # Restore HKLM Run items
    if ($stateData -and $stateData.StartupItems) {
        Write-Host "`n[*] Restoring system registry startup items (HKLM)..." -ForegroundColor Cyan
        foreach ($item in $stateData.StartupItems) {
            if ($item.Scope -eq "HKLM") {
                $hive = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
                if (Test-Path -LiteralPath $hive) {
                    Set-ItemProperty -Path $hive -Name $item.Name -Value $item.Value -Force -ErrorAction SilentlyContinue
                    Write-Host "  [+] Restored startup entry: $($item.Name) [HKLM]" -ForegroundColor Green
                }
            }
        }
    }

    # Restore Common Quarantined Startup folder shortcuts & ProgramData legacy root shortcuts
    $quarantineDir = Join-Path $Script:BackupDir "QuarantinedShortcuts"
    $commonStartup = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
    Restore-QuarantinedShortcuts -QuarantineDir $quarantineDir -CommonStartup $commonStartup -StateData $stateData -Scope "System"

    # Clean up legacy *.ugm_backup files in ProgramData startup folder
    if (Test-Path -LiteralPath $commonStartup) {
        Get-ChildItem -LiteralPath $commonStartup -File -Filter "*.ugm_backup" -ErrorAction SilentlyContinue | ForEach-Object {
            $origName = $_.Name -replace '\.ugm_backup$', ''
            Rename-Item -LiteralPath $_.FullName -NewName $origName -Force -ErrorAction SilentlyContinue
            Write-Host "  [+] Restored legacy common backup shortcut: $origName" -ForegroundColor Green
        }
    }

    # Restore Power Scheme
    if ($stateData -and $stateData.PowerScheme) {
        Write-Host "  [*] Restoring original power scheme ($($stateData.PowerScheme))..." -ForegroundColor Gray
        Set-PowerSchemeSafe -Guid $stateData.PowerScheme | Out-Null
    }

    # Restore Multimedia/MMCSS Settings
    if ($stateData -and $stateData.MultimediaConfig) {
        Restore-MultimediaConfig -Config $stateData.MultimediaConfig | Out-Null
    }

    # Restore Scheduled Tasks
    if ($stateData -and $stateData.ScheduledTasks) {
        Write-Host "`n[*] Restoring scheduled maintenance and telemetry tasks..." -ForegroundColor Cyan
        foreach ($st in $stateData.ScheduledTasks) {
            $origState = if ($st -is [hashtable]) { $st["OriginalState"] } else { $st.OriginalState }
            $tName     = if ($st -is [hashtable]) { $st["TaskName"] } else { $st.TaskName }
            $tPath     = if ($st -is [hashtable]) { $st["TaskPath"] } else { $st.TaskPath }

            if ($origState -ne "Disabled") {
                $enabled = $false
                if ($tPath) {
                    try {
                        $res = Enable-ScheduledTask -TaskPath $tPath -TaskName $tName -ErrorAction SilentlyContinue
                        if ($res) { $enabled = $true }
                    } catch {
                        Write-Verbose "Could not enable task $tName`: $($_.Exception.Message)"
                    }
                }
                if (-not $enabled) {
                    Enable-ScheduledTask -TaskName $tName -ErrorAction SilentlyContinue | Out-Null
                }
                Write-Host "  [+] Restored scheduled task: $tName" -ForegroundColor Green
            }
        }
    }

    # Restore Network Latency & Physical Adapter Properties
    if ($stateData) {
        Restore-NetworkGamingOptimizations `
            -NetworkLatencyConfig $stateData.NetworkLatencyConfig `
            -NetworkAdapterProperties $stateData.NetworkAdapterProperties | Out-Null
    }

    # Restore GameDVR System Policies (HKLM)
    if ($stateData -and $stateData.GameDVRConfig) {
        $gdvr = $stateData.GameDVRConfig
        if ($null -ne $gdvr.AllowGameDVR) {
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Value $gdvr.AllowGameDVR -Type DWord -Force -ErrorAction SilentlyContinue
        } else {
            Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -ErrorAction SilentlyContinue
        }
        Write-Host "  [+] GameDVR machine policy restored." -ForegroundColor Green
    } else {
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -ErrorAction SilentlyContinue
    }

    # Restore Processor Core Parking
    if ($stateData -and ($null -ne $stateData.CoreParkingMinCores)) {
        Restore-ProcessorIdleMinCores -OriginalPercent $stateData.CoreParkingMinCores | Out-Null
    }

    # Restore Minimum Processor Frequency State
    if ($stateData -and ($null -ne $stateData.ProcessorThrottleMin)) {
        Restore-ProcessorThrottleMin -OriginalPercent $stateData.ProcessorThrottleMin | Out-Null
    }

    # Restore AMD ULPS
    if ($stateData -and ($null -ne $stateData.UlpsConfig)) {
        Restore-AmdUlpsState -UlpsConfig $stateData.UlpsConfig | Out-Null
    }

    # Restore GPU MSI Mode & Priority
    if ($stateData -and ($null -ne $stateData.MSIConfig)) {
        Restore-GpuMsiConfig -MSIConfig $stateData.MSIConfig | Out-Null
    }

    # Restore NTFS File System I/O Tweaks
    if ($stateData -and ($null -ne $stateData.NTFSConfig)) {
        Restore-NTFSGamingOptimizations -NTFSConfig $stateData.NTFSConfig | Out-Null
    }

    # Restore Kernel DPC & Memory Management Settings
    if ($stateData -and ($null -ne $stateData.KernelDpcConfig)) {
        Restore-KernelDpcOptimizations -KernelDpcConfig $stateData.KernelDpcConfig | Out-Null
    }

    # Restore Input Buffer Queues
    if ($stateData -and ($null -ne $stateData.InputBufferConfig)) {
        Restore-InputBufferOptimizations -InputBufferConfig $stateData.InputBufferConfig | Out-Null
    }

    # Restore BCDedit System Timer Settings
    if ($stateData -and ($null -ne $stateData.BcdeditConfig)) {
        Restore-BcdeditTimerOptimizations -BcdeditConfig $stateData.BcdeditConfig | Out-Null
    }

    # Restore TCP Gaming Stack Settings
    if ($stateData -and ($null -ne $stateData.TcpStackConfig)) {
        Restore-TcpGamingStackOptimizations -TcpStackConfig $stateData.TcpStackConfig | Out-Null
    }

    # Restore HAGS GPU Scheduling
    if ($stateData -and ($null -ne $stateData.HagsConfig)) {
        Restore-HagsGpuScheduling -HagsConfig $stateData.HagsConfig | Out-Null
    }

    # Guarantee Microphone, Steam, LanmanServer, and peripheral services are unblocked
    Repair-CoreServices | Out-Null

    # Restore Windows Defender, Widgets & Focus Assist
    Set-DefenderGamingState -Disable $false | Out-Null
    Set-WindowsWidgetsAndSearchGamingState -Disable $false | Out-Null
    Set-FocusAssistAndSoundsGamingState -EnableFocusAssist $false | Out-Null

    # Mark system state as restored atomically with latest state from disk
    $latest = Get-ActiveStateSafe
    if ($latest) {
        $latest.SystemRestored = $true
        if ($Scope -eq "All") {
            # In All scope, execute user profile restoration now
            Restore-UserProfileState -StateData $latest -StartupConfig $StartupConfig | Out-Null
            $latest = Get-ActiveStateSafe
            if ($latest) {
                $latest.State = "Restored"
                Set-ActiveStateSafe -Data $latest | Out-Null
            }
        } else {
            if ($latest.UserRestored) {
                $latest.State = "Restored"
            } else {
                $latest.State = "Restoring_SystemDone"
            }
            Set-ActiveStateSafe -Data $latest | Out-Null
        }
    }

    Write-Host "`n[+] System state restored ($Scope scope). Services: $restoredCount restored, $failedCount failed." -ForegroundColor Green
    return $true
}

function Get-CurrentStateStatus {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $Script:ActiveStateFile)) {
        return "Normal"
    }
    try {
        $data = Get-Content -Path $Script:ActiveStateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        return $data.State
    }
    catch {
        return "Normal"
    }
}
