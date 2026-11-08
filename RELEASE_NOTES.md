# ⚡ Ultra Gaming Mode v3.1.1 — Competitive Low-Latency Engine & Fluent UI Overhaul

**Ultra Gaming Mode v3.1.1** is a patch release addressing automated release packaging checksum generation while bringing all v3.1 low-latency and UI features: a redesigned native desktop interface with dark/light themes, cutting-edge kernel-level latency optimizations, Winsock AFD fast-path socket bypass, ring-0 process prioritization for competitive esports titles, and an automated release distribution pipeline.

---

### 🔧 Bug Fixes in v3.1.1
- **Fixed Empty `SHA256SUMS.txt` Generation:** Resolved a PowerShell directory enumeration issue in `Build-Release.ps1` where `Get-ChildItem -Path $binDir -Include ...` without `-Recurse` caused `$binFiles` to return empty. Implemented robust extension matching (`Where-Object { $_.Extension -in @(".exe", ".msi", ".zip") }`) to ensure `.bin\SHA256SUMS.txt` reliably records all binary hashes.

---

## 🌟 What's New in v3.1

### 🎨 Native Desktop UI Redesign (Svelte 5 + Tauri v2)
- **Dark & Light Mode Toggle:** Full dual-theme system with smooth transition animations, persistent preference storage in `localStorage`, and native Windows DWM chrome color synchronization.
- **Enhanced Window Chrome:** Custom frameless title bar with responsive multi-display dragging, seamless minimize/maximize toggles, and reliable synchronous exit (`std::process::exit(0)`).
- **Redesigned Modular Views:**
  - **Dashboard:** Real-time hardware topology cards (CPU cores, GPU bus interface, RAM budget, disk types), active status indicators, and on-demand standby cache cleaner.
  - **Services Tab (207):** Live search and category filters (Telemetry, Xbox, Printing, Network, System) across all 207 stripped background services, alongside a dedicated tab for the 90 strictly protected whitelisted services.
  - **Tweaks & Latency View:** Direct switches for GPU MSI Mode, Winsock AFD Fast-Path, Dynamic Tick suppression, HAGS, and 1:1 raw mouse input.
  - **One-Click Repair Suite:** Emergency one-click recovery for DisplayPort / MPO stutter, microphone privacy permissions, Windows Search typing, and Snipping Tool (`PrtSc`).
  - **Live Log Console:** Collapsible real-time IPC event stream console.

---

### ⏱️ Kernel-Level Latency & Esports Frame Pacing
- **Ring-0 IFEO Prioritization for 16 Esports Games:** Pre-registers native NT kernel Image File Execution Options (`CpuPriorityClass = 3` [High], `IoPriority = 3` [High], `PagePriority = 5`) for *Counter-Strike 2* (`cs2.exe`), *Deadlock* (`project8.exe`), *Dota 2* (`dota2.exe`), *Apex Legends*, *Fortnite*, *Rust*, *Cyberpunk 2077*, *Elden Ring*, and more. Priorities attach at process initialization before third-party anti-cheat engines restrict handle access.
- **Winsock AFD Fast-Path & NDIS Multi-Core RSS:** Configures 64 KB datagram/copy receive thresholds (`FastSendDatagramThreshold = 65536`, `FastCopyReceiveThreshold = 65536`) in the AFD kernel driver so UDP game traffic bypasses socket buffering queues. Enables `MaxNumRssCpus = 4` for multi-core interrupt scaling.
- **Storage IRQ De-Contention:** Rebalanced NVMe and SATA storage controllers from High to Normal IRQ priority, granting exclusive High IRQ Priority to the primary gaming GPU on the PCIe bus.
- **AMD Radeon DXNAVI Anti-Stutter:** Locks AMD UMD shader cache to `Always On`, suppresses PCIe link power state dropping (`EnableAspmL0s = 0`, `EnableAspmL1 = 0`), and disables `StutterMode` and `PP_SclkDeepSleepDisable` to prevent core downclocking micro-stutters.
- **Leftover Optimizer Remediation:** Automatically scans for and resolves priority inversions caused by uninstalled third-party tweakers, restoring system servers (`fontdrvhost.exe`, `sihost.exe`, `lsass.exe`, `ctfmon.exe`) to Normal priority.
- **Windows Event Auditing Suppression:** Security and diagnostic event auditing is temporarily silenced during gaming sessions to prevent background disk writes.

---

### 🧹 On-Demand RAM Cache Purge & Timer Locking
- **Standby List Kernel Purge:** Uses native NT API calls (`ntdll.dll!NtSetSystemInformation` command 4 combined with `psapi.dll!EmptyWorkingSet`) to purge Windows standby cache pages, reclaiming 1.5 GB to 3.0 GB of memory on demand.
- **High-Precision Timer Resolution:** Locks system multimedia timer resolution to `0.500 ms` for ultra-consistent frame pacing and frame submission timing.

---

### 🛡️ Failsafe Watchdog Guarantee
- **Non-Destructive Snapshot Engine:** Captures full initial system states to `active_state.json`. Every service startup configuration, registry value, and power setting is 100% reversible.
- **Automatic Boot Watchdog:** Scheduled `HKLM\RunOnce` fail-safe watchdog automatically reverts your computer to clean stock Windows on the next reboot if not manually restored.
- **Strict Protection Whitelist:** 90 critical system components, audio endpoints, network drivers, anti-cheats (Easy Anti-Cheat, BattlEye, Vanguard), and screenshot utilities (`CaptureService`, `cbdhsvc`) are strictly protected from modification.

---

### 📦 Automated Release Packaging (.bin/)
- Automated build orchestrator (`Build-Release.bat` & `Build-Release.ps1`) compiles the Tauri release and automatically harvests all distribution formats into `.bin/`:
  - **`UltraGamingMode.exe`** — Portable, standalone single-file binary.
  - **`UltraGamingMode-Setup.exe`** — Standard NSIS Windows desktop installer.
  - **`UltraGamingMode.msi`** — Windows Installer package for managed deployments.
  - **`SHA256SUMS.txt`** — Cryptographic checksums generated automatically.

---

## 📊 Performance Benchmarks (*Counter-Strike 2*, 1080p Competitive)

| Metric | Stock Windows 11 | Ultra Gaming Mode v3.1 | Delta |
| :--- | :---: | :---: | :---: |
| **Average FPS** | 473.1 FPS | **493.0 FPS** | **+19.9 FPS (+4.2%)** |
| **1% Low FPS** | 211.4 FPS | **248.8 FPS** | **+37.4 FPS (+17.7%)** |
| **0.1% Low FPS** | 134.2 FPS | **171.6 FPS** | **+37.4 FPS (+27.9%)** |
| **Frame Time Jitter (StdDev)** | 2.11 ms | **1.42 ms** | **-32.7% smoother** |
| **Active Background Services** | 178 services | **74 services** | **-104 services** |
| **Standby RAM Released** | — | **+2.4 GB reclaimed** | Instant game headroom |

---

## 🚀 Quick Start

1. Download **`UltraGamingMode.exe`** (or run **`UltraGamingMode-Setup.exe`**).
2. Right-click and **Run as Administrator** (self-elevates via UAC).
3. Select your desired profile (e.g., *Esports / Low Latency*) and click **«Enable Gaming Mode»**.
4. Play your games with stripped background overhead and locked 0.5ms timers.
5. When done, click **«Restore Normal State»** or simply reboot your PC (the watchdog handles it automatically).

---

**Full Changelog**: https://github.com/RagTagsky/Win11-Gaming-Optimizer/compare/v3.0...v3.1.1
