<#
.SYNOPSIS
    Minimal configuration and safety verification for Ultra Gaming Mode.
#>
[CmdletBinding()]
param(
    [switch]$UserInstall
)

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

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

# 1. PowerShell AST Syntax & UTF-8 JSON/PS1 Integrity
$scripts = Get-ChildItem -Path $repoRoot -Recurse -Filter "*.ps1" | Where-Object { $_.FullName -notmatch '[\\/](Backups|target|\.git|\.bin)[\\/]' }
foreach ($s in $scripts) {
    $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($s.FullName, [ref]$null, [ref]$errs)
    Assert-Test ($errs.Count -eq 0) "Script '$($s.Name)' parses cleanly"
}

$cfgFiles = Get-ChildItem -Path (Join-Path $repoRoot "Config") -Filter "*.json"
$hasBom = $false
$validJson = $true
foreach ($f in $cfgFiles) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $hasBom = $true
    }
    try {
        [void]([System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
    } catch {
        $validJson = $false
    }
}
Assert-Test ((-not $hasBom) -and $validJson) "Config/*.json files are valid UTF-8 JSON without BOM"

# 2. Core Modules & Safety Boundaries
. (Join-Path $repoRoot "Core\ServiceManager.ps1")
. (Join-Path $repoRoot "Core\SystemOptimizer.ps1")
. (Join-Path $repoRoot "Core\StateEngine.ps1")

$bl = @((Get-Content -LiteralPath (Join-Path $repoRoot "Config\services_blacklist.json") -Raw -Encoding UTF8 | ConvertFrom-Json).TargetServices)
$wl = @((Get-Content -LiteralPath (Join-Path $repoRoot "Config\services_whitelist.json") -Raw -Encoding UTF8 | ConvertFrom-Json).ProtectedServices)
$st = Get-Content -LiteralPath (Join-Path $repoRoot "Config\startup_apps.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$tu = Get-Content -LiteralPath (Join-Path $repoRoot "Config\tuning.json") -Raw -Encoding UTF8 | ConvertFrom-Json

$overlap = @($bl | Where-Object { Test-ServiceInList -ServiceName $_.Name -List $wl })
Assert-Test ($overlap.Count -eq 0) "Zero overlap between services_blacklist.json and services_whitelist.json"

$mustProtectSvcs = @("RpcSs", "Dhcp", "Dnscache", "Audiosrv", "AudioEndpointBuilder", "MMCSS", "FACEIT", "vgk", "BEService", "zapret", "WinDivert", "WinDivert14")
$unprotectedSvcs = @($mustProtectSvcs | Where-Object { Test-ServiceShouldDisableInGaming -ServiceName $_ -Blacklist $bl -Whitelist $wl })
Assert-Test ($unprotectedSvcs.Count -eq 0) "Critical OS, audio, network, anti-cheat, and Zapret services cannot be disabled"

$mustProtectProcs = @("lsass", "csrss", "dwm", "explorer", "UltraGamingMode", "vgk", "EasyAntiCheat", "winws", "zapret")
$unprotectedProcs = @($mustProtectProcs | Where-Object { -not (Test-IsProtectedProcess -ProcessName $_) -or (Test-ProcessShouldCloseInGaming -ProcessName $_ -StartupConfig $st) })
Assert-Test ($unprotectedProcs.Count -eq 0) "Critical OS, self, anti-cheat, and Zapret processes are protected"

$tuProps = @($tu.PSObject.Properties.Name)
Assert-Test (
    $tuProps.Count -eq 3 -and
    ($tu.AutoLockTimerInGaming -is [bool]) -and
    ($tu.AutoPurgeRamInGaming -is [bool]) -and
    ($tu.AutoPurgeRamThresholdMB -ge 512 -and $tu.AutoPurgeRamThresholdMB -le 16384)
) "tuning.json contains valid AAA automation parameters"

Write-Host "`nTEST RESULTS: $testsRun Tests Run | $failures Failures" -ForegroundColor $(if ($failures -eq 0) { "Green" } else { "Red" })
if ($failures -gt 0) { exit 1 } else { exit 0 }
