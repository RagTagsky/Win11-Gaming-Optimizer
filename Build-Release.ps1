<#
.SYNOPSIS
    Automated build and release packaging orchestrator for Ultra Gaming Mode.
    Terminates running instances, deletes stale hyphenated binaries, compiles Tauri release,
    and harvests UltraGamingMode.exe, NSIS setup, and MSI into .bin/ and project root.
#>
[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [switch]$CreateGhRelease,
    [string]$Tag = "v3.0.0"
)

$ErrorActionPreference = "Stop"

# Automatically detect project root whether script is run from root or ui/ directory
if (Test-Path (Join-Path $PSScriptRoot "UltraGamingMode.ps1")) {
    $rootDir = $PSScriptRoot
} elseif (Test-Path (Join-Path $PSScriptRoot "..\UltraGamingMode.ps1")) {
    $rootDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    $rootDir = $PSScriptRoot
}

$binDir = Join-Path $rootDir ".bin"
if (-not (Test-Path $binDir)) {
    New-Item -Path $binDir -ItemType Directory -Force | Out-Null
}

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "   ULTRA GAMING MODE -- AUTOMATED RELEASE BUILDER    " -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan

# 1. Stop any running instances so files are not locked
Write-Host "`n[*] Stopping any running UltraGamingMode instances..." -ForegroundColor Yellow
Stop-Process -Name "UltraGamingMode", "ultra-gaming-mode" -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300

# 2. Delete stale hyphenated binary from old Cargo configuration
$releaseDir = Join-Path $rootDir "ui\src-tauri\target\release"
$staleExe   = Join-Path $releaseDir "ultra-gaming-mode.exe"
if (Test-Path $staleExe) {
    Remove-Item -Path $staleExe -Force -ErrorAction SilentlyContinue
    Write-Host "  [-] Removed stale legacy binary: target\release\ultra-gaming-mode.exe" -ForegroundColor DarkGray
}

# 3. Run Tauri Build
if (-not $SkipBuild) {
    Write-Host "`n[*] Starting release compilation (npm run tauri build)..." -ForegroundColor Yellow
    Push-Location (Join-Path $rootDir "ui")
    try {
        npm run tauri build
        if ($LASTEXITCODE -ne 0) {
            throw "Tauri build process failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

# 4. Locate and Harvest Artifacts
$bundleDir = Join-Path $releaseDir "bundle"

Write-Host "`n[*] Harvesting compiled binaries into .bin/ and root..." -ForegroundColor Cyan

# Standalone Portable EXE (Strictly prefer UltraGamingMode.exe over any legacy binary)
$portablePath = Join-Path $releaseDir "UltraGamingMode.exe"
if (-not (Test-Path $portablePath)) {
    $fallback = Get-ChildItem -Path $releaseDir -Filter "*.exe" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "UltraGamingMode|ultra-gaming-mode" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($fallback) {
        $portablePath = $fallback.FullName
    }
}

if (Test-Path $portablePath) {
    $destBinExe  = Join-Path $binDir "UltraGamingMode.exe"
    $destRootExe = Join-Path $rootDir "UltraGamingMode.exe"
    Copy-Item -Path $portablePath -Destination $destBinExe -Force
    Copy-Item -Path $portablePath -Destination $destRootExe -Force
    $sizeMb = [math]::Round((Get-Item $destBinExe).Length / 1MB, 2)
    Write-Host "  [+] Portable EXE:      .bin\UltraGamingMode.exe ($sizeMb MB)" -ForegroundColor Green
    Write-Host "  [+] Root Executable:   .\UltraGamingMode.exe (Updated!)" -ForegroundColor Green
} else {
    Write-Warning "Portable executable not found in $releaseDir"
}

# NSIS Installer Setup EXE
$nsisExe = Get-ChildItem -Path (Join-Path $bundleDir "nsis") -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($nsisExe) {
    $destNsis = Join-Path $binDir "UltraGamingMode-Setup.exe"
    Copy-Item -Path $nsisExe.FullName -Destination $destNsis -Force
    $sizeMb = [math]::Round((Get-Item $destNsis).Length / 1MB, 2)
    Write-Host "  [+] NSIS Installer:    .bin\UltraGamingMode-Setup.exe ($sizeMb MB)" -ForegroundColor Green
}

# MSI Windows Installer Package
$msiPkg = Get-ChildItem -Path (Join-Path $bundleDir "msi") -Filter "*.msi" -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($msiPkg) {
    $destMsi = Join-Path $binDir "UltraGamingMode.msi"
    Copy-Item -Path $msiPkg.FullName -Destination $destMsi -Force
    $sizeMb = [math]::Round((Get-Item $destMsi).Length / 1MB, 2)
    Write-Host "  [+] MSI Package:       .bin\UltraGamingMode.msi ($sizeMb MB)" -ForegroundColor Green
}

# 5. Compute Cryptographic Checksums (SHA256)
Write-Host "`n[*] Computing SHA256 checksums..." -ForegroundColor Cyan
$binFiles = Get-ChildItem -Path $binDir -Include "*.exe", "*.msi", "*.zip" -File
$checksumFile = Join-Path $binDir "SHA256SUMS.txt"
$hashLines = @()

foreach ($f in $binFiles) {
    $hash = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $hashLines += "$hash  $($f.Name)"
    Write-Host "  $($f.Name): $hash" -ForegroundColor Gray
}

$hashLines | Out-File -FilePath $checksumFile -Encoding utf8 -Force
Write-Host "  [+] Checksums written: .bin\SHA256SUMS.txt" -ForegroundColor Green

Write-Host "`n=====================================================" -ForegroundColor Green
Write-Host " [SUCCESS] All release artifacts ready in .bin/:     " -ForegroundColor Green
Get-ChildItem -Path $binDir | ForEach-Object {
    $sizeMb = [math]::Round($_.Length / 1MB, 2)
    Write-Host "   - $($_.Name) ($sizeMb MB)" -ForegroundColor White
}
Write-Host "=====================================================" -ForegroundColor Green
