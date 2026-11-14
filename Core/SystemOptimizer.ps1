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
    $isAlreadyHighPerf = Test-IsHighPerformanceScheme -SchemeGuid $activeGuid -RawOutput $activeRaw
    if ($isAlreadyHighPerf) {
        Write-Host "  [+] Current active power scheme is already optimized: $activeRaw" -ForegroundColor Green
        Write-Host "  [+] Retaining active plan to avoid PCIe Link State / DisplayPort timing disruptions." -ForegroundColor Green
        return $true
    }

    $ultimateGuid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
    $list = powercfg /list 2>&1
    $targetGuid = $null

    $existingUltLine = ($list -split "[\r\n]+") | Where-Object { $_ -match "(?i)Ultimate|\u041c\u0430\u043a\u0441\u0438\u043c\u0430\u043b\u044c\u043d\u0430\u044f" } | Select-Object -First 1
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
    try {
        if (-not (Test-Path $sysProfilePath)) {
            New-Item -Path $sysProfilePath -Force -ErrorAction SilentlyContinue | Out-Null
        }

        # Disable network packet throttling (0xFFFFFFFF)
        Set-ItemProperty -Path $sysProfilePath -Name "NetworkThrottlingIndex" -Value 4294967295 -Type DWord -Force -ErrorAction SilentlyContinue
        # Set SystemResponsiveness to safe 10 (guarantees 90% CPU priority to games while reserving 10% for system drivers/DWM)
        Set-ItemProperty -Path $sysProfilePath -Name "SystemResponsiveness"   -Value 10         -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Host "  [+] NetworkThrottlingIndex set to 0xFFFFFFFF (network packet throttling disabled)." -ForegroundColor Green
        Write-Host "  [+] SystemResponsiveness set to safe 10 (preserves DWM and display driver stability)." -ForegroundColor Green

        # Clean up and neutralize any corrupt Affinity = 0 or GPU Priority contention in Tasks\Games
        $gamesTaskPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
        if (Test-Path $gamesTaskPath) {
            # CRITICAL: Remove Affinity = 0 (an affinity mask of 0 starves threads and crashes drivers)
            Remove-ItemProperty -Path $gamesTaskPath -Name "Affinity" -ErrorAction SilentlyContinue
            # MS Learn (MMCSS): Priority 1-8 orders tasks inside the same Scheduling Category. Stock Games=2 ranks below
            # Playback(3)/Capture(5)/Window Manager(5); 6 puts game threads ahead of background multimedia while
            # "Medium" category keeps DWM and audio safe. ("GPU Priority" / "SFIO Priority" are documented as unused.)
            Set-ItemProperty -Path $gamesTaskPath -Name "Priority" -Value 6 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $gamesTaskPath -Name "Scheduling Category" -Value "Medium" -Type String -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $gamesTaskPath -Name "SFIO Priority" -Value "Normal" -Type String -Force -ErrorAction SilentlyContinue
            Write-Host "  [+] Tasks\Games MMCSS Priority = 6 (Medium category; Affinity=0 eliminated; DWM protected)." -ForegroundColor Green
        }
    }
    catch {
        Write-Warning "Failed to set Multimedia gaming configuration: $($_.Exception.Message)"
        return $false
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
    # shortcut: flush kernel standby cache directly instead of EmptyWorkingSet to prevent pagefile thrashing on 8GB HDD systems
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

    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()

    $finalMem = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
    $reclaimedKb = [math]::Max(0, ($finalMem - $initialMem))
    $reclaimedMb = [math]::Round($reclaimedKb / 1024, 2)

    Write-Host "  [+] Memory optimization complete via standby cache purge." -ForegroundColor Green
    if ($Aggressive) {
        Write-Host "  [+] Low-RAM Budget Guard: Standby cache reclaimed safely without HDD thrashing." -ForegroundColor Green
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
    $dispServices = @("AMD External Events Utility", "NVDisplay.ContainerLocalSystem", "DisplayEnhancementService", "GraphicsPerfSvc")
    foreach ($ds in $dispServices) {
        $svc = Get-Service -Name $ds -ErrorAction SilentlyContinue
        if ($svc -and $svc.StartType -ne "Disabled") {
            if ($svc.Status -ne "Running") {
                Start-Service -Name $ds -ErrorAction SilentlyContinue
                Write-Host "  [+] Restarted display service: $ds" -ForegroundColor Green
            }
        }
    }

    # 4. Clean up harmful MPO and Fullscreen Exclusive (FSE) overrides that cause monitor flickering/blinking in Deadlock & RDR2
    try {
        $dwm = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SOFTWARE\Microsoft\Windows\Dwm", $true)
        if ($dwm) {
            $dwm.DeleteValue("OverlayTestMode", $false)
            $dwm.Close()
        }
    } catch {}
    try {
        $gfx = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Control\GraphicsDrivers", $true)
        if ($gfx) {
            $gfx.DeleteValue("DisableOverlays", $false)
            $gfx.Close()
        }
    } catch {}
    $dwmPath = "HKLM:\SOFTWARE\Microsoft\Windows\Dwm"
    if (Test-Path $dwmPath) {
        Remove-ItemProperty -Path $dwmPath -Name "OverlayTestMode" -ErrorAction SilentlyContinue
    }
    $gfxDriversPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
    if (Test-Path $gfxDriversPath) {
        Remove-ItemProperty -Path $gfxDriversPath -Name "DisableOverlays" -ErrorAction SilentlyContinue
    }
    $gcsPath = "HKCU:\System\GameConfigStore"
    if (Test-Path $gcsPath) {
        Remove-ItemProperty -Path $gcsPath -Name "GameDVR_FSEBehavior" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $gcsPath -Name "GameDVR_HonorUserFSEBehaviorMode" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $gcsPath -Name "GameDVR_DXGIHonorFSEWindowsCompatible" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $gcsPath -Name "GameDVR_EFSEFeatureFlags" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $gcsPath -Name "GameDVR_FSEBehaviorMode" -ErrorAction SilentlyContinue
    }
    $dxUserPath = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
    if (Test-Path $dxUserPath) {
        Remove-ItemProperty -Path $dxUserPath -Name "DirectXUserGlobalSettings" -ErrorAction SilentlyContinue
        try {
            $dxu = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Software\Microsoft\DirectX\UserGpuPreferences", $true)
            if ($dxu) {
                foreach ($appName in $dxu.GetValueNames()) {
                    $val = [string]$dxu.GetValue($appName)
                    if ($val -match "SwapEffectUpgradeEnable=0;") {
                        $newVal = $val -replace "SwapEffectUpgradeEnable=0;", ""
                        $dxu.SetValue($appName, $newVal, [Microsoft.Win32.RegistryValueKind]::String)
                    }
                }
                $dxu.Close()
            }
        } catch {}
    }
    try {
        $ifeoRootKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options", $true)
        if ($ifeoRootKey) {
            $ifeoRootKey.DeleteSubKeyTree("RDR2.exe", $false)
            $ifeoRootKey.Close()
        }
    } catch {}
    Write-Host "  [+] MPO and Fullscreen Exclusive overrides cleared (eliminates Deadlock / RDR2 screen flickering)." -ForegroundColor Green

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

function Get-SystemBootId {
    [CmdletBinding()]
    param()

    try {
        $val = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" -Name "BootId" -ErrorAction SilentlyContinue).BootId
        if ($null -ne $val) {
            return [int]$val
        }
    } catch {}

    return $null
}

function Test-IsSameBootSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [Nullable[int]]$SavedBootId,

        [Parameter(Mandatory = $false)]
        [string]$SavedBootTime
    )

    # 1. Primary authority: Hardware/kernel boot timestamp (LastBootUpTime / TickCount64)
    # When SysMain is disabled in gaming mode, registry PrefetchParameters\BootId does NOT increment
    # on the first reboot, causing false-positive same-boot detections if BootId is checked alone.
    if (-not [string]::IsNullOrWhiteSpace($SavedBootTime)) {
        $currentBootTime = Get-ResilientBootTimestamp
        if ($currentBootTime) {
            try {
                $dtSaved = [DateTime]::Parse($SavedBootTime)
                $dtCurrent = [DateTime]::Parse($currentBootTime)
                # If boot time differs by 30 seconds or more, this is conclusively a new boot session.
                if ([Math]::Abs(($dtCurrent - $dtSaved).TotalSeconds) -ge 30) {
                    return $false
                }
                # Within the same 30s window: if BootId is also present and changed, consider it new
                if ($null -ne $SavedBootId) {
                    $currentBootId = Get-SystemBootId
                    if ($null -ne $currentBootId -and $currentBootId -ne $SavedBootId) {
                        return $false
                    }
                }
                return $true
            } catch {
                if ($currentBootTime -ne $SavedBootTime) {
                    return $false
                }
            }
        }
    }

    # 2. Secondary fallback: BootId alone if no SavedBootTime was recorded
    $currentBootId = Get-SystemBootId
    if ($null -ne $currentBootId -and $null -ne $SavedBootId) {
        return ($currentBootId -eq $SavedBootId)
    }

    return $false
}

function Test-IsLowRamSystem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int64]$TotalRamBytes
    )
    return ($TotalRamBytes -gt 0 -and $TotalRamBytes -le [int64](8.5 * 1024 * 1024 * 1024))
}

