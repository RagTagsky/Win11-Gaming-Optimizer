use super::*;
#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::Ordering;

pub fn is_dev_repo_root(dir: &Path) -> bool {
    dir.join("UltraGamingMode.ps1").exists()
        && dir.join("Core").join("StateEngine.ps1").exists()
        && (dir.join(".git").exists() || dir.join("Build-Release.ps1").exists())
}

pub fn is_dir_writable(dir: &Path) -> bool {
    let probe = dir.join(format!(
        ".ugm_write_probe_{}_{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0)
    ));
    match std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&probe)
    {
        Ok(_) => {
            let _ = std::fs::remove_file(&probe);
            true
        }
        Err(_) => false,
    }
}

pub fn sync_embedded_runtime(root: &Path) -> Result<(), String> {
    std::fs::create_dir_all(root.join("Backups"))
        .map_err(|e| format!("Не удалось создать папку Backups в {}: {}", root.display(), e))?;

    for asset in EMBEDDED_RUNTIME_ASSETS {
        let mut dest = root.to_path_buf();
        for seg in asset.rel_path.split('/') {
            dest.push(seg);
        }
        if let Some(parent) = dest.parent() {
            std::fs::create_dir_all(parent).map_err(|e| {
                format!(
                    "Не удалось создать каталог {}: {}",
                    parent.display(),
                    e
                )
            })?;
        }

        let should_write = if !dest.exists() {
            true
        } else if asset.preserve_if_exists {
            false
        } else {
            match std::fs::read(&dest) {
                Ok(existing) => existing.as_slice() != asset.bytes,
                Err(_) => true,
            }
        };

        if should_write {
            std::fs::write(&dest, asset.bytes).map_err(|e| format_fs_write_error(&dest, &e))?;
        }
    }

    let changes = migrate_user_configs_in_place(root)?;
    for ch in changes {
        record_startup_migration_log("info", format!("Автоисправление конфига: {}", ch));
    }

    Ok(())
}

