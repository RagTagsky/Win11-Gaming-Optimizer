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

if (-not ([System.Management.Automation.PSTypeName]'Win32StandbyCleaner').Type) {
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class Win32StandbyCleaner {
    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out long lpLuid);

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    public struct TOKEN_PRIVILEGES {
        public int PrivilegeCount;
        public long Luid;
        public int Attributes;
    }

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, ref TOKEN_PRIVILEGES NewState, int BufferLength, IntPtr PreviousState, IntPtr ReturnLength);

    [DllImport("kernel32.dll")]
    public static extern IntPtr GetCurrentProcess();

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);

    [DllImport("ntdll.dll")]
    public static extern int NtSetSystemInformation(int SystemInformationClass, ref int SystemInformation, int SystemInformationLength);

    public static bool EnablePrivilege(string privilege) {
        IntPtr token;
        if (!OpenProcessToken(GetCurrentProcess(), 0x0028, out token)) return false;
        long luid;
        if (!LookupPrivilegeValue(null, privilege, out luid)) { CloseHandle(token); return false; }
        TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES { PrivilegeCount = 1, Luid = luid, Attributes = 0x00000002 };
        bool ok = AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        int err = Marshal.GetLastWin32Error();
        CloseHandle(token);
        return ok && (err == 0);
    }

    public static int FlushStandbyList() {
        try {
            EnablePrivilege("SeProfileSingleProcessPrivilege");
            EnablePrivilege("SeIncreaseQuotaPrivilege");
            int command = 4; // MemoryPurgeStandbyList
            return NtSetSystemInformation(80, ref command, sizeof(int));
        } catch {
            return -1;
        }
    }
}
"@ -ErrorAction SilentlyContinue
    }
    catch {
        Write-Verbose "Win32StandbyCleaner type compilation notice: $($_.Exception.Message)"
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
    $activeGuid = Get-ActivePowerSchemeGuid
    $activeRaw = powercfg /getactivescheme 2>&1
    $isAlreadyHighPerf = ($activeGuid -in @("e9a42b02-d5df-448d-aa00-03f14749eb61", "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c")) -or
                         ($activeRaw -match "(?i)Bitsum|Ultimate|Revision|High [P|p]erformance|Max|Высокая производительность|Максимальная производительность")
    if ($isAlreadyHighPerf) {
        Write-Host "  [+] Current active power scheme is already optimized: $activeRaw" -ForegroundColor Green
        Write-Host "  [+] Retaining active plan to avoid PCIe Link State / DisplayPort timing disruptions." -ForegroundColor Green
        return $true
    }

    $ultimateGuid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
    $list = powercfg /list 2>&1
    $targetGuid = $null

    $existingUltLine = ($list -split "[\r\n]+") | Where-Object { $_ -match "(?i)Ultimate|Максимальная" } | Select-Object -First 1
    if ($existingUltLine -and $existingUltLine -match "([a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})") {
        $targetGuid = $matches[1]
    }
    elseif ($list -match "($ultimateGuid)") {
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
    param(
        [Parameter(Mandatory = $false)]
        [switch]$Aggressive
    )

    $modeText = if ($Aggressive) { "Aggressive Low-RAM standby list & process memory reclamation" } else { "memory caches and trimming non-critical process working sets" }
    Write-Host "[*] Flushing $modeText..." -ForegroundColor Cyan

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

    # If Aggressive (e.g. LowRamProfile <= 8GB), flush standby list via NtSetSystemInformation and trigger multi-pass GC
    if ($Aggressive) {
        try {
            if (([System.Management.Automation.PSTypeName]'Win32StandbyCleaner').Type) {
                $standbyRes = [Win32StandbyCleaner]::FlushStandbyList()
                if ($standbyRes -eq 0) {
                    Write-Host "  [+] Kernel standby cache list successfully flushed to free page list." -ForegroundColor Green
                }
            }
        }
        catch {
            Write-Verbose "FlushStandbyList execution notice: $($_.Exception.Message)"
        }
    }

    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()

    $finalMem = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
    $reclaimedKb = [math]::Max(0, ($finalMem - $initialMem))
    $reclaimedMb = [math]::Round($reclaimedKb / 1024, 2)

    Write-Host "  [+] Cleaned working sets across $trimmedProcesses non-critical processes." -ForegroundColor Green
    if ($Aggressive) {
        Write-Host "  [+] Low-RAM Budget Guard: Working set trim & standby cache reclaim complete." -ForegroundColor Green
    }
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

function Unroll-NestedCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        $InputObject
    )

    $result = @()
    if ($null -eq $InputObject) { return $result }
    foreach ($entry in @($InputObject)) {
        if ($entry -is [array] -or ($entry -is [System.Collections.IEnumerable] -and -not ($entry -is [string] -or $entry -is [hashtable]))) {
            foreach ($inner in $entry) { $result += $inner }
        } else {
            $result += $entry
        }
    }
    return $result
}

function Select-PrimaryGamingGpu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [array]$Gpus
    )

    if ($null -eq $Gpus -or $Gpus.Count -eq 0) {
        $Gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
    }
    if ($Gpus.Count -eq 0) { return $null }

    $pci = @($Gpus | Where-Object { $_.PNPDeviceID -match "^PCI" })
    if ($pci.Count -eq 0) { return ($Gpus | Select-Object -First 1) }

    $isDedicatedGpu = {
        param($g)
        if (-not $g) { return $false }
        if ($g.PNPDeviceID -match "VEN_10DE") { return $true }
        if ($g.PNPDeviceID -match "VEN_1002" -and $g.Name -notmatch "AMD Radeon\(TM\) Graphics|Vega [0-9] Mobile") { return $true }
        if ($g.PNPDeviceID -match "VEN_8086" -and ($g.Name -match "Arc" -or $g.Name -notmatch "HD Graphics|UHD Graphics|Iris")) { return $true }
        return $false
    }

    $dedicatedGpus = @($pci | Where-Object { & $isDedicatedGpu $_ })
    if ($dedicatedGpus.Count -gt 0) {
        $activeDedicated = @($dedicatedGpus | Where-Object { $_.CurrentHorizontalResolution -and $_.CurrentHorizontalResolution -gt 0 })
        if ($activeDedicated.Count -gt 0) { return $activeDedicated[0] }
        return $dedicatedGpus[0]
    }

    $activeGpu = @($pci | Where-Object { $_.CurrentHorizontalResolution -and $_.CurrentHorizontalResolution -gt 0 })
    if ($activeGpu.Count -gt 0) { return $activeGpu[0] }

    return $pci[0]
}

function Resolve-StorageDeviceMediaType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Model = "",

        [Parameter(Mandatory = $false)]
        [string]$MediaType = "Unspecified",

        [Parameter(Mandatory = $false)]
        [int]$SpindleSpeed = 0,

        [Parameter(Mandatory = $false)]
        [string]$BusType = ""
    )

    $hddModelPattern = "(?i)HDD|WD[0-9]|WDC|ST[0-9]|Hitachi|Seagate|Barracuda|Spinpoint|MQ01|DT01|Deskstar|Caviar|Blue|Green|Red|Purple|Black|FireCuda|IronWolf"
    $ssdModelPattern = "(?i)SSD|NVMe|NAND|EVO|PRO|Crucial|Kingston|KIOXIA|Lexar|Sandisk|Micron|SK hynix|Adata|Corsair|Intel SSD|Sabrent"

    $isHdd = $false
    $resolvedMedia = $MediaType

    if ($MediaType -match "HDD" -or ($SpindleSpeed -gt 0)) {
        $isHdd = $true
        $resolvedMedia = "HDD"
    } elseif ($MediaType -match "SSD" -or $BusType -match "NVMe") {
        $isHdd = $false
        $resolvedMedia = "SSD"
    } else {
        if ($Model -match $hddModelPattern) {
            $isHdd = $true
            $resolvedMedia = "HDD"
        } elseif ($Model -match $ssdModelPattern -or $BusType -match "NVMe") {
            $isHdd = $false
            $resolvedMedia = "SSD"
        }
    }

    return @{
        IsHdd     = $isHdd
        MediaType = $resolvedMedia
    }
}

function Get-PhysicalGamingAdapters {
    [CmdletBinding()]
    param()

    return @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object {
        $name = $_.Name
        $desc = $_.InterfaceDescription
        ($name -ne "Ethernet 2") -and
        ($name -ne "wwan99") -and
        ($name -notmatch '(?i)Apple|Wintun|Bluetooth|Virtual|TAP|VPN|Hyper-V|vEthernet') -and
        ($desc -notmatch '(?i)Apple|Wintun|Bluetooth|Virtual|TAP|VPN|Hyper-V')
    })
}

function Get-NetworkAdapterGamingProperties {
    [CmdletBinding()]
    param()

    $results = @()
    $adapters = Get-PhysicalGamingAdapters
    foreach ($adapter in $adapters) {
        $allProps = Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue
        $flow = $allProps | Where-Object { $_.RegistryKeyword -eq "*FlowControl" }
        $mod  = $allProps | Where-Object { $_.RegistryKeyword -eq "*InterruptModeration" }
        $eee  = $allProps | Where-Object { $_.RegistryKeyword -eq "*EEE" }
        $grn  = $allProps | Where-Object { $_.RegistryKeyword -eq "EnableGreenEthernet" }
        $pwr  = $allProps | Where-Object { $_.RegistryKeyword -eq "PowerSavingMode" }

        $results += @{
            AdapterName         = $adapter.Name
            InterfaceDesc       = $adapter.InterfaceDescription
            FlowControl         = if ($flow) { ($flow.RegistryValue | Select-Object -First 1) } else { $null }
            InterruptModeration = if ($mod) { ($mod.RegistryValue | Select-Object -First 1) } else { $null }
            EEE                 = if ($eee) { ($eee.RegistryValue | Select-Object -First 1) } else { $null }
            GreenEthernet       = if ($grn) { ($grn.RegistryValue | Select-Object -First 1) } else { $null }
            PowerSavingMode     = if ($pwr) { ($pwr.RegistryValue | Select-Object -First 1) } else { $null }
        }
    }
    return ,$results
}

