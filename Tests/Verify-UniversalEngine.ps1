<#
.SYNOPSIS
    Unit, configuration, and behavioral verification suite for Ultra Gaming Mode.
#>

$ErrorActionPreference = "Stop"
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}
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
Write-Host "   ULTRA GAMING MODE ENGINE VERIFICATION SUITE       " -ForegroundColor Magenta
Write-Host "=====================================================" -ForegroundColor Magenta

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

# -- 1. PowerShell AST Syntax & UTF-8 No-BOM Validation -----------------------
Write-Host "`n[Test Group 1] PowerShell AST Syntax & UTF-8 Encoding Validation:" -ForegroundColor Cyan
$scripts = Get-ChildItem -Path $repoRoot -Recurse -Filter "*.ps1" | Where-Object { $_.FullName -notmatch '[\\/](node_modules|target|\.git)[\\/]' }
foreach ($s in $scripts) {
    $errs = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($s.FullName, [ref]$null, [ref]$errs)
    Assert-Test ($errs.Count -eq 0) "Script '$($s.Name)' parses with 0 AST errors"
}

$allConfigFiles = Get-ChildItem -Path $repoRoot -Recurse -Include "*.ps1", "*.json" | Where-Object { $_.FullName -notmatch '[\\/](Backups|node_modules|target|\.git|EBWebView|dist)[\\/]' }
$hasBom = $false
foreach ($f in $allConfigFiles) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $hasBom = $true
        Write-Warning "File has UTF-8 BOM: $($f.FullName)"
    }
}
Assert-Test (-not $hasBom) "All PowerShell and JSON files are encoded in UTF-8 without BOM"

# -- 2. Core Module Loading & Live Hardware Auto-Detection --------------------
Write-Host "`n[Test Group 2] Core Module Exports & Live Hardware Auto-Detection:" -ForegroundColor Cyan
. (Join-Path $repoRoot "Core\ServiceManager.ps1")
. (Join-Path $repoRoot "Core\SystemOptimizer.ps1")
. (Join-Path $repoRoot "Core\StateEngine.ps1")