/// Safely upgrades legacy user Config/*.json files (e.g. from v3.5.x / v3.6.0)
/// in place without erasing user-customized service/process selections:
/// - Strips accidental UTF-8 BOMs from Config/*.json
/// - Migrates legacy tuning.json switches to strictly the 3 AAA automation keys
/// - Ensures critical Zapret/WinDivert/anti-cheat services are whitelisted and never blacklisted
/// - Resolves any overlap between services_whitelist.json and services_blacklist.json
/// - Ensures Zapret/winws and core OS shell processes are protected in startup_apps.json
///
/// Returns the list of applied migration descriptions, or `Err` if a required write fails.
pub fn migrate_user_configs_in_place(root: &Path) -> Result<Vec<String>, String> {
    let config_dir = root.join("Config");
    if !config_dir.is_dir() {
        return Ok(Vec::new());
    }

    let mut changes = Vec::new();

    let dir_entries = std::fs::read_dir(&config_dir)
        .map_err(|e| format!("Не удалось прочитать каталог '{}': {}", config_dir.display(), e))?;
    let mut json_paths: Vec<PathBuf> = dir_entries
        .flatten()
        .map(|e| e.path())
        .filter(|p| {
            p.extension()
                .and_then(|e| e.to_str())
                .map(|e| e.eq_ignore_ascii_case("json"))
                .unwrap_or(false)
        })
        .collect();
    json_paths.sort();

    for p in json_paths {
        let bytes = std::fs::read(&p)
            .map_err(|e| format!("Не удалось прочитать '{}': {}", p.display(), e))?;
        if bytes.starts_with(&[0xEF, 0xBB, 0xBF]) {
            std::fs::write(&p, &bytes[3..]).map_err(|e| format_fs_write_error(&p, &e))?;
            let fname = p
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("Config/*.json");
            changes.push(format!("удалён UTF-8 BOM из {}", fname));
        }
    }

    let tuning_path = config_dir.join("tuning.json");
    if tuning_path.exists() {
        let raw = std::fs::read_to_string(&tuning_path)
            .map_err(|e| format!("Не удалось прочитать '{}': {}", tuning_path.display(), e))?;
        let trimmed = raw.trim_start_matches('\u{feff}');
        match serde_json::from_str::<serde_json::Value>(trimmed) {
            Ok(serde_json::Value::Object(obj)) => {
                let needs_migration = obj.len() != 3
                    || !obj
                        .get("AutoLockTimerInGaming")
                        .map(|v| v.is_boolean())
                        .unwrap_or(false)
                    || !obj
                        .get("AutoPurgeRamInGaming")
                        .map(|v| v.is_boolean())
                        .unwrap_or(false)
                    || obj
                        .get("AutoPurgeRamThresholdMB")
                        .and_then(|v| v.as_u64())
                        .map(|n| {
                            n < MIN_AUTO_PURGE_RAM_THRESHOLD_MB as u64
                                || n > MAX_AUTO_PURGE_RAM_THRESHOLD_MB as u64
                        })
                        .unwrap_or(true);
                if needs_migration {
                    let auto_lock = obj
                        .get("AutoLockTimerInGaming")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(true);
                    let auto_purge = obj
                        .get("AutoPurgeRamInGaming")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(true);
                    let threshold_mb = obj
                        .get("AutoPurgeRamThresholdMB")
                        .and_then(|v| {
                            v.as_u64()
                                .map(|n| n.min(u32::MAX as u64) as u32)
                                .or_else(|| {
                                    v.as_i64().map(|n| {
                                        if n <= 0 {
                                            MIN_AUTO_PURGE_RAM_THRESHOLD_MB
                                        } else {
                                            n.min(u32::MAX as i64) as u32
                                        }
                                    })
                                })
                                .or_else(|| v.as_f64().map(|f| f.max(0.0) as u32))
                        })
                        .unwrap_or(DEFAULT_AUTO_PURGE_RAM_THRESHOLD_MB);
                    let normalized = normalize_tuning_config(TuningConfig {
                        auto_lock_timer_in_gaming: auto_lock,
                        auto_purge_ram_in_gaming: auto_purge,
                        auto_purge_ram_threshold_mb: threshold_mb,
                    });
                    write_json_no_bom(&tuning_path, &normalized)?;
                    changes.push(
                        "обновлён tuning.json до актуальной схемы AAA (3 параметра)".to_string(),
                    );
                }
            }
            _ => {
                write_json_no_bom(&tuning_path, &TuningConfig::default())?;
                changes.push(
                    "восстановлен повреждённый tuning.json до параметров AAA по умолчанию"
                        .to_string(),
                );
            }
        }
    }

    const MANDATORY_WHITELIST: &[&str] = &[
        "FACEIT",
        "FACEITService",
        "vgk",
        "vgc",
        "EasyAntiCheat",
        "BEService",
        "Audiosrv",
        "camsvc",
        "CaptureService",
        "cbdhsvc",
        "Apple Mobile Device Service",
        "ProcessGovernor",
        "zapret",
        "WinDivert",
        "WinDivert14",
    ];
    let wl_path = config_dir.join("services_whitelist.json");
    let bl_path = config_dir.join("services_blacklist.json");
    let mut effective_whitelist: Vec<String> = MANDATORY_WHITELIST
        .iter()
        .map(|s| (*s).to_string())
        .collect();

    if wl_path.exists() {
        let raw = std::fs::read_to_string(&wl_path)
            .map_err(|e| format!("Не удалось прочитать '{}': {}", wl_path.display(), e))?;
        if let Ok(mut wl_val) =
            serde_json::from_str::<serde_json::Value>(raw.trim_start_matches('\u{feff}'))
        {
            if let Some(arr) = wl_val
                .get_mut("ProtectedServices")
                .and_then(|v| v.as_array_mut())
            {
                let mut added_wl: Vec<&str> = Vec::new();
                for req in MANDATORY_WHITELIST {
                    let exists = arr.iter().any(|item| {
                        item.as_str()
                            .map(|s| service_names_match(s, req))
                            .unwrap_or(false)
                    });
                    if !exists {
                        arr.push(serde_json::Value::String((*req).to_string()));
                        added_wl.push(*req);
                    }
                }
                for item in arr.iter() {
                    if let Some(s) = item.as_str() {
                        if !effective_whitelist
                            .iter()
                            .any(|w| service_names_match(w, s))
                        {
                            effective_whitelist.push(s.to_string());
                        }
                    }
                }
                if !added_wl.is_empty() {
                    write_json_no_bom(&wl_path, &wl_val)?;
                    changes.push(format!(
                        "добавлены защищённые службы в services_whitelist.json ({}): {}",
                        added_wl.len(),
                        added_wl.join(", ")
                    ));
                }
            }
        }
    }

    if bl_path.exists() {
        let raw = std::fs::read_to_string(&bl_path)
            .map_err(|e| format!("Не удалось прочитать '{}': {}", bl_path.display(), e))?;
        if let Ok(mut bl_val) =
            serde_json::from_str::<serde_json::Value>(raw.trim_start_matches('\u{feff}'))
        {
            if let Some(arr) = bl_val
                .get_mut("TargetServices")
                .and_then(|v| v.as_array_mut())
            {
                let mut removed_bl: Vec<String> = Vec::new();
                arr.retain(|item| {
                    let name = item
                        .as_str()
                        .or_else(|| item.get("Name").and_then(|n| n.as_str()))
                        .unwrap_or("")
                        .trim();
                    if name.is_empty() {
                        removed_bl.push("<empty>".to_string());
                        return false;
                    }
                    let should_remove = effective_whitelist
                        .iter()
                        .any(|req| service_names_match(req, name));
                    if should_remove {
                        removed_bl.push(name.to_string());
                    }
                    !should_remove
                });
                if !removed_bl.is_empty() {
                    write_json_no_bom(&bl_path, &bl_val)?;
                    changes.push(format!(
                        "исключены защищённые службы из services_blacklist.json ({}): {}",
                        removed_bl.len(),
                        removed_bl.join(", ")
                    ));
                }
            }
        }
    }

    const MANDATORY_PROTECTED_PROCS: &[&str] = &["winws", "winws2", "zapret"];
    const FORBIDDEN_BLACKLIST_PROCS: &[&str] = &[
        "SearchHost",
        "TextInputHost",
        "UltraGamingMode",
        "winws",
        "winws2",
        "zapret",
    ];
    let st_path = config_dir.join("startup_apps.json");
    if st_path.exists() {
        let raw = std::fs::read_to_string(&st_path)
            .map_err(|e| format!("Не удалось прочитать '{}': {}", st_path.display(), e))?;
        if let Ok(mut st_val) =
            serde_json::from_str::<serde_json::Value>(raw.trim_start_matches('\u{feff}'))
        {
            let mut removed_st_bl: Vec<String> = Vec::new();
            let mut added_st_prot: Vec<&str> = Vec::new();
            if let Some(bl_arr) = st_val
                .get_mut("BlacklistProcesses")
                .and_then(|v| v.as_array_mut())
            {
                bl_arr.retain(|item| {
                    let raw_name = item.as_str().unwrap_or("").trim();
                    let clean = raw_name
                        .trim_end_matches(".exe")
                        .trim_end_matches(".EXE");
                    let forbidden = FORBIDDEN_BLACKLIST_PROCS
                        .iter()
                        .any(|forb| forb.eq_ignore_ascii_case(clean));
                    if forbidden {
                        removed_st_bl.push(clean.to_string());
                    }
                    !forbidden
                });
            }
            if let Some(prot_arr) = st_val
                .get_mut("ProtectedStartupNames")
                .and_then(|v| v.as_array_mut())
            {
                for req in MANDATORY_PROTECTED_PROCS {
                    let exists = prot_arr.iter().any(|item| {
                        item.as_str()
                            .map(|s| {
                                s.trim()
                                    .trim_end_matches(".exe")
                                    .trim_end_matches(".EXE")
                                    .eq_ignore_ascii_case(req)
                            })
                            .unwrap_or(false)
                    });
                    if !exists {
                        prot_arr.push(serde_json::Value::String((*req).to_string()));
                        added_st_prot.push(*req);
                    }
                }
            }
            if !removed_st_bl.is_empty() || !added_st_prot.is_empty() {
                write_json_no_bom(&st_path, &st_val)?;
                if !removed_st_bl.is_empty() {
                    changes.push(format!(
                        "исключены защищённые процессы из BlacklistProcesses в startup_apps.json: {}",
                        removed_st_bl.join(", ")
                    ));
                }
                if !added_st_prot.is_empty() {
                    changes.push(format!(
                        "добавлены защищённые процессы в ProtectedStartupNames в startup_apps.json: {}",
                        added_st_prot.join(", ")
                    ));
                }
            }
        }
    }

    Ok(changes)
}

pub fn ensure_backups_writable(root: &Path) {
    let backups_dir = root.join("Backups");
    let user_quarantine_dir = backups_dir.join("QuarantinedShortcuts").join("User");
    let _ = std::fs::create_dir_all(&user_quarantine_dir);

    #[cfg(target_os = "windows")]
    {
        BACKUPS_ACL_INIT.get_or_init(|| {
            if let Some(icacls) = resolve_system32_binary("icacls.exe") {
                if let Some(path_str) = user_quarantine_dir.to_str() {
                    let mut cmd = Command::new(icacls);
                    cmd.args([path_str, "/grant", "*S-1-5-11:(OI)(CI)M", "/Q"]);
                    cmd.creation_flags(CREATE_NO_WINDOW);
                    let _ = cmd.output();
                }
            }
        });
    }
}

