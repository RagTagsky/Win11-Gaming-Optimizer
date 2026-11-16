# ⚡ Ultra Gaming Mode v3.2.1 — Self-Contained Portable & Installer Runtime

**Ultra Gaming Mode v3.2.1** makes both the standalone **`UltraGamingMode.exe`** and the **`UltraGamingMode-Setup.exe` (NSIS)** / **`UltraGamingMode.msi` (MSI)** installers 100% self-contained out of the box—requiring zero repository files or external folders on any Windows 10/11 PC.

---

## 🔧 What's Fixed in v3.2.1

- **All Scripts & Configs Embedded Inside `UltraGamingMode.exe`:** Compiled `UltraGamingMode.ps1`, `UltraGamingMode.bat`, `Core\*.ps1`, `Config\*.json`, and `Tests\Verify-UniversalEngine.ps1` directly into the Rust/Tauri executable. Launching the standalone `.exe` anywhere (`Desktop`, `Downloads`, USB drive, another PC) automatically materializes the runtime into `%ProgramData%\UltraGamingMode` (preserving user-edited `Config\tuning.json` and `Backups\`) without cluttering the launch folder.
- **Included Inside NSIS & MSI Installers (`bundle.resources`):** Bundled `UltraGamingMode.ps1`, `UltraGamingMode.bat`, `Core\*.ps1`, `Config\*.json`, and `Tests\Verify-UniversalEngine.ps1` directly inside `UltraGamingMode-Setup.exe` and `UltraGamingMode.msi` so every file is present alongside `UltraGamingMode.exe` immediately after installation (`%LOCALAPPDATA%\UltraGamingMode\` or `Program Files\UltraGamingMode\`), with `Backups\` permissions configured cleanly for Boot-3 `HKLM\RunOnce` user-session restoration.
- **Clean Cyrillic / OEM Output Decoding:** Added line-by-line UTF-8, UTF-16LE, and Win32 OEM (`GetOEMCP` + `MultiByteToWideChar`) decoding for PowerShell stdout/stderr in Rust, eliminating garbled mojibake in error banners and console logs when localized Windows PowerShell errors occur.
- **Explicit Service List Error Reporting & Standalone Self-Test Fix:** Removed silent `Ok(...)` swallowing in `get_services_lists` when config JSON files fail to read/parse, and updated `Tests\Verify-UniversalEngine.ps1` root detection (`ProjectRoot`) to pass identically in packaged standalone/installed environments as well as `.git` clones (**325/325** PowerShell tests + **6/6** Rust unit tests).

---

## ✨ Highlights from v3.2.0 (Included in v3.2.1)

- **Fluent UI Overhaul & WCAG AA Accessibility (`ui/`):** Balanced Dark/Light theme system (`Fluent-баланс`), `@media (prefers-contrast: more)`, Windows High Contrast (`forced-colors: active`), `prefers-reduced-motion` gating, WAI-ARIA `tablist` arrow-key navigation, `ConfirmDialog` `<dialog>` modals for destructive/system actions, `role="alert"` IPC error banners, validated numeric queue sizing (`32–4096`) with rollback, and flicker-free DWM theme sync.
- **Core Low-Latency & Safety Engine:** Lossless `REG_BINARY` / `REG_MULTI_SZ` snapshot round-trips, live `-Action ApplyTuning`, full 14-key Win11 Debloat rollback, NVIDIA GeForce DPC & opt-in P-State control, 9 power latency settings, 11 NDIS properties, USB hub idle-suspend suppression, MMCSS `Tasks\Audio`, and DirectX `EnablePreemption`.

---

## 📦 Release Artifacts (`.bin/`)
Built via `Build-Release.ps1`:
- **`UltraGamingMode.exe`** — Fully self-contained portable binary (root & `.bin\UltraGamingMode.exe`)
- **`UltraGamingMode-Setup.exe`** — Self-contained NSIS Windows installer
- **`UltraGamingMode.msi`** — Self-contained MSI Windows Installer package
- **`SHA256SUMS.txt`** — SHA-256 verification checksums

---

**Full Changelog**: https://github.com/RagTagsky/Win11-Gaming-Optimizer/compare/v3.2.0...v3.2.1
