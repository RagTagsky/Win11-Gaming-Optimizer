function Set-ServiceStateSafe {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)] [string]$ServiceName,
        [Parameter(Mandatory = $true)] [ValidateSet("Disabled", "Manual", "Automatic")] [string]$StartupType,
        [switch]$StopNow,
        [Parameter(Mandatory = $false)] [string[]]$Whitelist,
        [switch]$IsRestoring
    )

    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $service) {
        # Fallback: check for versioned/suffixed services (e.g. GoogleUpdaterService157.0.8089.0)
        $matching = @(Get-Service -Name "$($ServiceName)*" -ErrorAction SilentlyContinue)
        if ($matching.Count -gt 0) {
            $service = $matching[0]
            $ServiceName = $service.Name
        } else {
            return $false
        }
    }

    if (-not $IsRestoring -and $Whitelist -and ($Whitelist -contains $ServiceName)) {
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

