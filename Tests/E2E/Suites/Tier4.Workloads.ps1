# Tier4.Workloads.ps1 — 6 Realistic Multi-Step End-User Application Workloads

Set-StrictMode -Version Latest

function Register-Tier4Tests {
    Register-E2ETest -Id "T4-01" -Tier 4 -Feature "F8" -Name "Fresh portable USB deployment runs cleanly with zero WebView2 and valid materialized assets" -Artifact ".bin/UltraGamingMode.exe" -Body {
        param($ctx)
        $exePath = Join-Path $ctx.RepoRoot ".bin\UltraGamingMode.exe"
        if (-not (Test-Path -LiteralPath $exePath)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin/UltraGamingMode.exe missing (M5 pending)" -Artifact ".bin/UltraGamingMode.exe"
        }
        $pe = Get-PEInspection -ExePath $exePath -Markers @("tauri::", "CreateCoreWebView2", "slint")
        if ($pe.MarkerCounts["tauri::"] -gt 0 -or $pe.FileVersion -notlike "4.0.1*") {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin/UltraGamingMode.exe is still pre-v4.0.0 build (M5 pending)" -Artifact ".bin/UltraGamingMode.exe"
        }

        $usbDir = Join-Path $ctx.Sandbox.Root ("usb_deploy_" + [guid]::NewGuid().ToString("N").Substring(0, 6))
        New-Item -ItemType Directory -Path $usbDir -Force | Out-Null
        $usbExe = Join-Path $usbDir "UltraGamingMode.exe"
        Copy-Item -LiteralPath $exePath -Destination $usbExe -Force

        $needInvoker = ($pe.ManifestExecutionLevel -eq "requireAdministrator")
        $psi1 = New-SandboxedProcessStartInfo -FilePath $usbExe -Arguments "--tray" -WorkingDirectory $usbDir -EnvRoot $ctx.Sandbox.EnvRw -RequireRunAsInvoker $needInvoker
        $p1 = Start-E2EHostedProcess -StartInfo $psi1
        $p2 = $null
        try {
            Start-Sleep -Milliseconds 3000
            $p1.Refresh()
            Assert-E2EEqual $false $p1.HasExited "Portable app must stay resident"
            $wv = @(Get-CimInstance Win32_Process -Filter "Name = 'msedgewebview2.exe' AND ParentProcessId = $($p1.Id)" -ErrorAction SilentlyContinue)
            Assert-E2EEqual 0 $wv.Count "Zero msedgewebview2.exe processes allowed"

            # Verify single-instance guard on second launch
            $psi2 = New-SandboxedProcessStartInfo -FilePath $usbExe -Arguments "--tray" -WorkingDirectory $usbDir -EnvRoot $ctx.Sandbox.EnvRw -RequireRunAsInvoker $needInvoker
            $p2 = Start-E2EHostedProcess -StartInfo $psi2
            Assert-E2ETrue ($p2.WaitForExit(5000)) "Second launch must exit via single-instance guard"

            # Locate materialized runtime root inside sandbox
            $candidates = @($usbDir, (Join-Path $ctx.Sandbox.EnvRw "ProgramFiles\UltraGamingMode"), (Join-Path $ctx.Sandbox.EnvRw "ProgramData\UltraGamingMode"), (Join-Path $ctx.Sandbox.EnvRw "LocalAppData\UltraGamingMode"), (Join-Path $ctx.Sandbox.EnvRw "LocalAppData\UltraGamingMode\Runtime"))
            $rtRoot = $candidates | Where-Object { Test-Path -LiteralPath (Join-Path $_ "UltraGamingMode.ps1") } | Select-Object -First 1
            Assert-E2ETrue ($null -ne $rtRoot) "Runtime assets must materialize in sandbox"
            Assert-E2ETrue (Test-Path -LiteralPath (Join-Path $rtRoot "Core\SystemOptimizer.ps1")) "Core/SystemOptimizer.ps1 must materialize"
            Assert-E2ETrue (-not (Test-Path -LiteralPath (Join-Path $rtRoot "docs"))) "Removed docs/ directory must not materialize"

            $boms = Find-Utf8BomFiles -RootDir $rtRoot -Extensions @(".ps1", ".json")
            Assert-E2EEqual 0 $boms.Count "Materialized .ps1/.json must be UTF-8 without BOM"
            $sd = (Get-Content -LiteralPath (Join-Path $rtRoot "Config\service_descriptions.json") -Raw -Encoding UTF8 | ConvertFrom-Json).Descriptions
            Assert-E2EEqual 328 @($sd.PSObject.Properties).Count "Materialized service descriptions must be 328"
        } finally {
            if ($null -ne $p2 -and -not $p2.HasExited) { Stop-E2EProcessTree -RootPid $p2.Id }
            Stop-E2EProcessTree -RootPid $p1.Id
        }
    }

    Register-E2ETest -Id "T4-02" -Tier 4 -Feature "F3xF8" -Name "Read-only folder fallback and pre-existing user Config/ui_settings.json preservation" -Artifact ".bin/UltraGamingMode.exe" -Body {
        param($ctx)
        $exePath = Join-Path $ctx.RepoRoot ".bin\UltraGamingMode.exe"
        if (-not (Test-Path -LiteralPath $exePath)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin/UltraGamingMode.exe missing (M5 pending)" -Artifact ".bin/UltraGamingMode.exe"
        }
        $pe = Get-PEInspection -ExePath $exePath -Markers @("tauri::")
        if ($pe.MarkerCounts["tauri::"] -gt 0 -or $pe.FileVersion -notlike "4.0.1*") {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin/UltraGamingMode.exe is still pre-v4.0.0 build (M5 pending)" -Artifact ".bin/UltraGamingMode.exe"
        }

        $roExe = Join-Path $ctx.Sandbox.PortableRo "UltraGamingMode.exe"
        Copy-Item -LiteralPath $exePath -Destination $roExe -Force
        $ladCfg = Join-Path $ctx.Sandbox.EnvRo "LocalAppData\UltraGamingMode"
        New-Item -ItemType Directory -Path $ladCfg -Force | Out-Null
        $preUi = '{"theme":"midnight-violet","ugm-last-dark-theme":"midnight-violet","ugm-last-light-theme":"daylight-warm"}'
        [System.IO.File]::WriteAllText((Join-Path $ladCfg "ui_settings.json"), $preUi, [System.Text.UTF8Encoding]::new($false))

        Set-DirectoryWriteDenyAcl -DirectoryPath $ctx.Sandbox.PortableRo
        Set-DirectoryWriteDenyAcl -DirectoryPath (Join-Path $ctx.Sandbox.EnvRo "ProgramFiles")
        Set-DirectoryWriteDenyAcl -DirectoryPath (Join-Path $ctx.Sandbox.EnvRo "ProgramData")

        $psi = New-SandboxedProcessStartInfo -FilePath $roExe -Arguments "--tray" -WorkingDirectory $ctx.Sandbox.PortableRo -EnvRoot $ctx.Sandbox.EnvRo -RequireRunAsInvoker ($pe.ManifestExecutionLevel -eq "requireAdministrator")
        $proc = Start-E2EHostedProcess -StartInfo $psi
        try {
            Start-Sleep -Milliseconds 3000
            $afterUi = Get-Content -LiteralPath (Join-Path $ladCfg "ui_settings.json") -Raw -Encoding UTF8 | ConvertFrom-Json
            Assert-E2EEqual "midnight-violet" $afterUi.theme "Fallback ui_settings.json must preserve midnight-violet"
            Assert-E2EEqual "daylight-warm" $afterUi.'ugm-last-light-theme' "Fallback ui_settings.json must preserve daylight-warm"
        } finally {
            Stop-E2EProcessTree -RootPid $proc.Id
            Remove-DirectoryWriteDenyAcl -DirectoryPath $ctx.Sandbox.PortableRo
            Remove-DirectoryWriteDenyAcl -DirectoryPath (Join-Path $ctx.Sandbox.EnvRo "ProgramFiles")
            Remove-DirectoryWriteDenyAcl -DirectoryPath (Join-Path $ctx.Sandbox.EnvRo "ProgramData")
        }
    }

    Register-E2ETest -Id "T4-03" -Tier 4 -Feature "F5" -Name "Zapret user AAA workflow protects bypass services/processes, TCP timestamps, and virtual NICs" -Artifact "Core/" -Body {
        param($ctx)
        Initialize-PsStage -RepoRoot $ctx.RepoRoot -StageRoot $ctx.Sandbox.PsStage
        $pwshPath = (Get-Process -Id $PID).Path
        $stageCore = Join-Path $ctx.Sandbox.PsStage "Core"
        $stageCfg  = Join-Path $ctx.Sandbox.PsStage "Config"
        $cmd = @"
. '$stageCore\ServiceManager.ps1'
. '$stageCore\SystemOptimizer.ps1'
. '$stageCore\StateEngine.ps1'
`$wl = (Get-Content -LiteralPath '$stageCfg\services_whitelist.json' -Raw -Encoding UTF8 | ConvertFrom-Json).ProtectedServices
`$bl = (Get-Content -LiteralPath '$stageCfg\services_blacklist.json' -Raw -Encoding UTF8 | ConvertFrom-Json).TargetServices | ForEach-Object { `$_.Name }
`$sa = Get-Content -LiteralPath '$stageCfg\startup_apps.json' -Raw -Encoding UTF8 | ConvertFrom-Json

foreach (`$svc in @('zapret','WinDivert','WinDivert14','RpcSs','Audiosrv','MMCSS')) {
    if (Test-ServiceShouldDisableInGaming -ServiceName `$svc -Blacklist `$bl -Whitelist `$wl) { throw "Protected service `$svc disabled" }
}
foreach (`$procName in @('winws.exe','winws2','zapret','FACEITClient.exe')) {
    if (Test-ProcessShouldCloseInGaming -ProcessName `$procName -BlacklistProcesses `$sa.BlacklistProcesses -ProtectedStartupNames `$sa.ProtectedStartupNames) { throw "Protected process `$procName closed" }
}
if (-not (Test-ShouldPreserveTcpTimestamps -CurrentTimestamps 'disabled' -ActiveServiceNames @('WinDivert14') -ActiveProcessNames @('winws.exe'))) {
    throw 'TCP timestamps not preserved'
}
`$adapters = @(Get-PhysicalGamingAdapters | ForEach-Object { `$_.Name })
if (`$adapters -contains 'Ethernet 2' -or `$adapters -contains 'wwan99') {
    throw 'Virtual/tethering adapter leaked into gaming NICs'
}
Write-Output 'WORKLOAD_ZAPRET_OK'
"@
        $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
        $out = & $pwshPath -NoProfile -EncodedCommand $b64 2>&1
        Assert-E2EEqual 0 $LASTEXITCODE ("Zapret workload failed: " + ($out -join " "))
        Assert-E2EMatch ($out -join "`n") 'WORKLOAD_ZAPRET_OK' "Workload marker missing"
    }

    Register-E2ETest -Id "T4-04" -Tier 4 -Feature "F4xF5" -Name "Multi-phase snapshot -> two-phase shortcut & registry restore -> clean state in sandbox" -Artifact "Core/StateEngine.ps1" -Body {
        param($ctx)
        Initialize-PsStage -RepoRoot $ctx.RepoRoot -StageRoot $ctx.Sandbox.PsStage
        $pwshPath = (Get-Process -Id $PID).Path
        $stageCore = Join-Path $ctx.Sandbox.PsStage "Core"
        $workDir = Join-Path $ctx.Sandbox.Root "workload_restore"
        $regKey = "HKCU:\Software\UGM_E2E_Test_" + [guid]::NewGuid().ToString("N")
        try {
            $cmd = @"
. '$stageCore\ServiceManager.ps1'
. '$stageCore\SystemOptimizer.ps1'
. '$stageCore\StateEngine.ps1'

New-Item -ItemType Directory -Path '$workDir\Q\User', '$workDir\Q\ProgramData', '$workDir\DstUser', '$workDir\DstCommon' -Force | Out-Null
Set-Content -LiteralPath '$workDir\Q\User\Game [Modded] (v2.0).lnk' -Value 'user-lnk'
Set-Content -LiteralPath '$workDir\Q\ProgramData\Launcher.lnk' -Value 'sys-lnk'
Set-Content -LiteralPath '$workDir\Q\Legacy.lnk.ugm_backup' -Value 'legacy-lnk'
`$mockState = [PSCustomObject]@{ StartupShortcuts = @([PSCustomObject]@{ Name='Legacy.lnk'; OriginalFolder='$workDir\DstUser'; FolderTag='User' }) }

`$stateFile = '$workDir\active_state.json'
[IO.File]::WriteAllText(`$stateFile, '{"State":"Armed","BootRunCount":0,"SystemRestored":false,"UserRestored":false}', [Text.UTF8Encoding]::new(`$false))
`$st = Get-ActiveStateSafe -Path `$stateFile

Restore-QuarantinedShortcuts -QuarantineDir '$workDir\Q' -UserStartup '$workDir\DstUser' -CommonStartup '$workDir\DstCommon' -StateData `$mockState -Scope 'System'
if (-not (Test-Path -LiteralPath '$workDir\DstCommon\Launcher.lnk')) { throw 'System restore failed' }
Set-StatePropertySafe -StateObject `$st -Name 'State' -Value 'Restoring_SystemDone'
Set-StatePropertySafe -StateObject `$st -Name 'SystemRestored' -Value `$true
`$null = Set-ActiveStateSafe -Path `$stateFile -Data `$st

`$st2 = Get-ActiveStateSafe -Path `$stateFile
Restore-QuarantinedShortcuts -QuarantineDir '$workDir\Q' -UserStartup '$workDir\DstUser' -CommonStartup '$workDir\DstCommon' -StateData `$mockState -Scope 'User'
if (-not (Test-Path -LiteralPath '$workDir\DstUser\Game [Modded] (v2.0).lnk') -or -not (Test-Path -LiteralPath '$workDir\DstUser\Legacy.lnk')) {
    throw 'User restore failed'
}
`$st2.UserRestored = `$true
`$st2.State = 'Restored'
`$null = Set-ActiveStateSafe -Path `$stateFile -Data `$st2
`$bytes = [IO.File]::ReadAllBytes(`$stateFile)
if (`$bytes.Length -ge 3 -and `$bytes[0] -eq 0xEF -and `$bytes[1] -eq 0xBB -and `$bytes[2] -eq 0xBF) { throw 'State JSON wrote BOM' }

