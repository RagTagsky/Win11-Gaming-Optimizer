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
$Script:ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $Script:BackupDir -ChildPath ".."))
$Script:APP_VERSION = "2.7"
$Script:APP_REPO = "RagTagsky/Win11-Gaming-Optimizer"

function Set-StatePropertySafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$StateObject,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [object]$Value = $null
    )

    if ($null -eq $StateObject) { return }
    if ($StateObject -is [System.Collections.IDictionary]) {
        $StateObject[$Name] = $Value
    }
    elseif ($StateObject.PSObject.Properties[$Name]) {
        $StateObject.$Name = $Value
    }
    else {
        $StateObject | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    }
}

function Get-ActiveStateSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path = $Script:ActiveStateFile
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    for ($i = 0; $i -lt 5; $i++) {
        try {
            $obj = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $obj) {
                $defaultProps = @{
                    State                = "Normal"
                    GamingBootId         = $null
                    GamingBootTime       = $null
                    BootRunCount         = 0
                    SessionLogonHandled  = $false
                    UserSessionHandled   = $false
                    SystemSessionHandled = $false
                    SystemRestored       = $false
                    UserRestored         = $false
                    LastBootError        = $null
                }
                foreach ($kv in $defaultProps.GetEnumerator()) {
                    if (-not $obj.PSObject.Properties[$kv.Key]) {
                        $obj | Add-Member -NotePropertyName $kv.Key -NotePropertyValue $kv.Value -Force
                    }
                }
            }
            return $obj
        } catch {
            Write-Verbose "Get-ActiveStateSafe retry $($i + 1) notice: $($_.Exception.Message)"
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

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    for ($i = 0; $i -lt 5; $i++) {
        try {
            $json = $Data | ConvertTo-Json -Depth 6
            [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
            return $true
        } catch {
            Write-Verbose "Set-ActiveStateSafe retry $($i + 1) notice: $($_.Exception.Message)"
            Start-Sleep -Milliseconds 100
        }
    }
    return $false
}

# Load optimizer module with include guard
if (-not (Get-Command Get-HardwareProfile -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot "SystemOptimizer.ps1")
}

# Registry Run hives handled by snapshot / suppression / restore (Scope -> Path)
$Script:RunHives = [ordered]@{
    HKCU   = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    HKLM   = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
    HKLM32 = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
}

function Get-GamingScheduledTaskTargets {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)] [bool]$HddProfile = $false)

    $list = @(
        @{ Name = "Consolidator";             Path = "\Microsoft\Windows\Customer Experience Improvement Program\" },
        @{ Name = "UsbCeip";                  Path = "\Microsoft\Windows\Customer Experience Improvement Program\" },
        @{ Name = "MapsToastTask";            Path = "\Microsoft\Windows\Maps\" },
        @{ Name = "ShowFeedbackToast";        Path = "\Microsoft\Windows\PerformanceTrace\" },
        @{ Name = "WhesvcToast";              Path = "\Microsoft\Windows\PerformanceTrace\" },
        @{ Name = "SustainabilityTelemetry";  Path = "\Microsoft\Windows\Sustainability\" },
        @{ Name = "PowerGridForecastTask";    Path = "\Microsoft\Windows\Sustainability\" },
        @{ Name = "AMDInstallLauncher";       Path = "\" },
        @{ Name = "AMDRyzenMasterSDKTask";    Path = "\" },
        @{ Name = "StartCN";                  Path = "\" },
        @{ Name = "StartDVR";                 Path = "\" },
        @{ Name = "ParkControl";              Path = "\" }
    )
    if ($HddProfile) { $list += @{ Name = "ScheduledDefrag"; Path = "\Microsoft\Windows\Defrag\" } }
    return $list
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
        Version                  = $Script:APP_VERSION
        Timestamp                = (Get-Date).ToString("o")
        State                    = "Armed"
        GamingBootId             = $null
        GamingBootTime           = $null
        BootRunCount             = 0
        SessionLogonHandled      = $false
        UserSessionHandled       = $false
        SystemSessionHandled     = $false
        SystemRestored           = $false
        UserRestored             = $false
        LastBootError            = $null
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
        ExtendedRegistryConfig   = @()
        PowerLatencyConfig       = $null
        MemoryCompressionConfig  = $null
    }

    # 1. Services Snapshot - shortcut: optimized for FPS & speed (batch CIM query instead of 173 individual calls)
    $cimServices = @(Get-CimInstance -ClassName Win32_Service -Property Name, DisplayName, StartMode, State -ErrorAction SilentlyContinue)
    $serviceMap = @{}
    foreach ($cs in $cimServices) {
        $serviceMap[$cs.Name] = $cs
    }

    $servicesList = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $BlacklistConfig) {
        $sName = $item.Name
        if ($Whitelist -contains $sName) { continue }

        $wmiSvc = $serviceMap[$sName]
        if (-not $wmiSvc) {
            foreach ($cs in $cimServices) {
                if ($cs.Name -like "$($sName)_*" -or $cs.Name -like "$($sName)[0-9]*") {
                    $wmiSvc = $cs
                    break
                }
            }
        }
        if ($wmiSvc) {
            $servicesList.Add(@{
                Name                = $sName
                DisplayName         = $wmiSvc.DisplayName
                OriginalStartupType = $wmiSvc.StartMode
                OriginalStatus      = $wmiSvc.State
            })
        }
    }
    $snapshot.Services = @($servicesList)

    # 2. HKCU / HKLM / HKLM-WOW64 Run Registry Items Snapshot
    foreach ($scope in $Script:RunHives.Keys) {
        $hivePath = $Script:RunHives[$scope]
        if (Test-Path $hivePath) {
            $props = Get-ItemProperty -Path $hivePath
            $props.PSObject.Properties | Where-Object {
                $_.Name -notmatch '^(PS(Path|ParentPath|ChildName|Drive|Provider))$'
            } | ForEach-Object {
                $snapshot.StartupItems += @{
                    Name  = $_.Name
                    Value = $_.Value
                    Scope = $scope
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

    # 5. Telemetry, Maintenance & third-party autorun Scheduled Tasks Snapshot
    $tasksToSnapshot = Get-GamingScheduledTaskTargets -HddProfile ([bool]$hwProfile.HddProfile)
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

    # 18-20. v2.8 extended registry tweaks, USB/NVMe/EPP power latency, memory compression
    $snapshot.ExtendedRegistryConfig  = @(Get-RegistryValueSnapshot -Targets @(Get-ExtendedGamingTargets -HardwareProfile $hwProfile -Whitelist $Whitelist))
    $snapshot.PowerLatencyConfig      = Get-PowerLatencyConfig
    $snapshot.MemoryCompressionConfig = Get-MemoryCompressionConfig

    # Write snapshot to disk atomically in pure UTF-8 without BOM
    Set-ActiveStateSafe -Path $Script:ActiveStateFile -Data $snapshot | Out-Null
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

    # 1. Suppress HKCU / HKLM / HKLM-WOW64 Run items (preserving only protected items like ctfmon, AMDNoiseSuppression)
    foreach ($regPath in $Script:RunHives.Values) {
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

    # 5. Disable Telemetry, Maintenance & third-party autorun Scheduled Tasks (suspend defrag on HDD)
    $hw = Get-HardwareProfile
    $tasksToDisable = Get-GamingScheduledTaskTargets -HddProfile ([bool]$hw.HddProfile)
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
    Set-InputBufferOptimizations -QueueSize 100 | Out-Null
    Set-BcdeditTimerOptimizations | Out-Null
    Set-HagsGpuScheduling -GpuVendor $hw.GpuVendor | Out-Null

    # 11. Repair legacy optimizer leftovers (priority inversion on fontdrvhost/sihost/lsass/ctfmon, orphaned tasks)
    Repair-LegacyOptimizerLeftovers | Out-Null

    # 12. Apply v2.8 Extended Gaming Optimizations (FSE/VRR, MPO off, IFEO game boost, IRQ, USB HID, AMD ASPM, VBS, ETW, Maintenance)
    $wlFile = Join-Path $Script:ProjectRoot "Config\services_whitelist.json"
    $wlList = if (Test-Path -LiteralPath $wlFile) { @((Get-Content -LiteralPath $wlFile -Raw -Encoding UTF8 | ConvertFrom-Json).ProtectedServices) } else { @() }
    Set-ExtendedGamingOptimizations -HardwareProfile $hw -Whitelist $wlList | Out-Null

    # 13. Apply Power Latency Optimizations (USB selective suspend, USB3 LPM, NVMe APST, Ryzen EPP)
    $activeState = Get-ActiveStateSafe
    $pwrCfg = if ($activeState -and $activeState.PowerLatencyConfig) { $activeState.PowerLatencyConfig } else { Get-PowerLatencyConfig }
    Set-PowerLatencyOptimizations -Config $pwrCfg | Out-Null

    # 14. Apply Memory Compression Gaming State (Disable on >= 16 GB RAM)
    Set-MemoryCompressionGamingState -HardwareProfile $hw | Out-Null

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
            $cleanName = [System.IO.Path]::GetFileName(($rf.Name -replace '\.ugm_backup$', ''))
            if ([string]::IsNullOrWhiteSpace($cleanName) -or $cleanName -in @(".", "..")) {
                continue
            }
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
                    } elseif ($matched.OriginalFolder -and $matched.OriginalFolder -notmatch '\.\.' -and $matched.OriginalFolder -like "*\Microsoft\Windows\Start Menu\Programs\Startup*") {
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

    # 7. Restore HKCU Extended Registry Tweaks (FSE/VRR/DXGI)
    if ($StateData -and $StateData.ExtendedRegistryConfig) {
        Restore-RegistryValueSnapshot -Snapshot $StateData.ExtendedRegistryConfig -Hive "HKCU" | Out-Null
        Write-Host "  [+] User DirectX / FSE registry parameters restored." -ForegroundColor Green
    }

    # Update active state file: mark UserRestored = $true atomically with latest state from disk
    $latest = Get-ActiveStateSafe
    if ($latest) {
        Set-StatePropertySafe -StateObject $latest -Name "UserRestored" -Value $true
        if ($latest.SystemRestored) {
            Set-StatePropertySafe -StateObject $latest -Name "State" -Value "Restored"
        } else {
            Set-StatePropertySafe -StateObject $latest -Name "State" -Value "Restoring_UserDone"
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
                    $targetSvcName = $sName
                    if (-not (Get-Service -Name $targetSvcName -ErrorAction SilentlyContinue)) {
                        $matching = @(Get-Service -Name "$($sName)*" -ErrorAction SilentlyContinue)
                        if ($matching.Count -gt 0) { $targetSvcName = $matching[0].Name }
                    }
                    Start-Service -Name $targetSvcName -ErrorAction SilentlyContinue
                }
            }
            else {
                $failedCount++
            }
        }
    }

    # Restore HKLM & HKLM-WOW64 Run items
    if ($stateData -and $stateData.StartupItems) {
        Write-Host "`n[*] Restoring system registry startup items (HKLM)..." -ForegroundColor Cyan
        foreach ($item in $stateData.StartupItems) {
            $hive = $Script:RunHives[$item.Scope]
            if ($hive -and (Test-Path -LiteralPath $hive)) {
                Set-ItemProperty -Path $hive -Name $item.Name -Value $item.Value -Force -ErrorAction SilentlyContinue
                Write-Host "  [+] Restored startup entry: $($item.Name) [$($item.Scope)]" -ForegroundColor Green
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
        $gpuVendor = if ($stateData.HardwareProfile) { $stateData.HardwareProfile.GpuVendor } else { "Unknown" }
        Restore-HagsGpuScheduling -HagsConfig $stateData.HagsConfig -GpuVendor $gpuVendor | Out-Null
    }

    # Restore Extended Registry Settings (MPO, Maintenance, VBS, IFEO Game Boost, IRQ, USB HID, AMD ASPM, ETW)
    if ($stateData -and $stateData.ExtendedRegistryConfig) {
        Restore-RegistryValueSnapshot -Snapshot $stateData.ExtendedRegistryConfig -Hive "HKLM" | Out-Null
        Write-Host "  [+] Extended system registry optimizations restored." -ForegroundColor Green
    }

    # Restore Power Latency Settings (USB selective suspend, USB3 LPM, NVMe APST, Ryzen EPP)
    if ($stateData -and $stateData.PowerLatencyConfig) {
        Restore-PowerLatencyOptimizations -Config $stateData.PowerLatencyConfig | Out-Null
    }

    # Restore Memory Compression
    if ($stateData -and $stateData.MemoryCompressionConfig) {
        Restore-MemoryCompressionConfig -Config $stateData.MemoryCompressionConfig | Out-Null
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
        Set-StatePropertySafe -StateObject $latest -Name "SystemRestored" -Value $true
        if ($Scope -eq "All") {
            # In All scope, execute user profile restoration now
            Restore-UserProfileState -StateData $latest -StartupConfig $StartupConfig | Out-Null
            $latest = Get-ActiveStateSafe
            if ($latest) {
                Set-StatePropertySafe -StateObject $latest -Name "State" -Value "Restored"
                Set-ActiveStateSafe -Data $latest | Out-Null
            }
        } else {
            if ($latest.UserRestored) {
                Set-StatePropertySafe -StateObject $latest -Name "State" -Value "Restored"
            } else {
                Set-StatePropertySafe -StateObject $latest -Name "State" -Value "Restoring_SystemDone"
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

    if (-not (Test-Path -LiteralPath $Script:ActiveStateFile)) {
        return "Normal"
    }
    try {
        $data = Get-ActiveStateSafe
        if ($data -and -not [string]::IsNullOrWhiteSpace([string]$data.State)) {
            return [string]$data.State
        }
        return "Normal"
    }
    catch {
        return "Normal"
    }
}

function Get-AppCurrentVersion {
    [CmdletBinding()]
    param()
    return $Script:APP_VERSION
}

function ConvertTo-SemVer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$VersionString
    )

    if ([string]::IsNullOrWhiteSpace($VersionString)) { return $null }

    $clean = ($VersionString.Trim() -replace '^[vV]', '') -replace '[-+_].*$', ''
    if ($clean -match '^\d+(\.\d+)*$') {
        $parts = $clean.Split('.')
        $major = [int]$parts[0]
        $minor = if ($parts.Length -gt 1) { [int]$parts[1] } else { 0 }
        $build = if ($parts.Length -gt 2) { [int]$parts[2] } else { 0 }
        $rev   = if ($parts.Length -gt 3) { [int]$parts[3] } else { 0 }
        return [System.Version]::new($major, $minor, $build, $rev)
    }
    return $null
}

function Test-SafeVersionTag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Tag
    )
    if ([string]::IsNullOrWhiteSpace($Tag)) { return $false }
    if ($Tag.Length -gt 64) { return $false }
    return ($Tag -match '^[vV]?\d+(\.\d+){0,3}([-+._][A-Za-z0-9]+)*$')
}

function Test-SafeGitHubReleaseUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Url,

        [Parameter(Mandatory = $false)]
        [string]$Repo = $Script:APP_REPO
    )
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    if ($Url.Length -gt 512) { return $false }
    if ($Url -match '[\r\n"''`&|<>^%]') { return $false }

    $escapedRepo = [regex]::Escape($Repo)
    return ($Url -match "^https://github\.com/$escapedRepo/releases(/[A-Za-z0-9._\-+/]+)?$")
}

function Check-AppUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$CurrentVersion = $Script:APP_VERSION,

        [Parameter(Mandatory = $false)]
        [string]$Repo = $Script:APP_REPO,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 3
    )

    if ($Repo -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
        $Repo = $Script:APP_REPO
    }
    $defaultReleaseUrl = "https://github.com/$Repo/releases"

    $result = [PSCustomObject]@{
        Checked         = $false
        UpdateAvailable = $false
        CurrentVersion  = $CurrentVersion
        LatestVersion   = $null
        ReleaseUrl      = $defaultReleaseUrl
        ReleaseName     = $null
        Error           = $null
    }

    # Never perform outbound network update checks under NT AUTHORITY\SYSTEM
    if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        $result.Error = "Skipped under NT AUTHORITY\SYSTEM"
        return $result
    }

    $oldProgress = $ProgressPreference
    try {
        $ProgressPreference = 'SilentlyContinue'

        if (-not ([System.Net.ServicePointManager]::SecurityProtocol -band [System.Net.SecurityProtocolType]::Tls12)) {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        }

        $latestTag = $null
        $releaseUrl = $null
        $releaseName = $null
        $isNetworkOffline = $false

        # Attempt 1: GitHub REST API
        $apiUrl = "https://api.github.com/repos/$Repo/releases/latest"
        try {
            $headers = @{
                "User-Agent" = "Win11-Gaming-Optimizer-Updater"
                "Accept"     = "application/vnd.github.v3+json"
            }
            $apiResp = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec $TimeoutSeconds -ErrorAction Stop
            if ($apiResp -and $apiResp.tag_name) {
                $candidateTag = [string]$apiResp.tag_name
                if (Test-SafeVersionTag -Tag $candidateTag) {
                    $latestTag = $candidateTag
                    $candidateUrl = [string]$apiResp.html_url
                    if (Test-SafeGitHubReleaseUrl -Url $candidateUrl -Repo $Repo) {
                        $releaseUrl = $candidateUrl
                    } else {
                        $releaseUrl = "$defaultReleaseUrl/tag/$latestTag"
                    }
                    $releaseName = [string]$apiResp.name
                }
            }
        }
        catch {
            $result.Error = $_.Exception.Message
            if ($_.Exception -is [System.Net.WebException]) {
                $webEx = [System.Net.WebException]$_.Exception
                if ($webEx.Status -in @(
                    [System.Net.WebExceptionStatus]::NameResolutionFailure,
                    [System.Net.WebExceptionStatus]::ConnectFailure
                )) {
                    $isNetworkOffline = $true
                }
            }
        }

        # Attempt 2: Fallback to GitHub Web 302 redirect (rate-limit immune)
        # Only query web redirect if network is reachable (avoids doubling timeout when offline)
        if (-not $latestTag -and -not $isNetworkOffline) {
            try {
                $webUrl = "https://github.com/$Repo/releases/latest"
                $req = [System.Net.HttpWebRequest]::Create($webUrl)
                $req.AllowAutoRedirect = $false
                $req.Timeout = [math]::Max(1000, $TimeoutSeconds * 1000)
                $req.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
                $resp = $req.GetResponse()
                try {
                    $loc = $resp.Headers['Location']
                    if ($loc -and $loc -match '/tag/([^/?#]+)') {
                        $candidateTag = $Matches[1]
                        if (Test-SafeVersionTag -Tag $candidateTag) {
                            $latestTag = $candidateTag
                            if (Test-SafeGitHubReleaseUrl -Url $loc -Repo $Repo) {
                                $releaseUrl = $loc
                            } else {
                                $releaseUrl = "$defaultReleaseUrl/tag/$latestTag"
                            }
                            $releaseName = $latestTag
                        }
                    }
                }
                finally {
                    $resp.Close()
                }
            }
            catch {
                $result.Error = $_.Exception.Message
            }
        }

        if ($latestTag) {
            $latestSemVer  = ConvertTo-SemVer $latestTag
            $currentSemVer = ConvertTo-SemVer $CurrentVersion

            $result.Checked       = $true
            $result.LatestVersion = $latestTag
            if ($releaseUrl -and (Test-SafeGitHubReleaseUrl -Url $releaseUrl -Repo $Repo)) {
                $result.ReleaseUrl = $releaseUrl
            }
            $result.ReleaseName   = $releaseName

            if ($latestSemVer -and $currentSemVer -and ($latestSemVer -gt $currentSemVer)) {
                $result.UpdateAvailable = $true
            }
            else {
                $result.UpdateAvailable = $false
            }
        }
    }
    catch {
        $result.Error = $_.Exception.Message
    }
    finally {
        $ProgressPreference = $oldProgress
    }

    return $result
}

function Invoke-AppUpdateWorkflow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$CurrentVersion = $Script:APP_VERSION,

        [Parameter(Mandatory = $false)]
        [switch]$OnStartup,

        [Parameter(Mandatory = $false)]
        [switch]$Passive,

        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 3
    )

    if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        return 0
    }

    $isVerbose = $Force -or (-not $OnStartup -and -not $Passive)

    if ($isVerbose) {
        Write-Host "[*] Checking for updates (GitHub)..." -ForegroundColor Cyan
    }

    $update = Check-AppUpdate -CurrentVersion $CurrentVersion -TimeoutSeconds $TimeoutSeconds
    $updateInfoFile = Join-Path $Script:BackupDir "update_info.cmd"

    if ($update.UpdateAvailable) {
        $safeVersion = if (Test-SafeVersionTag -Tag $update.LatestVersion) { $update.LatestVersion } else { "v$($update.CurrentVersion)" }
        $safeUrl = if (Test-SafeGitHubReleaseUrl -Url $update.ReleaseUrl) { $update.ReleaseUrl } else { "https://github.com/$Script:APP_REPO/releases" }

        # Cache validated update metadata for batch launcher
        try {
            $cmdContent = "@set `"UPDATE_AVAILABLE=1`"`r`n@set `"LATEST_VERSION=$safeVersion`"`r`n@set `"RELEASE_URL=$safeUrl`"`r`n"
            [System.IO.File]::WriteAllText($updateInfoFile, $cmdContent, [System.Text.Encoding]::ASCII)
        } catch {}

        # If invoked silently during batch launcher bootstrap, do not block menu with Read-Host
        if ($OnStartup -and -not $Force) {
            return 2  # 2 = Update available
        }

        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Yellow
        Write-Host "  UPDATE AVAILABLE: Ultra Gaming Mode $safeVersion is available!" -ForegroundColor Yellow
        Write-Host "  Current Version:  v$($update.CurrentVersion)" -ForegroundColor White
        Write-Host "  Latest Version:   $safeVersion" -ForegroundColor Green
        Write-Host "  Release URL:      $safeUrl" -ForegroundColor Cyan
        Write-Host "============================================================" -ForegroundColor Yellow

        if ($Passive -and -not $Force) {
            Write-Host "  [i] Run 'UltraGamingMode.ps1 -Action CheckUpdate' to update." -ForegroundColor Gray
            Write-Host ""
            return 2
        }

        Write-Host ""
        Write-Host "  [1] Open release page in browser" -ForegroundColor White
        Write-Host "  [2] Update repository now (git pull)" -ForegroundColor White
        Write-Host "  [0] Continue to Ultra Gaming Mode" -ForegroundColor Gray
        Write-Host ""

        $choice = "0"
        if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
            $choice = Read-Host "Select an option [0-2] (default: 0)"
            if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "0" }
        }

        if ($choice -eq "1") {
            Write-Host "[*] Opening release page in browser..." -ForegroundColor Cyan
            try {
                if (Test-SafeGitHubReleaseUrl -Url $safeUrl) {
                    Start-Process -FilePath $safeUrl
                } else {
                    Write-Warning "Blocked unsafe release URL."
                }
            } catch {
                Write-Warning "Could not open browser: $($_.Exception.Message)"
            }
            return 2
        }
        elseif ($choice -eq "2") {
            $projectRoot = if ($Script:ProjectRoot) { $Script:ProjectRoot } else { [System.IO.Path]::GetFullPath((Join-Path $Script:BackupDir "..")) }
            $gitDir = Join-Path $projectRoot ".git"
            $gitCmd = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            $hasGit = (Test-Path -LiteralPath $gitDir) -and ($null -ne $gitCmd)
            if ($hasGit) {
                Write-Host "[*] Pulling latest changes from git repository..." -ForegroundColor Cyan
                Push-Location $projectRoot
                try {
                    & $gitCmd.Source -c core.hooksPath=NUL pull --ff-only
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "[+] Repository successfully updated." -ForegroundColor Green
                        if (Test-Path -LiteralPath $updateInfoFile) {
                            Remove-Item -LiteralPath $updateInfoFile -Force -ErrorAction SilentlyContinue
                        }
                        return 0
                    } else {
                        Write-Warning "git pull exited with non-zero exit code ($LASTEXITCODE)."
                        return 2
                    }
                }
                catch {
                    Write-Warning "git pull encountered an error: $($_.Exception.Message)"
                    return 2
                }
                finally {
                    Pop-Location
                }
            } else {
                Write-Host "[!] Git repository not detected. Opening release download page..." -ForegroundColor Yellow
                try {
                    if (Test-SafeGitHubReleaseUrl -Url $safeUrl) {
                        Start-Process -FilePath $safeUrl
                    }
                } catch {
                    Write-Warning "Could not open browser: $($_.Exception.Message)"
                }
                return 2
            }
        }

        return 2  # 2 = Update available, user chose [0] Continue
    }

    # Clean up stale update cache if suite is already up-to-date
    if ($update.Checked -and -not $update.UpdateAvailable) {
        if (Test-Path -LiteralPath $updateInfoFile) {
            Remove-Item -LiteralPath $updateInfoFile -Force -ErrorAction SilentlyContinue
        }
        if ($isVerbose) {
            Write-Host "[+] Ultra Gaming Mode is up to date (v$($update.CurrentVersion)). Latest release: $($update.LatestVersion)" -ForegroundColor Green
        }
        return 0
    }

    # Offline or unable to connect
    if ($isVerbose) {
        Write-Host "[i] Update check skipped: unable to connect to GitHub (offline or rate-limited)." -ForegroundColor Gray
    }
    return 0
}


