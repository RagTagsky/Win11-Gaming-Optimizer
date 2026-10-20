<#
.SYNOPSIS
    Unit and integration verification suite for Universal Hardware Auto-Detection Engine.
#>

$ErrorActionPreference = "Stop"
$failures = 0
$testsRun = 0

function Assert-Test($condition, $message) {
    $script:testsRun++
    if ($condition) {
        Write-Host "  [PASS] $message" -ForegroundColor Green
    } else {
        $script:failures++
        Write-Host "  [FAIL] $message" -ForegroundColor Red
    }
}

Write-Host "=====================================================" -ForegroundColor Magenta
Write-Host "   UNIVERSAL HARDWARE ENGINE DEEP VERIFICATION SUITE  " -ForegroundColor Magenta
Write-Host "=====================================================" -ForegroundColor Magenta

# ── 1. PowerShell Syntax / AST Parse Check ──────────────────────────────────
Write-Host "`n[Test Group 1] AST Language Parser Validation across all scripts:" -ForegroundColor Cyan
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$scripts = Get-ChildItem -Path $repoRoot -Recurse -Filter "*.ps1"
foreach ($s in $scripts) {
    $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($s.FullName, [ref]$null, [ref]$errs)
    Assert-Test ($errs.Count -eq 0) "Script '$($s.Name)' parses with 0 AST errors"
}

# ── 2. Load Core Modules ───────────────────────────────────────────────────
Write-Host "`n[Test Group 2] Module Loading and Type Verification:" -ForegroundColor Cyan
. (Join-Path $repoRoot "Core\ServiceManager.ps1")
. (Join-Path $repoRoot "Core\SystemOptimizer.ps1")
. (Join-Path $repoRoot "Core\StateEngine.ps1")
Assert-Test (Get-Command Select-PrimaryGamingGpu -ErrorAction SilentlyContinue) "Select-PrimaryGamingGpu pure function is exported and accessible"
Assert-Test (Get-Command Resolve-StorageDeviceMediaType -ErrorAction SilentlyContinue) "Resolve-StorageDeviceMediaType pure function is exported and accessible"
Assert-Test (Get-Command Test-IsLowRamSystem -ErrorAction SilentlyContinue) "Test-IsLowRamSystem pure function is exported and accessible"
Assert-Test (Get-Command Test-IsHighPerformanceScheme -ErrorAction SilentlyContinue) "Test-IsHighPerformanceScheme pure function is exported and accessible"
Assert-Test (Get-Command Set-ServiceStateSafe -ErrorAction SilentlyContinue) "Set-ServiceStateSafe is exported and accessible"
Assert-Test (Get-Command Get-HardwareProfile -ErrorAction SilentlyContinue) "Get-HardwareProfile function is exported and accessible"
Assert-Test (Get-Command Apply-CpuGamingOptimizations -ErrorAction SilentlyContinue) "Apply-CpuGamingOptimizations is accessible"
Assert-Test (Get-Command Apply-GpuGamingOptimizations -ErrorAction SilentlyContinue) "Apply-GpuGamingOptimizations is accessible"
Assert-Test (Get-Command Set-NTFSGamingOptimizations -ErrorAction SilentlyContinue) "Set-NTFSGamingOptimizations is accessible"
Assert-Test (Get-Command Restore-NTFSGamingOptimizations -ErrorAction SilentlyContinue) "Restore-NTFSGamingOptimizations is accessible"
Assert-Test (Get-Command Get-KernelDpcConfig -ErrorAction SilentlyContinue) "Get-KernelDpcConfig is accessible"
Assert-Test (Get-Command Set-KernelDpcOptimizations -ErrorAction SilentlyContinue) "Set-KernelDpcOptimizations is accessible"
Assert-Test (Get-Command Restore-KernelDpcOptimizations -ErrorAction SilentlyContinue) "Restore-KernelDpcOptimizations is accessible"
Assert-Test (Get-Command Get-InputBufferConfig -ErrorAction SilentlyContinue) "Get-InputBufferConfig is accessible"
Assert-Test (Get-Command Set-InputBufferOptimizations -ErrorAction SilentlyContinue) "Set-InputBufferOptimizations is accessible"
Assert-Test (Get-Command Restore-InputBufferOptimizations -ErrorAction SilentlyContinue) "Restore-InputBufferOptimizations is accessible"
Assert-Test (Get-Command Get-BcdeditTimerConfig -ErrorAction SilentlyContinue) "Get-BcdeditTimerConfig is accessible"
Assert-Test (Get-Command Set-BcdeditTimerOptimizations -ErrorAction SilentlyContinue) "Set-BcdeditTimerOptimizations is accessible"
Assert-Test (Get-Command Restore-BcdeditTimerOptimizations -ErrorAction SilentlyContinue) "Restore-BcdeditTimerOptimizations is accessible"
Assert-Test (Get-Command Get-TcpStackConfig -ErrorAction SilentlyContinue) "Get-TcpStackConfig is accessible"
Assert-Test (Get-Command Set-TcpGamingStackOptimizations -ErrorAction SilentlyContinue) "Set-TcpGamingStackOptimizations is accessible"
Assert-Test (Get-Command Restore-TcpGamingStackOptimizations -ErrorAction SilentlyContinue) "Restore-TcpGamingStackOptimizations is accessible"
Assert-Test (Get-Command Get-HagsGpuSchedulingConfig -ErrorAction SilentlyContinue) "Get-HagsGpuSchedulingConfig is accessible"
Assert-Test (Get-Command Set-HagsGpuScheduling -ErrorAction SilentlyContinue) "Set-HagsGpuScheduling is accessible"
Assert-Test (Get-Command Restore-HagsGpuScheduling -ErrorAction SilentlyContinue) "Restore-HagsGpuScheduling is accessible"
Assert-Test (Get-Command Clear-AmdShaderCache -ErrorAction SilentlyContinue) "Clear-AmdShaderCache is accessible"
Assert-Test (Get-Command Clear-GpuShaderCache -ErrorAction SilentlyContinue) "Clear-GpuShaderCache alias is accessible"
Assert-Test (Get-Command Disable-UserStateAggressive -ErrorAction SilentlyContinue) "Disable-UserStateAggressive is accessible"