# Ephemeral HKCU registry round-trip
New-Item -Path '$regKey\Sub' -Force | Out-Null
Set-ItemProperty -Path '$regKey\Sub' -Name 'BinVal' -Value ([byte[]](0x30, 0x00)) -Type Binary
Set-ItemProperty -Path '$regKey' -Name 'MultiVal' -Value ([string[]]@('a', 'b')) -Type MultiString
`$targets = @(
    @{ Path = '$regKey\Sub'; Name = 'BinVal'; Value = ([byte[]](0x32, 0x00)); Kind = 'Binary' },
    @{ Path = '$regKey'; Name = 'MultiVal'; Value = ([string[]]@('c')); Kind = 'MultiString' },
    @{ Path = '$regKey'; Name = 'NewDw'; Value = 42; Kind = 'DWord' }
)
`$snap = Get-RegistryValueSnapshot -Targets `$targets
`$snapJson = (@{ ExtendedRegistryConfig = `$snap } | ConvertTo-Json -Depth 10 | ConvertFrom-Json).ExtendedRegistryConfig
`$null = Set-RegistryTargets -Targets `$targets
`$null = Restore-RegistryValueSnapshot -Snapshot `$snapJson -Hive 'HKCU'
`$subPath = '$regKey' -replace '^HKCU:\\', ''
`$k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(`$subPath)
if (`$k.GetValueNames() -contains 'NewDw') { `$k.Close(); throw 'NewDw not removed on restore' }
if ((`$k.GetValue('MultiVal') -join ',') -ne 'a,b') { `$k.Close(); throw 'MultiVal not restored' }
`$k.Close()
Write-Output 'WORKLOAD_RESTORE_OK'
"@
            $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
            $out = & $pwshPath -NoProfile -EncodedCommand $b64 2>&1
            Assert-E2EEqual 0 $LASTEXITCODE ("Restore workload failed: " + ($out -join " "))
            Assert-E2EMatch ($out -join "`n") 'WORKLOAD_RESTORE_OK' "Workload marker missing"
        } finally {
            Remove-Item -LiteralPath $regKey -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Register-E2ETest -Id "T4-05" -Tier 4 -Feature "F7" -Name "Offscreen Slint render walkthrough dumps distinct frames across all 8 themes, 5 tabs, and 860x600 viewport" -Artifact "src/ui_bridge.rs" -Body {
        param($ctx)
        $dumpDir = Join-Path $ctx.Sandbox.Root ("ui_render_" + [guid]::NewGuid().ToString("N").Substring(0, 6))
        New-Item -ItemType Directory -Path $dumpDir -Force | Out-Null

        $cargoExe = (Get-Command cargo.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source
        if ([string]::IsNullOrWhiteSpace($cargoExe)) {
            $fallback = Join-Path $env:USERPROFILE ".cargo\bin\cargo.exe"
            if (Test-Path -LiteralPath $fallback) { $cargoExe = $fallback }
        }
        Assert-E2ETrue (-not [string]::IsNullOrWhiteSpace($cargoExe)) "cargo.exe must be available"

        $prevDump = $env:UGM_DUMP_SCREENSHOTS
        Push-Location $ctx.RepoRoot
        try {
            $env:UGM_DUMP_SCREENSHOTS = $dumpDir
            $out = & $cargoExe test --color never ui_bridge::tests::test_render_all_8_themes_and_views_offscreen -- --exact 2>&1
            Assert-E2EEqual 0 $LASTEXITCODE ("Offscreen render walkthrough failed: " + ($out -join "`n"))
            Assert-E2EMatch ($out -join "`n") 'test result: ok\. 1 passed' "Offscreen render test must actually execute 1 test"
        } finally {
            if ($null -eq $prevDump) {
                Remove-Item Env:UGM_DUMP_SCREENSHOTS -ErrorAction SilentlyContinue
            } else {
                $env:UGM_DUMP_SCREENSHOTS = $prevDump
            }
            Pop-Location
        }

        $bmps = @(Get-ChildItem -LiteralPath $dumpDir -Filter "*.bmp")
        Assert-E2EEqual 25 $bmps.Count "Expected 25 rendered BMP frames (8 dash + 8 settings + 9 tab/viewport checks)"
        foreach ($f in $bmps) {
            Assert-E2ETrue ($f.Length -gt 1000000) "Rendered BMP $($f.Name) looks truncated ($($f.Length) bytes)"
        }

        $themeHashes = @{}
        foreach ($tid in @("dark", "oled-obsidian", "emerald-ops", "graphite-amber", "midnight-violet", "light", "daylight-warm", "frost-slate")) {
            $p = Join-Path $dumpDir ("dash_{0}.bmp" -f $tid)
            Assert-E2ETrue (Test-Path -LiteralPath $p) "Missing rendered dashboard frame for theme $tid"
            $h = Get-FileSha256Lower $p
            Assert-E2ETrue (-not $themeHashes.ContainsKey($h)) "Theme '$tid' rendered identical frame to '$($themeHashes[$h])'"
            $themeHashes[$h] = $tid
        }
        $hTab0 = Get-FileSha256Lower (Join-Path $dumpDir "tab0_dark_960.bmp")
        $hTab3 = Get-FileSha256Lower (Join-Path $dumpDir "tab3_dark_960.bmp")
        Assert-E2ETrue ($hTab0 -ne $hTab3) "Dashboard and Settings tabs must render distinct frames"
    }

    Register-E2ETest -Id "T4-06" -Tier 4 -Feature "F8" -Name "Full release verification: Verify-UniversalEngine, cargo test, checksums, BOM, and hygiene" -Artifact ".bin/SHA256SUMS.txt" -Body {
        param($ctx)
        # 1. PowerShell engine suite
        $vue = Join-Path $ctx.RepoRoot "Tests\Verify-UniversalEngine.ps1"
        $pwshPath = (Get-Process -Id $PID).Path
        $psOut = & $pwshPath -NoProfile -ExecutionPolicy Bypass -File $vue 2>&1
        Assert-E2EEqual 0 $LASTEXITCODE ("Verify-UniversalEngine failed: " + ($psOut -join "`n"))

        # 2. Check BOM & hygiene across repo
        $boms = Find-Utf8BomFiles -RootDir $ctx.RepoRoot -Extensions @(".ps1", ".json")
        Assert-E2EEqual 0 $boms.Count "Repo must have 0 BOMs"
        $hyg = Test-ContentPolicyHygiene -Paths @($ctx.RepoRoot)
        Assert-E2EEqual 0 $hyg.Count ("Repo hygiene violations: " + ($hyg -join "; "))

        # 3. Rust + Release artifacts gate (defers in Phase A if M3/M5 unbuilt, fails in Phase B)
        $ct = Invoke-CachedCargoTest -Context $ctx
        Assert-E2EEqual 0 $ct.ExitCode "cargo test must exit 0"

        $sumsFile = Join-Path $ctx.RepoRoot ".bin\SHA256SUMS.txt"
        $binExe = Join-Path $ctx.RepoRoot ".bin\UltraGamingMode.exe"
        if (-not (Test-Path -LiteralPath $sumsFile) -or -not (Test-Path -LiteralPath $binExe)) {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin release artifacts pending (M5)" -Artifact ".bin/SHA256SUMS.txt"
        }
        $pe = Get-PEInspection -ExePath $binExe -Markers @("tauri::")
        if ($pe.MarkerCounts["tauri::"] -gt 0 -or $pe.FileVersion -notlike "4.0.1*") {
            Invoke-E2EDeferIfPhaseA -ValidateSuiteOnly $ctx.ValidateSuiteOnly -Reason ".bin/UltraGamingMode.exe still legacy pre-v4.0.0 (M5 pending)" -Artifact ".bin/UltraGamingMode.exe"
        }
        $rootExe = Join-Path $ctx.RepoRoot "UltraGamingMode.exe"
        Assert-E2EEqual (Get-FileSha256Lower $binExe) (Get-FileSha256Lower $rootExe) "Root and .bin exe hashes must match"
    }
}
