# E2E.Assertions.ps1 — Test Registry, Assertions, Deferral & Reporting

Set-StrictMode -Version Latest

$script:E2ETestCases = [System.Collections.Generic.List[object]]::new()
$script:E2EResults = [System.Collections.Generic.List[object]]::new()

function Reset-E2ETestState {
    $script:E2ETestCases.Clear()
    $script:E2EResults.Clear()
}

function Register-E2ETest {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][ValidateSet(1, 2, 3, 4)][int]$Tier,
        [Parameter(Mandatory = $true)][string]$Feature,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Body,
        [string]$Artifact = ""
    )

    $script:E2ETestCases.Add([PSCustomObject]@{
        Id       = $Id
        Tier     = $Tier
        Feature  = $Feature
        Name     = $Name
        Body     = $Body
        Artifact = $Artifact
    })
}

function Get-RegisteredE2ETests {
    return @($script:E2ETestCases)
}

function Assert-E2ETrue {
    param(
        [Parameter(Mandatory = $false)]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not [bool]$Condition) {
        throw [System.Exception]::new("Assertion failed: $Message")
    }
}

function Assert-E2EEqual {
    param(
        [Parameter(Mandatory = $false)]$Expected,
        [Parameter(Mandatory = $false)]$Actual,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if ($Expected -ne $Actual) {
        throw [System.Exception]::new("Assertion failed: $Message (expected='$Expected', actual='$Actual')")
    }
}

function Assert-E2EMatch {
    param(
        [Parameter(Mandatory = $false)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if ($null -eq $Text -or $Text -notmatch $Pattern) {
        throw [System.Exception]::new("Assertion failed: $Message (pattern='$Pattern')")
    }
}

function Assert-E2ENotMatch {
    param(
        [Parameter(Mandatory = $false)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if ($null -ne $Text -and $Text -match $Pattern) {
        throw [System.Exception]::new("Assertion failed: $Message (unexpected match='$Pattern')")
    }
}

function Assert-E2EThrows {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$Message
    )
    $threw = $false
    try {
        & $Action | Out-Null
    } catch {
        $threw = $true
    }
    if (-not $threw) {
        throw [System.Exception]::new("Assertion failed (expected exception): $Message")
    }
}

function Invoke-E2EDeferIfPhaseA {
    param(
        [Parameter(Mandatory = $true)][bool]$ValidateSuiteOnly,
        [Parameter(Mandatory = $true)][string]$Reason,
        [string]$Artifact = ""
    )
    $detail = $Reason
    if (-not [string]::IsNullOrWhiteSpace($Artifact)) {
        $detail = "$Reason [artifact: $Artifact]"
    }
    if ($ValidateSuiteOnly) {
        throw [System.InvalidOperationException]::new("__E2E_DEFERRED__::$detail")
    } else {
        throw [System.Exception]::new("Required deliverable missing or incomplete: $detail")
    }
}

function Invoke-E2ETestCase {
    param(
        [Parameter(Mandatory = $true)]$TestCase,
        [Parameter(Mandatory = $true)]$Context
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $status = "Passed"
    $message = ""

    try {
        & $TestCase.Body $Context
    } catch {
        $errMsg = $_.Exception.Message
        if ($errMsg -like "__E2E_DEFERRED__::*") {
            $status = "Deferred"
            $message = $errMsg.Substring("__E2E_DEFERRED__::".Length)
        } else {
            $status = "Failed"
            $message = $errMsg
        }
    } finally {
        $sw.Stop()
    }

    if ($status -eq "Deferred" -and -not $Context.ValidateSuiteOnly) {
        $status = "Failed"
        $message = "Deferral forbidden in Phase B: $message"
    }

    $record = [PSCustomObject]@{
        id         = $TestCase.Id
        tier       = $TestCase.Tier
        feature    = $TestCase.Feature
        name       = $TestCase.Name
        status     = $status
        durationMs = [int64]$sw.ElapsedMilliseconds
        message    = $message
        artifact   = $TestCase.Artifact
    }
    $script:E2EResults.Add($record)
    return $record
}

function Test-E2EThresholds {
    param(
        [Parameter(Mandatory = $true)][string]$RequestedTier,
        [Parameter(Mandatory = $true)]$AllCases
    )

    $features = @("F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8")
    $tier1Min = 5
    $tier2Min = 5
    $tier3Min = 13
    $tier4Min = 5

    $featureCounts = [ordered]@{}
    foreach ($f in $features) {
        $t1 = @($AllCases | Where-Object { $_.Tier -eq 1 -and $_.Feature -eq $f }).Count
        $t2 = @($AllCases | Where-Object { $_.Tier -eq 2 -and $_.Feature -eq $f }).Count
        $featureCounts[$f] = [ordered]@{
            tier1 = $t1
            tier2 = $t2
        }
    }

    $t1Total = @($AllCases | Where-Object { $_.Tier -eq 1 }).Count
    $t2Total = @($AllCases | Where-Object { $_.Tier -eq 2 }).Count
    $t3Total = @($AllCases | Where-Object { $_.Tier -eq 3 }).Count
    $t4Total = @($AllCases | Where-Object { $_.Tier -eq 4 }).Count

    $ok = $true
    $reasons = [System.Collections.Generic.List[string]]::new()

    if ($RequestedTier -in @("All", "1")) {
        foreach ($f in $features) {
            if ($featureCounts[$f].tier1 -lt $tier1Min) {
                $ok = $false
                $reasons.Add("Tier 1 $f count $($featureCounts[$f].tier1) < $tier1Min")
            }
        }
    }
    if ($RequestedTier -in @("All", "2")) {
        foreach ($f in $features) {
            if ($featureCounts[$f].tier2 -lt $tier2Min) {
                $ok = $false
                $reasons.Add("Tier 2 $f count $($featureCounts[$f].tier2) < $tier2Min")
            }
        }
    }
    if ($RequestedTier -in @("All", "3")) {
        if ($t3Total -lt $tier3Min) {
            $ok = $false
            $reasons.Add("Tier 3 count $t3Total < $tier3Min")
        }
    }
    if ($RequestedTier -in @("All", "4")) {
        if ($t4Total -lt $tier4Min) {
            $ok = $false
            $reasons.Add("Tier 4 count $t4Total < $tier4Min")
        }
    }

    return [PSCustomObject]@{
        tier1MinPerFeature = $tier1Min
        tier2MinPerFeature = $tier2Min
        tier3MinTotal      = $tier3Min
        tier4MinWorkloads  = $tier4Min
        tier1Total         = $t1Total
        tier2Total         = $t2Total
        tier3Total         = $t3Total
        tier4Total         = $t4Total
        passed             = $ok
        reasons            = @($reasons)
        featureCounts      = $featureCounts
    }
}

function Write-E2EReport {
    param(
        [Parameter(Mandatory = $true)]$ReportObj,
        [string]$OutputJson = ""
    )

    Write-Host ""
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host ("  ULTRA GAMING MODE v{0} E2E SUITE ({1})" -f $ReportObj.targetVersion, $ReportObj.phase) -ForegroundColor Cyan
    Write-Host ("  Tier: {0} | Admin: {1} | PreExisting UGM PIDs: {2}" -f $ReportObj.requestedTier, $ReportObj.host.isAdmin, ($ReportObj.host.preExistingUgmPids -join ",")) -ForegroundColor DarkCyan
    Write-Host "=================================================================" -ForegroundColor Cyan

    foreach ($tierNum in @(1, 2, 3, 4)) {
        $tierItems = @($ReportObj.results | Where-Object { $_.tier -eq $tierNum })
        if ($tierItems.Count -eq 0) { continue }
        Write-Host ("`n[Tier {0}] ({1} cases)" -f $tierNum, $tierItems.Count) -ForegroundColor Yellow
        foreach ($r in $tierItems) {
            $tag = "[PASS]"
            $color = "Green"
            if ($r.status -eq "Failed") {
                $tag = "[FAIL]"
                $color = "Red"
            } elseif ($r.status -eq "Deferred") {
                $tag = "[DEFERRED]"
                $color = "DarkYellow"
            }
            $line = ("  {0,-10} {1,-9} {2,-6} {3} ({4} ms)" -f $tag, $r.id, $r.feature, $r.name, $r.durationMs)
            Write-Host $line -ForegroundColor $color
            if (-not [string]::IsNullOrWhiteSpace($r.message)) {
                Write-Host ("             -> {0}" -f $r.message) -ForegroundColor Gray
            }
        }
    }

    Write-Host "`n[Threshold Matrix]" -ForegroundColor Cyan
    foreach ($fk in $ReportObj.thresholds.featureCounts.Keys) {
        $fc = $ReportObj.thresholds.featureCounts[$fk]
        Write-Host ("  {0}: Tier1={1} Tier2={2}" -f $fk, $fc.tier1, $fc.tier2) -ForegroundColor Gray
    }
    Write-Host ("  Tier3={0} | Tier4={1} | ThresholdsPassed={2}" -f $ReportObj.thresholds.tier3Total, $ReportObj.thresholds.tier4Total, $ReportObj.thresholds.passed) -ForegroundColor Gray

    $integStr = if ($ReportObj.host.integrityClean) { "CLEAN" } else { "VIOLATION" }
    Write-Host ("`nRepo/Host Integrity: {0} | Orphaned Child Processes: {1}" -f $integStr, $ReportObj.host.orphanedProcesses) -ForegroundColor $(if ($ReportObj.host.integrityClean -and $ReportObj.host.orphanedProcesses -eq 0) { "Green" } else { "Red" })
    Write-Host ("RESULT: Passed={0} Failed={1} Deferred={2} Total={3} ExitCode={4}" -f $ReportObj.summary.passed, $ReportObj.summary.failed, $ReportObj.summary.deferred, $ReportObj.summary.total, $ReportObj.exitCode) -ForegroundColor $(if ($ReportObj.exitCode -eq 0) { "Green" } else { "Red" })

    if (-not [string]::IsNullOrWhiteSpace($OutputJson)) {
        $outDir = Split-Path -Path $OutputJson -Parent
        if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -LiteralPath $outDir)) {
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        }
        $jsonText = $ReportObj | ConvertTo-Json -Depth 8
        [System.IO.File]::WriteAllText($OutputJson, $jsonText, [System.Text.UTF8Encoding]::new($false))
    }
}