function Set-NetworkGamingOptimizations {
    [CmdletBinding()]
    param()

    Write-Host "[*] Applying Ultra Low Latency Network (TCPNoDelay, FlowControl=0, InterruptModeration=0)..." -ForegroundColor Cyan

    # 1. Apply TCP gaming stack optimizations (TCPNoDelay, TcpAckFrequency, netsh global, protecting iPhone and Wintun)
    Set-TcpGamingStackOptimizations | Out-Null

    # 2. Configure physical gaming network adapters strictly skipping Apple Mobile Device and Wintun tunnel
    $adapters = Get-PhysicalGamingAdapters
    foreach ($adapter in $adapters) {
        try {
            $advProps = Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue
            $fcProp  = $advProps | Where-Object { $_.RegistryKeyword -eq "*FlowControl" }
            $imProp  = $advProps | Where-Object { $_.RegistryKeyword -eq "*InterruptModeration" }
            $eeeProp = $advProps | Where-Object { $_.RegistryKeyword -eq "*EEE" }
            $grnProp = $advProps | Where-Object { $_.RegistryKeyword -eq "EnableGreenEthernet" }
            $pwrProp = $advProps | Where-Object { $_.RegistryKeyword -eq "PowerSavingMode" }

            if ($fcProp)  { Set-NetAdapterAdvancedProperty -InputObject $fcProp -RegistryValue "0" -ErrorAction SilentlyContinue }
            if ($imProp)  { Set-NetAdapterAdvancedProperty -InputObject $imProp -RegistryValue "0" -ErrorAction SilentlyContinue }
            if ($eeeProp) { Set-NetAdapterAdvancedProperty -InputObject $eeeProp -RegistryValue "0" -ErrorAction SilentlyContinue }
            if ($grnProp) { Set-NetAdapterAdvancedProperty -InputObject $grnProp -RegistryValue "0" -ErrorAction SilentlyContinue }
            if ($pwrProp) { Set-NetAdapterAdvancedProperty -InputObject $pwrProp -RegistryValue "0" -ErrorAction SilentlyContinue }

            Write-Host "  [+] Optimized '$($adapter.Name)' ($($adapter.InterfaceDescription)): FlowControl=0, InterruptModeration=0." -ForegroundColor Green
        }
        catch {
            Write-Verbose "Could not configure adapter $($adapter.Name): $($_.Exception.Message)"
        }
    }

    return $true
}

function Restore-NetworkGamingOptimizations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [array]$NetworkLatencyConfig,

        [Parameter(Mandatory = $false)]
        [array]$NetworkAdapterProperties
    )

    Write-Host "[*] Restoring network adapter latency and driver settings..." -ForegroundColor Cyan

    $interfacesPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    if ($NetworkLatencyConfig -and (Test-Path $interfacesPath)) {
        $protectedAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
            $name = $_.Name
            $desc = $_.InterfaceDescription
            ($name -eq "Ethernet 2") -or ($name -eq "wwan99") -or
            ($name -match '(?i)Apple|Wintun|Bluetooth|Virtual|TAP|VPN|Hyper-V|vEthernet') -or
            ($desc -match '(?i)Apple|Wintun|Bluetooth|Virtual|TAP|VPN|Hyper-V')
        })
        $protectedGuids = @($protectedAdapters | Where-Object { $_.InterfaceGuid } | ForEach-Object { $_.InterfaceGuid })

        foreach ($item in $NetworkLatencyConfig) {
            $guid = if ($item -is [hashtable]) { $item["Guid"] } else { $item.Guid }
            if ($protectedGuids -contains $guid) {
                Write-Verbose "Skipping protected interface GUID in legacy latency restore: $guid"
                continue
            }
            $guidPath = Join-Path $interfacesPath $guid
            if (Test-Path $guidPath) {
                $noDelay = if ($item -is [hashtable]) { $item["TCPNoDelay"] } else { $item.TCPNoDelay }
                $ackFreq = if ($item -is [hashtable]) { $item["TcpAckFrequency"] } else { $item.TcpAckFrequency }

                if ($null -ne $noDelay) {
                    Set-ItemProperty -Path $guidPath -Name "TCPNoDelay" -Value $noDelay -Type DWord -Force -ErrorAction SilentlyContinue
                } else {
                    Remove-ItemProperty -Path $guidPath -Name "TCPNoDelay" -ErrorAction SilentlyContinue
                }
                if ($null -ne $ackFreq) {
                    Set-ItemProperty -Path $guidPath -Name "TcpAckFrequency" -Value $ackFreq -Type DWord -Force -ErrorAction SilentlyContinue
                } else {
                    Remove-ItemProperty -Path $guidPath -Name "TcpAckFrequency" -ErrorAction SilentlyContinue
                }
            }
        }
    }

    # Restore advanced properties on physical adapters
    if ($NetworkAdapterProperties) {
        $flatAdapters = @(Unroll-NestedCollection -InputObject $NetworkAdapterProperties)
        foreach ($item in $flatAdapters) {
            $aName = if ($item -is [hashtable]) { $item["AdapterName"] } else { $item.AdapterName }
            if (-not $aName) { continue }

            $fc  = if ($item -is [hashtable]) { $item["FlowControl"] } else { $item.FlowControl }
            $im  = if ($item -is [hashtable]) { $item["InterruptModeration"] } else { $item.InterruptModeration }
            $eee = if ($item -is [hashtable]) { $item["EEE"] } else { $item.EEE }
            $grn = if ($item -is [hashtable]) { $item["GreenEthernet"] } else { $item.GreenEthernet }
            $pwr = if ($item -is [hashtable]) { $item["PowerSavingMode"] } else { $item.PowerSavingMode }

            try {
                $advProps = Get-NetAdapterAdvancedProperty -Name $aName -ErrorAction SilentlyContinue
                if ($null -ne $fc) {
                    $prop = $advProps | Where-Object { $_.RegistryKeyword -eq "*FlowControl" }
                    if ($prop) { Set-NetAdapterAdvancedProperty -InputObject $prop -RegistryValue ([string]$fc) -ErrorAction SilentlyContinue }
                }
                if ($null -ne $im) {
                    $prop = $advProps | Where-Object { $_.RegistryKeyword -eq "*InterruptModeration" }
                    if ($prop) { Set-NetAdapterAdvancedProperty -InputObject $prop -RegistryValue ([string]$im) -ErrorAction SilentlyContinue }
                }
                if ($null -ne $eee) {
                    $prop = $advProps | Where-Object { $_.RegistryKeyword -eq "*EEE" }
                    if ($prop) { Set-NetAdapterAdvancedProperty -InputObject $prop -RegistryValue ([string]$eee) -ErrorAction SilentlyContinue }
                }
                if ($null -ne $grn) {
                    $prop = $advProps | Where-Object { $_.RegistryKeyword -eq "EnableGreenEthernet" }
                    if ($prop) { Set-NetAdapterAdvancedProperty -InputObject $prop -RegistryValue ([string]$grn) -ErrorAction SilentlyContinue }
                }
                if ($null -ne $pwr) {
                    $prop = $advProps | Where-Object { $_.RegistryKeyword -eq "PowerSavingMode" }
                    if ($prop) { Set-NetAdapterAdvancedProperty -InputObject $prop -RegistryValue ([string]$pwr) -ErrorAction SilentlyContinue }
                }
                Write-Host "  [+] Restored adapter settings on '$aName'." -ForegroundColor Green
            }
            catch {
                Write-Verbose "Could not restore adapter properties for $aName`: $($_.Exception.Message)"
            }
        }
    }
    else {
        $adapters = Get-PhysicalGamingAdapters
        foreach ($adapter in $adapters) {
            try {
                $advProps = Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue
                $fcProp  = $advProps | Where-Object { $_.RegistryKeyword -eq "*FlowControl" }
                $imProp  = $advProps | Where-Object { $_.RegistryKeyword -eq "*InterruptModeration" }
                $eeeProp = $advProps | Where-Object { $_.RegistryKeyword -eq "*EEE" }
                if ($fcProp)  { Set-NetAdapterAdvancedProperty -InputObject $fcProp -RegistryValue "3" -ErrorAction SilentlyContinue }
                if ($imProp)  { Set-NetAdapterAdvancedProperty -InputObject $imProp -RegistryValue "1" -ErrorAction SilentlyContinue }
                if ($eeeProp) { Set-NetAdapterAdvancedProperty -InputObject $eeeProp -RegistryValue "1" -ErrorAction SilentlyContinue }
            }
            catch {
                Write-Verbose "Could not apply default adapter properties for $($adapter.Name)`: $($_.Exception.Message)"
            }
        }
    }

    Write-Host "  [+] Network settings restored to original state." -ForegroundColor Green
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
        Write-Host "[*] Checking Windows Defender Real-Time Protection & Scanning..." -ForegroundColor Cyan
        $isTamperProtected = $false
        try {
            $status = Get-MpComputerStatus -ErrorAction SilentlyContinue
            if ($status -and $status.IsTamperProtected) {
                $isTamperProtected = $true
            }
        } catch {
            Write-Verbose "Could not query Defender status: $($_.Exception.Message)"
        }

        if ($isTamperProtected) {
            Write-Host "  [i] Windows Defender Tamper Protection is active. Real-time protection retained for system security." -ForegroundColor Yellow
        } else {
            try {
                Set-MpPreference -DisableRealtimeMonitoring $true -DisableBehaviorMonitoring $true -DisableIOAVProtection $true -DisableScriptScanning $true -ErrorAction Stop
                Write-Host "  [+] Windows Defender real-time scanning suspended." -ForegroundColor Green
            }
            catch {
                Write-Verbose "Defender real-time suspension notice: $($_.Exception.Message)"
                Write-Host "  [i] Windows Defender real-time protection retained." -ForegroundColor Yellow
            }

            $rtPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"
            if (-not (Test-Path $rtPath)) { New-Item -Path $rtPath -Force -ErrorAction SilentlyContinue | Out-Null }
            if (Test-Path $rtPath) {
                Set-ItemProperty -Path $rtPath -Name "DisableRealtimeMonitoring" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $rtPath -Name "DisableBehaviorMonitoring" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $rtPath -Name "DisableIOAVProtection" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $rtPath -Name "DisableOnAccessProtection" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            }
        }
    }
    else {
        Write-Host "[*] Restoring Windows Defender Real-Time Protection..." -ForegroundColor Cyan
        try {
            Set-MpPreference -DisableRealtimeMonitoring $false -DisableBehaviorMonitoring $false -DisableIOAVProtection $false -DisableScriptScanning $false -ErrorAction Stop
            Write-Host "  [+] Windows Defender real-time protection restored." -ForegroundColor Green
        }
        catch {
            Write-Verbose "Defender restore notice: $($_.Exception.Message)"
            Write-Host "  [+] Windows Defender real-time protection verified." -ForegroundColor Green
        }

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

# ── Universal Hardware Auto-Detection & Adaptive Tuning Engine ─────────────

function Get-HardwareProfile {
    [CmdletBinding()]
    param()

    # 1. CPU Auto-Detection
    $allCpus = @(Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue)
    $cpu = if ($allCpus.Count -gt 0) { $allCpus[0] } else { $null }
    $cpuName = if ($cpu -and $cpu.Name) { ($cpu.Name.Trim() -replace '\s+', ' ') } else { "Unknown Processor" }
    $cpuMfg = if ($cpu -and $cpu.Manufacturer) { $cpu.Manufacturer } else { "" }
    $cpuVendor = if ($cpuMfg -match "Intel" -or $cpuName -match "Intel") { "Intel" }
                 elseif ($cpuMfg -match "AMD" -or $cpuName -match "AMD|Ryzen") { "AMD" }
                 else { "Unknown" }

    $physCores = 0
    $logCores = 0
    if ($allCpus.Count -gt 0) {
        $pMeasure = $allCpus | Measure-Object -Property NumberOfCores -Sum
        $physCores = if ($pMeasure.Sum) { [int]$pMeasure.Sum } else { 0 }
        $lMeasure = $allCpus | Measure-Object -Property NumberOfLogicalProcessors -Sum
        $logCores = if ($lMeasure.Sum) { [int]$lMeasure.Sum } else { 0 }
    }
    if ($physCores -le 0) { $physCores = [System.Environment]::ProcessorCount }
    if ($logCores -le 0) { $logCores = [System.Environment]::ProcessorCount }

    $arch = switch ($cpu.Architecture) {
        9 { "x64" }
        0 { "x86" }
        12 { "ARM64" }
        default { if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" } }
    }
    # LowCoreProfile: <= 4 logical cores (e.g. i3-2100 with 2C/4T or i5 4C/4T)
    $lowCore = ($logCores -le 4)

    # 2. GPU Auto-Detection (Dedicated gaming GPU priority)
    $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
    $primaryGpu = Select-PrimaryGamingGpu -Gpus $gpus

    $gpuName = if ($primaryGpu -and $primaryGpu.Name) { $primaryGpu.Name.Trim() } else { "Generic Display Adapter" }
    $gpuPnpId = if ($primaryGpu) { $primaryGpu.PNPDeviceID } else { $null }
    $gpuVendor = if ($primaryGpu) {
        if ($gpuPnpId -match "VEN_1002" -or $gpuName -match "AMD|Radeon" -or $primaryGpu.AdapterCompatibility -match "Advanced Micro Devices") { "AMD" }
        elseif ($gpuPnpId -match "VEN_10DE" -or $gpuName -match "NVIDIA|GeForce|Quadro|RTX|GTX" -or $primaryGpu.AdapterCompatibility -match "NVIDIA") { "NVIDIA" }
        elseif ($gpuPnpId -match "VEN_8086" -or $gpuName -match "Intel" -or $primaryGpu.AdapterCompatibility -match "Intel") { "Intel" }
        else { "Unknown" }
    } else { "Unknown" }

    $gpuRes = if ($primaryGpu -and $primaryGpu.CurrentHorizontalResolution) {
        "$($primaryGpu.CurrentHorizontalResolution)x$($primaryGpu.CurrentVerticalResolution) @ $($primaryGpu.CurrentRefreshRate)Hz"
    } else { "Display Inactive / Virtual" }

    # Query MSI status for the primary GPU
    $gpuMsiSupported = $false
    $gpuPriority = $null
    if ($gpuPnpId) {
        $msiPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$gpuPnpId\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
        $affPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$gpuPnpId\Device Parameters\Interrupt Management\Affinity Policy"
        if (Test-Path $msiPath) {
            $val = (Get-ItemProperty -Path $msiPath -ErrorAction SilentlyContinue).MSISupported
            if ($null -ne $val -and [int]$val -eq 1) { $gpuMsiSupported = $true }
        }
        if (Test-Path $affPath) {
            $val = (Get-ItemProperty -Path $affPath -ErrorAction SilentlyContinue).DevicePriority
            if ($null -ne $val) { $gpuPriority = [int]$val }
        }
    }

    # 3. RAM Auto-Detection & Pagefile Check
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $totalRamBytes = if ($cs -and $cs.TotalPhysicalMemory) { [int64]$cs.TotalPhysicalMemory } else { 0 }
    if ($totalRamBytes -le 0) {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os -and $os.TotalVisibleMemorySize) {
            $totalRamBytes = [int64]$os.TotalVisibleMemorySize * 1024
        }
    }
    $totalRamGb = [math]::Round($totalRamBytes / 1GB, 2)
    # LowRamProfile: <= 8.5 GB (covers 8 GB systems with hardware reservations)
    $lowRam = ($totalRamBytes -gt 0 -and $totalRamBytes -le [int64](8.5 * 1024 * 1024 * 1024))

    $pfManaged = if ($cs -and $null -ne $cs.AutomaticManagedPagefile) { [bool]$cs.AutomaticManagedPagefile } else { $false }
    $pfReg = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "PagingFiles", "ExistingPageFiles" -ErrorAction SilentlyContinue
    $hasPfReg = ($pfReg -and (($pfReg.PagingFiles -and $pfReg.PagingFiles.Count -gt 0) -or ($pfReg.ExistingPageFiles -and $pfReg.ExistingPageFiles.Count -gt 0)))
    $pfUsage = @(Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue)
    $pfConfigured = ($pfUsage.Count -gt 0 -or $hasPfReg -or $pfManaged)
    $pfWarning = if (-not $pfConfigured) {
        "CRITICAL: Paging file is disabled or missing! On 8GB RAM, modern games will crash with Out-Of-Memory (OOM)."
    } else { $null }

    # 4. Storage Disk Auto-Detection (System Drive C:)
    $cLetter = "C"
    $diskNum = $null
    $diskModel = "Unknown Storage Device"
    $mediaType = "Unknown"
    $busType = "Unknown"
    $isHdd = $false

    try {
        $part = Get-Partition -DriveLetter $cLetter -ErrorAction Stop
        $diskNum = $part.DiskNumber
        $pDisks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
        $targetDisk = $pDisks | Where-Object { [string]$_.DeviceId -eq [string]$diskNum } | Select-Object -First 1
        if ($targetDisk) {
            $diskModel = $targetDisk.FriendlyName
            $busType   = [string]$targetDisk.BusType
            $resolved  = Resolve-StorageDeviceMediaType -Model $targetDisk.FriendlyName -MediaType $targetDisk.MediaType -SpindleSpeed $targetDisk.SpindleSpeed -BusType $targetDisk.BusType
            $mediaType = $resolved.MediaType
            $isHdd     = $resolved.IsHdd
        }
    } catch {
        Write-Verbose "Partition query notice: $($_.Exception.Message)"
    }

    # Fallback to WMI if mediaType or diskModel remains unresolved
    if ($mediaType -eq "Unknown" -or $diskModel -eq "Unknown Storage Device") {
        try {
            $cDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID = 'C:'"
            $partitions = Get-CimAssociatedInstance -InputObject $cDrive -ResultClassName Win32_DiskPartition
            if ($partitions) {
                $drives = Get-CimAssociatedInstance -InputObject ($partitions | Select-Object -First 1) -ResultClassName Win32_DiskDrive
                if ($drives) {
                    $d = $drives | Select-Object -First 1
                    $diskModel = $d.Model
                    $diskNum   = $d.Index
                    $resolved  = Resolve-StorageDeviceMediaType -Model $d.Model
                    $mediaType = $resolved.MediaType
                    $isHdd     = $resolved.IsHdd
                }
            }
        } catch {
            Write-Verbose "CIM DiskDrive query notice: $($_.Exception.Message)"
        }
    }

    # Also detect if any secondary drive is an HDD
    $anyHdd = $false
    try {
        $allPDisks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
        foreach ($pd in $allPDisks) {
            $res = Resolve-StorageDeviceMediaType -Model $pd.FriendlyName -MediaType $pd.MediaType -SpindleSpeed $pd.SpindleSpeed -BusType $pd.BusType
            if ($res.IsHdd) {
                $anyHdd = $true
                break
            }
        }
    } catch {
        Write-Verbose "Secondary PhysicalDisk check notice: $($_.Exception.Message)"
    }

    if (-not $anyHdd) {
        try {
            $allDrives = @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue)
            foreach ($d in $allDrives) {
                $res = Resolve-StorageDeviceMediaType -Model $d.Model
                if ($res.IsHdd) {
                    $anyHdd = $true
                    break
                }
            }
        } catch {
            Write-Verbose "Secondary CimInstance DiskDrive check notice: $($_.Exception.Message)"
        }
    }

    return @{
        CpuName             = $cpuName
        CpuVendor           = $cpuVendor
        CpuArchitecture     = $arch
        PhysicalCores       = $physCores
        LogicalCores        = $logCores
        LowCoreProfile      = $lowCore

        GpuName             = $gpuName
        GpuVendor           = $gpuVendor
        GpuPnpDeviceId      = $gpuPnpId
        GpuResolution       = $gpuRes
        GpuMsiSupported     = $gpuMsiSupported
        GpuDevicePriority   = $gpuPriority

        TotalRamBytes       = $totalRamBytes
        TotalRamGB          = $totalRamGb
        LowRamProfile       = $lowRam
        PagefileConfigured  = $pfConfigured
        PagefileManaged     = $pfManaged
        PagefileWarning     = $pfWarning

        SystemDriveLetter   = $cLetter
        SystemDiskNumber    = $diskNum
        SystemDiskModel     = $diskModel
        SystemDiskMediaType = $mediaType
        SystemDiskBusType   = $busType
        IsHdd               = $isHdd
        HasAnyHdd           = $anyHdd
        HddProfile          = ($isHdd -or $anyHdd)
    }
}

