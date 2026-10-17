<div align="center">

# ⚡ Ultra Gaming Mode for Windows 11
### *Extreme Precision Stripper Edition (v2.3)*

**A zero-risk, high-precision latency and frame pacing optimizer for Windows 10/11.**  
Temporarily strips background bloat, halts real-time disk scanning, locks multimedia scheduling, and guarantees 100% automated failsafe recovery on next boot.

[![Windows 11 Supported](https://img.shields.io/badge/Windows-11%20%7C%2010-0078D4?logo=windows&logoColor=white&style=for-the-badge)](https://www.microsoft.com/windows)
[![PowerShell Version](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white&style=for-the-badge)](https://github.com/PowerShell/PowerShell)
[![Version](https://img.shields.io/badge/Version-v2.3--Extreme-FF4500?style=for-the-badge)](https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-success.svg?style=for-the-badge)](LICENSE)
[![Zero-Risk Watchdog](https://img.shields.io/badge/Watchdog-HKLM%20RunOnce-blueviolet?style=for-the-badge)](#the-zero-risk-watchdog-guarantee)
[![Tested On AMD](https://img.shields.io/badge/Hardware-Ryzen%20%2B%20Radeon-ED1C24?logo=amd&logoColor=white&style=for-the-badge)](#real-world-benchmarks-engine-telemetry)

---

[English](README.md) | [Русский](README.ru.md)

</div>

---

## 📑 Table of Contents
- [Why Ultra Gaming Mode?](#why-ultra-gaming-mode)
- [Real-World Benchmarks & Engine Telemetry](#real-world-benchmarks-engine-telemetry)
  - [Hardware Specs & Benchmark Environment](#hardware-specs-benchmark-environment)
  - [Verified CS2 Source 2 Engine Profiler Results](#verified-cs2-source-2-engine-profiler-results)
  - [Key Takeaways](#key-takeaways)
- [Core Architecture & Lifecycle](#core-architecture-lifecycle)
  - [Execution Flow Diagram](#execution-flow-diagram)
  - [The Zero-Risk Watchdog Guarantee](#the-zero-risk-watchdog-guarantee)
- [Deep Technical Features](#deep-technical-features)
  - [1. Targeted Service Blacklist (173 Services)](#1-targeted-service-blacklist-173-services)
  - [2. Ironclad Whitelist (119 Protected Services)](#2-ironclad-whitelist-119-protected-services)
  - [3. Temporary Windows Defender Suspension](#3-temporary-windows-defender-suspension)
  - [4. Background Process & Bloatware Annihilator](#4-background-process-bloatware-annihilator)
  - [5. Windows 11 Widgets & Bing Search Elimination](#5-windows-11-widgets-bing-search-elimination)
  - [6. Network & Latency Kernel Optimizations](#6-network-latency-kernel-optimizations)
  - [7. On-Demand Memory Trimming (Working Sets & Standby List)](#7-on-demand-memory-trimming-working-sets-standby-list)
  - [8. Emergency Repair Toolkit (DisplayPort & Audio/Microphone)](#8-emergency-repair-toolkit-displayport-audiomicrophone)
- [Quick Start Guide](#quick-start-guide)
  - [Option A: Interactive Menu (Recommended)](#option-a-interactive-menu-recommended)
  - [Option B: PowerShell CLI Usage](#option-b-powershell-cli-usage)
- [Menu Overview & CLI Reference](#menu-overview-cli-reference)
- [Directory Structure](#directory-structure)
- [System Requirements & Compatibility](#system-requirements-compatibility)
- [Author & Credits](#author-credits)
- [License](#license)

---

## ⚡ Why Ultra Gaming Mode?

Modern Windows 11 is packed with hundreds of background processes, telemetry collectors, diagnostic listeners, per-user service templates, and aggressive Defender real-time archive scans. In competitive esports titles (such as *Counter-Strike 2*, *VALORANT*, *Apex Legends*), these background spikes cause:
- **DPC (Deferred Procedure Call) Latency Spikes:** Caused by network power-saving sleep transitions (`*EEE`) and multimedia scheduler contention.
- **Texture / Asset Stutters:** Windows Defender intercepts synchronous filesystem read calls when games stream models, shaders, or maps.
- **Micro-Freezes on Frame Boundaries:** Secondary threads stealing CPU cycles from game render loops.
- **1% Low FPS Drops:** Jitter in frame pacing even when average FPS remains high.

**Ultra Gaming Mode v2.3** solves this without permanently mangling your operating system. Unlike brittle "debloater" scripts that break Windows Update, brick microphone privacy permissions, or cause black screens on DisplayPort monitors, Ultra Gaming Mode utilizes a **non-destructive, snapshot-driven lifecycle**:

```
[Normal Windows] ──(Arm Mode)──> [System Snapshot] ──(Reboot)──> [Stripped Ultra Gaming Mode]
       ▲                                                                   │
       │                                                                   │
       └───────────────────(Failsafe Watchdog / Restore)───────────────────┘
```

---

## 📊 Real-World Benchmarks & Engine Telemetry

All metrics were captured using internal engine profiling tools under strict, identical real-match conditions.

### Hardware Specs & Benchmark Environment
| Component | Specification |
|:---|:---|
| **CPU** | AMD Ryzen 5 5600X (6 Cores / 12 Threads @ 4.6 GHz) |
| **GPU** | AMD Radeon RX 6600 (8 GB GDDR6) |
| **RAM** | 32 GB DDR4 (Dual Channel 3600 MHz CL16) |
| **OS** | Windows 11 Pro (x64) |
| **Target Game** | *Counter-Strike 2* (Valve Source 2 Engine) |
| **Resolution** | 1440x1080 (4:3 Stretched) |
| **Video Settings** | Competitive Low (Reflex / Anti-Lag Enabled) |
| **Telemetry Tool** | Valve Source 2 `VProfLite` Internal Engine Profiler |
| **Sample Size** | **59,467 continuous frames** (~121.2 seconds continuous 5v5 firefight) |

---

### Verified CS2 Source 2 Engine Profiler Results

| Metric | Stock Windows 11 | Ultra Gaming Mode v2.3 | Delta / Gain | Real-World Impact |
|:---|:---:|:---:|:---:|:---|
| **1% Low FPS (P1)** | **169.6 FPS** | **187.5 FPS** | **+17.9 FPS (+10.6%)** | **Smoothest crosshair tracking during smokes & heavy firefights** |
| **Average FPS** | **473.1 FPS** | **493.0 FPS** | **+19.9 FPS (+4.2%)** | Higher peak performance and engine throughput |
| **Average FrameTime** | **2.11 ms** | **2.03 ms** | **-0.08 ms** | Lower base rendering overhead |
| **99% Frame Density (P99 FrameTotal)** | **5.90 ms** | **5.33 ms** | **-0.57 ms (-9.7%)** | Eliminates 99th percentile frame queuing bottlenecks |
| **Frame Boundary (P95 Sync Spikes)** | **4.50 ms** | **3.10 ms** | **-1.40 ms (-31.1%)** | **31.1% spike reduction! Eliminates CPU thread sync stalls** |
| **Client Rendering (P95 Render Spikes)** | **4.80 ms** | **3.40 ms** | **-1.40 ms (-29.2%)** | **29.2% smoother draw call pipeline and frame submission** |
| **Present_RenderDevice (P95 Input Queue)** | **2.48 ms** | **2.19 ms** | **-0.29 ms (-11.7%)** | **11.7% lower display swapchain input latency** |
| **Server Simulation (P95 Local Tickrate)** | **3.25 ms** | **3.11 ms** | **-0.14 ms (-4.3%)** | More consistent local sub-tick prediction processing |
| **Server Game (P95 Game Logic)** | **2.84 ms** | **2.70 ms** | **-0.14 ms (-4.9%)** | Cleaner execution thread for physics and entity collision |
| **Panorama UI (P99 UI Latency)** | **0.46 ms** | **0.14 ms** | **-0.32 ms (3.3x faster / -69.5%)** | Instant HUD updates, zero radar/killfeed lag |

### Key Takeaways
1. **-31.1% Frame Boundary Spike Drop:** The Source 2 engine spends significantly less time waiting for Windows kernel thread scheduling between frames.
2. **+17.9 FPS on 1% Lows:** 1% lows jumped past 187 FPS, preventing micro-stutters that typically ruin spray control and flick shots.
3. **P99 Panorama UI latency slashed by 3.3x:** Windows UI compositing interference is eradicated, keeping the in-game HUD running at near-zero execution time.

---

## 🛠 Core Architecture & Lifecycle

### Execution Flow Diagram

```
                 +---------------------------------------+
                 |   User Launches UltraGamingMode.bat   |
                 +---------------------------------------+
                                     │
                     [1] Arm Mode for Next Boot
                                     ▼
                 +---------------------------------------+
                 | 1. Create System State JSON Snapshot  |
                 | 2. Suppress Startup Apps & Widgets    |
                 | 3. Register SYSTEM Task Scheduler Job |
                 +---------------------------------------+
                                     │
                             Reboot PC
                                     ▼
                 +---------------------------------------+
                 | Task Scheduler executes ApplyBootMode |
                 | under NT AUTHORITY\SYSTEM:            |
                 | - Strips 173 Blacklist Services       |
                 | - Pauses Defender Real-Time Scans     |
                 | - Tunes Network (TCPNoDelay, *EEE off)|
                 | - Arms HKLM RunOnce Watchdog          |
                 +---------------------------------------+
                                     │
                       User Enters Gaming Session
                                     │
             ┌───────────────────────┴───────────────────────┐
             ▼                                               ▼
+-------------------------+                     +-------------------------+
|   Reboot PC Normally    |                     | Run [2] Restore State   |
|   RunOnce Watchdog      |                     | (Manual Instant Revert) |
|   Restores Everything   |                     |                         |
+-------------------------+                     +-------------------------+
             │                                               │
             └───────────────────────┬───────────────────────┘
                                     ▼
                 +---------------------------------------+
                 | Windows Returned to 100% Stock State: |
                 | - Services restored to original types |
                 | - Defender Real-Time Protection ON    |
                 | - Widgets, Search & Startup Restored  |
                 +---------------------------------------+
```

### The Zero-Risk Watchdog Guarantee
Unlike other tweak scripts that leave your operating system in an unrecoverable state if your machine crashes, Ultra Gaming Mode implements a hardware-grade fail-safe:
1. **State Snapshots (`Backups\active_state.json`):** Before touching a single registry key or service, every service's exact startup mode (`Manual`, `Auto`, `Disabled`), user startup shortcuts, UWP app flags, and network configs are stored in a structured JSON snapshot.
2. **`HKLM\RunOnce` Kernel Watchdog:** An autonomous watchdog is registered in `HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce` named `*UltraGamingModeRestore`.
3. **Crash-Proof Reversion:** If your PC unexpectedly crashes, loses power, or you simply reboot when your match finishes, Windows runs the watchdog on the next logon. It detects the reboot, unpacks `active_state.json`, and completely restores every service and setting back to normal.

---

## 🔬 Deep Technical Features

### 1. Targeted Service Blacklist (173 Services)
Carefully compiled to remove all background context switching without compromising system integrity:
- **Telemetry & Diagnostics:** `DiagTrack`, `dmwappushservice`, `DPS` (Diagnostic Policy Service), `wmiApSrv`, `pla` (Performance Logs), `TroubleshootingSvc`, `wuqisvc`, `WSAIFabricSvc` (Windows AI Fabric).
- **Hyper-V & Remote Desktop:** `TermService`, `SessionEnv`, `UmRdpService`, `WinRM`, `HvHost`, all `vmic*` Guest Integration services, `MSiSCSI`, `SNMPTrap`, `RpcLocator`.
- **Backup & File History:** `fhsvc` (File History), `wbengine` (Block Level Backup), `SDRSVC` (Windows Backup), `CloudBackupRestoreSvc`, `OneSyncSvc`.
- **Print & Scanners:** `Spooler`, `PrintNotify`, `PrintScanBrokerService`, `PrintDeviceConfigurationService`, `PrintWorkflowUserSvc`, `StiSvc` (WIA), `Fax`, `WiaRpc`.
- **Bluetooth (Selective):** `bthserv`, `BthAvctpSvc`, `BTAGService`, `BluetoothUserService` (can be instantly restored if Bluetooth controller is needed).
- **Xbox & Microsoft Store Background Daemons:** `ClipSVC`, `LicenseManager`, `AppXSvc`, `GamingServices`, `GamingServicesNet`, `XblAuthManager`, `XblGameSave`, `XboxGipSvc`, `XboxNetApiSvc`, `InstallService`, `PushToInstall`.
- **Windows 11 Per-User Template Services:** `CaptureService`, `BcastDVRUserService` (GameDVR broadcast buffer), `CDPUserSvc`, `DevicePickerUserSvc`, `DevicesFlowUserSvc`, `DeviceAssociationBrokerSvc`, `SmsRouter`, `MessagingService`, `PenService`, `UserDataSvc`, `UnistoreSvc`, `cbdhsvc`, `NPSMSvc`.
- **Search & Caches:** `WSearch` (Windows Search Indexer), `SysMain` (Superfetch).
- **Updates & Background Downloaders:** `wuauserv`, `bits`, `dosvc`, `UsoSvc`, `WaaSMedicSvc`, `edgeupdate`, `edgeupdatem`, `gupdate`, `gupdatem`.
- **Hotspot, Cellular & Geolocation:** `icssvc`, `autotimesvc`, `lfsvc`, `WFDSConMgrSvc`.
- **Third-Party Background Bloat:** `EABackgroundService` (EA App telemetry), `LibreOfficeMaintenance`.

### 2. Ironclad Whitelist (119 Protected Services)
The optimizer strictly checks every operation against an inviolable whitelist:
- **Ultra-Low Latency Input:** `GameInputSvc` (Windows 11 GameInput API), `hidserv` (HID input stack preserving 1,000 Hz, 4,000 Hz, and 8,000 Hz mouse polling and macros), `TextInputManagementService` (keyboard engine & in-game chat typing).
- **Audio & Microphone Security:** `Audiosrv`, `AudioEndpointBuilder`, `camsvc` (**Capability Access Manager Service** — protects microphone privacy permissions so Discord, Steam, and in-game voice never get blocked), `ApxSvc`, `midisrv`, `QWAVE`.
- **Network & Mobile Tethering:** `Dhcp`, `Dnscache`, `LanmanWorkstation`, `LanmanServer` (prevents RPC permission failures), `NlaSvc`, `netprofm`, `WlanSvc`, `Wcmsvc`, `Netman`, `nsi`, `Apple Mobile Device Service` (guarantees iPhone USB tethering on Ethernet 2 remains 100% active).
- **Anti-Cheat Kernels & Launchers:** `FACEIT`, `FACEITService`, `Steam Client Service`, `Rockstar Service`, `vgk`, `vgc` (Riot Vanguard), `EasyAntiCheat`, `BEService` (BattlEye).
- **Display & Hardware Drivers:** `AMD External Events Utility`, `AMD Crash Defender Service`, `GraphicsPerfSvc`, `DisplayEnhancementService`, `DispBrokerDesktopSvc`, `ProcessGovernor` (Process Lasso).
- **Core Security & UAC:** `Appinfo` (UAC privilege escalation), `StateRepository`, `UserManager`, `TokenBroker`, `wlidsvc`, `Schedule`, `TimeBrokerSvc`, `Winmgmt`.

### 3. Temporary Windows Defender Suspension
- When Ultra Gaming Mode boots, Windows Defender Real-Time Protection is temporarily set to bypass (`DisableRealtimeMonitoring = 1`, `DisableBehaviorMonitoring = 1`, `DisableIOAVProtection = 1`, `DisableScriptScanning = 1`).
- Eliminates synchronous disk I/O hooks during map loading and model streaming.
- Restores automatically on normal reboot or when running Option [2].

### 4. Background Process & Bloatware Annihilator
- **Terminated on Launch:** Web browsers (`firefox`, `chrome`, `msedge`), `Telegram`, `Discord`, `Spotify`, `EpicGamesLauncher`, `CrossDeviceResume` (Phone Link), AMD screen record overlays (`amdow`, `AMDRSServ`), taskbar widgets (`msedgewebview2`), cloud sync clients (`GoogleDriveFS`), background store updaters.
- **Strictly Protected:** The active game, **Steam**, **FACEIT Client**, AMD Radeon display driver (`atieclxx`, `amdfendrsr`), **MSI Afterburner / RivaTuner Statistics Server**, **Process Lasso** (`ProcessGovernor`), **Apple Mobile Device Service** (USB Tethering).

### 5. Windows 11 Widgets & Bing Search Elimination
- Disables Windows 11 News & Interests taskbar widgets (`TaskbarDa = 0`, `AllowNewsAndInterests = 0`), which immediately kills up to 6 hidden background `msedgewebview2.exe` processes.
- Disables Bing online search recommendations inside the Start Menu (`BingSearchEnabled = 0`, `DisableSearchBoxSuggestions = 1`), saving CPU cycles on desktop interactions.

### 6. Network & Latency Kernel Optimizations
- **Nagle's Algorithm Disabled:** Sets `TCPNoDelay = 1` and `TcpAckFrequency = 1` across all active network adapters, eliminating network packet buffering delays in online multiplayer.
- **Energy-Efficient Ethernet (*EEE) Disabled:** Deactivates power-saving sleep transitions on physical NICs (`*EEE = 0`, `EnableGreenEthernet = 0`), stopping micro-disconnects and packet jitter.

### 7. On-Demand Memory Trimming (Working Sets & Standby List)
- Features native Win32 P/Invoke calling `psapi.dll!EmptyWorkingSet`.
- Flushes bloated background process working sets into the standby cache, triggers garbage collection, and yields hundreds of megabytes of free RAM on the fly without restarting.

### 8. Emergency Repair Toolkit (DisplayPort & Audio/Microphone)
- **Option [5] DisplayPort Topology Reset:** Clears corrupt multi-monitor configuration caches in `HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers` (`Configuration`, `Connectivity`, `ScaleFactors`). Cleans invalid MMCSS thread priorities (`Affinity = 0`), restarts display services, and forces a clean DisplayPort Link Training handshake.
- **Option [6] Microphone & Core Services Unblock:** Instantly resets and starts `camsvc` (fixes microphone access in Discord/CS2), starts `LanmanServer`, and switches `Steam Client Service` and `bthserv` to Demand start.

---

## 🚀 Quick Start Guide

### Option A: Interactive Menu (Recommended)

1. Clone or download this repository:
   ```cmd
   git clone https://github.com/RagTagsky/Win11-Gaming-Optimizer.git
   cd Win11-Gaming-Optimizer
   ```
2. Right-click **`UltraGamingMode.bat`** and select **"Run as administrator"** (the launcher will also self-elevate if needed).
3. Choose **`[1] Arm Ultra Gaming Mode for Next Boot`**.
4. Restart your computer. Windows will boot directly into stripped Ultra Gaming Mode.
5. When finished playing, run **`UltraGamingMode.bat`** and select **`[2] Restore Normal Windows State Now`** (or simply reboot your PC to let the Watchdog restore it automatically).

```
============================================================
           ULTRA GAMING MODE CONTROLLER  v2.3
============================================================

 [1] Arm Ultra Gaming Mode for Next Boot
 [2] Restore Normal Windows State Now
 [3] Flush and Clean RAM Cache Now (Standby List)
 [4] Run System Diagnostic / Pre-Flight Check
 [5] Repair Display + Reset DisplayPort Cache (Emergency Fix)
 [6] Repair Microphone, Steam + Core Services (Instant Fix)
 [7] Check Current Status
 [8] Exit
============================================================
```

---

### Option B: PowerShell CLI Usage

Open PowerShell as Administrator:

```powershell
# Check current system status and running bloatware services
powershell.exe -ExecutionPolicy Bypass -File .\UltraGamingMode.ps1 -Action Status

# Run pre-flight diagnostic check
powershell.exe -ExecutionPolicy Bypass -File .\UltraGamingMode.ps1 -Action Diagnostic

# Arm Ultra Gaming Mode for next boot
powershell.exe -ExecutionPolicy Bypass -File .\UltraGamingMode.ps1 -Action Enable

# Clean RAM working sets on demand
powershell.exe -ExecutionPolicy Bypass -File .\UltraGamingMode.ps1 -Action CleanMemory

# Revert back to normal Windows configuration
powershell.exe -ExecutionPolicy Bypass -File .\UltraGamingMode.ps1 -Action Restore

# Emergency DisplayPort topology cache reset
powershell.exe -ExecutionPolicy Bypass -File .\UltraGamingMode.ps1 -Action RepairDisplay

# Emergency Microphone & Core Services repair
powershell.exe -ExecutionPolicy Bypass -File .\UltraGamingMode.ps1 -Action RepairServices
```

---

## 🕹 Menu Overview & CLI Reference

| Menu Option | CLI Action Flag | Description |
|:---:|:---|:---|
| **`[1]`** | `-Action Enable` | Creates backup snapshot, suppresses user startup apps, and arms Task Scheduler boot trigger under SYSTEM. |
| **`[2]`** | `-Action Restore` | Restores all 173 services to their original saved states, re-enables Windows Defender, unregisters boot triggers, and restores startup apps. |
| **`[3]`** | `-Action CleanMemory` | Calls `EmptyWorkingSet` via Win32 API to reclaim standby cache and process memory instantly. |
| **`[4]`** | `-Action Diagnostic` | Runs pre-flight audit: checks administrator privileges, MMCSS profiles, power plans, whitelist safety, blacklist count, and startup bloat. |
| **`[5]`** | `-Action RepairDisplay` | Emergency fix: wipes corrupt registry display topology caches and resets MMCSS game scheduling to default safe parameters. |
| **`[6]`** | `-Action RepairServices`| Emergency fix: repairs and starts `camsvc` (Microphone privacy), `LanmanServer` (RPC session), and unblocks Steam/Bluetooth. |
| **`[7]`** | `-Action Status` | Displays current active mode (`Normal`, `Armed`, `GameMode_Active`, `Restored`) and counts active background services. |
| **`[8]`** | `Exit` | Exits the interactive launcher. |

---

## 📂 Directory Structure

```
Win11-Gaming-Optimizer/
│
├── UltraGamingMode.bat              # Elevated interactive TUI launcher
├── UltraGamingMode.ps1              # Core PowerShell CLI controller & orchestrator
├── README.md                        # English documentation & benchmarks
├── README.ru.md                     # Russian documentation & benchmarks
├── LICENSE                          # MIT License
│
├── Config/
│   ├── services_blacklist.json      # 173 target non-essential Windows services
│   ├── services_whitelist.json      # 119 strictly protected critical components
│   └── startup_apps.json            # Target startup bloat & protected app rules
│
├── Core/
│   ├── ServiceManager.ps1           # Safe service manipulation with whitelist locks
│   ├── StateEngine.ps1              # Snapshot creation, registry backup & restore engine
│   └── SystemOptimizer.ps1          # Power, MMCSS, Network, Memory, and Defender tuning
│
└── Backups/
    └── active_state.json            # Dynamic active session snapshot (auto-generated)
```

---

## 💻 System Requirements & Compatibility

- **Operating System:** Windows 11 (21H2, 22H2, 23H2, 24H2) or Windows 10 (20H2+) 64-bit.
- **PowerShell:** PowerShell 5.1 (Built into Windows) or PowerShell 7+.
- **Privileges:** Administrator privileges required for service and registry modification.
- **Hardware Compatibility:**
  - Fully compatible with AMD Ryzen & Intel Core processors.
  - Fully compatible with AMD Radeon, NVIDIA GeForce, and Intel Arc GPUs.
  - DisplayPort DSC (Display Stream Compression) & HDMI 2.1 safe.
  - High polling rate mice (1000 Hz – 8000 Hz) fully supported via whitelisted `hidserv` and `GameInputSvc`.
- **Anti-Cheat Compatibility:** 100% compatible with FACEIT, Riot Vanguard (*VALORANT*), EasyAntiCheat (*Apex Legends*, *Fortnite*), BattlEye (*Rainbow Six Siege*), and Valve Anti-Cheat (*CS2*).

---

## 👤 Author & Credits

- **Developer:** RagTagsky
- **Official Website:** [ragtagsky.xyz](https://ragtagsky.xyz)
- **GitHub Repository:** [github.com/RagTagsky/Win11-Gaming-Optimizer](https://github.com/RagTagsky/Win11-Gaming-Optimizer)

---

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.  
You are free to use, modify, and distribute this software for personal and commercial gaming setups.