pub fn standalone_runtime_candidates() -> Vec<PathBuf> {
    let mut out = Vec::new();
    #[cfg(target_os = "windows")]
    {
        if let Some(pf) =
            std::env::var_os("ProgramW6432").or_else(|| std::env::var_os("ProgramFiles"))
        {
            out.push(PathBuf::from(pf).join("UltraGamingMode"));
        } else {
            out.push(PathBuf::from(r"C:\Program Files\UltraGamingMode"));
        }
        if let Some(pd) =
            std::env::var_os("ProgramData").or_else(|| std::env::var_os("ALLUSERSPROFILE"))
        {
            out.push(PathBuf::from(pd).join("UltraGamingMode"));
        } else {
            out.push(PathBuf::from(r"C:\ProgramData\UltraGamingMode"));
        }
        if let Some(local) = std::env::var_os("LOCALAPPDATA") {
            out.push(PathBuf::from(&local).join("UltraGamingMode").join("Runtime"));
            out.push(PathBuf::from(local).join("UltraGamingMode"));
        }
    }
    #[cfg(any(debug_assertions, test, not(target_os = "windows")))]
    out.push(std::env::temp_dir().join("UltraGamingMode"));
    out
}

pub fn resolve_runtime_root_fresh() -> PathBuf {
    #[cfg(any(debug_assertions, test))]
    {
        if let Ok(exe) = std::env::current_exe() {
            for ancestor in exe.ancestors().skip(1) {
                if is_dev_repo_root(ancestor) {
                    return ancestor.to_path_buf();
                }
            }
        }
        if let Ok(cwd) = std::env::current_dir() {
            for ancestor in cwd.ancestors() {
                if is_dev_repo_root(ancestor) {
                    return ancestor.to_path_buf();
                }
            }
        }
        let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        if is_dev_repo_root(&manifest_dir) {
            return manifest_dir;
        }
    }

    // Clean up any leftover .exe.old or stale ugm_update_* temp staging folders from a prior self-update
    cleanup_stale_update_artifacts();

    // Portable or installed bundle with UltraGamingMode.ps1 beside UltraGamingMode.exe
    if let Ok(exe) = std::env::current_exe() {
        if let Some(exe_dir) = exe.parent() {
            if exe_dir.join("UltraGamingMode.ps1").exists() && is_dir_writable(exe_dir) {
                if let Err(e) = sync_embedded_runtime(exe_dir) {
                    record_startup_migration_log(
                        "error",
                        format!("Не удалось обновить ресурсы/конфиги в '{}': {}", exe_dir.display(), e),
                    );
                }
                ensure_backups_writable(exe_dir);
                return exe_dir.to_path_buf();
            }
        }
    }

    // Single-file portable UltraGamingMode.exe or read-only directory:
    // materialize all scripts and configs into a writable candidate.
    for candidate in standalone_runtime_candidates() {
        if std::fs::create_dir_all(&candidate).is_ok()
            && is_dir_writable(&candidate)
            && sync_embedded_runtime(&candidate).is_ok()
        {
            ensure_backups_writable(&candidate);
            return candidate;
        }
    }

    // Last-resort portable directory next to executable if writable
    if let Ok(exe) = std::env::current_exe() {
        if let Some(exe_dir) = exe.parent() {
            if is_dir_writable(exe_dir) && sync_embedded_runtime(exe_dir).is_ok() {
                ensure_backups_writable(exe_dir);
                return exe_dir.to_path_buf();
            }
        }
    }

    std::env::current_dir().unwrap_or_default()
}

pub fn get_workspace_root() -> PathBuf {
    let root = RUNTIME_ROOT_CACHE
        .get_or_init(resolve_runtime_root_fresh)
        .clone();
    if !is_dev_repo_root(&root) && !root.join("UltraGamingMode.ps1").exists() {
        let _ = sync_embedded_runtime(&root);
    }
    root
}

pub fn resolve_system32_binary(binary_name: &str) -> Option<PathBuf> {
    std::env::var_os("SystemRoot").map(|sys_root| {
        PathBuf::from(sys_root)
            .join("System32")
            .join(binary_name)
    })
}

