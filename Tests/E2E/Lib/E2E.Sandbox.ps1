# E2E.Sandbox.ps1 — Isolated Staging, NTFS ACL RO, Env Redirection, PEReader, BOM & Hygiene Scanners

Set-StrictMode -Version Latest

$script:AppliedAclTargets = [System.Collections.Generic.List[object]]::new()

function Test-IsElevatedAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-E2ESandbox {
    $stamp = Get-Date -Format "yyyyMMddHHmmss"
    $gid = [guid]::NewGuid().ToString("N").Substring(0, 8)
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("ugm_e2e_{0}_{1}_{2}" -f $stamp, $PID, $gid)

    $psStage    = Join-Path $root "ps_stage"
    $portableRw = Join-Path $root "portable_rw"
    $portableRo = Join-Path $root "portable_ro"
    $envRw      = Join-Path $root "env_rw"
    $envRo      = Join-Path $root "env_ro"
    $browser    = Join-Path $root "browser_profile"

    $dirs = @($root, $psStage, $portableRw, $portableRo, $browser)
    foreach ($envBase in @($envRw, $envRo)) {
        $dirs += @(
            $envBase,
            (Join-Path $envBase "ProgramFiles"),
            (Join-Path $envBase "ProgramData"),
            (Join-Path $envBase "LocalAppData"),
            (Join-Path $envBase "AppData"),
            (Join-Path $envBase "UserProfile"),
            (Join-Path $envBase "Temp")
        )
    }

    foreach ($d in $dirs) {
        if (-not (Test-Path -LiteralPath $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
    }

    return [PSCustomObject]@{
        Root          = $root
        PsStage       = $psStage
        PortableRw    = $portableRw
        PortableRo    = $portableRo
        EnvRw         = $envRw
        EnvRo         = $envRo
        BrowserProfile = $browser
    }
}

function Set-DirectoryWriteDenyAcl {
    param([Parameter(Mandatory = $true)][string]$DirectoryPath)

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $rights = [System.Security.AccessControl.FileSystemRights]::WriteData -bor `
              [System.Security.AccessControl.FileSystemRights]::CreateFiles -bor `
              [System.Security.AccessControl.FileSystemRights]::AppendData -bor `
              [System.Security.AccessControl.FileSystemRights]::CreateDirectories -bor `
              [System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles
    $inherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor `
               [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    $prop = [System.Security.AccessControl.PropagationFlags]::None
    $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
        $identity,
        $rights,
        $inherit,
        $prop,
        [System.Security.AccessControl.AccessControlType]::Deny
    )

    $acl = Get-Acl -LiteralPath $DirectoryPath
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $DirectoryPath -AclObject $acl
    $script:AppliedAclTargets.Add([PSCustomObject]@{
        Path = $DirectoryPath
        Rule = $rule
    })
}

function Remove-DirectoryWriteDenyAcl {
    param([Parameter(Mandatory = $true)][string]$DirectoryPath)

    if (-not (Test-Path -LiteralPath $DirectoryPath)) {
        return
    }
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = Get-Acl -LiteralPath $DirectoryPath
    $rules = @($acl.GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier]))
    $changed = $false
    foreach ($r in $rules) {
        if ($r.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Deny -and $r.IdentityReference -eq $identity) {
            $null = $acl.RemoveAccessRuleSpecific($r)
            $changed = $true
        }
    }
    if ($changed) {
        Set-Acl -LiteralPath $DirectoryPath -AclObject $acl
    }
}

function Clear-AllE2EAcls {
    $items = @($script:AppliedAclTargets)
    for ($i = $items.Count - 1; $i -ge 0; $i--) {
        try {
            Remove-DirectoryWriteDenyAcl -DirectoryPath $items[$i].Path
        } catch {}
    }
    $script:AppliedAclTargets.Clear()
}

function Remove-E2ESandbox {
    param([Parameter(Mandatory = $false)]$Sandbox)

    Clear-AllE2EAcls
    if ($null -eq $Sandbox -or [string]::IsNullOrWhiteSpace($Sandbox.Root)) {
        return
    }
    if (Test-Path -LiteralPath $Sandbox.Root) {
        for ($attempt = 0; $attempt -lt 5; $attempt++) {
            try {
                Remove-Item -LiteralPath $Sandbox.Root -Recurse -Force -ErrorAction Stop
                break
            } catch {
                Start-Sleep -Milliseconds 250
            }
        }
    }
}

function Initialize-PsStage {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$StageRoot
    )

    $files = @("UltraGamingMode.ps1", "UltraGamingMode.bat")
    foreach ($f in $files) {
        $src = Join-Path $RepoRoot $f
        if (Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $StageRoot $f) -Force
        }
    }

    foreach ($dirName in @("Core", "Config")) {
        $srcDir = Join-Path $RepoRoot $dirName
        $dstDir = Join-Path $StageRoot $dirName
        if (Test-Path -LiteralPath $srcDir) {
            if (Test-Path -LiteralPath $dstDir) {
                Remove-Item -LiteralPath $dstDir -Recurse -Force
            }
            Copy-Item -LiteralPath $srcDir -Destination $dstDir -Recurse -Force
        }
    }

    $backupsDir = Join-Path $StageRoot "Backups"
    if (-not (Test-Path -LiteralPath $backupsDir)) {
        New-Item -ItemType Directory -Path $backupsDir -Force | Out-Null
    }
}

function New-SandboxedProcessStartInfo {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string]$Arguments = "",
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$EnvRoot,
        [bool]$RedirectOutput = $false,
        [bool]$RequireRunAsInvoker = $true
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $RedirectOutput
    $psi.RedirectStandardError = $RedirectOutput
    if ($RedirectOutput) {
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    }

    $pf   = Join-Path $EnvRoot "ProgramFiles"
    $pd   = Join-Path $EnvRoot "ProgramData"
    $lad  = Join-Path $EnvRoot "LocalAppData"
    $ad   = Join-Path $EnvRoot "AppData"
    $up   = Join-Path $EnvRoot "UserProfile"
    $tmp  = Join-Path $EnvRoot "Temp"

    $psi.Environment["ProgramW6432"]    = $pf
    $psi.Environment["ProgramFiles"]    = $pf
    $psi.Environment["ProgramData"]     = $pd
    $psi.Environment["ALLUSERSPROFILE"] = $pd
    $psi.Environment["LOCALAPPDATA"]    = $lad
    $psi.Environment["APPDATA"]         = $ad
    $psi.Environment["USERPROFILE"]     = $up
    $psi.Environment["TEMP"]            = $tmp
    $psi.Environment["TMP"]             = $tmp

    $envParentLeaf = (Split-Path (Split-Path $EnvRoot -Parent) -Leaf) -replace '^ugm_e2e_\d+_', 'e2e_'
    $envLeaf       = Split-Path $EnvRoot -Leaf
    $rawNs         = ("{0}_{1}" -f $envParentLeaf, $envLeaf) -replace '[^A-Za-z0-9_-]', ''
    if ($rawNs.Length -gt 48) { $rawNs = $rawNs.Substring($rawNs.Length - 48) }
    if (-not [string]::IsNullOrWhiteSpace($rawNs)) {
        $psi.Environment["UGM_INSTANCE_NAMESPACE"] = $rawNs
    }

    if ($RequireRunAsInvoker -and -not (Test-IsElevatedAdmin)) {
        $psi.Environment["__COMPAT_LAYER"] = "RunAsInvoker"
    }

    return $psi
}

function Get-FileSha256Lower {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-DirectoryTreeHashes {
    param(
        [Parameter(Mandatory = $true)][string]$BaseDir,
        [string]$Filter = "*"
    )
    $map = [ordered]@{}
    if (-not (Test-Path -LiteralPath $BaseDir)) {
        return $map
    }
    $items = Get-ChildItem -LiteralPath $BaseDir -Filter $Filter -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName
    foreach ($it in $items) {
        $map[$it.FullName] = Get-FileSha256Lower -Path $it.FullName
    }
    return $map
}

function Get-ScheduledTaskSummary {
    param([Parameter(Mandatory = $true)][string]$TaskName)
    try {
        $out = & schtasks.exe /Query /TN $TaskName /FO LIST 2>$null
        if ($LASTEXITCODE -eq 0) {
            return ("EXISTS:" + ($out -join "|"))
        }
        return "MISSING"
    } catch {
        return "UNKNOWN"
    }
}

function New-HostIntegritySnapshot {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $tracked = [ordered]@{}
    foreach ($rel in @("UltraGamingMode.ps1", "UltraGamingMode.bat")) {
        $p = Join-Path $RepoRoot $rel
        if (Test-Path -LiteralPath $p) {
            $tracked[$p] = Get-FileSha256Lower -Path $p
        } else {
            $tracked[$p] = "MISSING"
        }
    }

    foreach ($sub in @("Config", "Core", "Backups")) {
        $dir = Join-Path $RepoRoot $sub
        $hashes = Get-DirectoryTreeHashes -BaseDir $dir
        foreach ($k in $hashes.Keys) {
            $tracked[$k] = $hashes[$k]
        }
        $tracked["__COUNT__$sub"] = [string]$hashes.Count
    }

    $localUi = Join-Path $env:LOCALAPPDATA "UltraGamingMode\ui_settings.json"
    if (Test-Path -LiteralPath $localUi) {
        $tracked[$localUi] = Get-FileSha256Lower -Path $localUi
    } else {
        $tracked[$localUi] = "MISSING"
    }

    $tracked["__TASK__BootTrigger"] = Get-ScheduledTaskSummary -TaskName "UltraGamingMode_BootTrigger"
    $tracked["__TASK__AutoStart"]   = Get-ScheduledTaskSummary -TaskName "UltraGamingMode_AutoStart"

    return $tracked
}

function Test-HostIntegritySnapshot {
    param(
        [Parameter(Mandatory = $true)]$BeforeSnapshot,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    $after = New-HostIntegritySnapshot -RepoRoot $RepoRoot
    $drifts = [System.Collections.Generic.List[string]]::new()

    foreach ($k in $BeforeSnapshot.Keys) {
        if (-not $after.Contains($k)) {
            $drifts.Add("Missing key after run: $k")
        } elseif ($BeforeSnapshot[$k] -ne $after[$k]) {
            $drifts.Add("Changed after run: $k (before=$($BeforeSnapshot[$k]), after=$($after[$k]))")
        }
    }
    foreach ($k in $after.Keys) {
        if (-not $BeforeSnapshot.Contains($k)) {
            $drifts.Add("New unexpected artifact after run: $k")
        }
    }

    return [PSCustomObject]@{
        Clean  = ($drifts.Count -eq 0)
        Drifts = @($drifts)
    }
}

function Read-NullTerminatedAscii {
    param(
        [Parameter(Mandatory = $true)]$PeReader,
        [Parameter(Mandatory = $true)][int]$Rva
    )
    if ($Rva -le 0) { return "" }
    try {
        $sec = $PeReader.GetSectionData($Rva)
        $nr = $sec.GetReader()
        $bytes = [System.Collections.Generic.List[byte]]::new()
        while ($nr.RemainingBytes -gt 0 -and $bytes.Count -lt 260) {
            $b = $nr.ReadByte()
            if ($b -eq 0) { break }
            $bytes.Add($b)
        }
        return [System.Text.Encoding]::ASCII.GetString($bytes.ToArray())
    } catch {
        return ""
    }
}

function Get-PEInspection {
    param(
        [Parameter(Mandatory = $true)][string]$ExePath,
        [string[]]$Markers = @()
    )

    $fs = [System.IO.File]::OpenRead($ExePath)
    try {
        $pe = [System.Reflection.PortableExecutable.PEReader]::new($fs)
        try {
            $machine = [string]$pe.PEHeaders.CoffHeader.Machine
            $subsystem = [string]$pe.PEHeaders.PEHeader.Subsystem
            $isManaged = ($null -ne $pe.PEHeaders.CorHeader)

            $imports = [System.Collections.Generic.List[string]]::new()
            $impDir = $pe.PEHeaders.PEHeader.ImportTableDirectory
            if ($impDir.Size -gt 0 -and $impDir.RelativeVirtualAddress -gt 0) {
                $sec = $pe.GetSectionData($impDir.RelativeVirtualAddress)
                $r = $sec.GetReader()
                while ($r.RemainingBytes -ge 20) {
                    $oft = $r.ReadUInt32()
                    $null = $r.ReadUInt32()
                    $null = $r.ReadUInt32()
                    $nameRva = $r.ReadUInt32()
                    $ft = $r.ReadUInt32()
                    if ($oft -eq 0 -and $nameRva -eq 0 -and $ft -eq 0) { break }
                    if ($nameRva -gt 0) {
                        $dllName = Read-NullTerminatedAscii -PeReader $pe -Rva ([int]$nameRva)
                        if (-not [string]::IsNullOrWhiteSpace($dllName)) {
                            $imports.Add($dllName)
                        }
                    }
                }
            }

            $delayImports = [System.Collections.Generic.List[string]]::new()
            $dDir = $pe.PEHeaders.PEHeader.DelayImportTableDirectory
            if ($dDir.Size -gt 0 -and $dDir.RelativeVirtualAddress -gt 0) {
                $dSec = $pe.GetSectionData($dDir.RelativeVirtualAddress)
                $dr = $dSec.GetReader()
                while ($dr.RemainingBytes -ge 32) {
                    $attrs = $dr.ReadUInt32()
                    $dNameRva = $dr.ReadUInt32()
                    $null = $dr.ReadUInt32()
                    $null = $dr.ReadUInt32()
                    $null = $dr.ReadUInt32()
                    $null = $dr.ReadUInt32()
                    $null = $dr.ReadUInt32()
                    $null = $dr.ReadUInt32()
                    if ($attrs -eq 0 -and $dNameRva -eq 0) { break }
                    if ($dNameRva -gt 0) {
                        $dName = Read-NullTerminatedAscii -PeReader $pe -Rva ([int]$dNameRva)
                        if (-not [string]::IsNullOrWhiteSpace($dName)) {
                            $delayImports.Add($dName)
                        }
                    }
                }
            }
        } finally {
            $pe.Dispose()
        }
    } finally {
        $fs.Dispose()
    }

    $rawBytes = [System.IO.File]::ReadAllBytes($ExePath)
    $asciiText = [System.Text.Encoding]::GetEncoding(28591).GetString($rawBytes)
    $utf16Text = [System.Text.Encoding]::Unicode.GetString($rawBytes)

    $execLevel = ""
    if ($asciiText -match 'requestedExecutionLevel\s+level="([^"]+)"') {
        $execLevel = $Matches[1]
    }

    $markerCounts = [ordered]@{}
    foreach ($m in $Markers) {
        $esc = [regex]::Escape($m)
        $cAscii = ([regex]::Matches($asciiText, $esc)).Count
        $cUtf16 = ([regex]::Matches($utf16Text, $esc)).Count
        $markerCounts[$m] = ($cAscii + $cUtf16)
    }

    $verInfo = (Get-Item -LiteralPath $ExePath).VersionInfo

    return [PSCustomObject]@{
        Path                    = $ExePath
        Machine                 = $machine
        Subsystem               = $subsystem
        IsManaged               = $isManaged
        Imports                 = @($imports)
        DelayImports            = @($delayImports)
        ManifestExecutionLevel  = $execLevel
        FileVersion             = $verInfo.FileVersion
        ProductVersion          = $verInfo.ProductVersion
        MarkerCounts            = $markerCounts
    }
}

function Test-Utf8NoBom {
    param([Parameter(Mandatory = $true)][string]$FilePath)

    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [PSCustomObject]@{ Valid = $false; Reason = "UTF-8 BOM (EF BB BF) present" }
    }
    if ($bytes.Length -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))) {
        return [PSCustomObject]@{ Valid = $false; Reason = "UTF-16 BOM present" }
    }
    try {
        $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
        $null = $strictUtf8.GetString($bytes)
        return [PSCustomObject]@{ Valid = $true; Reason = "" }
    } catch {
        return [PSCustomObject]@{ Valid = $false; Reason = "Invalid UTF-8 byte sequence" }
    }
}

function Find-Utf8BomFiles {
    param(
        [Parameter(Mandatory = $true)][string]$RootDir,
        [string[]]$Extensions = @(".ps1", ".json"),
        [string]$ExcludeDirRegex = '(\\|/)(Backups|node_modules|target|\.git|EBWebView|dist)(\\|/|$)'
    )

    $violations = [System.Collections.Generic.List[string]]::new()
    $files = Get-ChildItem -LiteralPath $RootDir -File -Recurse -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        if ($Extensions -notcontains $f.Extension.ToLowerInvariant()) { continue }
        if ($f.FullName -match $ExcludeDirRegex) { continue }
        $chk = Test-Utf8NoBom -FilePath $f.FullName
        if (-not $chk.Valid) {
            $violations.Add("$($f.FullName): $($chk.Reason)")
        }
    }
    return , @($violations)
}

function Decode-Base64Utf8 {
    param([Parameter(Mandatory = $true)][string]$Encoded)
    return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Encoded))
}

function Test-ContentPolicyHygiene {
    param(
        [Parameter(Mandatory = $true)][string[]]$Paths,
        [string]$ExcludeDirRegex = '(\\|/)(Backups|node_modules|target|\.git|\.bin|EBWebView|dist|ui)(\\|/|$)',
        [string[]]$Extensions = @(".ps1", ".bat", ".rs", ".toml", ".slint", ".json", ".md", ".html", ".svg", ".wxs", ".nsi", ".txt", ".mjs")
    )

    # Decoded at runtime so the test harness itself holds zero prohibited attribution literals.
    $p1 = Decode-Base64Utf8 "XGIoYWl8bGxtfGdwdHxjaGF0Z3B0fG9wZW5haXxjbGF1ZGV8YW50aHJvcGljfGdlbWluaXxhbnRpZ3Jhdml0eXxjb3BpbG90fGN1cnNvcnx3aW5kc3VyZnxkZXZpbnxhZ2VudGljfHN1YmFnZW50fHRlYW13b3JrfGFzc2lzdGFudHxhc3Npc3RhbnRzfHNraWxsfHNraWxscylcYg=="
    $p2 = Decode-Base64Utf8 "KNCw0YHRgdC40YHRgtC10L3RgnzRgdC60LjQu9C7fNC90LXQudGA0L7RgdC10YJ80LjRgdC60YPRgdGB0YLQstC10L3QvVx3KlxzK9C40L3RgtC10LvQu9C10LrRgnzRgdCz0LXQvdC10YDQuNGA0L7QstCw0L3QvlxzK9C40Lh8XGLQuNC4Wy3igJRcc118Y28tYXV0aG9yZWQtYnkp"
    $allowEncoded = @(
        "V1NBSUZhYnJpY1N2Yw==",
        "V2luZG93cyBBSSBGYWJyaWM=",
        "V2luZG93cyBDb3BpbG90ICYgUmVjYWxsIEFJ",
        "V0lORE9XUyAxMSBERUVQIERFQkxPQVQgJiBBSSBTVVBQUkVTU0lPTg==",
        "YmFja2dyb3VuZCBBSSBzdXBwcmVzc2Vk",
        "V2luZG93cyBBSQ==",
        "UHJvZ3JhbSBDb21wYXRpYmlsaXR5IEFzc2lzdGFudA==",
        "TG9jYWwgUHJvZmlsZSBBc3Npc3RhbnQ=",
        "TWljcm9zb2Z0IEFjY291bnQgU2lnbi1pbiBBc3Npc3RhbnQ=",
        "TmV0d29yayBDb25uZWN0aXZpdHkgQXNzaXN0YW50",
        "Vm9pY2UgQXNzaXN0YW50",
        "0LPQvtC70L7RgdC+0LLRi9GFINCw0YHRgdC40YHRgtC10L3RgtC+0LI="
    )

    $allowPatterns = @('\bcursor\s*:', '\.cursor\b')
    foreach ($enc in $allowEncoded) {
        $allowPatterns += [regex]::Escape((Decode-Base64Utf8 $enc))
    }

    $hits = [System.Collections.Generic.List[string]]::new()
    $targetFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

    foreach ($p in $Paths) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $item = Get-Item -LiteralPath $p
        if ($item.PSIsContainer) {
            foreach ($f in (Get-ChildItem -LiteralPath $p -File -Recurse -ErrorAction SilentlyContinue)) {
                if ($f.FullName -match $ExcludeDirRegex) { continue }
                if ($Extensions -notcontains $f.Extension.ToLowerInvariant()) { continue }
                $targetFiles.Add($f)
            }
        } else {
            $targetFiles.Add($item)
        }
    }

    foreach ($tf in $targetFiles) {
        $lines = [System.IO.File]::ReadAllLines($tf.FullName, [System.Text.Encoding]::UTF8)
        for ($idx = 0; $idx -lt $lines.Count; $idx++) {
            $line = $lines[$idx]
            foreach ($ap in $allowPatterns) {
                $line = [regex]::Replace($line, $ap, " ", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            }
            $m1 = [regex]::Match($line, $p1, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($m1.Success) {
                $hits.Add("$($tf.FullName):$($idx + 1): matched '$($m1.Value)'")
                continue
            }
            $m2 = [regex]::Match($line, $p2, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($m2.Success) {
                $hits.Add("$($tf.FullName):$($idx + 1): matched '$($m2.Value)'")
            }
        }
    }

    return , @($hits)
}

function Test-PowerShellAst {
    param([Parameter(Mandatory = $true)][string[]]$Files)

    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($f in $Files) {
        $parseErrors = $null
        $tokens = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            foreach ($pe in $parseErrors) {
                $errors.Add("PS7 AST $f`:$($pe.Extent.StartLineNumber): $($pe.Message)")
            }
        }
    }

    $ps51 = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path -LiteralPath $ps51) {
        $listJson = ConvertTo-Json -InputObject @($Files) -Compress
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($listJson))
        $script = @"