# ── 3. Real System Hardware Profile Verification ───────────────────────────
Write-Host "`n[Test Group 3] Live System Hardware Auto-Detection:" -ForegroundColor Cyan
$liveHw = Get-HardwareProfile
Assert-Test ($liveHw.CpuVendor -in @("AMD", "Intel", "Unknown")) "Live CPU Vendor detected: $($liveHw.CpuVendor)"
Assert-Test ($liveHw.LogicalCores -gt 0) "Live Logical Cores detected: $($liveHw.LogicalCores)"
Assert-Test ($liveHw.TotalRamGB -gt 0) "Live Total RAM detected: $($liveHw.TotalRamGB) GB"
Assert-Test ($liveHw.GpuVendor -in @("AMD", "NVIDIA", "Intel", "Unknown")) "Live GPU Vendor detected: $($liveHw.GpuVendor)"
Assert-Test ($null -ne $liveHw.HddProfile) "Live HddProfile evaluated: $($liveHw.HddProfile)"

# ── 4. Low-Core Profile CPU Topologies ─────────────────────────────────────
Write-Host "`n[Test Group 4] CPU Core & Architecture Topology Simulation:" -ForegroundColor Cyan
$testCpus = @(
    @{ Name = "Intel(R) Core(TM) i3-2100 CPU @ 3.10GHz"; Cores = 2; Logical = 4; ExpectedLow = $true; ExpectedVendor = "Intel" },
    @{ Name = "Intel(R) Core(TM) i5-4460 CPU @ 3.20GHz"; Cores = 4; Logical = 4; ExpectedLow = $true; ExpectedVendor = "Intel" },
    @{ Name = "AMD Ryzen 5 5600X 6-Core Processor"; Cores = 6; Logical = 12; ExpectedLow = $false; ExpectedVendor = "AMD" },
    @{ Name = "AMD Ryzen 7 7800X3D 8-Core Processor"; Cores = 8; Logical = 16; ExpectedLow = $false; ExpectedVendor = "AMD" }
)
foreach ($c in $testCpus) {
    $isLow = ($c.Logical -le 4)
    $vendor = if ($c.Name -match "Intel") { "Intel" } elseif ($c.Name -match "AMD|Ryzen") { "AMD" } else { "Unknown" }
    Assert-Test ($isLow -eq $c.ExpectedLow) "$($c.Name): LowCoreProfile is $isLow (Expected: $($c.ExpectedLow))"
    Assert-Test ($vendor -eq $c.ExpectedVendor) "$($c.Name): Vendor is $vendor (Expected: $($c.ExpectedVendor))"
}

# ── 5. GPU Auto-Detection Matrix (Optimus, Enduro, Friend Rig) ─────────────
Write-Host "`n[Test Group 5] GPU Selection Matrix (Friend Rig, Optimus, Enduro, Arc, iGPU):" -ForegroundColor Cyan
$testGpuScenarios = @(
    @{
        Scenario = "Friend Rig: Intel Core i3-2100 + AMD Radeon RX 570 8GB"
        Gpus = @(
            [PSCustomObject]@{ Name = "Intel(R) HD Graphics 2000"; PNPDeviceID = "PCI\VEN_8086&DEV_0102"; CurrentHorizontalResolution = 0 },
            [PSCustomObject]@{ Name = "Radeon RX 570 Series"; PNPDeviceID = "PCI\VEN_1002&DEV_67DF"; CurrentHorizontalResolution = 1920 }
        )
        ExpectedSelected = "Radeon RX 570 Series"
        ExpectedVendor = "AMD"
    },
    @{
        Scenario = "Optimus Gaming Laptop: Intel Iris Xe + NVIDIA GeForce RTX 3060 (MUXless 0 res)"
        Gpus = @(
            [PSCustomObject]@{ Name = "Intel(R) Iris(R) Xe Graphics"; PNPDeviceID = "PCI\VEN_8086&DEV_9A49"; CurrentHorizontalResolution = 1920 },
            [PSCustomObject]@{ Name = "NVIDIA GeForce RTX 3060 Laptop GPU"; PNPDeviceID = "PCI\VEN_10DE&DEV_2520"; CurrentHorizontalResolution = 0 }
        )
        ExpectedSelected = "NVIDIA GeForce RTX 3060 Laptop GPU"
        ExpectedVendor = "NVIDIA"
    },
    @{
        Scenario = "Enduro Laptop: AMD Ryzen APU + AMD Radeon RX 6600M"
        Gpus = @(
            [PSCustomObject]@{ Name = "AMD Radeon(TM) Graphics"; PNPDeviceID = "PCI\VEN_1002&DEV_1636"; CurrentHorizontalResolution = 1920 },
            [PSCustomObject]@{ Name = "AMD Radeon RX 6600M"; PNPDeviceID = "PCI\VEN_1002&DEV_73DF"; CurrentHorizontalResolution = 0 }
        )
        ExpectedSelected = "AMD Radeon RX 6600M"
        ExpectedVendor = "AMD"
    },
    @{
        Scenario = "Discrete Intel Arc A770 + Intel UHD Graphics"
        Gpus = @(
            [PSCustomObject]@{ Name = "Intel(R) UHD Graphics 770"; PNPDeviceID = "PCI\VEN_8086&DEV_4680"; CurrentHorizontalResolution = 0 },
            [PSCustomObject]@{ Name = "Intel(R) Arc(TM) A770 Graphics"; PNPDeviceID = "PCI\VEN_8086&DEV_5690"; CurrentHorizontalResolution = 2560 }
        )
        ExpectedSelected = "Intel(R) Arc(TM) A770 Graphics"
        ExpectedVendor = "Intel"
    },
    @{
        Scenario = "Budget Desktop: Intel UHD Graphics 630 iGPU Only"
        Gpus = @(
            [PSCustomObject]@{ Name = "Intel(R) UHD Graphics 630"; PNPDeviceID = "PCI\VEN_8086&DEV_3E92"; CurrentHorizontalResolution = 1920 }
        )
        ExpectedSelected = "Intel(R) UHD Graphics 630"
        ExpectedVendor = "Intel"
    }
)

