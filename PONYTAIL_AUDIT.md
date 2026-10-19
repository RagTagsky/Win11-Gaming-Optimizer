# PONYTAIL CODEBASE AUDIT REPORT

**Target Repository**: `c:\Users\ragtagsky\Documents\Workstation\E.Mode`  
**Date**: October 19, 2026  
**Auditor**: Ponytail Senior Review Engine (/boost)  
**Assumed Load**: Single Windows administrator toggling between Normal Mode and Ultra Gaming Mode across hardware ranging from budget systems (Intel Core i3-2100, 8 GB RAM, 1 TB HDD) to high-end multi-core gaming PCs (Ryzen / Core i9, 32 GB RAM, NVMe SSD).

---

### What this repo does:
This repository provides an automated optimization and state-management system for Windows gaming. It captures a snapshot of Windows services, startup applications, network adapters, and power configurations, stops 173 non-essential services on boot under SYSTEM, tunes CPU/GPU latency parameters, and restores the original system state upon exiting gaming mode.

---

## Must fix

1. **Storage detection classifies NVMe SSDs as mechanical HDDs** (`Core/SystemOptimizer.ps1:L512-532, L1100, L1129`)
   - **What this is:** Heuristic media type detection (`Resolve-StorageDeviceMediaType`) that distinguishes mechanical hard drives (HDDs) from solid state drives (SSDs).
   - **Problem:** The `$hddModelPattern` regex tests for `WD[0-9]`, `Blue`, `Black`, `Green`, `Red`, and `FireCuda` before checking `$ssdModelPattern`. Best-selling NVMe SSDs such as "WD Black SN770 1TB", "WD Blue SN580", and "Seagate FireCuda 530" are misidentified as mechanical HDDs (`IsHdd = True`). Furthermore, in WMI fallback (`line 1100`) and secondary drive scans (`line 1129`), the function is called with only `-Model`, omitting `-BusType`, so any secondary WD or Seagate NVMe game drive forces the entire system into `HddProfile = True`.
   - **Fix:** Evaluate `$ssdModelPattern` and `$BusType -match "NVMe"` before `$hddModelPattern`, explicitly exempt models matching `(SN[0-9]|NVMe|SSD)`, and pass `-BusType $d.InterfaceType` at lines 1100 and 1129.
   - **If we skip it:** Fast NVMe SSDs trigger HDD Thrash Guard, which suspends Windows defrag/TRIM maintenance, kills `SysMain`, and causes long-term flash performance degradation and game stuttering.

2. **Blacklist disables Xbox gamepads, wireless controllers, and Bluetooth audio** (`Config/services_blacklist.json:L81-91, L309, L553`)
   - **What this is:** The list of Windows background services disabled when entering Ultra Gaming Mode.
   - **Problem:** `services_blacklist.json` includes `XboxGipSvc` (Xbox Accessory Management Service, line 309), `bthserv` (Bluetooth Support Service, line 81), `BthAvctpSvc` (line 85), `BTAGService` (line 89), and `BluetoothUserService` (line 553). Disabling these services breaks wired and wireless Xbox controllers, Bluetooth gamepads (DualSense, Xbox Wireless), and Bluetooth headsets, violating the project guarantee of 100% controller protection.
   - **Fix:** Delete `XboxGipSvc`, `bthserv`, `BthAvctpSvc`, `BTAGService`, and `BluetoothUserService` from `services_blacklist.json`, and add `bthserv` and `XboxGipSvc` to `Config/services_whitelist.json`.
   - **If we skip it:** Players using Xbox controllers or Bluetooth wireless headsets lose gamepad controls and audio input upon booting into Gaming Mode.

3. **Scheduled boot task crash loops on boot error** (`UltraGamingMode.ps1:L166-224`)
   - **What this is:** `ApplyBootMode` runs at startup under Task Scheduler (`NT AUTHORITY\SYSTEM`) to disable services and apply low-latency hardware settings.
   - **Problem:** The `try / finally` block only protects step 4 (arming RunOnce). If any cmdlet in steps 1 through 3 encounters an unhandled terminating error, WMI timeout, or disk write lock before line 209, step 5 (`Unregister-ScheduledTask`) is bypassed.
   - **Fix:** Enclose the entire execution body of `ApplyBootMode` in a top-level `try { ... } finally { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue }`.
   - **If we skip it:** A transient driver glitch or file lock traps Windows in an unrecoverable boot task loop on every machine startup.

