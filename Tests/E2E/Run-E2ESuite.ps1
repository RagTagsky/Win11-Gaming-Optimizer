#Requires -Version 7.0
<#
.SYNOPSIS
    Opaque-box End-to-End (E2E) Test Suite Runner for Ultra Gaming Mode v4.0.0.
#>

[CmdletBinding()]
param(
    [ValidateSet("1", "2", "3", "4", "All")]
    [string]$Tier = "All",

    [switch]$ValidateSuiteOnly,

    [string]$OutputJson = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$e2eRoot = $PSScriptRoot
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $e2eRoot "..\.."))

. (Join-Path $e2eRoot "Lib\E2E.Assertions.ps1")
. (Join-Path $e2eRoot "Lib\E2E.ProcessHost.ps1")
. (Join-Path $e2eRoot "Lib\E2E.Sandbox.ps1")

. (Join-Path $e2eRoot "Suites\Tier1.Functional.ps1")
. (Join-Path $e2eRoot "Suites\Tier2.EdgeAndSecurity.ps1")
. (Join-Path $e2eRoot "Suites\Tier3.Pairwise.ps1")
. (Join-Path $e2eRoot "Suites\Tier4.Workloads.ps1")

Reset-E2ETestState
Register-Tier1Tests
Register-Tier2Tests
Register-Tier3Tests
Register-Tier4Tests

$allCases = Get-RegisteredE2ETests
$thresholds = Test-E2EThresholds -RequestedTier $Tier -AllCases $allCases

$hostInit = Initialize-E2EProcessHost
$beforeSnapshot = New-HostIntegritySnapshot -RepoRoot $repoRoot
$sandbox = New-E2ESandbox

$startedUtc = [DateTime]::UtcNow.ToString("o")
$suiteSw = [System.Diagnostics.Stopwatch]::StartNew()

$suiteSelfErrors = [System.Collections.Generic.List[string]]::new()
$results = [System.Collections.Generic.List[object]]::new()
$orphanedCount = 0
$integrityResult = [PSCustomObject]@{ Clean = $true; Drifts = @() }

try {
    if ($ValidateSuiteOnly) {
        # Phase A suite integrity checks: AST (PS 5.1 & 7), UTF-8 no-BOM, policy hygiene, sandbox self-test
        $e2ePs1 = @(Get-ChildItem -LiteralPath $e2eRoot -Filter "*.ps1" -Recurse | Select-Object -ExpandProperty FullName)
        $astErrs = Test-PowerShellAst -Files $e2ePs1
        foreach ($e in $astErrs) { $suiteSelfErrors.Add($e) }

        $bomErrs = Find-Utf8BomFiles -RootDir $e2eRoot -Extensions @(".ps1", ".json")
        foreach ($b in $bomErrs) { $suiteSelfErrors.Add("BOM violation: $b") }

        $hygErrs = Test-ContentPolicyHygiene -Paths @($e2eRoot)
        foreach ($h in $hygErrs) { $suiteSelfErrors.Add("Hygiene violation: $h") }

        $sbSelf = Test-E2ESandboxSelfTest -Sandbox $sandbox -RepoRoot $repoRoot
        if (-not $sbSelf.Passed) {
            $suiteSelfErrors.Add("Sandbox self-test failed: $($sbSelf.Reason)")
        }
    }

    $selectedTiers = switch ($Tier) {
        "1"   { @(1) }
        "2"   { @(2) }
        "3"   { @(3) }
        "4"   { @(4) }
        "All" { @(1, 2, 3, 4) }
    }

    $context = [PSCustomObject]@{
        RepoRoot          = $repoRoot
        E2ERoot           = $e2eRoot
        Sandbox           = $sandbox
        ValidateSuiteOnly = [bool]$ValidateSuiteOnly
        TestInfraPath     = ""
        Cache             = @{}
    }

    $selectedCases = @($allCases | Where-Object { $selectedTiers -contains $_.Tier })
    foreach ($tc in $selectedCases) {
        $rec = Invoke-E2ETestCase -TestCase $tc -Context $context
        $results.Add($rec)
    }
} finally {
    $orphanedCount = Clear-E2EProcessHost
    Remove-E2ESandbox -Sandbox $sandbox
    $integrityResult = Test-HostIntegritySnapshot -BeforeSnapshot $beforeSnapshot -RepoRoot $repoRoot
    $suiteSw.Stop()
}

$finishedUtc = [DateTime]::UtcNow.ToString("o")

$passedCount   = @($results | Where-Object { $_.status -eq "Passed" }).Count
$failedCount   = @($results | Where-Object { $_.status -eq "Failed" }).Count
$deferredCount = @($results | Where-Object { $_.status -eq "Deferred" }).Count
$totalCount    = $results.Count

$exitCode = 0
if ($failedCount -gt 0 -or -not $thresholds.passed -or -not $integrityResult.Clean -or $orphanedCount -gt 0 -or $suiteSelfErrors.Count -gt 0) {
    $exitCode = 1
}
if (-not $ValidateSuiteOnly -and ($deferredCount -gt 0 -or $totalCount -eq 0)) {
    $exitCode = 1
}

if ($suiteSelfErrors.Count -gt 0) {
    Write-Host "`n[Suite Self-Validation Errors]" -ForegroundColor Red
    foreach ($se in $suiteSelfErrors) {
        Write-Host ("  - {0}" -f $se) -ForegroundColor Red
    }
}

if (-not $integrityResult.Clean) {
    Write-Host "`n[Integrity Drift Detected]" -ForegroundColor Red
    foreach ($dr in $integrityResult.Drifts) {
        Write-Host ("  - {0}" -f $dr) -ForegroundColor Red
    }
}

$report = [PSCustomObject]@{
    schemaVersion = "1.0"
    suite         = "UltraGamingMode.E2E"
    targetVersion = "4.0.0"
    phase         = $(if ($ValidateSuiteOnly) { "PhaseA-ValidateSuiteOnly" } else { "PhaseB-FullGate" })
    requestedTier = $Tier
    startedAtUtc  = $startedUtc
    finishedAtUtc = $finishedUtc
    durationMs    = [int64]$suiteSw.ElapsedMilliseconds
    host          = [PSCustomObject]@{
        os                 = [System.Environment]::OSVersion.VersionString
        psVersion          = $PSVersionTable.PSVersion.ToString()
        isAdmin            = (Test-IsElevatedAdmin)
        preExistingUgmPids = @($hostInit.PreExistingUgmPids)
        integrityClean     = $integrityResult.Clean
        integrityDrifts    = @($integrityResult.Drifts)
        orphanedProcesses  = $orphanedCount
    }
    thresholds    = $thresholds
    selfChecks    = [PSCustomObject]@{
        passed = ($suiteSelfErrors.Count -eq 0)
        errors = @($suiteSelfErrors)
    }
    summary       = [PSCustomObject]@{
        total    = $totalCount
        passed   = $passedCount
        failed   = $failedCount
        deferred = $deferredCount
    }
    exitCode      = $exitCode
    results       = @($results)
}

Write-E2EReport -ReportObj $report -OutputJson $OutputJson
exit $exitCode
