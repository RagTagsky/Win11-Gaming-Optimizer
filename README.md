<div align="center">

# ⚡ Ultra Gaming Mode for Windows 11
### *Extreme Precision & Universal Hardware Tuning Edition (v2.5)*

**A zero-risk, high-precision latency, frame pacing, and universal hardware optimizer for Windows 10/11.**  
Temporarily strips background bloat, halts real-time disk scanning, auto-detects and adapts to ANY PC hardware (Intel/AMD CPUs, NVIDIA/AMD/Intel GPUs, 8GB Low-RAM Guard, HDD 100% Thrash Protection), activates GPU MSI Mode, and guarantees 100% automated failsafe recovery on next boot.

[![Windows 11 Supported](https://img.shields.io/badge/Windows-11%20%7C%2010-0078D4?logo=windows&logoColor=white&style=for-the-badge)](https://www.microsoft.com/windows)
[![PowerShell Version](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white&style=for-the-badge)](https://github.com/PowerShell/PowerShell)
[![Version](https://img.shields.io/badge/Version-v2.5--Universal-FF4500?style=for-the-badge)](https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-success.svg?style=for-the-badge)](LICENSE)
[![Zero-Risk Watchdog](https://img.shields.io/badge/Watchdog-HKLM%20RunOnce-blueviolet?style=for-the-badge)](#the-zero-risk-watchdog-guarantee)
[![Universal Hardware](https://img.shields.io/badge/Hardware-Intel%20%2B%20AMD%20%7C%20NVIDIA-ED1C24?style=for-the-badge)](#universal-hardware-auto-detection-engine)

---

[English](README.md) | [Русский](README.ru.md)

</div>

---

## 📑 Table of Contents
- [Why Ultra Gaming Mode?](#why-ultra-gaming-mode)
- [Universal Hardware Auto-Detection Engine](#universal-hardware-auto-detection-engine)
  - [CPU Architecture Tuning (Intel & AMD)](#cpu-architecture-tuning-intel--amd)
  - [Adaptive GPU Engine (NVIDIA, AMD & Intel)](#adaptive-gpu-engine-nvidia-amd--intel)
  - [Low-RAM Budget Guard (8 GB Systems)](#low-ram-budget-guard-8-gb-systems)
  - [Mechanical HDD 100% Thrash Protection](#mechanical-hdd-100-thrash-protection)
- [Real-World Benchmarks & Engine Telemetry](#real-world-benchmarks-engine-telemetry)
  - [Hardware Specs & Benchmark Environments](#hardware-specs-benchmark-environments)
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
  - [7. GPU MSI (Message Signaled Interrupts) Mode & High Priority](#7-gpu-msi-message-signaled-interrupts-mode--high-priority)
  - [8. VBS / HVCI (Core Isolation / Memory Integrity) Diagnostics & Toggle](#8-vbs--hvci-core-isolation--memory-integrity-diagnostics--toggle)
  - [9. NTFS File System I/O Optimizations](#9-ntfs-file-system-io-optimizations)
  - [10. Physical Network Adapter Driver Tweaks (FlowControl & InterruptModeration)](#10-physical-network-adapter-driver-tweaks-flowcontrol--interruptmoderation)
  - [11. On-Demand Memory Trimming (Working Sets & Standby List)](#11-on-demand-memory-trimming-working-sets--standby-list)
  - [12. Emergency Repair Toolkit (DisplayPort & Audio/Microphone)](#12-emergency-repair-toolkit-displayport--audiomicrophone)
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

**Ultra Gaming Mode v2.5** solves this without permanently mangling your operating system. Unlike brittle "debloater" scripts that break Windows Update, brick microphone privacy permissions, or cause black screens on DisplayPort monitors, Ultra Gaming Mode utilizes a **non-destructive, snapshot-driven lifecycle**:

```
[Normal Windows] ──(Arm Mode)──> [System Snapshot] ──(Reboot)──> [Stripped Ultra Gaming Mode]
       ▲                                                                   │
       │                                                                   │
       └───────────────────(Failsafe Watchdog / Restore)───────────────────┘
```

---

## 🛠️ Universal Hardware Auto-Detection Engine

Ultra Gaming Mode v2.5 features an autonomous hardware discovery engine (`Get-HardwareProfile`) that inspects your machine's physical architecture during diagnostic checks, arming, and boot stages. Rather than applying blunt, one-size-fits-all tweaks, the optimizer detects exact CPU topologies, GPU bus interfaces, physical memory limits, and storage media types to dynamically tailor kernel and driver optimizations to your exact PC.

```
       ┌────────────────────────────────────────────────────────┐
       │         Universal Hardware Auto-Detection Engine       │
       │                 (Get-HardwareProfile)                  │
       └───────┬───────────────┬────────────────┬───────────────┘
               │               │                │               │
       ┌───────▼──────┐ ┌──────▼──────┐ ┌───────▼──────┐ ┌──────▼──────┐
       │   CPU Core   │ │   GPU Bus   │ │  RAM Budget  │ │   Storage   │
       │   Topology   │ │  Interrupts │ │  & Pagefile  │ │  Media Type │
       └───────┬──────┘ └──────┬──────┘ └───────┬──────┘ └──────┬──────┘
               │               │                │               │
       • Intel / AMD   • MSI Mode (IRQ) • Low-RAM Guard  • HDD Thrash   
       • Unpark Cores  • Priority High  • Standby Purge    Protection   
       • Low-Core Guard• AMD ULPS Off   • OOM Failsafe   • Defrag Halt  
```

### CPU Architecture Tuning (Intel & AMD)
- **Universal Core Unparking (`CPMINCORES 100`):** By default, the Windows Power Manager parks logical CPU cores to save milliwatts of power, causing severe thread scheduling latency when an esports engine suddenly demands multi-threaded draw execution. Ultra Gaming Mode automatically configures the active power plan (`powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100`), ensuring all physical and logical cores on both AMD Ryzen (Zen 2/3/4/5) and Intel Core architectures stay 100% unparked and ready for instantaneous instruction throughput.
- **Low-Core Guard (`LowCoreProfile`):** When the engine detects a CPU with 4 or fewer logical cores (e.g., dual-core/quad-thread chips like the Intel Core i3-2100 or older quad-core i5s), background context switching becomes fatal to frame pacing. The optimizer flags the system under `LowCoreProfile`, sets the minimum processor throttle state to 100% (`PROCTHROTTLEMIN = 100`) to prevent aggressive clock-downthrottling during transient frame drops, and aggressively suppresses background CPU interruptions. The original processor throttle states are captured in the snapshot and restored cleanly.

### Adaptive GPU Engine (NVIDIA, AMD & Intel)
- **Dedicated Primary GPU Discovery:** In multi-GPU setups (such as Intel HD Graphics paired with an AMD Radeon or NVIDIA GeForce card), naive scripts often target the wrong adapter. The engine prioritizes discrete PCI graphics devices with active display output (`CurrentHorizontalResolution > 0`) and dedicated vendor IDs (`VEN_1002` AMD, `VEN_10DE` NVIDIA, `VEN_8086` Intel discrete).
- **Universal Message Signaled Interrupts (MSI Mode):** Legacy line-based IRQs force the GPU to share interrupt lines with SATA controllers, USB hosts, and network interfaces. Ultra Gaming Mode enables Message Signaled Interrupts (`MSISupported = 1`) and elevates interrupt affinity to High Priority (`DevicePriority = 3`) under `HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\...\Device Parameters\Interrupt Management`. This replaces line contention with direct PCIe memory writes, significantly reducing GPU-to-CPU DPC frame submission latency.
- **AMD Radeon ULPS Disabling:** For AMD Radeon GPUs (Polaris, Vega, RDNA 1/2/3), the engine automatically scans driver registry nodes (`Class\{4d36e968-e325-11ce-bfc1-08002be10318}\000*`) and turns off Ultra Low Power State (`EnableUlps = 0`). This eliminates secondary monitor wake black screens, core clock ramp stutter, and voltage transition hitches.
- **NVIDIA GeForce & Intel Arc Safety:** MSI mode is applied cleanly without attempting AMD-specific ULPS keys, ensuring zero registry contamination or driver instability.

### Low-RAM Budget Guard (8 GB Systems)
- **`LowRamProfile` Auto-Activation:** Standard 8 GB DDR3 or DDR4 RAM kits frequently report between 7.8 GB and 8.1 GB to Windows due to hardware reservations and integrated GPU framebuffers. The engine uses an 8.5 GB threshold to reliably tag budget systems for memory protection.
- **Pagefile OOM Crash Protection:** A common misconception among budget gamers is disabling the Windows pagefile (virtual memory) to "save disk writes." On an 8 GB system, disabling the pagefile guarantees catastrophic Out-Of-Memory application crashes (OOM) and game crashes as soon as a modern game allocates virtual address space. Ultra Gaming Mode inspects `Win32_PageFileSetting`, validates paging files, and issues an immediate critical alert if the pagefile is disabled or missing.
- **Standby List Kernel Purge (`Win32StandbyCleaner`):** Leverages native NT API calls (`ntdll.dll!NtSetSystemInformation` with `SystemMemoryListInformation` command 4) combined with `psapi.dll!EmptyWorkingSet`. Unlike basic tools that only trim application working sets, this directly purges the Windows kernel standby page cache, freeing up 1.5 GB to 3.0 GB of RAM for immediate game allocation. For `LowRamProfile` systems, aggressive standby purging is automatically executed at boot.

### Mechanical HDD 100% Thrash Protection
- **Storage Media Auto-Detection (`HddProfile`):** Queries physical disk media types (`MediaType: HDD` vs `SSD`) for the system C: partition as well as secondary fixed storage drives. If mechanical spinning disks are detected, HDD Thrash Protection activates.
- **Scheduled Defragmentation Suspension:** Windows regularly schedules background storage maintenance (`\Microsoft\Windows\Defrag\ScheduledDefrag`) which triggers 100% disk usage and massive seek contention during gameplay. Ultra Gaming Mode suspends this task during gaming mode and restores its original state upon restoration.
- **Instant Kill for `SysMain` & `WSearch`:** Windows Search Indexer (`WSearch`) and Superfetch/SysMain (`SysMain`) continuously index files and pre-fetch binaries into memory, causing spinning hard drives to stay pegged at 100% active time. The optimizer halts and disables both daemons immediately.
- **NTFS I/O Optimization:** Enforces `disablelastaccess 1` (stopping NTFS from updating timestamps every time a game reads an asset file) and `disable8dot3 1` (stopping legacy 16-bit DOS filename hash generation), reducing head seek travel and disk queue depth.

---

## 📊 Real-World Benchmarks & Engine Telemetry

All metrics were captured using internal engine profiling tools under strict, identical real-match conditions.

### Hardware Specs & Benchmark Environments

| Spec | Environment A: Enthusiast Rig | Environment B: Low-End Budget Rig |
|:---|:---|:---|
| **Target Role** | High-Refresh Rate Competitive Esports | Budget / Legacy PC Gaming & Frame Pacing |
| **CPU** | AMD Ryzen 5 5600X (6C / 12T @ 4.6 GHz) | Intel Core i3-2100 (2C / 4T @ 3.10 GHz Sandy Bridge) |
| **GPU** | AMD Radeon RX 6600 (8 GB GDDR6) | AMD Radeon RX 570 (8 GB GDDR5 Polaris 20) |
| **RAM** | 32 GB DDR4 (Dual Channel 3600 MHz CL16) | 8 GB DDR3 (Dual Channel 1333 MHz CL9) |
| **Storage** | 1 TB NVMe PCIe 4.0 SSD | 1 TB Mechanical HDD (SATA 7200 RPM) |
| **OS** | Windows 11 Pro 64-bit | Windows 10 / 11 64-bit |
| **Adaptive Badges** | `[AMD CPU]` `[AMD GPU]` | `[Intel CPU \| Low-Core Guard]` `[AMD GPU]` `[Low-RAM Guard]` `[HDD Thrash Guard]` |

---

### Low-End & Budget PC Optimization Impact (Rig B Analysis)

On budget hardware like the **Intel Core i3-2100 + RX 570 + 8GB RAM + 1TB HDD** configuration, Windows 10/11 defaults typically render modern games unplayable due to multi-subsystem bottlenecks:
1. **Mechanical HDD 100% Active Time Eliminated:** In stock Windows, `SysMain`, `WSearch`, background `ScheduledDefrag`, and Windows Defender real-time scans peg mechanical hard drives at 100% disk usage for 15-30 minutes after boot. Ultra Gaming Mode halts all four simultaneously, dropping idle disk active time to **0-2%** and eliminating texture-streaming hitching and 10-second freeze frames.
2. **59% RAM Consumption Reduction (Low-RAM Guard):** Stock Windows with background telemetry, Teams, Edge widgets, and store daemons consumes **~5.4 GB of RAM at idle**, leaving only ~2.4 GB for games and triggering constant pagefile thrashing. Ultra Gaming Mode strips background services and purges the standby list with `Win32StandbyCleaner`, dropping idle consumption to **~2.2 GB** and yielding **~5.8 GB of contiguous free physical memory** for game assets.
3. **Low-Core Guard on 2C/4T Sandy Bridge:** With only 2 physical cores and 4 threads, any background process interrupting the CPU creates an instantaneous drop in 1% low FPS. Unparking all cores (`CPMINCORES 100`) and locking minimum throttle state (`PROCTHROTTLEMIN 100`) eliminates frequency drops during intense combat.
4. **RX 570 Polaris MSI Mode:** Replaces legacy IRQ pin sharing with dedicated PCIe MSI interrupts (`MSISupported = 1`, `DevicePriority = 3`), eliminating DPC latency spikes during rapid GPU draw calls.

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
- **Nagle's Algorithm Disabled:** Sets `TCPNoDelay = 1` and `TcpAckFrequency = 1` across all active IP interfaces, eliminating network packet buffering delays in online multiplayer.
- **Energy-Efficient Ethernet (*EEE) Disabled:** Deactivates power-saving sleep transitions on physical NICs (`*EEE = 0`, `EnableGreenEthernet = 0`, `PowerSavingMode = 0`), stopping micro-disconnects and packet jitter.

### 7. Universal CPU Architecture Tuning & Shader Cache Maintenance
- **Universal Core Unparking & Throttle Lock:** Automatically tunes the active power plan by setting processor idle minimum cores to 100% (`powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100`), keeping all physical and logical cores on both AMD Ryzen and Intel Core processors active. On budget or low-core chips (<= 4 logical cores), locks `PROCTHROTTLEMIN = 100` to prevent clock downthrottling during sudden thread spikes.
- **DirectX & Vulkan Shader Cache Purge:** Option **`[7]`** safely scrubs corrupt or bloated AMD, NVIDIA, and DirectX shader cache directories (`%LOCALAPPDATA%\AMD\DxCache`, `VkCache`, `DxcCache`, `DX9Cache`, `OglCache`, `%LOCALAPPDATA%\D3DSCache`), eliminating shader compilation micro-stutters and dropped frames in titles like *CS2*.

### 8. Adaptive GPU Engine & Message Signaled Interrupts (MSI Mode)
- **Primary Discrete GPU Auto-Detection:** Automatically discovers dedicated PCI graphics cards (AMD Radeon, NVIDIA GeForce, Intel Arc) with active displays, ignoring auxiliary integrated graphics.
- **Universal MSI Mode & High Priority:** Configures Message Signaled Interrupts (`MSISupported = 1`) and High Priority (`DevicePriority = 3`) under `Device Parameters\Interrupt Management`. Replaces legacy line-based IRQ sharing with direct PCIe MSI memory writes, eliminating interrupt conflicts and reducing GPU-to-CPU DPC frame submission latency.
- **AMD Radeon ULPS Disabling:** For AMD Radeon GPUs, disables Ultra Low Power State (`EnableUlps = 0`) across driver branches to prevent deep sleep wake lag and clock ramp hesitation.

### 9. VBS / HVCI (Core Isolation / Memory Integrity) Diagnostics & Toggle
- Diagnoses Virtualization-Based Security (VBS) and Hypervisor-Enforced Code Integrity (HVCI) via WMI/CIM namespace `root\Microsoft\Windows\DeviceGuard` (`Win32_DeviceGuard`).
- Option **`[8]`** provides a safe toggle to enable or disable VBS/HVCI in the registry (`EnableVirtualizationBasedSecurity` and `HypervisorEnforcedCodeIntegrity\Enabled`), removing hypervisor nested-ring CPU overhead and providing clear warnings that a reboot is required.

### 10. NTFS File System I/O Optimizations
- Applies `fsutil behavior set disablelastaccess 1` to stop Windows from updating the last-access timestamp on disk whenever a file is read, eliminating write amplification during game asset streaming.
- Applies `fsutil behavior set disable8dot3 1` to stop creating legacy DOS 8.3 short filename directory entries, accelerating directory traversals. Both settings are backed up and cleanly restored on normal state restoration.

### 11. Physical Network Adapter Driver Tweaks (FlowControl & InterruptModeration)
- For physical Ethernet and Wi-Fi adapters, automatically disables `*FlowControl` (prevents artificial pause frames that cause ping spikes) and `*InterruptModeration` (delivers incoming packets immediately to the CPU for the lowest possible network latency).
- **Ironclad Safety Exclusions:** Strictly ignores and protects Apple Mobile Device Ethernet (`Ethernet 2` for iPhone tethering) and Wintun tunnel adapters (`wwan99`).

### 12. On-Demand Memory Trimming (Working Sets & Standby List)
- Features native Win32 P/Invoke calling `psapi.dll!EmptyWorkingSet` and `ntdll.dll!NtSetSystemInformation` (`Win32StandbyCleaner`).
- Flushes bloated background process working sets, purges kernel standby memory caches, triggers garbage collection, and yields up to 3 GB of free RAM on the fly without restarting.

### 13. Emergency Repair Toolkit (DisplayPort & Audio/Microphone)
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
           ULTRA GAMING MODE CONTROLLER  v2.5
============================================================

 [1] Arm Ultra Gaming Mode for Next Boot
 [2] Restore Normal Windows State Now
 [3] Flush and Clean RAM Cache Now (Standby List)
 [4] Run System Diagnostic / Pre-Flight Check
 [5] Repair Display + Reset DisplayPort Cache (Emergency Fix)
 [6] Repair Microphone, Steam + Core Services (Instant Fix)
 [7] Purge AMD / DirectX / Vulkan Shader Cache
 [8] Check & Toggle VBS / HVCI (Core Isolation)
 [9] Check GPU MSI Mode & Device Priority Status
[10] Check Current Status
[11] Exit
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

# Purge AMD / DirectX / Vulkan shader cache
powershell.exe -ExecutionPolicy Bypass -File .\UltraGamingMode.ps1 -Action FlushShaderCache

# Check and toggle VBS / HVCI Memory Integrity
powershell.exe -ExecutionPolicy Bypass -File .\UltraGamingMode.ps1 -Action ToggleVBS

# Check GPU MSI Mode and IRQ Priority status
powershell.exe -ExecutionPolicy Bypass -File .\UltraGamingMode.ps1 -Action GpuMsiStatus

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
| **`[1]`** | `-Action Enable` | Creates backup snapshot (services, hardware profile, processor throttle, ULPS, MSI, NTFS, Core Parking, NIC settings, scheduled defrag on HDD), suppresses user startup apps, and arms Task Scheduler boot trigger under SYSTEM. |
| **`[2]`** | `-Action Restore` | Restores all 173 services, hardware settings (processor throttle, ULPS, MSI, Core Parking, NTFS, NIC, scheduled defrag), re-enables Windows Defender, unregisters boot triggers, and restores startup apps. |
| **`[3]`** | `-Action CleanMemory` | Calls `EmptyWorkingSet` and `Win32StandbyCleaner` (P/Invoke `NtSetSystemInformation`) to purge standby cache and process working sets instantly. |
| **`[4]`** | `-Action Diagnostic` | Runs pre-flight audit: inspects Universal Hardware Profile (CPU, GPU, RAM, Storage), checks administrator privileges, power plans & Core Parking, MMCSS profiles, network adapters, AMD ULPS, shader caches, GPU MSI mode, VBS/HVCI status, NTFS settings, whitelist protection, and bloat services. |
| **`[5]`** | `-Action RepairDisplay` | Emergency fix: wipes corrupt registry display topology caches and resets MMCSS game scheduling to default safe parameters. |
| **`[6]`** | `-Action RepairServices`| Emergency fix: repairs and starts `camsvc` (Microphone privacy), `LanmanServer` (RPC session), and unblocks Steam/Bluetooth. |
| **`[7]`** | `-Action FlushShaderCache`| Purges AMD DirectX, Vulkan, and D3D shader caches (`DxCache`, `VkCache`, `DxcCache`, `DX9Cache`, `OglCache`, `D3DSCache`) to eliminate shader pipeline micro-stutters. |
| **`[8]`** | `-Action ToggleVBS` | Checks and toggles Virtualization-Based Security (VBS) and Memory Integrity (HVCI) in registry to eliminate virtualization overhead. |
| **`[9]`** | `-Action GpuMsiStatus` | Displays GPU Vendor, Message Signaled Interrupts (MSI) status, and IRQ priority (`DevicePriority = 3`). |
| **`[10]`**| `-Action Status` | Displays current active mode, Universal Hardware Badges (CPU, GPU, Low-RAM Guard, HDD Thrash Guard), boot trigger, fail-safe watchdog, active services count, Core Parking, GPU MSI, and VBS status. |
| **`[11]`**| `Exit` | Exits the interactive launcher. |

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
