# ⚡ Ultra Gaming Mode v3.2.0 — Fluent UI Overhaul, Accessibility & Extended Low-Latency Engine

**Ultra Gaming Mode v3.2.0** delivers a complete Fluent-inspired redesign and accessibility overhaul of the **Tauri v2 + Svelte 5** desktop app paired with deeper hardware latency optimizations, lossless registry snapshot recovery, live tuning hot-apply (`-Action ApplyTuning`), and an expanded **325-test** verification suite.

---

## ✨ What's New in v3.2.0

### 🎨 Fluent UI Overhaul, Dark/Light Balance & WCAG AA Accessibility (`ui/`)
- **Fluent-Balance Color & Depth System:** Refined Dark & Light palettes in `app.css` with WCAG AA text and non-text contrast (`#2563eb` primary buttons with `#ffffff` ink, crisp input/switch/badge borders), soft layered elevation shadows in Light mode, tonal layering in Dark mode, and dedicated `@media (prefers-contrast: more)` and Windows High Contrast (`forced-colors: active`) rules.
- **Flicker-Free Theme Switching & Window Sync:** Temporary transition suppression when toggling `data-theme`, `localStorage` persistence (`ugm-theme`), native DWM frame sync (`set_window_theme`), and synchronized maximize state via `toggle_maximize_window` + `onResized`. Kept `"transparent": false` and `"theme": "Dark"` in `tauri.conf.json` for reliable WebView2 startup on Windows 11.
- **Full Keyboard Navigation & Accessible Controls:** WAI-ARIA `role="tablist"` / `role="tab"` navigation (`ArrowLeft`, `ArrowRight`, `Home`, `End`) with non-color active indicator bars, unified `:focus-visible` focus rings, skip link (`.skip-link`), `prefers-reduced-motion` gating on animations/transitions, proper `<label>`/`aria-live` semantics, and Fluent typography (`Segoe UI Variable Text`, `rem` scale, `tabular-nums`, `'ru-RU'` timestamps).
- **Modal Confirmation Guardrails (`ConfirmDialog.svelte`):** Native `<dialog>` confirmation modals (autofocused on Cancel) before purging GPU shader caches, resetting the Display/DWM stack, applying/reverting Win11 Debloat, and clearing event logs.
- **Real IPC Error Visibility & Unified Controls:** Stopped masking Tauri IPC errors behind fake mock data—failures now surface actionable `role="alert"` banners with «Повторить» / «Открыть журнал». Unified Standby RAM cache cleanup under **«Обслуживание»**, preserved search/category/repair/timer state across tabs, rewrote settings copy without double negatives with selectable `<code translate="no">` keys, and added validated custom input buffer sizing (`32–4096` packets) with save-error rollback alongside presets (`64 / 100 / 150 / 200`).
- **Contract Alignment Across Rust & Frontend:** Synced `BlacklistServiceItem` (optional `Status`), full `HardwareInfo` (`display`, `dpcLatency`, `mpoStatus`), `'Enable' | 'Restore'` actions, `'competitive' | 'aaa' | 'custom'` profiles, and fixed `Transitioning` badge rendering.

---

### ⚙️ Core Engine, Kernel Latency & Safety Upgrades (`Core/` & `UltraGamingMode.ps1`)
- **Lossless Binary & Multi-String Registry Snapshots (`ConvertTo-RegistryTypedValue`):** Fixed CLR array unrolling (`return ,$bytes` / `return ,$strs`) so `REG_BINARY` (e.g., AMD `ShaderCache`) and `REG_MULTI_SZ` registry keys back up and restore byte-for-byte cleanly.
- **Live Tuning Hot-Apply (`-Action ApplyTuning`):** Changing toggles in `Config\tuning.json` from the UI while Gaming Mode is `Armed` or `GameMode_Active` triggers live synchronization via `-Action ApplyTuning`, with non-elevated safety guards in `Set-DeepGameDVROptimizations`.
- **Complete 14-Key Windows 11 Debloat Rollback:** Added two-phase restoration (`-SkipSystemPolicies` / `-UserOnly`) restoring all 14 Windows 11 telemetry, Copilot, Edge, Widget, and Search registry keys cleanly after Widgets restoration for both hashtable and `PSCustomObject` snapshots.
- **NVIDIA GeForce, USB Hub, Power Latency & NDIS Completeness:**
  - `Get-NvidiaGpuDriverClassKeys`: disables `nvlddmkm` telemetry (`SendTelemetryData = 0`), enables `RmGpsPsEnablePerCpuCoreDpc = 1` across `nvlddmkm`/`NVAPI`/`NVTweak`, and gates `DisableDynamicPstate` behind `Config\tuning.json` (`DisableNvidiaDynamicPstate`).
  - Expanded `$Script:PowerLatencySettings` to all **9** AC low-latency sub-settings (USB selective suspend, NVMe idle timeouts, Processor EPP / Throttle Max / Idle Demote & Promote, PCIe ASPM) and `$Script:NetworkAdapterGamingMap` to all **11** NDIS properties (`*FlowControl`, `*InterruptModeration`, `*EEE`, `EnableGreenEthernet`, `PowerSavingMode`, `*RscIPv4`, `*RscIPv6`, `*WakeOnMagicPacket`, `*WakeOnPattern`, `*PMARPOffload`, `*PMNSOffload`).
  - Added USB selective-suspend suppression across `HidUsb`/`USBHUB3`/`usbhub`/`usbccgp`, MMCSS `Tasks\Audio` low-latency tuning, DirectX `EnablePreemption = 1`, `Explorer\Serialize` `StartupDelayInMSec = 0`, and StickyKeys (`"506"`), ToggleKeys (`"58"`), and FilterKeys (`"122"`) hotkey guards.

---

### ✅ Verification & Test Coverage
- **PowerShell Verification (`Tests/Verify-UniversalEngine.ps1`):** Expanded from 286 to **325** automated tests covering all new optimizer targets, lossless registry round-trips, 14-key Debloat recovery, and live `ApplyTuning` workflows (**0 failures**).
- **Rust Unit Tests (`cargo test`):** Added 4 Rust unit tests in `ui/src-tauri/src/lib.rs` validating profile resolution, tuning floor safety (`>= 32`), live tuning triggering, and deserialization of all 207 blacklist & 90 whitelist services (**4 passed, 0 failed**).
- **TypeScript / Svelte Diagnostics (`npm --prefix ui run check`):** `svelte-check` and `tsc -p tsconfig.node.json` pass with **0 errors and 0 warnings**.

---

## 📦 Release Artifacts (`.bin/`)
Built via `Build-Release.ps1`:
- **`UltraGamingMode.exe`** — Portable standalone desktop binary (root & `.bin\UltraGamingMode.exe`)
- **`UltraGamingMode-Setup.exe`** — NSIS Windows installer
- **`UltraGamingMode.msi`** — Windows Installer package
- **`SHA256SUMS.txt`** — SHA-256 verification checksums

---

**Full Changelog**: https://github.com/RagTagsky/Win11-Gaming-Optimizer/compare/v3.1...v3.2.0