pub fn resolve_powershell_exe() -> PathBuf {
    if let Some(sys_root) = std::env::var_os("SystemRoot") {
        let candidate = PathBuf::from(sys_root)
            .join("System32")
            .join("WindowsPowerShell")
            .join("v1.0")
            .join("powershell.exe");
        if candidate.exists() {
            return candidate;
        }
    }
    PathBuf::from(r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe")
}

#[cfg(target_os = "windows")]
pub(crate) fn decode_oem_line(bytes: &[u8]) -> Option<String> {
    if bytes.is_empty() {
        return Some(String::new());
    }
    #[link(name = "kernel32")]
    extern "system" {
        fn GetOEMCP() -> u32;
        fn MultiByteToWideChar(
            code_page: u32,
            dw_flags: u32,
            lp_multi_byte_str: *const u8,
            cb_multi_byte: i32,
            lp_wide_char_str: *mut u16,
            cch_wide_char: i32,
        ) -> i32;
    }
    let len = i32::try_from(bytes.len()).ok()?;
    unsafe {
        let mut cp = GetOEMCP();
        if cp == 0 {
            cp = 866; // fallback OEM CP866
        }
        let needed = MultiByteToWideChar(cp, 0, bytes.as_ptr(), len, std::ptr::null_mut(), 0);
        if needed <= 0 {
            return None;
        }
        let mut wide = vec![0u16; needed as usize];
        let written = MultiByteToWideChar(cp, 0, bytes.as_ptr(), len, wide.as_mut_ptr(), needed);
        if written <= 0 {
            return None;
        }
        Some(String::from_utf16_lossy(&wide[..(written as usize)]))
    }
}

pub fn decode_powershell_output(bytes: &[u8]) -> String {
    if bytes.is_empty() {
        return String::new();
    }
    if bytes.starts_with(&[0xFF, 0xFE]) && (bytes.len() - 2) % 2 == 0 {
        let units: Vec<u16> = bytes[2..]
            .chunks_exact(2)
            .map(|c| u16::from_le_bytes([c[0], c[1]]))
            .collect();
        return String::from_utf16_lossy(&units);
    }

    let trimmed = bytes.strip_prefix(&[0xEF, 0xBB, 0xBF]).unwrap_or(bytes);
    let mut lines_out = Vec::new();
    for raw_line in trimmed.split(|&b| b == b'\n') {
        let clean_line = raw_line.strip_suffix(b"\r").unwrap_or(raw_line);
        if let Ok(utf8) = std::str::from_utf8(clean_line) {
            lines_out.push(utf8.to_string());
        } else {
            #[cfg(target_os = "windows")]
            {
                if let Some(decoded) = decode_oem_line(clean_line) {
                    lines_out.push(decoded);
                    continue;
                }
            }
            lines_out.push(String::from_utf8_lossy(clean_line).into_owned());
        }
    }
    lines_out.join("\n")
}

pub fn normalize_tuning_config(mut cfg: TuningConfig) -> TuningConfig {
    cfg.auto_purge_ram_threshold_mb = cfg
        .auto_purge_ram_threshold_mb
        .clamp(MIN_AUTO_PURGE_RAM_THRESHOLD_MB, MAX_AUTO_PURGE_RAM_THRESHOLD_MB);
    cfg
}

pub fn load_tuning_from_disk(root: &Path) -> TuningConfig {
    let tuning_path = root.join("Config").join("tuning.json");
    if let Ok(raw) = std::fs::read_to_string(&tuning_path) {
        let clean = raw.trim_start_matches('\u{feff}');
        if let Ok(cfg) = serde_json::from_str::<TuningConfig>(clean) {
            return normalize_tuning_config(cfg);
        }
    }
    TuningConfig::default()
}

pub fn write_tuning_to_disk(root: &Path, cfg: &TuningConfig) -> Result<(), String> {
    let config_dir = root.join("Config");
    std::fs::create_dir_all(&config_dir)
        .map_err(|e| format!("Не удалось создать папку Config: {}", e))?;
    let tuning_path = config_dir.join("tuning.json");
    let safe_cfg = normalize_tuning_config(cfg.clone());
    write_json_no_bom(&tuning_path, &safe_cfg)
}

pub fn should_auto_purge_ram(
    mode: &str,
    cfg: &TuningConfig,
    available_ram_mb: u64,
    elapsed_since_last_purge_secs: Option<u64>,
) -> bool {
    if mode != "Gaming" || !cfg.auto_purge_ram_in_gaming {
        return false;
    }
    let threshold = cfg
        .auto_purge_ram_threshold_mb
        .clamp(MIN_AUTO_PURGE_RAM_THRESHOLD_MB, MAX_AUTO_PURGE_RAM_THRESHOLD_MB)
        as u64;
    if available_ram_mb >= threshold {
        return false;
    }
    match elapsed_since_last_purge_secs {
        Some(secs) => secs >= AUTO_PURGE_RAM_COOLDOWN_SECS,
        None => true,
    }
}

pub(crate) fn infer_service_category(name: &str, reason: &str) -> String {
    let n = strip_per_user_service_suffix(name.trim()).to_lowercase();
    let r = reason.to_lowercase();
    if n.starts_with("xbl")
        || n.starts_with("xbox")
        || n == "gamingservices"
        || n == "gamingservicesnet"
        || n == "bcastdvruserservice"
        || n == "clipsvc"
        || n == "licensemanager"
        || n == "appxsvc"
        || r.contains("xbox")
        || r.contains("gamedvr")
        || r.contains("game pass")
        || r.contains("microsoft store")
    {
        "Xbox".to_string()
    } else if n == "wuauserv"
        || n == "bits"
        || n == "dosvc"
        || n == "usosvc"
        || n == "waasmedicsvc"
        || n == "edgeupdate"
        || n == "edgeupdatem"
        || n == "gupdate"
        || n == "gupdatem"
        || n == "googleupdaterservice"
        || n == "installservice"
        || n == "pushtoinstall"
        || n == "trustedinstaller"
        || n == "clicktorunsvc"
        || r.contains("update")
        || r.contains("delivery optimization")
        || r.contains("обновлен")
    {
        "Updates".to_string()
    } else if n == "spooler"
        || n == "printnotify"
        || n == "printworkflowusersvc"
        || n == "printdeviceconfigurationservice"
        || n == "printscanbrokerservice"
        || n == "fax"
        || n == "stisvc"
        || n == "wia"
        || n == "wiarpc"
        || r.contains("print")
        || r.contains("fax")
        || r.contains("scanner")
        || r.contains("печат")
    {
        "Print".to_string()
    } else if n.contains("diag")
        || n.contains("telemetry")
        || n == "dmwappushservice"
        || n == "wersvc"
        || n == "wercplsupport"
        || n == "pcaaloha"
        || n == "pcasvc"
        || n == "dps"
        || n.starts_with("wdi")
        || n == "trkwks"
        || n == "ceip"
        || n == "uhssvc"
        || n == "pla"
        || n == "wmiapsrv"
        || n == "troubleshootingsvc"
        || n == "wuqisvc"
        || n == "wsaifabricsvc"
        || r.contains("telemetry")
        || r.contains("diagnostic")
        || r.contains("error reporting")
        || r.contains("customer experience")
        || r.contains("crash")
    {
        "Telemetry".to_string()
    } else if n == "bthserv"
        || n == "btagservice"
        || n == "bthavctpsvc"
        || n == "bluetoothuserservice"
        || n == "frameserver"
        || n == "frameservermonitor"
        || n == "penservice"
        || n == "sensrsvc"
        || n.starts_with("sensor")
        || n.starts_with("devicepicker")
        || n.starts_with("devicesflow")
        || n.starts_with("deviceassociation")
        || n == "camsvc"
        || r.contains("bluetooth")
        || r.contains("camera")
        || r.contains("webcam")
        || r.contains("sensor")
        || r.contains("hid")
        || r.contains("imaging")
    {
        "Devices".to_string()
    } else if n == "termservice"
        || n == "umrdpservice"
        || n == "sessionenv"
        || n == "hvhost"
        || n.starts_with("vmic")
        || n == "winrm"
        || n == "remoteaccess"
        || n == "remoteregistry"
        || n == "msiscsi"
        || n == "snmptrap"
        || n == "rpclocator"
        || r.contains("remote desktop")
        || r.contains("hyper-v")
        || r.contains("rdp")
        || r.contains("remote")
    {
        "Remote".to_string()
    } else if n == "wlansvc"
        || n == "wwansvc"
        || n == "icssvc"
        || n == "rasman"
        || n == "rasauto"
        || n == "ikeext"
        || n == "policyagent"
        || n == "wfdsconmgrsvc"
        || n == "wcncsvc"
        || n.starts_with("lanman")
        || n == "sharedaccess"
        || n == "alg"
        || n == "lmhosts"
        || n == "netlogon"
        || n == "ssdpsrv"
        || n == "upnphost"
        || n == "fdrespub"
        || n == "fdphost"
        || n == "iphlpsvc"
        || n == "lltdsvc"
        || n == "workfolderssvc"
        || n == "cscservice"
        || n == "peerdistsvc"
        || r.contains("network")
        || r.contains("wifi")
        || r.contains("wi-fi")
        || r.contains("wlan")
        || r.contains("routing")
        || r.contains("discovery")
        || r.contains("sharing")
        || r.contains("smb")
        || r.contains("netbios")
        || r.contains("upnp")
        || r.contains("ipv6")
        || r.contains("vpn")
        || r.contains("hotspot")
    {
        "Network".to_string()
    } else {
        "System".to_string()
    }
}

pub fn invalidate_active_state_cache() {
    if let Ok(mut guard) = ACTIVE_STATE_CACHE.lock() {
        *guard = None;
    }
}

pub(crate) fn read_cached_active_state(root: &Path) -> Option<CachedActiveState> {
    let active_state_path = root.join("Backups").join("active_state.json");
    let meta = std::fs::metadata(&active_state_path).ok()?;
    let modified = meta.modified().ok();
    let len = meta.len();

    if let Ok(guard) = ACTIVE_STATE_CACHE.lock() {
        if let Some(cached) = guard.as_ref() {
            if cached.path == active_state_path && cached.modified == modified && cached.len == len {
                return Some(cached.clone());
            }
        }
    }

    let content = std::fs::read_to_string(&active_state_path).ok()?;
    let clean = content.trim_start_matches('\u{feff}');
    let json = serde_json::from_str::<serde_json::Value>(clean).ok()?;

    let mode = match json.get("State").and_then(|v| v.as_str()) {
        Some("GameMode_Active") => "Gaming".to_string(),
        Some("Armed") => "Armed".to_string(),
        Some("Restoring_SystemDone") | Some("Restoring_UserDone") => "RestoringPending".to_string(),
        _ => "Normal".to_string(),
    };
    let active_since = if mode == "Gaming" || mode == "Armed" || mode == "RestoringPending" {
        json.get("Timestamp")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
    } else {
        None
    };

    let hw = json.get("HardwareProfile");
    let state_cpu = hw
        .and_then(|h| h.get("CpuName"))
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());
    let state_gpu = hw
        .and_then(|h| h.get("GpuName"))
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());
    let state_ram_gb = hw
        .and_then(|h| h.get("TotalRamGB"))
        .and_then(|v| v.as_f64())
        .filter(|&r| r > 0.0);

    let mut localized_service_names = std::collections::HashMap::new();
    if let Some(svcs) = json.get("Services").and_then(|v| v.as_array()) {
        for s in svcs {
            let s_name = s.get("Name").and_then(|v| v.as_str()).unwrap_or("").trim();
            let s_disp = s
                .get("DisplayName")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .trim();
            if !s_name.is_empty() && !s_disp.is_empty() {
                localized_service_names.insert(s_name.to_lowercase(), s_disp.to_string());
            }
        }
    }

    let parsed = CachedActiveState {
        path: active_state_path,
        modified,
        len,
        mode,
        active_since,
        state_cpu,
        state_gpu,
        state_ram_gb,
        localized_service_names,
    };

    if let Ok(mut guard) = ACTIVE_STATE_CACHE.lock() {
        *guard = Some(parsed.clone());
    }
    Some(parsed)
}

