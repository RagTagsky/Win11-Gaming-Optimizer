<#
.SYNOPSIS
    Automated build and release packaging orchestrator for Ultra Gaming Mode v4.0.0.
    Terminates running instances, compiles native Rust/Slint release via cargo build --release,
    populates .bin/UltraGamingMode.exe and root UltraGamingMode.exe, and writes SHA256SUMS.txt.
#>
[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [switch]$CreateGhRelease,
    [string]$Tag = "v4.0.0"
)

$ErrorActionPreference = "Stop"

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
Write-Host "   ULTRA GAMING MODE v4.0.0 -- NATIVE BUILDER        " -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan

# 1. Stop any running instances so files are not locked
Write-Host "`n[*] Stopping any running UltraGamingMode instances..." -ForegroundColor Yellow
Stop-Process -Name "UltraGamingMode", "ultra-gaming-mode" -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300

# 2. Clean stale legacy binaries from target/ and .bin/
$releaseDir = Join-Path $rootDir "target\release"
$staleExe   = Join-Path $releaseDir "ultra-gaming-mode.exe"
if (Test-Path $staleExe) {
    Remove-Item -Path $staleExe -Force -ErrorAction SilentlyContinue
    Write-Host "  [-] Removed stale legacy binary: target\release\ultra-gaming-mode.exe" -ForegroundColor DarkGray
}

foreach ($legacyPkg in @("UltraGamingMode-Setup.exe", "UltraGamingMode.msi")) {
    $legacyPath = Join-Path $binDir $legacyPkg
    if (Test-Path $legacyPath) {
        Remove-Item -Path $legacyPath -Force -ErrorAction SilentlyContinue
        Write-Host "  [-] Removed legacy bundle artifact: .bin\$legacyPkg" -ForegroundColor DarkGray
    }
}