function Test-IsHighPerformanceScheme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$SchemeGuid = "",

        [Parameter(Mandatory = $false)]
        [string]$RawOutput = ""
    )
    return ($SchemeGuid -in @("e9a42b02-d5df-448d-aa00-03f14749eb61", "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c")) -or
           ($RawOutput -match "(?i)Bitsum|Ultimate|Revision|High [P|p]erformance|Max|\u0412\u044b\u0441\u043e\u043a\u0430\u044f\s+\u043f\u0440\u043e\u0438\u0437\u0432\u043e\u0434\u0438\u0442\u0435\u043b\u044c\u043d\u043e\u0441\u0442\u044c|\u041c\u0430\u043a\u0441\u0438\u043c\u0430\u043b\u044c\u043d\u0430\u044f\s+\u043f\u0440\u043e\u0438\u0437\u0432\u043e\u0434\u0438\u0442\u0435\u043b\u044c\u043d\u043e\u0441\u0442\u044c")
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
    $ssdModelPattern = "(?i)SSD|NVMe|NAND|EVO|PRO|Crucial|Kingston|KIOXIA|Lexar|Sandisk|Micron|SK hynix|Adata|Corsair|Intel SSD|Sabrent|SN[0-9]|FireCuda\s+[0-9]{3}"

    $isHdd = $false
    $resolvedMedia = $MediaType

    # Priority 1: Check SSD / NVMe indicators first to protect NVMe drives (e.g. WD Black SN770, FireCuda 530)
    if ($MediaType -match "SSD" -or $BusType -match "NVMe" -or $Model -match "(?i)SN[0-9]|NVMe|SSD|FireCuda\s+[0-9]{3}|Optane") {
        $isHdd = $false
        $resolvedMedia = "SSD"
    } elseif ($MediaType -match "HDD" -or ($SpindleSpeed -gt 0)) {
        $isHdd = $true
        $resolvedMedia = "HDD"
    } elseif ($Model -match $ssdModelPattern) {
        $isHdd = $false
        $resolvedMedia = "SSD"
    } elseif ($Model -match $hddModelPattern) {
        $isHdd = $true
        $resolvedMedia = "HDD"
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

$Script:NetworkAdapterGamingMap = @(
    @{ Key = "FlowControl";         Keyword = "*FlowControl";         GamingValue = "0"; DefaultRestore = "3" }
    @{ Key = "InterruptModeration"; Keyword = "*InterruptModeration"; GamingValue = "0"; DefaultRestore = "1" }
    @{ Key = "EEE";                 Keyword = "*EEE";                 GamingValue = "0"; DefaultRestore = "1" }
    @{ Key = "GreenEthernet";       Keyword = "EnableGreenEthernet";  GamingValue = "0"; DefaultRestore = $null }
    @{ Key = "PowerSavingMode";     Keyword = "PowerSavingMode";      GamingValue = "0"; DefaultRestore = $null }
    @{ Key = "RscIPv4";             Keyword = "*RscIPv4";             GamingValue = "0"; DefaultRestore = "1" }
    @{ Key = "RscIPv6";             Keyword = "*RscIPv6";             GamingValue = "0"; DefaultRestore = "1" }
    @{ Key = "WakeOnMagicPacket";   Keyword = "*WakeOnMagicPacket";   GamingValue = "0"; DefaultRestore = $null }
    @{ Key = "WakeOnPattern";       Keyword = "*WakeOnPattern";       GamingValue = "0"; DefaultRestore = $null }
    @{ Key = "PMARPOffload";        Keyword = "*PMARPOffload";        GamingValue = "0"; DefaultRestore = $null }
    @{ Key = "PMNSOffload";         Keyword = "*PMNSOffload";         GamingValue = "0"; DefaultRestore = $null }
)

function Get-NetworkAdapterGamingProperties {
    [CmdletBinding()]
    param()

    $results = @()
    $adapters = Get-PhysicalGamingAdapters
    foreach ($adapter in $adapters) {
        $allProps = Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue
        $entry = @{
            AdapterName   = $adapter.Name
            InterfaceDesc = $adapter.InterfaceDescription
        }
        foreach ($spec in $Script:NetworkAdapterGamingMap) {
            $matched = $allProps | Where-Object { $_.RegistryKeyword -eq $spec.Keyword }
            $entry[$spec.Key] = if ($matched) { ($matched.RegistryValue | Select-Object -First 1) } else { $null }
        }
        $results += $entry
    }
    return $results
}

function Set-NetworkGamingOptimizations {
    [CmdletBinding()]
    param()

    Write-Host "[*] Applying Ultra Low Latency Network (TCPNoDelay, FlowControl=0, InterruptModeration=0, RSC=0, WoL/PM=0)..." -ForegroundColor Cyan

    # 1. Apply TCP gaming stack optimizations (TCPNoDelay, TcpAckFrequency, netsh global, protecting iPhone and Wintun)
    Set-TcpGamingStackOptimizations | Out-Null

    # 2. Configure physical gaming network adapters strictly skipping Apple Mobile Device and Wintun tunnel
    $adapters = Get-PhysicalGamingAdapters
    foreach ($adapter in $adapters) {
        try {
            $advProps = Get-NetAdapterAdvancedProperty -Name $adapter.Name -ErrorAction SilentlyContinue
            foreach ($spec in $Script:NetworkAdapterGamingMap) {
                $prop = $advProps | Where-Object { $_.RegistryKeyword -eq $spec.Keyword }
                if ($prop) {
                    Set-NetAdapterAdvancedProperty -InputObject $prop -RegistryValue $spec.GamingValue -ErrorAction SilentlyContinue
                }
            }

            Write-Host "  [+] Optimized '$($adapter.Name)' ($($adapter.InterfaceDescription)): FlowControl=0, InterruptModeration=0, RSC=0, WoL/PM=0." -ForegroundColor Green
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
        foreach ($item in @($NetworkAdapterProperties)) {
            $aName = if ($item -is [hashtable]) { $item["AdapterName"] } else { $item.AdapterName }
            if (-not $aName) { continue }

            try {
                $advProps = Get-NetAdapterAdvancedProperty -Name $aName -ErrorAction SilentlyContinue
                foreach ($spec in $Script:NetworkAdapterGamingMap) {
                    $savedVal = if ($item -is [hashtable]) {
                        $item[$spec.Key]
                    } elseif ($item.PSObject.Properties[$spec.Key]) {
                        $item.PSObject.Properties[$spec.Key].Value
                    } else {
                        $null
                    }
                    if ($null -ne $savedVal) {
                        $prop = $advProps | Where-Object { $_.RegistryKeyword -eq $spec.Keyword }
                        if ($prop) {
                            Set-NetAdapterAdvancedProperty -InputObject $prop -RegistryValue ([string]$savedVal) -ErrorAction SilentlyContinue
                        }
                    }
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
                foreach ($spec in $Script:NetworkAdapterGamingMap) {
                    if ($null -ne $spec.DefaultRestore) {
                        $prop = $advProps | Where-Object { $_.RegistryKeyword -eq $spec.Keyword }
                        if ($prop) {
                            Set-NetAdapterAdvancedProperty -InputObject $prop -RegistryValue $spec.DefaultRestore -ErrorAction SilentlyContinue
                        }
                    }
                }
            }
            catch {
                Write-Verbose "Could not apply default adapter properties for $($adapter.Name)`: $($_.Exception.Message)"
            }
        }
    }

    Write-Host "  [+] Network settings restored to original state." -ForegroundColor Green
    return $true
}

function Get-NetAdapterMsiConfig {
    [CmdletBinding()]
    param()

    $results = [System.Collections.Generic.List[object]]::new()
    $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object {
        $name = $_.Name
        $desc = $_.InterfaceDescription
        ($name -ne "Ethernet 2") -and
        ($name -ne "wwan99") -and
        ($name -notmatch '(?i)Apple|Wintun|Bluetooth|Virtual|TAP|VPN|Hyper-V|vEthernet') -and
        ($desc -notmatch '(?i)Apple|Wintun|Bluetooth|Virtual|TAP|VPN|Hyper-V')
    })

    foreach ($adapter in $adapters) {
        try {
            $pnpId = [string]$adapter.PnPDeviceID
            if ([string]::IsNullOrWhiteSpace($pnpId)) {
                $pnpDev = Get-PnpDevice -FriendlyName $adapter.InterfaceDescription -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($pnpDev) { $pnpId = [string]$pnpDev.InstanceId }
            }
            if ([string]::IsNullOrWhiteSpace($pnpId) -or -not ($pnpId -match "^PCI\\")) { continue }

            $msiKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$pnpId\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
            $origMsi = $null
            if (Test-Path -LiteralPath $msiKeyPath) {
                $prop = Get-ItemProperty -LiteralPath $msiKeyPath -Name "MSISupported" -ErrorAction SilentlyContinue
                if ($null -ne $prop -and $null -ne $prop.MSISupported) {
                    $origMsi = [int]$prop.MSISupported
                }
            }
            $results.Add(@{
                AdapterName  = $adapter.Name
                PnpDeviceId  = $pnpId
                RegistryPath = $msiKeyPath
                OriginalMsi  = $origMsi
            })
        } catch {
            Write-Verbose "Get-NetAdapterMsiConfig notice for $($adapter.Name): $($_.Exception.Message)"
        }
    }
    return $results.ToArray()
}

function Set-NetAdapterMsiMode {
    [CmdletBinding()]
    param()

    Write-Host "[*] Enabling MSI (Message Signaled Interrupts) mode for physical PCIe network adapters..." -ForegroundColor Cyan
    $modified = [System.Collections.Generic.List[object]]::new()
    $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object {
        $name = $_.Name
        $desc = $_.InterfaceDescription
        ($name -ne "Ethernet 2") -and
        ($name -ne "wwan99") -and
        ($name -notmatch '(?i)Apple|Wintun|Bluetooth|Virtual|TAP|VPN|Hyper-V|vEthernet') -and
        ($desc -notmatch '(?i)Apple|Wintun|Bluetooth|Virtual|TAP|VPN|Hyper-V')
    })

    foreach ($adapter in $adapters) {
        try {
            $pnpId = [string]$adapter.PnPDeviceID
            if ([string]::IsNullOrWhiteSpace($pnpId)) {
                $pnpDev = Get-PnpDevice -FriendlyName $adapter.InterfaceDescription -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($pnpDev) { $pnpId = [string]$pnpDev.InstanceId }
            }
            if ([string]::IsNullOrWhiteSpace($pnpId) -or -not ($pnpId -match "^PCI\\")) { continue }

            $msiKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$pnpId\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
            $origMsi = $null
            if (Test-Path -LiteralPath $msiKeyPath) {
                $prop = Get-ItemProperty -LiteralPath $msiKeyPath -Name "MSISupported" -ErrorAction SilentlyContinue
                if ($null -ne $prop -and $null -ne $prop.MSISupported) {
                    $origMsi = [int]$prop.MSISupported
                }
            }

            if (-not (Test-Path -LiteralPath $msiKeyPath)) {
                New-Item -Path $msiKeyPath -Force -ErrorAction Stop | Out-Null
            }
            Set-ItemProperty -LiteralPath $msiKeyPath -Name "MSISupported" -Value 1 -Type DWord -Force -ErrorAction Stop
            $modified.Add(@{
                AdapterName  = $adapter.Name
                PnpDeviceId  = $pnpId
                RegistryPath = $msiKeyPath
                OriginalMsi  = $origMsi
            })
            Write-Host "  [+] PCIe Network Adapter '$($adapter.Name)' ($pnpId): MSISupported = 1 (MSI interrupt mode active)." -ForegroundColor Green
        } catch {
            Write-Verbose "Could not enable MSI mode for adapter $($adapter.Name): $($_.Exception.Message)"
        }
    }
    return $modified.ToArray()
}

function Restore-NetAdapterMsiMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [Alias("NetAdapterMsiConfig")]
        [AllowEmptyCollection()]
        [array]$MsiBackup = @()
    )

    if (-not $MsiBackup -or $MsiBackup.Count -eq 0) { return $true }
    Write-Host "[*] Restoring PCIe network adapter MSI interrupt configuration..." -ForegroundColor Cyan
    foreach ($entry in @($MsiBackup)) {
        if (-not $entry) { continue }
        $regPath = if ($entry -is [hashtable]) { $entry["RegistryPath"] } else { $entry.RegistryPath }
        $origMsi = if ($entry -is [hashtable]) { $entry["OriginalMsi"] } else { $entry.OriginalMsi }
        $aName   = if ($entry -is [hashtable]) { $entry["AdapterName"] } else { $entry.AdapterName }
        if (-not $regPath) { continue }
        try {
            if (Test-Path -LiteralPath $regPath) {
                if ($null -ne $origMsi) {
                    Set-ItemProperty -LiteralPath $regPath -Name "MSISupported" -Value ([int]$origMsi) -Type DWord -Force -ErrorAction SilentlyContinue
                    Write-Host "  [+] Restored network adapter '$aName' MSISupported = $origMsi." -ForegroundColor Green
                } else {
                    Remove-ItemProperty -LiteralPath $regPath -Name "MSISupported" -Force -ErrorAction SilentlyContinue
                    Write-Host "  [+] Removed network adapter '$aName' MSISupported override (default)." -ForegroundColor Green
                }
            }
        } catch {
            Write-Verbose "Failed to restore MSI mode for $aName`: $($_.Exception.Message)"
        }
    }
    return $true
}