pub fn read_current_mode_fast(root: &Path) -> String {
    read_cached_active_state(root)
        .map(|s| s.mode)
        .unwrap_or_else(|| "Normal".to_string())
}

pub fn load_service_descriptions_map(
    root: &Path,
) -> std::collections::HashMap<String, ServiceDescriptionEntry> {
    let disk_path = root.join("Config").join("service_descriptions.json");
    let raw = std::fs::read_to_string(&disk_path).unwrap_or_else(|_| {
        String::from_utf8_lossy(include_bytes!("../../Config/service_descriptions.json")).into_owned()
    });
    let mut out = std::collections::HashMap::new();
    if let Ok(val) = serde_json::from_str::<serde_json::Value>(raw.trim_start_matches('\u{feff}')) {
        if let Some(obj) = val.get("Descriptions").and_then(|v| v.as_object()) {
            for (k, v) in obj {
                if let Ok(entry) = serde_json::from_value::<ServiceDescriptionEntry>(v.clone()) {
                    out.insert(k.to_lowercase(), entry);
                }
            }
        }
    }
    out
}

pub fn lookup_service_description<'a>(
    map: &'a std::collections::HashMap<String, ServiceDescriptionEntry>,
    service_name: &str,
) -> Option<&'a ServiceDescriptionEntry> {
    let trimmed = service_name.trim();
    let lower = trimmed.to_lowercase();
    if let Some(entry) = map.get(&lower) {
        return Some(entry);
    }
    let canon = canonical_service_name(trimmed).to_lowercase();
    map.get(&canon)
}

pub fn load_process_descriptions_map(
    root: &Path,
) -> std::collections::HashMap<String, ProcessDescriptionEntry> {
    let disk_path = root.join("Config").join("process_descriptions.json");
    let raw = std::fs::read_to_string(&disk_path).unwrap_or_else(|_| {
        String::from_utf8_lossy(include_bytes!("../../Config/process_descriptions.json")).into_owned()
    });
    let mut out = std::collections::HashMap::new();
    if let Ok(val) = serde_json::from_str::<serde_json::Value>(raw.trim_start_matches('\u{feff}')) {
        if let Some(obj) = val.get("Descriptions").and_then(|v| v.as_object()) {
            for (k, v) in obj {
                if let Ok(entry) = serde_json::from_value::<ProcessDescriptionEntry>(v.clone()) {
                    out.insert(strip_exe_suffix(k).to_lowercase(), entry);
                }
            }
        }
    }
    out
}

pub fn lookup_process_description<'a>(
    map: &'a std::collections::HashMap<String, ProcessDescriptionEntry>,
    process_name: &str,
) -> Option<&'a ProcessDescriptionEntry> {
    let clean = strip_exe_suffix(process_name).trim().to_lowercase();
    if clean.is_empty() {
        return None;
    }
    map.get(&clean)
}

pub(crate) fn get_cached_hw_static() -> &'static CachedHardwareStatic {
    HW_STATIC_CACHE.get_or_init(|| {
        #[cfg(target_os = "windows")]
        let cpu = win_hw::detect_cpu_name().unwrap_or_else(|| "Неизвестный процессор".to_string());
        #[cfg(not(target_os = "windows"))]
        let cpu = "Processor".to_string();

        #[cfg(target_os = "windows")]
        let gpu = win_hw::detect_gpu_name().unwrap_or_else(|| "Видеоадаптер".to_string());
        #[cfg(not(target_os = "windows"))]
        let gpu = "Graphics Adapter".to_string();

        CachedHardwareStatic { cpu, gpu }
    })
}