$requiredExports = @(
    "Select-PrimaryGamingGpu", "Resolve-StorageDeviceMediaType", "Test-IsLowRamSystem",
    "Test-IsHighPerformanceScheme", "Set-ServiceStateSafe", "Invoke-ServiceControlSafe",
    "Get-CanonicalServiceName", "Test-ServiceInList", "Test-ServiceShouldDisableInGaming",
    "Find-MatchingLiveServices", "Test-ProcessShouldCloseInGaming", "Test-StartupEntryMatchesNames",
    "Test-SafeServiceName", "Test-IsProtectedProcess", "Stop-ProcessSafe",
    "Get-HardwareProfile", "Apply-CpuGamingOptimizations", "Apply-GpuGamingOptimizations",
    "Set-NTFSGamingOptimizations", "Restore-NTFSGamingOptimizations",
    "Get-KernelDpcConfig", "Set-KernelDpcOptimizations", "Restore-KernelDpcOptimizations",
    "Get-InputBufferConfig", "Set-InputBufferOptimizations", "Restore-InputBufferOptimizations",
    "Get-BcdeditTimerConfig", "Set-BcdeditTimerOptimizations", "Restore-BcdeditTimerOptimizations",
    "Get-TcpStackConfig", "Test-ShouldPreserveTcpTimestamps", "Set-TcpGamingStackOptimizations", "Restore-TcpGamingStackOptimizations",
    "Get-HagsGpuSchedulingConfig", "Set-HagsGpuScheduling", "Restore-HagsGpuScheduling",
    "Get-ExtendedGamingTargets", "Set-ExtendedGamingOptimizations",
    "Get-PowerLatencyConfig", "Set-PowerLatencyOptimizations", "Restore-PowerLatencyOptimizations",
    "Get-MemoryCompressionConfig", "Set-MemoryCompressionGamingState", "Restore-MemoryCompressionConfig",
    "Get-NetAdapterMsiConfig", "Set-NetAdapterMsiMode", "Restore-NetAdapterMsiMode",
    "Clear-GpuShaderCache", "Disable-UserStateAggressive", "Restore-UserProfileState", "Restore-SystemState"
)
$missingExports = @($requiredExports | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
Assert-Test ($missingExports.Count -eq 0) "All $($requiredExports.Count) core engine functions are exported (missing: $($missingExports -join ', '))"

$liveHw = Get-HardwareProfile
Assert-Test ($liveHw.CpuVendor -in @("AMD", "Intel", "Unknown")) "Live CPU Vendor detected: $($liveHw.CpuVendor)"
Assert-Test ($liveHw.LogicalCores -gt 0) "Live Logical Cores detected: $($liveHw.LogicalCores)"
Assert-Test ($liveHw.TotalRamGB -gt 0) "Live Total RAM detected: $($liveHw.TotalRamGB) GB"
Assert-Test ($liveHw.GpuVendor -in @("AMD", "NVIDIA", "Intel", "Unknown")) "Live GPU Vendor detected: $($liveHw.GpuVendor)"
Assert-Test ($null -ne $liveHw.HddProfile) "Live HddProfile evaluated: $($liveHw.HddProfile)"

# -- 3. Hardware Detection Matrix (GPU, Storage, Low-RAM, Power Plans) --------
Write-Host "`n[Test Group 3] Hardware Auto-Detection Matrix (GPU, Storage, RAM, Power):" -ForegroundColor Cyan
$testGpuScenarios = @(
    @{
        Scenario = "Desktop: Intel HD iGPU + AMD Radeon RX 570"
        Gpus = @(
            [PSCustomObject]@{ Name = "Intel(R) HD Graphics 2000"; PNPDeviceID = "PCI\VEN_8086&DEV_0102"; CurrentHorizontalResolution = 0 },
            [PSCustomObject]@{ Name = "Radeon RX 570 Series"; PNPDeviceID = "PCI\VEN_1002&DEV_67DF"; CurrentHorizontalResolution = 1920 }
        )
        ExpectedSelected = "Radeon RX 570 Series"
    },
    @{
        Scenario = "Optimus Laptop: Intel Iris Xe + NVIDIA RTX 3060 (MUXless)"
        Gpus = @(
            [PSCustomObject]@{ Name = "Intel(R) Iris(R) Xe Graphics"; PNPDeviceID = "PCI\VEN_8086&DEV_9A49"; CurrentHorizontalResolution = 1920 },
            [PSCustomObject]@{ Name = "NVIDIA GeForce RTX 3060 Laptop GPU"; PNPDeviceID = "PCI\VEN_10DE&DEV_2520"; CurrentHorizontalResolution = 0 }
        )
        ExpectedSelected = "NVIDIA GeForce RTX 3060 Laptop GPU"
    },
    @{
        Scenario = "Enduro Laptop: AMD Ryzen APU + Radeon RX 6600M"
        Gpus = @(
            [PSCustomObject]@{ Name = "AMD Radeon(TM) Graphics"; PNPDeviceID = "PCI\VEN_1002&DEV_1636"; CurrentHorizontalResolution = 1920 },
            [PSCustomObject]@{ Name = "AMD Radeon RX 6600M"; PNPDeviceID = "PCI\VEN_1002&DEV_73DF"; CurrentHorizontalResolution = 0 }
        )
        ExpectedSelected = "AMD Radeon RX 6600M"
    },
    @{
        Scenario = "Discrete Intel Arc A770 + Intel UHD 770"
        Gpus = @(
            [PSCustomObject]@{ Name = "Intel(R) UHD Graphics 770"; PNPDeviceID = "PCI\VEN_8086&DEV_4680"; CurrentHorizontalResolution = 0 },
            [PSCustomObject]@{ Name = "Intel(R) Arc(TM) A770 Graphics"; PNPDeviceID = "PCI\VEN_8086&DEV_5690"; CurrentHorizontalResolution = 2560 }
        )
        ExpectedSelected = "Intel(R) Arc(TM) A770 Graphics"
    },
    @{
        Scenario = "Integrated GPU Only: Intel UHD Graphics 630"
        Gpus = @(
            [PSCustomObject]@{ Name = "Intel(R) UHD Graphics 630"; PNPDeviceID = "PCI\VEN_8086&DEV_3E92"; CurrentHorizontalResolution = 1920 }
        )
        ExpectedSelected = "Intel(R) UHD Graphics 630"
    }
)
foreach ($scenario in $testGpuScenarios) {
    $selected = Select-PrimaryGamingGpu -Gpus $scenario.Gpus
    Assert-Test ($selected.Name -eq $scenario.ExpectedSelected) "$($scenario.Scenario) -> Selected '$($selected.Name)'"
}

$storageCases = @(
    @{ Model = "WDC WD10EZEX-08WN4A0"; MediaType = "Unspecified"; ExpectedIsHdd = $true },
    @{ Model = "ST1000DM010-2EP102"; MediaType = "Unspecified"; ExpectedIsHdd = $true },
    @{ Model = "TOSHIBA MQ01ABD050"; MediaType = "HDD"; ExpectedIsHdd = $true },
    @{ Model = "Samsung SSD 980 PRO 1TB"; MediaType = "SSD"; ExpectedIsHdd = $false },
    @{ Model = "WD Black SN770 1TB"; MediaType = "Unspecified"; ExpectedIsHdd = $false },
    @{ Model = "FireCuda 2.5"; MediaType = "Unspecified"; ExpectedIsHdd = $true }
)
foreach ($sc in $storageCases) {
    $res = Resolve-StorageDeviceMediaType -Model $sc.Model -MediaType $sc.MediaType -BusType ""
    Assert-Test ($res.IsHdd -eq $sc.ExpectedIsHdd) "Storage '$($sc.Model)' -> IsHdd=$($res.IsHdd) (MediaType=$($res.MediaType))"
}

Assert-Test ((Test-IsLowRamSystem -TotalRamBytes ([int64](7.88 * 1GB))) -eq $true) "8 GB system (7.88 GB usable) activates LowRamProfile"
Assert-Test ((Test-IsLowRamSystem -TotalRamBytes ([int64](15.9 * 1GB))) -eq $false) "16 GB system disables LowRamProfile"

Assert-Test (Test-IsHighPerformanceScheme -SchemeGuid "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" -RawOutput "GUID: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c (High Performance)") "Recognizes High Performance power scheme GUID"
Assert-Test (Test-IsHighPerformanceScheme -SchemeGuid "e9a42b02-d5df-448d-aa00-03f14749eb61" -RawOutput "GUID: e9a42b02-d5df-448d-aa00-03f14749eb61 (Ultimate Performance)") "Recognizes Ultimate Performance power scheme GUID"
Assert-Test (-not (Test-IsHighPerformanceScheme -SchemeGuid "381b4222-f694-41f0-9685-ff5bb260df2e" -RawOutput "GUID: 381b4222-f694-41f0-9685-ff5bb260df2e (Balanced)")) "Recognizes Balanced power scheme as non-high-performance"

# -- 4. JSON Configuration & Service Descriptions Integrity -------------------
Write-Host "`n[Test Group 4] JSON Configuration & Service Descriptions Integrity:" -ForegroundColor Cyan
$blConfig  = Get-Content -LiteralPath (Join-Path $repoRoot "Config\services_blacklist.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$wlConfig  = Get-Content -LiteralPath (Join-Path $repoRoot "Config\services_whitelist.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$stConfig  = Get-Content -LiteralPath (Join-Path $repoRoot "Config\startup_apps.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$tunConfig = Get-Content -LiteralPath (Join-Path $repoRoot "Config\tuning.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$descPath  = Join-Path $repoRoot "Config\service_descriptions.json"

$blNames = @($blConfig.TargetServices | ForEach-Object { if ($_ -is [string]) { $_ } else { $_.Name } })
$wlNames = @($wlConfig.ProtectedServices)
$overlapServices = @($blNames | Where-Object { $wlNames -contains $_ })

Assert-Test ($blNames.Count -eq 205) "services_blacklist.json contains 205 TargetServices (actual: $($blNames.Count))"
Assert-Test ($wlNames.Count -eq 95) "services_whitelist.json contains 95 ProtectedServices (actual: $($wlNames.Count))"
Assert-Test ($overlapServices.Count -eq 0) "Zero overlap between services_blacklist.json and services_whitelist.json"

$criticalWhitelisted = @("FACEIT", "FACEITService", "vgk", "vgc", "EasyAntiCheat", "BEService", "Audiosrv", "camsvc", "CaptureService", "cbdhsvc", "Apple Mobile Device Service", "ProcessGovernor", "zapret", "WinDivert", "WinDivert14")
$missingCriticalWl = @($criticalWhitelisted | Where-Object { $wlNames -notcontains $_ })
Assert-Test ($missingCriticalWl.Count -eq 0) "services_whitelist.json protects all critical anti-cheat, audio, mic, Zapret/DPI & screenshot services"

$svcDescObj = (Get-Content -LiteralPath $descPath -Raw -Encoding UTF8 | ConvertFrom-Json).Descriptions
$missingDesc = @()
$invalidSvcSafety = @()
foreach ($svcName in ($blNames + $wlNames)) {
    $p = $svcDescObj.PSObject.Properties[$svcName]
    if (-not $p -or [string]::IsNullOrWhiteSpace($p.Value.summaryRu) -or [string]::IsNullOrWhiteSpace($p.Value.canDisableRu)) {
        $missingDesc += $svcName
    }
}
foreach ($prop in $svcDescObj.PSObject.Properties) {
    if ($prop.Value.safetyLevel -notin @("safe", "optional", "protected")) {
        $invalidSvcSafety += $prop.Name
    }
}
Assert-Test ($missingDesc.Count -eq 0) "service_descriptions.json covers all $($blNames.Count + $wlNames.Count) managed services (missing: $($missingDesc.Count))"
Assert-Test ($invalidSvcSafety.Count -eq 0) "service_descriptions.json defines valid safetyLevel on every entry (invalid: $($invalidSvcSafety.Count))"

$procDescPath = Join-Path $repoRoot "Config\process_descriptions.json"
$procDescObj = (Get-Content -LiteralPath $procDescPath -Raw -Encoding UTF8 | ConvertFrom-Json).Descriptions
$procDescKeys = @{}
$invalidProcSafety = @()
foreach ($prop in $procDescObj.PSObject.Properties) {
    $procDescKeys[$prop.Name.ToLowerInvariant()] = $prop.Value
    if (
        [string]::IsNullOrWhiteSpace($prop.Value.displayNameRu) -or
        [string]::IsNullOrWhiteSpace($prop.Value.summaryRu) -or
        [string]::IsNullOrWhiteSpace($prop.Value.canDisableRu) -or
        $prop.Value.safetyLevel -notin @("safe", "optional", "protected")
    ) {
        $invalidProcSafety += $prop.Name
    }
}
$missingProcDesc = @()
foreach ($pName in (@($stConfig.BlacklistProcesses) + @($stConfig.ProtectedStartupNames))) {
    $cleanKey = ($pName.Trim() -replace '(?i)\.exe$', '').ToLowerInvariant()
    if (-not $procDescKeys.ContainsKey($cleanKey)) {
        $missingProcDesc += $pName
    }
}
Assert-Test ($missingProcDesc.Count -eq 0 -and $invalidProcSafety.Count -eq 0) "process_descriptions.json covers all configured processes with valid Russian metadata and safetyLevel (missing: $($missingProcDesc.Count), invalid: $($invalidProcSafety.Count))"

Assert-Test ($stConfig.BlacklistProcesses -notcontains "SearchHost" -and $stConfig.BlacklistProcesses -notcontains "TextInputHost" -and $stConfig.BlacklistProcesses -notcontains "UltraGamingMode") "startup_apps.json excludes SearchHost, TextInputHost, and UltraGamingMode from BlacklistProcesses"
Assert-Test (
    $tunConfig.AutoLockTimerInGaming -is [bool] -and
    $tunConfig.AutoPurgeRamInGaming -is [bool] -and
    $tunConfig.AutoPurgeRamThresholdMB -ge 512 -and
    $tunConfig.DisableFullscreenOptimizations -is [bool] -and
    $tunConfig.DisableMouseAccel -is [bool] -and
    $tunConfig.DisableNvidiaDynamicPstate -is [bool] -and
    $tunConfig.EnableNetAdapterMsi -is [bool] -and
    $tunConfig.InputBufferQueueSize -ge 32
) "tuning.json defines all 6 boolean switches, AutoPurgeRamThresholdMB >= 512, and InputBufferQueueSize >= 32"

# -- 5. Low-Latency Kernel, DPC, BCDedit, TCP, HAGS & Extended Targets --------
Write-Host "`n[Test Group 5] Low-Latency Kernel, DPC, Timers, TCP & Extended Targets:" -ForegroundColor Cyan
$inputCfg = Get-InputBufferConfig
Assert-Test ($inputCfg -is [hashtable] -and $inputCfg.ContainsKey("MouseDataQueueSize") -and $inputCfg.ContainsKey("KeyboardDataQueueSize")) "Get-InputBufferConfig returns MouseDataQueueSize and KeyboardDataQueueSize"

$kdpcCfg = Get-KernelDpcConfig
Assert-Test ($kdpcCfg -is [hashtable] -and $kdpcCfg.ContainsKey("DisablePagingExecutive") -and $kdpcCfg.ContainsKey("Win32PrioritySeparation")) "Get-KernelDpcConfig returns kernel DPC and priority separation keys"

$parsedBcd = Get-BcdeditTimerConfig -BcdOutput @("identifier {current}", "disabledynamictick yes", "tscsyncpolicy Enhanced")
Assert-Test ($parsedBcd.DynamicTick -eq "yes" -and $parsedBcd.TscSyncPolicy -eq "Enhanced") "Get-BcdeditTimerConfig parses DynamicTick and TscSyncPolicy from bcdedit output"
$stockBcd = Get-BcdeditTimerConfig -BcdOutput @("identifier {current}", "description Windows 11")
Assert-Test ($null -eq $stockBcd.DynamicTick -and $null -eq $stockBcd.TscSyncPolicy) "Get-BcdeditTimerConfig returns null properties on stock bcdedit output"

$tcpCfg = Get-TcpStackConfig
$tcpGuids = @($tcpCfg.Interfaces | ForEach-Object { if ($_ -is [hashtable]) { $_["Guid"] } else { $_.Guid } })
Assert-Test ($tcpCfg -is [hashtable] -and $tcpGuids -notcontains "{8eb6cecf-6919-4cf4-8c70-e55823aa4b53}" -and $tcpGuids -notcontains "{2e219888-9139-4199-ea45-cb771d7dad1d}") "Get-TcpStackConfig isolates physical interfaces and excludes Apple USB Tethering & Wintun GUIDs"
Assert-Test (
    (Test-ShouldPreserveTcpTimestamps -CurrentTimestamps "disabled" -ActiveServiceNames @("zapret") -ActiveProcessNames @()) -and
    (Test-ShouldPreserveTcpTimestamps -CurrentTimestamps "disabled" -ActiveServiceNames @() -ActiveProcessNames @("winws.exe")) -and
    (Test-ShouldPreserveTcpTimestamps -CurrentTimestamps "enabled" -ActiveServiceNames @() -ActiveProcessNames @()) -and
    -not (Test-ShouldPreserveTcpTimestamps -CurrentTimestamps "disabled" -ActiveServiceNames @("Spooler") -ActiveProcessNames @("Discord"))
) "Test-ShouldPreserveTcpTimestamps preserves RFC 1323 timestamps when Zapret/WinDivert/winws is present or already enabled"

$gamingAdapterNames = @(Get-PhysicalGamingAdapters | ForEach-Object { $_.Name })
Assert-Test ($gamingAdapterNames -notcontains "Ethernet 2" -and $gamingAdapterNames -notcontains "wwan99") "Get-PhysicalGamingAdapters excludes 'Ethernet 2' and 'wwan99'"

$hagsCfg = Get-HagsGpuSchedulingConfig
Assert-Test ($hagsCfg -is [hashtable] -and $hagsCfg.ContainsKey("HwSchMode")) "Get-HagsGpuSchedulingConfig returns HwSchMode key"

$powerCfg = Get-PowerLatencyConfig
Assert-Test ($null -ne $powerCfg -and $powerCfg.Settings.Count -eq 9) "Get-PowerLatencyConfig captures all 9 power latency settings"

$schedTasks = Get-GamingScheduledTaskTargets -HddProfile $true
Assert-Test (@($schedTasks | Where-Object { $_.Name -eq "ScheduledDefrag" }).Count -gt 0) "Get-GamingScheduledTaskTargets includes ScheduledDefrag on HddProfile"

$highRamTargets = Get-ExtendedGamingTargets `
    -HardwareProfile ([PSCustomObject]@{ CpuVendor = "AMD"; GpuVendor = "NVIDIA"; LowRamProfile = $false; HddProfile = $false }) `
    -TuningConfig ([PSCustomObject]@{ DisableMouseAccel = $true; DisableNvidiaDynamicPstate = $true })
$lowRamTargets = Get-ExtendedGamingTargets `
    -HardwareProfile ([PSCustomObject]@{ CpuVendor = "AMD"; GpuVendor = "AMD"; LowRamProfile = $true; HddProfile = $false }) `
    -TuningConfig ([PSCustomObject]@{ DisableMouseAccel = $false; DisableNvidiaDynamicPstate = $false })

Assert-Test ($highRamTargets.Count -ge 25) "Get-ExtendedGamingTargets generates full registry optimization target set ($($highRamTargets.Count) targets)"
Assert-Test ($null -ne ($highRamTargets | Where-Object { $_.Name -eq 'SvcHostSplitThresholdInKB' -and $_.Value -eq 67108864 }) -and $null -eq ($lowRamTargets | Where-Object { $_.Name -eq 'SvcHostSplitThresholdInKB' })) "SvcHostSplitThresholdInKB is applied on >=16 GB RAM and skipped on LowRamProfile"
Assert-Test ($null -ne ($highRamTargets | Where-Object { $_.Path -match 'cs2\.exe\\PerfOptions' -and $_.Value -eq 3 }) -and $null -eq ($highRamTargets | Where-Object { $_.Path -match 'RDR2\.exe\\PerfOptions' })) "IFEO PerfOptions configures CS2 High Priority (3) and excludes RDR2"
Assert-Test ($null -ne ($highRamTargets | Where-Object { $_.Name -eq 'SendTelemetryData' -and $_.Value -eq 0 }) -and @($highRamTargets | Where-Object { $_.Name -eq 'RmGpsPsEnablePerCpuCoreDpc' -and $_.Value -eq 1 }).Count -ge 3) "NVIDIA targets disable driver telemetry and enable per-core DPC"
Assert-Test (@($highRamTargets | Where-Object { $_.Path -eq 'HKCU:\Control Panel\Mouse' -and $_.Name -in @('MouseSpeed', 'MouseThreshold1', 'MouseThreshold2') }).Count -eq 3 -and @($lowRamTargets | Where-Object { $_.Path -eq 'HKCU:\Control Panel\Mouse' -and $_.Name -eq 'MouseSpeed' }).Count -eq 0) "Get-ExtendedGamingTargets gates 1:1 mouse curve on DisableMouseAccel"

# -- 6. Multi-Directory Shortcut Quarantine & Two-Phase Restoration -----------
Write-Host "`n[Test Group 6] Multi-Directory Shortcut Quarantine & Two-Phase Restore:" -ForegroundColor Cyan
$tempTestRoot = Join-Path $env:TEMP ("UGM_Test_Quarantine_" + [System.Guid]::NewGuid().ToString("N"))
try {
    $testUserStartup   = Join-Path $tempTestRoot "DestUserStartup"
    $testCommonStartup = Join-Path $tempTestRoot "DestCommonStartup"
    $testQuarantine    = Join-Path $tempTestRoot "QuarantinedShortcuts"
    $testQUser         = Join-Path $testQuarantine "User"
    $testQCommon       = Join-Path $testQuarantine "ProgramData"

    New-Item -ItemType Directory -Path $testQUser, $testQCommon, $testUserStartup, $testCommonStartup -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $testQUser "Discord.lnk") -Value "User Discord"
    Set-Content -LiteralPath (Join-Path $testQCommon "Discord.lnk") -Value "ProgramData Discord"
    Set-Content -LiteralPath (Join-Path $testQUser "Game [Modded] (v2.0).lnk") -Value "Bracketed Game"
    Set-Content -LiteralPath (Join-Path $testQuarantine "LegacyApp.lnk.ugm_backup") -Value "Legacy Backup"

    $mockStateData = [PSCustomObject]@{
        StartupShortcuts = @(
            [PSCustomObject]@{ Name = "LegacyApp.lnk"; OriginalFolder = $testUserStartup; FolderTag = "User" }
        )
    }

    Restore-QuarantinedShortcuts -QuarantineDir $testQuarantine -UserStartup $testUserStartup -CommonStartup $testCommonStartup -StateData $mockStateData -Scope "System"
    Assert-Test ((Test-Path -LiteralPath (Join-Path $testCommonStartup "Discord.lnk")) -and -not (Test-Path -LiteralPath (Join-Path $testUserStartup "Discord.lnk"))) "Phase 1 (System Scope): restores ProgramData shortcuts while preserving User quarantine"

    Restore-QuarantinedShortcuts -QuarantineDir $testQuarantine -UserStartup $testUserStartup -CommonStartup $testCommonStartup -StateData $mockStateData -Scope "User"
    Assert-Test (
        (Test-Path -LiteralPath (Join-Path $testUserStartup "Discord.lnk")) -and
        (Test-Path -LiteralPath (Join-Path $testUserStartup "Game [Modded] (v2.0).lnk")) -and
        (Test-Path -LiteralPath (Join-Path $testUserStartup "LegacyApp.lnk")) -and
        -not (Test-Path -LiteralPath $testQuarantine)
    ) "Phase 2 (User Scope): restores User, bracketed, and .ugm_backup shortcuts and removes empty quarantine"
} finally {
    Remove-Item -LiteralPath $tempTestRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# -- 7. State Persistence, Watchdog Session Detection & Two-Phase Merge -------
Write-Host "`n[Test Group 7] State Persistence, Watchdog Boot Session & Atomic Merge:" -ForegroundColor Cyan
$tempStateFile = Join-Path $env:TEMP ("UGM_State_" + [System.Guid]::NewGuid().ToString("N") + ".json")
try {
    $legacyJson = '{"State":"Armed","BootRunCount":0,"SystemRestored":false,"UserRestored":false}'
    [System.IO.File]::WriteAllText($tempStateFile, $legacyJson, [System.Text.UTF8Encoding]::new($false))

    $loaded = Get-ActiveStateSafe -Path $tempStateFile
    Assert-Test ($null -ne $loaded.PSObject.Properties["GamingBootId"] -and $null -ne $loaded.PSObject.Properties["GamingBootTime"]) "Get-ActiveStateSafe normalizes missing GamingBootId and GamingBootTime properties"

    Set-StatePropertySafe -StateObject $loaded -Name "State" -Value "Restoring_SystemDone"
    Set-StatePropertySafe -StateObject $loaded -Name "SystemRestored" -Value $true
    Set-ActiveStateSafe -Path $tempStateFile -Data $loaded | Out-Null

    $usrPass = Get-ActiveStateSafe -Path $tempStateFile
    $usrPass.UserRestored = $true
    if ($usrPass.SystemRestored) { $usrPass.State = "Restored" }
    Set-ActiveStateSafe -Path $tempStateFile -Data $usrPass | Out-Null

    $finalState = Get-ActiveStateSafe -Path $tempStateFile
    $stateBytes = [System.IO.File]::ReadAllBytes($tempStateFile)
    $stateHasBom = ($stateBytes.Length -ge 3 -and $stateBytes[0] -eq 0xEF -and $stateBytes[1] -eq 0xBB -and $stateBytes[2] -eq 0xBF)
    Assert-Test ($finalState.State -eq "Restored" -and $finalState.SystemRestored -and $finalState.UserRestored -and -not $stateHasBom) "Two-phase state transition merges cleanly to Restored in pure UTF-8 without BOM"
} finally {
    Remove-Item -LiteralPath $tempStateFile -Force -ErrorAction SilentlyContinue
}

$bootId = Get-SystemBootId
$currentBootTs = Get-ResilientBootTimestamp
$oldBootTs = ([DateTime]::Parse($currentBootTs).AddHours(-5)).ToString("o")
Assert-Test ((Test-IsSameBootSession -SavedBootId $bootId) -eq $true -and (Test-IsSameBootSession -SavedBootId ($bootId + 1)) -eq $false) "Test-IsSameBootSession distinguishes current vs different BootId"
Assert-Test ((Test-IsSameBootSession -SavedBootId $null -SavedBootTime $currentBootTs) -eq $true -and (Test-IsSameBootSession -SavedBootId $null -SavedBootTime $oldBootTs) -eq $false) "Test-IsSameBootSession timestamp fallback detects stale boot sessions"

# -- 8. Registry & Debloat Snapshot Round-Trips (DWord, String, Binary, Multi) -
Write-Host "`n[Test Group 8] Registry, NIC MSI & Win11 Debloat Snapshot Round-Trips:" -ForegroundColor Cyan
$tempMsiKey = "HKCU:\Software\UGM_UnitTest_Msi_" + [System.Guid]::NewGuid().ToString("N")
try {
    New-Item -Path $tempMsiKey -Force | Out-Null
    Set-ItemProperty -LiteralPath $tempMsiKey -Name "MSISupported" -Value 1 -Type DWord -Force
    $null = Restore-NetAdapterMsiMode -MsiBackup @(@{ AdapterName = "TestNIC"; RegistryPath = $tempMsiKey; OriginalMsi = 0 }) 6>$null
    $restoredZero = (Get-ItemProperty -LiteralPath $tempMsiKey -Name "MSISupported" -ErrorAction SilentlyContinue).MSISupported
    $null = Restore-NetAdapterMsiMode -MsiBackup @(@{ AdapterName = "TestNIC"; RegistryPath = $tempMsiKey; OriginalMsi = $null }) 6>$null
    $restoredNull = (Get-ItemProperty -LiteralPath $tempMsiKey -Name "MSISupported" -ErrorAction SilentlyContinue).MSISupported
    Assert-Test ($restoredZero -eq 0 -and $null -eq $restoredNull) "Restore-NetAdapterMsiMode restores OriginalMsi value and deletes key when OriginalMsi is null"
} finally {
    Remove-Item -LiteralPath $tempMsiKey -Recurse -Force -ErrorAction SilentlyContinue
}

$binRegKey = "HKCU:\Software\UGM_TestBin_" + ([Guid]::NewGuid().ToString("N"))
try {
    New-Item -Path "$binRegKey\UMD" -Force | Out-Null
    Set-ItemProperty -Path "$binRegKey\UMD" -Name "ShaderCache" -Value ([byte[]](0x30, 0x00)) -Type Binary
    Set-ItemProperty -Path $binRegKey -Name "MultiVal" -Value ([string[]]@("alpha", "beta")) -Type MultiString

    $binTargets = @(
        @{ Path = "$binRegKey\UMD"; Name = "ShaderCache"; Value = ([byte[]](0x32, 0x00)); Kind = "Binary" },
        @{ Path = $binRegKey; Name = "MultiVal"; Value = ([string[]]@("gamma")); Kind = "MultiString" },
        @{ Path = $binRegKey; Name = "FastSendDatagramThreshold"; Value = 65536; Kind = "DWord" },
        @{ Path = $binRegKey; Name = "MenuShowDelay"; Value = "0"; Kind = "String" }
    )
    $binSnap = Get-RegistryValueSnapshot -Targets $binTargets
    $binJsonLoaded = (@{ ExtendedRegistryConfig = $binSnap } | ConvertTo-Json -Depth 10 | ConvertFrom-Json).ExtendedRegistryConfig
    $binApplied = Set-RegistryTargets -Targets $binTargets
    $binRestored = Restore-RegistryValueSnapshot -Snapshot $binJsonLoaded -Hive "HKCU"

    $subMain = $binRegKey -replace '^HKCU:\\', ''
    $kUmdRest = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("$subMain\UMD")
    $restoredBytes = $kUmdRest.GetValue("ShaderCache")
    $kUmdRest.Close()
    $kMainRest = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($subMain)
    $restoredMulti = $kMainRest.GetValue("MultiVal")
    $dwordRemoved = ($kMainRest.GetValueNames() -notcontains "FastSendDatagramThreshold")
    $kMainRest.Close()

    Assert-Test ($binApplied -eq 4 -and $binRestored -eq 4 -and $restoredBytes[0] -eq 0x30 -and ($restoredMulti -join ',') -eq 'alpha,beta' -and $dwordRemoved) "Registry snapshot engine losslessly round-trips REG_DWORD, REG_SZ, REG_BINARY, and REG_MULTI_SZ"
} finally {
    Remove-Item -LiteralPath $binRegKey -Recurse -Force -ErrorAction SilentlyContinue
}

$debloatSnap = Get-Windows11DebloatConfig
Assert-Test ($debloatSnap -is [hashtable] -and $debloatSnap.Count -eq 14) "Get-Windows11DebloatConfig captures all 14 Windows 11 debloat keys ($($debloatSnap.Count)/14)"

# -- 9. SemVer Parser, Suite Version & URL/Tag Injection Guards ---------------
Write-Host "`n[Test Group 9] SemVer Engine, Suite Version & URL Security Guards:" -ForegroundColor Cyan
Assert-Test ((Get-AppCurrentVersion) -eq "3.6.0") "Get-AppCurrentVersion returns '3.6.0'"

$vBase  = ConvertTo-SemVer "v2.8"
$vPad   = ConvertTo-SemVer "2.8.0"
$vPatch = ConvertTo-SemVer "v2.8.1"
$vCurr  = ConvertTo-SemVer "v3.6.0"
Assert-Test ($vBase -eq $vPad -and $vPatch -gt $vBase -and $vCurr -gt $vPatch) "ConvertTo-SemVer normalizes and compares versions accurately"
Assert-Test ($null -eq (ConvertTo-SemVer "") -and $null -eq (ConvertTo-SemVer "invalid")) "ConvertTo-SemVer returns null on invalid version input"

Assert-Test ((Test-SafeVersionTag -Tag "v3.6.0") -and -not (Test-SafeVersionTag -Tag 'v3.6.0"&calc.exe') -and -not (Test-SafeVersionTag -Tag "")) "Test-SafeVersionTag validates tags and blocks shell metacharacters"
Assert-Test (
    (Test-SafeGitHubReleaseUrl -Url "https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases/tag/v3.6.0") -and
    -not (Test-SafeGitHubReleaseUrl -Url "http://github.com/RagTagsky/Win11-Gaming-Optimizer/releases/tag/v3.6.0") -and
    -not (Test-SafeGitHubReleaseUrl -Url "https://evil.example.com/RagTagsky/Win11-Gaming-Optimizer/releases/tag/v3.6.0") -and
    -not (Test-SafeGitHubReleaseUrl -Url "file:///C:/Windows/System32/calc.exe")
) "Test-SafeGitHubReleaseUrl enforces HTTPS and github.com repository allowlist"

# -- 10. Process, WebView2 & Service Security Guards --------------------------
Write-Host "`n[Test Group 10] Process, WebView2 & Service Security Guards:" -ForegroundColor Cyan
Assert-Test ((Test-IsProtectedProcess -ProcessId 0) -and (Test-IsProtectedProcess -ProcessId 4) -and (Test-IsProtectedProcess -ProcessId $PID -ProcessName "powershell")) "Test-IsProtectedProcess blocks PID 0, PID 4, and current host PID"

$protectedProcSamples = @("lsass", "csrss", "winlogon", "dwm", "explorer", "svchost", "UltraGamingMode", "vgk", "EasyAntiCheat", "..\evil")
$unprotectedBlocked = @($protectedProcSamples | Where-Object { -not (Test-IsProtectedProcess -ProcessName $_) })
Assert-Test ($unprotectedBlocked.Count -eq 0) "Test-IsProtectedProcess blocks all critical OS, anti-cheat, self, and traversal process names"
Assert-Test (-not (Test-IsProtectedProcess -ProcessName "Discord") -and -not (Test-IsProtectedProcess -ProcessName "Spotify.exe")) "Test-IsProtectedProcess allows non-critical third-party apps (Discord, Spotify)"
Assert-Test ((-not (Stop-ProcessSafe -ProcessId $PID 3>$null)) -and (-not (Stop-ProcessSafe -ProcessName "lsass" 3>$null))) "Stop-ProcessSafe refuses to terminate current host PID or lsass"

Assert-Test (
    -not (Test-ShouldStopWebViewProcess -CommandLine 'msedgewebview2.exe --webview-exe-name=UltraGamingMode.exe') -and
    -not (Test-ShouldStopWebViewProcess -CommandLine 'msedgewebview2.exe --webview-exe-name=SearchHost.exe') -and
    (Test-ShouldStopWebViewProcess -CommandLine 'msedgewebview2.exe --webview-exe-name=Widgets.exe')
) "Test-ShouldStopWebViewProcess protects UltraGamingMode and SearchHost while targeting Widgets.exe"

Assert-Test ((Test-SafeServiceName -ServiceName "DiagTrack") -and (Test-SafeServiceName -ServiceName "AMD External Events Utility") -and -not (Test-SafeServiceName -ServiceName "svc*") -and -not (Test-SafeServiceName -ServiceName "..\Evil") -and -not (Test-SafeServiceName -ServiceName "a;calc.exe")) "Test-SafeServiceName validates service identifiers and blocks wildcards/traversal/injection"
Assert-Test ((-not (Set-ServiceStateSafe -ServiceName "..\Evil" -StartupType "Disabled" 3>$null)) -and (-not (Set-ServiceStateSafe -ServiceName "RpcSs" -StartupType "Disabled" -Whitelist @() 3>$null)) -and (-not (Set-ServiceStateSafe -ServiceName "Audiosrv" -StartupType "Disabled" -Whitelist @("Audiosrv") 3>$null))) "Set-ServiceStateSafe blocks traversal, immutable core services (RpcSs), and whitelisted services"

$svcBlockedAudio = $false
try { $null = Invoke-ServiceControlSafe -ServiceName "Audiosrv" -Operation "Stop" -Whitelist @("Audiosrv") } catch { $svcBlockedAudio = $true }
$svcBlockedCore = $false
try { $null = Invoke-ServiceControlSafe -ServiceName "RpcSs" -Operation "Disabled" -Whitelist @() } catch { $svcBlockedCore = $true }
Assert-Test ($svcBlockedAudio -and $svcBlockedCore) "Invoke-ServiceControlSafe throws on stopping whitelisted or disabling immutable core services"

# -- 11. Two-Mode Service/Process Rules & Canonical Name Matching (v3.6.0) ----
Write-Host "`n[Test Group 11] Two-Mode Service/Process Rules & Canonical Name Matching:" -ForegroundColor Cyan
Assert-Test (
    (Get-CanonicalServiceName -ServiceName "WpnUserService_5e3a4") -eq "WpnUserService" -and
    (Get-CanonicalServiceName -ServiceName "GoogleUpdaterService159.0.8140.0") -eq "GoogleUpdaterService" -and
    (Get-CanonicalServiceName -ServiceName "FontCache3.0.0.0") -eq "FontCache3.0.0.0" -and
    (Get-CanonicalServiceName -ServiceName "igfxCUIService2.0.0.0") -eq "igfxCUIService2.0.0.0" -and
    (Get-CanonicalServiceName -ServiceName "MyDriver_64") -eq "MyDriver_64" -and
    (Get-CanonicalServiceName -ServiceName "AudioSvc_32") -eq "AudioSvc_32" -and
    (Get-CanonicalServiceName -ServiceName "Worker_1") -eq "Worker_1"
) "Get-CanonicalServiceName strips per-user _LUID (4-16 hex) and dynamic 4-part updater versions while keeping fixed-version and short _64/_32/_1 suffixes"

$liveWpnInstances = @(Get-Service -Name "WpnUserService_*" -ErrorAction SilentlyContinue)
if ($liveWpnInstances.Count -gt 0) {
    $resolvedWpn = @(Find-MatchingLiveServices -ServiceName "WpnUserService")
    Assert-Test (
        $resolvedWpn.Count -gt 0 -and
        ($resolvedWpn | Where-Object { $_.Name -match '^WpnUserService_[0-9a-fA-F]{4,16}$' }).Count -eq $resolvedWpn.Count
    ) "Find-MatchingLiveServices resolves active per-user _LUID instance instead of non-runnable template service"
} else {
    Assert-Test ($true) "Find-MatchingLiveServices resolves active per-user _LUID instance (no active WpnUserService instance in session)"
}

Assert-Test (
    (Test-ServiceInList -ServiceName "WpnUserService_5e3a4" -List @("WpnUserService")) -and
    (Test-ServiceInList -ServiceName "GoogleUpdaterService159.0.8140.0" -List @(@{ Name = "GoogleUpdaterService" })) -and
    -not (Test-ServiceInList -ServiceName "Spooler" -List @("SysMain"))
) "Test-ServiceInList matches canonical per-user and versioned service names across string and object lists"

Assert-Test (
    (Test-ServiceShouldDisableInGaming -ServiceName "SysMain" -Blacklist @("SysMain") -Whitelist @()) -and
    -not (Test-ServiceShouldDisableInGaming -ServiceName "SysMain" -Blacklist @("SysMain") -Whitelist @("SysMain")) -and
    -not (Test-ServiceShouldDisableInGaming -ServiceName "WSAIFabricSvc" -Blacklist @("WSAIFabricSvc") -Whitelist @("WSAIFabricSvc")) -and
    -not (Test-ServiceShouldDisableInGaming -ServiceName "RpcSs" -Blacklist @("RpcSs") -Whitelist @())
) "Test-ServiceShouldDisableInGaming respects user choice for SysMain/WSAIFabricSvc and blocks immutable core services"

$mockStartupCfg = [PSCustomObject]@{
    BlacklistProcesses = @("Discord", "Widgets")
    ProtectedStartupNames = @("Spotify", "Widgets")
}
$mockStartupWidgetsOn = [PSCustomObject]@{
    BlacklistProcesses = @("Discord", "Widgets")
    ProtectedStartupNames = @("Spotify")
}
Assert-Test (
    (Test-ProcessShouldCloseInGaming -ProcessName "Discord.exe" -StartupConfig $mockStartupCfg) -and
    -not (Test-ProcessShouldCloseInGaming -ProcessName "Spotify" -StartupConfig $mockStartupCfg) -and
    -not (Test-ProcessShouldCloseInGaming -ProcessName "Widgets" -StartupConfig $mockStartupCfg) -and
    (Test-ProcessShouldCloseInGaming -ProcessName "Widgets" -StartupConfig $mockStartupWidgetsOn) -and
    -not (Test-ProcessShouldCloseInGaming -ProcessName "FACEITClient" -StartupConfig ([PSCustomObject]@{ BlacklistProcesses = @("FACEITClient"); ProtectedStartupNames = @() })) -and
    -not (Test-ProcessShouldCloseInGaming -ProcessName "winws.exe" -StartupConfig ([PSCustomObject]@{ BlacklistProcesses = @("winws"); ProtectedStartupNames = @() })) -and
    -not (Test-ProcessShouldCloseInGaming -ProcessName "zapret" -StartupConfig ([PSCustomObject]@{ BlacklistProcesses = @("zapret"); ProtectedStartupNames = @() }))
) "Test-ProcessShouldCloseInGaming enforces 2-mode priority, Widgets rule compliance, and FACEITClient/Zapret protection"

Assert-Test (
    (Test-StartupEntryMatchesNames -EntryName "Discord" -CommandValue 'C:\Users\P\AppData\Local\Discord\Update.exe --processStart Discord.exe' -Names @("Discord")) -and
    (Test-StartupEntryMatchesNames -EntryName "AppLauncher" -CommandValue 'C:\Users\P\AppData\Local\Discord\Update.exe --processStart Discord.exe' -Names @("Discord")) -and
    (Test-StartupEntryMatchesNames -EntryName "Discord_AutoStart" -CommandValue '' -Names @("Discord")) -and
    (Test-StartupEntryMatchesNames -EntryName "CustomTool" -CommandValue '"C:\Program Files\My App\My App.exe" --minimized' -Names @("My App")) -and
    -not (Test-StartupEntryMatchesNames -EntryName "Discord" -CommandValue 'C:\Users\P\AppData\Local\Discord\Update.exe --processStart Discord.exe' -Names @("Spotify"))
) "Test-StartupEntryMatchesNames matches direct, underscore-bounded, quoted spaced-path, and Squirrel --processStart exe targets without false positives"

$stopCmd = Get-Command Stop-BlacklistedProcesses -ErrorAction SilentlyContinue
$stopHasProtParam = [bool]($stopCmd -and $stopCmd.Parameters.ContainsKey("ProtectedNames"))
$stopSafeNoKill = $true
try {
    # Invoke with current pwsh process name in BOTH ProcessNames and ProtectedNames; must not terminate self or throw
    $selfProcName = (Get-Process -Id $PID).ProcessName
    Stop-BlacklistedProcesses -ProcessNames @($selfProcName) -ProtectedNames @($selfProcName)
} catch {
    $stopSafeNoKill = $false
}
Assert-Test ($stopHasProtParam -and $stopSafeNoKill) "Stop-BlacklistedProcesses enforces ProtectedNames override alongside critical process protection"

# -- Summary ------------------------------------------------------------------
Write-Host "`n=====================================================" -ForegroundColor Magenta
Write-Host "   TEST RESULTS: $testsRun Tests Run | $failures Failures" -ForegroundColor $(if ($failures -eq 0) { "Green" } else { "Red" })
Write-Host "=====================================================" -ForegroundColor Magenta

if ($failures -gt 0) {
    exit 1
} else {
    exit 0
}