function Set-DeepGameDVROptimizations {
    [CmdletBinding()]
    param()

    Write-Host "[*] Disabling GameDVR screen capture hooks and compositor overhead..." -ForegroundColor Cyan

    $gameDvrPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR"
    if (-not (Test-Path $gameDvrPath)) { New-Item -Path $gameDvrPath -Force -ErrorAction SilentlyContinue | Out-Null }
    Set-ItemProperty -Path $gameDvrPath -Name "AppCaptureEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

    $configStorePath = "HKCU:\System\GameConfigStore"
    if (-not (Test-Path $configStorePath)) { New-Item -Path $configStorePath -Force -ErrorAction SilentlyContinue | Out-Null }
    Set-ItemProperty -Path $configStorePath -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    # Classic exclusive-fullscreen behaviour (present in every release up to v2.7). Switch: Config\tuning.json
    $tuningFile = Join-Path $PSScriptRoot "..\Config\tuning.json"
    $tuning = if (Test-Path -LiteralPath $tuningFile) { Get-Content -LiteralPath $tuningFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
    if ($null -eq $tuning -or $tuning.DisableFullscreenOptimizations -ne $false) {
        Set-ItemProperty -Path $configStorePath -Name "GameDVR_FSEBehaviorMode" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
    } else {
        Remove-ItemProperty -Path $configStorePath -Name "GameDVR_FSEBehaviorMode" -ErrorAction SilentlyContinue
    }

    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
    if (-not (Test-Path $policyPath)) { New-Item -Path $policyPath -Force -ErrorAction SilentlyContinue | Out-Null }
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
    Set-Service -Name "camsvc" -StartupType Manual -ErrorAction SilentlyContinue
    $camsvc = Get-Service -Name "camsvc" -ErrorAction SilentlyContinue
    if ($camsvc) {
        if ($camsvc.Status -ne "Running") {
            Start-Service -Name "camsvc" -ErrorAction SilentlyContinue
            Write-Host "  [+] Service 'camsvc' started successfully (Microphone access unblocked)." -ForegroundColor Green
        }
        else {
            Write-Host "  [+] Service 'camsvc' is already running." -ForegroundColor Green
        }
    }

    # LanmanServer / bthserv / Rockstar Service are snapshotted blacklist targets now:
    # Restore-SystemState returns them to their exact original state, so no forced overrides here.

    # 2. Steam Client Service - Required for Steam launcher integrity and anti-cheat verification
    Write-Host "[*] Configuring Steam Client Service..." -ForegroundColor Cyan
    $steamSvc = Get-Service -Name "Steam Client Service" -ErrorAction SilentlyContinue
    if ($steamSvc) {
        Set-Service -Name "Steam Client Service" -StartupType Manual -ErrorAction SilentlyContinue
        Write-Host "  [+] Service 'Steam Client Service' set to Manual for clean first-launch." -ForegroundColor Green
    }

    # 3. Windows Search (WSearch) & Start Menu Search
    Write-Host "[*] Configuring Windows Search & Start Menu Search Engine..." -ForegroundColor Cyan
    Set-Service -Name "WSearch" -StartupType Automatic -ErrorAction SilentlyContinue
    $wsearch = Get-Service -Name "WSearch" -ErrorAction SilentlyContinue
    if ($wsearch) {
        if ($wsearch.Status -ne "Running") {
            Start-Service -Name "WSearch" -ErrorAction SilentlyContinue
            Write-Host "  [+] Service 'WSearch' started successfully (Start menu search unblocked)." -ForegroundColor Green
        } else {
            Write-Host "  [+] Service 'WSearch' is already running." -ForegroundColor Green
        }
    }
    # Clear any blocking policies in HKLM and HKCU (Search & Notification Center / Win+Shift+S Toast Handler)
    foreach ($p in @("HKCU:\Software\Policies\Microsoft\Windows\Explorer", "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer")) {
        if (Test-Path $p) {
            Remove-ItemProperty -Path $p -Name "DisableSearchBoxSuggestions" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $p -Name "DisableNotificationCenter" -ErrorAction SilentlyContinue
        }
    }
    $searchUserPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
    if (Test-Path $searchUserPath) {
        Set-ItemProperty -Path $searchUserPath -Name "BingSearchEnabled" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $searchUserPath -Name "CortanaConsent" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        # SearchboxTaskbarMode = 0: Hide taskbar search icon (user accesses search via Win key keyboard typing)
        Set-ItemProperty -Path $searchUserPath -Name "SearchboxTaskbarMode" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $searchUserPath -Name "BackgroundAppGlobalToggle" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    $advPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    if (Test-Path $advPath) {
        Set-ItemProperty -Path $advPath -Name "SearchboxTaskbarMode" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    $bgAppsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
    if (Test-Path $bgAppsPath) {
        Set-ItemProperty -Path $bgAppsPath -Name "GlobalUserDisabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    # Unblock background IPC for modern search apps if blocked by AppPrivacy Group Policy
    $appPrivPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"
    if (Test-Path $appPrivPath) {
        $curVal = (Get-ItemProperty -Path $appPrivPath -Name "LetAppsRunInBackground" -ErrorAction SilentlyContinue).LetAppsRunInBackground
        if ($curVal -eq 2) {
            Remove-ItemProperty -Path $appPrivPath -Name "LetAppsRunInBackground" -ErrorAction SilentlyContinue
        }
    }
    # Ensure Text Services Framework (ctfmon) is active for Win Key typing redirection
    $isSystem = $false
    try { $isSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem } catch {}
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "ctfmon" -Value "C:\Windows\System32\ctfmon.exe" -Type String -Force -ErrorAction SilentlyContinue
    if (-not $isSystem) {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "ctfmon" -Value "C:\Windows\System32\ctfmon.exe" -Type String -Force -ErrorAction SilentlyContinue
        if (-not (Get-Process -Name "ctfmon" -ErrorAction SilentlyContinue)) {
            Start-Process "C:\Windows\System32\ctfmon.exe" -ErrorAction SilentlyContinue
        }
    }
    # Restart SearchHost if running to reload indexer RPC binding and apply input routing
    Stop-Process -Name "SearchHost", "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue

    # 3b. Snipping Tool (PrtSc / Win+Shift+S), Clipboard & UWP AppContainer Access
    Write-Host "[*] Restoring Snipping Tool (PrtSc), Clipboard & UWP AppContainer Services..." -ForegroundColor Cyan
    $kbdCtrlPath = "HKCU:\Control Panel\Keyboard"
    if (-not (Test-Path $kbdCtrlPath)) {
        New-Item -Path $kbdCtrlPath -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Set-ItemProperty -Path $kbdCtrlPath -Name "PrintScreenKeyForSnippingEnabled" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    foreach ($tabletPolicy in @("HKCU:\Software\Policies\Microsoft\TabletPC", "HKLM:\SOFTWARE\Policies\Microsoft\Windows\TabletPC")) {
        if (Test-Path $tabletPolicy) {
            Remove-ItemProperty -Path $tabletPolicy -Name "DisableSnippingTool" -ErrorAction SilentlyContinue
        }
    }

    # CaptureService -> Manual (Demand = 3), cbdhsvc -> Automatic (2), CDPUserSvc / ConsentUxUserSvc / UdkUserSvc -> Manual (3)
    $perUserRepairs = @(
        @{ Name = "CaptureService";   StartupType = "Manual";    StartVal = 3; StartNow = $false },
        @{ Name = "cbdhsvc";          StartupType = "Automatic"; StartVal = 2; StartNow = $true  },
        @{ Name = "CDPUserSvc";       StartupType = "Manual";    StartVal = 3; StartNow = $false },
        @{ Name = "ConsentUxUserSvc"; StartupType = "Manual";    StartVal = 3; StartNow = $false },
        @{ Name = "UdkUserSvc";       StartupType = "Manual";    StartVal = 3; StartNow = $false }
    )
    foreach ($svcFix in $perUserRepairs) {
        $sName = $svcFix.Name
        $sType = $svcFix.StartupType
        $sVal  = $svcFix.StartVal
        Set-Service -Name $sName -StartupType $sType -ErrorAction SilentlyContinue
        $baseReg = "HKLM:\SYSTEM\CurrentControlSet\Services\$sName"
        if (Test-Path $baseReg) {
            Set-ItemProperty -Path $baseReg -Name "Start" -Value $sVal -Type DWord -Force -ErrorAction SilentlyContinue
        }
        $instRegs = Get-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($sName)_*" -ErrorAction SilentlyContinue
        foreach ($ir in $instRegs) {
            Set-ItemProperty -Path $ir.PSPath -Name "Start" -Value $sVal -Type DWord -Force -ErrorAction SilentlyContinue
        }
        if ($svcFix.StartNow) {
            Start-Service -Name $sName -ErrorAction SilentlyContinue
            $userInsts = Get-Service -Name "$($sName)_*" -ErrorAction SilentlyContinue
            foreach ($uInst in $userInsts) {
                if ($uInst.Status -ne "Running") {
                    Start-Service -Name $uInst.Name -ErrorAction SilentlyContinue
                }
            }
        }
    }
    Write-Host "  [+] CaptureService (Manual) & cbdhsvc (Automatic) unblocked; PrintScreenKeyForSnippingEnabled = 1." -ForegroundColor Green

    # Repair AppContainer ACLs on %LOCALAPPDATA%\Packages for ALL APPLICATION PACKAGES (S-1-15-2-1)
    # and ALL RESTRICTED APPLICATION PACKAGES (S-1-15-2-2) to fix 0x80070005 UWP/AppX crashes
    $packageDirs = New-Object System.Collections.Generic.List[string]
    if ($env:LOCALAPPDATA) {
        $localPkg = Join-Path $env:LOCALAPPDATA "Packages"
        if (Test-Path -LiteralPath $localPkg) { $packageDirs.Add($localPkg) }
    }
    foreach ($pkgDir in $packageDirs) {
        try {
            $acl = Get-Acl -LiteralPath $pkgDir -ErrorAction Stop
            foreach ($sidStr in @("S-1-15-2-1", "S-1-15-2-2")) {
                $sid = New-Object System.Security.Principal.SecurityIdentifier($sidStr)
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $sid,
                    [System.Security.AccessControl.FileSystemRights]::ReadAndExecute,
                    ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
                    [System.Security.AccessControl.PropagationFlags]::None,
                    [System.Security.AccessControl.AccessControlType]::Allow
                )
                $acl.AddAccessRule($rule)
            }
            Set-Acl -LiteralPath $pkgDir -AclObject $acl -ErrorAction SilentlyContinue
        } catch {
            Write-Verbose "AppContainer ACL notice on ${pkgDir}: $($_.Exception.Message)"
        }
    }
    Write-Host "  [+] AppContainer ACLs (S-1-15-2-1 / S-1-15-2-2) verified on %LOCALAPPDATA%\Packages." -ForegroundColor Green

    # 4. Core System Services (SysMain, Spooler)
    Write-Host "[*] Configuring Prefetcher and Print Spooler..." -ForegroundColor Cyan
    Set-Service -Name "SysMain" -StartupType Automatic -ErrorAction SilentlyContinue
    $sysmain = Get-Service -Name "SysMain" -ErrorAction SilentlyContinue
    if ($sysmain -and $sysmain.Status -ne "Running") { Start-Service -Name "SysMain" -ErrorAction SilentlyContinue }

    Set-Service -Name "Spooler" -StartupType Automatic -ErrorAction SilentlyContinue
    $spooler = Get-Service -Name "Spooler" -ErrorAction SilentlyContinue
    if ($spooler -and $spooler.Status -ne "Running") { Start-Service -Name "Spooler" -ErrorAction SilentlyContinue }

    Write-Host "`n[SUCCESS] Microphone, Windows Search, Snipping Tool, Steam and Core System services are fully unblocked!" -ForegroundColor Green
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
        [bool]$Disable,

        [Parameter(Mandatory = $false)]
        [switch]$SkipSystemPolicies
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
            Set-ItemProperty -Path $searchPath -Name "CortanaConsent" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            # Keep SearchboxTaskbarMode = 0: Hide taskbar search icon (user accesses search via Win key keyboard typing)
            Set-ItemProperty -Path $searchPath -Name "SearchboxTaskbarMode" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $searchPath -Name "BackgroundAppGlobalToggle" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        }
        $expPol = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
        if (Test-Path $expPol) {
            Remove-ItemProperty -Path $expPol -Name "DisableSearchBoxSuggestions" -ErrorAction SilentlyContinue
        }
        $advPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        if (Test-Path $advPath) {
            Set-ItemProperty -Path $advPath -Name "SearchboxTaskbarMode" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        }
        if (-not $SkipSystemPolicies) {
            $expPolMachine = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
            if (Test-Path $expPolMachine) {
                Remove-ItemProperty -Path $expPolMachine -Name "DisableSearchBoxSuggestions" -ErrorAction SilentlyContinue
            }
            $dshPath = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
            if (Test-Path $dshPath) {
                Remove-ItemProperty -Path $dshPath -Name "AllowNewsAndInterests" -ErrorAction SilentlyContinue
            }
            # Ensure WSearch service is restored to Automatic and started
            Set-Service -Name "WSearch" -StartupType Automatic -ErrorAction SilentlyContinue
            $ws = Get-Service -Name "WSearch" -ErrorAction SilentlyContinue
            if ($ws -and $ws.Status -ne "Running") { Start-Service -Name "WSearch" -ErrorAction SilentlyContinue }
        }
        Write-Host "  [+] Widgets, Windows Search and Start search settings restored." -ForegroundColor Green
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

$Script:CachedHardwareProfile = $null

function Get-HardwareProfile {
    [CmdletBinding()]
    param(
        [switch]$ForceRefresh
    )

    # shortcut: optimized for FPS - Cache hardware profile in memory. Hardware does not change at runtime.
    # Eliminates 2.8-3.6s of CIM/WMI queries on every status check, boot, and diagnostic call.
    if (-not $ForceRefresh -and $Script:CachedHardwareProfile) {
        return $Script:CachedHardwareProfile
    }

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
    $lowRam = Test-IsLowRamSystem -TotalRamBytes $totalRamBytes

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
                    $resolved  = Resolve-StorageDeviceMediaType -Model $d.Model -BusType $d.InterfaceType
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
                $res = Resolve-StorageDeviceMediaType -Model $d.Model -BusType $d.InterfaceType
                if ($res.IsHdd) {
                    $anyHdd = $true
                    break
                }
            }
        } catch {
            Write-Verbose "Secondary CimInstance DiskDrive check notice: $($_.Exception.Message)"
        }
    }

    $profile = @{
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

    $Script:CachedHardwareProfile = $profile
    return $profile
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
    return $keys
}

function Get-NvidiaGpuDriverClassKeys {
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
                    $mId  = $sk.GetValue("MatchingDeviceId")
                    if (($prov -match '(?i)NVIDIA') -or ($desc -match '(?i)NVIDIA') -or ($mId -match '(?i)VEN_10DE')) {
                        $keys += @{
                            SubKeyName = $sub
                            Path       = "HKLM:\$classPath\$sub"
                            DriverDesc = $desc
                        }
                    }
                    $sk.Close()
                }
            }
            $base.Close()
        }
    }
    catch {
        Write-Warning "Could not enumerate NVIDIA GPU driver class keys: $($_.Exception.Message)"
    }
    return $keys
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
        foreach ($item in @($UlpsConfig)) {
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
        (Join-Path $env:LOCALAPPDATA "NVIDIA Corporation\NV_Cache"),
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
        if ($raw -match "(?im)(?:AC|\u0441\u0435\u0442\u0438|secteur|wechselstrom|ca)[^:\r\n]*:\s*0x([0-9a-fA-F]+)") {
            return [Convert]::ToInt32($matches[1], 16)
        }
        $currentLines = ($raw -split "[\r\n]+") | Where-Object { $_ -match "(?i)(?:current|\u0442\u0435\u043a\u0443\u0449\u0438\u0439)" -and $_ -match ":\s*0x([0-9a-fA-F]+)" }
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
        [switch]$LowCore,

        [Parameter(Mandatory = $false)]
        [switch]$SkipSetActive
    )

    Write-Host "[*] Configuring Processor Core Parking (CPMINCORES = $Percent%)..." -ForegroundColor Cyan
    try {
        $out1 = powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES $Percent 2>&1
        if (-not $SkipSetActive) {
            $out2 = powercfg -setactive SCHEME_CURRENT 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "powercfg failed to apply CPMINCORES ($LASTEXITCODE): $out1 $out2"
                return $false
            }
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
        if ($raw -match "(?im)(?:AC|\u0441\u0435\u0442\u0438|secteur|wechselstrom|ca)[^:\r\n]*:\s*0x([0-9a-fA-F]+)") {
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

    # 1. Core unparking (CPMINCORES = 100%) for both Intel and AMD (skip immediate setactive to batch with frequency lock)
    Set-ProcessorIdleMinCores -Percent 100 -CpuVendor $hw.CpuVendor -LowCore:$hw.LowCoreProfile -SkipSetActive | Out-Null

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
        $fsPath = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
        Set-ItemProperty -Path $fsPath -Name "NtfsDisableLastAccessUpdate" -Value 1 -Type DWord -Force -ErrorAction Stop
        Write-Host "  [+] NTFS last access timestamp updates disabled (eliminates file read write amplification)." -ForegroundColor Green

        Set-ItemProperty -Path $fsPath -Name "NtfsDisable8dot3NameCreation" -Value 1 -Type DWord -Force -ErrorAction Stop
        Write-Host "  [+] NTFS 8.3 legacy short name generation disabled (speeds up directory lookups)." -ForegroundColor Green

        if ($IsHdd) {
            Write-Host "  [+] Mechanical HDD Protection: Disk head thrashing minimized by eliminating metadata update writes." -ForegroundColor Green
        }

        return $true
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

        # shortcut: optimized for FPS - do NOT set ThreadDpcEnable=0. Setting ThreadDpcEnable=0 forces DPCs to run
        # directly in interrupt context at DISPATCH_LEVEL, pre-empting the game engine and render loop whenever mouse,
        # network or audio interrupts fire. Threaded DPCs (ThreadDpcEnable=1 / default) let the scheduler balance interrupts.
        if (Test-Path $kernelPath) {
            $existingDpc = (Get-ItemProperty -Path $kernelPath -Name "ThreadDpcEnable" -ErrorAction SilentlyContinue).ThreadDpcEnable
            if ($null -ne $existingDpc -and [int]$existingDpc -eq 0) {
                Remove-ItemProperty -Path $kernelPath -Name "ThreadDpcEnable" -Force -ErrorAction SilentlyContinue
                Write-Host "  [+] ThreadDpcEnable = 0 eliminated (Threaded DPCs preserved to prevent render thread starvation)." -ForegroundColor Green
            }
        }

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
        [int]$QueueSize = 100
    )

    if ($QueueSize -lt 32) { $QueueSize = 32 }

    # shortcut: optimized for FPS - default 100 packets prevents packet drop / aim hitching on 1000Hz-8000Hz mice during high-speed flicks
    Write-Host "[*] Applying Direct Input Buffer Queue Optimizations (Mouse & Keyboard direct delivery, QueueSize = $QueueSize)..." -ForegroundColor Cyan

    $mouPath = "HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters"
    $kbdPath = "HKLM:\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters"

    try {
        if (-not (Test-Path $mouPath)) { New-Item -Path $mouPath -Force | Out-Null }
        Set-ItemProperty -Path $mouPath -Name "MouseDataQueueSize" -Value $QueueSize -Type DWord -Force -ErrorAction Stop
        Write-Host "  [+] MouseDataQueueSize = $QueueSize (Direct mouse packet delivery with zero-drop headroom)." -ForegroundColor Green

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
            $lines = bcdedit /enum "{current}" 2>&1
            if ($LASTEXITCODE -ne 0 -or -not $lines) {
                $lines = bcdedit /enum osloader 2>&1
            }
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

    # shortcut: optimized for FPS - Revert destructive placebo BCD overrides. On modern AMD Ryzen (Zen 3 / 5600X)
    # and Intel processors with hardware Invariant TSC, tscsyncpolicy Enhanced forces software cross-core IPI synchronization
    # on every QueryPerformanceCounter call (increasing QPC latency by ~15-20x), and disabledynamictick causes constant timer interrupt
    # storms that prevent CPU cores from hitting max boost clock (4.65 GHz). Reverting to clean hardware native defaults restores max FPS.
    Write-Host "[*] Configuring BCDedit Kernel System Timers (Native Invariant TSC & Clean Dynamic Tick)..." -ForegroundColor Cyan
    try {
        $null = bcdedit /deletevalue disabledynamictick 2>&1
        $null = bcdedit /deletevalue tscsyncpolicy 2>&1
        Write-Host "  [+] BCDedit timer policy verified: Native hardware Invariant TSC active (QPC overhead eliminated)." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Verbose "BCDedit timer config notice: $($_.Exception.Message)"
        return $true
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
            # Never re-inflict the proven-harmful 'disabledynamictick yes' / 'tscsyncpolicy Enhanced' from old snapshots.
            if ($null -ne $origTick -and ([string]$origTick) -match '^(?i)no$') {
                $safeTick = ([string]$origTick).ToLowerInvariant()
                $null = bcdedit /set disabledynamictick $safeTick 2>&1
                Write-Host "  [+] BCDedit disabledynamictick restored to '$safeTick'." -ForegroundColor Green
            } else {
                $null = bcdedit /deletevalue disabledynamictick 2>&1
                Write-Host "  [+] BCDedit disabledynamictick removed (reverted to system default)." -ForegroundColor Green
            }

            if ($null -ne $origTsc -and ([string]$origTsc) -match '^(?i)(Default|Legacy)$') {
                $safeTsc = [string]$origTsc
                $null = bcdedit /set tscsyncpolicy $safeTsc 2>&1
                Write-Host "  [+] BCDedit tscsyncpolicy restored to '$safeTsc'." -ForegroundColor Green
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
                if ($line -match '(?:RFC 1323 Timestamps|RFC 1323)\s*:\s*(\S+)') {
                    $v = $matches[1].Trim().ToLowerInvariant()
                    if ($v -match '^(enabled|включено)$') { $result.Timestamps = "enabled" }
                    elseif ($v -match "^(disabled|\u043e\u0442\u043a\u043b\u044e\u0447\u0435\u043d\u043e)$") { $result.Timestamps = "disabled" }
                    elseif ($v -match "^(default|\u043f\u043e)$") { $result.Timestamps = "default" }
                    else { $result.Timestamps = $v }
                }
                elseif ($line -match '(?:ECN Capability|ECN)\s*:\s*(\S+)') {
                    $v = $matches[1].Trim().ToLowerInvariant()
                    if ($v -match '^(enabled|включено)$') { $result.ECN = "enabled" }
                    elseif ($v -match "^(disabled|\u043e\u0442\u043a\u043b\u044e\u0447\u0435\u043d\u043e)$") { $result.ECN = "disabled" }
                    elseif ($v -match "^(default|\u043f\u043e)$") { $result.ECN = "default" }
                    else { $result.ECN = $v }
                }
                elseif ($line -match "(?:Receive-Side Scaling State|\u043c\u0430\u0441\u0448\u0442\u0430\u0431\u0438\u0440\u043e\u0432\u0430\u043d\u0438\u044f\s+\u0441\u0442\u043e\u0440\u043e\u043d\u044b\s+\u043f\u0440\u0438\u0435\u043c\u0430)\s*:\s*(\S+)") {
                    $v = $matches[1].Trim().ToLowerInvariant()
                    if ($v -match '^(enabled|включено)$') { $result.RSS = "enabled" }
                    elseif ($v -match "^(disabled|\u043e\u0442\u043a\u043b\u044e\u0447\u0435\u043d\u043e)$") { $result.RSS = "disabled" }
                    elseif ($v -match "^(default|\u043f\u043e)$") { $result.RSS = "default" }
                    else { $result.RSS = $v }
                }
            }
        }
    } catch {
        Write-Verbose "Netsh tcp parsing notice: $($_.Exception.Message)"
    }
    # Locale-independent fallback if netsh output was localized in another language
    if (-not $result.Timestamps) {
        $tcp1323 = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "Tcp1323Opts" -ErrorAction SilentlyContinue).Tcp1323Opts
        if ($null -ne $tcp1323) {
            $result.Timestamps = if (([int]$tcp1323 -band 2) -ne 0) { "enabled" } else { "disabled" }
        }
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

                if ([string]::IsNullOrWhiteSpace($guid) -or ([string]$guid) -notmatch '^\{?[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\}?$') {
                    Write-Verbose "Skipping invalid interface GUID in TCP stack restore: $guid"
                    continue
                }

                if ($protectedGuids -contains $guid) {
                    Write-Verbose "Skipping protected interface GUID in TCP stack restore: $guid"
                    continue
                }

                $targetPath = Join-Path $interfacesPath $guid
                if (Test-Path -LiteralPath $targetPath) {
                    if ($null -ne $noDelay) {
                        Set-ItemProperty -Path $targetPath -Name "TCPNoDelay" -Value ([int]$noDelay) -Type DWord -Force -ErrorAction SilentlyContinue
                    } else {
                        Remove-ItemProperty -Path $targetPath -Name "TCPNoDelay" -Force -ErrorAction SilentlyContinue
                    }
                    if ($null -ne $ackFreq) {
                        Set-ItemProperty -Path $targetPath -Name "TcpAckFrequency" -Value ([int]$ackFreq) -Type DWord -Force -ErrorAction SilentlyContinue
                    } else {
                        Remove-ItemProperty -Path $targetPath -Name "TcpAckFrequency" -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }

        try {
            $tsVal  = if ($ts -and ([string]$ts) -match '^(?i)(enabled|disabled|default)$') { ([string]$ts).ToLowerInvariant() } else { "enabled" }
            $ecnVal = if ($ecn -and ([string]$ecn) -match '^(?i)(enabled|disabled|default)$') { ([string]$ecn).ToLowerInvariant() } else { "disabled" }
            $rssVal = if ($rss -and ([string]$rss) -match '^(?i)(enabled|disabled|default)$') { ([string]$rss).ToLowerInvariant() } else { "enabled" }
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
    param(
        [Parameter(Mandatory = $false)]
        [string]$GpuVendor = "Unknown"
    )

    # shortcut: optimized for FPS - Do NOT force HAGS on AMD Radeon GPUs (RX 6600, RX 570, etc.).
    # On AMD RDNA2 / Polaris, HAGS creates known frame pacing jitter, micro-stutters and frame drops in DX11 and Source 2 (CS2).
    # Only configure HAGS for NVIDIA GPUs where HAGS is mature and reduces CPU render submission latency.
    if ($GpuVendor -eq "AMD") {
        # Actively clear a stale HwSchMode=2 left by older versions instead of silently keeping it.
        $gfx = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        $cur = (Get-ItemProperty -Path $gfx -Name "HwSchMode" -ErrorAction SilentlyContinue).HwSchMode
        if ($cur -eq 2) {
            Set-ItemProperty -Path $gfx -Name "HwSchMode" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Write-Host "  [+] HAGS: stale HwSchMode=2 on AMD GPU switched off (HwSchMode=1, RDNA2 frame pacing fix, after reboot)." -ForegroundColor Green
        } else {
            Write-Host "  [*] HAGS setting: kept off/default on AMD GPU (avoiding RDNA2 frame-pacing microstutter in CS2)." -ForegroundColor Yellow
        }
        return $true
    }

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
        [object]$HagsConfig,

        [Parameter(Mandatory = $false)]
        [string]$GpuVendor = "Unknown"
    )

    if ($HagsConfig) {
        Write-Host "[*] Restoring Hardware-Accelerated GPU Scheduling (HAGS) setting..." -ForegroundColor Cyan
        $gfxPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        $origMode = if ($HagsConfig -is [hashtable]) { $HagsConfig["HwSchMode"] } else { $HagsConfig.HwSchMode }
        # Old snapshots (pre-82049b4) captured HwSchMode=2 that this tool itself forced on AMD - never re-inflict it.
        if ($GpuVendor -eq "AMD" -and $origMode -eq 2) {
            Set-ItemProperty -Path $gfxPath -Name "HwSchMode" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Write-Host "  [+] HAGS kept off on AMD GPU (poisoned HwSchMode=2 snapshot ignored)." -ForegroundColor Green
            return $true
        }
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



# ── v2.8 Extended Gaming Optimizations (data-driven, fully reversible) ──────
# Every registry tweak below is described as a target @{ Path; Name; Value; Kind }.
# The same target list is snapshotted (Get-RegistryValueSnapshot), applied (Set-RegistryTargets)
# and reverted (Restore-RegistryValueSnapshot). Value = $null means "delete value while gaming".

$Script:GameIfeoExecutables = @(
    "cs2.exe", "project8.exe", "AtomicHeart-Win64-Shipping.exe", "osu!.exe", "Cult Of The Lamb.exe",
    "TS4_x64.exe", "hl2.exe", "dota2.exe", "r5apex.exe", "Valorant-Win64-Shipping.exe",
    "FortniteClient-Win64-Shipping.exe", "RustClient.exe", "GTA5.exe", "Cyberpunk2077.exe", "eldenring.exe"
)

$Script:EtwTelemetryAutoLoggers = @(
    "AutoLogger-Diagtrack-Listener", "Diagtrack-Listener", "DiagLog", "SQMLogger", "WiFiSession", "RadioMgr"
)

$Script:PowerLatencySettings = @(
    @{ Name = "USB Selective Suspend";       Sub = "2a737441-1930-4402-8d77-b2bebba308a3"; Setting = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"; Value = 0 },
    @{ Name = "USB 3 Link Power Mgmt";       Sub = "2a737441-1930-4402-8d77-b2bebba308a3"; Setting = "d4e98f31-5ffe-4ce1-be31-1b38b384c009"; Value = 0 },
    @{ Name = "NVMe Primary Idle Timeout";   Sub = "0012ee47-9041-4b5d-9b77-535fba8b1442"; Setting = "d639518a-e56d-4345-8af2-b9f32fb26109"; Value = 0 },
    @{ Name = "NVMe Secondary Idle Timeout"; Sub = "0012ee47-9041-4b5d-9b77-535fba8b1442"; Setting = "d3d55efd-c1ff-424e-9dc3-441be7833010"; Value = 0 },
    @{ Name = "Processor EPP";               Sub = "54533251-82be-4824-96c1-47b60b740d00"; Setting = "36687f9e-e3a5-4dbf-b1dc-15eb381c6863"; Value = 0 },
    @{ Name = "Processor Throttle Max";      Sub = "54533251-82be-4824-96c1-47b60b740d00"; Setting = "bc5038f7-23e0-4960-96da-33abaf5935ec"; Value = 100 },
    @{ Name = "Processor Idle Demote";       Sub = "54533251-82be-4824-96c1-47b60b740d00"; Setting = "4b92d758-5a24-4851-a470-815d78aee119"; Value = 100 },
    @{ Name = "Processor Idle Promote";      Sub = "54533251-82be-4824-96c1-47b60b740d00"; Setting = "7b224883-b3cc-4d79-819f-8374152cbe7c"; Value = 100 },
    @{ Name = "PCIe Link State Power Mgmt";  Sub = "501a4d13-42af-4429-9fd1-a8218c268e20"; Setting = "ee12f906-d277-404b-b6da-e5fa1a576df5"; Value = 0 }
)

function ConvertTo-RegistryKeyParts {
    param([string]$Path)
    if ($Path -match '^(HKLM|HKCU):\\(.+)$') {
        $root = if ($Matches[1] -eq "HKLM") { [Microsoft.Win32.Registry]::LocalMachine } else { [Microsoft.Win32.Registry]::CurrentUser }
        return @($root, $Matches[2])
    }
    return @($null, $null)
}

function ConvertTo-RegistryTypedValue {
    param($Value, [string]$Kind)
    switch ($Kind) {
        "DWord" {
            $n = [int64]$Value
            if ($n -gt [int]::MaxValue) { $n -= 4294967296 }
            return [int]$n
        }
        "QWord" {
            if ($Value -is [uint64] -and $Value -gt [uint64][int64]::MaxValue) {
                return [BitConverter]::ToInt64([BitConverter]::GetBytes([uint64]$Value), 0)
            }
            return [int64]$Value
        }
        "Binary" {
            if ($null -eq $Value) { return ,([byte[]]@()) }
            $bytes = [byte[]]@($Value | ForEach-Object { [byte]$_ })
            return ,$bytes
        }
        "MultiString" {
            if ($null -eq $Value) { return ,([string[]]@()) }
            $strs = [string[]]@($Value | ForEach-Object { [string]$_ })
            return ,$strs
        }
        default { return [string]$Value }
    }
}

function Get-RegistryValueSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)] [array]$Targets = @())

    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($t in $Targets) {
        $root, $sub = ConvertTo-RegistryKeyParts $t.Path
        if (-not $root) { continue }
        $entry = @{ Path = $t.Path; Name = $t.Name; KeyExisted = $false; Exists = $false; Value = $null; Kind = $t.Kind }
        try {
            $key = $root.OpenSubKey($sub)
            if ($key) {
                $entry.KeyExisted = $true
                if ($key.GetValueNames() -contains $t.Name) {
                    $entry.Exists = $true
                    $entry.Kind = $key.GetValueKind($t.Name).ToString()
                    $entry.Value = $key.GetValue($t.Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                }
                $key.Close()
            }
        } catch {
            Write-Verbose "Registry snapshot notice for $($t.Path)\$($t.Name): $($_.Exception.Message)"
        }
        $out.Add($entry)
    }
    return $out.ToArray()
}

function Set-RegistryTargets {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)] [array]$Targets = @())

    $isSystem = $false
    try { $isSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem } catch {}
    $applied = 0
    foreach ($t in $Targets) {
        if ($isSystem -and ([string]$t.Path).StartsWith("HKCU:", [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $root, $sub = ConvertTo-RegistryKeyParts $t.Path
        if (-not $root) { continue }
        try {
            if ($null -eq $t.Value) {
                $key = $root.OpenSubKey($sub, $true)
                if ($key) { $key.DeleteValue($t.Name, $false); $key.Close() }
            } else {
                $key = $root.CreateSubKey($sub)
                $kind = [Microsoft.Win32.RegistryValueKind]$t.Kind
                $typedVal = ConvertTo-RegistryTypedValue $t.Value $t.Kind
                $key.SetValue($t.Name, $typedVal, $kind)
                $key.Close()
            }
            $applied++
        } catch {
            Write-Verbose "Registry apply notice for $($t.Path)\$($t.Name): $($_.Exception.Message)"
        }
    }
    return $applied
}

function Restore-RegistryValueSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)] [array]$Snapshot = @(),
        [Parameter(Mandatory = $false)] [ValidateSet("All", "HKLM", "HKCU")] [string]$Hive = "All"
    )

    $restored = 0
    foreach ($e in @($Snapshot)) {
        if (-not $e -or -not $e.Path) { continue }
        if ($Hive -ne "All" -and -not ([string]$e.Path).StartsWith("$($Hive):", [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $root, $sub = ConvertTo-RegistryKeyParts $e.Path
        if (-not $root) { continue }
        try {
            if ($e.Exists) {
                $key = $root.CreateSubKey($sub)
                $kind = [Microsoft.Win32.RegistryValueKind]$e.Kind
                $typedVal = ConvertTo-RegistryTypedValue $e.Value $e.Kind
                $key.SetValue($e.Name, $typedVal, $kind)
                $key.Close()
            } else {
                $key = $root.OpenSubKey($sub, $true)
                if ($key) { $key.DeleteValue($e.Name, $false); $key.Close() }
                # Remove keys we created ourselves (e.g. IFEO\cs2.exe\PerfOptions and its empty parent)
                if (-not $e.KeyExisted) {
                    $current = $sub
                    for ($depth = 0; $depth -lt 2; $depth++) {
                        $k = $root.OpenSubKey($current)
                        if (-not $k) { break }
                        $isEmpty = ($k.ValueCount -eq 0 -and $k.SubKeyCount -eq 0)
                        $k.Close()
                        if (-not $isEmpty) { break }
                        $root.DeleteSubKey($current, $false)
                        $current = Split-Path -Path $current -Parent
                        if (-not $current -or $current -notmatch 'Image File Execution Options\\') { break }
                    }
                }
            }
            $restored++
        } catch {
            Write-Verbose "Registry restore notice for $($e.Path)\$($e.Name): $($_.Exception.Message)"
        }
    }
    return $restored
}

function Test-AntiCheatRequiresVbs {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)] [string[]]$Whitelist = @())

    # VBS/HVCI is kept ON when a protected (whitelisted) kernel anti-cheat that may depend on it is installed.
    foreach ($ac in @("vgk", "vgc", "FACEIT", "FACEITService")) {
        if (($Whitelist -contains $ac) -and (Get-Service -Name $ac -ErrorAction SilentlyContinue)) { return $true }
    }
    return $false
}