pub fn read_system_status_sync() -> Result<SystemStatus, String> {
    let root = get_workspace_root();
    let hw_static = get_cached_hw_static();

    let mut mode = "Normal".to_string();
    let mut active_since: Option<String> = None;
    let mut cpu = hw_static.cpu.clone();
    let mut gpu = hw_static.gpu.clone();

    #[cfg(target_os = "windows")]
    let mut ram = win_hw::detect_ram_gb().unwrap_or_else(|| "ОЗУ".to_string());
    #[cfg(not(target_os = "windows"))]
    let mut ram = "RAM".to_string();

    if let Some(cached) = read_cached_active_state(&root) {
        mode = cached.mode;
        active_since = cached.active_since;
        if let Some(c) = cached.state_cpu {
            cpu = c;
        }
        if let Some(g) = cached.state_gpu {
            gpu = g;
        }
        if ram == "ОЗУ" {
            if let Some(r) = cached.state_ram_gb {
                ram = format!("{:.0} ГБ ОЗУ", r);
            }
        }
    }

    let profile = "aaa".to_string();

    #[cfg(target_os = "windows")]
    let display = win_hw::detect_display_summary();
    #[cfg(not(target_os = "windows"))]
    let display = "Primary Display".to_string();

    #[cfg(target_os = "windows")]
    let dpc_latency = win_hw::detect_dpc_status();
    #[cfg(not(target_os = "windows"))]
    let dpc_latency = "Threaded DPC".to_string();

    #[cfg(target_os = "windows")]
    let mpo_status = win_hw::detect_mpo_status();
    #[cfg(not(target_os = "windows"))]
    let mpo_status = "Default".to_string();

    let is_locked = TIMER_LOCKED.load(Ordering::SeqCst);
    let timer_resolution = timer::query_timer_resolution()
        .map(|ms| {
            if is_locked {
                format!("{:.3} мс (зафиксировано)", ms)
            } else {
                format!("{:.3} мс", ms)
            }
        })
        .or_else(|| {
            Some(if is_locked {
                "0.500 мс (зафиксировано)".into()
            } else {
                "1.000 мс (штатный)".into()
            })
        });

    Ok(SystemStatus {
        mode,
        profile,
        hardware: HardwareInfo {
            cpu,
            gpu,
            ram,
            display,
            dpc_latency,
            mpo_status,
            timer_resolution,
        },
        active_since,
    })
}

pub fn read_tuning_config_sync() -> Result<TuningConfig, String> {
    let root = get_workspace_root();
    Ok(load_tuning_from_disk(&root))
}

pub fn should_trigger_live_tuning(raw_state: &str) -> bool {
    let clean_state = raw_state.trim_start_matches('\u{feff}');
    if let Ok(state_val) = serde_json::from_str::<serde_json::Value>(clean_state) {
        if let Some(state_str) = state_val.get("State").and_then(|v| v.as_str()) {
            return state_str == "Armed" || state_str == "GameMode_Active";
        }
    }
    false
}

pub fn write_tuning_config_sync(config: TuningConfig) -> Result<TuningConfig, String> {
    let root = get_workspace_root();
    let normalized = normalize_tuning_config(config);
    write_tuning_to_disk(&root, &normalized)?;
    Ok(normalized)
}

