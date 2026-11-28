<#
.SYNOPSIS
    Automated build and release packaging orchestrator for Ultra Gaming Mode v4.1.1.
    Terminates running instances, compiles native Rust/Slint release via cargo build --release,
    populates .bin/UltraGamingMode.exe and root UltraGamingMode.exe, packages native
    UltraGamingMode-Setup.exe (NSIS) and UltraGamingMode.msi (WiX), and writes SHA256SUMS.txt.
#>
[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [switch]$CreateGhRelease,
    [string]$Tag = "v4.1.1"
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

$cleanVersion = ($Tag -replace '^[vV]', '')
if ($cleanVersion -notmatch '^\d+\.\d+\.\d+$') {
    $cleanVersion = "4.1.1"
}

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "   ULTRA GAMING MODE v$cleanVersion -- NATIVE BUILDER        " -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan

# 1. Stop any repo-local instances so target/.bin/root files are not locked (leaves Program Files install untouched)
Write-Host "`n[*] Stopping any repo-local UltraGamingMode instances..." -ForegroundColor Yellow
Get-Process -Name "UltraGamingMode", "ultra-gaming-mode" -ErrorAction SilentlyContinue | Where-Object {
    $p = $null
    try { $p = $_.MainModule.FileName } catch {}
    ($null -eq $p) -or $p.StartsWith($rootDir, [System.StringComparison]::OrdinalIgnoreCase)
} | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300

# 2. Clean stale legacy binaries from target/ and previous installer outputs from .bin/
$releaseDir = Join-Path $rootDir "target\release"
$staleExe   = Join-Path $releaseDir "ultra-gaming-mode.exe"
if (Test-Path $staleExe) {
    Remove-Item -Path $staleExe -Force -ErrorAction SilentlyContinue
    Write-Host "  [-] Removed stale legacy binary: target\release\ultra-gaming-mode.exe" -ForegroundColor DarkGray
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

# 4. Locate and Harvest Portable Binary
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

# 5. Build Native Installers (NSIS Setup EXE & WiX MSI)
$installerDir = Join-Path $rootDir "installer"
$destSetupExe = Join-Path $binDir "UltraGamingMode-Setup.exe"
$destMsi      = Join-Path $binDir "UltraGamingMode.msi"

function Resolve-ToolBinary {
    param(
        [string]$CommandName,
        [string[]]$FallbackPaths
    )
    $cmd = Get-Command $CommandName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    foreach ($fp in $FallbackPaths) {
        if (-not [string]::IsNullOrWhiteSpace($fp) -and (Test-Path -LiteralPath $fp)) {
            return $fp
        }
    }
    return $null
}

$nsiScript = Join-Path $installerDir "UltraGamingMode.nsi"
if (Test-Path -LiteralPath $nsiScript) {
    $makensis = Resolve-ToolBinary -CommandName "makensis.exe" -FallbackPaths @(
        (Join-Path $env:LOCALAPPDATA "tauri\NSIS\makensis.exe"),
        "C:\Program Files (x86)\NSIS\makensis.exe",
        "C:\Program Files\NSIS\makensis.exe"
    )
    if ($makensis) {
        Write-Host "`n[*] Building NSIS installer (.bin\UltraGamingMode-Setup.exe)..." -ForegroundColor Yellow
        Push-Location $installerDir
        try {
            & $makensis /V2 "/DAPP_VERSION=$cleanVersion" "/DOUT_FILE=$destSetupExe" $nsiScript
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $destSetupExe)) {
                throw "NSIS makensis failed with exit code $LASTEXITCODE"
            }
            $setupMb = [math]::Round((Get-Item $destSetupExe).Length / 1MB, 2)
            Write-Host "  [+] NSIS Setup EXE:    .bin\UltraGamingMode-Setup.exe ($setupMb MB)" -ForegroundColor Green
        } finally {
            Pop-Location
        }
    } else {
        Write-Warning "makensis.exe not found; skipping UltraGamingMode-Setup.exe packaging."
    }
}

