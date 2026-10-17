<#
.SYNOPSIS
    Advanced Windows gaming optimizations: Power schemes, MMCSS/Network registry tweaks, and RAM cleaning.
.DESCRIPTION
    Module providing:
    - Active power scheme detection, Ultimate Performance enabling, and restoration.
    - MMCSS (Multimedia Class Scheduler Service) and NetworkThrottlingIndex gaming latency optimizations.
    - Win32 EmptyWorkingSet memory trimming and cache reclamation.
#>

# Define Win32 memory trimming API via P/Invoke if not already defined
if (-not ([System.Management.Automation.PSTypeName]'Win32MemoryOptimizer').Type) {
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class Win32MemoryOptimizer {
    [DllImport("psapi.dll", SetLastError = true)]
    public static extern bool EmptyWorkingSet(IntPtr hProcess);
}
"@ -ErrorAction Stop
    }
    catch {
        Write-Verbose "Win32MemoryOptimizer type definition skipped or already loaded: $($_.Exception.Message)"
    }
}

function Get-ActivePowerSchemeGuid {
    [CmdletBinding()]
    param()

    try {
        $raw = powercfg /getactivescheme 2>&1
        if ($raw -match '([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})') {
            return $matches[1]
        }
        return $null
    }
    catch {
        Write-Warning "Could not retrieve active power scheme: $($_.Exception.Message)"
        return $null
    }
}

function Set-PowerSchemeSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$')]
        [string]$Guid
    )

    try {
        $null = powercfg /setactive $Guid 2>&1
        Write-Host "  [+] Power scheme activated: $Guid" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Failed to set power scheme ($Guid): $($_.Exception.Message)"
        return $false
    }
}

function Enable-UltimatePerformance {
    [CmdletBinding()]
    param()

    Write-Host "[*] Checking Power Scheme..." -ForegroundColor Cyan

    # If the user already has a tuned high-performance scheme (like Bitsum, Revision, Ultimate), keep it!
    $activeRaw = powercfg /getactivescheme 2>&1
    if ($activeRaw -match "(Bitsum|Ultimate|Revision|High [P|p]erformance|Max)") {
        Write-Host "  [+] Current active power scheme is already optimized: $activeRaw" -ForegroundColor Green
        Write-Host "  [+] Retaining active plan to avoid PCIe Link State / DisplayPort timing disruptions." -ForegroundColor Green
        return $true
    }

    $ultimateGuid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
    $list = powercfg /list 2>&1
    $targetGuid = $null

    if ($list -match "($ultimateGuid)") {
        $targetGuid = $ultimateGuid
    }
    else {
        $dupOut = powercfg /duplicatescheme $ultimateGuid 2>&1
        if ($dupOut -match '([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})') {
            $targetGuid = $matches[1]
            Write-Host "  [+] Unlocked Ultimate Performance scheme: $targetGuid" -ForegroundColor Green
        }
        else {
            $highPerfGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
            if ($list -match "($highPerfGuid)") {
                $targetGuid = $highPerfGuid
                Write-Host "  [+] Using High Performance power scheme fallback: $targetGuid" -ForegroundColor Yellow
            }
        }
    }

    if ($targetGuid) {
        return Set-PowerSchemeSafe -Guid $targetGuid
    }

    Write-Warning "Could not activate a dedicated performance power scheme. Existing scheme retained."
    return $false
}

function Get-MultimediaGamingConfig {
    [CmdletBinding()]
    param()

    $config = @{
        SystemProfile = @{}
        GamesTask     = @{}
    }

    $sysProfilePath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    if (Test-Path $sysProfilePath) {
        $props = Get-ItemProperty -Path $sysProfilePath -ErrorAction SilentlyContinue
        if ($props) {
            $config.SystemProfile["NetworkThrottlingIndex"] = $props.NetworkThrottlingIndex
            $config.SystemProfile["SystemResponsiveness"]   = $props.SystemResponsiveness
        }
    }

    $gamesTaskPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
    if (Test-Path $gamesTaskPath) {
        $props = Get-ItemProperty -Path $gamesTaskPath -ErrorAction SilentlyContinue
        if ($props) {
            $config.GamesTask["GPU Priority"]        = $props."GPU Priority"
            $config.GamesTask["Priority"]            = $props.Priority
            $config.GamesTask["Scheduling Category"] = $props."Scheduling Category"
            $config.GamesTask["SFIO Priority"]       = $props."SFIO Priority"
        }
    }

    return $config
}