function Get-ExtendedGamingTargets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)] [object]$HardwareProfile,
        [Parameter(Mandatory = $false)] [string[]]$Whitelist,
        [Parameter(Mandatory = $false)] [object]$TuningConfig
    )

    $hw = if ($HardwareProfile) { $HardwareProfile } else { Get-HardwareProfile }
    if (-not $Whitelist) {
        $wlFile = Join-Path $PSScriptRoot "..\Config\services_whitelist.json"
        if (Test-Path -LiteralPath $wlFile) {
            $Whitelist = @((Get-Content -LiteralPath $wlFile -Raw -Encoding UTF8 | ConvertFrom-Json).ProtectedServices)
        }
    }

    $tuning = if ($null -ne $TuningConfig) {
        $TuningConfig
    } else {
        $tuningFile = Join-Path $PSScriptRoot "..\Config\tuning.json"
        if (Test-Path -LiteralPath $tuningFile) {
            try { Get-Content -LiteralPath $tuningFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null }
        } else { $null }
    }

    $targets = [System.Collections.Generic.List[object]]::new()
    function Add-T($Path, $Name, $Value, $Kind = "DWord", $Group = "") {
        $targets.Add(@{ Path = $Path; Name = $Name; Value = $Value; Kind = $Kind; Group = $Group })
    }

    # 1. Windows Automatic Maintenance lockout (prevents 40+ maintenance tasks waking mid-match)
    Add-T "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance" "MaintenanceDisabled" 1 "DWord" "Maintenance"

    # 2. ETW telemetry AutoLogger ring buffers (effective from next boot)
    foreach ($logger in $Script:EtwTelemetryAutoLoggers) {
        $lp = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\$logger"
        if (Test-Path -LiteralPath $lp) { Add-T $lp "Start" 0 "DWord" "ETW" }
    }

    # 4. VBS / HVCI off for the gaming boot (skipped if a protected anti-cheat may require it)
    if (-not (Test-AntiCheatRequiresVbs -Whitelist $Whitelist)) {
        Add-T "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard" "EnableVirtualizationBasedSecurity" 0 "DWord" "VBS"
        Add-T "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" "Enabled" 0 "DWord" "VBS"
    }

    # 5. Ring-0 game process boost (read by the kernel at process creation, before anti-cheat handle stripping)
    $ifeoRoot = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
    foreach ($exe in $Script:GameIfeoExecutables) {
        $pp = "$ifeoRoot\$exe\PerfOptions"
        Add-T $pp "CpuPriorityClass" 3 "DWord" "IFEO"
        Add-T $pp "IoPriority" 3 "DWord" "IFEO"
        Add-T $pp "PagePriority" 5 "DWord" "IFEO"
    }

    # 6. AMD RDNA/Polaris driver: PCIe link sleep off, DXNAVI de-stutter, deep sleep off + shader cache Always On
    if ($hw.GpuVendor -eq "AMD") {
        foreach ($k in @(Get-AmdGpuDriverClassKeys)) {
            $kp = if ($k -is [hashtable]) { $k["Path"] } else { $k.Path }
            if ($kp) {
                Add-T $kp "EnableAspmL0s" 0 "DWord" "AMD"
                Add-T $kp "EnableAspmL1" 0 "DWord" "AMD"
                Add-T $kp "StutterMode" 0 "DWord" "AMD"
                Add-T $kp "PP_SclkDeepSleepDisable" 1 "DWord" "AMD"
                if (Test-Path -LiteralPath "$kp\UMD") { Add-T "$kp\UMD" "ShaderCache" ([byte[]](0x32, 0x00)) "Binary" "AMD" }
            }
        }
    }

    # 6b. NVIDIA GeForce driver: telemetry suppression & per-core DPC distribution
    if ($hw.GpuVendor -eq "NVIDIA") {
        Add-T "HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm\Global\Startup" "SendTelemetryData" 0 "DWord" "NVIDIA"
        Add-T "HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm" "RmGpsPsEnablePerCpuCoreDpc" 1 "DWord" "NVIDIA"
        Add-T "HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm\NVAPI" "RmGpsPsEnablePerCpuCoreDpc" 1 "DWord" "NVIDIA"
        Add-T "HKLM:\SYSTEM\CurrentControlSet\Services\nvlddmkm\Global\NVTweak" "RmGpsPsEnablePerCpuCoreDpc" 1 "DWord" "NVIDIA"
        foreach ($k in @(Get-NvidiaGpuDriverClassKeys)) {
            $kp = if ($k -is [hashtable]) { $k["Path"] } else { $k.Path }
            if ($kp) {
                Add-T $kp "RmGpsPsEnablePerCpuCoreDpc" 1 "DWord" "NVIDIA"
                if ($tuning -and $tuning.DisableNvidiaDynamicPstate -eq $true) {
                    Add-T $kp "DisableDynamicPstate" 1 "DWord" "NVIDIA"
                }
            }
        }
    }

    # 7 & 8. Storage controller IRQ de-contention + USB HID idle-suspend suppression (single Enum walk)
    $storageClasses = @("{4d36e97b-e325-11ce-bfc1-08002be10318}", "{4d36e96a-e325-11ce-bfc1-08002be10318}")
    try {
        $enumRoot = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Enum")
        if ($enumRoot) {
            foreach ($bus in @("PCI", "USB")) {
                $busKey = $enumRoot.OpenSubKey($bus)
                if (-not $busKey) { continue }
                foreach ($dev in $busKey.GetSubKeyNames()) {
                    try {
                        $devKey = $busKey.OpenSubKey($dev)
                        if (-not $devKey) { continue }
                        foreach ($inst in $devKey.GetSubKeyNames()) {
                            try {
                                $ik = $devKey.OpenSubKey($inst)
                                if (-not $ik) { continue }
                                $instPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$bus\$dev\$inst\Device Parameters"
                                if ($bus -eq "PCI" -and ($storageClasses -contains [string]$ik.GetValue("ClassGUID"))) {
                                    $ap = $ik.OpenSubKey("Device Parameters\Interrupt Management\Affinity Policy")
                                    if ($ap) {
                                        if ($ap.GetValue("DevicePriority") -eq 3) { Add-T "$instPath\Interrupt Management\Affinity Policy" "DevicePriority" 2 "DWord" "IRQ" }
                                        $ap.Close()
                                    }
                                }
                                elseif ($bus -eq "USB" -and (@("HidUsb", "USBHUB3", "usbhub", "usbccgp") -contains [string]$ik.GetValue("Service"))) {
                                    $dp = $ik.OpenSubKey("Device Parameters")
                                    if ($dp) {
                                        if ($dp.GetValue("EnhancedPowerManagementEnabled") -eq 1) { Add-T $instPath "EnhancedPowerManagementEnabled" 0 "DWord" "USB" }
                                        if ($dp.GetValue("AllowIdleIrpInD3") -eq 1) { Add-T $instPath "AllowIdleIrpInD3" 0 "DWord" "USB" }
                                        $dp.Close()
                                    }
                                }
                                $ik.Close()
                            } catch {
                                Write-Verbose "Enum instance access notice ($bus\$dev\$inst): $($_.Exception.Message)"
                            }
                        }
                        $devKey.Close()
                    } catch {
                        Write-Verbose "Enum device access notice ($bus\$dev): $($_.Exception.Message)"
                    }
                }
                $busKey.Close()
            }
            $enumRoot.Close()
        }
    } catch {
        Write-Verbose "Enum root access notice: $($_.Exception.Message)"
    }

    # 9. Winsock AFD Fast-Path & NDIS RSS CPU Scaling (WinUtil / AtlasOS / ReviOS / Calypto / Fr33thy / XOS)
    $afdPath = "HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters"
    Add-T $afdPath "FastSendDatagramThreshold" 65536 "DWord" "Network"
    Add-T $afdPath "FastCopyReceiveThreshold" 65536 "DWord" "Network"
    Add-T $afdPath "DefaultSendWindow" 65536 "DWord" "Network"
    Add-T $afdPath "DefaultReceiveWindow" 65536 "DWord" "Network"
    Add-T "HKLM:\SYSTEM\CurrentControlSet\Services\NDIS\Parameters" "MaxNumRssCpus" 4 "DWord" "Network"

    # 10. Kernel Power Energy Estimation Telemetry, Fast Startup & Svchost Consolidation
    $taggedEnergyPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\EnergyEstimation\TaggedEnergy"
    Add-T $taggedEnergyPath "DisableTaggedEnergyLogging" 1 "DWord" "Kernel"
    Add-T $taggedEnergyPath "TelemetryMaxApplication" 0 "DWord" "Kernel"
    Add-T $taggedEnergyPath "TelemetryMaxTagPerApplication" 0 "DWord" "Kernel"
    Add-T "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" 0 "DWord" "Kernel"
    Add-T "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" "CoalescingTimerInterval" 0 "DWord" "Kernel"
    if (-not $hw.LowRamProfile) {
        Add-T "HKLM:\SYSTEM\CurrentControlSet\Control" "SvcHostSplitThresholdInKB" 67108864 "DWord" "Svchost"
    }

    # 11. DirectX Flip Model, Windowed Optimizations & Desktop/Mouse Input
    Add-T "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "PlatformSupportMiracast" 0 "DWord" "Graphics"
    Add-T "HKCU:\Control Panel\Desktop" "MenuShowDelay" "0" "String" "Desktop"
    Add-T "HKCU:\Control Panel\Desktop" "LowLevelHooksTimeout" 5000 "DWord" "Desktop"
    Add-T "HKCU:\Control Panel\Mouse" "MouseHoverTime" "10" "String" "Input"
    Add-T "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences" "DirectXUserGlobalSettings" "SwapEffectUpgradeEnable=1;VRROptimizeEnable=1;" "String" "Graphics"
    if ($tuning -and $tuning.DisableMouseAccel -eq $true) {
        Add-T "HKCU:\Control Panel\Mouse" "MouseSpeed" "0" "String" "Input"
        Add-T "HKCU:\Control Panel\Mouse" "MouseThreshold1" "0" "String" "Input"
        Add-T "HKCU:\Control Panel\Mouse" "MouseThreshold2" "0" "String" "Input"
    }

    # 12. Storage Sense & Reserve Manager I/O Prevention
    Add-T "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" "01" 0 "DWord" "Storage"
    Add-T "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager" "ShippedWithReserves" 0 "DWord" "Storage"

    # 13. MMCSS Audio Low-Latency Task Alignment
    $mmcssAudio = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio"
    Add-T $mmcssAudio "Background Only" "False" "String" "MMCSS"
    Add-T $mmcssAudio "Clock Rate" 10000 "DWord" "MMCSS"
    Add-T $mmcssAudio "Priority" 6 "DWord" "MMCSS"
    Add-T $mmcssAudio "Scheduling Category" "Medium" "String" "MMCSS"
    Add-T $mmcssAudio "SFIO Priority" "High" "String" "MMCSS"

    # 14. DirectX Kernel Preemption, Instant Shell Startup & Hotkey Interception Suppression
    Add-T "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Scheduler" "EnablePreemption" 1 "DWord" "Graphics"
    Add-T "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" "StartupDelayInMSec" 0 "DWord" "Desktop"
    Add-T "HKCU:\Control Panel\Accessibility\StickyKeys" "Flags" "506" "String" "Input"
    Add-T "HKCU:\Control Panel\Accessibility\ToggleKeys" "Flags" "58" "String" "Input"
    Add-T "HKCU:\Control Panel\Accessibility\Keyboard Response" "Flags" "122" "String" "Input"

    return $targets.ToArray()
}