$wxsScript = Join-Path $installerDir "UltraGamingMode.wxs"
if (Test-Path -LiteralPath $wxsScript) {
    $candle = Resolve-ToolBinary -CommandName "candle.exe" -FallbackPaths @(
        (Join-Path $env:LOCALAPPDATA "tauri\WixTools314\candle.exe"),
        "C:\Program Files (x86)\WiX Toolset v3.14\bin\candle.exe",
        "C:\Program Files (x86)\WiX Toolset v3.11\bin\candle.exe"
    )
    $light = Resolve-ToolBinary -CommandName "light.exe" -FallbackPaths @(
        (Join-Path $env:LOCALAPPDATA "tauri\WixTools314\light.exe"),
        "C:\Program Files (x86)\WiX Toolset v3.14\bin\light.exe",
        "C:\Program Files (x86)\WiX Toolset v3.11\bin\light.exe"
    )
    if ($candle -and $light) {
        Write-Host "`n[*] Building WiX MSI installer (.bin\UltraGamingMode.msi)..." -ForegroundColor Yellow
        $wixObj = Join-Path $env:TEMP "UltraGamingMode_$cleanVersion.wixobj"
        $wixPdb = Join-Path $binDir "UltraGamingMode.wixpdb"
        Push-Location $installerDir
        try {
            & $candle -nologo -arch x64 -ext WixUtilExtension "-dAppVersion=$cleanVersion.0" -out $wixObj $wxsScript
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $wixObj)) {
                throw "WiX candle.exe failed with exit code $LASTEXITCODE"
            }
            & $light -nologo -ext WixUIExtension -ext WixUtilExtension -spdb -sice:ICE61 -out $destMsi $wixObj
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $destMsi)) {
                throw "WiX light.exe failed with exit code $LASTEXITCODE"
            }
            $msiMb = [math]::Round((Get-Item $destMsi).Length / 1MB, 2)
            Write-Host "  [+] WiX MSI Package:   .bin\UltraGamingMode.msi ($msiMb MB)" -ForegroundColor Green
        } finally {
            Pop-Location
            Remove-Item -LiteralPath $wixObj -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $wixPdb -Force -ErrorAction SilentlyContinue
        }
    } else {
        Write-Warning "WiX candle.exe/light.exe not found; skipping UltraGamingMode.msi packaging."
    }
}

# 6. Compute Cryptographic Checksums (SHA256) in UTF-8 without BOM
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