4. **Watchdog 30-second timestamp check causes both false rollback and missed rollback on fast reboot** (`UltraGamingMode.ps1:L236-251`)
   - **What this is:** Watchdog logic in `Restore` that decides whether an interactive logon belongs to the current gaming session or a subsequent reboot.
   - **Problem:** It computes `[Math]::Abs(([DateTime]$currentBootTime - [DateTime]$stateData.GamingBootTime).TotalSeconds) < 30`. If Session 0 WMI timed out and used `TickCount64` while Session 1 reads CIM, or if login occurs after clock drift, `$isSameBoot` evaluates to `$false` and normal mode is restored on the user's initial login. Conversely, if a player restarts after gaming on a fast UEFI/NVMe machine and logs in within 30 seconds, `$diffSec -lt 30` evaluates to `$true`, and the watchdog fails to roll back, leaving Gaming Mode active.
   - **Fix:** Replace the brittle timestamp comparison with an explicit boolean flag (`SessionLogonHandled: $false -> $true`) in `active_state.json`.
   - **If we skip it:** Gamers experience either premature rollbacks on their first login or failed rollbacks when restarting to exit gaming mode.

5. **RunOnce watchdog triggers UAC elevation prompts and uses unquoted executable paths** (`UltraGamingMode.ps1:L34-38, L260`)
   - **What this is:** Fail-safe RunOnce watchdog registered in `HKLM:\...\RunOnce` to monitor interactive logins.
   - **Problem:** Lines 34-38 invoke `Start-Process powershell.exe ... -Verb RunAs` whenever invoked without administrator rights, which triggers an invasive UAC elevation prompt on every user login. Furthermore, line 260 registers an unquoted relative path (`powershell.exe`) in `HKLM:\...\RunOnce`, reintroducing an unquoted executable vulnerability.
   - **Fix:** Use fully qualified, quoted `"$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"`, and manage session completion via a dedicated scheduled task or logon trigger that runs without interactive UAC prompts.
   - **If we skip it:** Users face unwanted UAC popups at logon, and dismissing the popup silently leaves the watchdog disabled.

6. **Group Policy leak permanently disables GameDVR after restore** (`Core/SystemOptimizer.ps1:L744-747` / `Core/StateEngine.ps1:L682-695`)
   - **What this is:** Background game recording and Xbox Game Bar capture hook suppression.
   - **Problem:** `Set-DeepGameDVROptimizations` creates `HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR\AllowGameDVR = 0`. This machine-wide Group Policy override is never recorded in `New-SystemStateBackup` and is never removed by `Restore-SystemState`.
   - **Fix:** Explicitly delete `AllowGameDVR` in `Restore-SystemState`: `Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -ErrorAction SilentlyContinue`.
   - **If we skip it:** Restoring normal system state leaves GameDVR and Xbox Game Bar permanently blocked by Windows Group Policy.

---

## Should fix

7. **Duplicated `Get-ResilientBootTimestamp` helper** (`reuse:` `Core/SystemOptimizer.ps1:L421-438` vs `UltraGamingMode.ps1:L63-80`)
   - **What this is:** Helper function retrieving system boot time via CIM with a `TickCount64` fallback.
   - **Problem:** An identical 18-line function is defined in both `UltraGamingMode.ps1` and `Core/SystemOptimizer.ps1`. Because `UltraGamingMode.ps1` dot-sources `SystemOptimizer.ps1` at line 48, it immediately overwrites its own definition.
   - **Fix:** Delete `Get-ResilientBootTimestamp` from `UltraGamingMode.ps1` and reuse the implementation from `Core/SystemOptimizer.ps1`.
   - **If we skip it:** 18 lines of duplicated code risk divergence during future maintenance.

8. **Artificial 2D array wrapping and redundant unrolling helper** (`yagni:` / `delete:` `Core/SystemOptimizer.ps1:L440-457, L578, L1208`)
   - **What this is:** Helper `Unroll-NestedCollection` created to flatten nested collections of network properties and ULPS keys.
   - **Problem:** Lines 578 (`return ,$results`) and 1208 (`return ,$keys`) prepend an artificial comma operator `,`, creating unwanted 2D arrays. An 18-line helper and multiple unit tests were then added just to undo the comma operator.
   - **Fix:** Remove the leading comma (`return $results` and `return $keys`) and delete `Unroll-NestedCollection`. PowerShell unrolls collection pipelines natively.
   - **If we skip it:** 30+ lines of unnecessary wrapper code and artificial complexity clutter production and test files.

9. **Duplicate dot-sourcing of `SystemOptimizer.ps1`** (`reuse:` `Core/StateEngine.ps1:L18` / `UltraGamingMode.ps1:L48-49`)
   - **What this is:** Script dependency loading at startup.
   - **Problem:** `UltraGamingMode.ps1` dot-sources `SystemOptimizer.ps1` at line 48 and `StateEngine.ps1` at line 49. But line 18 of `StateEngine.ps1` unconditionally dot-sources `SystemOptimizer.ps1` a second time, forcing PowerShell to parse and compile 2,537 lines of code twice on every execution.
   - **Fix:** Add an include guard in `StateEngine.ps1`: `if (-not (Get-Command Get-HardwareProfile -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot "SystemOptimizer.ps1") }`.
   - **If we skip it:** Script startup suffers a 150-300ms parsing penalty and redundant AST memory allocation.