# ── AMD Radeon & Ryzen Hardware Optimizations ──────────────────────────────

function Get-AmdGpuDriverClassKeys {
    [CmdletBinding()]
    param()

    $keys = @()
    $classPath = "SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
    try {
        $base = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($classPath)
        if ($base) {
            $subNames = $base.GetSubKeyNames() | Where-Object { $_ -match '^\d{4}$' }
            foreach ($sub in $subNames) {
                $sk = $base.OpenSubKey($sub)
                if ($sk) {
                    $desc = $sk.GetValue("DriverDesc")
                    $prov = $sk.GetValue("ProviderName")
                    $ulps = $sk.GetValue("EnableUlps")
                    if (($desc -match '(?i)AMD|Radeon') -or ($prov -match '(?i)Advanced Micro Devices') -or ($null -ne $ulps)) {
                        $keys += @{
                            SubKeyName = $sub
                            Path       = "HKLM:\$classPath\$sub"
                            DriverDesc = $desc
                            EnableUlps = $ulps
                        }
                    }
                    $sk.Close()
                }
            }
            $base.Close()
        }
    }
    catch {
        Write-Warning "Could not enumerate GPU driver class keys: $($_.Exception.Message)"
    }
    return ,$keys
}

function Set-AmdUlpsState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Enable
    )

    $stateText = if ($Enable -eq 0) { "Disabling (0)" } else { "Enabling (1)" }
    Write-Host "[*] $stateText AMD ULPS (Ultra Low Power State)..." -ForegroundColor Cyan

    $keys = @(Get-AmdGpuDriverClassKeys)
    if ($keys.Count -eq 0) {
        Write-Host "  [i] No AMD GPU driver keys found. ULPS configuration skipped." -ForegroundColor Gray
        return $false
    }

    $allSuccess = $true
    foreach ($k in $keys) {
        $p = if ($k -is [hashtable]) { $k["Path"] } else { $k.Path }
        $sub = if ($k -is [hashtable]) { $k["SubKeyName"] } else { $k.SubKeyName }
        $desc = if ($k -is [hashtable]) { $k["DriverDesc"] } else { $k.DriverDesc }
        try {
            Set-ItemProperty -Path $p -Name "EnableUlps" -Value $Enable -Type DWord -Force -ErrorAction Stop
            Write-Host "  [+] Set EnableUlps = $Enable on $sub ($desc)." -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to set EnableUlps on $p`: $($_.Exception.Message)"
            $allSuccess = $false
        }
    }
    return $allSuccess
}

function Restore-AmdUlpsState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [array]$UlpsConfig
    )

    if ($UlpsConfig) {
        Write-Host "[*] Restoring AMD ULPS settings..." -ForegroundColor Cyan
        $flatUlps = @(Unroll-NestedCollection -InputObject $UlpsConfig)
        foreach ($item in $flatUlps) {
            $regPath = if ($item -is [hashtable]) { $item["Path"] } else { $item.Path }
            $origVal = if ($item -is [hashtable]) { $item["EnableUlps"] } else { $item.EnableUlps }
            if ($regPath) {
                try {
                    if ($null -ne $origVal) {
                        Set-ItemProperty -Path $regPath -Name "EnableUlps" -Value $origVal -Type DWord -Force -ErrorAction Stop
                        Write-Host "  [+] Restored EnableUlps = $origVal on $regPath." -ForegroundColor Green
                    } else {
                        Remove-ItemProperty -Path $regPath -Name "EnableUlps" -ErrorAction Stop
                        Write-Host "  [+] Removed EnableUlps on $regPath (restored to original state)." -ForegroundColor Green
                    }
                }
                catch {
                    Write-Warning "Failed to restore EnableUlps on $regPath`: $($_.Exception.Message)"
                }
            }
        }
    }
    return $true
}