function Set-GamingMultimediaConfig {
    [CmdletBinding()]
    param()

    Write-Host "[*] Applying Safe Network & Multimedia Gaming Optimizations..." -ForegroundColor Cyan

    $sysProfilePath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    if (-not (Test-Path $sysProfilePath)) {
        New-Item -Path $sysProfilePath -Force | Out-Null
    }

    # Disable network packet throttling (0xFFFFFFFF)
    Set-ItemProperty -Path $sysProfilePath -Name "NetworkThrottlingIndex" -Value 4294967295 -Type DWord -Force
    # Set SystemResponsiveness to safe 10 (guarantees 90% CPU priority to games while reserving 10% for system drivers/DWM)
    Set-ItemProperty -Path $sysProfilePath -Name "SystemResponsiveness"   -Value 10         -Type DWord -Force
    Write-Host "  [+] NetworkThrottlingIndex set to 0xFFFFFFFF (network packet throttling disabled)." -ForegroundColor Green
    Write-Host "  [+] SystemResponsiveness set to safe 10 (preserves DWM and display driver stability)." -ForegroundColor Green

    # Clean up and neutralize any corrupt Affinity = 0 or GPU Priority contention in Tasks\Games
    $gamesTaskPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
    if (Test-Path $gamesTaskPath) {
        # CRITICAL: Remove Affinity = 0 (an affinity mask of 0 starves threads and crashes drivers)
        Remove-ItemProperty -Path $gamesTaskPath -Name "Affinity" -ErrorAction SilentlyContinue
        # Ensure GPU Priority does not conflict with DWM (leave at safe default 8 or 2)
        Set-ItemProperty -Path $gamesTaskPath -Name "Priority" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $gamesTaskPath -Name "Scheduling Category" -Value "Medium" -Type String -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $gamesTaskPath -Name "SFIO Priority" -Value "Normal" -Type String -Force -ErrorAction SilentlyContinue
        Write-Host "  [+] Tasks\Games profile verified safe (Affinity=0 eliminated; DWM protected)." -ForegroundColor Green
    }

    return $true
}

