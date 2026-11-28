<div align="center">

# ⚡ Ultra Gaming Mode for Windows 11
### *Native Rust + Slint GUI · AAA Frame Pacing · Portable Universal Edition (v4.1.1)*

**A zero-risk, snapshot-driven kernel latency, frame pacing, and hardware optimizer for Windows 10 & 11.**  
Built on a **native Rust + Slint 1.19.0 GUI** (`960×680` frameless, Windows DWM Dark Mode & rounded corners, `Segoe UI Variable Text` + `Cascadia Code`, zero WebView2) and a **Win32 / PowerShell AAA Engine** — featuring an **8-theme design package (5 dark + 3 light)**, a unified AAA gaming pipeline, 2-mode Services & Processes management with safety tooltips, native `tray-icon` background mode, portable single-executable execution (`UltraGamingMode.exe`), automatic `0.500 ms` timer resolution, smart Standby RAM auto-purge, **Zapret / WinDivert / `winws`** protection, and a crash-proof `HKLM\RunOnce` failsafe watchdog.

[![Release](https://img.shields.io/badge/Release-v4.1.1-2563EB?style=for-the-badge&labelColor=0F172A)](https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases/latest)
[![Platform](https://img.shields.io/badge/Windows-11%20%7C%2010%20(x64)-2563EB?style=for-the-badge&logo=windows&logoColor=white&labelColor=0F172A)](https://www.microsoft.com/windows)
[![Desktop Stack](https://img.shields.io/badge/GUI-Rust%20%2B%20Slint-3B82F6?style=for-the-badge&logo=rust&logoColor=white&labelColor=0F172A)](#option-a-native-desktop-gui-app-v400---recommended)
[![Watchdog](https://img.shields.io/badge/Failsafe-HKLM%20RunOnce-10B981?style=for-the-badge&labelColor=0F172A)](#the-zero-risk-watchdog-guarantee)
[![Anti-Cheat Safe](https://img.shields.io/badge/Anti--Cheat-FACEIT%20%7C%20Vanguard%20%7C%20EAC%20%7C%20VAC-10B981?style=for-the-badge&labelColor=0F172A)](#2-ironclad-whitelist-95-protected-services)
[![Test Suite](https://img.shields.io/badge/Verified-PS%20%2B%20Rust%20Tests-475569?style=for-the-badge&labelColor=0F172A)](#directory-structure)
[![License: MIT](https://img.shields.io/badge/License-MIT-475569?style=for-the-badge&labelColor=0F172A)](LICENSE)

<br />

[**🚀 Quick Start**](#quick-start-guide) · [**📊 CS2 Benchmarks**](#real-world-benchmarks-engine-telemetry) · [**🛠️ Hardware Engine**](#universal-hardware-auto-detection-engine) · [**🛡️ Watchdog Lifecycle**](#core-architecture-lifecycle) · [**🔬 19 Technical Modules**](#deep-technical-features) · [**⌨️ CLI Reference**](#menu-overview-cli-reference)

**Language:** [**🇺🇸 English**](README.md) · [**🇷🇺 Русский**](README.ru.md)

</div>

---

## ✨ Architecture at a Glance

| 🖥️ Native Rust + Slint GUI & Tray | ⚡ Kernel, Input & Network Latency | 🛠️ Universal Hardware Adaptation | 🛡️ Zero-Risk Snapshot Watchdog |
|:---|:---|:---|:---|
| • **Native Rust + Slint 1.19.0** (`960×680` frameless, zero WebView2, DWM Dark Mode)<br>• **Native Tray Mode**: closing `[×]` destroys the Slint window and keeps only `tray-icon` + `muda` active<br>• **8-Theme Design Package** (5 dark + 3 light, 4×2 grid + smart header polarity toggle)<br>• **Portable Single EXE** (`UltraGamingMode.exe` with embedded runtime assets) + SHA-256 Updater | • **Auto `0.500 ms` Timer Lock** in Gaming Mode (`NtSetTimerResolution`)<br>• **GPU & PCIe NIC MSI Mode** (`DevicePriority = 3`)<br>• **Winsock AFD 64 KB Fast-Path** & Nagle off<br>• **AAA Input Buffers** (`100` packets, `>= 32` safety floor, 8000 Hz safe) | • **CPU Unparking** (`CPMINCORES 100`) & Low-Core Guard (`<= 4` threads)<br>• **Discrete GPU Discovery** (AMD ULPS/DXNAVI, NVIDIA Per-Core DPC, Intel Arc, AAA Flip Model + HDR/OBS)<br>• **Low-RAM Guard (8 GB)** + native `NtSetSystemInformation` Standby Purge<br>• **Mechanical HDD 100% Thrash Guard** | • Full pre-flight JSON snapshot (`Backups\active_state.json`)<br>• Autonomous `HKLM\RunOnce` kernel watchdog (`*UltraGamingModeRestore`)<br>• **95 Protected Whitelist Services** (`FACEIT`, `vgk`, `EAC`, `zapret`, `WinDivert`, `camsvc`, `PrtSc`)<br>• 1-Click Emergency DisplayPort & Audio Repair |

> [!TIP]
> **What's New in v4.1.1 (building on v4.0.1 / v4.0.0):**
> - **1-Click SHA-256 Verified In-App Updater (`v4.1.1`):** Automatic background release discovery, quick header update pill, and primary in-app install button that detects NSIS (`Setup.exe`), WiX (`.msi`), or Portable (`UltraGamingMode.exe`) deployments, cryptographically verifies `SHA256SUMS.txt` before execution, preserves `Config/*.json`, and seamlessly relaunches the app.
> - **Hardened NSIS & WiX Installers (`v4.0.1`):** Reliable elevated/tray process shutdown during upgrades, automatic cleanup of legacy root Start Menu `.lnk` shortcuts and scheduled tasks on uninstall, mutual NSIS↔MSI cross-detection preserving user `Config/*.json`, and explicit `GCLP_HICON` window class icons.
> - **Zero-Freeze Async UI & Resilient Tray (`v4.0.1`):** Non-blocking background loading for Processes, Services, Autostart, and Tray RAM purge, automatic tray retry on early Windows logon, safe UTF-16 `NOTIFYICONDATAW` tooltip clamping, modal keyboard `Tab` focus traps, local wall-clock Event Log timestamps, and full `Backups\verify-*.log` diagnostic reports.
> - **Native Rust + Slint 1.19.0 Desktop GUI (`v4.0.0`, Zero WebView2):** Pure native Rust + Slint desktop application (`960×680` frameless, min `860×600`) with Windows DWM Dark Mode & rounded-border frame synchronization (`DwmSetWindowAttribute`), crisp Windows typography (`Segoe UI Variable Text` + `Cascadia Code` with Windows 10 `Segoe UI` / `Consolas` fallbacks), native `tray-icon` + `muda` menu, zero browser runtimes, and portable-first `UltraGamingMode.exe` embedding all PowerShell and JSON runtime assets (`EMBEDDED_RUNTIME_ASSETS`).
> - **8-Theme Design Package (5 Dark + 3 Light):** Added `dark`, `oled-obsidian`, `emerald-ops`, `graphite-amber`, `midnight-violet`, `light`, `daylight-warm`, and `frost-slate` with custom theme-matched inputs, scrollbars, switches, and radial ambient glow, an accessible 4×2 live preview grid in Settings, and a smart header toggle remembering `ugm-last-dark-theme` and `ugm-last-light-theme`.
> - **Unified AAA Gaming Pipeline & Clean Russian UX:** Streamlined Overview focused on the unified AAA pipeline (Graphics/DWM, CPU/HID, Memory/Timer, Network/Zapret) with automatic Flip Model + HDR/OBS + MPO-safe defaults and simplified `Config/tuning.json` automation (`AutoLockTimerInGaming`, `AutoPurgeRamInGaming`, `AutoPurgeRamThresholdMB`), while keeping full **Processes** (`181` descriptions), **Services** (`328` descriptions), and **Maintenance** controls.
> - **Strict Zapret / WinDivert DPI Protection:** Built-in safeguards protecting `zapret`, `WinDivert`, `WinDivert14`, `winws`/`winws2`, and preserving RFC 1323 `TCP timestamps=enabled` whenever DPI bypass is present.

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
  - [19. AAA Frame Pacing, Ring-0 IFEO & Top-Tier Optimizations (v4.0.0)](#19-aaa-frame-pacing-ring-0-ifeo--top-tier-optimizations-v400)
- [Quick Start Guide](#quick-start-guide)
  - [Option A: Native Desktop GUI App (v4.0.0 - Recommended)](#option-a-native-desktop-gui-app-v400---recommended)
  - [Option B: Interactive TUI Menu](#option-b-interactive-tui-menu)
  - [Option C: PowerShell CLI Usage](#option-c-powershell-cli-usage)
- [Menu Overview & CLI Reference](#menu-overview-cli-reference)
- [Directory Structure](#directory-structure)
- [Building from Source](#building-from-source)
- [System Requirements & Compatibility](#system-requirements-compatibility)
- [Author & Credits](#author-credits)
- [License](#license)

---

## ⚡ Why Ultra Gaming Mode?

Modern Windows 11 is packed with hundreds of background processes, telemetry collectors, diagnostic listeners, per-user service templates, and aggressive Defender real-time archive scans. In demanding esports and AAA titles (such as *Counter-Strike 2*, *VALORANT*, *Apex Legends*), these background spikes cause:
- **DPC (Deferred Procedure Call) Latency Spikes:** Caused by network power-saving sleep transitions (`*EEE`) and multimedia scheduler contention.
- **Texture / Asset Stutters:** Windows Defender intercepts synchronous filesystem read calls when games stream models, shaders, or maps.
- **Micro-Freezes on Frame Boundaries:** Secondary threads stealing CPU cycles from game render loops.
- **1% Low FPS Drops:** Jitter in frame pacing even when average FPS remains high.

**Ultra Gaming Mode v4.0.0** solves this without permanently mangling your operating system. Unlike brittle "debloater" scripts that break Windows Update, brick microphone privacy permissions, or cause black screens on DisplayPort monitors, Ultra Gaming Mode utilizes a **non-destructive, snapshot-driven lifecycle**:

```
[Normal Windows] ──(Arm Mode)──> [System Snapshot] ──(Reboot)──> [Stripped Ultra Gaming Mode]
       ▲                                                                   │
       │                                                                   │
       └───────────────────(Failsafe Watchdog / Restore)───────────────────┘
```

---

## 🛠️ Universal Hardware Auto-Detection Engine

Ultra Gaming Mode v4.0.0 features an autonomous hardware discovery engine (`Get-HardwareProfile`) that inspects your machine's physical architecture during diagnostic checks, arming, and boot stages. Rather than applying blunt, one-size-fits-all tweaks, the optimizer detects exact CPU topologies, GPU bus interfaces, physical memory limits, and storage media types to dynamically tailor kernel and driver optimizations to your exact PC.

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
| **Target Role** | High-Refresh Rate Esports & AAA | Budget / Legacy PC Gaming & Frame Pacing |
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

| Metric | Stock Windows 11 | Ultra Gaming Mode (PS Engine Baseline, v3.5.1) | Delta / Gain | Real-World Impact |
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
- **Telemetry & Diagnostics:** `DiagTrack`, `dmwappushservice`, `DPS` (Diagnostic Policy Service), `wmiApSrv`, `pla` (Performance Logs), `TroubleshootingSvc`, `wuqisvc`, `WSAIFabricSvc`.
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
- **Strictly Protected:** The active game, **Steam**, **FACEIT Client**, **Zapret DPI Bypass** (`winws`, `winws2`, `zapret`), AMD Radeon display driver (`atieclxx`), **MSI Afterburner / RivaTuner Statistics Server**, **Process Lasso** (`ProcessGovernor`), **Apple Mobile Device Service** (USB Tethering), Windows 11 Start Menu Search (`SearchHost`, `TextInputHost`), and **Ultra Gaming Mode** itself (`UltraGamingMode.exe`).
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
- **PCIe Network Adapter MSI Mode:** Automatically switches physical PCIe network controllers (`^PCI\\`) to Message Signaled Interrupts (`MSISupported = 1` under `Device Parameters\Interrupt Management\MessageSignaledInterruptProperties`) as part of AAA optimization, eliminating legacy line-based IRQ sharing between the network card and USB/audio controllers.
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
- **Fixed AAA High-Polling Safe Input Queues (`100` Packets, Floor `>= 32`):** Configures `MouseDataQueueSize = 100` and `KeyboardDataQueueSize = 100` in `HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters` and `kbdclass\Parameters` automatically in AAA Gaming Mode.
- **Zero-Drop High-Polling Protection:** High-polling mice operating at 1,000 Hz, 4,000 Hz, and 8,000 Hz generate dense interrupt bursts. The engine enforces `100` packets for zero packet drops with a strict safety floor of `>= 32` packets inside `Set-InputBufferOptimizations`, while leaving raw mouse pointer/acceleration curves untouched.
- Original queue depths are captured in `active_state.json` and cleanly restored upon mode deactivation.

### 16. BCDedit System Timer Synchronization
- **Native Hardware Invariant TSC & Dynamic Tick Preservation:** Clears legacy `disabledynamictick` and `tscsyncpolicy` overrides (`bcdedit /deletevalue disabledynamictick`, `bcdedit /deletevalue tscsyncpolicy`) so modern multi-core CPUs use hardware Invariant Time Stamp Counter (TSC) without high-overhead software timer synchronization or micro-stutters in *CS2* and *Deadlock*.
- Original boot configuration state is captured in `active_state.json` and restored cleanly upon mode deactivation.

### 17. High-Performance TCP Gaming Stack
- **Global TCP Low-Latency Stack (`netsh int tcp set global`):**
  - `timestamps`: Automatically preserves **RFC 1323 `timestamps=enabled`** whenever **Zapret / WinDivert / `winws`** (`zapret`, `WinDivert`, `WinDivert14`, `winws`, `winws2`) is detected or already enabled, ensuring DPI bypass continues functioning reliably; otherwise sets `timestamps=disabled` to remove 12-byte header overhead.
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

### 19. AAA Frame Pacing, Ring-0 IFEO & Top-Tier Optimizations (v4.0.0)
- **Winsock AFD Fast-Path & NDIS Multi-Core RSS:** Sets `FastSendDatagramThreshold = 65536`, `FastCopyReceiveThreshold = 65536`, `DefaultSendWindow = 65536`, and `DefaultReceiveWindow = 65536` under `HKLM:\SYSTEM\CurrentControlSet\Services\AFD\Parameters` so UDP game packets up to 64 KB bypass Winsock kernel buffering, and sets `MaxNumRssCpus = 4` under `Services\NDIS\Parameters` for multi-core network interrupt scaling.
- **Kernel Power Telemetry Suppression & Process Consolidation:** Disables Windows energy estimation telemetry (`DisableTaggedEnergyLogging = 1`, `TelemetryMaxApplication = 0`, `TelemetryMaxTagPerApplication = 0` under `Control\Power\EnergyEstimation\TaggedEnergy`), disables timer coalescing (`CoalescingTimerInterval = 0`) and Fast Startup (`HiberbootEnabled = 0`), and consolidates `svchost.exe` processes (`SvcHostSplitThresholdInKB = 67108864` on systems with >= 16 GB RAM; automatically skipped on `LowRamProfile`).
- **AMD Radeon DXNAVI Anti-Stutter & Clock Lock:** Alongside disabling PCIe link power state drops (`EnableAspmL0s = 0`, `EnableAspmL1 = 0`) and locking AMD UMD ShaderCache to `Always On (0x32, 0x00)`, configures `StutterMode = 0` and `PP_SclkDeepSleepDisable = 1` across AMD display class keys (`{4d36e968-e325-11ce-bfc1-08002be10318}`) to eliminate DXNAVI core downclocking micro-stutters.
- **NVIDIA GeForce Telemetry Suppression & Per-Core DPC:** Automatically detects NVIDIA driver keys (`VEN_10DE` / `NVIDIA`), suppresses `nvlddmkm` driver telemetry (`SendTelemetryData = 0`), and distributes GPU DPC processing across CPU cores (`RmGpsPsEnablePerCpuCoreDpc = 1` across `nvlddmkm`, `NVAPI`, `NVTweak`, and driver class keys) while preserving native dynamic power state management.
- **AAA DirectX Flip Model, HDR/OBS Compatibility & MPO Safe:** Enables DirectX Flip Model and VRR optimizations (`DirectXUserGlobalSettings = SwapEffectUpgradeEnable=1;VRROptimizeEnable=1;`) without disabling Fullscreen Optimizations (ensuring seamless Alt-Tab, HDR, and OBS Game Capture alongside active MPO Safe cleanup), enables DirectX scheduler preemption (`EnablePreemption = 1`), disables Miracast wireless display polling (`PlatformSupportMiracast = 0`), eliminates shell startup delay (`StartupDelayInMSec = 0`), disables Windows StickyKeys (`"506"`), ToggleKeys (`"58"`), and FilterKeys (`"122"`) hotkey popups, accelerates desktop input response (`MenuShowDelay = 0`, `LowLevelHooksTimeout = 5000`, `MouseHoverTime = 10`), and suppresses background disk I/O from Storage Sense (`01 = 0`) and ReserveManager (`ShippedWithReserves = 0`).
- **Third-Party Optimizer Leftovers Remediation:** Scans for and fixes priority inversion caused by uninstalled third-party optimizers (e.g., `GameModeX`). Restores system-critical services (`fontdrvhost.exe`, `sihost.exe`, `lsass.exe`, `ctfmon.exe`) stuck at Idle (4) or Low I/O priorities back to Normal, eliminating text rendering freezes and frame pacing spikes.
- **Ring-0 IFEO Execution Options for 15 Games:** Pre-registers kernel image execution options (`CpuPriorityClass = 3` [High], `IoPriority = 3` [High], `PagePriority = 5`) for games such as *Counter-Strike 2* (`cs2.exe`), *Deadlock* (`project8.exe`), *Dota 2* (`dota2.exe`), *Fortnite*, *Apex Legends*, *Rust*, *Cyberpunk 2077*, and *Elden Ring*. Because the Windows NT kernel assigns these at process initialization, priorities take effect before user-mode anti-cheat systems strip process handle access rights.
- **Storage Controller IRQ De-Contention:** Reconfigures NVMe and SATA storage controllers from High (`DevicePriority = 3`) to Normal (`DevicePriority = 2`), reserving High IRQ Priority exclusively for the primary gaming GPU (`DevicePriority = 3`). Prevents heavy disk I/O interrupts from preempting frame rendering on the PCIe bus.
- **USB Hub & HID Selective Suspend Lockout:** Suppresses aggressive USB power management (`EnhancedPowerManagementEnabled = 0`, `AllowIdleIrpInD3 = 0`) across `HidUsb`, `USBHUB3`, `usbhub`, and `usbccgp` device nodes, preventing polling drops and hub-level sleeps during rapid mouse flicks.
- **Expanded Power Scheme Latency Guards (9 Sub-Settings) & Scheme Ordering:** Unconditionally activates Ultimate Performance prior to CPU tuning and enforces 9 AC latency overrides (`USB Selective Suspend`, `USB 3 Link Power Mgmt`, `NVMe Primary/Secondary Idle Timeout`, `Processor EPP`, `Processor Throttle Max = 100`, `Processor Idle Demote/Promote = 100%`, and `PCIe Link State Power Mgmt = 0`).
- **MMCSS `Tasks\Games` & `Tasks\Audio` Priority Alignment:** Re-aligns Multimedia Class Scheduler `Games` and `Audio` tasks (`Priority = 6`, `Scheduling Category = "Medium"`, Audio `SFIO Priority = "High"`, `Clock Rate = 10000`), elevating game frame and audio threads over background multimedia tasks while preserving DWM stability.
- **Windows Maintenance Lockout, Memory Compression, Debloat Restore & AAA Automation:** Disables Windows Automatic Maintenance (`MaintenanceDisabled = 1`), disables memory compression (`Disable-MMAgent -mc -prelaunch` on >=16 GB RAM), snapshots and reverts all 14 Windows 11 debloat values (`TaskbarDa`, `PresenceWriterActivation`, `DisableSearchBoxSuggestions`, `TurnOffWindowsCopilotMachine`, `WSAIFabricSvcStart`, etc.), and automates Gaming Mode timer locking (`AutoLockTimerInGaming`) and Standby RAM cleanup (`AutoPurgeRamInGaming`, `AutoPurgeRamThresholdMB`) via `Config\tuning.json`.
- **Target Blacklist & Whitelist Precision:** 205 non-essential background services stripped during gaming mode while 95 critical system, input, anti-cheat (`FACEIT` / `FACEITService` whitelisted by default), DPI bypass (`zapret` / `WinDivert` / `WinDivert14`), audio, and screenshot (`CaptureService`, `cbdhsvc`) services remain strictly protected.
---

## 🚀 Quick Start Guide

### Option A: Native Desktop GUI App (v4.0.0 - Recommended)

Ultra Gaming Mode v4.0.0 ships as a portable-first native Windows 11 desktop application built in **Rust** and **Slint 1.19.0** (`960×680` frameless window, minimum `860×600`, Windows DWM Dark Mode & rounded-corner sync, `Segoe UI Variable Text` + `Cascadia Code` typography, zero WebView2). All PowerShell modules and JSON configs are embedded inside **`UltraGamingMode.exe`** (`EMBEDDED_RUNTIME_ASSETS`) and automatically materialized alongside the executable (with fallback to `Program Files`, `ProgramData`, or `%LOCALAPPDATA%` when launched from a read-only folder) — **no mandatory installation required**.

#### 📦 Release Packages
| Package | Format | Best For |
|:---|:---|:---|
| **`UltraGamingMode.exe`** *(Primary)* | Standalone Portable EXE | Zero-install portable execution from any folder with embedded PS1 & JSON runtime |
| **`UltraGamingMode-Setup.exe`** *(Optional)* | NSIS Installer (`perMachine`) | Optional Start Menu / Desktop shortcuts & installer-managed deployment (zero WebView2) |
| **`UltraGamingMode.msi`** *(Optional)* | Windows Installer (`MSI`) | Optional clean MSI deployment to `C:\Program Files\UltraGamingMode` (zero WebView2) |
| **`SHA256SUMS.txt`** | Checksum Manifest | Cryptographic verification for all release binaries |

#### 🧭 Desktop UI Tabs & Controls
| Tab | Key Features & Controls |
|:---|:---|
| **1. Обзор (`Overview`)** | Live AAA mode status banner, **«Включить игровой режим» / «Вернуть штатный режим»** toggle, 1-click **PC Reboot**, interrupted-restore recovery banner, clean **Unified AAA Gaming Pipeline** 2×2 summary (`Графика и DWM`, `Ядро и ввод HID`, `Память и таймер`, `Сеть и защита DPI`), on-demand `0.500 ms` timer lock/unlock, hardware telemetry cards, and **SHA-256 verified GitHub Updater**. |
| **2. Процессы (`Processes`)** | Single unified list of currently running processes (grouped by executable with memory usage & Windows Startup badges) plus configured offline rules, instant filter (`Все` / `Выкл. в Gaming Mode` / `Без утилки`), 2-choice toggle (**«Без утилки»** vs **«Выкл. в Gaming Mode»**), **Zapret** (`winws`/`winws2`/`zapret`) & OS/anti-cheat locks, and safety tooltips backed by `181` curated `process_descriptions.json` entries & `.exe` metadata. |
| **3. Службы (`Services`)** | Compact 1-click quick presets bar (`Wi-Fi` with live connection warning, `Bluetooth`, `FACEIT AC`, `Камера`, `Xbox / Store`, `VPN / PPPoE`, `Принтер`), single unified list of installed Windows services (running services on top), filter, 2-choice toggle, OS core & **Zapret** (`zapret`, `WinDivert`, `WinDivert14`) protection locks, and safety tooltips backed by `328` curated `service_descriptions.json` entries & Windows SCM. |
| **4. Настройки (`Settings`)** | **4×2 Theme Grid (8 themes: 5 dark + 3 light)** with live mini-previews, keyboard accessibility, instant atomic switching, and smart header toggle (`ugm-last-dark-theme` / `ugm-last-light-theme` + Windows DWM chrome sync); **«Запуск вместе с Windows»** (elevated `--tray` Task Scheduler autostart with path-drift repair); and AAA automation (`AutoLockTimerInGaming`, `AutoPurgeRamInGaming`, `AutoPurgeRamThresholdMB` `512–16384 MB`). |
| **5. Обслуживание (`Maintenance`)** | Instant **Standby RAM Purge (`Win32StandbyCleaner`)**, config integrity check, service state restore, confirmation-guarded **GPU Shader Cache Purge** (AMD / NVIDIA / Intel / DirectX), DisplayPort / DWM topology reset, reversible Windows 11 Debloat, and collapsible **Log Console** access. |

> [!NOTE]
> **Native Rust System Tray Mode:** Closing the window (`[×]`) unloads the Slint GUI window while keeping only the lightweight native Rust `tray-icon` + `muda` indicator active in the background:
> - 🟢 **Green:** AAA Gaming Mode Active (`0.500 ms` timer & optimizations active)
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
           ULTRA GAMING MODE CONTROLLER  v4.0.0
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
| *(CLI/GUI)* | `-Action ApplyTuning` | Applies AAA automation settings in `Config\tuning.json` (`AutoLockTimerInGaming`, `AutoPurgeRamInGaming`, `AutoPurgeRamThresholdMB`) when state is `Armed` or `GameMode_Active`. |
---

## 📂 Directory Structure

```
Win11-Gaming-Optimizer/
│
├── Cargo.toml                       # Root Rust crate manifest (v4.0.0, Slint 1.19 + tray-icon + muda)
├── Cargo.lock                       # Locked Rust dependency graph
├── build.rs                         # Slint compiler + Windows manifest & icon embedding
├── UltraGamingMode.bat              # Elevated interactive TUI launcher
├── UltraGamingMode.ps1              # Core PowerShell CLI controller & orchestrator
├── Build-Release.ps1                # Automated Rust + Slint build, .bin/ packaging & SHA256SUMS generator
├── README.md                        # English documentation & benchmarks
├── README.ru.md                     # Russian documentation & benchmarks
├── LICENSE                          # MIT License
│
├── assets/
│   └── icons/                       # Multi-size Ultra Gaming Mode app icons (PNG & ICO)
│
├── installer/                       # Native Windows installers (zero browser runtime)
│   ├── UltraGamingMode.nsi          # NSIS Setup installer script (UltraGamingMode-Setup.exe)
│   └── UltraGamingMode.wxs          # WiX 3.14 x64 MSI package definition (UltraGamingMode.msi)
│
├── src/                             # Native Rust application core & Win32/Slint backend
│   ├── main.rs                      # Entry point, single-instance wake, Slint event loop & close-to-tray
│   ├── lib.rs                       # Public crate exports & Rust unit tests
│   ├── backend/                     # Modular Win32/PS/Config/Updater/Tray-sync backend submodules
│   │   ├── mod.rs                   # Re-exports, embedded runtime assets & core unit tests
│   │   ├── types.rs                 # Shared DTOs, protection lists & identifier helpers
│   │   ├── win_hw.rs                # Win32 FFI (hardware, registry, processes, services, SID, mutex)
│   │   ├── timer.rs                 # NtQueryTimerResolution / NtSetTimerResolution (0.500ms lock)
│   │   ├── config.rs                # Runtime asset sync, config migration, tuning & system status
│   │   ├── actions.rs               # PS engine runner, RAM purge, shader flush & Verify gate
│   │   ├── updater.rs               # SHA-256 verified GitHub release checker & in-app self-updater
│   │   ├── autostart.rs             # Elevated Task Scheduler XML registration & symlink guards
│   │   └── processes.rs             # Process/service/startup rule lists & live snapshot builder
│   ├── themes.rs                    # 8-theme design package (43+2 tokens) & persistent preferences
│   ├── dwm.rs                       # Windows DWM Dark Mode titlebar integration (DwmSetWindowAttribute)
│   ├── tray.rs                      # Native tray-icon + muda menu & 32x32 dynamic status icon
│   └── ui_bridge.rs                 # Slint property/callback/model bindings & background sync
│
├── slint/                           # Native Slint 1.19 declarative UI modules (960x680 frameless)
│   ├── main.slint                   # Root frameless Window, ambient glow, tabs & collapsible log drawer
│   ├── theme.slint                  # ThemeTokens global (43+2 color tokens + Windows font tokens)
│   ├── components.slint             # Vector icons, SurfaceCard, ThemedScrollView, ThemedLineEdit & ThemedSwitch
│   ├── titlebar.slint               # Frameless TitleBar (WindowMoveArea + smart dark/light toggle)
│   ├── dashboard.slint              # Обзор (AAA toggle, unified pipeline, 0.500ms timer, telemetry, updater)
│   ├── processes.slint              # Процессы (unified list, Zapret/OS guards, tooltips)
│   ├── services.slint               # Службы (unified list, 7 presets, Wi-Fi banner, tooltips)
│   ├── settings.slint               # Настройки (4x2 theme grid, autostart, AAA automation)
│   ├── maintenance.slint            # Обслуживание (repair actions & confirmation-guarded tools)
│   └── dialogs.slint                # LogConsole, ConfirmDialog & ItemTooltip modal overlays
│
├── Config/
│   ├── process_descriptions.json    # Localized Russian descriptions & safety verdicts for 181 Windows/app processes
│   ├── service_descriptions.json    # Localized Russian descriptions & safety verdicts for 328 Windows services
│   ├── services_blacklist.json      # 205 target non-essential Windows services
│   ├── services_whitelist.json      # 95 strictly protected critical components (incl. FACEIT & Zapret)
│   ├── startup_apps.json            # Target startup bloat & protected app rules
│   └── tuning.json                  # AAA automation config (AutoLockTimerInGaming, AutoPurgeRamInGaming, AutoPurgeRamThresholdMB)
│
├── Core/
│   ├── ServiceManager.ps1           # Safe service manipulation with whitelist locks
│   ├── StateEngine.ps1              # Snapshot creation, registry backup & restore engine
│   └── SystemOptimizer.ps1          # Power, MMCSS, Network, Memory, and Defender tuning
│
└── Tests/
    └── Verify-UniversalEngine.ps1   # PowerShell engine unit tests & hardware simulation suite
```

---

## 🔨 Building from Source

Ultra Gaming Mode v4.0.0 builds with a **pure Rust toolchain** (no external JavaScript/browser SDKs required):

```powershell
# Build the native Rust + Slint portable binary
cargo build --release

# Or build the full release package & SHA256SUMS.txt into .bin/
.\Build-Release.ps1 -Tag v4.1.1
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
You are free to use, modify, and distribute this software for personal and gaming setups.

### Third-Party GUI Attribution
Desktop GUI built with **[Slint UI](https://slint.dev/)** under the Slint Royalty-Free License (`LicenseRef-Slint-Royalty-free-2.0`).