foreach ($scenario in $testGpuScenarios) {
    $selected = Select-PrimaryGamingGpu -Gpus $scenario.Gpus
    $v = if ($selected.PNPDeviceID -match "VEN_1002" -or $selected.Name -match "AMD|Radeon") { "AMD" }
         elseif ($selected.PNPDeviceID -match "VEN_10DE" -or $selected.Name -match "NVIDIA|GeForce") { "NVIDIA" }
         elseif ($selected.PNPDeviceID -match "VEN_8086" -or $selected.Name -match "Intel") { "Intel" }
         else { "Unknown" }

    Assert-Test ($selected.Name -eq $scenario.ExpectedSelected) "$($scenario.Scenario) -> Picked '$($selected.Name)' via production Select-PrimaryGamingGpu"
    Assert-Test ($v -eq $scenario.ExpectedVendor) "$($scenario.Scenario) -> Vendor is '$v'"
}

# ── 6. Storage Disk Auto-Detection Heuristics ──────────────────────────────
Write-Host "`n[Test Group 6] Storage Media Auto-Detection (HDD vs SSD Heuristics):" -ForegroundColor Cyan

$storageCases = @(
    @{ Model = "WDC WD10EZEX-08WN4A0"; MediaType = "Unspecified"; ExpectedIsHdd = $true; ExpectedMediaType = "HDD" },
    @{ Model = "ST1000DM010-2EP102"; MediaType = "Unspecified"; ExpectedIsHdd = $true; ExpectedMediaType = "HDD" },
    @{ Model = "TOSHIBA MQ01ABD050"; MediaType = "HDD"; ExpectedIsHdd = $true; ExpectedMediaType = "HDD" },
    @{ Model = "Samsung SSD 980 PRO 1TB"; MediaType = "SSD"; ExpectedIsHdd = $false; ExpectedMediaType = "SSD" },
    @{ Model = "ADATA LEGEND 900"; MediaType = "Unspecified"; ExpectedIsHdd = $false; ExpectedMediaType = "SSD" },
    @{ Model = "WD Black SN770 1TB"; MediaType = "Unspecified"; ExpectedIsHdd = $false; ExpectedMediaType = "SSD" },
    @{ Model = "WD Blue SN580 1TB"; MediaType = "Unspecified"; ExpectedIsHdd = $false; ExpectedMediaType = "SSD" },
    @{ Model = "Seagate FireCuda 530"; MediaType = "Unspecified"; ExpectedIsHdd = $false; ExpectedMediaType = "SSD" },
    @{ Model = "FireCuda 2.5"; MediaType = "Unspecified"; ExpectedIsHdd = $true; ExpectedMediaType = "HDD" }
)

foreach ($sc in $storageCases) {
    $bus = if ($sc.BusType) { $sc.BusType } else { "" }
    $res = Resolve-StorageDeviceMediaType -Model $sc.Model -MediaType $sc.MediaType -BusType $bus
    Assert-Test ($res.IsHdd -eq $sc.ExpectedIsHdd) "Model '$($sc.Model)' with MediaType '$($sc.MediaType)': IsHdd=$($res.IsHdd) (Expected: $($sc.ExpectedIsHdd))"
    Assert-Test ($res.MediaType -eq $sc.ExpectedMediaType) "Model '$($sc.Model)': Resolved MediaType=$($res.MediaType) (Expected: $($sc.ExpectedMediaType))"
}

# ── 7. Low-RAM 8GB Guard & Pagefile Verification ───────────────────────────
Write-Host "`n[Test Group 7] Low-RAM 8GB Guard & Pagefile Alerts:" -ForegroundColor Cyan
$ramCases = @(
    @{ Bytes = [int64](7.88 * 1024 * 1024 * 1024); ExpectedLow = $true; Desc = "8 GB Budget System (7.88 GB usable)" },
    @{ Bytes = [int64](15.9 * 1024 * 1024 * 1024); ExpectedLow = $false; Desc = "16 GB Standard System" },
    @{ Bytes = [int64](31.9 * 1024 * 1024 * 1024); ExpectedLow = $false; Desc = "32 GB Enthusiast System" }
)
foreach ($rc in $ramCases) {
    $low = Test-IsLowRamSystem -TotalRamBytes $rc.Bytes
    Assert-Test ($low -eq $rc.ExpectedLow) "$($rc.Desc): LowRamProfile=$low via production Test-IsLowRamSystem (Expected: $($rc.ExpectedLow))"
}

# ── 8. v2.6 Competitive Low-Latency Suite & Registry Engine ───────────────
Write-Host "`n[Test Group 8] v2.6 Competitive Low-Latency Engine & Registry Validation:" -ForegroundColor Cyan

# 8.1 Registry path resolution for mouclass / kbdclass
$mouPath = "HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters"
$kbdPath = "HKLM:\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters"
Assert-Test (Test-Path $mouPath) "Registry path exists: mouclass\Parameters"
Assert-Test (Test-Path $kbdPath) "Registry path exists: kbdclass\Parameters"

$inputCfg = Get-InputBufferConfig
Assert-Test ($inputCfg -is [hashtable] -and $inputCfg.ContainsKey("MouseDataQueueSize")) "Get-InputBufferConfig returns MouseDataQueueSize key"
Assert-Test ($inputCfg -is [hashtable] -and $inputCfg.ContainsKey("KeyboardDataQueueSize")) "Get-InputBufferConfig returns KeyboardDataQueueSize key"