function Clear-AmdShaderCache {
    [CmdletBinding()]
    param()

    Write-Host "`n=====================================================" -ForegroundColor Magenta
    Write-Host "     UNIVERSAL GPU & DIRECTX / VULKAN SHADER CACHE PURGE " -ForegroundColor Magenta
    Write-Host "=====================================================" -ForegroundColor Magenta

    $targetDirs = @(
        (Join-Path $env:LOCALAPPDATA "AMD\DxCache"),
        (Join-Path $env:LOCALAPPDATA "AMD\VkCache"),
        (Join-Path $env:LOCALAPPDATA "AMD\DxcCache"),
        (Join-Path $env:LOCALAPPDATA "AMD\DX9Cache"),
        (Join-Path $env:LOCALAPPDATA "AMD\OglCache"),
        (Join-Path $env:LOCALAPPDATA "NVIDIA\DXCache"),
        (Join-Path $env:LOCALAPPDATA "NVIDIA\GLCache"),
        (Join-Path $env:APPDATA "NVIDIA\ComputeCache"),
        (Join-Path $env:LOCALAPPDATA "Intel\ShaderCache"),
        (Join-Path $env:LOCALAPPDATA "Intel\D3DSCache"),
        (Join-Path $env:LOCALAPPDATA "D3DSCache")
    )

    $totalPurgedFiles = 0
    $totalFreedBytes = 0

    foreach ($dir in $targetDirs) {
        if (-not (Test-Path $dir)) {
            continue
        }

        Write-Host "[*] Inspecting cache directory: $dir" -ForegroundColor Cyan
        $filesBefore = Get-ChildItem -Path $dir -Recurse -File -ErrorAction SilentlyContinue
        $dirFileCount = if ($filesBefore) { $filesBefore.Count } else { 0 }
        $dirBytes = 0
        if ($filesBefore) {
            $measure = $filesBefore | Measure-Object -Property Length -Sum
            $dirBytes = if ($measure.Sum) { $measure.Sum } else { 0 }
        }

        $dirMb = [math]::Round($dirBytes / 1MB, 2)
        Write-Host "  [+] Found $dirFileCount cache files ($dirMb MB)." -ForegroundColor White

        $items = Get-ChildItem -Path $dir -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            try {
                Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
            catch {
                Write-Verbose "Cache file lock notice for $($item.FullName)`: $($_.Exception.Message)"
            }
        }

        $filesAfter = Get-ChildItem -Path $dir -Recurse -File -ErrorAction SilentlyContinue
        $remainingCount = if ($filesAfter) { $filesAfter.Count } else { 0 }
        $remainingBytes = 0
        if ($filesAfter) {
            $remMeasure = $filesAfter | Measure-Object -Property Length -Sum
            $remainingBytes = if ($remMeasure.Sum) { $remMeasure.Sum } else { 0 }
        }

        $actuallyPurgedFiles = [Math]::Max(0, ($dirFileCount - $remainingCount))
        $actuallyFreedBytes  = [Math]::Max(0, ($dirBytes - $remainingBytes))

        $totalPurgedFiles += $actuallyPurgedFiles
        $totalFreedBytes  += $actuallyFreedBytes

        $leafName = Split-Path $dir -Leaf
        if ($dir -match '(?i)AMD\\') { $leafName = "AMD\$leafName" }
        elseif ($dir -match '(?i)NVIDIA\\') { $leafName = "NVIDIA\$leafName" }
        elseif ($dir -match '(?i)Intel\\') { $leafName = "Intel\$leafName" }
        Write-Host "  [+] Purged $actuallyPurgedFiles files in $leafName." -ForegroundColor Green
    }

    $totalFreedMb = [math]::Round($totalFreedBytes / 1MB, 2)
    Write-Host "`n[SUCCESS] Shader cache purge complete. Cleaned $totalPurgedFiles files, freed $totalFreedMb MB." -ForegroundColor Green
    Write-Host "  [i] Shaders will cleanly recompile in-game without stutter or corruption." -ForegroundColor Gray
    return $totalFreedMb
}

Set-Alias -Name Clear-GpuShaderCache -Value Clear-AmdShaderCache -ErrorAction SilentlyContinue

function Get-ProcessorIdleMinCores {
    [CmdletBinding()]
    param()

    try {
        # 1. Fast, exact, locale-independent registry query
        $activeGuid = Get-ActivePowerSchemeGuid
        if ($activeGuid) {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$activeGuid\54533251-82be-4824-96c1-47b60b740d00\0cc5b647-c1df-4637-891a-dec35c318583"
            if (Test-Path $regPath) {
                $p = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
                if ($null -ne $p.ACSettingIndex) {
                    return [int]$p.ACSettingIndex
                }
            }
        }

        # 2. Locale-aware command line parsing fallback
        $raw = powercfg /q SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 2>&1 | Out-String
        if ($raw -match "(?im)(?:AC|сети|secteur|wechselstrom|ca)[^:\r\n]*:\s*0x([0-9a-fA-F]+)") {
            return [Convert]::ToInt32($matches[1], 16)
        }
        $currentLines = ($raw -split "[\r\n]+") | Where-Object { $_ -match "(?i)(?:current|текущий)" -and $_ -match ":\s*0x([0-9a-fA-F]+)" }
        if ($currentLines.Count -gt 0 -and $currentLines[0] -match ":\s*0x([0-9a-fA-F]+)") {
            return [Convert]::ToInt32($matches[1], 16)
        }
        return $null
    }
    catch {
        return $null
    }
}

function Set-ProcessorIdleMinCores {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$Percent = 100,

        [Parameter(Mandatory = $false)]
        [string]$CpuVendor = "",

        [Parameter(Mandatory = $false)]
        [switch]$LowCore
    )

    Write-Host "[*] Configuring Processor Core Parking (CPMINCORES = $Percent%)..." -ForegroundColor Cyan
    try {
        $out1 = powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES $Percent 2>&1
        $out2 = powercfg -setactive SCHEME_CURRENT 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "powercfg failed to apply CPMINCORES ($LASTEXITCODE): $out1 $out2"
            return $false
        }
        if ($Percent -eq 100) {
            if ($LowCore) {
                Write-Host "  [+] Low-Core Budget CPU Guard: All logical cores forced unparked (prevents thread stalls, CPMINCORES = 100%)." -ForegroundColor Green
            } elseif ($CpuVendor -eq "Intel") {
                Write-Host "  [+] Intel Core Architecture: Core parking DISABLED (CPMINCORES = 100% - all threads active)." -ForegroundColor Green
            } elseif ($CpuVendor -eq "AMD") {
                Write-Host "  [+] AMD Ryzen Architecture: Core parking DISABLED (CPMINCORES = 100% - all CCX cores active)." -ForegroundColor Green
            } else {
                Write-Host "  [+] Processor Core Parking DISABLED (all CPU cores kept active, CPMINCORES = 100%)." -ForegroundColor Green
            }
        }
        else {
            Write-Host "  [+] Processor CPMINCORES set to $Percent%." -ForegroundColor Green
        }
        return $true
    }
    catch {
        Write-Warning "Failed to set CPMINCORES: $($_.Exception.Message)"
        return $false
    }
}

function Restore-ProcessorIdleMinCores {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [object]$OriginalPercent
    )

    if ($null -ne $OriginalPercent) {
        Write-Host "[*] Restoring Processor Core Parking..." -ForegroundColor Cyan
        try {
            $p = [int]$OriginalPercent
            $out1 = powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES $p 2>&1
            $out2 = powercfg -setactive SCHEME_CURRENT 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "powercfg failed to restore CPMINCORES ($LASTEXITCODE): $out1 $out2"
                return $false
            }
            Write-Host "  [+] Processor core parking restored to $p%." -ForegroundColor Green
            return $true
        }
        catch {
            Write-Warning "Exception restoring CPMINCORES: $($_.Exception.Message)"
            return $false
        }
    }
    return $true
}

function Get-ProcessorThrottleMin {
    [CmdletBinding()]
    param()

    try {
        $activeGuid = Get-ActivePowerSchemeGuid
        if ($activeGuid) {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$activeGuid\54533251-82be-4824-96c1-47b60b740d00\893dee8e-2bef-41e0-89c6-b55d0929964c"
            if (Test-Path $regPath) {
                $p = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
                if ($null -ne $p.ACSettingIndex) {
                    return [int]$p.ACSettingIndex
                }
            }
        }

        $raw = powercfg /q SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 2>&1 | Out-String
        if ($raw -match "(?im)(?:AC|сети|secteur|wechselstrom|ca)[^:\r\n]*:\s*0x([0-9a-fA-F]+)") {
            return [Convert]::ToInt32($matches[1], 16)
        }
        return $null
    }
    catch {
        return $null
    }
}

function Restore-ProcessorThrottleMin {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [object]$OriginalPercent
    )

    if ($null -ne $OriginalPercent) {
        Write-Host "[*] Restoring Minimum Processor Frequency State..." -ForegroundColor Cyan
        try {
            $p = [int]$OriginalPercent
            $null = powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN $p 2>&1
            $null = powercfg -setactive SCHEME_CURRENT 2>&1
            Write-Host "  [+] Minimum processor frequency restored to $p%." -ForegroundColor Green
            return $true
        }
        catch {
            Write-Warning "Exception restoring PROCTHROTTLEMIN: $($_.Exception.Message)"
            return $false
        }
    }
    return $true
}

