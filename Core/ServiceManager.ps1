$Script:ImmutableCoreServices = @(
    "RpcSs", "DcomLaunch", "RpcEptMapper", "PlugPlay", "Power", "LSM",
    "SamSs", "EventLog", "BFE", "mpssvc", "ProfSvc", "UserManager",
    "CryptSvc", "KeyIso", "VaultSvc", "CoreMessagingRegistrar",
    "SystemEventsBroker", "BrokerInfrastructure", "nsi", "Dhcp",
    "Dnscache", "Winmgmt", "Schedule", "TrustedInstaller",
    "Audiosrv", "AudioEndpointBuilder", "MMCSS"
)

$Script:FixedVersionServiceNames = @(
    "FontCache3.0.0.0",
    "igfxCUIService2.0.0.0"
)

function Get-CanonicalServiceName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ServiceName = ""
    )

    if ([string]::IsNullOrWhiteSpace($ServiceName)) {
        return ""
    }
    $trimmed = $ServiceName.Trim()
    $withoutLuid = $trimmed -replace '_[0-9a-fA-F]{4,16}$', ''
    foreach ($fixed in $Script:FixedVersionServiceNames) {
        if ($withoutLuid -ieq $fixed) {
            return $withoutLuid
        }
    }
    if ($withoutLuid -match '^([A-Za-z][A-Za-z0-9_\- ]*?)\d+\.\d+\.\d+\.\d+$') {
        return $Matches[1]
    }
    return $withoutLuid
}

function Test-ServiceInList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ServiceName = "",

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [array]$List = @()
    )

    if ([string]::IsNullOrWhiteSpace($ServiceName) -or -not $List -or $List.Count -eq 0) {
        return $false
    }
    $trimmed = $ServiceName.Trim()
    $canon = Get-CanonicalServiceName -ServiceName $trimmed
    foreach ($item in $List) {
        $entryName = if ($item -is [string]) {
            $item
        } elseif ($item -is [System.Collections.IDictionary] -and $item.Contains("Name")) {
            [string]$item["Name"]
        } elseif ($null -ne $item -and $item.PSObject.Properties["Name"]) {
            [string]$item.Name
        } else {
            ""
        }
        if ([string]::IsNullOrWhiteSpace($entryName)) { continue }
        $entryTrim = $entryName.Trim()
        if ($entryTrim -ieq $trimmed -or $entryTrim -ieq $canon) {
            return $true
        }
        $entryCanon = Get-CanonicalServiceName -ServiceName $entryTrim
        if ($entryCanon -ieq $canon) {
            return $true
        }
    }
    return $false
}

function Test-ServiceShouldDisableInGaming {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [array]$Blacklist = @(),

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$Whitelist = @()
    )

    if (-not (Test-SafeServiceName -ServiceName $ServiceName)) {
        return $false
    }
    if (Test-ServiceInList -ServiceName $ServiceName -List $Script:ImmutableCoreServices) {
        return $false
    }
    if (Test-ServiceInList -ServiceName $ServiceName -List $Whitelist) {
        return $false
    }
    return (Test-ServiceInList -ServiceName $ServiceName -List $Blacklist)
}

function Find-MatchingLiveServices {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName
    )

    $canon = Get-CanonicalServiceName -ServiceName $ServiceName
    $exact = @(Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)
    if ($exact.Count -gt 0) {
        # Per-user base templates (SERVICE_USER_SERVICE=0x40 without SERVICE_USERSERVICE_INSTANCE=0x80)
        # cannot be started directly; prefer active _LUID instances when a user session is logged on,
        # falling back to the template when no live instance exists yet (e.g. SYSTEM AtStartup).
        $allPerUserTemplates = ($exact | Where-Object {
            (([int]$_.ServiceType -band 0xC0) -ne 0x40)
        }).Count -eq 0
        if (-not $allPerUserTemplates) {
            return $exact
        }
        if (-not [string]::IsNullOrWhiteSpace($canon)) {
            $liveInstances = @(Get-Service -Name "$($canon)_*" -ErrorAction SilentlyContinue | Where-Object {
                (Get-CanonicalServiceName -ServiceName $_.Name) -ieq $canon
            })
            if ($liveInstances.Count -gt 0) {
                return $liveInstances
            }
        }
        return $exact
    }
    if ([string]::IsNullOrWhiteSpace($canon)) {
        return @()
    }
    $candidates = @(Get-Service -Name "$($canon)_*", "$($canon)[0-9]*" -ErrorAction SilentlyContinue)
    $matched = @($candidates | Where-Object {
        (Get-CanonicalServiceName -ServiceName $_.Name) -ieq $canon
    })
    if ($matched.Count -gt 0) {
        return $matched
    }
    if ($canon -ine $ServiceName.Trim()) {
        return @(Get-Service -Name $canon -ErrorAction SilentlyContinue)
    }
    return @()
}