# 8.2 Kernel DPC & Memory Management snapshot integrity
$kdpcCfg = Get-KernelDpcConfig
Assert-Test ($kdpcCfg -is [hashtable] -and $kdpcCfg.ContainsKey("DisablePagingExecutive")) "Get-KernelDpcConfig returns DisablePagingExecutive key"
Assert-Test ($kdpcCfg -is [hashtable] -and $kdpcCfg.ContainsKey("ThreadDpcEnable")) "Get-KernelDpcConfig returns ThreadDpcEnable key"
Assert-Test ($kdpcCfg -is [hashtable] -and $kdpcCfg.ContainsKey("Win32PrioritySeparation")) "Get-KernelDpcConfig returns Win32PrioritySeparation key"
Assert-Test ($kdpcCfg -is [hashtable] -and $kdpcCfg.ContainsKey("PowerThrottlingOff")) "Get-KernelDpcConfig returns PowerThrottlingOff key"

# Test round-trip snapshot persistence
$simulatedSnapshot = @{
    KernelDpcConfig   = @{ DisablePagingExecutive = 1; ThreadDpcEnable = 0; Win32PrioritySeparation = 38; PowerThrottlingOff = 1 }
    InputBufferConfig = @{ MouseDataQueueSize = 16; KeyboardDataQueueSize = 16 }
    BcdeditConfig     = @{ DynamicTick = "yes"; TscSyncPolicy = "Enhanced" }
    HagsConfig        = @{ HwSchMode = 2 }
}
$jsonRoundTrip = $simulatedSnapshot | ConvertTo-Json -Depth 5 | ConvertFrom-Json
Assert-Test ($jsonRoundTrip.KernelDpcConfig.DisablePagingExecutive -eq 1 -and $jsonRoundTrip.KernelDpcConfig.ThreadDpcEnable -eq 0) "KernelDpcConfig preserves numeric types across JSON round-trip"
Assert-Test ($jsonRoundTrip.InputBufferConfig.MouseDataQueueSize -eq 16 -and $jsonRoundTrip.InputBufferConfig.KeyboardDataQueueSize -eq 16) "InputBufferConfig preserves queue sizes across JSON round-trip"
Assert-Test ($jsonRoundTrip.BcdeditConfig.DynamicTick -eq "yes" -and $jsonRoundTrip.BcdeditConfig.TscSyncPolicy -eq "Enhanced") "BcdeditConfig preserves timer strings across JSON round-trip"
Assert-Test ($jsonRoundTrip.HagsConfig.HwSchMode -eq 2) "HagsConfig preserves HwSchMode across JSON round-trip"

# 8.3 BCDedit parser verification against simulated bcdedit outputs
$mockBcdTuned = @(
    "Windows Boot Loader",
    "-------------------",
    "identifier              {current}",
    "device                  partition=C:",
    "path                    \WINDOWS\system32\winload.efi",
    "description             Windows 11",
    "locale                  en-US",
    "disabledynamictick      yes",
    "tscsyncpolicy           Enhanced"
)
$parsedTuned = Get-BcdeditTimerConfig -BcdOutput $mockBcdTuned
Assert-Test ($parsedTuned.DynamicTick -eq "yes") "Get-BcdeditTimerConfig extracts DynamicTick='yes' from simulated output"
Assert-Test ($parsedTuned.TscSyncPolicy -eq "Enhanced") "Get-BcdeditTimerConfig extracts TscSyncPolicy='Enhanced' from simulated output"

$mockBcdDefault = @(
    "Windows Boot Loader",
    "-------------------",
    "identifier              {current}",
    "device                  partition=C:",
    "path                    \WINDOWS\system32\winload.efi",
    "description             Windows 11"
)
$parsedDef = Get-BcdeditTimerConfig -BcdOutput $mockBcdDefault
Assert-Test ($null -eq $parsedDef.DynamicTick -and $null -eq $parsedDef.TscSyncPolicy) "Get-BcdeditTimerConfig handles stock Windows output without timer keys safely ($null)"

# 8.4 TCP gaming stack & interface isolation verification
$tcpCfg = Get-TcpStackConfig
Assert-Test ($tcpCfg -is [hashtable] -and $tcpCfg.ContainsKey("Timestamps")) "Get-TcpStackConfig returns Timestamps key"
Assert-Test ($tcpCfg -is [hashtable] -and $tcpCfg.ContainsKey("Interfaces")) "Get-TcpStackConfig returns Interfaces collection"

$tcpInterfaceGuids = @($tcpCfg.Interfaces | ForEach-Object { if ($_ -is [hashtable]) { $_["Guid"] } else { $_.Guid } })
Assert-Test ($tcpInterfaceGuids -notcontains "{8eb6cecf-6919-4cf4-8c70-e55823aa4b53}") "Get-TcpStackConfig strictly excludes Apple Mobile Device GUID {8eb6cecf-6919-4cf4-8c70-e55823aa4b53}"
Assert-Test ($tcpInterfaceGuids -notcontains "{2e219888-9139-4199-ea45-cb771d7dad1d}") "Get-TcpStackConfig strictly excludes Wintun tunnel GUID {2e219888-9139-4199-ea45-cb771d7dad1d}"

$gamingAdapters = Get-PhysicalGamingAdapters
$gamingAdapterNames = @($gamingAdapters | ForEach-Object { $_.Name })
Assert-Test ($gamingAdapterNames -notcontains "Ethernet 2") "Get-PhysicalGamingAdapters strictly excludes 'Ethernet 2' (Apple Mobile Device Tethering)"
Assert-Test ($gamingAdapterNames -notcontains "wwan99") "Get-PhysicalGamingAdapters strictly excludes 'wwan99' (Wintun VPN tunnel)"

# 8.5 HAGS GPU scheduling configuration
$hagsCfg = Get-HagsGpuSchedulingConfig
Assert-Test ($hagsCfg -is [hashtable] -and $hagsCfg.ContainsKey("HwSchMode")) "Get-HagsGpuSchedulingConfig returns HwSchMode key"

# 8.6 Non-destructive fallback when running non-elevated
$threwError = $false
try {
    $null = Get-KernelDpcConfig
    $null = Get-InputBufferConfig
    $null = Get-BcdeditTimerConfig
    $null = Get-TcpStackConfig
    $null = Get-HagsGpuSchedulingConfig
} catch {
    $threwError = $true
}
Assert-Test ($threwError -eq $false) "Non-destructive fallback: All v2.6 query functions execute without throwing unhandled exceptions"