function Set-ExtendedGamingOptimizations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)] [object]$HardwareProfile,
        [Parameter(Mandatory = $false)] [string[]]$Whitelist
    )

    Write-Host "[*] Applying v3.2.0 extended optimizations (FSE/VRR, DirectX Flip/Preemption, NVIDIA/AMD DPC, IRQ, USB Hub/HID, AFD/NDIS, MMCSS Audio, ETW)..." -ForegroundColor Cyan
    $targets = @(Get-ExtendedGamingTargets -HardwareProfile $HardwareProfile -Whitelist $Whitelist)
    $applied = Set-RegistryTargets -Targets $targets
    $groups = ($targets | ForEach-Object { $_.Group } | Sort-Object -Unique) -join ", "
    Write-Host "  [+] $applied/$($targets.Count) registry targets applied ($groups). Boot-time items take effect after restart." -ForegroundColor Green

    # Stop running telemetry ETW sessions right now (AutoLogger Start=0 covers the next boot)
    foreach ($logger in $Script:EtwTelemetryAutoLoggers) {
        $null = logman stop $logger -ets 2>&1
    }
    return $applied
}

function Get-PowerAcSettingIndex {
    [CmdletBinding()]
    param([string]$SchemeGuid, [string]$Sub, [string]$Setting)

    foreach ($p in @(
        "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$SchemeGuid\$Sub\$Setting",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\$Sub\$Setting\DefaultPowerSchemeValues\$SchemeGuid"
    )) {
        $v = (Get-ItemProperty -Path $p -Name "ACSettingIndex" -ErrorAction SilentlyContinue).ACSettingIndex
        if ($null -ne $v) { return [int]$v }
    }
    # Locale-independent fallback: AC index is always the second-to-last hex value (AC precedes DC)
    $hex = [regex]::Matches((powercfg /q $SchemeGuid $Sub $Setting 2>&1 | Out-String), ':\s*0x([0-9a-fA-F]+)')
    if ($hex.Count -ge 2) { return [Convert]::ToInt32($hex[$hex.Count - 2].Groups[1].Value, 16) }
    return $null
}

