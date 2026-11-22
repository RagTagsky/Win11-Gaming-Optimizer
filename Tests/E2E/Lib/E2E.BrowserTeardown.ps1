# E2E.BrowserTeardown.ps1 — PowerShell wrapper for Verify-TeardownCdp.mjs

Set-StrictMode -Version Latest

function Invoke-TeardownCdpVerification {
    param(
        [string]$HtmlPath = "",
        [Parameter(Mandatory = $true)][string]$UserDataDir,
        [switch]$NegativeSelfTest
    )

    $nodeExe = (Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if ([string]::IsNullOrWhiteSpace($nodeExe)) {
        $fallbackNode = "C:\Program Files\nodejs\node.exe"
        if (Test-Path -LiteralPath $fallbackNode) {
            $nodeExe = $fallbackNode
        } else {
            throw "node.exe not found on host"
        }
    }

    $mjsPath = Join-Path $PSScriptRoot "Verify-TeardownCdp.mjs"
    if (-not (Test-Path -LiteralPath $mjsPath)) {
        throw "Verify-TeardownCdp.mjs missing at $mjsPath"
    }

    $argsList = @($mjsPath, "--user-data-dir", $UserDataDir)
    if ($NegativeSelfTest) {
        $argsList += "--negative-self-test"
    } else {
        $argsList += @("--html", $HtmlPath)
    }

    $stdout = & $nodeExe @argsList 2>$null
    $code = $LASTEXITCODE
    $raw = ($stdout -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Verify-TeardownCdp.mjs produced empty output (exitCode=$code)"
    }
    $parsed = $raw | ConvertFrom-Json
    return [PSCustomObject]@{
        ExitCode = $code
        Result   = $parsed
    }
}