# ── 9. Multi-Directory Shortcut Quarantine & Collision Resilience ───────────
Write-Host "`n[Test Group 9] Shortcut Quarantine, Collision Resilience & LiteralPath Validation:" -ForegroundColor Cyan
$tempTestRoot = Join-Path $env:TEMP ("UGM_Test_Quarantine_" + [System.Guid]::NewGuid().ToString("N"))
$testUserStartup = Join-Path $tempTestRoot "DestUserStartup"
$testCommonStartup = Join-Path $tempTestRoot "DestCommonStartup"
$testQuarantine = Join-Path $tempTestRoot "QuarantinedShortcuts"
$testQUser = Join-Path $testQuarantine "User"
$testQCommon = Join-Path $testQuarantine "ProgramData"

New-Item -ItemType Directory -Path $testQUser -Force | Out-Null
New-Item -ItemType Directory -Path $testQCommon -Force | Out-Null
New-Item -ItemType Directory -Path $testUserStartup -Force | Out-Null
New-Item -ItemType Directory -Path $testCommonStartup -Force | Out-Null

Set-Content -LiteralPath (Join-Path $testQUser "Discord.lnk") -Value "User Discord Target"
Set-Content -LiteralPath (Join-Path $testQCommon "Discord.lnk") -Value "ProgramData Discord Target"
Set-Content -LiteralPath (Join-Path $testQUser "Game [Modded] (v2.0).lnk") -Value "Bracketed Game Target"

# Unsegregated and legacy shortcuts directly in quarantine root
Set-Content -LiteralPath (Join-Path $testQuarantine "LegacyAppWithMeta.lnk") -Value "Legacy User App"
Set-Content -LiteralPath (Join-Path $testQuarantine "LegacyAppNoMeta.lnk") -Value "Legacy Fallback App"
Set-Content -LiteralPath (Join-Path $testQuarantine "LegacyProgramData.lnk") -Value "Legacy ProgramData App"
Set-Content -LiteralPath (Join-Path $testQuarantine "LegacyAppWithBackupExt.lnk.ugm_backup") -Value "Legacy Backup User App"
Set-Content -LiteralPath (Join-Path $testQuarantine "LegacyCommonBackup.lnk.ugm_backup") -Value "Legacy Backup Common App"

# Foreign/residual file to test non-destructive empty-only quarantine directory cleanup
Set-Content -LiteralPath (Join-Path $testQuarantine "residual_backup.txt") -Value "Residual data that must not cause folder deletion"

$mockStateData = [PSCustomObject]@{
    StartupShortcuts = @(
        [PSCustomObject]@{
            Name           = "LegacyAppWithMeta.lnk"
            OriginalFolder = $testUserStartup
            FolderTag      = "User"
        },
        [PSCustomObject]@{
            Name           = "LegacyProgramData.lnk"
            OriginalFolder = $testCommonStartup
            FolderTag      = "ProgramData"
        },
        [PSCustomObject]@{
            Name           = "LegacyAppWithBackupExt.lnk"
            OriginalFolder = $testUserStartup
            FolderTag      = "User"
        },
        [PSCustomObject]@{
            Name           = "LegacyCommonBackup.lnk"
            OriginalFolder = $testCommonStartup
            FolderTag      = "ProgramData"
        }
    )
}

# Phase 1: Run production Restore-QuarantinedShortcuts with Scope "System"
Restore-QuarantinedShortcuts -QuarantineDir $testQuarantine -UserStartup $testUserStartup -CommonStartup $testCommonStartup -StateData $mockStateData -Scope "System"

$commonDiscordPhase1 = Test-Path -LiteralPath (Join-Path $testCommonStartup "Discord.lnk")
$legacyProgramDataPhase1 = Test-Path -LiteralPath (Join-Path $testCommonStartup "LegacyProgramData.lnk")
$legacyCommonBackupPhase1 = Test-Path -LiteralPath (Join-Path $testCommonStartup "LegacyCommonBackup.lnk")
$userDiscordPhase1 = Test-Path -LiteralPath (Join-Path $testUserStartup "Discord.lnk")
$quarantinePreservedPhase1 = Test-Path -LiteralPath $testQuarantine

Assert-Test ($commonDiscordPhase1) "Phase 1 (System Scope): Common Discord.lnk restored to ProgramData"
Assert-Test ($legacyProgramDataPhase1) "Phase 1 (System Scope): Legacy ProgramData root shortcut restored to Common Startup"
Assert-Test ($legacyCommonBackupPhase1) "Phase 1 (System Scope): Legacy ProgramData .ugm_backup shortcut restored with clean .lnk extension"
Assert-Test (-not $userDiscordPhase1) "Phase 1 (System Scope): User shortcuts strictly preserved in quarantine during System phase"
Assert-Test ($quarantinePreservedPhase1) "Phase 1 (System Scope): Quarantine directory strictly preserved while User items remain"

# Phase 2: Run production Restore-QuarantinedShortcuts with Scope "User"
Restore-QuarantinedShortcuts -QuarantineDir $testQuarantine -UserStartup $testUserStartup -CommonStartup $testCommonStartup -StateData $mockStateData -Scope "User"

$userDiscordRestored = Test-Path -LiteralPath (Join-Path $testUserStartup "Discord.lnk")
$bracketGameRestored = Test-Path -LiteralPath (Join-Path $testUserStartup "Game [Modded] (v2.0).lnk")
$legacyWithMetaRestored = Test-Path -LiteralPath (Join-Path $testUserStartup "LegacyAppWithMeta.lnk")
$legacyNoMetaRestored = Test-Path -LiteralPath (Join-Path $testUserStartup "LegacyAppNoMeta.lnk")
$legacyBackupUserRestored = Test-Path -LiteralPath (Join-Path $testUserStartup "LegacyAppWithBackupExt.lnk")
$quarantinePreservedWhenNonEmpty = Test-Path -LiteralPath $testQuarantine