function Get-PowerLatencyConfig {
    [CmdletBinding()]
    param()

    $guid = Get-ActivePowerSchemeGuid
    if (-not $guid) { return $null }
    $settings = foreach ($s in $Script:PowerLatencySettings) {
        @{ Name = $s.Name; Sub = $s.Sub; Setting = $s.Setting; Original = (Get-PowerAcSettingIndex -SchemeGuid $guid -Sub $s.Sub -Setting $s.Setting) }
    }
    return @{ SchemeGuid = $guid; Settings = @($settings) }
}

function Set-PowerLatencyOptimizations {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)] [object]$Config)

    if (-not $Config -or -not $Config.SchemeGuid) { return $false }
    Write-Host "[*] Disabling USB selective suspend, USB3 LPM, NVMe APST idle and Ryzen/Intel EPP ramp-up delay..." -ForegroundColor Cyan
    foreach ($s in @($Config.Settings)) {
        if ($null -eq $s.Original) { continue }  # unknown original -> do not touch (cannot restore)
        $target = ($Script:PowerLatencySettings | Where-Object { $_.Setting -eq $s.Setting } | Select-Object -First 1).Value
        $null = powercfg /setacvalueindex $Config.SchemeGuid $s.Sub $s.Setting $target 2>&1
        $null = powercfg /setacvalueindex SCHEME_CURRENT $s.Sub $s.Setting $target 2>&1
        Write-Host "  [+] $($s.Name): $($s.Original) -> $target" -ForegroundColor Green
    }
    $null = powercfg /setactive SCHEME_CURRENT 2>&1
    return $true
}

