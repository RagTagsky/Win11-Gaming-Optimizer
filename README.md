<div align="center">

# ⚡ Ultra Gaming Mode for Windows 11
### *Native Desktop GUI · Competitive Low-Latency · Universal Hardware Edition (v3.6.0)*

**A zero-risk, snapshot-driven kernel latency, frame pacing, and hardware optimizer for Windows 10 & 11.**  
Built with **Tauri v2 (Rust) + Svelte 5** and a native **Win32 / PowerShell Engine** — featuring simplified 2-mode Services & Processes controls with hover safety tooltips, zero-RAM tray mode, elevated Task Scheduler autostart, 1-click service quick presets, automatic `0.500 ms` timer resolution, smart background Standby RAM auto-purge, and a 100% crash-proof `HKLM\RunOnce` failsafe watchdog.

[![Release](https://img.shields.io/badge/Release-v3.6.0-2563EB?style=for-the-badge&labelColor=0F172A)](https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases/latest)
[![Platform](https://img.shields.io/badge/Windows-11%20%7C%2010%20(x64)-2563EB?style=for-the-badge&logo=windows&logoColor=white&labelColor=0F172A)](https://www.microsoft.com/windows)
[![Desktop Stack](https://img.shields.io/badge/Tauri%20v2-Rust%20%2B%20Svelte%205-3B82F6?style=for-the-badge&logo=rust&logoColor=white&labelColor=0F172A)](#option-a-native-desktop-gui-app-v360---recommended)
[![Watchdog](https://img.shields.io/badge/Failsafe-HKLM%20RunOnce-10B981?style=for-the-badge&labelColor=0F172A)](#the-zero-risk-watchdog-guarantee)
[![Anti-Cheat Safe](https://img.shields.io/badge/Anti--Cheat-FACEIT%20%7C%20Vanguard%20%7C%20EAC%20%7C%20VAC-10B981?style=for-the-badge&labelColor=0F172A)](#2-ironclad-whitelist-95-protected-services)
[![Test Suite](https://img.shields.io/badge/Verified-82%20PS%20%2B%2025%20Rust%20Tests-475569?style=for-the-badge&labelColor=0F172A)](#directory-structure)
[![License: MIT](https://img.shields.io/badge/License-MIT-475569?style=for-the-badge&labelColor=0F172A)](LICENSE)

<br />

[**🚀 Quick Start**](#quick-start-guide) · [**📊 CS2 Benchmarks**](#real-world-benchmarks-engine-telemetry) · [**🛠️ Hardware Engine**](#universal-hardware-auto-detection-engine) · [**🛡️ Watchdog Lifecycle**](#core-architecture-lifecycle) · [**🔬 19 Technical Modules**](#deep-technical-features) · [**⌨️ CLI Reference**](#menu-overview-cli-reference)

**Language:** [**🇺🇸 English**](README.md) · [**🇷🇺 Русский**](README.ru.md)

</div>

---

## ✨ Architecture at a Glance

| 🖥️ Native Desktop & Zero-RAM Tray | ⚡ Kernel, Input & Network Latency | 🛠️ Universal Hardware Adaptation | 🛡️ Zero-Risk Snapshot Watchdog |
|:---|:---|:---|:---|
| • **Tauri v2 + Rust + Svelte 5** Fluent UI<br>• **Zero-RAM Tray Mode**: closing `[×]` unloads WebView2 (`0 MB` UI RAM)<br>• **Elevated Autostart** (`--tray`) via Task Scheduler without UAC prompts<br>• **SHA-256 Verified Updater** directly from GitHub Releases | • **Auto `0.500 ms` Timer Lock** in Gaming Mode (`NtSetTimerResolution`)<br>• **GPU & PCIe NIC MSI Mode** (`DevicePriority = 3`)<br>• **Winsock AFD 64 KB Fast-Path** & Nagle off<br>• **High-Polling Input Buffer** (`32–1024` packets, 8000 Hz safe) | • **CPU Unparking** (`CPMINCORES 100`) & Low-Core Guard (`<= 4` threads)<br>• **Discrete GPU Discovery** (AMD ULPS/DXNAVI, NVIDIA Per-Core DPC, Intel Arc)<br>• **Low-RAM Guard (8 GB)** + native `NtSetSystemInformation` Standby Purge<br>• **Mechanical HDD 100% Thrash Guard** | • Full pre-flight JSON snapshot (`Backups\active_state.json`)<br>• Autonomous `HKLM\RunOnce` kernel watchdog (`*UltraGamingModeRestore`)<br>• **95 Protected Whitelist Services** (`FACEIT`, `vgk`, `EAC`, `zapret`, `camsvc`, `PrtSc`)<br>• 1-Click Emergency DisplayPort & Audio Repair |

> [!TIP]
> **What's New in v3.6.0:**
> - **Simplified 2-Mode Services & Processes UI:** Replaced nested sub-tabs, 9 categories, manual Start/Stop menus, and the separate Windows Startup sub-tab with one unified list for **Services** (running services on top + compact quick presets bar) and one unified list for **Processes** (running processes + configured offline rules). Every non-protected item has a clear 2-choice toggle: **«Без утилки»** (runs normally and keeps autostart intact) or **«Выкл. в Gaming Mode»** (temporarily suspended in Gaming Mode and restored on exit).
> - **Hover & Keyboard Safety Tooltips for Every Service and Process:** Hovering or focusing any row opens a compact tooltip card explaining what the item does in plain Russian, a color-coded verdict (🟢 `Можно выключить` · 🟡 `По желанию` · 🔴 `Нельзя выключать`), and the impact of disabling it — backed by 328 curated service descriptions, 181 curated process descriptions (`Config/process_descriptions.json`), and automatic fallbacks to Windows SCM descriptions (`QueryServiceConfig2W`) and `.exe` version metadata.
> - **Canonical Service Matching, Strict User Choice & Zapret DPI Bypass Protection:** Both the Rust backend and PowerShell engine canonicalize per-user `_LUID` and dynamic 4-part updater suffixes (`GoogleUpdaterService*`), strictly respect user rules for `SysMain`, `WSearch`, `WSAIFabricSvc`, and `Widgets`, and protect **Zapret** (`zapret`, `WinDivert`, `WinDivert14`, `winws`/`winws2`, autostart entries, and automatic preservation of `TCP timestamps=enabled`) alongside OS core, anti-cheats (`FACEIT`, `vgk`, `EAC`), and game clients.

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
  - [1. Targeted Service Blacklist (205 Services)](#1-targeted-service-blacklist-205-services)
  - [2. Ironclad Whitelist (95 Protected Services)](#2-ironclad-whitelist-95-protected-services)
  - [3. Temporary Windows Defender Suspension](#3-temporary-windows-defender-suspension)
  - [4. Background Process & Bloatware Annihilator](#4-background-process-bloatware-annihilator)
  - [5. Windows 11 Widgets & Bing Search Elimination](#5-windows-11-widgets-bing-search-elimination)
  - [6. Network & Latency Kernel Optimizations](#6-network-latency-kernel-optimizations)
  - [7. Universal CPU Architecture Tuning & Shader Cache Maintenance](#7-universal-cpu-architecture-tuning--shader-cache-maintenance)
  - [8. Adaptive GPU Engine & Message Signaled Interrupts (MSI Mode)](#8-adaptive-gpu-engine--message-signaled-interrupts-msi-mode)
  - [9. VBS / HVCI (Core Isolation / Memory Integrity) Diagnostics & Toggle](#9-vbs--hvci-core-isolation--memory-integrity-diagnostics--toggle)
  - [10. NTFS File System I/O Optimizations](#10-ntfs-file-system-io-optimizations)
  - [11. Physical Network Adapter Driver Tweaks (FlowControl, InterruptModeration & MSI Mode)](#11-physical-network-adapter-driver-tweaks-flowcontrol-interruptmoderation--msi-mode)
  - [12. On-Demand Memory Trimming (Working Sets & Standby List)](#12-on-demand-memory-trimming-working-sets--standby-list)
  - [13. Emergency Repair Toolkit (DisplayPort & Audio/Microphone)](#13-emergency-repair-toolkit-displayport--audiomicrophone)
  - [14. Kernel DPC Execution & Executive Memory Tuning](#14-kernel-dpc-execution--executive-memory-tuning)
  - [15. Direct Peripheral Input Queues (Mouse & Keyboard)](#15-direct-peripheral-input-queues-mouse--keyboard)
  - [16. BCDedit System Timer Synchronization](#16-bcdedit-system-timer-synchronization)
  - [17. High-Performance TCP Gaming Stack](#17-high-performance-tcp-gaming-stack)
  - [18. Hardware-Accelerated GPU Scheduling (HAGS)](#18-hardware-accelerated-gpu-scheduling-hags)
  - [19. Competitive Frame Pacing, Ring-0 IFEO & Top-Tier Optimizations (v3.6.0)](#19-competitive-frame-pacing-ring-0-ifeo--top-tier-optimizations-v360)
- [Quick Start Guide](#quick-start-guide)
  - [Option A: Native Desktop GUI App (v3.6.0 - Recommended)](#option-a-native-desktop-gui-app-v360---recommended)
  - [Option B: Interactive TUI Menu](#option-b-interactive-tui-menu)
  - [Option C: PowerShell CLI Usage](#option-c-powershell-cli-usage)
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

**Ultra Gaming Mode v3.6.0** solves this without permanently mangling your operating system. Unlike brittle "debloater" scripts that break Windows Update, brick microphone privacy permissions, or cause black screens on DisplayPort monitors, Ultra Gaming Mode utilizes a **non-destructive, snapshot-driven lifecycle**:

```
[Normal Windows] ──(Arm Mode)──> [System Snapshot] ──(Reboot)──> [Stripped Ultra Gaming Mode]
       ▲                                                                   │
       │                                                                   │
       └───────────────────(Failsafe Watchdog / Restore)───────────────────┘
```

---

## 🛠️ Universal Hardware Auto-Detection Engine

Ultra Gaming Mode v3.6.0 features an autonomous hardware discovery engine (`Get-HardwareProfile`) that inspects your machine's physical architecture during diagnostic checks, arming, and boot stages. Rather than applying blunt, one-size-fits-all tweaks, the optimizer detects exact CPU topologies, GPU bus interfaces, physical memory limits, and storage media types to dynamically tailor kernel and driver optimizations to your exact PC.

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

| Metric | Stock Windows 11 | Ultra Gaming Mode v3.5.1 | Delta / Gain | Real-World Impact |
|:---|:---:|:---:|:---:|:---|
| **Average FPS (`FPS: Avg`)** | **443.8 FPS** | **477.1 FPS** | **+33.3 FPS (+7.5%)** | **Higher sustained throughput across identical 121s benchmark run** |
| **Total Rendered Frames (`121s`)** | **53,636** | **57,504** | **+3,868 frames (+7.2%)** | More frames delivered to display over the same match window |
| **Average FrameTime (`FrameTotal Avg`)** | **2.25 ms** | **2.10 ms** | **-0.15 ms (-6.7%)** | Lower baseline rendering and scheduling overhead per frame |
| **1s Max FrameTime (`FrameTotal P50 / P95`)** | **6.23 / 8.64 ms** | **5.57 / 8.28 ms** | **-0.66 ms (-10.6%)** | **10.6% tighter median 1-second worst-frame spikes** |
| **Present_RenderDevice (`1s max P95`)** | **4.23 ms** | **2.57 ms** | **-1.66 ms (-39.2%)** | **39.2% lower display swapchain & input presentation spikes** |
| **Present_RenderDevice (`All frames P99`)** | **1.43 ms** | **1.16 ms** | **-0.27 ms (-18.9%)** | **18.9% faster 99th-percentile frame presentation to monitor** |
| **Frame Boundary (`1s max P95` Sync Spikes)** | **5.78 ms** | **3.67 ms** | **-2.11 ms (-36.5%)** | **36.5% spike reduction — eliminates CPU thread sync stalls** |
| **Frame Boundary (`All frames P99`)** | **2.11 ms** | **1.91 ms** | **-0.20 ms (-9.5%)** | Cleaner frame-to-frame handoff in the kernel scheduler |
| **Client Rendering (`1s max P95` Render Spikes)** | **6.27 ms** | **4.04 ms** | **-2.23 ms (-35.6%)** | **35.6% smoother draw call pipeline during heavy utility/smokes** |
| **Client Rendering (`All frames P99`)** | **2.44 ms** | **2.22 ms** | **-0.22 ms (-9.0%)** | More consistent 99th-percentile GPU draw submission |
| **Client Simulation (`All frames P99`)** | **1.01 ms** | **0.88 ms** | **-0.13 ms (-12.9%)** | Faster client-side entity and physics state updates |
| **ClientSimulateTick (`1s max P95`)** | **0.84 ms** | **0.72 ms** | **-0.12 ms (-14.3%)** | Tighter client sub-tick simulation consistency |
| **Networking (`Active P99`)** | **0.57 ms** | **0.45 ms** | **-0.12 ms (-21.1%)** | **21.1% faster packet processing via Winsock AFD & NDIS RSS** |
| **Server Simulation (`1s max P95`)** | **3.53 ms** | **3.33 ms** | **-0.20 ms (-5.7%)** | Lower local server tick processing spikes |
| **Panorama UI Text (`PanoramaTextPango P99`)** | **0.43 ms** | **0.24 ms** | **-0.19 ms (-44.2%)** | **44.2% faster HUD, killfeed & text compositing latency** |

### Key Takeaways
1. **-39.2% Display Swapchain (`Present_RenderDevice`) & -36.5% Frame Boundary Spikes:** P95 1-second presentation spikes dropped from `4.23 ms` to `2.57 ms` and thread synchronization spikes dropped from `5.78 ms` to `3.67 ms`, directly translating to snappier mouse feel and zero micro-stutters.
2. **+33.3 Average FPS (+7.5%) & -35.6% Client Rendering Spikes:** Average framerate climbed from `443.8 FPS` (`53,636` frames) to `477.1 FPS` (`57,504` frames) while P95 render spikes dropped from `6.27 ms` to `4.04 ms`.
3. **-21.1% Networking & -44.2% Panorama HUD Latency:** Active P99 network packet processing dropped from `0.57 ms` to `0.45 ms` and Panorama UI text rendering dropped from `0.43 ms` to `0.24 ms`.

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
                  | - Strips 205 Blacklist Services       |
                  | - Pauses Defender Real-Time Scans     |
                  | - Peripheral Input Queues (>=32-100)  |
                  | - Kernel DPC & Executive Memory Tune  |
                  | - BCDedit Timer & TSC Synchronization |
                  | - TCP & Winsock AFD Fast-Path (64KB)  |
                  | - Hardware-Accelerated GPU Sched(HAGS)|
                  | - Tunes Network (*EEE, NIC MSI Mode)  |
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
                  | - Input Queues restored (100 packets) |
                  | - Kernel DPC & Paging Exec restored   |
                  | - BCDedit Dynamic Tick & TSC restored |
                  | - TCP & Winsock AFD settings restored |
                  | - HAGS GPU scheduling restored        |
                  | - Widgets, Search & Startup Restored  |
                  +---------------------------------------+
```

### The Zero-Risk Watchdog Guarantee
Unlike other tweak scripts that leave your operating system in an unrecoverable state if your machine crashes, Ultra Gaming Mode implements a hardware-grade fail-safe:
1. **State Snapshots (`Backups\active_state.json`):** Before touching a single registry key or service, every service's exact startup mode (`Manual`, `Auto`, `Disabled`), user startup shortcuts, UWP app flags, network configs, hardware profile, processor throttle states, ULPS, GPU & NIC MSI Mode, NTFS, Core Parking, NIC settings, scheduled defrag, Kernel DPC config, Input Buffer config, BCDedit timer config, TCP stack config, Extended Registry snapshots, and HAGS GPU scheduling config are stored in a structured JSON snapshot.
2. **`HKLM\RunOnce` Kernel Watchdog:** An autonomous watchdog is registered in `HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce` named `*UltraGamingModeRestore`.
3. **Crash-Proof Reversion:** If your PC unexpectedly crashes, loses power, or you simply reboot when your match finishes, Windows runs the watchdog on the next logon. It detects the reboot, unpacks `active_state.json`, and completely restores every service, timer, queue, and driver setting back to normal.
---

## 🔬 Deep Technical Features

### 1. Targeted Service Blacklist (205 Services)
Carefully compiled to remove all background context switching without compromising system integrity:
- **Telemetry & Diagnostics:** `DiagTrack`, `dmwappushservice`, `DPS` (Diagnostic Policy Service), `wmiApSrv`, `pla` (Performance Logs), `TroubleshootingSvc`, `wuqisvc`, `WSAIFabricSvc` (Windows AI Fabric).
- **Hyper-V & Remote Desktop:** `TermService`, `SessionEnv`, `UmRdpService`, `WinRM`, `HvHost`, all `vmic*` Guest Integration services, `MSiSCSI`, `SNMPTrap`, `RpcLocator`.
- **Backup & File History:** `fhsvc` (File History), `wbengine` (Block Level Backup), `SDRSVC` (Windows Backup), `CloudBackupRestoreSvc`, `OneSyncSvc`.
- **Print & Scanners:** `Spooler`, `PrintNotify`, `PrintScanBrokerService`, `PrintDeviceConfigurationService`, `PrintWorkflowUserSvc`, `StiSvc` (WIA), `Fax`, `WiaRpc`.
- **Bluetooth (Selective):** `bthserv`, `BthAvctpSvc`, `BTAGService`, `BluetoothUserService` (can be instantly restored if Bluetooth controller is needed).
- **Xbox & Microsoft Store Background Daemons:** `ClipSVC`, `LicenseManager`, `AppXSvc`, `GamingServices`, `GamingServicesNet`, `XblAuthManager`, `XblGameSave`, `XboxGipSvc`, `XboxNetApiSvc`, `InstallService`, `PushToInstall`.
- **Windows 11 Per-User Template Services:** `BcastDVRUserService` (GameDVR broadcast buffer), `DevicePickerUserSvc`, `DevicesFlowUserSvc`, `DeviceAssociationBrokerSvc`, `SmsRouter`, `MessagingService`, `PenService`, `UserDataSvc`, `UnistoreSvc`, `NPSMSvc`.
- **Search & Caches:** `WSearch` (Windows Search Indexer), `SysMain` (Superfetch).
- **Updates & Background Downloaders:** `wuauserv`, `bits`, `dosvc`, `UsoSvc`, `WaaSMedicSvc`, `edgeupdate`, `edgeupdatem`, `gupdate`, `gupdatem`, `GoogleUpdaterService`.
- **Hotspot, Cellular & Geolocation:** `icssvc`, `autotimesvc`, `lfsvc`, `WFDSConMgrSvc`.
- **Third-Party Background Bloat:** `EABackgroundService` (EA App telemetry), `LibreOfficeMaintenance`.

### 2. Ironclad Whitelist (95 Protected Services)
The optimizer strictly checks every operation against an inviolable whitelist:
- **Ultra-Low Latency Input:** `GameInputSvc` (Windows 11 GameInput API), `hidserv` (HID input stack preserving 1,000 Hz, 4,000 Hz, and 8,000 Hz mouse polling and macros), `TextInputManagementService` (keyboard engine & in-game chat typing).
- **Snipping Tool (`PrtSc`) & Clipboard Protection:** `CaptureService`, `cbdhsvc` (Clipboard User Service), `CDPUserSvc`, `ConsentUxUserSvc`, `UdkUserSvc` — strictly protected (including per-user `_xxxxx` suffixed instances) so screenshots and clipboard history work seamlessly during gameplay.
- **Audio & Microphone Security:** `Audiosrv`, `AudioEndpointBuilder`, `camsvc` (**Capability Access Manager Service** — protects microphone privacy permissions so Discord, Steam, and in-game voice never get blocked), `ApxSvc`, `QWAVE`.
- **Network & Mobile Tethering:** `Dhcp`, `Dnscache`, `LanmanWorkstation`, `NlaSvc`, `netprofm`, `Wcmsvc`, `Netman`, `nsi`, `Apple Mobile Device Service` (guarantees iPhone USB tethering on Ethernet 2 remains 100% active).
- **Anti-Cheat Kernels & Launchers:** `Steam Client Service`, `vgk`, `vgc` (Riot Vanguard), `EasyAntiCheat`, `BEService` (BattlEye).
- **Display & Hardware Drivers:** `AMD External Events Utility` (FreeSync), `GraphicsPerfSvc`, `DisplayEnhancementService`, `DispBrokerDesktopSvc`, `ProcessGovernor` (Process Lasso).
- **Core Security & UAC:** `Appinfo` (UAC privilege escalation), `StateRepository`, `UserManager`, `TokenBroker`, `Schedule`, `TimeBrokerSvc`, `Winmgmt`.

### 3. Temporary Windows Defender Suspension
- When Ultra Gaming Mode boots, Windows Defender Real-Time Protection is temporarily set to bypass (`DisableRealtimeMonitoring = 1`, `DisableBehaviorMonitoring = 1`, `DisableIOAVProtection = 1`, `DisableScriptScanning = 1`).
- Eliminates synchronous disk I/O hooks during map loading and model streaming.
- Restores automatically on normal reboot or when running Option [2].

### 4. Background Process & Bloatware Annihilator
- **Terminated on Launch:** Web browsers (`firefox`, `chrome`, `msedge`), `Telegram`, `Discord`, `Spotify`, `EpicGamesLauncher`, `CrossDeviceResume` (Phone Link), AMD screen record overlays (`amdow`, `AMDRSServ`), taskbar widgets (`Widgets`), cloud sync clients (`GoogleDriveFS`), background store updaters.
- **Strictly Protected:** The active game, **Steam**, **FACEIT Client**, AMD Radeon display driver (`atieclxx`), **MSI Afterburner / RivaTuner Statistics Server**, **Process Lasso** (`ProcessGovernor`), **Apple Mobile Device Service** (USB Tethering), Windows 11 Start Menu Search (`SearchHost`, `TextInputHost`), and WebView2 renderers belonging to Ultra Gaming Mode (`UltraGamingMode.exe`).
- **Origin-Segregated Startup Shortcut Quarantine:** Startup folder shortcuts (`.lnk`, `.url`) from both user (`AppData\...\Startup`) and system (`ProgramData\...\Startup`) are quarantined into dedicated origin folders (`Backups\QuarantinedShortcuts\User` and `Backups\QuarantinedShortcuts\ProgramData`). Uses PowerShell `-LiteralPath` to prevent wildcard syntax errors when filenames contain brackets (e.g. `Game [Modded].lnk`), and restores them to their exact origin folders with zero name collisions.

### 5. Windows 11 Widgets & Bing Search Elimination
- Disables Windows 11 News & Interests taskbar widgets (`TaskbarDa = 0`, `AllowNewsAndInterests = 0`), which immediately kills up to 6 hidden background `msedgewebview2.exe` processes.
- Disables Bing online search recommendations inside the Start Menu (`BingSearchEnabled = 0`, `DisableSearchBoxSuggestions = 1`), saving CPU cycles on desktop interactions.

### 6. Network & Latency Kernel Optimizations
- **Nagle's Algorithm Disabled:** Sets `TCPNoDelay = 1` and `TcpAckFrequency = 1` across all active IP interfaces, eliminating network packet buffering delays in online multiplayer.
- **Energy-Efficient Ethernet (*EEE) Disabled:** Deactivates power-saving sleep transitions on physical NICs (`*EEE = 0`, `EnableGreenEthernet = 0`, `PowerSavingMode = 0`), stopping micro-disconnects and packet jitter.

### 7. Universal CPU Architecture Tuning & Shader Cache Maintenance
- **Universal Core Unparking & Throttle Lock:** Automatically tunes the active power plan by setting processor idle minimum cores to 100% (`powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100`), keeping all physical and logical cores on both AMD Ryzen and Intel Core processors active. On budget or low-core chips (<= 4 logical cores), locks `PROCTHROTTLEMIN = 100` to prevent clock downthrottling during sudden thread spikes.
- **DirectX & Vulkan Shader Cache Purge:** Option **`[3]`** in the Advanced Tools menu safely scrubs corrupt or bloated AMD, NVIDIA, and Intel DirectX/Vulkan shader cache across 12 directories (`%LOCALAPPDATA%\AMD\DxCache`, `VkCache`, `DxcCache`, `DX9Cache`, `OglCache`, `%LOCALAPPDATA%\NVIDIA\DXCache`, `GLCache`, `%APPDATA%\NVIDIA\ComputeCache`, `%LOCALAPPDATA%\NVIDIA Corporation\NV_Cache`, `%LOCALAPPDATA%\Intel\ShaderCache`, `Intel\D3DSCache`, `%LOCALAPPDATA%\D3DSCache`), eliminating shader compilation micro-stutters and dropped frames in titles like *CS2*.

### 8. Adaptive GPU Engine & Message Signaled Interrupts (MSI Mode)
- **Primary Discrete GPU Auto-Detection:** Automatically discovers dedicated PCI graphics cards (AMD Radeon, NVIDIA GeForce, Intel Arc) with active displays, ignoring auxiliary integrated graphics.
- **Universal MSI Mode & High Priority:** Configures Message Signaled Interrupts (`MSISupported = 1`) and High Priority (`DevicePriority = 3`) under `Device Parameters\Interrupt Management`. Replaces legacy line-based IRQ sharing with direct PCIe MSI memory writes, eliminating interrupt conflicts and reducing GPU-to-CPU DPC frame submission latency.
- **AMD Radeon ULPS Disabling:** For AMD Radeon GPUs, disables Ultra Low Power State (`EnableUlps = 0`) across driver branches to prevent deep sleep wake lag and clock ramp hesitation.

### 9. VBS / HVCI (Core Isolation / Memory Integrity) Diagnostics & Toggle
- Diagnoses Virtualization-Based Security (VBS) and Hypervisor-Enforced Code Integrity (HVCI) via WMI/CIM namespace `root\Microsoft\Windows\DeviceGuard` (`Win32_DeviceGuard`).
- Option **`[4]`** in the Advanced Tools menu provides a safe toggle to enable or disable VBS/HVCI in the registry (`EnableVirtualizationBasedSecurity` and `HypervisorEnforcedCodeIntegrity\Enabled`), removing hypervisor nested-ring CPU overhead and providing clear warnings that a reboot is required.

### 10. NTFS File System I/O Optimizations
- Applies `fsutil behavior set disablelastaccess 1` to stop Windows from updating the last-access timestamp on disk whenever a file is read, eliminating write amplification during game asset streaming.
- Applies `fsutil behavior set disable8dot3 1` to stop creating legacy DOS 8.3 short filename directory entries, accelerating directory traversals. Both settings are backed up and cleanly restored on normal state restoration.

### 11. Physical Network Adapter Driver Tweaks (FlowControl, InterruptModeration, RSC, WoL & MSI Mode)
- For physical Ethernet and Wi-Fi adapters, automatically disables `*FlowControl` (prevents artificial pause frames that cause ping spikes), `*InterruptModeration` (delivers incoming packets immediately to the CPU for the lowest possible network latency), Receive Segment Coalescing (`*RscIPv4`, `*RscIPv6`), Wake-on-LAN (`*WakeOnMagicPacket`, `*WakeOnPattern`), and Power Management Offloads (`*PMARPOffload`, `*PMNSOffload`) alongside `*EEE`, `EnableGreenEthernet`, and `PowerSavingMode`. All 11 NDIS keywords are snapshotted via a shared mapping and restored cleanly.
- **PCIe Network Adapter MSI Mode (`EnableNetAdapterMsi`):** Automatically switches physical PCIe network controllers (`^PCI\\`) to Message Signaled Interrupts (`MSISupported = 1` under `Device Parameters\Interrupt Management\MessageSignaledInterruptProperties`), eliminating legacy line-based IRQ sharing between the network card and USB/audio controllers.
- **Ironclad Safety Exclusions:** Strictly ignores and protects Apple Mobile Device Ethernet (`Ethernet 2` for iPhone tethering) and Wintun tunnel adapters (`wwan99`).

### 12. On-Demand Memory Trimming (Working Sets & Standby List)
- Features native Win32 P/Invoke calling `psapi.dll!EmptyWorkingSet` and `ntdll.dll!NtSetSystemInformation` (`Win32StandbyCleaner`).
- Flushes bloated background process working sets, purges kernel standby memory caches, triggers garbage collection, and yields up to 3 GB of free RAM on the fly without restarting.

### 13. Emergency Repair Toolkit (DisplayPort & Audio/Microphone)
- **Option [1] DisplayPort Topology & MPO Reset:** Clears corrupt multi-monitor configuration caches in `HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers` (`Configuration`, `Connectivity`, `ScaleFactors`), clears broken MPO/FSE overrides (`OverlayTestMode`, `DisableOverlays`), cleans invalid MMCSS thread priorities (`Affinity = 0`), restarts display services, and forces a clean DisplayPort Link Training handshake.
- **Option [2] Microphone, Search, Snipping Tool & Core Services Unblock:** Instantly resets and starts `camsvc` (fixes microphone access in Discord/CS2), restores Windows Search (`WSearch`), Snipping Tool (`CaptureService`, `cbdhsvc`, `PrintScreenKeyForSnippingEnabled = 1`, AppContainer ACLs), starts `LanmanServer`, and switches `Steam Client Service` and `bthserv` to Demand start.

### 14. Kernel DPC Execution & Executive Memory Tuning
- **Disable Paging Executive (`DisablePagingExecutive = 1`):** Configured under `HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management` on systems with >= 16 GB RAM (automatically skipped on `LowRamProfile` 8 GB systems to preserve physical RAM). Forces Windows kernel-mode drivers and executive code to reside permanently in physical RAM, preventing driver page faults.
- **Threaded DPC Scheduling (`ThreadDpcEnable`):** Preserves optimal Windows 11 threaded DPC execution while cleaning legacy uncached DPC bottlenecks, avoiding `DISPATCH_LEVEL` lockups on modern high-polling USB and audio stacks.
- **Foreground Quantum Priority (`Win32PrioritySeparation = 0x26` / 38 dec):** Configured under `HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl`. Enforces short, variable thread scheduling quantums with a 3:1 foreground execution boost. This gives the focused esports title maximum CPU scheduling preemption over background threads.
- **Disable Power Throttling (`PowerThrottlingOff = 1`):** Configured under `HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling`. Disables Windows EcoQoS energy throttling for game processes, ensuring render threads never suffer artificial CPU frequency downclocking.

### 15. Direct Peripheral Input Queues (Mouse & Keyboard)
- **Configurable High-Polling Safe Input Queues (`InputBufferQueueSize = 100`, Floor `>= 32`):** Configures `MouseDataQueueSize` and `KeyboardDataQueueSize` in `HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters` and `kbdclass\Parameters` via `Config\tuning.json`.
- **Zero-Drop High-Polling Protection:** Competitive mice operating at 1,000 Hz, 4,000 Hz, and 8,000 Hz generate dense interrupt bursts. The engine defaults to `100` packets for zero packet drops and enforces a strict safety floor of `>= 32` packets inside `Set-InputBufferOptimizations`, preventing buffer overflow stutters while keeping input response instantaneous.
- **Optional 1:1 Raw Mouse Curve (`DisableMouseAccel`):** Configurable in `Config\tuning.json` to enforce `MouseSpeed = 0`, `MouseThreshold1 = 0`, and `MouseThreshold2 = 0` under `HKCU:\Control Panel\Mouse`.
- Original queue depths are captured in `active_state.json` and cleanly restored upon mode deactivation.

### 16. BCDedit System Timer Synchronization
- **Native Hardware Invariant TSC & Dynamic Tick Preservation:** Clears legacy `disabledynamictick` and `tscsyncpolicy` overrides (`bcdedit /deletevalue disabledynamictick`, `bcdedit /deletevalue tscsyncpolicy`) so modern multi-core CPUs use hardware Invariant Time Stamp Counter (TSC) without high-overhead software timer synchronization or micro-stutters in *CS2* and *Deadlock*.
- Original boot configuration state is captured in `active_state.json` and restored cleanly upon mode deactivation.

### 17. High-Performance TCP Gaming Stack
- **Global TCP Low-Latency Stack (`netsh int tcp set global`):**
  - `timestamps=disabled`: Drops 12-byte TCP timestamp headers from network packets, eliminating unnecessary packet overhead and CPU timestamp calculation.
  - `ecncapability=disabled`: Disables Explicit Congestion Notification to prevent dropped or artificially delayed packets on gaming routers and hops that handle ECN incorrectly.
  - `rss=enabled`: Enforces Receive Side Scaling across CPU cores, offloading network packet interrupts across all available processor threads.
- **Per-Adapter Gaming TCP Tuning:** Sets `TcpAckFrequency = 1` (immediate ACK without waiting) and `TCPNoDelay = 1` (disables Nagle's algorithm) across all active physical gaming adapters under `HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces`.
- **Locale-Resilient `netsh` & Registry Detection:** State inspection (`Get-TcpStackConfig`) queries `netsh int tcp show global` and parses both English (`enabled`) and localized Russian (`включено`) output alongside the `HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Tcp1323Opts` registry fallback for TCP Timestamps, ensuring reliable detection across Windows locales.
- **Ironclad Safety Exclusions:** Strictly isolates and excludes Apple Mobile Device USB tethering (`Ethernet 2`) and Wintun VPN tunnels (`wwan99`), guaranteeing phone tethering and VPN connections remain unaffected.

### 18. Hardware-Accelerated GPU Scheduling (HAGS)
- Sets `HwSchMode = 2` under `HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers`.
- Offloads high-frequency GPU memory management and frame scheduling directly from the Windows OS kernel to the GPU's dedicated scheduling processor (available on NVIDIA Pascal/Turing/Ampere/Ada Lovelace, AMD RDNA 3, and Intel Arc).
- Significantly cuts frame submission queuing overhead and reduces DPC latency spikes during GPU-bound scenarios.
- Automatically disabled on AMD RDNA2/Polaris cards (`HwSchMode = 1`) to eliminate known Source 2 engine (CS2) frame-pacing micro-stutter.
- Fully snapshot-backed and restored cleanly in `active_state.json`.

### 19. Competitive Frame Pacing, Ring-0 IFEO & Top-Tier Optimizations (v3.6.0)
- **Winsock AFD Fast-Path & NDIS Multi-Core RSS:** Sets `FastSendDatagramThreshold = 65536`, `FastCopyReceiveThreshold = 65536`, `DefaultSendWindow = 65536`, and `DefaultReceiveWindow = 65536` under `HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters` so UDP game packets up to 64 KB bypass Winsock kernel buffering, and sets `MaxNumRssCpus = 4` under `Services\NDIS\Parameters` for multi-core network interrupt scaling.
- **Kernel Power Telemetry Suppression & Process Consolidation:** Disables Windows energy estimation telemetry (`DisableTaggedEnergyLogging = 1`, `TelemetryMaxApplication = 0`, `TelemetryMaxTagPerApplication = 0` under `Control\Power\EnergyEstimation\TaggedEnergy`), disables timer coalescing (`CoalescingTimerInterval = 0`) and Fast Startup (`HiberbootEnabled = 0`), and consolidates `svchost.exe` processes (`SvcHostSplitThresholdInKB = 67108864` on systems with >= 16 GB RAM; automatically skipped on `LowRamProfile`).
- **AMD Radeon DXNAVI Anti-Stutter & Clock Lock:** Alongside disabling PCIe link power state drops (`EnableAspmL0s = 0`, `EnableAspmL1 = 0`) and locking AMD UMD ShaderCache to `Always On (0x32, 0x00)`, configures `StutterMode = 0` and `PP_SclkDeepSleepDisable = 1` across AMD display class keys (`{4d36e968-e325-11ce-bfc1-08002be10318}`) to eliminate DXNAVI core downclocking micro-stutters.
- **NVIDIA GeForce Telemetry Suppression, Per-Core DPC & Dynamic P-State Lock:** Automatically detects NVIDIA driver keys (`VEN_10DE` / `NVIDIA`), suppresses `nvlddmkm` driver telemetry (`SendTelemetryData = 0`), distributes GPU DPC processing across CPU cores (`RmGpsPsEnablePerCpuCoreDpc = 1` across `nvlddmkm`, `NVAPI`, `NVTweak`, and driver class keys), and provides the reversible `DisableNvidiaDynamicPstate` toggle (`DisableDynamicPstate = 1`).
- **DirectX Flip Model, Kernel Preemption & Desktop/Hotkey Guard:** Enables DirectX Flip Model and VRR optimizations (`DirectXUserGlobalSettings = SwapEffectUpgradeEnable=1;VRROptimizeEnable=1;`), enables DirectX scheduler preemption (`EnablePreemption = 1`), disables Miracast wireless display polling (`PlatformSupportMiracast = 0`), eliminates shell startup delay (`StartupDelayInMSec = 0`), disables Windows StickyKeys (`"506"`), ToggleKeys (`"58"`), and FilterKeys (`"122"`) hotkey popups, accelerates desktop input response (`MenuShowDelay = 0`, `LowLevelHooksTimeout = 5000`, `MouseHoverTime = 10`), and suppresses background disk I/O from Storage Sense (`01 = 0`) and ReserveManager (`ShippedWithReserves = 0`).
- **Third-Party Optimizer Leftovers Remediation:** Scans for and fixes priority inversion caused by uninstalled third-party optimizers (e.g., `GameModeX`). Restores system-critical services (`fontdrvhost.exe`, `sihost.exe`, `lsass.exe`, `ctfmon.exe`) stuck at Idle (4) or Low I/O priorities back to Normal, eliminating text rendering freezes and frame pacing spikes.
- **Ring-0 IFEO Execution Options for 16 Esports Games:** Pre-registers kernel image execution options (`CpuPriorityClass = 3` [High], `IoPriority = 3` [High], `PagePriority = 5`) for games such as *Counter-Strike 2* (`cs2.exe`), *Deadlock* (`project8.exe`), *Dota 2* (`dota2.exe`), *Fortnite*, *Apex Legends*, *Rust*, *Cyberpunk 2077*, and *Elden Ring*. Because the Windows NT kernel assigns these at process initialization, priorities take effect before user-mode anti-cheat systems strip process handle access rights.
- **Storage Controller IRQ De-Contention:** Reconfigures NVMe and SATA storage controllers from High (`DevicePriority = 3`) to Normal (`DevicePriority = 2`), reserving High IRQ Priority exclusively for the primary gaming GPU (`DevicePriority = 3`). Prevents heavy disk I/O interrupts from preempting frame rendering on the PCIe bus.
- **USB Hub & HID Selective Suspend Lockout:** Suppresses aggressive USB power management (`EnhancedPowerManagementEnabled = 0`, `AllowIdleIrpInD3 = 0`) across `HidUsb`, `USBHUB3`, `usbhub`, and `usbccgp` device nodes, preventing polling drops and hub-level sleeps during rapid mouse flicks.
- **Expanded Power Scheme Latency Guards (9 Sub-Settings) & Scheme Ordering:** Unconditionally activates Ultimate Performance prior to CPU tuning and enforces 9 AC latency overrides (`USB Selective Suspend`, `USB 3 Link Power Mgmt`, `NVMe Primary/Secondary Idle Timeout`, `Processor EPP`, `Processor Throttle Max = 100`, `Processor Idle Demote/Promote = 100%`, and `PCIe Link State Power Mgmt = 0`).
- **MMCSS `Tasks\Games` & `Tasks\Audio` Priority Alignment:** Re-aligns Multimedia Class Scheduler `Games` and `Audio` tasks (`Priority = 6`, `Scheduling Category = "Medium"`, Audio `SFIO Priority = "High"`, `Clock Rate = 10000`), elevating game frame and audio threads over background multimedia tasks while preserving DWM stability.
- **Windows Maintenance Lockout, Memory Compression Toggling & Complete 14-Key Debloat Restore:** Disables Windows Automatic Maintenance (`MaintenanceDisabled = 1`), disables memory compression (`Disable-MMAgent -mc -prelaunch` on >=16 GB RAM), snapshots and reverts all 14 Windows 11 debloat values (`TaskbarDa`, `PresenceWriterActivation`, `DisableSearchBoxSuggestions`, `TurnOffWindowsCopilotMachine`, `WSAIFabricSvcStart`, etc.), and supports live `-Action ApplyTuning` re-application when `Config\tuning.json` changes in GUI while Gaming Mode is armed/active.
- **Target Blacklist & Whitelist Precision:** 205 non-essential background services stripped during gaming mode while 95 critical system, input, anti-cheat (`FACEIT` / `FACEITService` whitelisted by default), DPI bypass (`zapret` / `WinDivert`), audio, and screenshot (`CaptureService`, `cbdhsvc`) services remain strictly protected.
---

## 🚀 Quick Start Guide

### Option A: Native Desktop GUI App (v3.6.0 - Recommended)

Ultra Gaming Mode v3.6.0 ships as a self-contained Windows 11 Native Desktop application built on **Tauri v2 (Rust)** and **Svelte 5**. All PowerShell engines, JSON configs, and self-tests are embedded inside **`UltraGamingMode.exe`** and synchronized to **`C:\Program Files\UltraGamingMode`**.

#### 📦 Release Packages
| Package | Format | Best For |
|:---|:---|:---|
| **`UltraGamingMode-Setup.exe`** | NSIS Installer (`perMachine`) | Recommended desktop install with Start Menu / Desktop shortcuts & in-app auto-updater |
| **`UltraGamingMode.msi`** | Windows Installer (`MSI`) | Enterprise / clean MSI deployment to `C:\Program Files\UltraGamingMode` |
| **`UltraGamingMode.exe`** | Standalone Portable EXE | Zero-install portable execution with embedded PowerShell & JSON runtime |

#### 🧭 Desktop UI Tabs & Controls
| Tab | Key Features & Controls |
|:---|:---|
| **1. Обзор (`Overview`)** | Live mode status badge, primary **«Включить игровой режим» / «Вернуть штатный режим»** button, 1-click **PC Reboot**, interrupted-restore recovery banner, optimization profiles (`Киберспорт`, `AAA и стриминг`, `Пользовательский`), on-demand `0.500 ms` timer lock/unlock, hardware telemetry cards, and **SHA-256 verified GitHub Updater**. |
| **2. Процессы (`Processes`)** | Single unified list of currently running processes (grouped by executable with memory usage & Windows Startup badges) plus configured offline rules, instant filter (`Все` / `Выкл. в Gaming Mode` / `Без утилки`), 2-choice toggle (**«Без утилки»** vs **«Выкл. в Gaming Mode»**), hardware/anti-cheat/client lock badges, and hover/focus safety tooltips backed by `process_descriptions.json` & `.exe` metadata. |
| **3. Службы (`Services`)** | Compact 1-click quick presets bar (`Wi-Fi` with live connection warning, `Bluetooth`, `FACEIT AC`, `Камера`, `Xbox / Store`, `VPN / PPPoE`, `Принтер`), single unified list of installed Windows services (running services on top), filter (`Все` / `Выкл. в Gaming Mode` / `Без утилки`), 2-choice toggle (**«Без утилки»** vs **«Выкл. в Gaming Mode»**), OS core lock badges, and hover/focus safety tooltips backed by `service_descriptions.json` & Windows SCM. |
| **4. Настройки (`Settings`)** | **«Запуск и фоновый режим»** (elevated `--tray` Task Scheduler autostart with path-drift repair, auto `0.500 ms` timer lock, and smart background Standby RAM auto-purge), `Config\tuning.json` switches (`FSE`, `NetAdapterMsi`, `DisableMouseAccel`, `DisableNvidiaDynamicPstate`), and `InputBufferQueueSize` (`32–1024` packets) with live `-Action ApplyTuning`. |
| **5. Обслуживание (`Maintenance`)** | Instant **Standby RAM Purge (`Win32StandbyCleaner`)**, config integrity check, service state restore, confirmation-guarded **GPU Shader Cache Purge** (AMD / NVIDIA / Intel / DirectX), DisplayPort / DWM topology reset, and reversible Windows 11 Debloat. |

> [!NOTE]
> **Zero-RAM System Tray Indicator:** Closing the window (`[×]`) destroys the WebView2 renderer (`0 MB` UI memory overhead) while keeping the native Rust tray icon active:
> - 🟢 **Green:** Gaming Mode Active (`0.500 ms` timer & optimizations active)
> - 🟠 **Orange:** Armed for Next Boot / Pending Restore completion
> - 🔴 **Red:** Normal Stock Windows State

---

### Option B: Interactive TUI Menu

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
           ULTRA GAMING MODE CONTROLLER  v3.6.0
            Universal Hardware Adaptive Suite
============================================================

  [1] Enable Gaming Mode (Arm for Next Boot)
  [2] Restore Normal Windows State
  [3] Flush RAM Cache Now (Standby List)
  [4] System Diagnostic & Hardware Check
  [5] Advanced Tools & Emergency Repairs -->
  [6] Check for Updates (GitHub)
  [0] Exit
============================================================
```

Choosing **`[5]`** opens the Advanced Tools & Emergency Repairs submenu:

```
============================================================
           ADVANCED TOOLS & EMERGENCY REPAIRS
============================================================

  [1] Reset DisplayPort & Monitor Topology Cache
  [2] Repair Microphone, Steam & Audio Services
  [3] Purge Universal GPU Shader Cache (AMD / NVIDIA / Intel / DirectX)
  [4] Check & Toggle VBS / Core Isolation
  [5] Check GPU MSI & IRQ Priority Status
  [6] Check Kernel DPC, Input Buffer & Timer Status
  [7] View Full Mode Status
  [8] Check for Updates (GitHub)
  [0] <-- Back to Main Menu
============================================================
```

---

### Option C: PowerShell CLI Usage

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

# Check Kernel DPC, peripheral input buffers, system timers, and HAGS latency status
powershell.exe -ExecutionPolicy Bypass -File .\UltraGamingMode.ps1 -Action KernelLatencyStatus

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

### Main Menu:
| Menu Option | CLI Action Flag | Description |
|:---:|:---|:---|
| **`[1]`** | `-Action Enable` | Creates backup snapshot (services, hardware profile, processor throttle, ULPS, GPU & NIC MSI Mode, NTFS, Core Parking, NIC settings, scheduled defrag, Kernel DPC, input queues, timers, TCP stack, Extended Registry targets, HAGS), suppresses user startup apps, and arms Task Scheduler boot trigger under SYSTEM. |
| **`[2]`** | `-Action Restore` | Restores all 205 services, hardware settings (processor throttle, ULPS, GPU & NIC MSI Mode, Core Parking, NTFS, NIC, scheduled defrag, Kernel DPC, input queues, timers, TCP stack, Extended Registry targets, HAGS), re-enables Windows Defender, unregisters boot triggers, and restores startup apps. |
| **`[3]`** | `-Action CleanMemory` | Calls `EmptyWorkingSet` and `Win32StandbyCleaner` (P/Invoke `NtSetSystemInformation`) to purge standby cache and process working sets instantly. |
| **`[4]`** | `-Action Diagnostic` | Runs pre-flight audit: inspects Universal Hardware Profile (CPU, GPU, RAM, Storage), checks administrator privileges, power plans & Core Parking, MMCSS profiles, network adapters, AMD ULPS, shader caches, GPU MSI mode, VBS/HVCI status, NTFS settings, whitelist protection, bloat services, Kernel DPC, input queues, BCDedit timers, TCP stack, and HAGS status. |
| **`[5]`** | `Advanced Tools -->` | Opens the Advanced Tools & Emergency Repairs submenu (see below). |
| **`[6]`** | `-Action CheckUpdate` | Checks GitHub API for newer releases with non-blocking offline resilience and SemVer comparison. Prompts to update via `git pull` or open the release notes. |
| **`[0]`** | `Exit` | Exits the interactive launcher. |

### Advanced Tools & Emergency Repairs Submenu (Option [5]):
| Submenu Option | CLI Action Flag | Description |
|:---:|:---|:---|
| **`[1]`** | `-Action RepairDisplay` | Emergency fix: wipes corrupt registry display topology caches and resets MMCSS game scheduling to default safe parameters. |
| **`[2]`** | `-Action RepairServices`| Emergency fix: repairs and starts `camsvc` (Microphone privacy), `LanmanServer` (RPC session), Windows Search, Snipping Tool (`CaptureService`, `cbdhsvc`), and unblocks Steam/Bluetooth. |
| **`[3]`** | `-Action FlushShaderCache`| Purges AMD, NVIDIA, and DirectX/Vulkan shader caches (`DxCache`, `VkCache`, `DxcCache`, `DX9Cache`, `OglCache`, `NVIDIA\DXCache`, `GLCache`, `ComputeCache`, `D3DSCache`) to eliminate shader pipeline micro-stutters. |
| **`[4]`** | `-Action ToggleVBS` | Checks and toggles Virtualization-Based Security (VBS) and Memory Integrity (HVCI) in registry to eliminate virtualization overhead. |
| **`[5]`** | `-Action GpuMsiStatus` | Displays GPU Vendor, Message Signaled Interrupts (MSI) status, and IRQ priority (`DevicePriority = 3`). |
| **`[6]`** | `-Action KernelLatencyStatus` | Displays Kernel DPC (`DisablePagingExecutive`, `ThreadDpcEnable`, `Win32PrioritySeparation`), peripheral input queues (`mouclass`/`kbdclass` buffer sizes), BCDedit timer sync (`disabledynamictick`, `tscsyncpolicy`), TCP stack global parameters, and HAGS scheduling status. |
| **`[7]`** | `-Action Status` | Displays current active mode, Universal Hardware Badges (CPU, GPU, Low-RAM Guard, HDD Thrash Guard, Kernel DPC, Input Buffer, Dynamic Tick, HAGS), active services count, and detailed system status. |
| **`[8]`** | `-Action CheckUpdate` | Checks GitHub API for newer releases directly from the Advanced Tools submenu. |
| **`[0]`** | `<-- Back` | Returns to the Main Menu. |
| *(CLI/GUI)* | `-Action ApplyTuning` | Live-applies `Config\tuning.json` toggles (`FSE`, `MouseAccel`, `DisableNvidiaDynamicPstate`, `NetAdapterMsi`, `InputBufferQueueSize`) when state is `Armed` or `GameMode_Active`. |
---

## 📂 Directory Structure

```
Win11-Gaming-Optimizer/
│
├── UltraGamingMode.bat              # Elevated interactive TUI launcher
├── UltraGamingMode.ps1              # Core PowerShell CLI controller & orchestrator
├── Build-Release.ps1                # Automated Tauri build, .bin/ packaging & SHA256SUMS generator
├── README.md                        # English documentation & benchmarks
├── README.ru.md                     # Russian documentation & benchmarks
├── LICENSE                          # MIT License
│
├── ui/                              # Native Desktop frontend & Tauri Rust backend
│   ├── src/                         # Svelte 5 (Runes) + Tailwind CSS v4 + Lucide Icons + ItemTooltip + ConfirmDialog
│   └── src-tauri/                   # Rust application core with native window chrome, theme sync & 25 unit tests
│
├── Config/
│   ├── process_descriptions.json    # Localized Russian descriptions & safety verdicts for 173 Windows/app processes
│   ├── service_descriptions.json    # Localized Russian descriptions & safety verdicts for 325 Windows services
│   ├── services_blacklist.json      # 205 target non-essential Windows services
│   ├── services_whitelist.json      # 95 strictly protected critical components (incl. FACEIT & Zapret)
│   ├── startup_apps.json            # Target startup bloat & protected app rules
│   └── tuning.json                  # User-configurable AutoLockTimer, FSE, Mouse Accel, NVIDIA P-State, NIC MSI & Input Queue
│
├── Core/
│   ├── ServiceManager.ps1           # Safe service manipulation with whitelist locks
│   ├── StateEngine.ps1              # Snapshot creation, registry backup & restore engine
│   └── SystemOptimizer.ps1          # Power, MMCSS, Network, Memory, and Defender tuning
│
└── Tests/
    └── Verify-UniversalEngine.ps1   # 72 automated unit tests & hardware simulation suite
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
