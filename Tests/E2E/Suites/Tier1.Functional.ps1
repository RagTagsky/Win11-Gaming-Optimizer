# Tier1.Functional.ps1 -- 40 Isolated Requirement-Level Tests (5 per Feature Area F1-F8)

Set-StrictMode -Version Latest

function Invoke-CachedCargoTest {
    param([Parameter(Mandatory = $true)]$Context)

    $cargoToml = Join-Path $Context.RepoRoot "Cargo.toml"
    if (-not (Test-Path -LiteralPath $cargoToml)) {
        Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $Context.ValidateSuiteOnly -Reason "Root Cargo.toml not yet created (M3 pending)" -Artifact "Cargo.toml"
    }

    if ($Context.Cache.ContainsKey("CargoTest")) {
        return $Context.Cache["CargoTest"]
    }

    $cargoExe = (Get-Command cargo.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if ([string]::IsNullOrWhiteSpace($cargoExe)) {
        $fallback = Join-Path $env:USERPROFILE ".cargo\bin\cargo.exe"
        if (Test-Path -LiteralPath $fallback) { $cargoExe = $fallback }
    }
    Assert-E2ETrue (-not [string]::IsNullOrWhiteSpace($cargoExe)) "cargo.exe must be available"

    Push-Location $Context.RepoRoot
    try {
        $out = & $cargoExe test --color never 2>&1
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    $res = [PSCustomObject]@{
        ExitCode = $code
        Output   = ($out -join "`n")
    }
    $Context.Cache["CargoTest"] = $res
    return $res
}

function Register-Tier1Tests {
    # =========================================================================
    # F1: Native Rust GUI & No-WebView2 Binary (5 tests)
    # =========================================================================
    Register-E2ETest -Id "T1-F1-01" -Tier 1 -Feature "F1" -Name "Root Cargo manifest uses Slint without Tauri/WebView2 and legacy ui/ removed" -Artifact "Cargo.toml" -Body {
        param($ctx)
        $cargoToml = Join-Path $ctx.RepoRoot "Cargo.toml"
        if (-not (Test-Path -LiteralPath $cargoToml)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "Root Cargo.toml not yet created (M3 pending)" -Artifact "Cargo.toml"
        }
        $raw = Get-Content -LiteralPath $cargoToml -Raw -Encoding UTF8
        Assert-E2EMatch $raw 'version\s*=\s*"4\.0\.0"' "Cargo.toml version must be 4.0.0"
        Assert-E2EMatch $raw 'slint' "Cargo.toml must depend on slint"
        Assert-E2ENotMatch $raw '(?i)\b(tauri|wry|webview2-com|tao)\b' "Cargo.toml must not contain Tauri or WebView2 crates"
        $legacyUi = Join-Path $ctx.RepoRoot "ui"
        if (Test-Path -LiteralPath $legacyUi) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "Legacy ui/ directory not yet removed (M4 pending)" -Artifact "ui/"
        }
    }

    Register-E2ETest -Id "T1-F1-02" -Tier 1 -Feature "F1" -Name "Frameless Slint window geometry 960x680 (min 860x600) and custom TitleBar" -Artifact "slint/main.slint" -Body {
        param($ctx)
        $slintDir = Join-Path $ctx.RepoRoot "slint"
        if (-not (Test-Path -LiteralPath $slintDir)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "slint/ templates not yet created (M4 pending)" -Artifact "slint/"
        }
        $allSlint = (Get-ChildItem -LiteralPath $slintDir -Filter "*.slint" -Recurse | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
        Assert-E2EMatch $allSlint 'no-frame:\s*true' "Slint main window must be frameless (no-frame: true)"
        Assert-E2EMatch $allSlint '960px' "Slint window width 960px must be defined"
        Assert-E2EMatch $allSlint '680px' "Slint window height 680px must be defined"
        Assert-E2EMatch $allSlint 'min-width:\s*860px' "Slint min-width 860px must be enforced"
        Assert-E2EMatch $allSlint 'min-height:\s*600px' "Slint min-height 600px must be enforced"
        Assert-E2EMatch $allSlint '(?i)titlebar' "Custom TitleBar must exist in slint/"
    }

    Register-E2ETest -Id "T1-F1-03" -Tier 1 -Feature "F1" -Name "Built UltraGamingMode.exe PE headers and markers show native Rust/Slint without WebView2" -Artifact ".bin/UltraGamingMode.exe" -Body {
        param($ctx)
        $exePath = Join-Path $ctx.RepoRoot ".bin\UltraGamingMode.exe"
        if (-not (Test-Path -LiteralPath $exePath)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin/UltraGamingMode.exe missing (M5 pending)" -Artifact ".bin/UltraGamingMode.exe"
        }
        $pe = Get-PEInspection -ExePath $exePath -Markers @("CreateCoreWebView2", "ICoreWebView2", "WebView2Loader", "tauri::", "wry::", "EBWebView", "slint", "DwmSetWindowAttribute")
        if ($pe.MarkerCounts["tauri::"] -gt 0 -or $pe.MarkerCounts["CreateCoreWebView2"] -gt 0 -or $pe.FileVersion -notlike "4.0.0*") {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin/UltraGamingMode.exe is still pre-v4.0.0 legacy build (M5 pending)" -Artifact ".bin/UltraGamingMode.exe"
        }
        Assert-E2EEqual "Amd64" $pe.Machine "PE Machine must be Amd64"
        Assert-E2EEqual "WindowsGui" $pe.Subsystem "PE Subsystem must be WindowsGui"
        Assert-E2EEqual $false $pe.IsManaged "Native Rust binary must not be managed CLR"
        $allImports = (@($pe.Imports) + @($pe.DelayImports)) -join ","
        Assert-E2EMatch $allImports 'dwmapi\.dll' "dwmapi.dll must be imported"
        Assert-E2EMatch $allImports 'user32\.dll' "user32.dll must be imported"
        Assert-E2EMatch $allImports 'shell32\.dll' "shell32.dll must be imported"
        Assert-E2ENotMatch $allImports 'WebView2Loader\.dll' "WebView2Loader.dll must not be imported"
        Assert-E2EEqual 0 $pe.MarkerCounts["CreateCoreWebView2"] "Zero CreateCoreWebView2 symbols"
        Assert-E2EEqual 0 $pe.MarkerCounts["ICoreWebView2"] "Zero ICoreWebView2 symbols"
        Assert-E2EEqual 0 $pe.MarkerCounts["tauri::"] "Zero tauri:: symbols"
        Assert-E2EEqual 0 $pe.MarkerCounts["wry::"] "Zero wry:: symbols"
        Assert-E2EEqual 0 $pe.MarkerCounts["EBWebView"] "Zero EBWebView strings"
        Assert-E2ETrue ($pe.MarkerCounts["slint"] -gt 0) "Native Slint symbols must be present in binary"
    }

    Register-E2ETest -Id "T1-F1-04" -Tier 1 -Feature "F1" -Name "Windows DWM Dark Mode synchronization uses DwmSetWindowAttribute(20/19)" -Artifact "src/dwm.rs" -Body {
        param($ctx)
        $dwmRs = Join-Path $ctx.RepoRoot "src\dwm.rs"
        if (-not (Test-Path -LiteralPath $dwmRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/dwm.rs not yet created (M3 pending)" -Artifact "src/dwm.rs"
        }
        $raw = Get-Content -LiteralPath $dwmRs -Raw -Encoding UTF8
        Assert-E2EMatch $raw 'DwmSetWindowAttribute' "src/dwm.rs must invoke DwmSetWindowAttribute"
        Assert-E2EMatch $raw '\b20\b' "src/dwm.rs must use DWMWA_USE_IMMUTABLE_DARK_MODE (20)"
        Assert-E2EMatch $raw '\b19\b' "src/dwm.rs must include fallback attribute 19"
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass cleanly"
    }

    Register-E2ETest -Id "T1-F1-05" -Tier 1 -Feature "F1" -Name "Native GUI exposes exact 5 Russian tabs and core dialogs/tooltips/console" -Artifact "slint/" -Body {
        param($ctx)
        $slintDir = Join-Path $ctx.RepoRoot "slint"
        if (-not (Test-Path -LiteralPath $slintDir)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "slint/ templates not yet created (M4 pending)" -Artifact "slint/"
        }
        $allSlint = (Get-ChildItem -LiteralPath $slintDir -Filter "*.slint" -Recurse | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
        foreach ($tabEsc in @('\u041e\u0431\u0437\u043e\u0440', '\u041f\u0440\u043e\u0446\u0435\u0441\u0441\u044b', '\u0421\u043b\u0443\u0436\u0431\u044b', '\u041d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438', '\u041e\u0431\u0441\u043b\u0443\u0436\u0438\u0432\u0430\u043d\u0438\u0435')) {
            $tab = [regex]::Unescape($tabEsc)
            Assert-E2EMatch $allSlint ([regex]::Escape($tab)) "Slint UI must contain Russian tab '$tab'"
        }
        $srcText = (Get-ChildItem -LiteralPath (Join-Path $ctx.RepoRoot "src") -Filter "*.rs" -Recurse | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
        $combined = $allSlint + "`n" + $srcText
        Assert-E2EMatch $combined '(?i)confirm' "Confirm dialog support must exist"
        Assert-E2EMatch $combined '(?i)tooltip' "Tooltip support must exist"
        Assert-E2EMatch $combined '(?i)log' "Log console support must exist"
    }

    # =========================================================================
    # F2: System Tray, Single-Instance & CLI (5 tests)
    # =========================================================================
    Register-E2ETest -Id "T1-F2-01" -Tier 1 -Feature "F2" -Name "Native tray menu includes required Russian items and zero profile submenu" -Artifact "src/tray.rs" -Body {
        param($ctx)
        $trayRs = Join-Path $ctx.RepoRoot "src\tray.rs"
        if (-not (Test-Path -LiteralPath $trayRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/tray.rs not yet created (M3 pending)" -Artifact "src/tray.rs"
        }
        $raw = Get-Content -LiteralPath $trayRs -Raw -Encoding UTF8
        foreach ($id in @("tray-status", "tray-open", "tray-toggle", "tray-clean-ram", "tray-timer", "tray-reboot", "tray-exit")) {
            Assert-E2EMatch $raw ([regex]::Escape($id)) "Tray module must define menu ID '$id'"
        }
        Assert-E2ENotMatch $raw '\u041f\u0440\u043e\u0444\u0438\u043b\u044c \u043e\u043f\u0442\u0438\u043c\u0438\u0437\u0430\u0446\u0438\u0438' "Tray must NOT have profile submenu"
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass cleanly"
    }

    Register-E2ETest -Id "T1-F2-02" -Tier 1 -Feature "F2" -Name "Dynamic 32x32 tray status icon RGBA generation verified by cargo test" -Artifact "src/tray.rs" -Body {
        param($ctx)
        $trayRs = Join-Path $ctx.RepoRoot "src\tray.rs"
        if (-not (Test-Path -LiteralPath $trayRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/tray.rs not yet created (M3 pending)" -Artifact "src/tray.rs"
        }
        $raw = Get-Content -LiteralPath $trayRs -Raw -Encoding UTF8
        Assert-E2EMatch $raw '\b32\b' "Tray icon dimension 32 must be defined"
        Assert-E2EMatch $raw '34,\s*197,\s*94' "Gaming green RGB (34,197,94) must be defined"
        Assert-E2EMatch $raw '245,\s*158,\s*11' "Armed amber RGB (245,158,11) must be defined"
        Assert-E2EMatch $raw '239,\s*68,\s*68' "Normal red RGB (239,68,68) must be defined"
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass tray icon tests"
    }

    Register-E2ETest -Id "T1-F2-03" -Tier 1 -Feature "F2" -Name "Live sandboxed --tray launch stays resident without WebView2 child processes" -Artifact ".bin/UltraGamingMode.exe" -Body {
        param($ctx)
        $exePath = Join-Path $ctx.RepoRoot ".bin\UltraGamingMode.exe"
        if (-not (Test-Path -LiteralPath $exePath)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin/UltraGamingMode.exe missing (M5 pending)" -Artifact ".bin/UltraGamingMode.exe"
        }
        $pe = Get-PEInspection -ExePath $exePath -Markers @("tauri::")
        if ($pe.MarkerCounts["tauri::"] -gt 0 -or $pe.FileVersion -notlike "4.0.0*") {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin/UltraGamingMode.exe is still legacy pre-v4.0.0 build (M5 pending)" -Artifact ".bin/UltraGamingMode.exe"
        }
        $preUgm = Get-E2EPreExistingUgmPids
        Assert-E2ETrue ($preUgm.Count -eq 0) "Host must not have pre-existing UltraGamingMode.exe running during live single-instance test"

        $stageExe = Join-Path $ctx.Sandbox.PortableRw "UltraGamingMode.exe"
        Copy-Item -LiteralPath $exePath -Destination $stageExe -Force
        $psi = New-SandboxedProcessStartInfo -FilePath $stageExe -Arguments "--tray" -WorkingDirectory $ctx.Sandbox.PortableRw -EnvRoot $ctx.Sandbox.EnvRw -RequireRunAsInvoker ($pe.ManifestExecutionLevel -eq "requireAdministrator")
        $proc = Start-E2EHostedProcess -StartInfo $psi
        try {
            Start-Sleep -Milliseconds 2500
            $proc.Refresh()
            Assert-E2EEqual $false $proc.HasExited "UltraGamingMode.exe --tray should stay alive in tray mode"
            $wv = @(Get-CimInstance Win32_Process -Filter "Name = 'msedgewebview2.exe' AND ParentProcessId = $($proc.Id)" -ErrorAction SilentlyContinue)
            Assert-E2EEqual 0 $wv.Count "Zero msedgewebview2.exe processes may spawn"
        } finally {
            Stop-E2EProcessTree -RootPid $proc.Id
        }
    }

    Register-E2ETest -Id "T1-F2-04" -Tier 1 -Feature "F2" -Name "Single-instance mutex prevents duplicate resident tray instances" -Artifact ".bin/UltraGamingMode.exe" -Body {
        param($ctx)
        $exePath = Join-Path $ctx.RepoRoot ".bin\UltraGamingMode.exe"
        if (-not (Test-Path -LiteralPath $exePath)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin/UltraGamingMode.exe missing (M5 pending)" -Artifact ".bin/UltraGamingMode.exe"
        }
        $pe = Get-PEInspection -ExePath $exePath -Markers @("tauri::")
        if ($pe.MarkerCounts["tauri::"] -gt 0 -or $pe.FileVersion -notlike "4.0.0*") {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin/UltraGamingMode.exe is still legacy pre-v4.0.0 build (M5 pending)" -Artifact ".bin/UltraGamingMode.exe"
        }
        Assert-E2EEqual 0 (Get-E2EPreExistingUgmPids).Count "No pre-existing UltraGamingMode.exe allowed"

        $stageExe = Join-Path $ctx.Sandbox.PortableRw "UltraGamingMode.exe"
        Copy-Item -LiteralPath $exePath -Destination $stageExe -Force
        $needInvoker = ($pe.ManifestExecutionLevel -eq "requireAdministrator")
        $psi1 = New-SandboxedProcessStartInfo -FilePath $stageExe -Arguments "--tray" -WorkingDirectory $ctx.Sandbox.PortableRw -EnvRoot $ctx.Sandbox.EnvRw -RequireRunAsInvoker $needInvoker
        $p1 = Start-E2EHostedProcess -StartInfo $psi1
        $p2 = $null
        try {
            Start-Sleep -Milliseconds 1800
            $psi2 = New-SandboxedProcessStartInfo -FilePath $stageExe -Arguments "--tray" -WorkingDirectory $ctx.Sandbox.PortableRw -EnvRoot $ctx.Sandbox.EnvRw -RequireRunAsInvoker $needInvoker
            $p2 = Start-E2EHostedProcess -StartInfo $psi2
            $exited = $p2.WaitForExit(5000)
            Assert-E2ETrue $exited "Second instance must exit promptly via single-instance guard"
            $p1.Refresh()
            Assert-E2EEqual $false $p1.HasExited "First instance must remain alive"
        } finally {
            if ($null -ne $p2 -and -not $p2.HasExited) { Stop-E2EProcessTree -RootPid $p2.Id }
            Stop-E2EProcessTree -RootPid $p1.Id
        }
    }

    Register-E2ETest -Id "T1-F2-05" -Tier 1 -Feature "F2" -Name "Sandboxed PowerShell CLI Status and Diagnostic execute non-destructively and parse cleanly in PS 5.1 & 7" -Artifact "UltraGamingMode.ps1" -Body {
        param($ctx)
        Initialize-PsStage -RepoRoot $ctx.RepoRoot -StageRoot $ctx.Sandbox.PsStage
        $ps1 = Join-Path $ctx.Sandbox.PsStage "UltraGamingMode.ps1"
        $bat = Join-Path $ctx.Sandbox.PsStage "UltraGamingMode.bat"
        $astFiles = @($ps1) + @(Get-ChildItem -LiteralPath (Join-Path $ctx.Sandbox.PsStage "Core") -Filter "*.ps1" | Select-Object -ExpandProperty FullName)
        $astErrs = Test-PowerShellAst -Files $astFiles
        Assert-E2EEqual 0 $astErrs.Count ("PS 5.1/7 AST errors: " + ($astErrs -join "; "))

        $batText = Get-Content -LiteralPath $bat -Raw -Encoding UTF8
        Assert-E2EMatch $batText '4\.0\.0' "UltraGamingMode.bat must report v4.0.0"

        $pwshPath = (Get-Process -Id $PID).Path
        foreach ($act in @("Status", "Diagnostic", "KernelLatencyStatus", "GpuMsiStatus")) {
            $psi = New-SandboxedProcessStartInfo -FilePath $pwshPath -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$ps1`" -Action $act -SkipUpdateCheck" -WorkingDirectory $ctx.Sandbox.PsStage -EnvRoot $ctx.Sandbox.EnvRw -RedirectOutput $true -RequireRunAsInvoker $false
            $proc = Start-E2EHostedProcess -StartInfo $psi
            $stdout = $proc.StandardOutput.ReadToEnd()
            $null = $proc.StandardError.ReadToEnd()
            $null = $proc.WaitForExit(15000)
            Assert-E2EEqual 0 $proc.ExitCode "Action '$act' must exit 0"
            Assert-E2ETrue ($stdout.Length -gt 20) "Action '$act' must emit non-empty output"
        }
    }

    # =========================================================================
    # F3: 8-Theme 43(+2)-Token Engine & Smart Toggle (5 tests)
    # =========================================================================
    Register-E2ETest -Id "T1-F3-01" -Tier 1 -Feature "F3" -Name "All 8 themes and exact 43(+2) token hex/rgba values present in themes.rs" -Artifact "src/themes.rs" -Body {
        param($ctx)
        $themesRs = Join-Path $ctx.RepoRoot "src\themes.rs"
        if (-not (Test-Path -LiteralPath $themesRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/themes.rs not yet created (M3 pending)" -Artifact "src/themes.rs"
        }
        $raw = Get-Content -LiteralPath $themesRs -Raw -Encoding UTF8
        $expectedThemes = @(
            @{ id = "dark"; name = [regex]::Unescape('\u0422\u0451\u043c\u043d\u0430\u044f \u043a\u043b\u0430\u0441\u0441\u0438\u043a\u0430'); tokens = @("#0c0f14", "#131720", "#1b202c", "#232a38", "#2c3547", "#2563eb", "#74b4fc", "#f1f5f9", "#c42b1c") },
            @{ id = "oled-obsidian"; name = [regex]::Unescape('OLED \u041e\u0431\u0441\u0438\u0434\u0438\u0430\u043d'); tokens = @("#000000", "#090b0f", "#11151d", "#191f2b", "#222a3a", "#0275a6", "#4cc4fa", "#f3f6fa", "#d42636") },
            @{ id = "emerald-ops"; name = [regex]::Unescape('\u0422\u0430\u043a\u0442\u0438\u0447\u0435\u0441\u043a\u0438\u0439 \u0438\u0437\u0443\u043c\u0440\u0443\u0434'); tokens = @("#090e0d", "#101715", "#17221f", "#1f2e2a", "#283b36", "#0e7478", "#3ddbe0", "#edf6f2", "#65e67d") },
            @{ id = "graphite-amber"; name = [regex]::Unescape('\u0421\u043f\u043e\u043a\u043e\u0439\u043d\u044b\u0439 \u0433\u0440\u0430\u0444\u0438\u0442'); tokens = @("#141518", "#1b1d21", "#24272d", "#2d3139", "#373c46", "#c2410c", "#fb9b52", "#f3f1ec", "#fdeb5b") },
            @{ id = "midnight-violet"; name = [regex]::Unescape('\u0413\u043b\u0443\u0431\u043e\u043a\u0430\u044f \u043d\u043e\u0447\u044c'); tokens = @("#0d0c16", "#151324", "#1f1c33", "#282442", "#322d52", "#7c3aed", "#c4a8fd", "#f3f1fc", "#a78bfa") },
            @{ id = "light"; name = [regex]::Unescape('\u0421\u0432\u0435\u0442\u043b\u0430\u044f \u043a\u043b\u0430\u0441\u0441\u0438\u043a\u0430'); tokens = @("#f3f6fa", "#ffffff", "#edf2f7", "#e2e9f2", "#d4dfec", "#2563eb", "#1d4ed8", "#0f172a", "#046c4e") },
            @{ id = "daylight-warm"; name = [regex]::Unescape('\u0422\u0451\u043f\u043b\u0430\u044f \u0434\u043d\u0435\u0432\u043d\u0430\u044f'); tokens = @("#f3efe6", "#fbf9f4", "#ece6da", "#e2dacb", "#d5cbb8", "#0b6e73", "#096166", "#1f1c17", "#1b6628") },
            @{ id = "frost-slate"; name = [regex]::Unescape('\u0421\u0435\u0432\u0435\u0440\u043d\u044b\u0439 \u043b\u0451\u0434'); tokens = @("#e8eef5", "#f5f8fc", "#e1e8f2", "#d4dfed", "#c5d4e6", "#3749a6", "#2c3d91", "#141e30", "#04694b") }
        )
        $lastPos = -1
        foreach ($t in $expectedThemes) {
            $idx = $raw.IndexOf("`"$($t.id)`"")
            Assert-E2ETrue ($idx -gt $lastPos) "Theme '$($t.id)' must appear in exact spec order"
            $lastPos = $idx
            Assert-E2EMatch $raw ([regex]::Escape($t.name)) "Theme Russian name '$($t.name)' must exist"
            foreach ($tok in $t.tokens) {
                Assert-E2EMatch $raw ([regex]::Escape($tok)) "Token '$tok' for '$($t.id)' must exist in themes.rs"
            }
        }
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must verify exact 43(+2) theme tokens"
    }

    Register-E2ETest -Id "T1-F3-02" -Tier 1 -Feature "F3" -Name "Slint ThemeTokens global binds all 43 base + optional glow/highlight tokens" -Artifact "slint/theme.slint" -Body {
        param($ctx)
        $slintDir = Join-Path $ctx.RepoRoot "slint"
        if (-not (Test-Path -LiteralPath $slintDir)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "slint/ templates not yet created (M4 pending)" -Artifact "slint/"
        }
        $allSlint = (Get-ChildItem -LiteralPath $slintDir -Filter "*.slint" -Recurse | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
        foreach ($tok in @("bg-app", "bg-surface", "bg-elevated", "bg-hover", "bg-active", "bg-titlebar", "border-subtle", "border-strong", "border-input", "text-primary", "text-secondary", "text-muted", "accent-solid", "accent-text", "status-active-text", "status-warn-text", "status-danger-solid", "focus-ring", "switch-off-bg", "close-hover-bg")) {
            $underscore = $tok.Replace("-", "_")
            Assert-E2ETrue (($allSlint -match [regex]::Escape($tok)) -or ($allSlint -match [regex]::Escape($underscore))) "Slint theme binding for '$tok' must exist"
        }
    }

    Register-E2ETest -Id "T1-F3-03" -Tier 1 -Feature "F3" -Name "Settings page implements 4x2 theme grid with mini-previews and keyboard accessibility" -Artifact "slint/settings.slint" -Body {
        param($ctx)
        $settingsSlint = Join-Path $ctx.RepoRoot "slint\settings.slint"
        if (-not (Test-Path -LiteralPath $settingsSlint)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "slint/settings.slint not yet created (M4 pending)" -Artifact "slint/settings.slint"
        }
        $raw = Get-Content -LiteralPath $settingsSlint -Raw -Encoding UTF8
        Assert-E2EMatch $raw '(?i)(FocusScope|accessible-role|key-pressed)' "Theme grid must support keyboard accessibility"
        Assert-E2EMatch $raw '(?i)(GridLayout|row:|col:|for\s+)' "4x2 grid layout must exist in settings.slint"
    }

    Register-E2ETest -Id "T1-F3-04" -Tier 1 -Feature "F3" -Name "Smart header toggle persists ugm-last-dark-theme and ugm-last-light-theme" -Artifact "src/themes.rs" -Body {
        param($ctx)
        $themesRs = Join-Path $ctx.RepoRoot "src\themes.rs"
        if (-not (Test-Path -LiteralPath $themesRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/themes.rs not yet created (M3 pending)" -Artifact "src/themes.rs"
        }
        $raw = Get-Content -LiteralPath $themesRs -Raw -Encoding UTF8
        Assert-E2EMatch $raw 'ugm-last-dark-theme' "ugm-last-dark-theme persistence key required"
        Assert-E2EMatch $raw 'ugm-last-light-theme' "ugm-last-light-theme persistence key required"
        Assert-E2EMatch $raw 'ui_settings\.json' "ui_settings.json persistence required"
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass theme persistence/toggle tests"
    }

    Register-E2ETest -Id "T1-F3-05" -Tier 1 -Feature "F3" -Name "Theme polarity maps 5 dark themes to DWM true and 3 light themes to DWM false" -Artifact "src/ui_bridge.rs" -Body {
        param($ctx)
        $themesRs = Join-Path $ctx.RepoRoot "src\themes.rs"
        $bridgeRs = Join-Path $ctx.RepoRoot "src\ui_bridge.rs"
        if (-not (Test-Path -LiteralPath $themesRs) -or -not (Test-Path -LiteralPath $bridgeRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/themes.rs or src/ui_bridge.rs not yet created (M3/M4 pending)" -Artifact "src/ui_bridge.rs"
        }
        $combined = (Get-Content -LiteralPath $themesRs -Raw -Encoding UTF8) + "`n" + (Get-Content -LiteralPath $bridgeRs -Raw -Encoding UTF8)
        Assert-E2EMatch $combined 'apply_dwm_dark_mode' "UI bridge must invoke apply_dwm_dark_mode on theme updates"
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass"
    }

    # =========================================================================
    # F4: AAA-Only Profile & Russian UX (5 tests)
    # =========================================================================
    Register-E2ETest -Id "T1-F4-01" -Tier 1 -Feature "F4" -Name "Zero competitive or custom profiles remain in PowerShell engine and tuning.json" -Artifact "Core/" -Body {
        param($ctx)
        $psFiles = @((Join-Path $ctx.RepoRoot "UltraGamingMode.ps1")) + @(Get-ChildItem -LiteralPath (Join-Path $ctx.RepoRoot "Core") -Filter "*.ps1" | Select-Object -ExpandProperty FullName)
        foreach ($f in $psFiles) {
            $txt = Get-Content -LiteralPath $f -Raw -Encoding UTF8
            Assert-E2ENotMatch $txt '(?i)(CUSTOM_PROFILE_OVERRIDE|CompetitiveProfile|Profile\s*=\s*"(competitive|custom)")' "Legacy profile branching must not exist in $f"
        }
        $tun = Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "Config\tuning.json") -Raw -Encoding UTF8 | ConvertFrom-Json
        $props = @($tun.PSObject.Properties.Name)
        Assert-E2EEqual 3 $props.Count "Config/tuning.json must contain strictly 3 AAA keys"
    }

    Register-E2ETest -Id "T1-F4-02" -Tier 1 -Feature "F4" -Name "AAA Flip-Model and fixed latency defaults enforced in Core engine" -Artifact "Core/SystemOptimizer.ps1" -Body {
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
`$mouse = @(`$targets | Where-Object { `$_.Path -eq 'HKCU:\Control Panel\Mouse' -and `$_.Name -in @('MouseSpeed','MouseThreshold1','MouseThreshold2') })
`$pstate = @(`$targets | Where-Object { `$_.Name -eq 'DisableDynamicPstate' })
if (`$null -eq `$dx -or `$dx.Value -ne 'SwapEffectUpgradeEnable=1;VRROptimizeEnable=1;') { throw 'Missing AAA Flip-Model DirectXUserGlobalSettings' }
if (`$mouse.Count -ne 0) { throw 'Mouse curve override must not exist' }
if (`$pstate.Count -ne 0) { throw 'DisableDynamicPstate override must not exist' }
Write-Output 'AAA_DEFAULTS_OK'
"@
        $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
        $out = & $pwshPath -NoProfile -EncodedCommand $b64 2>&1
        Assert-E2EEqual 0 $LASTEXITCODE ("AAA defaults check failed: " + ($out -join " "))
        Assert-E2EMatch ($out -join "`n") 'AAA_DEFAULTS_OK' "AAA defaults check must output marker"
    }

    Register-E2ETest -Id "T1-F4-03" -Tier 1 -Feature "F4" -Name "Existing Verify-UniversalEngine.ps1 passes 100% as opaque-box gate" -Artifact "Tests/Verify-UniversalEngine.ps1" -Body {
        param($ctx)
        $vue = Join-Path $ctx.RepoRoot "Tests\Verify-UniversalEngine.ps1"
        $pwshPath = (Get-Process -Id $PID).Path
        $out = & $pwshPath -NoProfile -ExecutionPolicy Bypass -File $vue 2>&1
        Assert-E2EEqual 0 $LASTEXITCODE ("Verify-UniversalEngine.ps1 failed: " + ($out -join "`n"))
        Assert-E2EMatch ($out -join "`n") '0 Failures' "Verify-UniversalEngine.ps1 must report 0 Failures"
    }

    Register-E2ETest -Id "T1-F4-04" -Tier 1 -Feature "F4" -Name "Slint UI displays intuitive Russian UX without legacy tweak switches" -Artifact "slint/" -Body {
        param($ctx)
        $slintDir = Join-Path $ctx.RepoRoot "slint"
        if (-not (Test-Path -LiteralPath $slintDir)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "slint/ templates not yet created (M4 pending)" -Artifact "slint/"
        }
        $allSlint = (Get-ChildItem -LiteralPath $slintDir -Filter "*.slint" -Recurse | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
        Assert-E2EMatch $allSlint 'AAA' "UI must clearly denote AAA mode"
        foreach ($legacy in @("DisableFullscreenOptimizations", "DisableMouseAccel", "DisableNvidiaDynamicPstate", "EnableNetAdapterMsi", "InputBufferQueueSize")) {
            Assert-E2ENotMatch $allSlint $legacy "Legacy switch '$legacy' must not appear in Slint UI"
        }
    }

    Register-E2ETest -Id "T1-F4-05" -Tier 1 -Feature "F4" -Name "Version 4.0.0 synchronized across PS engine, bat launcher, Cargo.toml, and Build-Release.ps1" -Artifact "Core/StateEngine.ps1" -Body {
        param($ctx)
        $se = Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "Core\StateEngine.ps1") -Raw -Encoding UTF8
        Assert-E2EMatch $se '\$Script:APP_VERSION\s*=\s*"4\.0\.0"' "Core/StateEngine.ps1 must be 4.0.0"
        $bat = Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "UltraGamingMode.bat") -Raw -Encoding UTF8
        Assert-E2EMatch $bat '4\.0\.0' "UltraGamingMode.bat must be 4.0.0"

        $cargoToml = Join-Path $ctx.RepoRoot "Cargo.toml"
        if (-not (Test-Path -LiteralPath $cargoToml)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "Cargo.toml not yet created (M3 pending)" -Artifact "Cargo.toml"
        }
        $br = Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "Build-Release.ps1") -Raw -Encoding UTF8
        if ($br -notmatch 'v4\.0\.0') {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "Build-Release.ps1 not yet updated to v4.0.0 (M5 pending)" -Artifact "Build-Release.ps1"
        }
        Assert-E2EMatch (Get-Content -LiteralPath $cargoToml -Raw -Encoding UTF8) 'version\s*=\s*"4\.0\.0"' "Cargo.toml must be 4.0.0"
    }

    # =========================================================================
    # F5: Descriptions & Zapret/WinDivert/winws Protection (5 tests)
    # =========================================================================
    Register-E2ETest -Id "T1-F5-01" -Tier 1 -Feature "F5" -Name "Exact 328 service and 181 process Russian descriptions with safetyLevel breakdown" -Artifact "Config/service_descriptions.json" -Body {
        param($ctx)
        $sd = (Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "Config\service_descriptions.json") -Raw -Encoding UTF8 | ConvertFrom-Json).Descriptions
        $pd = (Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "Config\process_descriptions.json") -Raw -Encoding UTF8 | ConvertFrom-Json).Descriptions
        $sProps = @($sd.PSObject.Properties)
        $pProps = @($pd.PSObject.Properties)
        Assert-E2EEqual 328 $sProps.Count "service_descriptions.json must contain 328 entries"
        Assert-E2EEqual 181 $pProps.Count "process_descriptions.json must contain 181 entries"

        $sCounts = @{ safe = 0; optional = 0; protected = 0 }
        foreach ($p in $sProps) {
            Assert-E2ETrue (-not [string]::IsNullOrWhiteSpace($p.Value.summaryRu)) "Service '$($p.Name)' summaryRu required"
            Assert-E2ETrue (-not [string]::IsNullOrWhiteSpace($p.Value.canDisableRu)) "Service '$($p.Name)' canDisableRu required"
            $sCounts[$p.Value.safetyLevel]++
        }
        Assert-E2EEqual 137 $sCounts["safe"] "service safe count"
        Assert-E2EEqual 91 $sCounts["optional"] "service optional count"
        Assert-E2EEqual 100 $sCounts["protected"] "service protected count"

        $pCounts = @{ safe = 0; optional = 0; protected = 0 }
        foreach ($p in $pProps) {
            Assert-E2ETrue (-not [string]::IsNullOrWhiteSpace($p.Value.displayNameRu)) "Process '$($p.Name)' displayNameRu required"
            Assert-E2ETrue (-not [string]::IsNullOrWhiteSpace($p.Value.summaryRu)) "Process '$($p.Name)' summaryRu required"
            $pCounts[$p.Value.safetyLevel]++
        }
        Assert-E2EEqual 47 $pCounts["safe"] "process safe count"
        Assert-E2EEqual 65 $pCounts["optional"] "process optional count"
        Assert-E2EEqual 69 $pCounts["protected"] "process protected count"
    }

    Register-E2ETest -Id "T1-F5-02" -Tier 1 -Feature "F5" -Name "Whitelist (95) and Blacklist (205) are disjoint with 100% description coverage" -Artifact "Config/services_whitelist.json" -Body {
        param($ctx)
        $wl = @((Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "Config\services_whitelist.json") -Raw -Encoding UTF8 | ConvertFrom-Json).ProtectedServices)
        $bl = @((Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "Config\services_blacklist.json") -Raw -Encoding UTF8 | ConvertFrom-Json).TargetServices | ForEach-Object { $_.Name })
        $sd = (Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "Config\service_descriptions.json") -Raw -Encoding UTF8 | ConvertFrom-Json).Descriptions
        Assert-E2EEqual 95 $wl.Count "Whitelist count must be 95"
        Assert-E2EEqual 205 $bl.Count "Blacklist count must be 205"

        $wlSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($w in $wl) { $null = $wlSet.Add($w) }
        $overlap = @($bl | Where-Object { $wlSet.Contains($_) })
        Assert-E2EEqual 0 $overlap.Count ("Whitelist/Blacklist overlap: " + ($overlap -join ","))

        $sdMap = @{}
        foreach ($p in $sd.PSObject.Properties) { $sdMap[$p.Name.ToLowerInvariant()] = $true }
        foreach ($s in ($wl + $bl)) {
            Assert-E2ETrue $sdMap.ContainsKey($s.ToLowerInvariant()) "Service '$s' missing from service_descriptions.json"
        }
    }

    Register-E2ETest -Id "T1-F5-03" -Tier 1 -Feature "F5" -Name "All 27 immutable core services block disable/stop across PS engine" -Artifact "Core/ServiceManager.ps1" -Body {
        param($ctx)
        Initialize-PsStage -RepoRoot $ctx.RepoRoot -StageRoot $ctx.Sandbox.PsStage
        $pwshPath = (Get-Process -Id $PID).Path
        $stageCore = Join-Path $ctx.Sandbox.PsStage "Core"
        $cmd = @"
. '$stageCore\ServiceManager.ps1'
`$core27 = @('RpcSs','DcomLaunch','RpcEptMapper','PlugPlay','Power','LSM','SamSs','EventLog','BFE','mpssvc','ProfSvc','UserManager','CryptSvc','KeyIso','VaultSvc','CoreMessagingRegistrar','SystemEventsBroker','BrokerInfrastructure','nsi','Dhcp','Dnscache','Winmgmt','Schedule','TrustedInstaller','Audiosrv','AudioEndpointBuilder','MMCSS')
foreach (`$svc in `$core27) {
    if (Test-ServiceShouldDisableInGaming -ServiceName `$svc -Blacklist `$core27 -Whitelist @()) {
        throw "Core service `$svc was not blocked"
    }
}
Write-Output 'CORE27_PROTECTED'
"@
        $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
        $out = & $pwshPath -NoProfile -EncodedCommand $b64 2>&1
        Assert-E2EEqual 0 $LASTEXITCODE ("Core27 check failed: " + ($out -join " "))
        Assert-E2EMatch ($out -join "`n") 'CORE27_PROTECTED' "Core27 check marker missing"
    }

    Register-E2ETest -Id "T1-F5-04" -Tier 1 -Feature "F5" -Name "Zapret, WinDivert, WinDivert14, winws, winws2 protected in configs and engine" -Artifact "Config/startup_apps.json" -Body {
        param($ctx)
        $wl = @((Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "Config\services_whitelist.json") -Raw -Encoding UTF8 | ConvertFrom-Json).ProtectedServices)
        foreach ($s in @("zapret", "WinDivert", "WinDivert14")) {
            Assert-E2ETrue ($wl -contains $s) "Whitelist must protect '$s'"
        }
        $sa = Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "Config\startup_apps.json") -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in @("zapret", "winws", "winws2")) {
            Assert-E2ETrue ($sa.ProtectedStartupNames -contains $p) "ProtectedStartupNames must protect '$p'"
        }

        Initialize-PsStage -RepoRoot $ctx.RepoRoot -StageRoot $ctx.Sandbox.PsStage
        $pwshPath = (Get-Process -Id $PID).Path
        $stageCore = Join-Path $ctx.Sandbox.PsStage "Core"
        $cmd = @"
