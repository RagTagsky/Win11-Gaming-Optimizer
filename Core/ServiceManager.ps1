function Test-IsServiceProtected {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)] [string]$ServiceName,
        [Parameter(Mandatory = $true)] [string[]]$Whitelist
    )
    return ($Whitelist -contains $ServiceName)
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

    if (-not $IsRestoring -and $Whitelist -and (Test-IsServiceProtected -ServiceName $ServiceName -Whitelist $Whitelist)) {
        Write-Warning "Service '$ServiceName' is protected by the Whitelist. Skipping modification."
        return $false
    }

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $service) { return $false }

    $startVal = switch ($StartupType) {
        "Automatic" { 2 }
        "Manual"    { 3 }
        "Disabled"  { 4 }
    }
    $scType = switch ($StartupType) {
        "Automatic" { "auto" }
        "Manual"    { "demand" }
        "Disabled"  { "disabled" }
    }

    $configured = $false
    try {
        Set-Service -Name $ServiceName -StartupType $StartupType -ErrorAction Stop
        Write-Host "  [+] Service '$ServiceName' startup type set to $StartupType." -ForegroundColor Green
        $configured = $true
    }
    catch {
        $null = sc.exe config "$ServiceName" start= $scType 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [+] Service '$ServiceName' configured via sc.exe fallback ($scType)." -ForegroundColor Green
            $configured = $true
        }
        else {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
            if (Test-Path $regPath) {
                try {
                    Set-ItemProperty -Path $regPath -Name "Start" -Value $startVal -Type DWord -Force -ErrorAction Stop
                    Write-Host "  [+] Service '$ServiceName' configured via Direct Registry ($StartupType / Start=$startVal)." -ForegroundColor Green
                    $configured = $true
                }
                catch {
                    Write-Warning "Failed to configure service '$ServiceName': $($_.Exception.Message)"
                }
            }
        }
    }

    if ($StopNow) {
        if ($service.Status -eq 'Running') {
            $null = sc.exe stop "$ServiceName" 2>&1
            Write-Host "  [!] Sent stop command to '$ServiceName'." -ForegroundColor Yellow
        }
        # Also stop any active per-user service instances (e.g. CaptureService_5e3a4, CDPUserSvc_5e3a4)
        $userInstances = Get-Service -Name "$($ServiceName)_*" -ErrorAction SilentlyContinue
        foreach ($uInst in $userInstances) {
            if ($uInst.Status -eq 'Running') {
                $null = sc.exe stop "$($uInst.Name)" 2>&1
                Write-Host "  [!] Sent stop command to per-user instance '$($uInst.Name)'." -ForegroundColor Yellow
            }
        }
    }

    return $configured
}