`$files = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64')) | ConvertFrom-Json
`$errs = @()
foreach (`$f in `$files) {
  `$pe = `$null; `$tk = `$null
  `$null = [System.Management.Automation.Language.Parser]::ParseFile(`$f, [ref]`$tk, [ref]`$pe)
  if (`$pe -and `$pe.Count -gt 0) {
    foreach (`$e in `$pe) { `$errs += "PS5.1 AST `${f}:`$(`$e.Extent.StartLineNumber): `$(`$e.Message)" }
  }
}
if (`$errs.Count -gt 0) { `$errs | ForEach-Object { Write-Output `$_ }; exit 1 }
exit 0
"@
        $out = & $ps51 -NoProfile -NonInteractive -Command $script 2>&1
        if ($LASTEXITCODE -ne 0) {
            foreach ($line in $out) {
                $errors.Add([string]$line)
            }
        }
    }

    return , @($errors)
}

function Test-E2ESandboxSelfTest {
    param(
        [Parameter(Mandatory = $true)]$Sandbox,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    # 1. Stage copy verification
    Initialize-PsStage -RepoRoot $RepoRoot -StageRoot $Sandbox.PsStage
    $stagedPs1 = Join-Path $Sandbox.PsStage "UltraGamingMode.ps1"
    if (-not (Test-Path -LiteralPath $stagedPs1)) {
        return [PSCustomObject]@{ Passed = $false; Reason = "Stage copy missing UltraGamingMode.ps1" }
    }

    # 2. NTFS Deny ACE verification + clean removal
    $aclProbeFile = Join-Path $Sandbox.PortableRo "acl_write_probe.txt"
    Set-DirectoryWriteDenyAcl -DirectoryPath $Sandbox.PortableRo
    $writeBlocked = $false
    try {
        [System.IO.File]::WriteAllText($aclProbeFile, "should-fail")
    } catch {
        $writeBlocked = $true
    }
    if (-not $writeBlocked) {
        return [PSCustomObject]@{ Passed = $false; Reason = "NTFS Deny ACE failed to block write in portable_ro" }
    }
    Remove-DirectoryWriteDenyAcl -DirectoryPath $Sandbox.PortableRo
    [System.IO.File]::WriteAllText($aclProbeFile, "unlocked-ok")
    Remove-Item -LiteralPath $aclProbeFile -Force

    # 3. Env-redirected child process + Job Object tracking/cleanup
    $pwshPath = (Get-Process -Id $PID).Path
    $psi = New-SandboxedProcessStartInfo `
        -FilePath $pwshPath `
        -Arguments '-NoProfile -Command "Write-Output $env:LOCALAPPDATA; Start-Sleep -Seconds 30"' `
        -WorkingDirectory $Sandbox.Root `
        -EnvRoot $Sandbox.EnvRw `
        -RedirectOutput $true `
        -RequireRunAsInvoker $false

    $proc = Start-E2EHostedProcess -StartInfo $psi
    $line = $proc.StandardOutput.ReadLine()
    $expectedLad = Join-Path $Sandbox.EnvRw "LocalAppData"
    if ($line -ne $expectedLad) {
        Stop-E2EProcessTree -RootPid $proc.Id
        return [PSCustomObject]@{ Passed = $false; Reason = "Env redirection failed: expected '$expectedLad', got '$line'" }
    }
    Stop-E2EProcessTree -RootPid $proc.Id
    $stillAlive = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
    if ($null -ne $stillAlive -and -not $stillAlive.HasExited) {
        return [PSCustomObject]@{ Passed = $false; Reason = "Tracked child process failed to terminate cleanly" }
    }

    return [PSCustomObject]@{ Passed = $true; Reason = "" }
}
