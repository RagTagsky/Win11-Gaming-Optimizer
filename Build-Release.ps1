<#
.SYNOPSIS
    Automated build and release packaging orchestrator for Ultra Gaming Mode.
    Compiles Tauri frontend & Rust backend, harvests release artifacts into .bin/ and root,
    computes SHA256 checksums, and prepares clean GitHub release packages.
#>
[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [switch]$CreateGhRelease,
    [string]$Tag = "v3.0.0"
)

$ErrorActionPreference = "Stop"
$rootDir = $PSScriptRoot
$binDir = Join-Path $rootDir ".bin"

if (-not (Test-Path $binDir)) {
    New-Item -Path $binDir -ItemType Directory -Force | Out-Null
}

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "   ULTRA GAMING MODE -- AUTOMATED RELEASE BUILDER    " -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan

# 1. Run Tauri Build
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

# 2. Locate and Harvest Artifacts
$releaseDir = Join-Path $rootDir "ui\src-tauri\target\release"
$bundleDir  = Join-Path $releaseDir "bundle"

Write-Host "`n[*] Harvesting compiled binaries into .bin/ ..." -ForegroundColor Cyan

# Standalone Portable EXE
$portableExe = Get-ChildItem -Path $releaseDir -Filter "*ultra-gaming-mode*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $portableExe) {
    $portableExe = Get-ChildItem -Path $releaseDir -Filter "*UltraGamingMode*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
}

if ($portableExe) {
    $destBinExe = Join-Path $binDir "UltraGamingMode.exe"
    Copy-Item -Path $portableExe.FullName -Destination $destBinExe -Force
    # Copy to project root for quick direct launch
    Copy-Item -Path $portableExe.FullName -Destination (Join-Path $rootDir "UltraGamingMode.exe") -Force
    $sizeMb = [math]::Round((Get-Item $destBinExe).Length / 1MB, 2)
    Write-Host "  [+] Portable EXE:      .bin\UltraGamingMode.exe ($sizeMb MB)" -ForegroundColor Green
    Write-Host "  [+] Root Shortcut:     .\UltraGamingMode.exe" -ForegroundColor Green
} else {
    Write-Warning "Portable executable not found in $releaseDir"
}

# NSIS Installer Setup EXE
$nsisExe = Get-ChildItem -Path (Join-Path $bundleDir "nsis") -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($nsisExe) {
    $destNsis = Join-Path $binDir "UltraGamingMode-Setup.exe"
    Copy-Item -Path $nsisExe.FullName -Destination $destNsis -Force
    $sizeMb = [math]::Round((Get-Item $destNsis).Length / 1MB, 2)
    Write-Host "  [+] NSIS Installer:    .bin\UltraGamingMode-Setup.exe ($sizeMb MB)" -ForegroundColor Green
}

# MSI Windows Installer Package
$msiPkg = Get-ChildItem -Path (Join-Path $bundleDir "msi") -Filter "*.msi" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($msiPkg) {
    $destMsi = Join-Path $binDir "UltraGamingMode.msi"
    Copy-Item -Path $msiPkg.FullName -Destination $destMsi -Force
    $sizeMb = [math]::Round((Get-Item $destMsi).Length / 1MB, 2)
    Write-Host "  [+] MSI Package:       .bin\UltraGamingMode.msi ($sizeMb MB)" -ForegroundColor Green
}

# 3. Compute Cryptographic Checksums (SHA256)
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

# 4. Optional: GitHub Release publishing via gh CLI
if ($CreateGhRelease) {
    Write-Host "`n[*] Publishing release via GitHub CLI (gh release create)..." -ForegroundColor Yellow
    $ghAssets = @($binFiles | ForEach-Object { $_.FullName })
    $ghAssets += $checksumFile

    & gh release create $Tag $ghAssets --title "Ultra Gaming Mode $Tag" --notes "Release $Tag binaries and installers"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [+] GitHub Release published successfully: $Tag" -ForegroundColor Green
    } else {
        Write-Warning "gh release create failed. Please upload files from .bin/ manually."
    }
}

Write-Host "`n=====================================================" -ForegroundColor Green
Write-Host " [SUCCESS] All release artifacts ready in .bin/:     " -ForegroundColor Green
Get-ChildItem -Path $binDir | ForEach-Object {
    $sizeMb = [math]::Round($_.Length / 1MB, 2)
    Write-Host "   - $($_.Name) ($sizeMb MB)" -ForegroundColor White
}
Write-Host "=====================================================" -ForegroundColor Green
