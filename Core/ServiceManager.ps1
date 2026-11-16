$Script:ImmutableCoreServices = @(
    "RpcSs", "DcomLaunch", "RpcEptMapper", "PlugPlay", "Power", "LSM",
    "SamSs", "EventLog", "BFE", "mpssvc", "ProfSvc", "UserManager",
    "CryptSvc", "KeyIso", "VaultSvc", "CoreMessagingRegistrar",
    "SystemEventsBroker", "BrokerInfrastructure", "nsi", "Dhcp",
    "Dnscache", "Winmgmt", "Schedule", "TrustedInstaller",
    "Audiosrv", "AudioEndpointBuilder", "MMCSS"
)

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

    $baseInputName = $ServiceName -replace '_[0-9a-fA-F]+$', ''
    $isCoreImmutable = ($Script:ImmutableCoreServices -contains $ServiceName) -or ($Script:ImmutableCoreServices -contains $baseInputName)
    if (-not $IsRestoring -and ($isCoreImmutable -or ($Whitelist -and (($Whitelist -contains $ServiceName) -or ($Whitelist -contains $baseInputName))))) {
        Write-Warning "Service '$ServiceName' is protected by the Whitelist. Skipping modification."
        return $false
    }

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $service) {
        # Fallback: check for per-user (_LUID) or versioned ([0-9]*) services (e.g. GoogleUpdaterService157.0.8089.0)
        $matching = @(Get-Service -Name "$($ServiceName)_*", "$($ServiceName)[0-9]*" -ErrorAction SilentlyContinue)
        if ($matching.Count -gt 0) {
            $service = $matching[0]
            $ServiceName = $service.Name
        } else {
            return $false
        }
    }

    $resolvedBaseName = $ServiceName -replace '_[0-9a-fA-F]+$', ''
    $isResolvedImmutable = ($Script:ImmutableCoreServices -contains $ServiceName) -or ($Script:ImmutableCoreServices -contains $resolvedBaseName)
    if (-not $IsRestoring -and ($isResolvedImmutable -or ($Whitelist -and (($Whitelist -contains $ServiceName) -or ($Whitelist -contains $resolvedBaseName))))) {
        Write-Warning "Service '$ServiceName' is protected by the Whitelist. Skipping modification."
        return $false
    }

    $startVal = switch ($StartupType) {
        "Automatic" { 2 }
        "Manual"    { 3 }
        "Disabled"  { 4 }
    }

    $configured = $false
    try {
        Set-Service -Name $ServiceName -StartupType $StartupType -ErrorAction Stop
        Write-Host "  [+] Service '$ServiceName' startup type set to $StartupType." -ForegroundColor Green
        $configured = $true
    }
    catch {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
        if (Test-Path -LiteralPath $regPath) {
            try {
                Set-ItemProperty -LiteralPath $regPath -Name "Start" -Value $startVal -Type DWord -Force -ErrorAction Stop
                if ($ServiceName -match '^(.+)_[0-9a-fA-F]+$') {
                    $baseRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($Matches[1])"
                    if (Test-Path -LiteralPath $baseRegPath) {
                        Set-ItemProperty -LiteralPath $baseRegPath -Name "Start" -Value $startVal -Type DWord -Force -ErrorAction SilentlyContinue
                    }
                } else {
                    $instanceRegPaths = Get-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($ServiceName)_*" -ErrorAction SilentlyContinue
                    foreach ($instReg in $instanceRegPaths) {
                        Set-ItemProperty -LiteralPath $instReg.PSPath -Name "Start" -Value $startVal -Type DWord -Force -ErrorAction SilentlyContinue
                    }
                }
                Write-Host "  [+] Service '$ServiceName' configured via Direct Registry ($StartupType / Start=$startVal)." -ForegroundColor Green
                $configured = $true
            }
            catch {
                Write-Warning "Failed to configure service '$ServiceName': $($_.Exception.Message)"
            }
        }
    }

    if ($StopNow) {
        if ($service.Status -eq 'Running') {
            Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
            Write-Host "  [!] Sent stop command to '$ServiceName'." -ForegroundColor Yellow
        }
        # Also stop any active per-user service instances (e.g. CaptureService_5e3a4, CDPUserSvc_5e3a4)
        $userInstances = Get-Service -Name "$($ServiceName)_*" -ErrorAction SilentlyContinue
        foreach ($uInst in $userInstances) {
            if ($uInst.Status -eq 'Running') {
                Stop-Service -Name $uInst.Name -Force -ErrorAction SilentlyContinue
                Write-Host "  [!] Sent stop command to per-user instance '$($uInst.Name)'." -ForegroundColor Yellow
            }
        }
    }

    return $configured
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

    $baseName = $ServiceName -replace '_[0-9a-fA-F]+$', ''
    $isProtected = ($Script:ImmutableCoreServices -contains $ServiceName) -or
                   ($Script:ImmutableCoreServices -contains $baseName) -or
                   ($Whitelist -and (($Whitelist -contains $ServiceName) -or ($Whitelist -contains $baseName)))

    if ($Operation -in @("Stop", "Disabled") -and $isProtected) {
        throw "Service '$ServiceName' is protected by the Whitelist / Core OS and cannot be stopped or disabled."
    }

    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $svc) {
        $matching = @(Get-Service -Name "$($ServiceName)_*", "$($ServiceName)[0-9]*" -ErrorAction SilentlyContinue)
        if ($matching.Count -gt 0) {
            $svc = $matching[0]
            $ServiceName = $svc.Name
        } else {
            throw "Service '$ServiceName' was not found on this system."
        }
    }

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