10. **Dead configuration options in `startup_apps.json`** (`delete:` `Config/startup_apps.json:L10-20`)
    - **What this is:** Configuration properties defining startup registry locations, folders, and targeted UWP packages.
    - **Problem:** `"StartupRegistryPaths"`, `"StartupFolders"`, and `"TargetAppModelPackages"` exist in `Config/startup_apps.json`, but `Core/StateEngine.ps1` never references them; it hardcodes its own paths and suppresses all non-Apple UWP startup tasks unconditionally.
    - **Fix:** Either filter UWP apps using `TargetAppModelPackages` in `Disable-UserStateAggressive`, or delete the unused fields from `startup_apps.json`.
    - **If we skip it:** Users edit `startup_apps.json` expecting to configure UWP exclusions, but their modifications have zero effect.

11. **Conflicting process blacklist vs memory whitelist for AMD Overlay** (`Config/startup_apps.json:L32` vs `Core/SystemOptimizer.ps1:L316`)
    - **What this is:** Process filtering for Radeon Software overlay (`amdow.exe`).
    - **Problem:** `startup_apps.json:32` lists `amdow` in `BlacklistProcesses` for forced termination, while `Core/SystemOptimizer.ps1:316` explicitly whitelists `amdow` as a protected GPU infrastructure process.
    - **Fix:** Remove `amdow` from `BlacklistProcesses` in `Config/startup_apps.json` so AMD Radeon in-game overlay functions normally.
    - **If we skip it:** Calling `Stop-BlacklistedProcesses` crashes Radeon Software in-game overlay and metric tracking during gaming.

12. **Trivial single-line wrapper `Test-IsServiceProtected`** (`yagni:` `Core/ServiceManager.ps1:L1-8`)
    - **What this is:** Wrapper function checking whether a service name exists in the whitelist array.
    - **Problem:** The function contains 8 lines of CmdletBinding overhead solely to evaluate `($Whitelist -contains $ServiceName)`.
    - **Fix:** Delete `Test-IsServiceProtected` and use `$Whitelist -contains $ServiceName` directly at call sites.
    - **If we skip it:** An unnecessary layer of abstraction that only passes calls through.

13. **Subprocess spawning via `sc.exe` slows down boot and restore** (`stdlib / native` `Core/ServiceManager.ps1:L55, 77, 84` / `Core/StateEngine.ps1:L552` / `Core/SystemOptimizer.ps1:L762-820`)
    - **What this is:** External calls to `sc.exe` to configure, start, and stop Windows services.
    - **Problem:** Executing `sc.exe` in loops across 173 services spawns dozens of external OS processes, adding 5 to 10 seconds of startup and shutdown delay.
    - **Fix:** Use native PowerShell cmdlets `Set-Service`, `Stop-Service`, and `Start-Service` with `-ErrorAction SilentlyContinue`, reserving direct registry modification as the single fallback.
    - **If we skip it:** Mode switching takes significantly longer due to repetitive process creation overhead.

14. **Indiscriminate `EmptyWorkingSet` memory trimming induces HDD thrashing** (`Core/SystemOptimizer.ps1:L321-335`)
    - **What this is:** `Optimize-SystemMemory` function iterating through all running processes and calling Win32 `EmptyWorkingSet`.
    - **Problem:** Calling `EmptyWorkingSet` across every process forcibly evicts active pages into the paging file. On 8 GB budget systems with an HDD, background processes encountering immediate page faults trigger heavy disk I/O thrashing.
    - **Fix:** Rely on `[Win32StandbyCleaner]::FlushStandbyList()` to reclaim standby cache pages without evicting active process working sets.
    - **If we skip it:** Budget 8 GB HDD systems suffer severe frame drops and stuttering right after launching a game.

15. **Overengineered shortcut quarantine routing** (`yagni:` `Core/StateEngine.ps1:L43-81, L576-596`)
    - **What this is:** Function `Resolve-QuarantineDestinationPath` and file search loop to restore quarantined startup `.lnk` shortcuts.
    - **Problem:** Quarantined shortcuts are already segregated into `QuarantinedShortcuts\User` and `QuarantinedShortcuts\ProgramData`. Restoring them requires only two batch move operations. The 38-line helper and multi-parameter lookup were created purely to satisfy artificial test mocks.
    - **Fix:** Replace the entire lookup loop with `Move-Item "$quarantineDir\User\*" $userStartup` and `Move-Item "$quarantineDir\ProgramData\*" $commonStartup`.
    - **If we skip it:** 50+ lines of unnecessary path-routing complexity remain in the state engine.

---

## Nice to have