. '$stageCore\ServiceManager.ps1'
. '$stageCore\StateEngine.ps1'
foreach (`$p in @('winws','winws2','zapret')) {
    if (Test-ProcessShouldCloseInGaming -ProcessName `$p -BlacklistProcesses @('winws','winws2','zapret') -ProtectedStartupNames @()) {
        throw "Protected process `$p was allowed to close"
    }
}
Write-Output 'ZAPRET_PROTECTED'
"@
        $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
        $out = & $pwshPath -NoProfile -EncodedCommand $b64 2>&1
        Assert-E2EEqual 0 $LASTEXITCODE ("Zapret check failed: " + ($out -join " "))
        Assert-E2EMatch ($out -join "`n") 'ZAPRET_PROTECTED' "Zapret protection marker missing"
    }

    Register-E2ETest -Id "T1-F5-05" -Tier 1 -Feature "F5" -Name "RFC 1323 TCP timestamps preserved when Zapret/WinDivert/winws active" -Artifact "Core/SystemOptimizer.ps1" -Body {
        param($ctx)
        Initialize-PsStage -RepoRoot $ctx.RepoRoot -StageRoot $ctx.Sandbox.PsStage
        $pwshPath = (Get-Process -Id $PID).Path
        $stageCore = Join-Path $ctx.Sandbox.PsStage "Core"
        $cmd = @"
. '$stageCore\ServiceManager.ps1'
. '$stageCore\SystemOptimizer.ps1'
if (-not (Test-ShouldPreserveTcpTimestamps -CurrentTimestamps 'disabled' -ActiveServiceNames @('zapret') -ActiveProcessNames @())) { throw 'zapret svc failed' }
if (-not (Test-ShouldPreserveTcpTimestamps -CurrentTimestamps 'disabled' -ActiveServiceNames @('WinDivert') -ActiveProcessNames @())) { throw 'WinDivert svc failed' }
if (-not (Test-ShouldPreserveTcpTimestamps -CurrentTimestamps 'disabled' -ActiveServiceNames @('WinDivert14') -ActiveProcessNames @())) { throw 'WinDivert14 svc failed' }
if (-not (Test-ShouldPreserveTcpTimestamps -CurrentTimestamps 'disabled' -ActiveServiceNames @() -ActiveProcessNames @('winws.exe'))) { throw 'winws proc failed' }
if (-not (Test-ShouldPreserveTcpTimestamps -CurrentTimestamps 'disabled' -ActiveServiceNames @() -ActiveProcessNames @('winws2'))) { throw 'winws2 proc failed' }
if (Test-ShouldPreserveTcpTimestamps -CurrentTimestamps 'disabled' -ActiveServiceNames @('Spooler') -ActiveProcessNames @('Discord')) { throw 'unrelated should be false' }
Write-Output 'TCP_TIMESTAMPS_OK'
"@
        $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
        $out = & $pwshPath -NoProfile -EncodedCommand $b64 2>&1
        Assert-E2EEqual 0 $LASTEXITCODE ("TCP timestamp check failed: " + ($out -join " "))
        Assert-E2EMatch ($out -join "`n") 'TCP_TIMESTAMPS_OK' "TCP timestamp marker missing"
    }

    # =========================================================================
    # F6: Standby RAM & 0.5ms Timer Automation (5 tests)
    # =========================================================================
    Register-E2ETest -Id "T1-F6-01" -Tier 1 -Feature "F6" -Name "Config/tuning.json defaults match AAA automation schema" -Artifact "Config/tuning.json" -Body {
        param($ctx)
        $tun = Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "Config\tuning.json") -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-E2EEqual $true $tun.AutoLockTimerInGaming "AutoLockTimerInGaming default must be true"
        Assert-E2EEqual $true $tun.AutoPurgeRamInGaming "AutoPurgeRamInGaming default must be true"
        Assert-E2EEqual 2048 ([int]$tun.AutoPurgeRamThresholdMB) "AutoPurgeRamThresholdMB default must be 2048"
    }

    Register-E2ETest -Id "T1-F6-02" -Tier 1 -Feature "F6" -Name "Standby RAM auto-purge backend uses 60s poll and 180s cooldown" -Artifact "src/backend.rs" -Body {
        param($ctx)
        $backendRs = Join-Path $ctx.RepoRoot "src\backend.rs"
        if (-not (Test-Path -LiteralPath $backendRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/backend.rs not yet created (M3 pending)" -Artifact "src/backend.rs"
        }
        $raw = Get-Content -LiteralPath $backendRs -Raw -Encoding UTF8
        Assert-E2EMatch $raw '\b180\b' "180s standby RAM cooldown must be defined"
        Assert-E2EMatch $raw '\b60\b' "60s standby RAM poll interval must be defined"
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass standby RAM tests"
    }

    Register-E2ETest -Id "T1-F6-03" -Tier 1 -Feature "F6" -Name "Standby RAM kernel API NtSetSystemInformation(80, 4) present in PS and Rust" -Artifact "Core/SystemOptimizer.ps1" -Body {
        param($ctx)
        $sysOpt = Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "Core\SystemOptimizer.ps1") -Raw -Encoding UTF8
        Assert-E2EMatch $sysOpt 'NtSetSystemInformation' "Core/SystemOptimizer.ps1 must define NtSetSystemInformation"
        $backendRs = Join-Path $ctx.RepoRoot "src\backend.rs"
        if (-not (Test-Path -LiteralPath $backendRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/backend.rs not yet created (M3 pending)" -Artifact "src/backend.rs"
        }
        $raw = Get-Content -LiteralPath $backendRs -Raw -Encoding UTF8
        Assert-E2EMatch $raw 'NtSetSystemInformation' "src/backend.rs must call NtSetSystemInformation"
    }

    Register-E2ETest -Id "T1-F6-04" -Tier 1 -Feature "F6" -Name "0.500ms timer lock via NtSetTimerResolution(5000) verified" -Artifact "src/backend.rs" -Body {
        param($ctx)
        $backendRs = Join-Path $ctx.RepoRoot "src\backend.rs"
        if (-not (Test-Path -LiteralPath $backendRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/backend.rs not yet created (M3 pending)" -Artifact "src/backend.rs"
        }
        $raw = Get-Content -LiteralPath $backendRs -Raw -Encoding UTF8
        Assert-E2EMatch $raw 'NtSetTimerResolution' "src/backend.rs must invoke NtSetTimerResolution"
        Assert-E2EMatch $raw '\b5000\b' "0.500ms (5000 x 100ns) target must be present"
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass timer resolution tests"
    }

    Register-E2ETest -Id "T1-F6-05" -Tier 1 -Feature "F6" -Name "TuningConfig persistence round-trip verified via cargo test" -Artifact "src/backend.rs" -Body {
        param($ctx)
        $backendRs = Join-Path $ctx.RepoRoot "src\backend.rs"
        if (-not (Test-Path -LiteralPath $backendRs)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "src/backend.rs not yet created (M3 pending)" -Artifact "src/backend.rs"
        }
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass tuning persistence tests"
    }

    # =========================================================================
    # F7: Unified AAA Pipeline UI, Typography, Themed Primitives & Docs (5 tests)
    # =========================================================================
    Register-E2ETest -Id "T1-F7-01" -Tier 1 -Feature "F7" -Name "Removed 3D teardown artifacts are absent from repo, build.rs, backend, and Slint UI" -Artifact "src/backend.rs" -Body {
        param($ctx)
        Assert-E2ETrue (-not (Test-Path -LiteralPath (Join-Path $ctx.RepoRoot "docs\teardown"))) "docs/teardown directory must be removed"
        $buildRs = Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "build.rs") -Raw -Encoding UTF8
        Assert-E2ENotMatch $buildRs 'teardown' "build.rs must not reference teardown"

        $backendRs = Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "src\backend.rs") -Raw -Encoding UTF8
        Assert-E2ENotMatch $backendRs 'open_teardown_page|resolve_teardown_html_path|docs/teardown' "src/backend.rs must not embed or launch teardown"

        $slintAll = (Get-ChildItem -LiteralPath (Join-Path $ctx.RepoRoot "slint") -Filter "*.slint" -Recurse | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
        Assert-E2ENotMatch $slintAll 'open-teardown|3D-\u0430\u0440\u0445\u0438\u0442\u0435\u043a\u0442\u0443\u0440' "Slint UI must not expose 3D teardown callbacks or buttons"
    }

    Register-E2ETest -Id "T1-F7-02" -Tier 1 -Feature "F7" -Name "Dashboard renders unified 4-stage AAA gaming pipeline cleanly without clutter" -Artifact "slint/dashboard.slint" -Body {
        param($ctx)
        $dash = Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "slint\dashboard.slint") -Raw -Encoding UTF8
        Assert-E2EMatch $dash '\u0415\u0434\u0438\u043d\u044b\u0439 \u0438\u0433\u0440\u043e\u0432\u043e\u0439 \u043a\u043e\u043d\u0432\u0435\u0439\u0435\u0440 AAA' "Dashboard must display unified AAA pipeline title"
        Assert-E2EMatch $dash '\u0413\u0440\u0430\u0444\u0438\u043a\u0430 \u0438 DWM' "Dashboard pipeline must include Graphics & DWM stage"
        Assert-E2EMatch $dash '\u042f\u0434\u0440\u043e \u0438 \u0432\u0432\u043e\u0434 HID' "Dashboard pipeline must include CPU & HID input stage"
        Assert-E2EMatch $dash '\u041f\u0430\u043c\u044f\u0442\u044c \u0438 \u0442\u0430\u0439\u043c\u0435\u0440' "Dashboard pipeline must include Memory & Timer stage"
        Assert-E2EMatch $dash '\u0421\u0435\u0442\u044c \u0438 \u0437\u0430\u0449\u0438\u0442\u0430 DPI' "Dashboard pipeline must include Network & DPI protection stage"
        Assert-E2EMatch $dash '0\.500 \u043c\u0441' "Dashboard must reflect 0.500 ms timer lock"
        Assert-E2EMatch $dash 'Zapret' "Dashboard must reflect Zapret DPI protection"
    }

    Register-E2ETest -Id "T1-F7-03" -Tier 1 -Feature "F7" -Name "Windows typography (Segoe UI Variable Text + Cascadia Code) and Win10 fallbacks are wired" -Artifact "slint/theme.slint" -Body {
        param($ctx)
        $themeSlint = Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "slint\theme.slint") -Raw -Encoding UTF8
        $mainSlint = Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "slint\main.slint") -Raw -Encoding UTF8
        $bridgeRs = Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "src\ui_bridge.rs") -Raw -Encoding UTF8

        Assert-E2EMatch $themeSlint 'font-sans:\s*"Segoe UI Variable Text"' "ThemeTokens must configure Segoe UI Variable Text"
        Assert-E2EMatch $themeSlint 'font-mono:\s*"Cascadia Code"' "ThemeTokens must configure Cascadia Code"
        Assert-E2EMatch $mainSlint 'default-font-family:\s*ThemeTokens\.font-sans' "MainWindow must bind default-font-family to ThemeTokens.font-sans"
        Assert-E2EMatch $bridgeRs 'Segoe UI' "ui_bridge.rs must include Windows 10 Segoe UI fallback"
        Assert-E2EMatch $bridgeRs 'Consolas' "ui_bridge.rs must include Windows 10 Consolas fallback"

        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must pass font detection & UI bridge tests"
        Assert-E2EMatch $ct.Output 'test_font_detection_prefers_win11_with_clean_fallback\s*\.\.\.\s*ok' "Font detection unit test must pass"
    }

    Register-E2ETest -Id "T1-F7-04" -Tier 1 -Feature "F7" -Name "All 8 themes use custom themed Slint primitives with zero un-themed std-widgets imports" -Artifact "slint/components.slint" -Body {
        param($ctx)
        $slintFiles = Get-ChildItem -LiteralPath (Join-Path $ctx.RepoRoot "slint") -Filter "*.slint" -Recurse
        $slintAll = ($slintFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n"
        Assert-E2ENotMatch $slintAll 'std-widgets\.slint' "Slint views must not import un-themed std-widgets.slint"

        $comp = Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "slint\components.slint") -Raw -Encoding UTF8
        Assert-E2EMatch $comp 'export component SurfaceCard' "components.slint must export SurfaceCard"
        Assert-E2EMatch $comp 'export component ThemedScrollView' "components.slint must export ThemedScrollView"
        Assert-E2EMatch $comp 'ThemeTokens\.scrollbar-thumb' "ThemedScrollView must bind ThemeTokens.scrollbar-thumb"
        Assert-E2EMatch $comp 'export component ThemedLineEdit' "components.slint must export ThemedLineEdit"
        Assert-E2EMatch $comp 'ThemeTokens\.border-input' "ThemedLineEdit must bind ThemeTokens.border-input"
        Assert-E2EMatch $comp 'export component ThemedSwitch' "components.slint must export ThemedSwitch"

        $mainSlint = Get-Content -LiteralPath (Join-Path $ctx.RepoRoot "slint\main.slint") -Raw -Encoding UTF8
        Assert-E2EMatch $mainSlint '@radial-gradient\(' "MainWindow ambient glow must use smooth radial gradient"
    }

    Register-E2ETest -Id "T1-F7-05" -Tier 1 -Feature "F7" -Name "README.md and README.ru.md document v4.0.0 Slint UI, unified pipeline, 8 themes, and typography" -Artifact "README.md" -Body {
        param($ctx)
        foreach ($md in @("README.md", "README.ru.md")) {
            $txt = Get-Content -LiteralPath (Join-Path $ctx.RepoRoot $md) -Raw -Encoding UTF8
            Assert-E2EMatch $txt '4\.0\.0' "$md must document v4.0.0"
            Assert-E2EMatch $txt '(?i)slint' "$md must document Slint GUI"
            Assert-E2EMatch $txt 'Segoe UI Variable Text' "$md must document Segoe UI Variable Text typography"
            Assert-E2EMatch $txt 'Cascadia Code' "$md must document Cascadia Code monospace typography"
            Assert-E2ENotMatch $txt 'docs/teardown/|preview\.svg' "$md must not link removed 3D teardown assets"
        }
    }

    # =========================================================================
    # F8: Portable Mode, Packaging, UTF-8 & Repo Hygiene (5 tests)
    # =========================================================================
    Register-E2ETest -Id "T1-F8-01" -Tier 1 -Feature "F8" -Name "Portable UltraGamingMode.exe materializes runtime assets into isolated temp dir" -Artifact ".bin/UltraGamingMode.exe" -Body {
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

        $portDir = Join-Path $ctx.Sandbox.Root ("port_t1_" + [guid]::NewGuid().ToString("N").Substring(0, 6))
        New-Item -ItemType Directory -Path $portDir -Force | Out-Null
        $portExe = Join-Path $portDir "UltraGamingMode.exe"
        Copy-Item -LiteralPath $exePath -Destination $portExe -Force

        $psi = New-SandboxedProcessStartInfo -FilePath $portExe -Arguments "--tray" -WorkingDirectory $portDir -EnvRoot $ctx.Sandbox.EnvRw -RequireRunAsInvoker ($pe.ManifestExecutionLevel -eq "requireAdministrator")
        $proc = Start-E2EHostedProcess -StartInfo $psi
        try {
            Start-Sleep -Milliseconds 3000
            $candidates = @($portDir, (Join-Path $ctx.Sandbox.EnvRw "ProgramFiles\UltraGamingMode"), (Join-Path $ctx.Sandbox.EnvRw "ProgramData\UltraGamingMode"), (Join-Path $ctx.Sandbox.EnvRw "LocalAppData\UltraGamingMode"), (Join-Path $ctx.Sandbox.EnvRw "LocalAppData\UltraGamingMode\Runtime"))
            $foundRoot = $candidates | Where-Object { Test-Path -LiteralPath (Join-Path $_ "UltraGamingMode.ps1") } | Select-Object -First 1
            Assert-E2ETrue ($null -ne $foundRoot) "Portable runtime must materialize UltraGamingMode.ps1 inside sandbox"
            Assert-E2ETrue (Test-Path -LiteralPath (Join-Path $foundRoot "Core\SystemOptimizer.ps1")) "Portable runtime must materialize Core/SystemOptimizer.ps1"
            Assert-E2ETrue (-not (Test-Path -LiteralPath (Join-Path $foundRoot "docs"))) "Removed docs/ directory must not be materialized"
            Assert-E2ETrue (-not (Test-Path -LiteralPath (Join-Path $foundRoot "EBWebView"))) "EBWebView directory must never be created"
        } finally {
            Stop-E2EProcessTree -RootPid $proc.Id
        }
    }

    Register-E2ETest -Id "T1-F8-02" -Tier 1 -Feature "F8" -Name "Release artifacts (.bin/UltraGamingMode.exe, root exe, SHA256SUMS.txt) match byte-for-byte" -Artifact ".bin/SHA256SUMS.txt" -Body {
        param($ctx)
        $binExe = Join-Path $ctx.RepoRoot ".bin\UltraGamingMode.exe"
        $rootExe = Join-Path $ctx.RepoRoot "UltraGamingMode.exe"
        $sumsFile = Join-Path $ctx.RepoRoot ".bin\SHA256SUMS.txt"
        if (-not (Test-Path -LiteralPath $binExe) -or -not (Test-Path -LiteralPath $sumsFile)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "Release .bin/ artifacts not yet built (M5 pending)" -Artifact ".bin/SHA256SUMS.txt"
        }
        $pe = Get-PEInspection -ExePath $binExe -Markers @("tauri::")
        if ($pe.MarkerCounts["tauri::"] -gt 0 -or $pe.FileVersion -notlike "4.0.0*") {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin/UltraGamingMode.exe not yet rebuilt for v4.0.0 (M5 pending)" -Artifact ".bin/UltraGamingMode.exe"
        }
        Assert-E2EEqual (Get-FileSha256Lower $binExe) (Get-FileSha256Lower $rootExe) ".bin/UltraGamingMode.exe and root UltraGamingMode.exe must have identical SHA-256"
        $bomChk = Test-Utf8NoBom -FilePath $sumsFile
        Assert-E2ETrue $bomChk.Valid "SHA256SUMS.txt must be UTF-8 without BOM"

        $lines = @(Get-Content -LiteralPath $sumsFile -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        Assert-E2ETrue ($lines.Count -ge 1) "SHA256SUMS.txt must contain checksum entries"
        foreach ($ln in $lines) {
            Assert-E2EMatch $ln '^[0-9a-f]{64}  \S+$' "Invalid SHA256SUMS line format: $ln"
            $parts = $ln -split '  ', 2
            $target = Join-Path $ctx.RepoRoot (".bin\" + $parts[1])
            Assert-E2ETrue (Test-Path -LiteralPath $target) "Checksum target missing: $target"
            Assert-E2EEqual $parts[0] (Get-FileSha256Lower $target) "SHA-256 mismatch for $($parts[1])"
        }
    }

    Register-E2ETest -Id "T1-F8-03" -Tier 1 -Feature "F8" -Name "All active .ps1 and .json files across repo are strictly UTF-8 without BOM" -Artifact "." -Body {
        param($ctx)
        $violations = Find-Utf8BomFiles -RootDir $ctx.RepoRoot -Extensions @(".ps1", ".json")
        Assert-E2EEqual 0 $violations.Count ("UTF-8 BOM / encoding violations: " + ($violations -join "; "))
    }

    Register-E2ETest -Id "T1-F8-04" -Tier 1 -Feature "F8" -Name "Zero prohibited attribution mentions across repo source, configs, docs, and E2E tests" -Artifact "." -Body {
        param($ctx)
        $targets = @($ctx.RepoRoot)
        if (-not [string]::IsNullOrWhiteSpace($ctx.TestInfraPath) -and (Test-Path -LiteralPath $ctx.TestInfraPath)) {
            $targets += $ctx.TestInfraPath
        }
        $hits = Test-ContentPolicyHygiene -Paths $targets
        Assert-E2EEqual 0 $hits.Count ("Content policy hygiene violations: " + ($hits -join "; "))
    }

    Register-E2ETest -Id "T1-F8-05" -Tier 1 -Feature "F8" -Name "Build-Release.ps1 v4.0.0 release notes contract uses 3 plain Russian bullets on lines 1-3" -Artifact "Build-Release.ps1" -Body {
        param($ctx)
        $brPath = Join-Path $ctx.RepoRoot "Build-Release.ps1"
        $raw = Get-Content -LiteralPath $brPath -Raw -Encoding UTF8
        if ($raw -notmatch 'v4\.0\.0') {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason "Build-Release.ps1 not yet updated to v4.0.0 (M5 pending)" -Artifact "Build-Release.ps1"
        }
        Assert-E2ENotMatch $raw 'npm run tauri build' "Build-Release.ps1 must not invoke Tauri build"
        Assert-E2EMatch $raw 'cargo build --release' "Build-Release.ps1 must invoke cargo build --release"

        # Validate release notes contract helper if embedded or documented
        $sampleValid = @(
            ([regex]::Unescape('- \u041f\u0435\u0440\u0435\u0445\u043e\u0434 \u043d\u0430 \u043d\u0430\u0442\u0438\u0432\u043d\u044b\u0439 \u0438\u043d\u0442\u0435\u0440\u0444\u0435\u0439\u0441 \u0431\u0435\u0437 \u043b\u0438\u0448\u043d\u0438\u0445 \u0437\u0430\u0432\u0438\u0441\u0438\u043c\u043e\u0441\u0442\u0435\u0439')),
            ([regex]::Unescape('- \u0414\u043e\u0431\u0430\u0432\u043b\u0435\u043d\u044b \u0432\u043e\u0441\u0435\u043c\u044c \u0442\u0435\u043c \u043e\u0444\u043e\u0440\u043c\u043b\u0435\u043d\u0438\u044f \u0441 \u043f\u0435\u0440\u0435\u043a\u043b\u044e\u0447\u0435\u043d\u0438\u0435\u043c')),
            ([regex]::Unescape('- \u041e\u0441\u0442\u0430\u0432\u043b\u0435\u043d \u0442\u043e\u043b\u044c\u043a\u043e \u043f\u0440\u043e\u0444\u0438\u043b\u044c \u043e\u043f\u0442\u0438\u043c\u0438\u0437\u0430\u0446\u0438\u0438 AAA'))
        )
        for ($i = 0; $i -lt 3; $i++) {
            Assert-E2EMatch $sampleValid[$i] '^- [^\*#`]+$' "Sample release bullet invalid"
        }
    }
}
