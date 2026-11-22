# E2E.ProcessHost.ps1 — Win32 Job Object & Deterministic Child Process Cleanup

Set-StrictMode -Version Latest

if (-not ("UgmE2E.NativeProcessHost" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace UgmE2E {
    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct IO_COUNTERS {
        public ulong ReadOperationCount;
        public ulong WriteOperationCount;
        public ulong OtherOperationCount;
        public ulong ReadTransferCount;
        public ulong WriteTransferCount;
        public ulong OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    public static class NativeProcessHost {
        public const int JobObjectExtendedLimitInformation = 9;
        public const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000;

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern IntPtr CreateJobObjectW(IntPtr lpJobAttributes, string lpName);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetInformationJobObject(IntPtr hJob, int JobObjectInfoClass, ref JOBOBJECT_EXTENDED_LIMIT_INFORMATION lpJobObjectInfo, uint cbJobObjectInfoLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CloseHandle(IntPtr hObject);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("dwmapi.dll")]
        public static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out int pvAttribute, int cbAttribute);
    }
}
"@
}

$script:E2EJobHandle = [IntPtr]::Zero
$script:PreExistingUgmPids = @()
$script:TrackedChildPids = [System.Collections.Generic.List[int]]::new()

function Initialize-E2EProcessHost {
    $script:PreExistingUgmPids = @(Get-Process -Name "UltraGamingMode" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    $script:TrackedChildPids.Clear()

    if ($script:E2EJobHandle -eq [IntPtr]::Zero) {
        $job = [UgmE2E.NativeProcessHost]::CreateJobObjectW([IntPtr]::Zero, $null)
        if ($job -ne [IntPtr]::Zero) {
            $info = New-Object UgmE2E.JOBOBJECT_EXTENDED_LIMIT_INFORMATION
            $info.BasicLimitInformation.LimitFlags = [UgmE2E.NativeProcessHost]::JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
            $size = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf($info)
            $null = [UgmE2E.NativeProcessHost]::SetInformationJobObject(
                $job,
                [UgmE2E.NativeProcessHost]::JobObjectExtendedLimitInformation,
                [ref]$info,
                $size
            )
            $script:E2EJobHandle = $job
        }
    }

    return [PSCustomObject]@{
        PreExistingUgmPids = @($script:PreExistingUgmPids)
        JobHandleActive    = ($script:E2EJobHandle -ne [IntPtr]::Zero)
    }
}

function Register-E2ETrackedPid {
    param([Parameter(Mandatory = $true)][int]$ProcessId)
    if ($script:PreExistingUgmPids -notcontains $ProcessId -and -not $script:TrackedChildPids.Contains($ProcessId)) {
        $script:TrackedChildPids.Add($ProcessId)
    }
}

function Start-E2EHostedProcess {
    param(
        [Parameter(Mandatory = $true)][System.Diagnostics.ProcessStartInfo]$StartInfo
    )

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $StartInfo
    $started = $proc.Start()
    if (-not $started) {
        throw "Failed to start process: $($StartInfo.FileName)"
    }

    Register-E2ETrackedPid -ProcessId $proc.Id

    if ($script:E2EJobHandle -ne [IntPtr]::Zero) {
        try {
            $null = [UgmE2E.NativeProcessHost]::AssignProcessToJobObject($script:E2EJobHandle, $proc.Handle)
        } catch {}
    }

    return $proc
}

function Stop-E2EProcessTree {
    param([Parameter(Mandatory = $true)][int]$RootPid)

    if ($script:PreExistingUgmPids -contains $RootPid) {
        return
    }

    try {
        $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $RootPid" -ErrorAction SilentlyContinue)
        foreach ($c in $children) {
            $childPid = [int]$c.ProcessId
            if ($childPid -gt 0 -and $childPid -ne $PID) {
                Stop-E2EProcessTree -RootPid $childPid
            }
        }
    } catch {}

    try {
        $p = Get-Process -Id $RootPid -ErrorAction SilentlyContinue
        if ($null -ne $p -and -not $p.HasExited) {
            Stop-Process -Id $RootPid -Force -ErrorAction SilentlyContinue
            $null = $p.WaitForExit(3000)
        }
    } catch {}
}

function Stop-E2ETrackedProcesses {
    $pidsCopy = @($script:TrackedChildPids)
    foreach ($cpid in $pidsCopy) {
        Stop-E2EProcessTree -RootPid $cpid
    }

    $orphans = 0
    foreach ($cpid in $pidsCopy) {
        $still = Get-Process -Id $cpid -ErrorAction SilentlyContinue
        if ($null -ne $still -and -not $still.HasExited) {
            $orphans++
        }
    }

    if ($orphans -eq 0) {
        $script:TrackedChildPids.Clear()
    }
    return $orphans
}

function Clear-E2EProcessHost {
    $orphans = Stop-E2ETrackedProcesses
    if ($script:E2EJobHandle -ne [IntPtr]::Zero) {
        try {
            $null = [UgmE2E.NativeProcessHost]::CloseHandle($script:E2EJobHandle)
        } catch {}
        $script:E2EJobHandle = [IntPtr]::Zero
    }
    return $orphans
}

function Get-E2EPreExistingUgmPids {
    return , @($script:PreExistingUgmPids)
}