function Test-SafeServiceName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ServiceName
    )

    if ([string]::IsNullOrWhiteSpace($ServiceName)) {
        return $false
    }
    $trimmed = $ServiceName.Trim()
    if ($trimmed.Length -gt 128) {
        return $false
    }
    if ($trimmed -match '(\.\.|[\\/\*\?\[\]"'';&|<>`])') {
        return $false
    }
    return ($trimmed -match '^[A-Za-z0-9_.\- ]{1,128}$')
}

function Set-ServiceStateSafe {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)] [string]$ServiceName,
        [Parameter(Mandatory = $true)] [ValidateSet("Disabled", "Manual", "Automatic")] [string]$StartupType,
        [switch]$StopNow,
        [Parameter(Mandatory = $false)] [string[]]$Whitelist,
        [switch]$IsRestoring
    )

    if (-not (Test-SafeServiceName -ServiceName $ServiceName)) {
        Write-Warning "Rejected unsafe service identifier '$ServiceName'."
        return $false
    }

    $isCoreImmutable = Test-ServiceInList -ServiceName $ServiceName -List $Script:ImmutableCoreServices
    if (-not $IsRestoring -and ($isCoreImmutable -or (Test-ServiceInList -ServiceName $ServiceName -List $Whitelist))) {
        Write-Warning "Service '$ServiceName' is protected by the Whitelist. Skipping modification."
        return $false
    }

    $matchedServices = @(Find-MatchingLiveServices -ServiceName $ServiceName)
    if ($matchedServices.Count -eq 0) {
        return $false
    }

    $startVal = switch ($StartupType) {
        "Automatic" { 2 }
        "Manual"    { 3 }
        "Disabled"  { 4 }
    }

    $anyConfigured = $false
    foreach ($service in $matchedServices) {
        $targetName = $service.Name
        $isResolvedImmutable = Test-ServiceInList -ServiceName $targetName -List $Script:ImmutableCoreServices
        if (-not $IsRestoring -and ($isResolvedImmutable -or (Test-ServiceInList -ServiceName $targetName -List $Whitelist))) {
            Write-Warning "Service '$targetName' is protected by the Whitelist. Skipping modification."
            continue
        }

        $configured = $false
        try {
            Set-Service -Name $targetName -StartupType $StartupType -ErrorAction Stop
            Write-Host "  [+] Service '$targetName' startup type set to $StartupType." -ForegroundColor Green
            $configured = $true
            # Keep per-user base template and active _LUID instances synchronized across reboots
            if ($targetName -match '^(.+)_[0-9a-fA-F]{4,16}$') {
                $baseRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($Matches[1])"
                if (Test-Path -LiteralPath $baseRegPath) {
                    Set-ItemProperty -LiteralPath $baseRegPath -Name "Start" -Value $startVal -Type DWord -Force -ErrorAction SilentlyContinue
                }
            } elseif (([int]$service.ServiceType -band 0x40) -ne 0) {
                $instanceRegPaths = Get-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($targetName)_*" -ErrorAction SilentlyContinue
                foreach ($instReg in $instanceRegPaths) {
                    Set-ItemProperty -LiteralPath $instReg.PSPath -Name "Start" -Value $startVal -Type DWord -Force -ErrorAction SilentlyContinue
                }
            }
        }
        catch {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$targetName"
            if (Test-Path -LiteralPath $regPath) {
                try {
                    Set-ItemProperty -LiteralPath $regPath -Name "Start" -Value $startVal -Type DWord -Force -ErrorAction Stop
                    if ($targetName -match '^(.+)_[0-9a-fA-F]{4,16}$') {
                        $baseRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($Matches[1])"
                        if (Test-Path -LiteralPath $baseRegPath) {
                            Set-ItemProperty -LiteralPath $baseRegPath -Name "Start" -Value $startVal -Type DWord -Force -ErrorAction SilentlyContinue
                        }
                    } else {
                        $instanceRegPaths = Get-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($targetName)_*" -ErrorAction SilentlyContinue
                        foreach ($instReg in $instanceRegPaths) {
                            Set-ItemProperty -LiteralPath $instReg.PSPath -Name "Start" -Value $startVal -Type DWord -Force -ErrorAction SilentlyContinue
                        }
                    }
                    Write-Host "  [+] Service '$targetName' configured via Direct Registry ($StartupType / Start=$startVal)." -ForegroundColor Green
                    $configured = $true
                }
                catch {
                    Write-Warning "Failed to configure service '$targetName': $($_.Exception.Message)"
                }
            }
        }

        if ($configured) {
            $anyConfigured = $true
        }

        if ($StopNow) {
            if ($service.Status -eq 'Running') {
                Stop-Service -Name $targetName -Force -ErrorAction SilentlyContinue
                Write-Host "  [!] Sent stop command to '$targetName'." -ForegroundColor Yellow
            }
            # Also stop any active per-user service instances (e.g. WpnUserService_5e3a4)
            $userInstances = Get-Service -Name "$($targetName)_*" -ErrorAction SilentlyContinue
            foreach ($uInst in $userInstances) {
                if ($uInst.Status -eq 'Running') {
                    Stop-Service -Name $uInst.Name -Force -ErrorAction SilentlyContinue
                    Write-Host "  [!] Sent stop command to per-user instance '$($uInst.Name)'." -ForegroundColor Yellow
                }
            }
        }
    }

    return $anyConfigured
}

