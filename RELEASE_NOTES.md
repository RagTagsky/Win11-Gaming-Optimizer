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