pub fn read_services_lists_from_root(
    root: &Path,
    include_live_status: bool,
) -> Result<ServicesLists, String> {
    let bl_path = root.join("Config").join("services_blacklist.json");
    let wl_path = root.join("Config").join("services_whitelist.json");

    let localized_names = read_cached_active_state(root)
        .map(|s| s.localized_service_names)
        .unwrap_or_default();
    let desc_map = load_service_descriptions_map(root);

    #[cfg(target_os = "windows")]
    let live_map = if include_live_status {
        win_hw::enumerate_live_services()
    } else {
        std::collections::HashMap::new()
    };
    #[cfg(not(target_os = "windows"))]
    let live_map: std::collections::HashMap<String, (String, String, String)> =
        std::collections::HashMap::new();

    let raw_bl = std::fs::read_to_string(&bl_path).map_err(|e| {
        format!(
            "Не удалось прочитать список служб ({}): {}",
            bl_path.display(),
            e
        )
    })?;
    let val_bl: serde_json::Value =
        serde_json::from_str(raw_bl.trim_start_matches('\u{feff}')).map_err(|e| {
            format!(
                "Ошибка разбора списка служб ({}): {}",
                bl_path.display(),
                e
            )
        })?;
    let arr_bl = val_bl
        .get("TargetServices")
        .and_then(|v| v.as_array())
        .ok_or_else(|| format!("В файле {} отсутствует поле TargetServices", bl_path.display()))?;

    let find_live_entry = |svc_name: &str| -> Option<&(String, String, String)> {
        let trimmed = svc_name.trim();
        let lower = trimmed.to_lowercase();
        if let Some(exact) = live_map.get(&lower) {
            return Some(exact);
        }
        let target_canon = canonical_service_name(trimmed);
        for v in live_map.values() {
            if canonical_service_name(&v.0).eq_ignore_ascii_case(target_canon) {
                return Some(v);
            }
        }
        None
    };

    let mut blacklist: Vec<BlacklistServiceItem> = Vec::with_capacity(arr_bl.len());
    let mut bl_category_map: std::collections::HashMap<String, String> =
        std::collections::HashMap::new();
    for item in arr_bl {
        if let Ok(mut parsed) = serde_json::from_value::<BlacklistServiceItem>(item.clone()) {
            #[cfg(target_os = "windows")]
            if include_live_status {
                let mut matched_live_name: Option<String> = None;
                if let Some((orig_name, status, scm_disp)) = find_live_entry(&parsed.name) {
                    matched_live_name = Some(orig_name.clone());
                    if parsed.status.trim().is_empty() {
                        parsed.status = status.clone();
                    }
                    if parsed.display_name.trim().is_empty() && !scm_disp.trim().is_empty() {
                        parsed.display_name = scm_disp.trim().to_string();
                    }
                } else if parsed.status.trim().is_empty() {
                    parsed.status = "NotInstalled".to_string();
                }
                if parsed.start_type.trim().is_empty() {
                    if let Some(ref live_name) = matched_live_name {
                        parsed.start_type = win_hw::read_service_start_type(live_name);
                    }
                    if parsed.start_type.trim().is_empty() {
                        parsed.start_type = win_hw::read_service_start_type(&parsed.name);
                    }
                }
            }

            if parsed.display_name.trim().is_empty() {
                if let Some(loc) = localized_names.get(&parsed.name.to_lowercase()) {
                    parsed.display_name = loc.clone();
                } else {
                    parsed.display_name = parsed.reason.clone();
                }
            }
            if parsed.category.trim().is_empty() {
                parsed.category = infer_service_category(&parsed.name, &parsed.reason);
            }
            let is_core = is_immutable_core_service(&parsed.name);
            if let Some(desc) = lookup_service_description(&desc_map, &parsed.name) {
                if parsed.summary_ru.trim().is_empty() {
                    parsed.summary_ru = desc.summary_ru.clone();
                }
                if parsed.can_disable_hint.trim().is_empty() {
                    parsed.can_disable_hint = desc.can_disable_ru.clone();
                }
                parsed.safety_level = normalize_safety_level(&desc.safety_level, is_core);
            } else {
                parsed.safety_level = normalize_safety_level(&parsed.safety_level, is_core);
            }
            bl_category_map.insert(
                canonical_service_name(&parsed.name).to_lowercase(),
                parsed.category.clone(),
            );
            blacklist.push(parsed);
        }
    }

    let raw_wl = std::fs::read_to_string(&wl_path).map_err(|e| {
        format!(
            "Не удалось прочитать белый список служб ({}): {}",
            wl_path.display(),
            e
        )
    })?;
    let val_wl: serde_json::Value =
        serde_json::from_str(raw_wl.trim_start_matches('\u{feff}')).map_err(|e| {
            format!(
                "Ошибка разбора белого списка ({}): {}",
                wl_path.display(),
                e
            )
        })?;
    let arr_wl = val_wl
        .get("ProtectedServices")
        .and_then(|v| v.as_array())
        .ok_or_else(|| {
            format!(
                "В файле {} отсутствует поле ProtectedServices",
                wl_path.display()
            )
        })?;

    let mut whitelist: Vec<String> = Vec::with_capacity(arr_wl.len());
    let mut whitelist_descriptions = std::collections::HashMap::new();
    let mut whitelist_items: Vec<WhitelistServiceItem> = Vec::with_capacity(arr_wl.len());

    for item in arr_wl {
        if let Some(s) = item.as_str() {
            let desc = lookup_service_description(&desc_map, s);
            if let Some(d) = desc {
                whitelist_descriptions.insert(s.to_string(), d.clone());
            }
            let (status, scm_disp) = if include_live_status {
                if let Some((_orig, st, disp)) = find_live_entry(s) {
                    (st.clone(), disp.trim().to_string())
                } else {
                    ("NotInstalled".to_string(), String::new())
                }
            } else {
                (String::new(), String::new())
            };
            let display_name = if !scm_disp.is_empty() {
                scm_disp
            } else if let Some(loc) = localized_names.get(&s.to_lowercase()) {
                loc.clone()
            } else {
                s.to_string()
            };
            let is_core = is_immutable_core_service(s);
            let summary_ru = desc.map(|d| d.summary_ru.clone()).unwrap_or_default();
            let can_disable_hint = desc.map(|d| d.can_disable_ru.clone()).unwrap_or_default();
            let safety_level = normalize_safety_level(
                desc.map(|d| d.safety_level.as_str()).unwrap_or("protected"),
                is_core,
            );
            whitelist_items.push(WhitelistServiceItem {
                name: s.to_string(),
                display_name,
                status,
                is_core_locked: is_core,
                summary_ru,
                can_disable_hint,
                safety_level,
            });
            whitelist.push(s.to_string());
        }
    }

    let in_whitelist = |svc: &str| -> bool {
        whitelist.iter().any(|w| service_names_match(w, svc))
    };
    let in_blacklist = |svc: &str| -> bool {
        blacklist.iter().any(|b| service_names_match(&b.name, svc))
    };

    let mut all_installed_services: Vec<InstalledServiceItem> = Vec::new();
    if include_live_status {
        #[cfg(target_os = "windows")]
        let scm_desc_fallback = {
            let missing_names: Vec<String> = live_map
                .values()
                .filter(|(orig_name, _, _)| lookup_service_description(&desc_map, orig_name).is_none())
                .map(|(orig_name, _, _)| orig_name.clone())
                .collect();
            win_hw::read_service_scm_descriptions(&missing_names)
        };
        #[cfg(not(target_os = "windows"))]
        let scm_desc_fallback: std::collections::HashMap<String, String> =
            std::collections::HashMap::new();

        for (orig_name, status, scm_disp) in live_map.values() {
            let is_core = is_immutable_core_service(orig_name);
            let wl_hit = in_whitelist(orig_name);
            let bl_hit = in_blacklist(orig_name);
            let membership = if is_core {
                "core"
            } else if wl_hit {
                "whitelist"
            } else if bl_hit {
                "blacklist"
            } else {
                "none"
            }
            .to_string();
            let disable_in_gaming = !is_core && !wl_hit && bl_hit;

            let disp = if scm_disp.trim().is_empty() {
                orig_name.clone()
            } else {
                scm_disp.trim().to_string()
            };
            let canon = canonical_service_name(orig_name);
            let cat = bl_category_map
                .get(&orig_name.to_lowercase())
                .or_else(|| bl_category_map.get(&canon.to_lowercase()))
                .cloned()
                .unwrap_or_else(|| infer_service_category(orig_name, &disp));
            let desc = lookup_service_description(&desc_map, orig_name);
            let summary_ru = if let Some(d) = desc.filter(|d| !d.summary_ru.trim().is_empty()) {
                d.summary_ru.clone()
            } else if let Some(scm_d) = scm_desc_fallback.get(&orig_name.to_lowercase()) {
                scm_d.clone()
            } else {
                format!("Служба Windows или стороннего ПО («{}»).", disp)
            };
            let can_disable_hint = if let Some(d) =
                desc.filter(|d| !d.can_disable_ru.trim().is_empty())
            {
                d.can_disable_ru.clone()
            } else if is_core {
                "Критическая служба ядра Windows — отключать нельзя.".to_string()
            } else {
                "Редкая или сторонняя служба. Отключайте в Gaming Mode, только если уверены, что она не нужна во время игры.".to_string()
            };
            let safety_level = normalize_safety_level(
                desc.map(|d| d.safety_level.as_str()).unwrap_or("optional"),
                is_core,
            );
            #[cfg(target_os = "windows")]
            let start_type = win_hw::read_service_start_type(orig_name);
            #[cfg(not(target_os = "windows"))]
            let start_type = String::new();

            all_installed_services.push(InstalledServiceItem {
                name: orig_name.clone(),
                display_name: disp,
                status: status.clone(),
                start_type,
                category: cat,
                membership,
                is_core_locked: is_core,
                disable_in_gaming,
                summary_ru,
                can_disable_hint,
                safety_level,
            });
        }
        all_installed_services.sort_by(|a, b| {
            let a_run = if a.status == "Running" { 0u8 } else { 1u8 };
            let b_run = if b.status == "Running" { 0u8 } else { 1u8 };
            a_run
                .cmp(&b_run)
                .then_with(|| a.display_name.to_lowercase().cmp(&b.display_name.to_lowercase()))
                .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
        });
    }

    #[cfg(target_os = "windows")]
    let wifi_active = if include_live_status
        && live_map
            .get("wlansvc")
            .map(|v| v.1 == "Running")
            .unwrap_or(false)
    {
        win_hw::is_wifi_connected()
    } else {
        false
    };
    #[cfg(not(target_os = "windows"))]
    let wifi_active = false;

    let feature_packs: Vec<ServiceFeaturePack> = SERVICE_FEATURE_PACKS
        .iter()
        .map(|p| {
            let keep_enabled = p
                .services
                .iter()
                .all(|s| in_whitelist(s) && !in_blacklist(s));
            ServiceFeaturePack {
                id: p.id.to_string(),
                title: p.title.to_string(),
                description: p.description.to_string(),
                keep_enabled_in_game: keep_enabled,
                services: p.services.iter().map(|s| (*s).to_string()).collect(),
            }
        })
        .collect();

    Ok(ServicesLists {
        blacklist,
        whitelist,
        whitelist_descriptions,
        whitelist_items,
        all_installed_services,
        wifi_active,
        feature_packs,
    })
}

