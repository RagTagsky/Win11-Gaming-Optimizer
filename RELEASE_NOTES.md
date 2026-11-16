# ⚡ Ultra Gaming Mode v3.2.3 — Unified `Program Files` Installers & Runtime

**Ultra Gaming Mode v3.2.3** unifies all installation targets and standalone runtime extraction under **`C:\Program Files\UltraGamingMode`** (`perMachine`) and updates both **NSIS (`UltraGamingMode-Setup.exe`)** and **MSI (`UltraGamingMode.msi`)** finish-page launch handling for `requireAdministrator` UAC elevation.

---

## 📦 What's Changed in v3.2.3

- **Unified `Program Files` Installation (`ui/src-tauri/tauri.conf.json`, `ui/src-tauri/src/lib.rs`):**
  - Switched NSIS (`UltraGamingMode-Setup.exe`) `installMode` to `"perMachine"` so **both** `UltraGamingMode-Setup.exe` and `UltraGamingMode.msi` install to **`C:\Program Files\UltraGamingMode\`** with All Users Start Menu / Desktop shortcuts and `HKLM` registration (no split between `%LOCALAPPDATA%` and `Program Files`).
  - Pinned MSI `upgradeCode` (`7630b84c-95f6-58d0-8c30-969d061c38b0`) across releases.
  - Updated `standalone_runtime_candidates()` so standalone portable `UltraGamingMode.exe` also materializes scripts, JSON configs, and `Backups\` into **`%ProgramFiles%\UltraGamingMode`** first (`ProgramW6432` / `ProgramFiles`) with `*S-1-5-11:(OI)(CI)M` write ACLs on `Backups\` for post-reboot `RunOnce` recovery, keeping `%ProgramData%\UltraGamingMode` as fallback if unprivileged.
- **UAC-Compatible Installer Templates (`ui/src-tauri/templates/installer.nsi`, `ui/src-tauri/templates/main.wxs`):**
  - Replaced `nsis_tauri_utils::RunAsUser` (`CreateProcessWithTokenW` without elevation) with `ExecShell "open"` in the custom NSIS template so launching `UltraGamingMode.exe` from the Finish page or `/R` silent relaunch works cleanly with the `requireAdministrator` manifest.
  - Updated the WiX MSI template to read `HKLM` (`perMachine` NSIS key) for `PrevInstallDirNoName` and launch via `WixShellExec` (`WixCA`) on the Finish dialog so UAC elevation succeeds instead of hitting Error `740` / `1721`.

---

## 🔧 Previous Fixes in v3.2.2

# ⚡ Ultra Gaming Mode v3.2.2 — WebView2 Self-Termination Fix & Blank-Window Prevention

**Ultra Gaming Mode v3.2.2** resolves the solid white window crash triggered after enabling Gaming Mode or during WebView2 initialization on Windows 11, keeping the **Tauri v2 + Svelte 5** GUI alive and responsive throughout every operation.

---

## 🔧 What's Fixed in v3.2.2

- **Protected UI WebView2 & Windows Search Processes (`Config/startup_apps.json`, `Core/StateEngine.ps1`):**
  - Removed indiscriminate `"msedgewebview2"` killing from `BlacklistProcesses` (which previously terminated `UltraGamingMode.exe`'s own WebView2 renderer process during `-Action Enable`, causing the window to go blank white!).
  - Added `Test-ShouldStopWebViewProcess` and PID/name guards inside `Stop-BlacklistedProcesses` so even explicit WebView2 sweeps strictly protect `UltraGamingMode`, `SearchHost`, `TextInputHost`, `StartMenuExperienceHost`, `ShellExperienceHost`, and `LockApp`, targeting only Windows Widgets hosts.
- **Zero-Flash Dark Window Background & Boot Guard (`ui/src-tauri/tauri.conf.json`, `ui/index.html`, `ui/src-tauri/src/lib.rs`):**
  - Configured explicit dark `"backgroundColor": "#0c0e12"` on the main Tauri window and pre-CSS theme background styling in `index.html`, synchronized via `window.set_background_color(...)` on Dark/Light toggle.
  - Added an early `index.html` boot error fallback panel inside `#app` so uncaught startup exceptions never leave a blank window.
- **Non-Blocking Async IPC Commands (`ui/src-tauri/src/lib.rs`):**
  - Moved `get_system_status`, `get_tuning_config`, `save_tuning_config`, `get_services_lists`, `lock_timer_resolution`, `execute_mode_action`, and `execute_emergency_repair` onto `tauri::async_runtime::spawn_blocking` and warmed up the standalone workspace in a background thread during `.setup()`, preventing WebView2 UI thread stalls on startup.

---

## ✨ Highlights from v3.2.1 (Included in v3.2.2)

- **Self-Contained `UltraGamingMode.exe` & `NSIS`/`MSI` Installers:** All 10 runtime scripts, JSON configs, and self-tests are embedded inside `UltraGamingMode.exe` (`include_bytes!` -> `%ProgramData%\UltraGamingMode`) AND packaged cleanly inside `UltraGamingMode-Setup.exe` & `UltraGamingMode.msi` (`bundle.resources`), with UTF-8/UTF-16LE/Win32 OEM (`GetOEMCP`) error decoding.
- **Fluent UI Overhaul & Extended Optimizer:** `Fluent-баланс` Dark/Light theme system with WCAG AA / High Contrast, ARIA keyboard navigation, modal `<dialog>` confirmations, lossless `REG_BINARY`/`REG_MULTI_SZ` snapshot recovery, live `-Action ApplyTuning`, and 14-key Win11 Debloat rollback.

---

## 📦 Release Artifacts (`.bin/`)
Built via `Build-Release.ps1`:
- **`UltraGamingMode.exe`** — Fully self-contained portable binary (root & `.bin\UltraGamingMode.exe`)
- **`UltraGamingMode-Setup.exe`** — Self-contained NSIS Windows installer
- **`UltraGamingMode.msi`** — Self-contained MSI Windows Installer package
- **`SHA256SUMS.txt`** — SHA-256 verification checksums

---

**Full Changelog**: https://github.com/RagTagsky/Win11-Gaming-Optimizer/compare/v3.2.1...v3.2.2