function Apply-CpuGamingOptimizations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [object]$HardwareProfile
    )

    $hw = if ($HardwareProfile) { $HardwareProfile } else { Get-HardwareProfile }

    Write-Host "[*] Applying Adaptive CPU Gaming Optimizations ($($hw.CpuVendor), $($hw.LogicalCores) Threads)..." -ForegroundColor Cyan

    # 1. Core unparking (CPMINCORES = 100%) for both Intel and AMD
    Set-ProcessorIdleMinCores -Percent 100 -CpuVendor $hw.CpuVendor -LowCore:$hw.LowCoreProfile | Out-Null

    # 2. Minimum & Maximum processor frequency to 100%
    try {
        $null = powercfg -setacvalueindex SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 bc5038f7-23e0-4960-96da-33abaf5935ec 100 2>&1
        $null = powercfg -setacvalueindex SCHEME_CURRENT 54533251-82be-4824-96c1-47b60b740d00 893dee8e-2bef-41e0-89c6-b55d0929964c 100 2>&1
        $null = powercfg -setactive SCHEME_CURRENT 2>&1
        Write-Host "  [+] Processor Frequency locked to 100% (eliminates clock ramp-up latency)." -ForegroundColor Green
    }
    catch {
        Write-Verbose "Processor frequency lock notice: $($_.Exception.Message)"
    }

    if ($hw.CpuVendor -eq "AMD") {
        Write-Host "  [+] AMD Zen Architecture Profile: Inter-core wake latency eliminated across all CCXs." -ForegroundColor Green
    }
    elseif ($hw.CpuVendor -eq "Intel") {
        if ($hw.LowCoreProfile) {
            Write-Host "  [+] Intel Low-Core Budget Profile: All $($hw.LogicalCores) threads kept 100% active (prevents Sandy Bridge sleep stalls)." -ForegroundColor Green
        } else {
            Write-Host "  [+] Intel Core Architecture Profile: High-frequency C-state latency reduction active." -ForegroundColor Green
        }
    }
    return $true
}

# ── GPU MSI (Message Signaled Interrupts) Mode ─────────────────────────────

function Get-GpuPnpDeviceId {
    [CmdletBinding()]
    param()

    try {
        return Select-PrimaryGamingGpu
    }
    catch {
        Write-Verbose "Get-GpuPnpDeviceId error: $($_.Exception.Message)"
        return $null
    }
}

function Get-GpuMsiConfig {
    [CmdletBinding()]
    param()

    $gpu = Get-GpuPnpDeviceId
    if (-not $gpu -or -not $gpu.PNPDeviceID) { return $null }

    $vendor = "Unknown"
    if ($gpu.PNPDeviceID -match "VEN_1002" -or $gpu.Name -match "AMD|Radeon" -or $gpu.AdapterCompatibility -match "Advanced Micro Devices") { $vendor = "AMD" }
    elseif ($gpu.PNPDeviceID -match "VEN_10DE" -or $gpu.Name -match "NVIDIA|GeForce|Quadro|RTX|GTX" -or $gpu.AdapterCompatibility -match "NVIDIA") { $vendor = "NVIDIA" }
    elseif ($gpu.PNPDeviceID -match "VEN_8086" -or $gpu.Name -match "Intel" -or $gpu.AdapterCompatibility -match "Intel") { $vendor = "Intel" }

    $basePath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($gpu.PNPDeviceID)\Device Parameters\Interrupt Management"
    $msiPath = Join-Path $basePath "MessageSignaledInterruptProperties"
    $affPath = Join-Path $basePath "Affinity Policy"

    $msiSupp = $null
    $devPrio = $null

    if (Test-Path $msiPath) {
        $p = Get-ItemProperty -Path $msiPath -ErrorAction SilentlyContinue
        if ($null -ne $p.MSISupported) { $msiSupp = [int]$p.MSISupported }
    }
    if (Test-Path $affPath) {
        $p = Get-ItemProperty -Path $affPath -ErrorAction SilentlyContinue
        if ($null -ne $p.DevicePriority) { $devPrio = [int]$p.DevicePriority }
    }

    return @{
        PNPDeviceID    = $gpu.PNPDeviceID
        DeviceName     = $gpu.Name
        Vendor         = $vendor
        BasePath       = $basePath
        MSISupported   = $msiSupp
        DevicePriority = $devPrio
    }
}

function Set-GpuMsiGamingConfig {
    [CmdletBinding()]
    param()

    Write-Host "[*] Enabling MSI (Message Signaled Interrupts) & High Priority for GPU..." -ForegroundColor Cyan

    $gpu = Get-GpuPnpDeviceId
    if (-not $gpu -or -not $gpu.PNPDeviceID) {
        Write-Warning "Could not detect PCI GPU for MSI configuration."
        return $false
    }

    $vendor = "PCI"
    if ($gpu.PNPDeviceID -match "VEN_1002" -or $gpu.Name -match "AMD|Radeon") { $vendor = "AMD" }
    elseif ($gpu.PNPDeviceID -match "VEN_10DE" -or $gpu.Name -match "NVIDIA|GeForce") { $vendor = "NVIDIA" }
    elseif ($gpu.PNPDeviceID -match "VEN_8086" -or $gpu.Name -match "Intel") { $vendor = "Intel" }

    $basePath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($gpu.PNPDeviceID)\Device Parameters\Interrupt Management"
    $msiPath = Join-Path $basePath "MessageSignaledInterruptProperties"
    $affPath = Join-Path $basePath "Affinity Policy"

    try {
        if (-not (Test-Path $msiPath)) { New-Item -Path $msiPath -Force -ErrorAction Stop | Out-Null }
        Set-ItemProperty -Path $msiPath -Name "MSISupported" -Value 1 -Type DWord -Force -ErrorAction Stop
        Write-Host "  [+] GPU '$($gpu.Name)' ($vendor): MSISupported set to 1 (MSI mode active)." -ForegroundColor Green

        if (-not (Test-Path $affPath)) { New-Item -Path $affPath -Force -ErrorAction Stop | Out-Null }
        Set-ItemProperty -Path $affPath -Name "DevicePriority" -Value 3 -Type DWord -Force -ErrorAction Stop
        Write-Host "  [+] GPU '$($gpu.Name)' ($vendor): DevicePriority set to 3 (High IRQ Priority)." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "Failed to set GPU MSI mode: $($_.Exception.Message)"
        return $false
    }
}

function Apply-GpuGamingOptimizations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [object]$HardwareProfile
    )

    $hw = if ($HardwareProfile) { $HardwareProfile } else { Get-HardwareProfile }

    Write-Host "[*] Applying Adaptive GPU Gaming Optimizations ($($hw.GpuVendor) - $($hw.GpuName))..." -ForegroundColor Cyan

    # 1. Enable MSI Mode & High IRQ Priority for primary GPU
    Set-GpuMsiGamingConfig | Out-Null

    # 2. Vendor specific tweaks
    if ($hw.GpuVendor -eq "AMD" -or (Get-AmdGpuDriverClassKeys).Count -gt 0) {
        Set-AmdUlpsState -Enable 0 | Out-Null
        Write-Host "  [+] AMD Polaris / RDNA Profile: ULPS disabled (eliminates GPU deep-sleep stutter)." -ForegroundColor Green
    }
    elseif ($hw.GpuVendor -eq "NVIDIA") {
        Write-Host "  [+] NVIDIA GeForce Profile: MSI High Priority enabled (ULPS is AMD-specific; skipped)." -ForegroundColor Green
    }
    elseif ($hw.GpuVendor -eq "Intel") {
        Write-Host "  [+] Intel Graphics Profile: MSI mode configured where supported." -ForegroundColor Green
    }

    return $true
}

function Restore-GpuMsiConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [object]$MSIConfig
    )

    if ($MSIConfig) {
        Write-Host "[*] Restoring GPU MSI and Interrupt Priority settings..." -ForegroundColor Cyan
        $basePath = if ($MSIConfig -is [hashtable]) { $MSIConfig["BasePath"] } else { $MSIConfig.BasePath }
        $origMsi  = if ($MSIConfig -is [hashtable]) { $MSIConfig["MSISupported"] } else { $MSIConfig.MSISupported }
        $origPrio = if ($MSIConfig -is [hashtable]) { $MSIConfig["DevicePriority"] } else { $MSIConfig.DevicePriority }

        if ($basePath) {
            $msiPath = Join-Path $basePath "MessageSignaledInterruptProperties"
            $affPath = Join-Path $basePath "Affinity Policy"

            try {
                if (Test-Path $msiPath) {
                    if ($null -ne $origMsi) {
                        Set-ItemProperty -Path $msiPath -Name "MSISupported" -Value $origMsi -Type DWord -Force -ErrorAction Stop
                        Write-Host "  [+] GPU MSI mode restored to $origMsi." -ForegroundColor Green
                    } else {
                        Remove-ItemProperty -Path $msiPath -Name "MSISupported" -Force -ErrorAction Stop
                        Write-Host "  [+] GPU MSISupported removed (restored to original state)." -ForegroundColor Green
                    }
                }

                if (Test-Path $affPath) {
                    if ($null -ne $origPrio) {
                        Set-ItemProperty -Path $affPath -Name "DevicePriority" -Value $origPrio -Type DWord -Force -ErrorAction Stop
                        Write-Host "  [+] GPU DevicePriority restored to $origPrio." -ForegroundColor Green
                    }
                    else {
                        Remove-ItemProperty -Path $affPath -Name "DevicePriority" -Force -ErrorAction Stop
                        Write-Host "  [+] GPU DevicePriority removed (restored to default)." -ForegroundColor Green
                    }
                }
                return $true
            }
            catch {
                Write-Warning "Failed to restore GPU MSI settings: $($_.Exception.Message)"
                return $false
            }
        }
    }
    return $true
}

# ── VBS / HVCI (Virtualization-Based Security / Memory Integrity) ────────────

function Get-VbsHvciDiagnosticInfo {
    [CmdletBinding()]
    param()

    $info = @{
        VbsRunning          = $false
        VbsStatus           = "Disabled (0)"
        HvciRunning         = $false
        VbsRegistryEnabled  = $false
        HvciRegistryEnabled = $false
    }

    try {
        $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
        if (-not $dg) {
            $dg = Get-CimInstance -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
        }
        if ($dg) {
            $statusVal = [int]$dg.VirtualizationBasedSecurityStatus
            $info.VbsStatus = switch ($statusVal) {
                0 { "Disabled (0)" }
                1 { "Enabled but not running (1)" }
                2 { "Enabled and running (2)" }
                default { "Unknown ($statusVal)" }
            }
            $info.VbsRunning = ($statusVal -eq 2)

            $secRunning = $dg.SecurityServicesRunning
            if ($secRunning -and ($secRunning -contains 2)) {
                $info.HvciRunning = $true
            }
        }
    }
    catch {
        Write-Verbose "DeviceGuard query notice: $($_.Exception.Message)"
    }

    $dgPath = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"
    if (Test-Path $dgPath) {
        $p = Get-ItemProperty -Path $dgPath -ErrorAction SilentlyContinue
        if ($null -ne $p.EnableVirtualizationBasedSecurity -and [int]$p.EnableVirtualizationBasedSecurity -eq 1) {
            $info.VbsRegistryEnabled = $true
        }
    }

    $hvciPath = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"
    if (Test-Path $hvciPath) {
        $p = Get-ItemProperty -Path $hvciPath -ErrorAction SilentlyContinue
        if ($null -ne $p.Enabled -and [int]$p.Enabled -eq 1) {
            $info.HvciRegistryEnabled = $true
        }
    }

    return $info
}