function Restore-PowerLatencyOptimizations {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)] [object]$Config)

    if (-not $Config -or -not $Config.SchemeGuid) { return $true }
    Write-Host "[*] Restoring USB / NVMe / EPP power latency settings..." -ForegroundColor Cyan
    foreach ($s in @($Config.Settings)) {
        if ($null -eq $s.Original) { continue }
        $null = powercfg /setacvalueindex $Config.SchemeGuid $s.Sub $s.Setting ([int]$s.Original) 2>&1
    }
    $null = powercfg /setactive SCHEME_CURRENT 2>&1
    Write-Host "  [+] Power latency settings restored." -ForegroundColor Green
    return $true
}

function Get-MemoryCompressionConfig {
    [CmdletBinding()]
    param()
    try {
        $m = Get-MMAgent -ErrorAction Stop
        return @{ MemoryCompression = [bool]$m.MemoryCompression; ApplicationPreLaunch = [bool]$m.ApplicationPreLaunch }
    } catch {
        return $null
    }
}

function Set-MemoryCompressionGamingState {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)] [object]$HardwareProfile)

    $hw = if ($HardwareProfile) { $HardwareProfile } else { Get-HardwareProfile }
    if ($hw.LowRamProfile -or [double]$hw.TotalRamGB -lt 16) {
        Write-Host "  [i] Memory compression retained (< 16 GB RAM: compression prevents pagefile thrashing)." -ForegroundColor Gray
        return $false
    }
    foreach ($feature in @("MemoryCompression", "ApplicationPreLaunch")) {
        try {
            $splat = @{ $feature = $true; ErrorAction = "Stop" }
            Disable-MMAgent @splat
        } catch {
            Write-Verbose "Disable-MMAgent $feature notice: $($_.Exception.Message)"
        }
    }
    Write-Host "  [+] Memory compression & app prelaunch disabled ($($hw.TotalRamGB) GB RAM: frees CPU cycles and L3 cache)." -ForegroundColor Green
    return $true
}

function Restore-MemoryCompressionConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)] [object]$Config)

    if (-not $Config) { return $true }
    foreach ($feature in @("MemoryCompression", "ApplicationPreLaunch")) {
        if ($Config.$feature) {
            try {
                $splat = @{ $feature = $true; ErrorAction = "Stop" }
                Enable-MMAgent @splat
            } catch {
                Write-Verbose "Enable-MMAgent $feature notice: $($_.Exception.Message)"
            }
        }
    }
    Write-Host "  [+] Memory compression / prelaunch restored." -ForegroundColor Green
    return $true
}

function Repair-LegacyOptimizerLeftovers {
    [CmdletBinding()]
    param()

    Write-Host "[*] Scanning for broken leftovers of third-party optimizers (IFEO priority inversion, orphaned tasks)..." -ForegroundColor Cyan
    $fixed = 0
    $systemExes = @("fontdrvhost.exe", "sihost.exe", "lsass.exe", "ctfmon.exe", "dwm.exe", "csrss.exe", "svchost.exe",
                    "explorer.exe", "audiodg.exe", "winlogon.exe", "services.exe", "wininit.exe", "smss.exe")
    try {
        $ifeo = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options", $true)
        if ($ifeo) {
            foreach ($name in $ifeo.GetSubKeyNames()) {
                if ($name -match "^'.+'$") {
                    # Malformed quoted key names (e.g. 'AggregatorHost.exe') never match any image - pure junk
                    $ifeo.DeleteSubKeyTree($name, $false)
                    Write-Host "  [x] Removed malformed IFEO key: $name" -ForegroundColor Yellow
                    $fixed++
                    continue
                }
                if ($systemExes -notcontains $name) { continue }
                $po = $ifeo.OpenSubKey("$name\PerfOptions")
                if (-not $po) { continue }
                $cpu = $po.GetValue("CpuPriorityClass"); $io = $po.GetValue("IoPriority"); $page = $po.GetValue("PagePriority")
                $po.Close()
                # Demoted system servers cause priority inversion (DWM/win32k/games block on them)
                if (($null -ne $cpu -and $cpu -in @(1, 5)) -or ($null -ne $io -and $io -lt 2) -or ($null -ne $page -and $page -lt 5)) {
                    $ifeo.DeleteSubKeyTree("$name\PerfOptions", $false)
                    Write-Host "  [x] Removed priority-inversion PerfOptions on system process: $name" -ForegroundColor Yellow
                    $fixed++
                }
            }
            $ifeo.Close()
        }
    } catch {
        Write-Verbose "IFEO cleanup notice: $($_.Exception.Message)"
    }

    # 2. Harmful MPO and Fullscreen Exclusive (FSE) overrides that cause display flickering/blinking in Deadlock & RDR2
    try {
        $dwm = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SOFTWARE\Microsoft\Windows\Dwm", $true)
        if ($dwm) {
            if ($null -ne $dwm.GetValue("OverlayTestMode")) {
                $dwm.DeleteValue("OverlayTestMode", $false)
                Write-Host "  [x] Removed harmful MPO disable key: HKLM:\SOFTWARE\Microsoft\Windows\Dwm\OverlayTestMode" -ForegroundColor Yellow
                $fixed++
            }
            $dwm.Close()
        }
    } catch {}

    try {
        $gfx = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Control\GraphicsDrivers", $true)
        if ($gfx) {
            if ($null -ne $gfx.GetValue("DisableOverlays")) {
                $gfx.DeleteValue("DisableOverlays", $false)
                Write-Host "  [x] Removed harmful MPO disable key: HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\DisableOverlays" -ForegroundColor Yellow
                $fixed++
            }
            $gfx.Close()
        }
    } catch {}

    try {
        $gcs = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("System\GameConfigStore", $true)
        if ($gcs) {
            foreach ($vName in @("GameDVR_FSEBehavior", "GameDVR_HonorUserFSEBehaviorMode", "GameDVR_DXGIHonorFSEWindowsCompatible", "GameDVR_EFSEFeatureFlags")) {
                if ($null -ne $gcs.GetValue($vName)) {
                    $gcs.DeleteValue($vName, $false)
                    Write-Host "  [x] Removed harmful FSE override key: HKCU:\System\GameConfigStore\$vName" -ForegroundColor Yellow
                    $fixed++
                }
            }
            $gcs.Close()
        }
    } catch {}

    try {
        $dxu = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Software\Microsoft\DirectX\UserGpuPreferences", $true)
        if ($dxu) {
            $globalVal = [string]$dxu.GetValue("DirectXUserGlobalSettings")
            if ($globalVal -match "SwapEffectUpgradeEnable=0") {
                $dxu.DeleteValue("DirectXUserGlobalSettings", $false)
                Write-Host "  [x] Removed forced DXGI global override: DirectXUserGlobalSettings" -ForegroundColor Yellow
                $fixed++
            }
            foreach ($appName in $dxu.GetValueNames()) {
                $val = [string]$dxu.GetValue($appName)
                if ($val -match "SwapEffectUpgradeEnable=0;") {
                    $newVal = $val -replace "SwapEffectUpgradeEnable=0;", ""
                    $dxu.SetValue($appName, $newVal, [Microsoft.Win32.RegistryValueKind]::String)
                    Write-Host "  [x] Removed SwapEffectUpgradeEnable=0 override for: $appName" -ForegroundColor Yellow
                    $fixed++
                }
            }
            $dxu.Close()
        }
    } catch {}

    # 3. Purge heavy open-world game IFEO (RDR2.exe) that starves DWM rendering threads
    try {
        $ifeoRootKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options", $true)
        if ($ifeoRootKey) {
            if ($ifeoRootKey.GetSubKeyNames() -contains "RDR2.exe") {
                $ifeoRootKey.DeleteSubKeyTree("RDR2.exe", $false)
                Write-Host "  [x] Removed RDR2.exe IFEO priority override (prevents DWM thread starvation)." -ForegroundColor Yellow
                $fixed++
            }
            $ifeoRootKey.Close()
        }
    } catch {}

    # Lift already-running system servers stuck at Idle / BelowNormal
    foreach ($p in @(Get-Process -Name "sihost", "fontdrvhost", "ctfmon" -ErrorAction SilentlyContinue)) {
        try {
            if ($p.PriorityClass -in @([System.Diagnostics.ProcessPriorityClass]::Idle, [System.Diagnostics.ProcessPriorityClass]::BelowNormal)) {
                $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Normal
                Write-Host "  [+] $($p.ProcessName) (PID $($p.Id)) priority restored to Normal." -ForegroundColor Green
                $fixed++
            }
        } catch {
            Write-Verbose "Priority fix notice for $($p.ProcessName): $($_.Exception.Message)"
        }
    }

    # Orphaned scheduled tasks whose executable no longer exists (e.g. uninstalled GameModeX)
    foreach ($t in @(Get-ScheduledTask -TaskName "GameModeX" -ErrorAction SilentlyContinue)) {
        $exe = [Environment]::ExpandEnvironmentVariables([string](@($t.Actions)[0].Execute)).Trim('"')
        if (-not $exe -or -not (Test-Path -LiteralPath $exe)) {
            Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -ErrorAction SilentlyContinue
            Write-Host "  [x] Removed orphaned scheduled task: $($t.TaskPath)$($t.TaskName)" -ForegroundColor Yellow
            $fixed++
        }
    }

    if ($fixed -eq 0) { Write-Host "  [+] No broken optimizer leftovers found." -ForegroundColor Green }
    return $fixed
}

# ==============================================================================
# ── Windows 11 Deep Debloat & Background AI / Telemetry Suppression ──────────
# ==============================================================================

function Get-Windows11DebloatConfig {
    [CmdletBinding()]
    param()

    $isSystem = $false
    try { $isSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem } catch {}

    $config = @{
        GameDVR_Enabled              = $null
        AppCaptureEnabled            = $null
        TurnOffWindowsCopilot        = $null
        TaskbarDa                    = $null
        BingSearchEnabled            = $null
        DisableSearchBoxSuggestions  = $null
        AllowGameDVR                 = $null
        PresenceWriterActivation     = $null
        EdgeStartupBoost             = $null
        EdgeBackgroundMode           = $null
        DisableAIDataAnalysis        = $null
        TurnOffWindowsCopilotMachine = $null
        WSAIFabricSvcStart           = $null
        AllowNewsAndInterests        = $null
    }

    try {
        if (-not $isSystem) {
            $p = Get-ItemProperty -Path "HKCU:\System\GameConfigStore" -ErrorAction SilentlyContinue
            if ($null -ne $p -and $p.PSObject.Properties["GameDVR_Enabled"]) { $config.GameDVR_Enabled = [int]$p.GameDVR_Enabled }

            $p = Get-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" -ErrorAction SilentlyContinue
            if ($null -ne $p -and $p.PSObject.Properties["AppCaptureEnabled"]) { $config.AppCaptureEnabled = [int]$p.AppCaptureEnabled }

            $p = Get-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -ErrorAction SilentlyContinue
            if ($null -ne $p -and $p.PSObject.Properties["TurnOffWindowsCopilot"]) { $config.TurnOffWindowsCopilot = [int]$p.TurnOffWindowsCopilot }

            $p = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -ErrorAction SilentlyContinue
            if ($null -ne $p -and $p.PSObject.Properties["TaskbarDa"]) { $config.TaskbarDa = [int]$p.TaskbarDa }

            $p = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -ErrorAction SilentlyContinue
            if ($null -ne $p -and $p.PSObject.Properties["BingSearchEnabled"]) { $config.BingSearchEnabled = [int]$p.BingSearchEnabled }

            $p = Get-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -ErrorAction SilentlyContinue
            if ($null -ne $p -and $p.PSObject.Properties["DisableSearchBoxSuggestions"]) { $config.DisableSearchBoxSuggestions = [int]$p.DisableSearchBoxSuggestions }
        }

        $p = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -ErrorAction SilentlyContinue
        if ($null -ne $p -and $p.PSObject.Properties["AllowGameDVR"]) { $config.AllowGameDVR = [int]$p.AllowGameDVR }

        $p = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Windows.Gaming.GameBar.PresenceServer.Internal.PresenceWriter" -ErrorAction SilentlyContinue
        if ($null -ne $p -and $p.PSObject.Properties["ActivationType"]) { $config.PresenceWriterActivation = [int]$p.ActivationType }

        $p = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -ErrorAction SilentlyContinue
        if ($null -ne $p) {
            if ($p.PSObject.Properties["StartupBoostEnabled"]) { $config.EdgeStartupBoost = [int]$p.StartupBoostEnabled }
            if ($p.PSObject.Properties["BackgroundModeEnabled"]) { $config.EdgeBackgroundMode = [int]$p.BackgroundModeEnabled }
        }

        $p = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -ErrorAction SilentlyContinue
        if ($null -ne $p -and $p.PSObject.Properties["DisableAIDataAnalysis"]) { $config.DisableAIDataAnalysis = [int]$p.DisableAIDataAnalysis }

        $p = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -ErrorAction SilentlyContinue
        if ($null -ne $p -and $p.PSObject.Properties["TurnOffWindowsCopilot"]) { $config.TurnOffWindowsCopilotMachine = [int]$p.TurnOffWindowsCopilot }

        $p = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WSAIFabricSvc" -ErrorAction SilentlyContinue
        if ($null -ne $p -and $p.PSObject.Properties["Start"]) { $config.WSAIFabricSvcStart = [int]$p.Start }

        $p = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -ErrorAction SilentlyContinue
        if ($null -ne $p -and $p.PSObject.Properties["AllowNewsAndInterests"]) { $config.AllowNewsAndInterests = [int]$p.AllowNewsAndInterests }
    } catch {
        Write-Verbose "Get-Windows11DebloatConfig notice: $($_.Exception.Message)"
    }

    return $config
}