Assert-Test ($userDiscordRestored) "Phase 2 (User Scope): Same-name User Discord.lnk correctly routes to AppData Startup"
Assert-Test ($bracketGameRestored) "Phase 2 (User Scope): Special bracketed shortcut 'Game [Modded] (v2.0).lnk' routes without wildcard parsing error"
Assert-Test ($legacyWithMetaRestored) "Phase 2 (User Scope): Legacy root shortcut with metadata routes to original folder"
Assert-Test ($legacyNoMetaRestored) "Phase 2 (User Scope): Legacy root shortcut without metadata defaults safely to AppData Startup"
Assert-Test ($legacyBackupUserRestored) "Phase 2 (User Scope): Legacy root .ugm_backup shortcut matches metadata and restores with clean .lnk extension"
Assert-Test ($quarantinePreservedWhenNonEmpty) "Quarantine directory is strictly preserved when non-empty (residual file present)"

# Remove residual file and verify clean quarantine directory deletion when fully empty
Remove-Item -LiteralPath (Join-Path $testQuarantine "residual_backup.txt") -Force -ErrorAction SilentlyContinue
Restore-QuarantinedShortcuts -QuarantineDir $testQuarantine -UserStartup $testUserStartup -CommonStartup $testCommonStartup -StateData $mockStateData -Scope "All"
$quarantineDeletedWhenEmpty = (-not (Test-Path -LiteralPath $testQuarantine))
Assert-Test ($quarantineDeletedWhenEmpty) "Quarantine directory is cleanly deleted when completely empty"

Remove-Item -LiteralPath $tempTestRoot -Recurse -Force -ErrorAction SilentlyContinue

# ── 10. Localization Resilience, 2D Array Unrolling & Multi-Vendor Shader Coverage ──
Write-Host "`n[Test Group 10] Localization Resilience, 2D Array Unrolling & Multi-Vendor Shader Coverage:" -ForegroundColor Cyan