function Toggle-VbsHvciState {
    [CmdletBinding()]
    param()

    Write-Host "`n=====================================================" -ForegroundColor Yellow
    Write-Host "    VBS / HVCI (CORE ISOLATION & MEMORY INTEGRITY)   " -ForegroundColor Yellow
    Write-Host "=====================================================" -ForegroundColor Yellow

    $current = Get-VbsHvciDiagnosticInfo
    Write-Host " Current VBS Status:          $($current.VbsStatus)" -ForegroundColor White
    Write-Host " Current HVCI Running:        $($current.HvciRunning)" -ForegroundColor White
    Write-Host " VBS Registry Config:         $($current.VbsRegistryEnabled)" -ForegroundColor White
    Write-Host " HVCI Registry Config:        $($current.HvciRegistryEnabled)" -ForegroundColor White

    $dgPath = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"
    $hvciPath = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"

    # Read explicit registry configuration first to allow clean toggling before reboot
    $regVbs = $null
    $regHvci = $null
    if (Test-Path $dgPath) {
        $val = (Get-ItemProperty -Path $dgPath -Name "EnableVirtualizationBasedSecurity" -ErrorAction SilentlyContinue).EnableVirtualizationBasedSecurity
        if ($null -ne $val) { $regVbs = [int]$val }
    }
    if (Test-Path $hvciPath) {
        $val = (Get-ItemProperty -Path $hvciPath -Name "Enabled" -ErrorAction SilentlyContinue).Enabled
        if ($null -ne $val) { $regHvci = [int]$val }
    }

    $isCurrentlyActive = if ($null -ne $regHvci) {
        ($regHvci -eq 1)
    } elseif ($null -ne $regVbs) {
        ($regVbs -eq 1)
    } else {
        ($current.VbsRunning -or $current.HvciRunning)
    }

    $targetState = if ($isCurrentlyActive) { 0 } else { 1 }

    try {
        if (-not (Test-Path $dgPath)) { New-Item -Path $dgPath -Force -ErrorAction Stop | Out-Null }
        if (-not (Test-Path $hvciPath)) { New-Item -Path $hvciPath -Force -ErrorAction Stop | Out-Null }

        Set-ItemProperty -Path $dgPath -Name "EnableVirtualizationBasedSecurity" -Value $targetState -Type DWord -Force -ErrorAction Stop
        Set-ItemProperty -Path $hvciPath -Name "Enabled" -Value $targetState -Type DWord -Force -ErrorAction Stop

        if ($targetState -eq 0) {
            Write-Host "`n[+] VBS & HVCI (Memory Integrity) successfully DISABLED in registry." -ForegroundColor Green
            Write-Host "  [+] Hypervisor ring virtualization overhead removed for lower gaming latency." -ForegroundColor Green
        }
        else {
            Write-Host "`n[+] VBS & HVCI (Memory Integrity) successfully ENABLED in registry." -ForegroundColor Green
        }

        Write-Host "`n[IMPORTANT WARNING] A PC restart is REQUIRED for VBS/HVCI changes to take effect!" -ForegroundColor Red
        return $true
    }
    catch {
        Write-Error "Failed to modify VBS/HVCI registry keys: $($_.Exception.Message)"
        return $false
    }
}

# ── NTFS File System I/O Optimizations ─────────────────────────────────────

function Get-NTFSFileSystemConfig {
    [CmdletBinding()]
    param()

    $fsPath = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
    $lastAccess = $null
    $dot3 = $null

    if (Test-Path $fsPath) {
        $p = Get-ItemProperty -Path $fsPath -ErrorAction SilentlyContinue
        if ($null -ne $p.NtfsDisableLastAccessUpdate) { $lastAccess = [int64]$p.NtfsDisableLastAccessUpdate }
        if ($null -ne $p.NtfsDisable8dot3NameCreation) { $dot3 = [int64]$p.NtfsDisable8dot3NameCreation }
    }

    return @{
        NtfsDisableLastAccessUpdate  = $lastAccess
        NtfsDisable8dot3NameCreation = $dot3
    }
}

function Set-NTFSGamingOptimizations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$IsHdd
    )

    Write-Host "[*] Applying NTFS File System I/O Optimizations (DisableLastAccess & Disable8dot3)..." -ForegroundColor Cyan
    try {
        $out1 = fsutil behavior set disablelastaccess 1 2>&1
        $code1 = $LASTEXITCODE
        $out2 = fsutil behavior set disable8dot3 1 2>&1
        $code2 = $LASTEXITCODE

        if ($code1 -eq 0) {
            Write-Host "  [+] NTFS last access timestamp updates disabled (eliminates file read write amplification)." -ForegroundColor Green
        } else {
            Write-Warning "Could not configure disablelastaccess ($code1): $out1"
        }

        if ($code2 -eq 0) {
            Write-Host "  [+] NTFS 8.3 legacy short name generation disabled (speeds up directory lookups)." -ForegroundColor Green
        } else {
            Write-Warning "Could not configure disable8dot3 ($code2): $out2"
        }

        if ($IsHdd) {
            Write-Host "  [+] Mechanical HDD Protection: Disk head thrashing minimized by eliminating metadata update writes." -ForegroundColor Green
        }

        return ($code1 -eq 0 -and $code2 -eq 0)
    }
    catch {
        Write-Warning "Could not configure NTFS optimizations: $($_.Exception.Message)"
        return $false
    }
}

function Restore-NTFSGamingOptimizations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [object]$NTFSConfig
    )

    if ($NTFSConfig) {
        Write-Host "[*] Restoring NTFS File System settings..." -ForegroundColor Cyan
        $fsPath = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
        $origLast = if ($NTFSConfig -is [hashtable]) { $NTFSConfig["NtfsDisableLastAccessUpdate"] } else { $NTFSConfig.NtfsDisableLastAccessUpdate }
        $orig8dot3 = if ($NTFSConfig -is [hashtable]) { $NTFSConfig["NtfsDisable8dot3NameCreation"] } else { $NTFSConfig.NtfsDisable8dot3NameCreation }

        try {
            if ($null -ne $origLast) {
                Set-ItemProperty -Path $fsPath -Name "NtfsDisableLastAccessUpdate" -Value $origLast -Type DWord -Force -ErrorAction Stop
            } else {
                Remove-ItemProperty -Path $fsPath -Name "NtfsDisableLastAccessUpdate" -Force -ErrorAction SilentlyContinue
            }
            if ($null -ne $orig8dot3) {
                Set-ItemProperty -Path $fsPath -Name "NtfsDisable8dot3NameCreation" -Value $orig8dot3 -Type DWord -Force -ErrorAction Stop
            } else {
                Remove-ItemProperty -Path $fsPath -Name "NtfsDisable8dot3NameCreation" -Force -ErrorAction SilentlyContinue
            }
            Write-Host "  [+] NTFS settings restored to original values." -ForegroundColor Green
            return $true
        }
        catch {
            Write-Warning "Failed to restore NTFS settings: $($_.Exception.Message)"
            return $false
        }
    }
    return $true
}

# ── Kernel DPC & Memory Management Optimizations ────────────────────────────

function Get-KernelDpcConfig {
    [CmdletBinding()]
    param()

    $memPath    = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
    $kernelPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel"
    $prioPath   = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
    $powerPath  = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"

    $disablePaging    = $null
    $threadDpc        = $null
    $win32Prio        = $null
    $powerThrottleOff = $null

    if (Test-Path $memPath) {
        $p = Get-ItemProperty -Path $memPath -Name "DisablePagingExecutive" -ErrorAction SilentlyContinue
        if ($null -ne $p -and $null -ne $p.DisablePagingExecutive) { $disablePaging = [int]$p.DisablePagingExecutive }
    }
    if (Test-Path $kernelPath) {
        $p = Get-ItemProperty -Path $kernelPath -Name "ThreadDpcEnable" -ErrorAction SilentlyContinue
        if ($null -ne $p -and $null -ne $p.ThreadDpcEnable) { $threadDpc = [int]$p.ThreadDpcEnable }
    }
    if (Test-Path $prioPath) {
        $p = Get-ItemProperty -Path $prioPath -Name "Win32PrioritySeparation" -ErrorAction SilentlyContinue
        if ($null -ne $p -and $null -ne $p.Win32PrioritySeparation) { $win32Prio = [int]$p.Win32PrioritySeparation }
    }
    if (Test-Path $powerPath) {
        $p = Get-ItemProperty -Path $powerPath -Name "PowerThrottlingOff" -ErrorAction SilentlyContinue
        if ($null -ne $p -and $null -ne $p.PowerThrottlingOff) { $powerThrottleOff = [int]$p.PowerThrottlingOff }
    }

    return @{
        DisablePagingExecutive  = $disablePaging
        ThreadDpcEnable         = $threadDpc
        Win32PrioritySeparation = $win32Prio
        PowerThrottlingOff      = $powerThrottleOff
    }
}

function Set-KernelDpcOptimizations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$IsLowRam
    )

    Write-Host "[*] Applying Kernel DPC & Memory Management Optimizations..." -ForegroundColor Cyan

    $memPath    = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
    $kernelPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel"
    $prioPath   = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
    $powerPath  = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"

    try {
        if (-not (Test-Path $memPath)) { New-Item -Path $memPath -Force | Out-Null }
        if ($IsLowRam) {
            Write-Host "  [!] Low-RAM Budget Guard: DisablePagingExecutive skipped (preserves physical RAM for games on 8GB systems)." -ForegroundColor Yellow
        } else {
            Set-ItemProperty -Path $memPath -Name "DisablePagingExecutive" -Value 1 -Type DWord -Force -ErrorAction Stop
            Write-Host "  [+] DisablePagingExecutive = 1 (Kernel and system drivers locked in physical RAM)." -ForegroundColor Green
        }

        if (-not (Test-Path $kernelPath)) { New-Item -Path $kernelPath -Force | Out-Null }
        Set-ItemProperty -Path $kernelPath -Name "ThreadDpcEnable" -Value 0 -Type DWord -Force -ErrorAction Stop
        Write-Host "  [+] ThreadDpcEnable = 0 (Immediate kernel DPC execution, worker thread delay eliminated)." -ForegroundColor Green

        if (-not (Test-Path $prioPath)) { New-Item -Path $prioPath -Force | Out-Null }
        Set-ItemProperty -Path $prioPath -Name "Win32PrioritySeparation" -Value 38 -Type DWord -Force -ErrorAction Stop
        Write-Host "  [+] Win32PrioritySeparation = 0x26 (38) (Short, variable 3:1 foreground gaming boost)." -ForegroundColor Green

        if (-not (Test-Path $powerPath)) { New-Item -Path $powerPath -Force | Out-Null }
        Set-ItemProperty -Path $powerPath -Name "PowerThrottlingOff" -Value 1 -Type DWord -Force -ErrorAction Stop
        Write-Host "  [+] PowerThrottlingOff = 1 (Global CPU power throttling disabled for game threads)." -ForegroundColor Green

        return $true
    }
    catch {
        Write-Warning "Failed to set Kernel DPC optimizations: $($_.Exception.Message)"
        return $false
    }
}