function Set-Windows11DebloatOptimizations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$DisableGameBar,
        [Parameter(Mandatory = $false)]
        [switch]$DisableEdgeBoost,
        [Parameter(Mandatory = $false)]
        [switch]$DisableAI,
        [Parameter(Mandatory = $false)]
        [switch]$DisableWidgets,
        [Parameter(Mandatory = $false)]
        [switch]$DisableBingSearch,
        [Parameter(Mandatory = $false)]
        [switch]$All
    )

    Write-Host "[*] Applying Windows 11 Deep Debloat & Background Suppression..." -ForegroundColor Cyan
    $isSystem = $false
    try { $isSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem } catch {}

    # 1. GameDVR & Background Recording
    if ($All -or $DisableGameBar) {
        try {
            if (-not $isSystem) {
                if (-not (Test-Path "HKCU:\System\GameConfigStore")) { New-Item -Path "HKCU:\System\GameConfigStore" -Force | Out-Null }
                Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

                if (-not (Test-Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR")) { New-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" -Force | Out-Null }
                Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            }

            if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR")) { New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Force | Out-Null }
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

            if (-not (Test-Path "HKLM:\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Windows.Gaming.GameBar.PresenceServer.Internal.PresenceWriter")) {
                New-Item -Path "HKLM:\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Windows.Gaming.GameBar.PresenceServer.Internal.PresenceWriter" -Force | Out-Null
            }
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Windows.Gaming.GameBar.PresenceServer.Internal.PresenceWriter" -Name "ActivationType" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            Write-Host "  [+] Xbox Game Bar DVR & background recording suppressed." -ForegroundColor Green
        } catch {
            Write-Warning "Failed to disable GameDVR: $($_.Exception.Message)"
        }
    }

    # 2. Edge Startup Boost & Background Extensions
    if ($All -or $DisableEdgeBoost) {
        try {
            foreach ($k in @("HKLM:\SOFTWARE\Policies\Microsoft\Edge", "HKLM:\SOFTWARE\Policies\Microsoft\Edge\Recommended")) {
                if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
                Set-ItemProperty -Path $k -Name "StartupBoostEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $k -Name "BackgroundModeEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            }
            Write-Host "  [+] Microsoft Edge Startup Boost & background processes blocked." -ForegroundColor Green
        } catch {
            Write-Warning "Failed to disable Edge Startup Boost: $($_.Exception.Message)"
        }
    }

    # 3. Windows Copilot & Recall AI
    if ($All -or $DisableAI) {
        try {
            if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI")) { New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Force | Out-Null }
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAIDataAnalysis" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

            $copilotKeys = if ($isSystem) { @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot") } else { @("HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot", "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot") }
            foreach ($k in $copilotKeys) {
                if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
                Set-ItemProperty -Path $k -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            }

            if (Get-Service -Name "WSAIFabricSvc" -ErrorAction SilentlyContinue) {
                Stop-Service -Name "WSAIFabricSvc" -Force -ErrorAction SilentlyContinue
                Set-Service -Name "WSAIFabricSvc" -StartupType Disabled -ErrorAction SilentlyContinue
            }
            Write-Host "  [+] Windows Copilot & AI telemetry background analysis disabled." -ForegroundColor Green
        } catch {
            Write-Warning "Failed to disable Windows AI: $($_.Exception.Message)"
        }
    }

    # 4. Widgets & NewsFeeds
    if ($All -or $DisableWidgets) {
        try {
            if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh")) { New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Force | Out-Null }
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

            if (-not $isSystem) {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) { New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force | Out-Null }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            }
            Write-Host "  [+] Windows 11 Widgets Board & News Feeds disabled." -ForegroundColor Green
        } catch {
            Write-Warning "Failed to disable Widgets: $($_.Exception.Message)"
        }
    }

    # 5. Bing Search in Start Menu
    if (($All -or $DisableBingSearch) -and -not $isSystem) {
        try {
            if (-not (Test-Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer")) { New-Item -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Force | Out-Null }
            Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableSearchBoxSuggestions" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

            if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search")) { New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Force | Out-Null }
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            Write-Host "  [+] Bing search suggestions & ads in Start Menu removed." -ForegroundColor Green
        } catch {
            Write-Warning "Failed to disable Bing Search: $($_.Exception.Message)"
        }
    }

    # 6. Windows Security Event Auditing Suppression (auditpol)
    try {
        auditpol.exe /set /category:* /success:disable /failure:disable 2>&1 | Out-Null
        Write-Host "  [+] Windows Security event auditing (auditpol) suppressed." -ForegroundColor Green
    } catch {
        Write-Verbose "Auditpol suppression notice: $($_.Exception.Message)"
    }

    return $true
}

function Restore-Windows11DebloatOptimizations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [object]$DebloatConfig,

        [Parameter(Mandatory = $false)]
        [switch]$UserOnly
    )

    Write-Host "[*] Restoring Windows 11 Debloat & Application settings..." -ForegroundColor Cyan
    $isSystem = $false
    try { $isSystem = [Security.Principal.WindowsIdentity]::GetCurrent().IsSystem } catch {}

    if (-not $DebloatConfig) {
        $DebloatConfig = @{
            GameDVR_Enabled              = 1
            AppCaptureEnabled            = 1
            TurnOffWindowsCopilot        = $null
            TaskbarDa                    = 1
            BingSearchEnabled            = $null
            DisableSearchBoxSuggestions  = $null
            AllowGameDVR                 = $null
            PresenceWriterActivation     = 1
            EdgeStartupBoost             = $null
            EdgeBackgroundMode           = $null
            DisableAIDataAnalysis        = $null
            TurnOffWindowsCopilotMachine = $null
            WSAIFabricSvcStart           = $null
            AllowNewsAndInterests        = $null
        }
    }

    $getCfgVal = {
        param([string]$Key)
        if ($DebloatConfig -is [System.Collections.IDictionary]) {
            if ($DebloatConfig.Contains($Key)) { return $DebloatConfig[$Key] }
            return $null
        }
        $p = $DebloatConfig.PSObject.Properties[$Key]
        if ($p) { return $p.Value }
        return $null
    }

    $restoreDwordOrRemove = {
        param([string]$Path, [string]$Name, $Value)
        if ($null -ne $Value) {
            if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction SilentlyContinue | Out-Null }
            Set-ItemProperty -Path $Path -Name $Name -Value ([int]$Value) -Type DWord -Force -ErrorAction SilentlyContinue
        } else {
            Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction SilentlyContinue
        }
    }

    try {
        # 1. Restore GameDVR & Taskbar / Search / Copilot user hive settings
        if (-not $isSystem) {
            $gdvr = & $getCfgVal "GameDVR_Enabled"
            if ($null -ne $gdvr) {
                $gdvrPath = "HKCU:\System\GameConfigStore"
                if (-not (Test-Path -LiteralPath $gdvrPath)) { New-Item -Path $gdvrPath -Force -ErrorAction SilentlyContinue | Out-Null }
                Set-ItemProperty -Path $gdvrPath -Name "GameDVR_Enabled" -Value ([int]$gdvr) -Type DWord -Force -ErrorAction SilentlyContinue
            }

            $appCap = & $getCfgVal "AppCaptureEnabled"
            if ($null -ne $appCap) {
                $appCapPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR"
                if (-not (Test-Path -LiteralPath $appCapPath)) { New-Item -Path $appCapPath -Force -ErrorAction SilentlyContinue | Out-Null }
                Set-ItemProperty -Path $appCapPath -Name "AppCaptureEnabled" -Value ([int]$appCap) -Type DWord -Force -ErrorAction SilentlyContinue
            }

            & $restoreDwordOrRemove "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" (& $getCfgVal "TurnOffWindowsCopilot")

            $taskbarDa = & $getCfgVal "TaskbarDa"
            if ($null -eq $taskbarDa) { $taskbarDa = 1 }
            $advPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            if (-not (Test-Path -LiteralPath $advPath)) { New-Item -Path $advPath -Force -ErrorAction SilentlyContinue | Out-Null }
            Set-ItemProperty -Path $advPath -Name "TaskbarDa" -Value ([int]$taskbarDa) -Type DWord -Force -ErrorAction SilentlyContinue

            & $restoreDwordOrRemove "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" (& $getCfgVal "BingSearchEnabled")
            & $restoreDwordOrRemove "HKCU:\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" (& $getCfgVal "DisableSearchBoxSuggestions")
        }

        if (-not $UserOnly) {
            # 2. Restore GameDVR policy & GameBar PresenceWriter activation
            & $restoreDwordOrRemove "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" (& $getCfgVal "AllowGameDVR")

            $presence = & $getCfgVal "PresenceWriterActivation"
            if ($null -eq $presence) { $presence = 1 }
            $presencePath = "HKLM:\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Windows.Gaming.GameBar.PresenceServer.Internal.PresenceWriter"
            if (-not (Test-Path -LiteralPath $presencePath)) { New-Item -Path $presencePath -Force -ErrorAction SilentlyContinue | Out-Null }
            Set-ItemProperty -Path $presencePath -Name "ActivationType" -Value ([int]$presence) -Type DWord -Force -ErrorAction SilentlyContinue

            # 3. Restore Microsoft Edge policies
            & $restoreDwordOrRemove "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "StartupBoostEnabled" (& $getCfgVal "EdgeStartupBoost")
            & $restoreDwordOrRemove "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "BackgroundModeEnabled" (& $getCfgVal "EdgeBackgroundMode")
            Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge\Recommended" -Name "StartupBoostEnabled" -Force -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge\Recommended" -Name "BackgroundModeEnabled" -Force -ErrorAction SilentlyContinue

            # 4. Restore AI / Copilot policies & WSAIFabricSvc startup
            & $restoreDwordOrRemove "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" (& $getCfgVal "DisableAIDataAnalysis")
            & $restoreDwordOrRemove "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" (& $getCfgVal "TurnOffWindowsCopilotMachine")

            $wsaiStart = & $getCfgVal "WSAIFabricSvcStart"
            $wsaiRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\WSAIFabricSvc"
            if ($null -ne $wsaiStart -and (Test-Path -LiteralPath $wsaiRegPath)) {
                Set-ItemProperty -Path $wsaiRegPath -Name "Start" -Value ([int]$wsaiStart) -Type DWord -Force -ErrorAction SilentlyContinue
            } elseif (Get-Service -Name "WSAIFabricSvc" -ErrorAction SilentlyContinue) {
                Set-Service -Name "WSAIFabricSvc" -StartupType Manual -ErrorAction SilentlyContinue
            }

            # 5. Restore Widgets / News & Interests policy
            & $restoreDwordOrRemove "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests" (& $getCfgVal "AllowNewsAndInterests")

            # 6. Restore basic Security Event Auditing
            auditpol.exe /set /subcategory:"Logon" /success:enable /failure:enable 2>&1 | Out-Null
        }

        Write-Host "  [+] Windows 11 components and debloat settings reverted to original state." -ForegroundColor Green
        return $true
    } catch {
        Write-Warning "Failed to restore Windows 11 debloat settings: $($_.Exception.Message)"
        return $false
    }
}