16. **Duplicated latency status display routines** (`merge:` `UltraGamingMode.ps1:L733-800` vs `L810-856`)
    - **What this is:** Console output showing low-latency kernel, timer, input buffer, and HAGS status.
    - **Problem:** Lines 810-856 in `KernelLatencyStatus` duplicate lines 733-800 in `Diagnostic` almost character-for-character.
    - **Fix:** Merge the display logic into a single helper `Show-LatencySubsystemStatus` called by both menu actions.
    - **If we skip it:** 50 lines of duplicate UI formatting must be maintained in parallel.

17. **Fake unit tests asserting on local test-script copies** (`Tests/Verify-UniversalEngine.ps1:L176-179, L327-331`)
    - **What this is:** Unit test assertions in `Verify-UniversalEngine.ps1` for power schemes and Low-RAM profiling.
    - **Problem:** Test Group 7 (lines 176-179) and Test Group 10.1 (lines 327-331) do not call production functions. They run private math expressions and regexes copied into the test script itself, giving false-positive passes even if production code fails.
    - **Fix:** Export pure functions `Test-IsHighPerformanceScheme` and `Test-IsLowRamSystem` from `SystemOptimizer.ps1` and assert against them.
    - **If we skip it:** The test suite verifies its own copy of the logic rather than production code.

18. **Redundant WMI hardware scanning during cold boot** (`Core/SystemOptimizer.ps1:L977-1171` / `UltraGamingMode.ps1:L175`)
    - **What this is:** Running full hardware profile auto-detection `Get-HardwareProfile` during `ApplyBootMode`.
    - **Problem:** `New-SystemStateBackup` already stored the hardware profile in `active_state.json`. Executing `Get-HardwareProfile` again during Session 0 cold boot triggers 8 redundant CIM queries while WMI is busy starting up.
    - **Fix:** In `ApplyBootMode`, read `$hw = $stateData.HardwareProfile` directly from `active_state.json`.
    - **If we skip it:** Cold boot into Gaming Mode takes 3-5 seconds longer than necessary.

19. **Repeated `powercfg -setactive` calls in CPU tuning** (`Core/SystemOptimizer.ps1:L1406, 1500, 1530`)
    - **What this is:** Applying CPU core parking, minimum throttle frequency, and processor states.
    - **Problem:** Each helper calls `powercfg -setactive SCHEME_CURRENT` separately, causing 3 ACPI power state renegotiations in rapid succession.
    - **Fix:** Execute `powercfg -setacvalueindex` for all desired settings first, then call `powercfg -setactive SCHEME_CURRENT` once at the end.
    - **If we skip it:** Unnecessary CPU frequency and PCIe power state renegotiation flickering during mode transition.

20. **External `fsutil.exe` execution when native registry setting suffices** (`stdlib / native` `Core/SystemOptimizer.ps1:L1870-1874`)
    - **What this is:** Disabling NTFS last access updates and 8.3 short name creation.
    - **Problem:** `Set-NTFSGamingOptimizations` runs `fsutil.exe` twice, while `Restore-NTFSGamingOptimizations` sets registry values directly via `Set-ItemProperty`.
    - **Fix:** Set `NtfsDisableLastAccessUpdate` and `NtfsDisable8dot3NameCreation` directly via `Set-ItemProperty` in `Set-NTFSGamingOptimizations`.
    - **If we skip it:** Spawns two unnecessary child processes and relies on external tool exit codes.

---

### Smaller findings left out (4 items):
1. **Misleading Function Name** (`Core/SystemOptimizer.ps1:L1276-1355`): `Clear-AmdShaderCache` cleans AMD, NVIDIA, Intel, and DirectX, relying on an alias `Clear-GpuShaderCache`.
2. **Misleading Return Type Contract** (`Core/SystemOptimizer.ps1:L1552-1563`): `Get-GpuPnpDeviceId` returns a `Win32_VideoController` object rather than a PNP ID string.
3. **Unquoted PowerShell Invocations in Batch File** (`UltraGamingMode.bat:L22, 47, 53, 59, 65, 103`): Spawns `powershell.exe` without full path `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`.
4. **Unrestored State in Widgets & Notifications** (`Core/SystemOptimizer.ps1:L937, L968`): Restoration unconditionally enables `TaskbarDa = 1` and `NOC_GLOBAL_SETTING_TOASTS_ENABLED = 1` without checking if the user previously had them disabled.

---

**Verdict:** Fix storage detection (Finding 1) and gamepad/Bluetooth service blacklist (Finding 2) first to prevent SSD misconfiguration and broken controllers, then harden Session 0 boot error handling (Finding 3).  
**Lean:** -240 lines, -2 external tool dependencies (`sc.exe`, `fsutil.exe`) possible.  
**Not checked:** Cold-boot Task Scheduler execution under live Session 0 `NT AUTHORITY\SYSTEM` (requires actual physical reboot).
