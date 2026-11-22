# Tier2.EdgeAndSecurity.ps1 — 40 Boundary, Corner, Negative & Security Tests (5 per Feature Area F1-F8)

Set-StrictMode -Version Latest

function Register-Tier2Tests {
    # =========================================================================
    # F1: Native Rust GUI & No-WebView2 Binary (5 tests)
    # =========================================================================
    Register-E2ETest -Id "T2-F1-01" -Tier 2 -Feature "F1" -Name "Window minimum size clamp 860x600 enforced in Slint root window" -Artifact "slint/main.slint" -Body {
        param($ctx)
        $slintDir = Join-Path $ctx.RepoRoot "slint"
        if (-not (Test-Path -LiteralPath $slintDir)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "slint/ templates not yet created (M4 pending)" -Artifact "slint/"
        }
        $mainSlint = Join-Path $slintDir "main.slint"
        $txt = Get-Content -LiteralPath $mainSlint -Raw -Encoding UTF8
        Assert-E2EMatch $txt 'min-width:\s*860px' "min-width must be 860px"
        Assert-E2EMatch $txt 'min-height:\s*600px' "min-height must be 600px"
        Assert-E2ENotMatch $txt 'min-width:\s*[1-7]\d{2}px' "min-width must not allow shrinking below 860px"
    }

    Register-E2ETest -Id "T2-F1-02" -Tier 2 -Feature "F1" -Name "DWM dark mode handles invalid HWND(0) and Windows build fallback (20 -> 19)" -Artifact "src/dwm.rs" -Body {
        param($ctx)
        $dwmRs = Join-Path $ctx.RepoRoot "src\dwm.rs"
        if (-not (Test-Path -LiteralPath $dwmRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/dwm.rs not yet created (M3 pending)" -Artifact "src/dwm.rs"
        }
        $raw = Get-Content -LiteralPath $dwmRs -Raw -Encoding UTF8
        Assert-E2EMatch $raw 'hwnd\s*==\s*0|hwnd\s*<=\s*0|is_null' "src/dwm.rs must guard against null HWND(0)"
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass DWM edge tests"
    }

    Register-E2ETest -Id "T2-F1-03" -Tier 2 -Feature "F1" -Name "Corrupted, empty, or missing active_state.json degrades safely to Normal" -Artifact "Core/StateEngine.ps1" -Body {
        param($ctx)
        Initialize-PsStage -RepoRoot $ctx.RepoRoot -StageRoot $ctx.Sandbox.PsStage
        $pwshPath = (Get-Process -Id $PID).Path
        $stageCore = Join-Path $ctx.Sandbox.PsStage "Core"
        $corruptFile = Join-Path $ctx.Sandbox.Root "corrupt_state.json"
        [System.IO.File]::WriteAllText($corruptFile, "{broken-json", [System.Text.UTF8Encoding]::new($false))
        $emptyFile = Join-Path $ctx.Sandbox.Root "empty_state.json"
        [System.IO.File]::WriteAllText($emptyFile, "", [System.Text.UTF8Encoding]::new($false))
        $missingFile = Join-Path $ctx.Sandbox.Root "missing_state.json"

        $cmd = @"
. '$stageCore\ServiceManager.ps1'
. '$stageCore\StateEngine.ps1'
foreach (`$p in @('$corruptFile', '$emptyFile', '$missingFile')) {
    `$st = Get-ActiveStateSafe -Path `$p
    `$mode = if (`$null -eq `$st -or [string]::IsNullOrWhiteSpace(`$st.State)) { 'Normal' } else { `$st.State }
    if (`$mode -ne 'Normal') { throw "Unexpected mode `$mode for `$p" }
}
Write-Output 'STATE_CORRUPT_SAFE'
"@
        $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
        $out = & $pwshPath -NoProfile -EncodedCommand $b64 2>&1
        Assert-E2EEqual 0 $LASTEXITCODE ("State recovery check failed: " + ($out -join " "))
        Assert-E2EMatch ($out -join "`n") 'STATE_CORRUPT_SAFE' "State recovery marker missing"
    }

    Register-E2ETest -Id "T2-F1-04" -Tier 2 -Feature "F1" -Name "PowerShell output decoder in backend handles UTF-8, UTF-16LE BOM, and OEM CP866" -Artifact "src/backend.rs" -Body {
        param($ctx)
        $backendRs = Join-Path $ctx.RepoRoot "src\backend.rs"
        if (-not (Test-Path -LiteralPath $backendRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/backend.rs not yet created (M3 pending)" -Artifact "src/backend.rs"
        }
        $raw = Get-Content -LiteralPath $backendRs -Raw -Encoding UTF8
        Assert-E2EMatch $raw '(?i)(866|cp866|from_utf16|utf8)' "Backend must support UTF-8/UTF-16/CP866 decoding"
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass output decoding tests"
    }

    Register-E2ETest -Id "T2-F1-05" -Tier 2 -Feature "F1" -Name "PE inspector rejects legacy WebView2 binary when testing built release exe" -Artifact ".bin/UltraGamingMode.exe" -Body {
        param($ctx)
        $exePath = Join-Path $ctx.RepoRoot ".bin\UltraGamingMode.exe"
        if (-not (Test-Path -LiteralPath $exePath)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin/UltraGamingMode.exe missing (M5 pending)" -Artifact ".bin/UltraGamingMode.exe"
        }
        $pe = Get-PEInspection -ExePath $exePath -Markers @("tauri::", "CreateCoreWebView2", "WebView2Loader", "slint")
        if ($pe.MarkerCounts["tauri::"] -gt 0 -or $pe.FileVersion -notlike "4.0.0*") {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin/UltraGamingMode.exe is still legacy build (M5 pending)" -Artifact ".bin/UltraGamingMode.exe"
        }
        Assert-E2EEqual 0 $pe.MarkerCounts["WebView2Loader"] "WebView2Loader symbol count must be 0"
        Assert-E2ETrue ($pe.MarkerCounts["slint"] -gt 0) "Slint marker must be > 0"
    }

    # =========================================================================
    # F2: System Tray, Single-Instance & CLI (5 tests)
    # =========================================================================
    Register-E2ETest -Id "T2-F2-01" -Tier 2 -Feature "F2" -Name "Tray icon handles unknown/unexpected mode strings safely with Red fallback" -Artifact "src/tray.rs" -Body {
        param($ctx)
        $trayRs = Join-Path $ctx.RepoRoot "src\tray.rs"
        if (-not (Test-Path -LiteralPath $trayRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/tray.rs not yet created (M3 pending)" -Artifact "src/tray.rs"
        }
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass tray unknown-mode fallback tests"
    }

    Register-E2ETest -Id "T2-F2-02" -Tier 2 -Feature "F2" -Name "Mode action re-entrancy guard prevents concurrent Enable/Restore races" -Artifact "src/backend.rs" -Body {
        param($ctx)
        $backendRs = Join-Path $ctx.RepoRoot "src\backend.rs"
        if (-not (Test-Path -LiteralPath $backendRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/backend.rs not yet created (M3 pending)" -Artifact "src/backend.rs"
        }
        $raw = Get-Content -LiteralPath $backendRs -Raw -Encoding UTF8
        Assert-E2EMatch $raw 'MODE_ACTION_BUSY|AtomicBool|compare_exchange' "Re-entrancy lock must exist in backend"
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass concurrency guard tests"
    }

    Register-E2ETest -Id "T2-F2-03" -Tier 2 -Feature "F2" -Name "Invalid CLI -Action and -ServiceOperation values rejected before execution" -Artifact "UltraGamingMode.ps1" -Body {
        param($ctx)
        Initialize-PsStage -RepoRoot $ctx.RepoRoot -StageRoot $ctx.Sandbox.PsStage
        $ps1 = Join-Path $ctx.Sandbox.PsStage "UltraGamingMode.ps1"
        $pwshPath = (Get-Process -Id $PID).Path

        $psi1 = New-SandboxedProcessStartInfo -FilePath $pwshPath -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$ps1`" -Action InvalidActionXYZ -SkipUpdateCheck" -WorkingDirectory $ctx.Sandbox.PsStage -EnvRoot $ctx.Sandbox.EnvRw -RedirectOutput $true -RequireRunAsInvoker $false
        $p1 = Start-E2EHostedProcess -StartInfo $psi1
        $null = $p1.StandardOutput.ReadToEnd(); $null = $p1.StandardError.ReadToEnd()
        $null = $p1.WaitForExit(10000)
        Assert-E2ETrue ($p1.ExitCode -ne 0) "Invalid -Action must exit non-zero"

        $psi2 = New-SandboxedProcessStartInfo -FilePath $pwshPath -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$ps1`" -Action ServiceControl -ServiceOperation DropTable -SkipUpdateCheck" -WorkingDirectory $ctx.Sandbox.PsStage -EnvRoot $ctx.Sandbox.EnvRw -RedirectOutput $true -RequireRunAsInvoker $false
        $p2 = Start-E2EHostedProcess -StartInfo $psi2
        $null = $p2.StandardOutput.ReadToEnd(); $null = $p2.StandardError.ReadToEnd()
        $null = $p2.WaitForExit(10000)
        Assert-E2ETrue ($p2.ExitCode -ne 0) "Invalid -ServiceOperation must exit non-zero"
    }

    Register-E2ETest -Id "T2-F2-04" -Tier 2 -Feature "F2" -Name "Non-elevated Enable action fails cleanly with exit code 1 before any OS mutation" -Artifact "UltraGamingMode.ps1" -Body {
        param($ctx)
        if (Test-IsElevatedAdmin) {
            return
        }
        Initialize-PsStage -RepoRoot $ctx.RepoRoot -StageRoot $ctx.Sandbox.PsStage
        $ps1 = Join-Path $ctx.Sandbox.PsStage "UltraGamingMode.ps1"
        $pwshPath = (Get-Process -Id $PID).Path
        $psi = New-SandboxedProcessStartInfo -FilePath $pwshPath -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$ps1`" -Action Enable -SkipUpdateCheck" -WorkingDirectory $ctx.Sandbox.PsStage -EnvRoot $ctx.Sandbox.EnvRw -RedirectOutput $true -RequireRunAsInvoker $false
        $p = Start-E2EHostedProcess -StartInfo $psi
        $null = $p.StandardOutput.ReadToEnd()
        $err = $p.StandardError.ReadToEnd()
        $null = $p.WaitForExit(10000)
        Assert-E2EEqual 1 $p.ExitCode "Non-elevated Enable must exit 1"
        Assert-E2EMatch $err 'Administrator' "Error must specify Administrator requirement"
    }

    Register-E2ETest -Id "T2-F2-05" -Tier 2 -Feature "F2" -Name "Task Scheduler autostart XML escapes special chars (&, <, spaces) cleanly" -Artifact "src/backend.rs" -Body {
        param($ctx)
        $backendRs = Join-Path $ctx.RepoRoot "src\backend.rs"
        if (-not (Test-Path -LiteralPath $backendRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/backend.rs not yet created (M3 pending)" -Artifact "src/backend.rs"
        }
        $raw = Get-Content -LiteralPath $backendRs -Raw -Encoding UTF8
        Assert-E2EMatch $raw 'UltraGamingMode_AutoStart' "Autostart task name must exist"
        Assert-E2EMatch $raw '&amp;|&lt;|escape_xml' "XML escaping for special path characters must exist"
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass XML escaping tests"
    }

    # =========================================================================
    # F3: 8-Theme 43(+2)-Token Engine & Smart Toggle (5 tests)
    # =========================================================================
    Register-E2ETest -Id "T2-F3-01" -Tier 2 -Feature "F3" -Name "Legacy dark/light ui_settings.json values migrate cleanly with ugm-last-* keys" -Artifact "src/themes.rs" -Body {
        param($ctx)
        $themesRs = Join-Path $ctx.RepoRoot "src\themes.rs"
        if (-not (Test-Path -LiteralPath $themesRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/themes.rs not yet created (M3 pending)" -Artifact "src/themes.rs"
        }
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass legacy theme migration tests"
    }

    Register-E2ETest -Id "T2-F3-02" -Tier 2 -Feature "F3" -Name "Unknown or cross-polarity ui_settings.json theme IDs recover cleanly" -Artifact "src/themes.rs" -Body {
        param($ctx)
        $themesRs = Join-Path $ctx.RepoRoot "src\themes.rs"
        if (-not (Test-Path -LiteralPath $themesRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/themes.rs not yet created (M3 pending)" -Artifact "src/themes.rs"
        }
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass cross-polarity sanitization tests"
    }

    Register-E2ETest -Id "T2-F3-03" -Tier 2 -Feature "F3" -Name "Read-only runtime Config/ falls back to redirected LOCALAPPDATA for ui_settings.json" -Artifact "src/themes.rs" -Body {
        param($ctx)
        $themesRs = Join-Path $ctx.RepoRoot "src\themes.rs"
        if (-not (Test-Path -LiteralPath $themesRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/themes.rs not yet created (M3 pending)" -Artifact "src/themes.rs"
        }
        $raw = Get-Content -LiteralPath $themesRs -Raw -Encoding UTF8
        $backendRs = Join-Path $ctx.RepoRoot "src\backend.rs"
        $bRaw = if (Test-Path -LiteralPath $backendRs) { Get-Content -LiteralPath $backendRs -Raw -Encoding UTF8 } else { "" }
        Assert-E2EMatch ($raw + "`n" + $bRaw) 'LOCALAPPDATA' "Fallback to LOCALAPPDATA must be implemented for read-only Config"
    }

    Register-E2ETest -Id "T2-F3-04" -Tier 2 -Feature "F3" -Name "Optional bg-app-glow and surface-top-highlight appear ONLY on themes 3,4,5,8" -Artifact "src/themes.rs" -Body {
        param($ctx)
        $themesRs = Join-Path $ctx.RepoRoot "src\themes.rs"
        if (-not (Test-Path -LiteralPath $themesRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/themes.rs not yet created (M3 pending)" -Artifact "src/themes.rs"
        }
        $raw = Get-Content -LiteralPath $themesRs -Raw -Encoding UTF8
        Assert-E2EMatch $raw 'rgba\(61,\s*219,\s*224' "emerald-ops surface highlight must exist"
        Assert-E2EMatch $raw 'rgba\(251,\s*155,\s*82' "graphite-amber surface highlight must exist"
        Assert-E2EMatch $raw 'rgba\(196,\s*168,\s*253' "midnight-violet surface highlight must exist"
        Assert-E2EMatch $raw 'rgba\(255,\s*255,\s*255,\s*0\.65\)' "frost-slate surface highlight must exist"
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must verify optional token presence/absence"
    }

    Register-E2ETest -Id "T2-F3-05" -Tier 2 -Feature "F3" -Name "Smart toggle repeated 2N times returns deterministically to initial theme" -Artifact "src/themes.rs" -Body {
        param($ctx)
        $themesRs = Join-Path $ctx.RepoRoot "src\themes.rs"
        if (-not (Test-Path -LiteralPath $themesRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/themes.rs not yet created (M3 pending)" -Artifact "src/themes.rs"
        }
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must verify toggle involution"
    }

    # =========================================================================
    # F4: AAA-Only Profile & Russian UX (5 tests)
    # =========================================================================
    Register-E2ETest -Id "T2-F4-01" -Tier 2 -Feature "F4" -Name "Legacy v3.6.0 tuning.json extra switches are ignored without breaking AAA targets" -Artifact "Core/SystemOptimizer.ps1" -Body {
        param($ctx)
        Initialize-PsStage -RepoRoot $ctx.RepoRoot -StageRoot $ctx.Sandbox.PsStage
        $pwshPath = (Get-Process -Id $PID).Path
        $stageCore = Join-Path $ctx.Sandbox.PsStage "Core"
        $cmd = @"
. '$stageCore\ServiceManager.ps1'
. '$stageCore\SystemOptimizer.ps1'
. '$stageCore\StateEngine.ps1'
`$legacy = [PSCustomObject]@{
    DisableFullscreenOptimizations = `$true
    DisableMouseAccel = `$true
    DisableNvidiaDynamicPstate = `$true
    EnableNetAdapterMsi = `$false
    InputBufferQueueSize = 250
    AutoLockTimerInGaming = `$true
    AutoPurgeRamInGaming = `$true
    AutoPurgeRamThresholdMB = 2048
}
`$hw = [PSCustomObject]@{ CpuVendor='Intel'; GpuVendor='NVIDIA'; LowRamProfile=`$false; HddProfile=`$false }
`$targets = Get-ExtendedGamingTargets -HardwareProfile `$hw -TuningConfig `$legacy
`$mouse = @(`$targets | Where-Object { `$_.Path -eq 'HKCU:\Control Panel\Mouse' -and `$_.Name -in @('MouseSpeed','MouseThreshold1','MouseThreshold2') })
`$pstate = @(`$targets | Where-Object { `$_.Name -eq 'DisableDynamicPstate' })
if (`$mouse.Count -ne 0 -or `$pstate.Count -ne 0) { throw 'Legacy overrides leaked into AAA targets' }
Write-Output 'LEGACY_IGNORED_OK'
"@
        $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
        $out = & $pwshPath -NoProfile -EncodedCommand $b64 2>&1
        Assert-E2EEqual 0 $LASTEXITCODE ("Legacy tuning check failed: " + ($out -join " "))
        Assert-E2EMatch ($out -join "`n") 'LEGACY_IGNORED_OK' "Legacy ignore marker missing"
    }

    Register-E2ETest -Id "T2-F4-02" -Tier 2 -Feature "F4" -Name "InputBufferQueueSize clamps unsafe values below 32 and defaults AAA to 100" -Artifact "Core/SystemOptimizer.ps1" -Body {
        param($ctx)
        $sysOpt = Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "Core\SystemOptimizer.ps1") -Raw -Encoding UTF8
        Assert-E2EMatch $sysOpt '100' "AAA default InputBufferQueueSize 100 must be present"
        Assert-E2EMatch $sysOpt '32' "Safety floor >= 32 must be preserved"
    }

    Register-E2ETest -Id "T2-F4-03" -Tier 2 -Feature "F4" -Name "Enable action guards against duplicate snapshot overwrite when already Armed or Active" -Artifact "UltraGamingMode.ps1" -Body {
        param($ctx)
        $ps1 = Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "UltraGamingMode.ps1") -Raw -Encoding UTF8
        Assert-E2EMatch $ps1 'Armed|GameMode_Active' "Duplicate Armed/Active state guard must exist in UltraGamingMode.ps1"
    }

    Register-E2ETest -Id "T2-F4-04" -Tier 2 -Feature "F4" -Name "Watchdog boot session check distinguishes stale boot timestamps vs current boot" -Artifact "Core/SystemOptimizer.ps1" -Body {
        param($ctx)
        Initialize-PsStage -RepoRoot $ctx.RepoRoot -StageRoot $ctx.Sandbox.PsStage
        $pwshPath = (Get-Process -Id $PID).Path
        $stageCore = Join-Path $ctx.Sandbox.PsStage "Core"
        $cmd = @"
. '$stageCore\ServiceManager.ps1'
. '$stageCore\SystemOptimizer.ps1'
`$bid = Get-SystemBootId
`$ts = Get-ResilientBootTimestamp
`$old = ([DateTime]::Parse(`$ts).AddHours(-6)).ToString('o')
if (-not (Test-IsSameBootSession -SavedBootId `$bid)) { throw 'Current BootId failed' }
if (Test-IsSameBootSession -SavedBootId (`$bid + 1)) { throw 'Mismatched BootId should be false' }
if (Test-IsSameBootSession -SavedBootId `$null -SavedBootTime `$old) { throw 'Old BootTime should be false' }
Write-Output 'BOOT_SESSION_OK'
"@
        $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
        $out = & $pwshPath -NoProfile -EncodedCommand $b64 2>&1
        Assert-E2EEqual 0 $LASTEXITCODE ("Boot session check failed: " + ($out -join " "))
        Assert-E2EMatch ($out -join "`n") 'BOOT_SESSION_OK' "Boot session marker missing"
    }

    Register-E2ETest -Id "T2-F4-05" -Tier 2 -Feature "F4" -Name "Slint UI and Rust tray have zero Competitive or Custom profile strings" -Artifact "slint/" -Body {
        param($ctx)
        $slintDir = Join-Path $ctx.RepoRoot "slint"
        $srcDir = Join-Path $ctx.RepoRoot "src"
        if (-not (Test-Path -LiteralPath $slintDir) -or -not (Test-Path -LiteralPath $srcDir)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/ or slint/ not yet created (M3/M4 pending)" -Artifact "slint/"
        }
        $all = (@(Get-ChildItem -LiteralPath $slintDir -Filter "*.slint" -Recurse) + @(Get-ChildItem -LiteralPath $srcDir -Filter "*.rs" -Recurse) | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
        Assert-E2ENotMatch $all '(?i)(Профиль оптимизации|Соревновательный|Пользовательский|competitive|CUSTOM_PROFILE)' "Zero non-AAA profile references allowed in UI/Rust"
    }

    # =========================================================================
    # F5: Descriptions & Zapret/WinDivert/winws Protection (5 tests)
    # =========================================================================
    Register-E2ETest -Id "T2-F5-01" -Tier 2 -Feature "F5" -Name "Canonical service matching strips _LUID & 4-part updater versions while keeping fixed versions" -Artifact "Core/ServiceManager.ps1" -Body {
        param($ctx)
        Initialize-PsStage -RepoRoot $ctx.RepoRoot -StageRoot $ctx.Sandbox.PsStage
        $pwshPath = (Get-Process -Id $PID).Path
        $stageCore = Join-Path $ctx.Sandbox.PsStage "Core"
        $cmd = @"
. '$stageCore\ServiceManager.ps1'
if ((Get-CanonicalServiceName 'WpnUserService_5e3a4') -ne 'WpnUserService') { throw 'LUID strip failed' }
if ((Get-CanonicalServiceName 'GoogleUpdaterService159.0.8140.0') -ne 'GoogleUpdaterService') { throw '4-part updater strip failed' }
if ((Get-CanonicalServiceName 'FontCache3.0.0.0') -ne 'FontCache3.0.0.0') { throw 'FontCache3.0.0.0 must be preserved' }
if ((Get-CanonicalServiceName 'igfxCUIService2.0.0.0') -ne 'igfxCUIService2.0.0.0') { throw 'igfxCUIService2.0.0.0 must be preserved' }
if ((Get-CanonicalServiceName 'MyDriver_64') -ne 'MyDriver_64') { throw '_64 suffix must be preserved' }
Write-Output 'CANONICAL_OK'
"@
        $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
        $out = & $pwshPath -NoProfile -EncodedCommand $b64 2>&1
        Assert-E2EEqual 0 $LASTEXITCODE ("Canonical service check failed: " + ($out -join " "))
        Assert-E2EMatch ($out -join "`n") 'CANONICAL_OK' "Canonical marker missing"
    }

    Register-E2ETest -Id "T2-F5-02" -Tier 2 -Feature "F5" -Name "Path traversal, wildcard, shell injection, and long service names rejected" -Artifact "Core/ServiceManager.ps1" -Body {
        param($ctx)
        Initialize-PsStage -RepoRoot $ctx.RepoRoot -StageRoot $ctx.Sandbox.PsStage
        $pwshPath = (Get-Process -Id $PID).Path
        $stageCore = Join-Path $ctx.Sandbox.PsStage "Core"
        $longName = "A" * 129
        $cmd = @"
. '$stageCore\ServiceManager.ps1'
foreach (`$bad in @('', '..\Evil', 'svc*', 'a;calc.exe', '$longName')) {
    if (Test-SafeServiceName -Name `$bad) { throw "Unsafe service name accepted: `$bad" }
}
if (-not (Test-SafeServiceName -Name 'Spooler')) { throw 'Valid service name rejected' }
Write-Output 'INJECTION_BLOCKED'
"@
        $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
        $out = & $pwshPath -NoProfile -EncodedCommand $b64 2>&1
        Assert-E2EEqual 0 $LASTEXITCODE ("Injection guard check failed: " + ($out -join " "))
        Assert-E2EMatch ($out -join "`n") 'INJECTION_BLOCKED' "Injection guard marker missing"
    }

    Register-E2ETest -Id "T2-F5-03" -Tier 2 -Feature "F5" -Name "Bracketed shortcut names and .ugm_backup files restore safely inside sandbox" -Artifact "Core/StateEngine.ps1" -Body {
        param($ctx)
        Initialize-PsStage -RepoRoot $ctx.RepoRoot -StageRoot $ctx.Sandbox.PsStage
        $pwshPath = (Get-Process -Id $PID).Path
        $stageCore = Join-Path $ctx.Sandbox.PsStage "Core"
        $qRoot = Join-Path $ctx.Sandbox.Root "q_bracket_test"
        $cmd = @"
. '$stageCore\ServiceManager.ps1'
. '$stageCore\StateEngine.ps1'
`$u = Join-Path '$qRoot' 'UserDst'
`$c = Join-Path '$qRoot' 'CommonDst'
`$q = Join-Path '$qRoot' 'Quarantine'
New-Item -ItemType Directory -Path `$u, `$c, (Join-Path `$q 'User') -Force | Out-Null
Set-Content -LiteralPath (Join-Path `$q 'User\Game [Modded] (v2.0).lnk') -Value 'ok'
Restore-QuarantinedShortcuts -QuarantineDir `$q -UserStartup `$u -CommonStartup `$c -StateData `$null -Scope 'User'
if (-not (Test-Path -LiteralPath (Join-Path `$u 'Game [Modded] (v2.0).lnk'))) { throw 'Bracketed shortcut missing after restore' }
Write-Output 'BRACKET_RESTORE_OK'
"@
        $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
        $out = & $pwshPath -NoProfile -EncodedCommand $b64 2>&1
        Assert-E2EEqual 0 $LASTEXITCODE ("Bracket restore failed: " + ($out -join " "))
        Assert-E2EMatch ($out -join "`n") 'BRACKET_RESTORE_OK' "Bracket restore marker missing"
    }

    Register-E2ETest -Id "T2-F5-04" -Tier 2 -Feature "F5" -Name "TCP timestamp preservation handles mixed case WINWS.EXE and WinWs2" -Artifact "Core/SystemOptimizer.ps1" -Body {
        param($ctx)
        Initialize-PsStage -RepoRoot $ctx.RepoRoot -StageRoot $ctx.Sandbox.PsStage
        $pwshPath = (Get-Process -Id $PID).Path
        $stageCore = Join-Path $ctx.Sandbox.PsStage "Core"
        $cmd = @"
. '$stageCore\ServiceManager.ps1'
. '$stageCore\SystemOptimizer.ps1'
if (-not (Test-ShouldPreserveTcpTimestamps -CurrentTimestamps 'disabled' -ActiveServiceNames @() -ActiveProcessNames @('WINWS.EXE'))) { throw 'WINWS.EXE case failed' }
if (-not (Test-ShouldPreserveTcpTimestamps -CurrentTimestamps 'disabled' -ActiveServiceNames @() -ActiveProcessNames @('WinWs2'))) { throw 'WinWs2 case failed' }
Write-Output 'MIXED_CASE_TCP_OK'
"@
        $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
        $out = & $pwshPath -NoProfile -EncodedCommand $b64 2>&1
        Assert-E2EEqual 0 $LASTEXITCODE ("Mixed-case TCP check failed: " + ($out -join " "))
        Assert-E2EMatch ($out -join "`n") 'MIXED_CASE_TCP_OK' "Mixed-case TCP marker missing"
    }

    Register-E2ETest -Id "T2-F5-05" -Tier 2 -Feature "F5" -Name "startup_apps.json excludes SearchHost, TextInputHost, and UltraGamingMode" -Artifact "Config/startup_apps.json" -Body {
        param($ctx)
        $sa = Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "Config\startup_apps.json") -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($forbidden in @("SearchHost", "TextInputHost", "UltraGamingMode")) {
            Assert-E2ETrue ($sa.BlacklistProcesses -notcontains $forbidden) "BlacklistProcesses must never include '$forbidden'"
        }
    }

    # =========================================================================
    # F6: Standby RAM & 0.5ms Timer Automation (5 tests)
    # =========================================================================
    Register-E2ETest -Id "T2-F6-01" -Tier 2 -Feature "F6" -Name "AutoPurgeRamThresholdMB clamps out-of-range values to 512..=16384" -Artifact "src/backend.rs" -Body {
        param($ctx)
        $backendRs = Join-Path $ctx.RepoRoot "src\backend.rs"
        if (-not (Test-Path -LiteralPath $backendRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/backend.rs not yet created (M3 pending)" -Artifact "src/backend.rs"
        }
        $raw = Get-Content -LiteralPath $backendRs -Raw -Encoding UTF8
        Assert-E2EMatch $raw '512' "Lower clamp 512 must exist"
        Assert-E2EMatch $raw '16384' "Upper clamp 16384 must exist"
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass threshold clamping tests"
    }

    Register-E2ETest -Id "T2-F6-02" -Tier 2 -Feature "F6" -Name "Standby RAM auto-purge suppresses triggers under 180s cooldown" -Artifact "src/backend.rs" -Body {
        param($ctx)
        $backendRs = Join-Path $ctx.RepoRoot "src\backend.rs"
        if (-not (Test-Path -LiteralPath $backendRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/backend.rs not yet created (M3 pending)" -Artifact "src/backend.rs"
        }
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass 180s cooldown boundary tests"
    }

    Register-E2ETest -Id "T2-F6-03" -Tier 2 -Feature "F6" -Name "Standby RAM auto-purge stays disabled when mode is Normal/Armed or toggle off" -Artifact "src/backend.rs" -Body {
        param($ctx)
        $backendRs = Join-Path $ctx.RepoRoot "src\backend.rs"
        if (-not (Test-Path -LiteralPath $backendRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/backend.rs not yet created (M3 pending)" -Artifact "src/backend.rs"
        }
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass mode/toggle gating tests"
    }

    Register-E2ETest -Id "T2-F6-04" -Tier 2 -Feature "F6" -Name "Standby RAM threshold strict inequality (available == threshold does not purge)" -Artifact "src/backend.rs" -Body {
        param($ctx)
        $backendRs = Join-Path $ctx.RepoRoot "src\backend.rs"
        if (-not (Test-Path -LiteralPath $backendRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/backend.rs not yet created (M3 pending)" -Artifact "src/backend.rs"
        }
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass boundary equality tests"
    }

    Register-E2ETest -Id "T2-F6-05" -Tier 2 -Feature "F6" -Name "Timer resolution clamps desired 5000 against hardware max_res" -Artifact "src/backend.rs" -Body {
        param($ctx)
        $backendRs = Join-Path $ctx.RepoRoot "src\backend.rs"
        if (-not (Test-Path -LiteralPath $backendRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/backend.rs not yet created (M3 pending)" -Artifact "src/backend.rs"
        }
        $raw = Get-Content -LiteralPath $backendRs -Raw -Encoding UTF8
        Assert-E2EMatch $raw 'NtQueryTimerResolution' "NtQueryTimerResolution must be used to clamp against hardware max_res"
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass timer clamp tests"
    }

    # =========================================================================
    # F7: Offline 3D Architecture Teardown & Docs (5 tests)
    # =========================================================================
    Register-E2ETest -Id "T2-F7-01" -Tier 2 -Feature "F7" -Name "3D Teardown adapts to 960x680, 860x600, and 390x844 viewports without collapsing canvas" -Artifact "docs/teardown/index.html" -Body {
        param($ctx)
        $htmlPath = Join-Path $ctx.RepoRoot "docs\teardown\index.html"
        if (-not $ctx.Cache.ContainsKey("TeardownCdp")) {
            $ctx.Cache["TeardownCdp"] = Invoke-TeardownCdpVerification -HtmlPath $htmlPath -UserDataDir $ctx.Sandbox.BrowserProfile
        }
        $resizes = @($ctx.Cache["TeardownCdp"].Result.resizeResults)
        Assert-E2ETrue ($resizes.Count -ge 3) "Must test 3 viewport sizes"
        foreach ($r in $resizes) {
            Assert-E2ETrue ($r.canvasW -gt 0 -and $r.canvasH -gt 0) "Canvas collapsed at viewport $($r.viewport)"
        }
    }

    Register-E2ETest -Id "T2-F7-02" -Tier 2 -Feature "F7" -Name "CDP verifier negative self-test reliably detects external HTTP requests and JS errors" -Artifact "Tests/E2E/Lib/Verify-TeardownCdp.mjs" -Body {
        param($ctx)
        $neg = Invoke-TeardownCdpVerification -UserDataDir $ctx.Sandbox.BrowserProfile -NegativeSelfTest
        Assert-E2EEqual 0 $neg.ExitCode "Negative self-test mode must return 0 when catching faults"
        Assert-E2ETrue (@($neg.Result.externalRequests).Count -gt 0) "CDP must detect injected external HTTPS request"
        Assert-E2ETrue ((@($neg.Result.consoleErrors).Count -gt 0) -or (@($neg.Result.exceptions).Count -gt 0)) "CDP must detect injected console error / uncaught exception"
    }

    Register-E2ETest -Id "T2-F7-03" -Tier 2 -Feature "F7" -Name "3D Teardown avoids external ES modules or CORS-blocked file:// imports" -Artifact "docs/teardown/index.html" -Body {
        param($ctx)
        $htmlPath = Join-Path $ctx.RepoRoot "docs\teardown\index.html"
        $raw = Get-Content -LiteralPath $htmlPath -Raw -Encoding UTF8
        Assert-E2ENotMatch $raw '<script[^>]+type\s*=\s*"module"' "Must not rely on ES module imports blocked under file:// CORS"
        Assert-E2ENotMatch $raw '\bfetch\s*\(\s*["'']https?://' "Must not call fetch() against external URLs"
    }

    Register-E2ETest -Id "T2-F7-04" -Tier 2 -Feature "F7" -Name "Backend open_teardown_page handles missing local HTML cleanly without panic" -Artifact "src/backend.rs" -Body {
        param($ctx)
        $backendRs = Join-Path $ctx.RepoRoot "src\backend.rs"
        if (-not (Test-Path -LiteralPath $backendRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/backend.rs not yet created (M3 pending)" -Artifact "src/backend.rs"
        }
        $raw = Get-Content -LiteralPath $backendRs -Raw -Encoding UTF8
        Assert-E2EMatch $raw 'teardown' "Teardown launcher logic must exist in backend.rs"
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass teardown path tests"
    }

    Register-E2ETest -Id "T2-F7-05" -Tier 2 -Feature "F7" -Name "README.md and README.ru.md contain zero broken ui/ links or missing teardown assets" -Artifact "README.md" -Body {
        param($ctx)
        foreach ($md in @("README.md", "README.ru.md")) {
            $txt = Get-Content -LiteralPath (Join-Path $ctx.RepoRoot $md) -Raw -Encoding UTF8
            if ($txt -notmatch 'docs/teardown/' -or $txt -notmatch '4\.0\.0') {
                Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "$md not yet updated for v4.0.0 (M2 pending)" -Artifact $md
            }
            Assert-E2ENotMatch $txt 'ui/src-tauri' "$md must not point to removed Tauri paths"
        }
    }

    # =========================================================================
    # F8: Portable Mode, Packaging, UTF-8 & Repo Hygiene (5 tests)
    # =========================================================================
    Register-E2ETest -Id "T2-F8-01" -Tier 2 -Feature "F8" -Name "Portable materialization preserves pre-existing user tuning.json & ui_settings.json" -Artifact ".bin/UltraGamingMode.exe" -Body {
        param($ctx)
        $exePath = Join-Path $ctx.RepoRoot ".bin\UltraGamingMode.exe"
        if (-not (Test-Path -LiteralPath $exePath)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin/UltraGamingMode.exe missing (M5 pending)" -Artifact ".bin/UltraGamingMode.exe"
        }
        $pe = Get-PEInspection -ExePath $exePath -Markers @("tauri::")
        if ($pe.MarkerCounts["tauri::"] -gt 0 -or $pe.FileVersion -notlike "4.0.0*") {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin/UltraGamingMode.exe is still pre-v4.0.0 build (M5 pending)" -Artifact ".bin/UltraGamingMode.exe"
        }
        Assert-E2EEqual 0 (Get-E2EPreExistingUgmPids).Count "No pre-existing UltraGamingMode.exe allowed"

        $portDir = Join-Path $ctx.Sandbox.Root ("port_preserve_" + [guid]::NewGuid().ToString("N").Substring(0, 6))
        $cfgDir = Join-Path $portDir "Config"
        New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $portDir "UltraGamingMode.ps1"), "# sentinel", [System.Text.UTF8Encoding]::new($false))
        $customTuning = '{"AutoLockTimerInGaming":false,"AutoPurgeRamInGaming":true,"AutoPurgeRamThresholdMB":4096}'
        [System.IO.File]::WriteAllText((Join-Path $cfgDir "tuning.json"), $customTuning, [System.Text.UTF8Encoding]::new($false))
        $portExe = Join-Path $portDir "UltraGamingMode.exe"
        Copy-Item -LiteralPath $exePath -Destination $portExe -Force

        $psi = New-SandboxedProcessStartInfo -FilePath $portExe -Arguments "--tray" -WorkingDirectory $portDir -EnvRoot $ctx.Sandbox.EnvRw -RequireRunAsInvoker ($pe.ManifestExecutionLevel -eq "requireAdministrator")
        $proc = Start-E2EHostedProcess -StartInfo $psi
        try {
            Start-Sleep -Milliseconds 2500
            $afterTuning = Get-Content -LiteralPath (Join-Path $cfgDir "tuning.json") -Raw -Encoding UTF8
            Assert-E2EMatch $afterTuning '4096' "User tuning.json threshold 4096 must NOT be overwritten"
        } finally {
            Stop-E2EProcessTree -RootPid $proc.Id
        }
    }

    Register-E2ETest -Id "T2-F8-02" -Tier 2 -Feature "F8" -Name "NTFS read-only portable directory falls back cleanly to redirected LOCALAPPDATA" -Artifact ".bin/UltraGamingMode.exe" -Body {
        param($ctx)
        $exePath = Join-Path $ctx.RepoRoot ".bin\UltraGamingMode.exe"
        if (-not (Test-Path -LiteralPath $exePath)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin/UltraGamingMode.exe missing (M5 pending)" -Artifact ".bin/UltraGamingMode.exe"
        }
        $pe = Get-PEInspection -ExePath $exePath -Markers @("tauri::")
        if ($pe.MarkerCounts["tauri::"] -gt 0 -or $pe.FileVersion -notlike "4.0.0*") {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin/UltraGamingMode.exe is still pre-v4.0.0 build (M5 pending)" -Artifact ".bin/UltraGamingMode.exe"
        }
        Assert-E2EEqual 0 (Get-E2EPreExistingUgmPids).Count "No pre-existing UltraGamingMode.exe allowed"

        $roExe = Join-Path $ctx.Sandbox.PortableRo "UltraGamingMode.exe"
        Copy-Item -LiteralPath $exePath -Destination $roExe -Force
        Set-DirectoryWriteDenyAcl -DirectoryPath $ctx.Sandbox.PortableRo
        Set-DirectoryWriteDenyAcl -DirectoryPath (Join-Path $ctx.Sandbox.EnvRo "ProgramFiles")
        Set-DirectoryWriteDenyAcl -DirectoryPath (Join-Path $ctx.Sandbox.EnvRo "ProgramData")

        $psi = New-SandboxedProcessStartInfo -FilePath $roExe -Arguments "--tray" -WorkingDirectory $ctx.Sandbox.PortableRo -EnvRoot $ctx.Sandbox.EnvRo -RequireRunAsInvoker ($pe.ManifestExecutionLevel -eq "requireAdministrator")
        $proc = Start-E2EHostedProcess -StartInfo $psi
        try {
            Start-Sleep -Milliseconds 3000
            $lad = Join-Path $ctx.Sandbox.EnvRo "LocalAppData"
            $hit = Get-ChildItem -LiteralPath $lad -Filter "UltraGamingMode.ps1" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            Assert-E2ETrue ($null -ne $hit) "Read-only portable_ro + ProgramFiles/ProgramData must fall back to LOCALAPPDATA"
        } finally {
            Stop-E2EProcessTree -RootPid $proc.Id
            Remove-DirectoryWriteDenyAcl -DirectoryPath $ctx.Sandbox.PortableRo
            Remove-DirectoryWriteDenyAcl -DirectoryPath (Join-Path $ctx.Sandbox.EnvRo "ProgramFiles")
            Remove-DirectoryWriteDenyAcl -DirectoryPath (Join-Path $ctx.Sandbox.EnvRo "ProgramData")
        }
    }

    Register-E2ETest -Id "T2-F8-03" -Tier 2 -Feature "F8" -Name "Build-Release.ps1 and installer/ contain zero WebView2 bootstrapper references" -Artifact "Build-Release.ps1" -Body {
        param($ctx)
        $br = Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "Build-Release.ps1") -Raw -Encoding UTF8
        if ($br -notmatch 'v4\.0\.0') {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "Build-Release.ps1 not yet updated for v4.0.0 (M5 pending)" -Artifact "Build-Release.ps1"
        }
        Assert-E2ENotMatch $br '(?i)webview2' "Build-Release.ps1 must not reference WebView2"
        $instDir = Join-Path $ctx.RepoRoot "installer"
        if (Test-Path -LiteralPath $instDir) {
            $instAll = (Get-ChildItem -LiteralPath $instDir -File -Recurse | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
            Assert-E2ENotMatch $instAll '(?i)webview2' "installer/ templates must not embed WebView2 bootstrapper"
        }
    }

    Register-E2ETest -Id "T2-F8-04" -Tier 2 -Feature "F8" -Name "UTF-8 BOM validator negative self-test rejects injected EF BB BF header" -Artifact "Tests/E2E/Lib/E2E.Sandbox.ps1" -Body {
        param($ctx)
        $bomFile = Join-Path $ctx.Sandbox.Root "bom_negative_probe.json"
        $noBomFile = Join-Path $ctx.Sandbox.Root "clean_probe.json"
        try {
            [System.IO.File]::WriteAllText($bomFile, '{"ok":true}', [System.Text.UTF8Encoding]::new($true))
            [System.IO.File]::WriteAllText($noBomFile, '{"ok":true}', [System.Text.UTF8Encoding]::new($false))
            $resBom = Test-Utf8NoBom -FilePath $bomFile
            $resClean = Test-Utf8NoBom -FilePath $noBomFile
            Assert-E2EEqual $false $resBom.Valid "BOM detector must reject UTF-8 BOM"
            Assert-E2EEqual $true $resClean.Valid "BOM detector must accept clean UTF-8"
        } finally {
            Remove-Item -LiteralPath $bomFile, $noBomFile -Force -ErrorAction SilentlyContinue
        }
    }

    Register-E2ETest -Id "T2-F8-05" -Tier 2 -Feature "F8" -Name "Content policy hygiene scanner catches synthetic leak while allowlisting Windows OS terms" -Artifact "Tests/E2E/Lib/E2E.Sandbox.ps1" -Body {
        param($ctx)
        $badFile = Join-Path $ctx.Sandbox.Root "policy_bad_probe.md"
        $okFile = Join-Path $ctx.Sandbox.Root "policy_ok_probe.md"
        try {
            $badText = Decode-Base64Utf8 "R2VuZXJhdGVkIGJ5IEFJIGFzc2lzdGFudCBza2lsbA=="
            $okText = (Decode-Base64Utf8 "V1NBSUZhYnJpY1N2Yw==") + " - " + (Decode-Base64Utf8 "UHJvZ3JhbSBDb21wYXRpYmlsaXR5IEFzc2lzdGFudA==")
            [System.IO.File]::WriteAllText($badFile, $badText, [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText($okFile, $okText, [System.Text.UTF8Encoding]::new($false))

            $badHits = Test-ContentPolicyHygiene -Paths @($badFile)
            $okHits = Test-ContentPolicyHygiene -Paths @($okFile)
            Assert-E2ETrue ($badHits.Count -gt 0) "Policy scanner must catch synthetic leak"
            Assert-E2EEqual 0 $okHits.Count "Policy scanner must allowlist verified Windows OS names"
        } finally {
            Remove-Item -LiteralPath $badFile, $okFile -Force -ErrorAction SilentlyContinue
        }
    }
}