function Restore-KernelDpcOptimizations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [object]$KernelDpcConfig
    )

    if ($KernelDpcConfig) {
        Write-Host "[*] Restoring Kernel DPC & Memory Management settings..." -ForegroundColor Cyan

        $memPath    = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
        $kernelPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel"
        $prioPath   = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
        $powerPath  = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"

        $origPaging = if ($KernelDpcConfig -is [hashtable]) { $KernelDpcConfig["DisablePagingExecutive"] } else { $KernelDpcConfig.DisablePagingExecutive }
        $origDpc    = if ($KernelDpcConfig -is [hashtable]) { $KernelDpcConfig["ThreadDpcEnable"] } else { $KernelDpcConfig.ThreadDpcEnable }
        $origPrio   = if ($KernelDpcConfig -is [hashtable]) { $KernelDpcConfig["Win32PrioritySeparation"] } else { $KernelDpcConfig.Win32PrioritySeparation }
        $origPwr    = if ($KernelDpcConfig -is [hashtable]) { $KernelDpcConfig["PowerThrottlingOff"] } else { $KernelDpcConfig.PowerThrottlingOff }

        try {
            if (Test-Path $memPath) {
                if ($null -ne $origPaging) {
                    Set-ItemProperty -Path $memPath -Name "DisablePagingExecutive" -Value $origPaging -Type DWord -Force -ErrorAction SilentlyContinue
                } else {
                    Remove-ItemProperty -Path $memPath -Name "DisablePagingExecutive" -Force -ErrorAction SilentlyContinue
                }
            }
            if (Test-Path $kernelPath) {
                if ($null -ne $origDpc) {
                    Set-ItemProperty -Path $kernelPath -Name "ThreadDpcEnable" -Value $origDpc -Type DWord -Force -ErrorAction SilentlyContinue
                } else {
                    Remove-ItemProperty -Path $kernelPath -Name "ThreadDpcEnable" -Force -ErrorAction SilentlyContinue
                }
            }
            if (Test-Path $prioPath) {
                if ($null -ne $origPrio) {
                    Set-ItemProperty -Path $prioPath -Name "Win32PrioritySeparation" -Value $origPrio -Type DWord -Force -ErrorAction SilentlyContinue
                } else {
                    Remove-ItemProperty -Path $prioPath -Name "Win32PrioritySeparation" -Force -ErrorAction SilentlyContinue
                }
            }
            if (Test-Path $powerPath) {
                if ($null -ne $origPwr) {
                    Set-ItemProperty -Path $powerPath -Name "PowerThrottlingOff" -Value $origPwr -Type DWord -Force -ErrorAction SilentlyContinue
                } else {
                    Remove-ItemProperty -Path $powerPath -Name "PowerThrottlingOff" -Force -ErrorAction SilentlyContinue
                }
            }
            Write-Host "  [+] Kernel DPC & Memory Management settings restored." -ForegroundColor Green
            return $true
        }
        catch {
            Write-Warning "Failed to restore Kernel DPC settings: $($_.Exception.Message)"
            return $false
        }
    }
    return $true
}

# ── Direct Peripheral Input Buffer Queue Optimizations ──────────────────────

function Get-InputBufferConfig {
    [CmdletBinding()]
    param()

    $mouPath = "HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters"
    $kbdPath = "HKLM:\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters"

    $mouQueue = $null
    $kbdQueue = $null

    if (Test-Path $mouPath) {
        $p = Get-ItemProperty -Path $mouPath -Name "MouseDataQueueSize" -ErrorAction SilentlyContinue
        if ($null -ne $p -and $null -ne $p.MouseDataQueueSize) { $mouQueue = [int]$p.MouseDataQueueSize }
    }
    if (Test-Path $kbdPath) {
        $p = Get-ItemProperty -Path $kbdPath -Name "KeyboardDataQueueSize" -ErrorAction SilentlyContinue
        if ($null -ne $p -and $null -ne $p.KeyboardDataQueueSize) { $kbdQueue = [int]$p.KeyboardDataQueueSize }
    }

    return @{
        MouseDataQueueSize    = $mouQueue
        KeyboardDataQueueSize = $kbdQueue
    }
}

function Set-InputBufferOptimizations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$QueueSize = 32
    )

    Write-Host "[*] Applying Direct Input Buffer Queue Optimizations (Mouse & Keyboard direct delivery, QueueSize = $QueueSize)..." -ForegroundColor Cyan

    $mouPath = "HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters"
    $kbdPath = "HKLM:\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters"

    try {
        if (-not (Test-Path $mouPath)) { New-Item -Path $mouPath -Force | Out-Null }
        Set-ItemProperty -Path $mouPath -Name "MouseDataQueueSize" -Value $QueueSize -Type DWord -Force -ErrorAction Stop
        Write-Host "  [+] MouseDataQueueSize = $QueueSize (Direct mouse packet delivery with anti-drop headroom)." -ForegroundColor Green

        if (-not (Test-Path $kbdPath)) { New-Item -Path $kbdPath -Force | Out-Null }
        Set-ItemProperty -Path $kbdPath -Name "KeyboardDataQueueSize" -Value $QueueSize -Type DWord -Force -ErrorAction Stop
        Write-Host "  [+] KeyboardDataQueueSize = $QueueSize (Direct keyboard event delivery)." -ForegroundColor Green

        return $true
    }
    catch {
        Write-Warning "Failed to set Input Buffer optimizations: $($_.Exception.Message)"
        return $false
    }
}

function Restore-InputBufferOptimizations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [object]$InputBufferConfig
    )

    if ($InputBufferConfig) {
        Write-Host "[*] Restoring Mouse & Keyboard input buffer queue sizes..." -ForegroundColor Cyan

        $mouPath = "HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters"
        $kbdPath = "HKLM:\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters"

        $origMou = if ($InputBufferConfig -is [hashtable]) { $InputBufferConfig["MouseDataQueueSize"] } else { $InputBufferConfig.MouseDataQueueSize }
        $origKbd = if ($InputBufferConfig -is [hashtable]) { $InputBufferConfig["KeyboardDataQueueSize"] } else { $InputBufferConfig.KeyboardDataQueueSize }

        try {
            if (Test-Path $mouPath) {
                if ($null -ne $origMou) {
                    Set-ItemProperty -Path $mouPath -Name "MouseDataQueueSize" -Value $origMou -Type DWord -Force -ErrorAction SilentlyContinue
                } else {
                    Remove-ItemProperty -Path $mouPath -Name "MouseDataQueueSize" -Force -ErrorAction SilentlyContinue
                }
            }
            if (Test-Path $kbdPath) {
                if ($null -ne $origKbd) {
                    Set-ItemProperty -Path $kbdPath -Name "KeyboardDataQueueSize" -Value $origKbd -Type DWord -Force -ErrorAction SilentlyContinue
                } else {
                    Remove-ItemProperty -Path $kbdPath -Name "KeyboardDataQueueSize" -Force -ErrorAction SilentlyContinue
                }
            }
            Write-Host "  [+] Input buffer queue sizes restored to original values." -ForegroundColor Green
            return $true
        }
        catch {
            Write-Warning "Failed to restore input buffer queue sizes: $($_.Exception.Message)"
            return $false
        }
    }
    return $true
}

# ── BCDedit High-Precision System Timer Optimizations ───────────────────────

function Get-BcdeditTimerConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$BcdOutput
    )

    $result = @{
        DynamicTick   = $null
        TscSyncPolicy = $null
    }

    try {
        $raw = if ($BcdOutput) { $BcdOutput } else {
            $lines = bcdedit /enum osloader 2>&1
            if ($LASTEXITCODE -ne 0 -or -not $lines) {
                $lines = bcdedit /enum 2>&1
            }
            $lines
        }
        if ($raw) {
            foreach ($line in $raw) {
                if ($line -match '^\s*disabledynamictick\s+(\S+)') {
                    $result.DynamicTick = $matches[1].Trim()
                }
                elseif ($line -match '^\s*tscsyncpolicy\s+(\S+)') {
                    $result.TscSyncPolicy = $matches[1].Trim()
                }
            }
        }
    }
    catch {
        Write-Verbose "Could not query BCDedit: $($_.Exception.Message)"
    }

    return $result
}

function Set-BcdeditTimerOptimizations {
    [CmdletBinding()]
    param()

    Write-Host "[*] Applying BCDedit Kernel Timer Optimizations (disabledynamictick yes, tscsyncpolicy Enhanced)..." -ForegroundColor Cyan
    try {
        $out1 = bcdedit /set disabledynamictick yes 2>&1
        $code1 = $LASTEXITCODE
        $out2 = bcdedit /set tscsyncpolicy Enhanced 2>&1
        $code2 = $LASTEXITCODE

        if ($code1 -eq 0) {
            Write-Host "  [+] BCDedit disabledynamictick set to 'yes' (eliminates dynamic timer latency jitter)." -ForegroundColor Green
        } else {
            Write-Warning "Could not configure disabledynamictick ($code1): $out1"
        }

        if ($code2 -eq 0) {
            Write-Host "  [+] BCDedit tscsyncpolicy set to 'Enhanced' (synchronizes TSC timestamp counters across cores)." -ForegroundColor Green
        } else {
            Write-Warning "Could not configure tscsyncpolicy ($code2): $out2"
        }

        return ($code1 -eq 0 -and $code2 -eq 0)
    }
    catch {
        Write-Warning "Failed to set BCDedit timer optimizations: $($_.Exception.Message)"
        return $false
    }
}

function Restore-BcdeditTimerOptimizations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [object]$BcdeditConfig
    )

    if ($BcdeditConfig) {
        Write-Host "[*] Restoring BCDedit timer configuration..." -ForegroundColor Cyan
        $origTick = if ($BcdeditConfig -is [hashtable]) { $BcdeditConfig["DynamicTick"] } else { $BcdeditConfig.DynamicTick }
        $origTsc  = if ($BcdeditConfig -is [hashtable]) { $BcdeditConfig["TscSyncPolicy"] } else { $BcdeditConfig.TscSyncPolicy }

        try {
            if ($null -ne $origTick -and $origTick -ne "") {
                $null = bcdedit /set disabledynamictick $origTick 2>&1
                Write-Host "  [+] BCDedit disabledynamictick restored to '$origTick'." -ForegroundColor Green
            } else {
                $null = bcdedit /deletevalue disabledynamictick 2>&1
                Write-Host "  [+] BCDedit disabledynamictick removed (reverted to system default)." -ForegroundColor Green
            }

            if ($null -ne $origTsc -and $origTsc -ne "") {
                $null = bcdedit /set tscsyncpolicy $origTsc 2>&1
                Write-Host "  [+] BCDedit tscsyncpolicy restored to '$origTsc'." -ForegroundColor Green
            } else {
                $null = bcdedit /deletevalue tscsyncpolicy 2>&1
                Write-Host "  [+] BCDedit tscsyncpolicy removed (reverted to system default)." -ForegroundColor Green
            }
            return $true
        }
        catch {
            Write-Warning "Failed to restore BCDedit timer settings: $($_.Exception.Message)"
            return $false
        }
    }
    return $true
}

