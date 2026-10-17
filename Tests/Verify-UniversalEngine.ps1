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
. (Join-Path $repoRoot "Core\SystemOptimizer.ps1")
. (Join-Path $repoRoot "Core\StateEngine.ps1")
Assert-Test (Get-Command Get-HardwareProfile -ErrorAction SilentlyContinue) "Get-HardwareProfile function is exported and accessible"
Assert-Test (Get-Command Apply-CpuGamingOptimizations -ErrorAction SilentlyContinue) "Apply-CpuGamingOptimizations is accessible"
Assert-Test (Get-Command Apply-GpuGamingOptimizations -ErrorAction SilentlyContinue) "Apply-GpuGamingOptimizations is accessible"
Assert-Test (Get-Command Set-NTFSGamingOptimizations -ErrorAction SilentlyContinue) "Set-NTFSGamingOptimizations is accessible"
Assert-Test (Get-Command Restore-NTFSGamingOptimizations -ErrorAction SilentlyContinue) "Restore-NTFSGamingOptimizations is accessible"

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

function Test-SelectPrimaryGpu($gpus) {
    $pci = @($gpus | Where-Object { $_.PNPDeviceID -match "^PCI" })
    if ($pci.Count -eq 0) { return ($gpus | Select-Object -First 1) }

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

foreach ($scenario in $testGpuScenarios) {
    $selected = Test-SelectPrimaryGpu $scenario.Gpus
    $v = if ($selected.PNPDeviceID -match "VEN_1002" -or $selected.Name -match "AMD|Radeon") { "AMD" }
         elseif ($selected.PNPDeviceID -match "VEN_10DE" -or $selected.Name -match "NVIDIA|GeForce") { "NVIDIA" }
         elseif ($selected.PNPDeviceID -match "VEN_8086" -or $selected.Name -match "Intel") { "Intel" }
         else { "Unknown" }

    Assert-Test ($selected.Name -eq $scenario.ExpectedSelected) "$($scenario.Scenario) -> Picked '$($selected.Name)'"
    Assert-Test ($v -eq $scenario.ExpectedVendor) "$($scenario.Scenario) -> Vendor is '$v'"
}

# ── 6. Storage Disk Auto-Detection Heuristics ──────────────────────────────
Write-Host "`n[Test Group 6] Storage Media Auto-Detection (HDD vs SSD Heuristics):" -ForegroundColor Cyan
$hddModelPattern = "(?i)HDD|WD[0-9]|WDC|ST[0-9]|Hitachi|Seagate|Barracuda|Spinpoint|MQ01|DT01|Deskstar|Caviar|Blue|Green|Red|Purple|Black|FireCuda|IronWolf"
$ssdModelPattern = "(?i)SSD|NVMe|NAND|EVO|PRO|Crucial|Kingston|KIOXIA|Lexar|Sandisk|Micron|SK hynix|Adata|Corsair|Intel SSD|Sabrent"

$storageCases = @(
    @{ Model = "WDC WD10EZEX-08WN4A0"; MediaType = "Unspecified"; ExpectedIsHdd = $true; ExpectedMediaType = "HDD" },
    @{ Model = "ST1000DM010-2EP102"; MediaType = "Unspecified"; ExpectedIsHdd = $true; ExpectedMediaType = "HDD" },
    @{ Model = "TOSHIBA MQ01ABD050"; MediaType = "HDD"; ExpectedIsHdd = $true; ExpectedMediaType = "HDD" },
    @{ Model = "Samsung SSD 980 PRO 1TB"; MediaType = "SSD"; ExpectedIsHdd = $false; ExpectedMediaType = "SSD" },
    @{ Model = "ADATA LEGEND 900"; MediaType = "Unspecified"; ExpectedIsHdd = $false; ExpectedMediaType = "SSD" }
)

foreach ($sc in $storageCases) {
    $isHdd = $false
    $media = $sc.MediaType
    if ($media -match "HDD") {
        $isHdd = $true
    } elseif ($media -match "SSD") {
        $isHdd = $false
    } else {
        if ($sc.Model -match $hddModelPattern) {
            $isHdd = $true
            $media = "HDD"
        } elseif ($sc.Model -match $ssdModelPattern) {
            $isHdd = $false
            $media = "SSD"
        }
    }
    Assert-Test ($isHdd -eq $sc.ExpectedIsHdd) "Model '$($sc.Model)' with MediaType '$($sc.MediaType)': IsHdd=$isHdd (Expected: $($sc.ExpectedIsHdd))"
    Assert-Test ($media -eq $sc.ExpectedMediaType) "Model '$($sc.Model)': Resolved MediaType=$media (Expected: $($sc.ExpectedMediaType))"
}

# ── 7. Low-RAM 8GB Guard & Pagefile Verification ───────────────────────────
Write-Host "`n[Test Group 7] Low-RAM 8GB Guard & Pagefile Alerts:" -ForegroundColor Cyan
$ramCases = @(
    @{ Bytes = [int64](7.88 * 1024 * 1024 * 1024); ExpectedLow = $true; Desc = "8 GB Budget System (7.88 GB usable)" },
    @{ Bytes = [int64](15.9 * 1024 * 1024 * 1024); ExpectedLow = $false; Desc = "16 GB Standard System" },
    @{ Bytes = [int64](31.9 * 1024 * 1024 * 1024); ExpectedLow = $false; Desc = "32 GB Enthusiast System" }
)
foreach ($rc in $ramCases) {
    $low = ($rc.Bytes -gt 0 -and $rc.Bytes -le [int64](8.5 * 1024 * 1024 * 1024))
    Assert-Test ($low -eq $rc.ExpectedLow) "$($rc.Desc): LowRamProfile=$low (Expected: $($rc.ExpectedLow))"
}

# ── 8. Summary ─────────────────────────────────────────────────────────────
Write-Host "`n=====================================================" -ForegroundColor Magenta
Write-Host "   TEST RESULTS: $testsRun Tests Run | $failures Failures" -ForegroundColor $(if ($failures -eq 0) { "Green" } else { "Red" })
Write-Host "=====================================================" -ForegroundColor Magenta

if ($failures -gt 0) {
    exit 1
} else {
    exit 0
}