# 7. Optional GitHub Release creation/update
if ($CreateGhRelease) {
    $notesList = [System.Collections.Generic.List[string]]::new()
    $notesList.Add(([regex]::Unescape('- \u0418\u0441\u043f\u0440\u0430\u0432\u043b\u0435\u043d\u0430 \u043f\u043e\u043c\u0435\u0442\u043a\u0430 \u0441\u0438\u0441\u0442\u0435\u043c\u043d\u044b\u0445 \u0432\u0435\u0431-\u043f\u0440\u043e\u0446\u0435\u0441\u0441\u043e\u0432 Windows 11 \u0432 \u0441\u043f\u0438\u0441\u043a\u0435 \u043f\u0440\u043e\u0446\u0435\u0441\u0441\u043e\u0432 (\u0443\u0431\u0440\u0430\u043d\u043e \u0443\u0441\u0442\u0430\u0440\u0435\u0432\u0448\u0435\u0435 \u043e\u043f\u0438\u0441\u0430\u043d\u0438\u0435 \u043e\u0442 v3)')))
    $notesList.Add(([regex]::Unescape('- \u0423\u0441\u0442\u0430\u043d\u043e\u0432\u043a\u0430 \u043e\u0431\u043d\u043e\u0432\u043b\u0435\u043d\u0438\u0439 \u0432 \u043e\u0434\u0438\u043d \u043a\u043b\u0438\u043a \u043f\u0440\u044f\u043c\u043e \u0432 \u043f\u0440\u043e\u0433\u0440\u0430\u043c\u043c\u0435 \u0441 \u043f\u0440\u043e\u0432\u0435\u0440\u043a\u043e\u0439 SHA-256')))
    $notesList.Add(([regex]::Unescape('- \u0410\u0432\u0442\u043e\u043e\u043f\u0440\u0435\u0434\u0435\u043b\u0435\u043d\u0438\u0435 \u0440\u0435\u0436\u0438\u043c\u0430 Setup, MSI \u0438\u043b\u0438 Portable \u0441 \u0431\u0435\u0437\u043e\u043f\u0430\u0441\u043d\u044b\u043c \u043f\u0435\u0440\u0435\u0437\u0430\u043f\u0443\u0441\u043a\u043e\u043c \u0438 \u0441\u043e\u0445\u0440\u0430\u043d\u0435\u043d\u0438\u0435\u043c \u043a\u043e\u043d\u0444\u0438\u0433\u043e\u0432')))
    $notesList.Add("")
    $notesList.Add(([regex]::Unescape('### \u0424\u0430\u0439\u043b\u044b \u0438 SHA-256')))
    foreach ($hl in $hashLines) {
        $notesList.Add("- $hl")
    }

    $uploadAssets = [System.Collections.Generic.List[string]]::new()
    foreach ($f in $binFiles) {
        $uploadAssets.Add($f.FullName)
    }
    if (Test-Path -LiteralPath $checksumFile) {
        $uploadAssets.Add($checksumFile)
    }

    $notesFile = Join-Path $binDir "RELEASE_NOTES.txt"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($notesFile, $notesList.ToArray(), $utf8NoBom)
    Push-Location $rootDir
    try {
        $ghCmd = Get-Command gh -ErrorAction SilentlyContinue
        if ($ghCmd) {
            $prevEap = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            & $ghCmd.Source release view $Tag *> $null
            $viewCode = $LASTEXITCODE
            $ErrorActionPreference = $prevEap
            if ($viewCode -eq 0) {
                & $ghCmd.Source release edit $Tag --title "Ultra Gaming Mode $Tag" --notes-file $notesFile
                if ($LASTEXITCODE -ne 0) { throw "gh release edit failed with exit code $LASTEXITCODE" }
                & $ghCmd.Source release upload $Tag $uploadAssets.ToArray() --clobber
                if ($LASTEXITCODE -ne 0) { throw "gh release upload failed with exit code $LASTEXITCODE" }
            } else {
                & $ghCmd.Source release create $Tag $uploadAssets.ToArray() --title "Ultra Gaming Mode $Tag" --notes-file $notesFile
                if ($LASTEXITCODE -ne 0) { throw "gh release create failed with exit code $LASTEXITCODE" }
            }
        } else {
            $credOut = ("protocol=https`nhost=github.com`n`n" | git credential fill) -join "`n"
            if ($credOut -notmatch 'password=([^\r\n]+)') {
                throw "GitHub CLI (gh) not found and git credential helper returned no token."
            }
            $token = $Matches[1].Trim()
            $headers = @{
                Authorization = "Bearer $token"
                Accept        = "application/vnd.github+json"
                "User-Agent"  = "UltraGamingMode-Builder/$cleanVersion"
            }
            $repoSlug = "RagTagsky/Win11-Gaming-Optimizer"
            $bodyText = $notesList.ToArray() -join "`n"
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

            $assetNames = @($uploadAssets | ForEach-Object { [System.IO.Path]::GetFileName($_) })
            foreach ($existingAsset in @($rel.assets)) {
                if ($existingAsset.name -in $assetNames) {
                    Invoke-RestMethod -Method Delete -Uri "https://api.github.com/repos/$repoSlug/releases/assets/$($existingAsset.id)" -Headers $headers -ErrorAction SilentlyContinue | Out-Null
                }
            }

            $uploadBase = ($rel.upload_url -replace '\{\?name,label\}$', '')
            foreach ($assetPath in $uploadAssets) {
                $assetName = [System.IO.Path]::GetFileName($assetPath)
                $ct = if ($assetName.EndsWith(".txt")) { "text/plain; charset=utf-8" } else { "application/octet-stream" }
                Invoke-RestMethod -Method Post -Uri "${uploadBase}?name=$assetName" -Headers $headers -InFile $assetPath -ContentType $ct | Out-Null
                Write-Host "  [+] Uploaded GitHub Release asset: $assetName" -ForegroundColor Green
            }
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
