<#
.SYNOPSIS
    Wrapper script so .\Build-Release.ps1 works when invoked from inside the ui/ directory.
#>
param(
    [switch]$SkipBuild,
    [switch]$CreateGhRelease,
    [string]$Tag = "v3.0.0"
)

& (Join-Path $PSScriptRoot "..\Build-Release.ps1") @PSBoundParameters