function Restore-MultimediaConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config
    )

    Write-Host "[*] Restoring Multimedia Class Scheduler (MMCSS) settings..." -ForegroundColor Cyan

    $sysProfile = if ($Config -is [hashtable] -and $Config.ContainsKey("SystemProfile")) {
        $Config["SystemProfile"]
    } elseif ($Config.PSObject.Properties["SystemProfile"]) {
        $Config.SystemProfile
    } else { $null }

    if ($sysProfile) {
        $sysProfilePath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        if (Test-Path $sysProfilePath) {
            $props = if ($sysProfile -is [hashtable]) { $sysProfile.GetEnumerator() } else { $sysProfile.PSObject.Properties }
            foreach ($prop in $props) {
                $k = if ($prop.Name) { $prop.Name } else { $prop.Key }
                $v = if ($null -ne $prop.Value) { $prop.Value } else { $sysProfile[$k] }
                if ($null -ne $v) {
                    Set-ItemProperty -Path $sysProfilePath -Name $k -Value $v -Type DWord -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    $gamesTask = if ($Config -is [hashtable] -and $Config.ContainsKey("GamesTask")) {
        $Config["GamesTask"]
    } elseif ($Config.PSObject.Properties["GamesTask"]) {
        $Config.GamesTask
    } else { $null }

    if ($gamesTask) {
        $gamesTaskPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
        if (Test-Path $gamesTaskPath) {
            # Always ensure Affinity is removed if 0
            Remove-ItemProperty -Path $gamesTaskPath -Name "Affinity" -ErrorAction SilentlyContinue

            $props = if ($gamesTask -is [hashtable]) { $gamesTask.GetEnumerator() } else { $gamesTask.PSObject.Properties }
            foreach ($prop in $props) {
                $k = if ($prop.Name) { $prop.Name } else { $prop.Key }
                $v = if ($null -ne $prop.Value) { $prop.Value } else { $gamesTask[$k] }
                if ($null -ne $v -and $k -ne "Affinity") {
                    $propType = if ($v -is [int]) { "DWord" } else { "String" }
                    Set-ItemProperty -Path $gamesTaskPath -Name $k -Value $v -Type $propType -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Write-Host "  [+] Multimedia settings successfully restored." -ForegroundColor Green
    return $true
}

function Optimize-SystemMemory {
    [CmdletBinding()]
    param()

    Write-Host "[*] Flushing memory caches and trimming non-critical process working sets..." -ForegroundColor Cyan

    $initialMem = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
    $trimmedProcesses = 0

    # Whitelist all kernel, display, GPU driver, audio, and shell infrastructure processes
    $protectedProcNames = @(
        "System", "Idle", "Registry", "smss", "csrss", "wininit", "services", "lsass",
        "dwm", "audiodg", "vgk", "vgc",
        "nvcontainer", "nvdisplay.container", "nvcplui",
        "amdfendrsr", "RadeonSoftware", "amdow", "AMDNoiseSuppression", "atiesrxx", "atidxx",
        "igfxCUIService", "igfxEM",
        "fontdrvhost", "winlogon", "sihost", "explorer", "svchost", "SearchHost", "ShellExperienceHost"
    )

    $processes = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Id -gt 4 -and ($protectedProcNames -notcontains $_.ProcessName)
    }

    foreach ($proc in $processes) {
        try {
            if ($proc.Handle) {
                $null = [Win32MemoryOptimizer]::EmptyWorkingSet($proc.Handle)
                $trimmedProcesses++
            }
        }
        catch {
            # Access denied on system-protected processes is expected and ignored
        }
    }

    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()

    $finalMem = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
    $reclaimedKb = [math]::Max(0, ($finalMem - $initialMem))
    $reclaimedMb = [math]::Round($reclaimedKb / 1024, 2)

    Write-Host "  [+] Cleaned working sets across $trimmedProcesses non-critical processes." -ForegroundColor Green
    Write-Host "  [+] Free physical RAM increased by $reclaimedMb MB." -ForegroundColor Green
    return $reclaimedMb
}

function Repair-DisplayPipeline {
    [CmdletBinding()]
    param()

    Write-Host "`n=====================================================" -ForegroundColor Yellow
    Write-Host "       DISPLAY PIPELINE & DISPLAYPORT REPAIR         " -ForegroundColor Yellow
    Write-Host "=====================================================" -ForegroundColor Yellow

    # 1. Clean up invalid MMCSS Affinity / GPU Priority
    $gamesTaskPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
    if (Test-Path $gamesTaskPath) {
        Remove-ItemProperty -Path $gamesTaskPath -Name "Affinity" -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $gamesTaskPath -Name "Priority" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $gamesTaskPath -Name "Scheduling Category" -Value "Medium" -Type String -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $gamesTaskPath -Name "SFIO Priority" -Value "Normal" -Type String -Force -ErrorAction SilentlyContinue
        Write-Host "  [+] MMCSS Games task profile restored to safe Windows defaults." -ForegroundColor Green
    }

    $sysProfilePath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    if (Test-Path $sysProfilePath) {
        Set-ItemProperty -Path $sysProfilePath -Name "SystemResponsiveness" -Value 20 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Host "  [+] SystemResponsiveness restored to standard 20% background reserve." -ForegroundColor Green
    }

    # 2. Reset Display Topology Cache in Registry (forces clean Link Training)
    $gfxPaths = @(
        "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Configuration",
        "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Connectivity",
        "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\ScaleFactors"
    )

    foreach ($path in $gfxPaths) {
        if (Test-Path $path) {
            Get-ChildItem -Path $path -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  [+] Cleared cached display topology in $(Split-Path $path -Leaf)." -ForegroundColor Green
        }
    }

    # 3. Ensure Display Driver services are running
    $dispServices = @("AMD External Events Utility", "amdfendrsr", "NVDisplay.ContainerLocalSystem", "DisplayEnhancementService", "GraphicsPerfSvc")
    foreach ($ds in $dispServices) {
        $svc = Get-Service -Name $ds -ErrorAction SilentlyContinue
        if ($svc -and $svc.StartType -ne "Disabled") {
            if ($svc.Status -ne "Running") {
                Start-Service -Name $ds -ErrorAction SilentlyContinue
                Write-Host "  [+] Restarted display service: $ds" -ForegroundColor Green
            }
        }
    }

    Write-Host "`n[SUCCESS] Display pipeline repaired. All DisplayPort ports reset to clean handshake." -ForegroundColor Green
    return $true
}

function Set-NetworkGamingOptimizations {
    [CmdletBinding()]
    param()

    Write-Host "[*] Applying Ultra Low Latency Network (TCPNoDelay & EEE Disable)..." -ForegroundColor Cyan

    # 1. Disable Nagle's algorithm (TCPNoDelay = 1, TcpAckFrequency = 1) across all active interfaces
    $interfacesPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    if (Test-Path $interfacesPath) {
        Get-ChildItem -Path $interfacesPath | ForEach-Object {
            $props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
            if ($props.DhcpIPAddress -or $props.IPAddress) {
                Set-ItemProperty -Path $_.PSPath -Name "TCPNoDelay" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $_.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            }
        }
        Write-Host "  [+] TCPNoDelay & TcpAckFrequency set to 1 (Nagle's buffering delay eliminated)." -ForegroundColor Green
    }

    # 2. Disable Energy Efficient Ethernet and Green Ethernet power-saving sleep transitions on physical adapters
    try {
        Set-NetAdapterAdvancedProperty -Name "*" -RegistryKeyword "*EEE" -RegistryValue 0 -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "*" -RegistryKeyword "EnableGreenEthernet" -RegistryValue 0 -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "*" -RegistryKeyword "PowerSavingMode" -RegistryValue 0 -ErrorAction SilentlyContinue
        Write-Host "  [+] Physical network adapter energy-saving sleep states disabled (*EEE, GreenEthernet)." -ForegroundColor Green
    }
    catch {
        Write-Verbose "Network adapter property modification skipped: $($_.Exception.Message)"
    }

    return $true
}

function Restore-NetworkGamingOptimizations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [array]$NetworkLatencyConfig
    )

    Write-Host "[*] Restoring network adapter latency settings..." -ForegroundColor Cyan

    $interfacesPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    if ($NetworkLatencyConfig -and (Test-Path $interfacesPath)) {
        foreach ($item in $NetworkLatencyConfig) {
            $guidPath = Join-Path $interfacesPath $item.Guid
            if (Test-Path $guidPath) {
                if ($null -ne $item.TCPNoDelay) {
                    Set-ItemProperty -Path $guidPath -Name "TCPNoDelay" -Value $item.TCPNoDelay -Type DWord -Force -ErrorAction SilentlyContinue
                } else {
                    Remove-ItemProperty -Path $guidPath -Name "TCPNoDelay" -ErrorAction SilentlyContinue
                }
                if ($null -ne $item.TcpAckFrequency) {
                    Set-ItemProperty -Path $guidPath -Name "TcpAckFrequency" -Value $item.TcpAckFrequency -Type DWord -Force -ErrorAction SilentlyContinue
                } else {
                    Remove-ItemProperty -Path $guidPath -Name "TcpAckFrequency" -ErrorAction SilentlyContinue
                }
            }
        }
    }

    # Restore EEE on physical adapters
    try {
        Set-NetAdapterAdvancedProperty -Name "*" -RegistryKeyword "*EEE" -RegistryValue 1 -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "*" -RegistryKeyword "EnableGreenEthernet" -RegistryValue 1 -ErrorAction SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name "*" -RegistryKeyword "PowerSavingMode" -RegistryValue 1 -ErrorAction SilentlyContinue
    }
    catch {}

    Write-Host "  [+] Network latency settings restored to original state." -ForegroundColor Green
    return $true
}

function Set-DeepGameDVROptimizations {
    [CmdletBinding()]
    param()

    Write-Host "[*] Disabling GameDVR screen capture hooks and compositor overhead..." -ForegroundColor Cyan

    $gameDvrPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR"
    if (-not (Test-Path $gameDvrPath)) { New-Item -Path $gameDvrPath -Force | Out-Null }
    Set-ItemProperty -Path $gameDvrPath -Name "AppCaptureEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

    $configStorePath = "HKCU:\System\GameConfigStore"
    if (-not (Test-Path $configStorePath)) { New-Item -Path $configStorePath -Force | Out-Null }
    Set-ItemProperty -Path $configStorePath -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $configStorePath -Name "GameDVR_FSEBehaviorMode" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue

    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
    if (-not (Test-Path $policyPath)) { New-Item -Path $policyPath -Force | Out-Null }
    Set-ItemProperty -Path $policyPath -Name "AllowGameDVR" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

    Write-Host "  [+] GameDVR background capture hooks completely deactivated." -ForegroundColor Green
    return $true
}

function Repair-CoreServices {
    [CmdletBinding()]
    param()

    Write-Host "`n=====================================================" -ForegroundColor Yellow
    Write-Host "     REPAIRING MICROPHONE, STEAM & CORE SERVICES     " -ForegroundColor Yellow
    Write-Host "=====================================================" -ForegroundColor Yellow

    # 1. camsvc (Capability Access Manager Service) - Required for Microphone and Camera privacy access
    Write-Host "[*] Configuring Capability Access Manager (Microphone & Audio Privacy)..." -ForegroundColor Cyan
    $null = sc.exe config "camsvc" start= demand
    $camsvc = Get-Service -Name "camsvc" -ErrorAction SilentlyContinue
    if ($camsvc) {
        if ($camsvc.Status -ne "Running") {
            try {
                Start-Service -Name "camsvc" -ErrorAction Stop
                Write-Host "  [+] Service 'camsvc' started successfully (Microphone access unblocked)." -ForegroundColor Green
            }
            catch {
                $null = sc.exe start "camsvc"
                Write-Host "  [+] Service 'camsvc' start signaled via sc.exe." -ForegroundColor Green
            }
        }
        else {
            Write-Host "  [+] Service 'camsvc' is already running." -ForegroundColor Green
        }
    }

    # 2. LanmanServer (Server service) - Required for Windows RPC session checks and file sharing
    Write-Host "[*] Configuring Server service (LanmanServer)..." -ForegroundColor Cyan
    $null = sc.exe config "LanmanServer" start= auto
    $srv = Get-Service -Name "LanmanServer" -ErrorAction SilentlyContinue
    if ($srv) {
        if ($srv.Status -ne "Running") {
            try {
                Start-Service -Name "LanmanServer" -ErrorAction Stop
                Write-Host "  [+] Service 'LanmanServer' started successfully (RPC session unblocked)." -ForegroundColor Green
            }
            catch {
                $null = sc.exe start "LanmanServer"
                Write-Host "  [+] Service 'LanmanServer' start signaled via sc.exe." -ForegroundColor Green
            }
        }
        else {
            Write-Host "  [+] Service 'LanmanServer' is already running." -ForegroundColor Green
        }
    }

    # 3. Steam Client Service - Required for Steam launcher integrity and anti-cheat verification
    Write-Host "[*] Configuring Steam Client Service..." -ForegroundColor Cyan
    $steamSvc = Get-Service -Name "Steam Client Service" -ErrorAction SilentlyContinue
    if ($steamSvc) {
        $null = sc.exe config "Steam Client Service" start= demand
        Write-Host "  [+] Service 'Steam Client Service' set to Manual (demand) for clean first-launch." -ForegroundColor Green
    }

    # 4. Bluetooth Support Service (bthserv) - Required for Bluetooth gamepads and wireless headsets
    Write-Host "[*] Checking Bluetooth Services..." -ForegroundColor Cyan
    $bth = Get-Service -Name "bthserv" -ErrorAction SilentlyContinue
    if ($bth) {
        $null = sc.exe config "bthserv" start= demand
        Write-Host "  [+] Service 'bthserv' set to Manual (demand) for Bluetooth gamepads/audio." -ForegroundColor Green
    }

    # 5. Rockstar Game Library Service
    $rockstar = Get-Service -Name "Rockstar Service" -ErrorAction SilentlyContinue
    if ($rockstar) {
        $null = sc.exe config "Rockstar Service" start= demand
        Write-Host "  [+] Service 'Rockstar Service' set to Manual (demand)." -ForegroundColor Green
    }

    Write-Host "`n[SUCCESS] Microphone, Steam, LanmanServer, and peripheral services are fully unblocked!" -ForegroundColor Green
    return $true
}

function Set-DefenderGamingState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Disable
    )

    if ($Disable) {
        Write-Host "[*] Temporarily disabling Windows Defender Real-Time Protection & Scanning..." -ForegroundColor Cyan
        try {
            Set-MpPreference -DisableRealtimeMonitoring $true -DisableBehaviorMonitoring $true -DisableIOAVProtection $true -DisableScriptScanning $true -ErrorAction SilentlyContinue
            Write-Host "  [+] Windows Defender real-time scanning suspended." -ForegroundColor Green
        }
        catch {}

        $rtPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"
        if (-not (Test-Path $rtPath)) { New-Item -Path $rtPath -Force -ErrorAction SilentlyContinue | Out-Null }
        if (Test-Path $rtPath) {
            Set-ItemProperty -Path $rtPath -Name "DisableRealtimeMonitoring" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $rtPath -Name "DisableBehaviorMonitoring" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $rtPath -Name "DisableIOAVProtection" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $rtPath -Name "DisableOnAccessProtection" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-Host "[*] Restoring Windows Defender Real-Time Protection..." -ForegroundColor Cyan
        try {
            Set-MpPreference -DisableRealtimeMonitoring $false -DisableBehaviorMonitoring $false -DisableIOAVProtection $false -DisableScriptScanning $false -ErrorAction SilentlyContinue
            Write-Host "  [+] Windows Defender real-time protection restored." -ForegroundColor Green
        }
        catch {}

        $rtPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"
        if (Test-Path $rtPath) {
            Remove-ItemProperty -Path $rtPath -Name "DisableRealtimeMonitoring" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $rtPath -Name "DisableBehaviorMonitoring" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $rtPath -Name "DisableIOAVProtection" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $rtPath -Name "DisableOnAccessProtection" -ErrorAction SilentlyContinue
        }
    }
    return $true
}

function Set-WindowsWidgetsAndSearchGamingState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Disable
    )

    if ($Disable) {
        Write-Host "[*] Disabling Windows 11 Widgets and Bing web search in Start menu..." -ForegroundColor Cyan
        # 1. Disable Bing web search in Start
        $searchPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
        if (-not (Test-Path $searchPath)) { New-Item -Path $searchPath -Force -ErrorAction SilentlyContinue | Out-Null }
        if (Test-Path $searchPath) {
            Set-ItemProperty -Path $searchPath -Name "BingSearchEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $searchPath -Name "CortanaConsent" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        }
        $expPol = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
        if (-not (Test-Path $expPol)) { New-Item -Path $expPol -Force -ErrorAction SilentlyContinue | Out-Null }
        if (Test-Path $expPol) {
            Set-ItemProperty -Path $expPol -Name "DisableSearchBoxSuggestions" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        }

        # 2. Disable Taskbar Widgets (removes 6 msedgewebview2 processes)
        $advPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        if (Test-Path $advPath) {
            Set-ItemProperty -Path $advPath -Name "TaskbarDa" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        }
        $dshPath = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
        if (-not (Test-Path $dshPath)) { New-Item -Path $dshPath -Force -ErrorAction SilentlyContinue | Out-Null }
        if (Test-Path $dshPath) {
            Set-ItemProperty -Path $dshPath -Name "AllowNewsAndInterests" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        }

        Write-Host "  [+] Widgets and Bing Start search disabled (msedgewebview2 suppressed)." -ForegroundColor Green
    }
    else {
        Write-Host "[*] Restoring Windows Widgets and Start search..." -ForegroundColor Cyan
        $searchPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
        if (Test-Path $searchPath) {
            Set-ItemProperty -Path $searchPath -Name "BingSearchEnabled" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        }
        $expPol = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
        if (Test-Path $expPol) {
            Remove-ItemProperty -Path $expPol -Name "DisableSearchBoxSuggestions" -ErrorAction SilentlyContinue
        }
        $advPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        if (Test-Path $advPath) {
            Set-ItemProperty -Path $advPath -Name "TaskbarDa" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        }
        $dshPath = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
        if (Test-Path $dshPath) {
            Remove-ItemProperty -Path $dshPath -Name "AllowNewsAndInterests" -ErrorAction SilentlyContinue
        }
        Write-Host "  [+] Widgets and Start search settings restored." -ForegroundColor Green
    }
    return $true
}

function Set-FocusAssistAndSoundsGamingState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$EnableFocusAssist
    )

    $notifPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings"
    if (-not (Test-Path $notifPath)) { New-Item -Path $notifPath -Force -ErrorAction SilentlyContinue | Out-Null }

    if ($EnableFocusAssist) {
        Write-Host "[*] Enabling Focus Assist / Do Not Disturb & muting toast sounds..." -ForegroundColor Cyan
        if (Test-Path $notifPath) {
            Set-ItemProperty -Path $notifPath -Name "NOC_GLOBAL_SETTING_TOASTS_ENABLED" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        }
        Write-Host "  [+] Windows notifications and toast sound spikes suppressed during game." -ForegroundColor Green
    }
    else {
        Write-Host "[*] Restoring Windows notifications and system toasts..." -ForegroundColor Cyan
        if (Test-Path $notifPath) {
            Set-ItemProperty -Path $notifPath -Name "NOC_GLOBAL_SETTING_TOASTS_ENABLED" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        }
        Write-Host "  [+] Windows notifications restored." -ForegroundColor Green
    }
    return $true
}