pub fn apply_service_feature_pack_in_root(
    root: &Path,
    pack_id: &str,
    keep_enabled_in_game: bool,
    include_live_status: bool,
) -> Result<ServicesLists, String> {
    let pack = SERVICE_FEATURE_PACKS
        .iter()
        .find(|p| p.id.eq_ignore_ascii_case(pack_id.trim()))
        .ok_or_else(|| format!("Неизвестный пакет функций служб: '{}'", pack_id))?;

    let bl_path = root.join("Config").join("services_blacklist.json");
    let wl_path = root.join("Config").join("services_whitelist.json");
    let desc_map = load_service_descriptions_map(root);

    let raw_bl = std::fs::read_to_string(&bl_path)
        .map_err(|e| format!("Не удалось прочитать {}: {}", bl_path.display(), e))?;
    let mut doc_bl: serde_json::Value =
        serde_json::from_str(raw_bl.trim_start_matches('\u{feff}'))
            .map_err(|e| format!("Ошибка разбора {}: {}", bl_path.display(), e))?;

    let raw_wl = std::fs::read_to_string(&wl_path)
        .map_err(|e| format!("Не удалось прочитать {}: {}", wl_path.display(), e))?;
    let mut doc_wl: serde_json::Value =
        serde_json::from_str(raw_wl.trim_start_matches('\u{feff}'))
            .map_err(|e| format!("Ошибка разбора {}: {}", wl_path.display(), e))?;

    let wl_arr = doc_wl
        .get_mut("ProtectedServices")
        .and_then(|v| v.as_array_mut())
        .ok_or_else(|| "Отсутствует массив ProtectedServices".to_string())?;

    if keep_enabled_in_game {
        for &svc in pack.services {
            if !wl_arr
                .iter()
                .filter_map(|v| v.as_str())
                .any(|s| service_names_match(s, svc))
            {
                wl_arr.push(serde_json::Value::String(svc.to_string()));
            }
        }
        if let Some(bl_arr) = doc_bl
            .get_mut("TargetServices")
            .and_then(|v| v.as_array_mut())
        {
            bl_arr.retain(|item| {
                let name = item.get("Name").and_then(|v| v.as_str()).unwrap_or("");
                !pack.services.iter().any(|s| service_names_match(s, name))
            });
        }
    } else {
        wl_arr.retain(|v| {
            let Some(name) = v.as_str() else { return true };
            if is_immutable_core_service(name) {
                return true;
            }
            !pack.services.iter().any(|s| service_names_match(s, name))
        });

        let bl_arr = doc_bl
            .get_mut("TargetServices")
            .and_then(|v| v.as_array_mut())
            .ok_or_else(|| "Отсутствует массив TargetServices".to_string())?;

        for &svc in pack.services {
            if is_immutable_core_service(svc) {
                continue;
            }
            let exists = bl_arr.iter().any(|item| {
                item.get("Name")
                    .and_then(|v| v.as_str())
                    .map(|n| service_names_match(n, svc))
                    .unwrap_or(false)
            });
            if !exists {
                let reason = lookup_service_description(&desc_map, svc)
                    .map(|d| d.summary_ru.clone())
                    .filter(|s| !s.trim().is_empty())
                    .unwrap_or_else(|| pack.description.to_string());
                let cat = infer_service_category(svc, &reason);
                let mut map = serde_json::Map::new();
                map.insert("Name".into(), serde_json::Value::String(svc.to_string()));
                map.insert("Category".into(), serde_json::Value::String(cat));
                map.insert("Reason".into(), serde_json::Value::String(reason));
                bl_arr.push(serde_json::Value::Object(map));
            }
        }
    }

    write_json_no_bom(&wl_path, &doc_wl)?;
    write_json_no_bom(&bl_path, &doc_bl)?;
    read_services_lists_from_root(root, include_live_status)
}

pub fn read_services_lists_sync() -> Result<ServicesLists, String> {
    let root = get_workspace_root();
    read_services_lists_from_root(&root, cfg!(target_os = "windows"))
}

pub fn compute_initial_disabled_counts(root: &Path) -> (usize, usize) {
    let disabled_services = read_services_lists_from_root(root, false)
        .map(|lists| {
            lists
                .blacklist
                .iter()
                .filter(|b| {
                    !is_immutable_core_service(&b.name)
                        && !lists
                            .whitelist
                            .iter()
                            .any(|w| service_names_match(w, &b.name))
                })
                .count()
        })
        .unwrap_or(205);

    let disabled_processes = read_process_lists_from_root(root)
        .map(|cfg| {
            let prot_set: std::collections::HashSet<String> = cfg
                .protected_startup_names
                .iter()
                .map(|s| strip_exe_suffix(s).trim().to_lowercase())
                .filter(|s| !s.is_empty())
                .collect();
            let mut seen = std::collections::HashSet::new();
            for raw in &cfg.blacklist_processes {
                let clean = strip_exe_suffix(raw).trim();
                let key = clean.to_lowercase();
                if !key.is_empty()
                    && !is_protected_process_name(clean)
                    && !prot_set.contains(&key)
                {
                    seen.insert(key);
                }
            }
            seen.len()
        })
        .unwrap_or(40);

    (disabled_services, disabled_processes)
}