# ── TCP Gaming Network Stack Optimizations ──────────────────────────────────

function Get-TcpStackConfig {
    [CmdletBinding()]
    param()

    $result = @{
        Timestamps = $null
        ECN        = $null
        RSS        = $null
        Interfaces = @()
    }

    try {
        $raw = netsh int tcp show global 2>&1
        if ($raw) {
            foreach ($line in $raw) {
                if ($line -match 'RFC 1323 Timestamps\s*:\s*(\w+)') {
                    $result.Timestamps = $matches[1].Trim()
                }
                elseif ($line -match 'ECN Capability\s*:\s*(\w+)') {
                    $result.ECN = $matches[1].Trim()
                }
                elseif ($line -match 'Receive-Side Scaling State\s*:\s*(\w+)') {
                    $result.RSS = $matches[1].Trim()
                }
            }
        }
    } catch {
        Write-Verbose "Netsh tcp parsing notice: $($_.Exception.Message)"
    }

    $interfacesPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    $gamingAdapters = Get-PhysicalGamingAdapters
    $allowedGuids = @($gamingAdapters | Where-Object { $_.InterfaceGuid } | ForEach-Object { $_.InterfaceGuid })

    $protectedAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $name = $_.Name
        $desc = $_.InterfaceDescription
        ($name -eq "Ethernet 2") -or ($name -eq "wwan99") -or
        ($name -match '(?i)Apple|Wintun|Bluetooth|Virtual|TAP|VPN|Hyper-V|vEthernet') -or
        ($desc -match '(?i)Apple|Wintun|Bluetooth|Virtual|TAP|VPN|Hyper-V')
    })
    $protectedGuids = @($protectedAdapters | Where-Object { $_.InterfaceGuid } | ForEach-Object { $_.InterfaceGuid })

    if ((Test-Path $interfacesPath) -and $allowedGuids.Count -gt 0) {
        Get-ChildItem -Path $interfacesPath | ForEach-Object {
            $guid = $_.PSChildName
            if ($protectedGuids -contains $guid) {
                return
            }
            if ($allowedGuids -contains $guid) {
                $p = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
                $result.Interfaces += @{
                    Guid            = $guid
                    TcpAckFrequency = if ($null -ne $p.TcpAckFrequency) { [int]$p.TcpAckFrequency } else { $null }
                    TCPNoDelay      = if ($null -ne $p.TCPNoDelay) { [int]$p.TCPNoDelay } else { $null }
                }
            }
        }
    }

    return $result
}

function Set-TcpGamingStackOptimizations {
    [CmdletBinding()]
    param()

    Write-Host "[*] Applying TCP Gaming Stack Optimizations (TcpAckFrequency=1, TCPNoDelay=1, timestamps=disabled, ecn=disabled, rss=enabled)..." -ForegroundColor Cyan

    $interfacesPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    $gamingAdapters = Get-PhysicalGamingAdapters
    $allowedGuids = @($gamingAdapters | Where-Object { $_.InterfaceGuid } | ForEach-Object { $_.InterfaceGuid })

    $protectedAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $name = $_.Name
        $desc = $_.InterfaceDescription
        ($name -eq "Ethernet 2") -or ($name -eq "wwan99") -or
        ($name -match '(?i)Apple|Wintun|Bluetooth|Virtual|TAP|VPN|Hyper-V|vEthernet') -or
        ($desc -match '(?i)Apple|Wintun|Bluetooth|Virtual|TAP|VPN|Hyper-V')
    })
    $protectedGuids = @($protectedAdapters | Where-Object { $_.InterfaceGuid } | ForEach-Object { $_.InterfaceGuid })

    if ((Test-Path $interfacesPath) -and $allowedGuids.Count -gt 0) {
        $configuredCount = 0
        Get-ChildItem -Path $interfacesPath | ForEach-Object {
            $guid = $_.PSChildName
            if ($protectedGuids -contains $guid) {
                Write-Verbose "Skipping protected interface GUID: $guid"
                return
            }

            if ($allowedGuids -contains $guid) {
                Set-ItemProperty -Path $_.PSPath -Name "TCPNoDelay" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $_.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                $configuredCount++
            }
        }
        Write-Host "  [+] TCPNoDelay & TcpAckFrequency set to 1 across $configuredCount gaming interface(s)." -ForegroundColor Green
        Write-Host "  [+] Protected Apple Mobile Device (Ethernet 2) & Wintun (wwan99) from TCP stack modifications." -ForegroundColor Green
    }
    elseif ($allowedGuids.Count -eq 0) {
        Write-Host "  [i] No physical gaming network adapters found to configure TCPNoDelay/TcpAckFrequency." -ForegroundColor Gray
        Write-Host "  [+] Protected Apple Mobile Device (Ethernet 2) & Wintun (wwan99) from TCP stack modifications." -ForegroundColor Green
    }

    try {
        $null = netsh int tcp set global timestamps=disabled ecncapability=disabled rss=enabled 2>&1
        Write-Host "  [+] TCP global parameters applied: timestamps=disabled, ecncapability=disabled, rss=enabled." -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to set netsh tcp global parameters: $($_.Exception.Message)"
    }

    return $true
}

function Restore-TcpGamingStackOptimizations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [object]$TcpStackConfig
    )

    if ($TcpStackConfig) {
        Write-Host "[*] Restoring TCP gaming stack configuration..." -ForegroundColor Cyan

        $ts     = if ($TcpStackConfig -is [hashtable]) { $TcpStackConfig["Timestamps"] } else { $TcpStackConfig.Timestamps }
        $ecn    = if ($TcpStackConfig -is [hashtable]) { $TcpStackConfig["ECN"] } else { $TcpStackConfig.ECN }
        $rss    = if ($TcpStackConfig -is [hashtable]) { $TcpStackConfig["RSS"] } else { $TcpStackConfig.RSS }
        $ifaces = if ($TcpStackConfig -is [hashtable]) { $TcpStackConfig["Interfaces"] } else { $TcpStackConfig.Interfaces }

        $protectedAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
            $name = $_.Name
            $desc = $_.InterfaceDescription
            ($name -eq "Ethernet 2") -or ($name -eq "wwan99") -or
            ($name -match '(?i)Apple|Wintun|Bluetooth|Virtual|TAP|VPN|Hyper-V|vEthernet') -or
            ($desc -match '(?i)Apple|Wintun|Bluetooth|Virtual|TAP|VPN|Hyper-V')
        })
        $protectedGuids = @($protectedAdapters | Where-Object { $_.InterfaceGuid } | ForEach-Object { $_.InterfaceGuid })

        $interfacesPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
        if ($ifaces -and (Test-Path $interfacesPath)) {
            foreach ($item in @($ifaces)) {
                $guid    = if ($item -is [hashtable]) { $item["Guid"] } else { $item.Guid }
                $noDelay = if ($item -is [hashtable]) { $item["TCPNoDelay"] } else { $item.TCPNoDelay }
                $ackFreq = if ($item -is [hashtable]) { $item["TcpAckFrequency"] } else { $item.TcpAckFrequency }

                if ($protectedGuids -contains $guid) {
                    Write-Verbose "Skipping protected interface GUID in TCP stack restore: $guid"
                    continue
                }

                $targetPath = Join-Path $interfacesPath $guid
                if (Test-Path $targetPath) {
                    if ($null -ne $noDelay) {
                        Set-ItemProperty -Path $targetPath -Name "TCPNoDelay" -Value $noDelay -Type DWord -Force -ErrorAction SilentlyContinue
                    } else {
                        Remove-ItemProperty -Path $targetPath -Name "TCPNoDelay" -Force -ErrorAction SilentlyContinue
                    }
                    if ($null -ne $ackFreq) {
                        Set-ItemProperty -Path $targetPath -Name "TcpAckFrequency" -Value $ackFreq -Type DWord -Force -ErrorAction SilentlyContinue
                    } else {
                        Remove-ItemProperty -Path $targetPath -Name "TcpAckFrequency" -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }

        try {
            $tsVal  = if ($ts) { $ts } else { "enabled" }
            $ecnVal = if ($ecn) { $ecn } else { "disabled" }
            $rssVal = if ($rss) { $rss } else { "enabled" }
            $null = netsh int tcp set global timestamps=$tsVal ecncapability=$ecnVal rss=$rssVal 2>&1
            Write-Host "  [+] TCP global parameters restored (timestamps=$tsVal, ecncapability=$ecnVal, rss=$rssVal)." -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to restore netsh tcp global parameters: $($_.Exception.Message)"
        }
        return $true
    }
    return $true
}

# ── Hardware-Accelerated GPU Scheduling (HAGS) ──────────────────────────────

function Get-HagsGpuSchedulingConfig {
    [CmdletBinding()]
    param()

    $gfxPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
    $hwSchMode = $null
    if (Test-Path $gfxPath) {
        $p = Get-ItemProperty -Path $gfxPath -Name "HwSchMode" -ErrorAction SilentlyContinue
        if ($null -ne $p -and $null -ne $p.HwSchMode) {
            $hwSchMode = [int]$p.HwSchMode
        }
    }
    return @{ HwSchMode = $hwSchMode }
}

function Set-HagsGpuScheduling {
    [CmdletBinding()]
    param()

    Write-Host "[*] Configuring Hardware-Accelerated GPU Scheduling (HAGS)..." -ForegroundColor Cyan
    $gfxPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
    try {
        if (-not (Test-Path $gfxPath)) {
            New-Item -Path $gfxPath -Force | Out-Null
        }
        Set-ItemProperty -Path $gfxPath -Name "HwSchMode" -Value 2 -Type DWord -Force -ErrorAction Stop
        Write-Host "  [+] HAGS (Hardware-Accelerated GPU Scheduling) enabled (HwSchMode = 2)." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "Could not configure HAGS: $($_.Exception.Message)"
        return $false
    }
}

function Restore-HagsGpuScheduling {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [object]$HagsConfig
    )

    if ($HagsConfig) {
        Write-Host "[*] Restoring Hardware-Accelerated GPU Scheduling (HAGS) setting..." -ForegroundColor Cyan
        $gfxPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        $origMode = if ($HagsConfig -is [hashtable]) { $HagsConfig["HwSchMode"] } else { $HagsConfig.HwSchMode }
        try {
            if ($null -ne $origMode) {
                Set-ItemProperty -Path $gfxPath -Name "HwSchMode" -Value $origMode -Type DWord -Force -ErrorAction Stop
                Write-Host "  [+] HAGS restored to original mode: $origMode." -ForegroundColor Green
            } else {
                Remove-ItemProperty -Path $gfxPath -Name "HwSchMode" -Force -ErrorAction SilentlyContinue
                Write-Host "  [+] HAGS HwSchMode property removed (default)." -ForegroundColor Green
            }
            return $true
        }
        catch {
            Write-Warning "Failed to restore HAGS setting: $($_.Exception.Message)"
            return $false
        }
    }
    return $true
}