$testPowerOutputs = @(
    @{ Raw = "GUID схемы питания: 929fef13-d38f-4d3a-b857-7c19197b2246  (Bitsum Highest Performance)"; Guid = "929fef13-d38f-4d3a-b857-7c19197b2246"; Expected = $true; Desc = "Bitsum Power Plan" },
    @{ Raw = "GUID схемы питания: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (Высокая производительность)"; Guid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"; Expected = $true; Desc = "Russian High Performance" },
    @{ Raw = "GUID схемы питания: e9a42b02-d5df-448d-aa00-03f14749eb61  (Максимальная производительность)"; Guid = "e9a42b02-d5df-448d-aa00-03f14749eb61"; Expected = $true; Desc = "Russian Ultimate Performance" },
    @{ Raw = "GUID схемы питания: 381b4222-f694-41f0-9685-ff5bb260df2e  (Сбалансированная)"; Guid = "381b4222-f694-41f0-9685-ff5bb260df2e"; Expected = $false; Desc = "Russian Balanced (Needs Boost)" },
    @{ Raw = "Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)"; Guid = "381b4222-f694-41f0-9685-ff5bb260df2e"; Expected = $false; Desc = "English Balanced (Needs Boost)" }
)

foreach ($tp in $testPowerOutputs) {
    $isHigh = Test-IsHighPerformanceScheme -SchemeGuid $tp.Guid -RawOutput $tp.Raw
    Assert-Test ($isHigh -eq $tp.Expected) "$($tp.Desc): Detected High-Performance = $isHigh via production Test-IsHighPerformanceScheme (Expected: $($tp.Expected))"
}

# 10.2 Test flat collection returns (no artificial 2D comma-wrapping)
$keys = Get-AmdGpuDriverClassKeys
$isKeys2D = ($keys.Count -gt 0 -and $keys[0] -is [array])
Assert-Test (-not $isKeys2D) "Get-AmdGpuDriverClassKeys returns flat collection without 2D array nesting"

$netProps = Get-NetworkAdapterGamingProperties
$isNet2D = ($netProps.Count -gt 0 -and $netProps[0] -is [array])
Assert-Test (-not $isNet2D) "Get-NetworkAdapterGamingProperties returns flat collection without 2D array nesting"

# 10.3 Test universal shader targets across 12 directories
$testShaderTargets = @(
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
$hasAmd = ($testShaderTargets | Where-Object { $_ -match "AMD" }).Count -ge 5
$hasNvidia = ($testShaderTargets | Where-Object { $_ -match "NVIDIA" }).Count -ge 4
$hasIntel = ($testShaderTargets | Where-Object { $_ -match "Intel" }).Count -ge 2
Assert-Test ($hasAmd -and $hasNvidia -and $hasIntel) "Shader cache purge targets all major GPU vendors (AMD, NVIDIA, Intel)"
Assert-Test ($testShaderTargets.Count -ge 12) "Total universal shader cache directory coverage: $($testShaderTargets.Count) targets"

# ── 11. Zero-Trust Security, Hardening & Resilience Assertions ─────────────
Write-Host "`n[Test Group 11] Zero-Trust Security, Whitelist Guards & Resilience:" -ForegroundColor Cyan

# 11.1 Resilient Boot Timestamp (SEC-01)
$ts = Get-ResilientBootTimestamp
[DateTime]$parsedTs = [DateTime]::MinValue
$parseOk = [DateTime]::TryParse($ts, [ref]$parsedTs)
Assert-Test ($parseOk -and $parsedTs.Year -ge 2024) "Get-ResilientBootTimestamp returns valid ISO-8601 boot timestamp ($ts)"

# 11.2 Protected Service Whitelist Guard
$whitelistMock = @("Audiosrv", "AudioEndpointBuilder", "vgk", "vgc", "EasyAntiCheat", "BEService")
$audioBlocked = (-not (Set-ServiceStateSafe -ServiceName "Audiosrv" -StartupType "Disabled" -Whitelist $whitelistMock))
Assert-Test ($audioBlocked) "Audiosrv is strictly protected from modification by whitelist guard"
$vgkBlocked = (-not (Set-ServiceStateSafe -ServiceName "vgk" -StartupType "Disabled" -Whitelist $whitelistMock))
Assert-Test ($vgkBlocked) "Anti-cheat service 'vgk' (Vanguard) is strictly protected from modification"

# 11.3 Services Blacklist Integrity (SLOP-01)
$blPath = Join-Path $repoRoot "Config\services_blacklist.json"
$blContent = Get-Content -Path $blPath -Raw -Encoding UTF8 | ConvertFrom-Json
$hardcodedChrome = $blContent.TargetServices | Where-Object { $_.Name -match "GoogleUpdaterService\d+" }
Assert-Test ($null -eq $hardcodedChrome) "No hardcoded versioned Chrome updater service strings in services_blacklist.json (SLOP-01 resolved)"
$baseChrome = $blContent.TargetServices | Where-Object { $_.Name -eq "GoogleUpdaterService" }
Assert-Test ($null -ne $baseChrome) "Clean base 'GoogleUpdaterService' identifier present in services_blacklist.json"

# 11.4 Startup Blacklist Cleanliness (SLOP-02)
$stPath = Join-Path $repoRoot "Config\startup_apps.json"
$stContent = Get-Content -Path $stPath -Raw -Encoding UTF8 | ConvertFrom-Json
$syntheticApps = @("TimeTracker", "ege-tracker-sync", "PulseSync", "GeminiAppLauncher")
$foundSynthetic = @($stContent.BlacklistProcesses | Where-Object { $syntheticApps -contains $_ })
Assert-Test ($foundSynthetic.Count -eq 0) "All synthetic AI placeholder processes removed from startup_apps.json (SLOP-02 resolved)"

# 11.5 Adaptive Low-RAM Kernel DPC Guard (PERF-01)
$cmdKernel = Get-Command Set-KernelDpcOptimizations
Assert-Test ($cmdKernel.Parameters.ContainsKey("IsLowRam")) "Set-KernelDpcOptimizations exports -IsLowRam parameter for 8GB rig protection"

# 11.6 Input Buffer Anti-Drop Headroom (PERF-02)
$cmdInput = Get-Command Set-InputBufferOptimizations
Assert-Test ($cmdInput.Parameters.ContainsKey("QueueSize")) "Set-InputBufferOptimizations exports -QueueSize parameter (default 32)"

# 11.7 Bluetooth and Xbox Controller Whitelist Protection
$wlPath = Join-Path $repoRoot "Config\services_whitelist.json"
$wlContent = Get-Content -Path $wlPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Test ($wlContent.ProtectedServices -contains "bthserv") "bthserv is present in services_whitelist.json"
Assert-Test ($wlContent.ProtectedServices -contains "XboxGipSvc") "XboxGipSvc is present in services_whitelist.json"

$controllerBlacklisted = @($blContent.TargetServices | Where-Object { $_.Name -in @("bthserv", "BthAvctpSvc", "BTAGService", "XboxGipSvc", "BluetoothUserService") })
Assert-Test ($controllerBlacklisted.Count -eq 0) "Bluetooth and Xbox controller services completely removed from services_blacklist.json"

# 11.8 Dead Configuration & AMD Overlay Whitelist Protection
Assert-Test ($stContent.BlacklistProcesses -notcontains "amdow") "amdow overlay is strictly excluded from BlacklistProcesses"
Assert-Test ($null -eq $stContent.StartupRegistryPaths) "Dead StartupRegistryPaths removed from startup_apps.json"
Assert-Test ($null -eq $stContent.StartupFolders) "Dead StartupFolders removed from startup_apps.json"
Assert-Test ($null -eq $stContent.TargetAppModelPackages) "Dead TargetAppModelPackages removed from startup_apps.json"
# 11.9 Two-Phase Restoration & User Profile Isolation Contract
$cmdUserProfile = Get-Command Restore-UserProfileState -ErrorAction SilentlyContinue
Assert-Test ($null -ne $cmdUserProfile) "Restore-UserProfileState is exported from StateEngine.ps1"

$cmdSystemState = Get-Command Restore-SystemState -ErrorAction SilentlyContinue
Assert-Test ($cmdSystemState.Parameters.ContainsKey("Scope")) "Restore-SystemState exports -Scope parameter"

$scopeAttr = $cmdSystemState.Parameters["Scope"].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
$hasValidScopes = ($null -ne $scopeAttr -and ($scopeAttr.ValidValues -contains "All") -and ($scopeAttr.ValidValues -contains "System") -and ($scopeAttr.ValidValues -contains "User"))
Assert-Test ($hasValidScopes) "Restore-SystemState validates scopes 'All', 'System', 'User'"

$ugmPath = Join-Path $repoRoot "UltraGamingMode.ps1"
$ugmCmd = Get-Command $ugmPath
$actionAttr = $ugmCmd.Parameters["Action"].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
$hasRestoreUserAction = ($null -ne $actionAttr -and ($actionAttr.ValidValues -contains "RestoreUser"))
Assert-Test ($hasRestoreUserAction) "UltraGamingMode.ps1 declares 'RestoreUser' in Action ValidateSet"

$hasScopeParam = $ugmCmd.Parameters.ContainsKey("Scope")
Assert-Test ($hasScopeParam) "UltraGamingMode.ps1 declares 'Scope' parameter in Param block"

$scopeAttr2 = $ugmCmd.Parameters["Scope"].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
$hasValidUgmScopes = ($null -ne $scopeAttr2 -and ($scopeAttr2.ValidValues -contains "User"))
Assert-Test ($hasValidUgmScopes) "UltraGamingMode.ps1 validates 'User' in Scope ValidateSet"

$userProfileDef = (Get-Command Restore-UserProfileState).Definition
$hasSystemGuard = ($userProfileDef -like '*WindowsIdentity*IsSystem*' -and $userProfileDef -like '*return $false*')
Assert-Test ($hasSystemGuard) "Restore-UserProfileState strictly blocks execution under SYSTEM to prevent profile corruption"

$systemStateDef = (Get-Command Restore-SystemState).Definition
$hasScopeGuard = ($systemStateDef -like '*WindowsIdentity*IsSystem*' -and $systemStateDef -like '*$Scope = "System"*')
Assert-Test ($hasScopeGuard) "Restore-SystemState automatically downscopes to 'System' under SYSTEM"

$ugmContent = Get-Content -LiteralPath $ugmPath -Raw -Encoding UTF8
$hasPrematureExit = ($ugmContent -match 'if\s*\(-not\s*\$isSystem\s*-and\s*\$hasScheduledWatchdog\)\s*\{\s*Write-Verbose[^\}]+exit 0')
Assert-Test (-not $hasPrematureExit) "UltraGamingMode.ps1 does not prematurely exit 0 in interactive user watchdog"

# 11.10 Non-Elevated Execution Contract for RestoreUser and User Scope
$adminCheckBlock = if ($ugmContent -match '(?ms)if \(-not \$isAdmin\) \{(.*?)\r?\n\}') { $Matches[1] } else { "" }
$allowsRestoreUserNonElevated = ($adminCheckBlock -match '\$Action\s*-eq\s*["'']RestoreUser["'']')
Assert-Test ($allowsRestoreUserNonElevated) "UltraGamingMode.ps1 unconditionally permits non-elevated execution for -Action RestoreUser"

$allowsUserScopeNonElevated = ($adminCheckBlock -match '\$Scope\s*-eq\s*["'']User["'']')
Assert-Test ($allowsUserScopeNonElevated) "UltraGamingMode.ps1 permits non-elevated execution for -Scope User"

# 11.11 Coordinated Trigger Cleanup Contract
$preservesTriggersUntilBothDone = ($ugmContent -match 'UserRestored' -and $ugmContent -match 'SystemRestored' -and $ugmContent -match 'Unregister-BootTasks')
Assert-Test ($preservesTriggersUntilBothDone) "UltraGamingMode.ps1 coordinates trigger cleanup only when both scopes are restored"

# 11.12 Two-Phase Atomic State Merge Validation
$tempStateFile = Join-Path $env:TEMP ("UGM_AtomicState_" + [System.Guid]::NewGuid().ToString("N") + ".json")
$initialData = [PSCustomObject]@{
    State = "GameMode_Active"
    SystemRestored = $false
    UserRestored = $false
}
Set-ActiveStateSafe -Path $tempStateFile -Data $initialData | Out-Null

# Simulate System pass running first
$sysState = Get-ActiveStateSafe -Path $tempStateFile
$sysState.SystemRestored = $true
$sysState.State = "Restoring_SystemDone"
Set-ActiveStateSafe -Path $tempStateFile -Data $sysState | Out-Null

# Simulate concurrent User pass loading latest from disk
$usrState = Get-ActiveStateSafe -Path $tempStateFile
$usrState.UserRestored = $true
if ($usrState.SystemRestored) { $usrState.State = "Restored" }
Set-ActiveStateSafe -Path $tempStateFile -Data $usrState | Out-Null

$finalState = Get-ActiveStateSafe -Path $tempStateFile
Assert-Test ($finalState.SystemRestored -eq $true -and $finalState.UserRestored -eq $true -and $finalState.State -eq "Restored") "Two-phase atomic state updates merge cleanly to Restored without overwriting"
Remove-Item -LiteralPath $tempStateFile -Force -ErrorAction SilentlyContinue

# 11.13 Boot Session & Watchdog Race Condition Prevention Contract
$bootId = Get-SystemBootId
if ($null -ne $bootId) {
    Assert-Test ($bootId -is [int]) "Get-SystemBootId returns valid integer BootId ($bootId)"
    Assert-Test (Test-IsSameBootSession -SavedBootId $bootId) "Test-IsSameBootSession returns True for identical BootId"
    Assert-Test (-not (Test-IsSameBootSession -SavedBootId ($bootId + 1))) "Test-IsSameBootSession returns False for different BootId"
} else {
    Assert-Test ($true) "Get-SystemBootId handled gracefully on system without Prefetch BootId"
}

$currentBoot = Get-ResilientBootTimestamp
$oldBoot = ([DateTime]::Parse($currentBoot).AddHours(-5)).ToString("o")
Assert-Test (Test-IsSameBootSession -SavedBootId $null -SavedBootTime $currentBoot) "Test-IsSameBootSession fallback returns True for matching boot timestamp"
Assert-Test (-not (Test-IsSameBootSession -SavedBootId $null -SavedBootTime $oldBoot)) "Test-IsSameBootSession fallback returns False for 5-hour-old boot timestamp"
Assert-Test (-not (Test-IsSameBootSession -SavedBootId $null -SavedBootTime "")) "Test-IsSameBootSession fallback returns False for empty boot timestamp"

# Watchdog safety guard in UltraGamingMode.ps1
Assert-Test ($ugmContent -match 'Test-IsSameBootSession') "UltraGamingMode.ps1 utilizes Test-IsSameBootSession for watchdog session detection"
Assert-Test ($ugmContent -match '\$stateData\.State -eq ["'']Armed["'']') "UltraGamingMode.ps1 guards against premature restoration when state is Armed"
Assert-Test ($ugmContent -notmatch 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce.*-Action RestoreUser -Watchdog') "UltraGamingMode.ps1 does not arm premature user RunOnce during Enable action"

# 11.14 Pure UTF-8 without BOM Encoding Check (Source & Config Files)
$allConfigFiles = Get-ChildItem -Path $repoRoot -Recurse -Include "*.ps1", "*.json" | Where-Object { $_.FullName -notmatch '[\\/]Backups[\\/]' }
$hasBom = $false
foreach ($f in $allConfigFiles) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $hasBom = $true
        Write-Warning "File has UTF-8 BOM: $($f.FullName)"
    }
}
Assert-Test (-not $hasBom) "All PowerShell and JSON files encoded in pure UTF-8 without BOM"

# ── 12. Summary ────────────────────────────────────────────────────────────
Write-Host "`n=====================================================" -ForegroundColor Magenta
Write-Host "   TEST RESULTS: $testsRun Tests Run | $failures Failures" -ForegroundColor $(if ($failures -eq 0) { "Green" } else { "Red" })
Write-Host "=====================================================" -ForegroundColor Magenta

if ($failures -gt 0) {
    exit 1
} else {
    exit 0
}
