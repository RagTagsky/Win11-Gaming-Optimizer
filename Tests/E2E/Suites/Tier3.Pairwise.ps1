# Tier3.Pairwise.ps1 -- 14 Cross-Feature Pairwise Combinatorial Cases

Set-StrictMode -Version Latest

function Register-Tier3Tests {
    Register-E2ETest -Id "T3-01" -Tier 3 -Feature "F1xF3" -Name "All 8 themes bind validly to Slint tokens and DWM dark/light polarity" -Artifact "src/themes.rs" -Body {
        param($ctx)
        $themesRs = Join-Path $ctx.RepoRoot "src\themes.rs"
        $dwmRs = Join-Path $ctx.RepoRoot "src\dwm.rs"
        $slintTheme = Join-Path $ctx.RepoRoot "slint\theme.slint"
        if (-not (Test-Path -LiteralPath $themesRs) -or -not (Test-Path -LiteralPath $dwmRs) -or -not (Test-Path -LiteralPath $slintTheme)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "themes.rs / dwm.rs / slint/theme.slint not yet created (M3/M4 pending)" -Artifact "slint/theme.slint"
        }
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass theme + DWM parity checks"
    }

    Register-E2ETest -Id "T3-02" -Tier 3 -Feature "F2xF4" -Name "Native tray status transitions operate cleanly with zero profile submenu" -Artifact "src/tray.rs" -Body {
        param($ctx)
        $trayRs = Join-Path $ctx.RepoRoot "src\tray.rs"
        if (-not (Test-Path -LiteralPath $trayRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/tray.rs not yet created (M3 pending)" -Artifact "src/tray.rs"
        }
        $raw = Get-Content -LiteralPath $trayRs -Raw -Encoding UTF8
        Assert-E2ENotMatch $raw '\u041f\u0440\u043e\u0444\u0438\u043b\u044c \u043e\u043f\u0442\u0438\u043c\u0438\u0437\u0430\u0446\u0438\u0438|competitive|custom' "Tray must remain AAA-only"
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass tray state transitions"
    }

    Register-E2ETest -Id "T3-03" -Tier 3 -Feature "F3xF8" -Name "Pre-seeded Config/ui_settings.json survives portable launch without overwriting theme choice" -Artifact ".bin/UltraGamingMode.exe" -Body {
        param($ctx)
        $exePath = Join-Path $ctx.RepoRoot ".bin\UltraGamingMode.exe"
        if (-not (Test-Path -LiteralPath $exePath)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin/UltraGamingMode.exe missing (M5 pending)" -Artifact ".bin/UltraGamingMode.exe"
        }
        $pe = Get-PEInspection -ExePath $exePath -Markers @("tauri::")
        if ($pe.MarkerCounts["tauri::"] -gt 0 -or $pe.FileVersion -notlike "4.1.1*") {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin/UltraGamingMode.exe is still pre-v4.0.0 build (M5 pending)" -Artifact ".bin/UltraGamingMode.exe"
        }

        $portDir = Join-Path $ctx.Sandbox.Root ("port_ui_" + [guid]::NewGuid().ToString("N").Substring(0, 6))
        $cfgDir = Join-Path $portDir "Config"
        New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $portDir "UltraGamingMode.ps1"), "# sentinel", [System.Text.UTF8Encoding]::new($false))
        $uiJson = '{"theme":"emerald-ops","ugm-last-dark-theme":"emerald-ops","ugm-last-light-theme":"frost-slate"}'
        [System.IO.File]::WriteAllText((Join-Path $cfgDir "ui_settings.json"), $uiJson, [System.Text.UTF8Encoding]::new($false))
        $portExe = Join-Path $portDir "UltraGamingMode.exe"
        Copy-Item -LiteralPath $exePath -Destination $portExe -Force

        $psi = New-SandboxedProcessStartInfo -FilePath $portExe -Arguments "--tray" -WorkingDirectory $portDir -EnvRoot $ctx.Sandbox.EnvRw -RequireRunAsInvoker ($pe.ManifestExecutionLevel -eq "requireAdministrator")
        $proc = Start-E2EHostedProcess -StartInfo $psi
        try {
            Start-Sleep -Milliseconds 2500
            $after = Get-Content -LiteralPath (Join-Path $cfgDir "ui_settings.json") -Raw -Encoding UTF8 | ConvertFrom-Json
            Assert-E2EEqual "emerald-ops" $after.theme "Active theme emerald-ops must be preserved"
            Assert-E2EEqual "frost-slate" $after.'ugm-last-light-theme' "Last light theme frost-slate must be preserved"
        } finally {
            Stop-E2EProcessTree -RootPid $proc.Id
        }
    }

    Register-E2ETest -Id "T3-04" -Tier 3 -Feature "F4xF5" -Name "AAA optimization targets preserve Zapret/WinDivert/winws and Flip-Model simultaneously" -Artifact "Core/SystemOptimizer.ps1" -Body {
        param($ctx)
        Initialize-PsStage -RepoRoot $ctx.RepoRoot -StageRoot $ctx.Sandbox.PsStage
        $pwshPath = (Get-Process -Id $PID).Path
        $stageCore = Join-Path $ctx.Sandbox.PsStage "Core"
        $cmd = @"
. '$stageCore\ServiceManager.ps1'
. '$stageCore\SystemOptimizer.ps1'
. '$stageCore\StateEngine.ps1'
`$hw = [PSCustomObject]@{ CpuVendor='AMD'; GpuVendor='NVIDIA'; LowRamProfile=`$false; HddProfile=`$false }
`$targets = Get-ExtendedGamingTargets -HardwareProfile `$hw -TuningConfig `$null
`$dx = `$targets | Where-Object { `$_.Name -eq 'DirectXUserGlobalSettings' }
if (`$null -eq `$dx) { throw 'Missing Flip-Model target' }
if (-not (Test-ShouldPreserveTcpTimestamps -CurrentTimestamps 'disabled' -ActiveServiceNames @('zapret') -ActiveProcessNames @('winws2'))) { throw 'Zapret TCP timestamps not preserved' }
if (Test-ProcessShouldCloseInGaming -ProcessName 'winws2' -BlacklistProcesses @('winws2') -ProtectedStartupNames @('winws2')) { throw 'winws2 closed' }
Write-Output 'PAIR_AAA_ZAPRET_OK'
"@
        $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
        $out = & $pwshPath -NoProfile -EncodedCommand $b64 2>&1
        Assert-E2EEqual 0 $LASTEXITCODE ("Pairwise AAA+Zapret failed: " + ($out -join " "))
        Assert-E2EMatch ($out -join "`n") 'PAIR_AAA_ZAPRET_OK' "Marker missing"
    }

    Register-E2ETest -Id "T3-05" -Tier 3 -Feature "F4xF6" -Name "Legacy tuning.json keys + out-of-range RAM threshold normalize cleanly to AAA defaults" -Artifact "src/backend.rs" -Body {
        param($ctx)
        $backendRs = Join-Path $ctx.RepoRoot "src\backend.rs"
        if (-not (Test-Path -LiteralPath $backendRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/backend.rs not yet created (M3 pending)" -Artifact "src/backend.rs"
        }
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass legacy tuning + threshold clamp tests"
    }

    Register-E2ETest -Id "T3-06" -Tier 3 -Feature "F5xF6" -Name "Protected processes (winws, zapret, UltraGamingMode) unaffected when memory/process cleaners run" -Artifact "Core/StateEngine.ps1" -Body {
        param($ctx)
        Initialize-PsStage -RepoRoot $ctx.RepoRoot -StageRoot $ctx.Sandbox.PsStage
        $pwshPath = (Get-Process -Id $PID).Path
        $stageCore = Join-Path $ctx.Sandbox.PsStage "Core"
        $cmd = @"
. '$stageCore\ServiceManager.ps1'
. '$stageCore\StateEngine.ps1'
foreach (`$p in @('winws','winws2','zapret','UltraGamingMode','SearchHost','TextInputHost')) {
    if (Test-ProcessShouldCloseInGaming -ProcessName `$p -BlacklistProcesses @(`$p) -ProtectedStartupNames @()) {
        throw "Critical process `$p should never close"
    }
}
Write-Output 'PAIR_PROC_GUARD_OK'
"@
        $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
        $out = & $pwshPath -NoProfile -EncodedCommand $b64 2>&1
        Assert-E2EEqual 0 $LASTEXITCODE ("Process guard check failed: " + ($out -join " "))
        Assert-E2EMatch ($out -join "`n") 'PAIR_PROC_GUARD_OK' "Marker missing"
    }

    Register-E2ETest -Id "T3-07" -Tier 3 -Feature "F1xF7" -Name "Portable UltraGamingMode.exe extracts byte-identical PS1/JSON assets and never creates docs/" -Artifact ".bin/UltraGamingMode.exe" -Body {
        param($ctx)
        $exePath = Join-Path $ctx.RepoRoot ".bin\UltraGamingMode.exe"
        $repoPs1 = Join-Path $ctx.RepoRoot "UltraGamingMode.ps1"
        $repoTuning = Join-Path $ctx.RepoRoot "Config\tuning.json"
        if (-not (Test-Path -LiteralPath $exePath)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin/UltraGamingMode.exe missing (M5 pending)" -Artifact ".bin/UltraGamingMode.exe"
        }
        $pe = Get-PEInspection -ExePath $exePath -Markers @("tauri::")
        if ($pe.MarkerCounts["tauri::"] -gt 0 -or $pe.FileVersion -notlike "4.1.1*") {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin/UltraGamingMode.exe is still pre-v4.0.0 build (M5 pending)" -Artifact ".bin/UltraGamingMode.exe"
        }

        $portDir = Join-Path $ctx.Sandbox.Root ("port_rt_" + [guid]::NewGuid().ToString("N").Substring(0, 6))
        New-Item -ItemType Directory -Path $portDir -Force | Out-Null
        $portExe = Join-Path $portDir "UltraGamingMode.exe"
        Copy-Item -LiteralPath $exePath -Destination $portExe -Force
        $psi = New-SandboxedProcessStartInfo -FilePath $portExe -Arguments "--tray" -WorkingDirectory $portDir -EnvRoot $ctx.Sandbox.EnvRw -RequireRunAsInvoker ($pe.ManifestExecutionLevel -eq "requireAdministrator")
        $proc = Start-E2EHostedProcess -StartInfo $psi
        try {
            Start-Sleep -Milliseconds 3000
            $candidates = @($portDir, (Join-Path $ctx.Sandbox.EnvRw "ProgramFiles\UltraGamingMode"), (Join-Path $ctx.Sandbox.EnvRw "ProgramData\UltraGamingMode"), (Join-Path $ctx.Sandbox.EnvRw "LocalAppData\UltraGamingMode"), (Join-Path $ctx.Sandbox.EnvRw "LocalAppData\UltraGamingMode\Runtime"))
            $foundRoot = $candidates | Where-Object { Test-Path -LiteralPath (Join-Path $_ "UltraGamingMode.ps1") } | Select-Object -First 1
            Assert-E2ETrue ($null -ne $foundRoot) "Extracted UltraGamingMode.ps1 missing in sandbox runtime candidates"
            $extractedPs1 = Join-Path $foundRoot "UltraGamingMode.ps1"
            $extractedTuning = Join-Path $foundRoot "Config\tuning.json"
            Assert-E2ETrue (Test-Path -LiteralPath $extractedTuning) "Extracted Config/tuning.json missing"
            Assert-E2EEqual (Get-FileSha256Lower $repoPs1) (Get-FileSha256Lower $extractedPs1) "Extracted UltraGamingMode.ps1 must match repo"
            Assert-E2EEqual (Get-FileSha256Lower $repoTuning) (Get-FileSha256Lower $extractedTuning) "Extracted Config/tuning.json must match repo"
            Assert-E2ETrue (-not (Test-Path -LiteralPath (Join-Path $foundRoot "docs"))) "Removed docs/ folder must not be extracted in runtime root"
            Assert-E2ETrue (-not (Test-Path -LiteralPath (Join-Path $portDir "docs"))) "Removed docs/ folder must not be extracted in portable dir"
        } finally {
            Stop-E2EProcessTree -RootPid $proc.Id
        }
    }

    Register-E2ETest -Id "T3-08" -Tier 3 -Feature "F3xF7" -Name "All 8 dark and light Slint themes render with custom primitives and DWM chrome wiring" -Artifact "src/ui_bridge.rs" -Body {
        param($ctx)
        $slintAll = (Get-ChildItem -LiteralPath (Join-Path $ctx.RepoRoot "slint") -Filter "*.slint" -Recurse | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
        $bridgeRs = Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "src\ui_bridge.rs") -Raw -Encoding UTF8
        Assert-E2ENotMatch $slintAll 'std-widgets\.slint' "Zero un-themed std-widgets imports allowed"
        Assert-E2EMatch $bridgeRs 'set_bg_app_glow_cx' "ui_bridge.rs must apply theme glow coordinate"
        Assert-E2EMatch $bridgeRs 'set_surface_top_highlight' "ui_bridge.rs must apply theme surface highlight"
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass theme & offscreen rendering tests"
        Assert-E2EMatch $ct.Output 'test_render_all_8_themes_and_views_offscreen\s*\.\.\.\s*ok' "Offscreen 8-theme rendering test must pass"
    }

    Register-E2ETest -Id "T3-09" -Tier 3 -Feature "F2xF6" -Name "Tray timer menu item and backend 0.500ms timer/Standby RAM automation stay aligned" -Artifact "src/tray.rs" -Body {
        param($ctx)
        $trayRs = Join-Path $ctx.RepoRoot "src\tray.rs"
        $backendRs = Join-Path $ctx.RepoRoot "src\backend.rs"
        if (-not (Test-Path -LiteralPath $trayRs) -or -not (Test-Path -LiteralPath $backendRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/tray.rs or src/backend.rs not yet created (M3 pending)" -Artifact "src/tray.rs"
        }
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass timer/tray integration checks"
    }

    Register-E2ETest -Id "T3-10" -Tier 3 -Feature "F5xF8" -Name "Config JSON files preserve Cyrillic UTF-8 without BOM across PS stage copy" -Artifact "Config/" -Body {
        param($ctx)
        Initialize-PsStage -RepoRoot $ctx.RepoRoot -StageRoot $ctx.Sandbox.PsStage
        $cfgDir = Join-Path $ctx.Sandbox.PsStage "Config"
        $bomViolations = Find-Utf8BomFiles -RootDir $cfgDir -Extensions @(".json")
        Assert-E2EEqual 0 $bomViolations.Count "Zero BOMs allowed in staged Config/*.json"
        $sd = (Get-Content -LiteralPath (Join-Path $cfgDir "service_descriptions.json") -Raw -Encoding UTF8 | ConvertFrom-Json).Descriptions
        $pd = (Get-Content -LiteralPath (Join-Path $cfgDir "process_descriptions.json") -Raw -Encoding UTF8 | ConvertFrom-Json).Descriptions
        Assert-E2EEqual 328 @($sd.PSObject.Properties).Count "Staged service_descriptions count must be 328"
        Assert-E2EEqual 181 @($pd.PSObject.Properties).Count "Staged process_descriptions count must be 181"
        Assert-E2EMatch ($sd.zapret.summaryRu) '[\u0410-\u042f\u0430-\u044f\u0401\u0451]' "Cyrillic UTF-8 text must remain intact for zapret"
    }

    Register-E2ETest -Id "T3-11" -Tier 3 -Feature "F4xF8" -Name "Zero prohibited attribution mentions across Rust, Slint, PS1, JSON, Markdown, and E2E tests" -Artifact "." -Body {
        param($ctx)
        $targets = @((Join-Path $ctx.RepoRoot "Core"), (Join-Path $ctx.RepoRoot "Config"), (Join-Path $ctx.RepoRoot "Tests\E2E"))
        foreach ($opt in @("src", "slint", "README.md", "README.ru.md", "Build-Release.ps1", "UltraGamingMode.ps1")) {
            $p = Join-Path $ctx.RepoRoot $opt
            if (Test-Path -LiteralPath $p) { $targets += $p }
        }
        $hits = Test-ContentPolicyHygiene -Paths $targets
        Assert-E2EEqual 0 $hits.Count ("Policy hygiene hits: " + ($hits -join "; "))
    }

    Register-E2ETest -Id "T3-12" -Tier 3 -Feature "F1xF2" -Name "Native binary combines WindowsGui subsystem, DWM import, tray symbols, and zero WebView2" -Artifact ".bin/UltraGamingMode.exe" -Body {
        param($ctx)
        $exePath = Join-Path $ctx.RepoRoot ".bin\UltraGamingMode.exe"
        if (-not (Test-Path -LiteralPath $exePath)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin/UltraGamingMode.exe missing (M5 pending)" -Artifact ".bin/UltraGamingMode.exe"
        }
        $pe = Get-PEInspection -ExePath $exePath -Markers @("tauri::", "Shell_NotifyIconW", "DwmSetWindowAttribute", "slint")
        if ($pe.MarkerCounts["tauri::"] -gt 0 -or $pe.FileVersion -notlike "4.1.1*") {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin/UltraGamingMode.exe is still pre-v4.0.0 build (M5 pending)" -Artifact ".bin/UltraGamingMode.exe"
        }
        Assert-E2EEqual "WindowsGui" $pe.Subsystem "Subsystem must be WindowsGui"
        Assert-E2ETrue ($pe.Imports -contains "dwmapi.dll") "dwmapi.dll must be imported"
        Assert-E2ETrue ($pe.Imports -contains "shell32.dll") "shell32.dll must be imported"
        Assert-E2ETrue ($pe.MarkerCounts["slint"] -gt 0) "Slint marker must exist"
    }

    Register-E2ETest -Id "T3-13" -Tier 3 -Feature "F4xF5" -Name "Low-RAM + HDD hardware profile matrix preserves protected services and skips SvcHostSplit" -Artifact "Core/SystemOptimizer.ps1" -Body {
        param($ctx)
        Initialize-PsStage -RepoRoot $ctx.RepoRoot -StageRoot $ctx.Sandbox.PsStage
        $pwshPath = (Get-Process -Id $PID).Path
        $stageCore = Join-Path $ctx.Sandbox.PsStage "Core"
        $cmd = @"
. '$stageCore\ServiceManager.ps1'
. '$stageCore\SystemOptimizer.ps1'
. '$stageCore\StateEngine.ps1'
`$low = Get-ExtendedGamingTargets -HardwareProfile ([PSCustomObject]@{ CpuVendor='AMD'; GpuVendor='AMD'; LowRamProfile=`$true; HddProfile=`$true }) -TuningConfig `$null
if (`$null -ne (`$low | Where-Object { `$_.Name -eq 'SvcHostSplitThresholdInKB' })) { throw 'SvcHostSplit should be skipped on LowRam' }
`$tasks = Get-GamingScheduledTaskTargets -HddProfile `$true
if (@(`$tasks | Where-Object { `$_.Name -eq 'ScheduledDefrag' }).Count -eq 0) { throw 'ScheduledDefrag missing on HddProfile' }
if (Test-ServiceShouldDisableInGaming -ServiceName 'SysMain' -Blacklist @('SysMain') -Whitelist @('SysMain')) { throw 'Whitelisted SysMain disabled' }
Write-Output 'PAIR_MATRIX_OK'
"@
        $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
        $out = & $pwshPath -NoProfile -EncodedCommand $b64 2>&1
        Assert-E2EEqual 0 $LASTEXITCODE ("Hardware matrix check failed: " + ($out -join " "))
        Assert-E2EMatch ($out -join "`n") 'PAIR_MATRIX_OK' "Marker missing"
    }

    Register-E2ETest -Id "T3-14" -Tier 3 -Feature "F5xF7" -Name "README docs and Dashboard pipeline reflect 328/205/95/181 counts and Zapret RFC 1323 invariants" -Artifact "slint/dashboard.slint" -Body {
        param($ctx)
        $dash = Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "slint\dashboard.slint") -Raw -Encoding UTF8
        Assert-E2EMatch $dash 'Zapret' "Dashboard pipeline must mention Zapret"
        Assert-E2EMatch $dash 'WinDivert' "Dashboard pipeline must mention WinDivert"
        Assert-E2EMatch $dash 'RFC 1323' "Dashboard pipeline must mention RFC 1323 Timestamps"

        foreach ($md in @("README.md", "README.ru.md")) {
            $raw = Get-Content -LiteralPath (Join-Path $ctx.RepoRoot $md) -Raw -Encoding UTF8
            Assert-E2EMatch $raw '328' "$md must document 328 services"
            Assert-E2EMatch $raw '205' "$md must document 205 blacklisted services"
            Assert-E2EMatch $raw '95' "$md must document 95 whitelisted services"
            Assert-E2EMatch $raw '181' "$md must document 181 processes"
            Assert-E2EMatch $raw 'Zapret|WinDivert' "$md must document Zapret/WinDivert protection"
            Assert-E2EMatch $raw 'RFC 1323' "$md must document RFC 1323 TCP timestamps"
        }
    }
}