function Invoke-ServiceControlSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Start", "Stop", "Automatic", "Manual", "Disabled")]
        [string]$Operation,

        [Parameter(Mandatory = $false)]
        [string[]]$Whitelist = @()
    )

    if (-not (Test-SafeServiceName -ServiceName $ServiceName)) {
        throw "Invalid service identifier: '$ServiceName'"
    }

    $isProtected = (Test-ServiceInList -ServiceName $ServiceName -List $Script:ImmutableCoreServices) -or
                   (Test-ServiceInList -ServiceName $ServiceName -List $Whitelist)

    if ($Operation -in @("Stop", "Disabled") -and $isProtected) {
        throw "Service '$ServiceName' is protected by the Whitelist / Core OS and cannot be stopped or disabled."
    }

    $matching = @(Find-MatchingLiveServices -ServiceName $ServiceName)
    if ($matching.Count -eq 0) {
        throw "Service '$ServiceName' was not found on this system."
    }
    $svc = $matching[0]
    $ServiceName = $svc.Name

    switch ($Operation) {
        "Start" {
            if ($svc.StartType -eq "Disabled") {
                Set-Service -Name $ServiceName -StartupType Manual -ErrorAction Stop
            }
            if ($svc.Status -ne "Running") {
                Start-Service -Name $ServiceName -ErrorAction Stop
            }
            Write-Host "Service '$ServiceName' started successfully."
            return $true
        }
        "Stop" {
            if ($svc.Status -ne "Stopped") {
                Stop-Service -Name $ServiceName -Force -ErrorAction Stop
            }
            Write-Host "Service '$ServiceName' stopped successfully."
            return $true
        }
        { $_ -in @("Automatic", "Manual", "Disabled") } {
            $ok = Set-ServiceStateSafe -ServiceName $ServiceName -StartupType $Operation -Whitelist $Whitelist -IsRestoring:($Operation -ne "Disabled")
            if (-not $ok) {
                throw "Failed to set startup type of service '$ServiceName' to $Operation."
            }
            Write-Host "Service '$ServiceName' startup type set to $Operation."
            return $true
        }
    }
    return $false
}