# 3. Run Native Cargo Release Build
if (-not $SkipBuild) {
    Write-Host "`n[*] Starting native release compilation (cargo build --release)..." -ForegroundColor Yellow
    Push-Location $rootDir
    try {
        cargo build --release
        if ($LASTEXITCODE -ne 0) {
            throw "Native cargo build process failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

# 4. Locate and Harvest Artifacts
Write-Host "`n[*] Harvesting compiled native binary into .bin/ and root..." -ForegroundColor Cyan

$portablePath = Join-Path $releaseDir "UltraGamingMode.exe"
if (-not (Test-Path $portablePath)) {
    throw "Compiled native executable not found at $portablePath"
}

$destBinExe  = Join-Path $binDir "UltraGamingMode.exe"
$destRootExe = Join-Path $rootDir "UltraGamingMode.exe"
Copy-Item -Path $portablePath -Destination $destBinExe -Force
Copy-Item -Path $portablePath -Destination $destRootExe -Force
$sizeMb = [math]::Round((Get-Item $destBinExe).Length / 1MB, 2)
Write-Host "  [+] Portable EXE:      .bin\UltraGamingMode.exe ($sizeMb MB)" -ForegroundColor Green
Write-Host "  [+] Root Executable:   .\UltraGamingMode.exe (Updated!)" -ForegroundColor Green

# 5. Compute Cryptographic Checksums (SHA256) in UTF-8 without BOM
Write-Host "`n[*] Computing SHA256 checksums..." -ForegroundColor Cyan
$binFiles = Get-ChildItem -Path $binDir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @(".exe", ".msi", ".zip") -and $_.Name -ne "SHA256SUMS.txt" } |
    Sort-Object Name
$checksumFile = Join-Path $binDir "SHA256SUMS.txt"
$hashLines = [System.Collections.Generic.List[string]]::new()

foreach ($f in $binFiles) {
    $hash = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $hashLines.Add("$hash  $($f.Name)")
    Write-Host "  $($f.Name): $hash" -ForegroundColor Gray
}

if ($hashLines.Count -gt 0) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($checksumFile, $hashLines.ToArray(), $utf8NoBom)
    Write-Host "  [+] Checksums written: .bin\SHA256SUMS.txt ($($hashLines.Count) files)" -ForegroundColor Green
} else {
    Write-Warning "No binary artifacts found in $binDir to checksum!"
}

# 6. Optional GitHub Release creation
if ($CreateGhRelease) {
    $exeSha = (Get-FileHash -Path $destBinExe -Algorithm SHA256).Hash.ToLowerInvariant()
    $notesLines = @(
        "- Переход на полностью нативный интерфейс Rust и Slint без внешних браузерных движков",
        "- Добавлены восемь тем оформления с мгновенным переключением и синхронизацией заголовка Windows",
        "- Единый игровой профиль AAA с автоматической очисткой кэша памяти, таймером 0.5 мс и защитой Zapret",
        "",
        "Контрольная сумма SHA-256 (UltraGamingMode.exe): $exeSha"
    )
    $notesFile = Join-Path $binDir "RELEASE_NOTES.txt"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($notesFile, $notesLines, $utf8NoBom)
    Push-Location $rootDir
    try {
        $ghCmd = Get-Command gh -ErrorAction SilentlyContinue
        if ($ghCmd) {
            & $ghCmd.Source release create $Tag $destBinExe $checksumFile --title "Ultra Gaming Mode $Tag" --notes-file $notesFile
        } else {
            $credOut = ("protocol=https`nhost=github.com`n`n" | git credential fill) -join "`n"
            if ($credOut -notmatch 'password=([^\r\n]+)') {
                throw "GitHub CLI (gh) not found and git credential helper returned no token."
            }
            $token = $Matches[1].Trim()
            $headers = @{
                Authorization = "Bearer $token"
                Accept        = "application/vnd.github+json"
                "User-Agent"  = "UltraGamingMode-Builder/4.0.0"
            }
            $repoSlug = "RagTagsky/Win11-Gaming-Optimizer"
            $bodyText = $notesLines -join "`n"
            $relPayload = (@{
                tag_name   = $Tag
                name       = "Ultra Gaming Mode $Tag"
                body       = $bodyText
                draft      = $false
                prerelease = $false
            } | ConvertTo-Json -Depth 5)

            $rel = $null
            try {
                $rel = Invoke-RestMethod -Method Get -Uri "https://api.github.com/repos/$repoSlug/releases/tags/$Tag" -Headers $headers -ErrorAction Stop
                $rel = Invoke-RestMethod -Method Patch -Uri "https://api.github.com/repos/$repoSlug/releases/$($rel.id)" -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($relPayload)) -ContentType "application/json; charset=utf-8" -ErrorAction Stop
            } catch {
                $rel = Invoke-RestMethod -Method Post -Uri "https://api.github.com/repos/$repoSlug/releases" -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($relPayload)) -ContentType "application/json; charset=utf-8" -ErrorAction Stop
            }

            foreach ($existingAsset in @($rel.assets)) {
                if ($existingAsset.name -in @("UltraGamingMode.exe", "SHA256SUMS.txt")) {
                    Invoke-RestMethod -Method Delete -Uri "https://api.github.com/repos/$repoSlug/releases/assets/$($existingAsset.id)" -Headers $headers -ErrorAction SilentlyContinue | Out-Null
                }
            }

            $uploadBase = ($rel.upload_url -replace '\{\?name,label\}$', '')
            Invoke-RestMethod -Method Post -Uri "${uploadBase}?name=UltraGamingMode.exe" -Headers $headers -InFile $destBinExe -ContentType "application/octet-stream" | Out-Null
            Invoke-RestMethod -Method Post -Uri "${uploadBase}?name=SHA256SUMS.txt" -Headers $headers -InFile $checksumFile -ContentType "text/plain; charset=utf-8" | Out-Null
            Write-Host "  [+] GitHub Release $Tag published/updated via REST API: $($rel.html_url)" -ForegroundColor Green
        }
    } finally {
        Pop-Location
        Remove-Item -LiteralPath $notesFile -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n=====================================================" -ForegroundColor Green
Write-Host " [SUCCESS] All release artifacts ready in .bin/:     " -ForegroundColor Green
Get-ChildItem -Path $binDir | ForEach-Object {
    $sizeMb = [math]::Round($_.Length / 1MB, 2)
    Write-Host "   - $($_.Name) ($sizeMb MB)" -ForegroundColor White
}
Write-Host "=====================================================" -ForegroundColor Green
