use super::*;
#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::Ordering;

pub fn run_powershell_script(
    root: &Path,
    script_path: &Path,
    args: &[&str],
    success_fallback: String,
    spawn_error_prefix: &str,
) -> Result<ActionResult, String> {
    if !script_path.exists() {
        return Err(format!(
            "Скрипт движка не найден по пути: {}",
            script_path.display()
        ));
    }
    let script_str = script_path
        .to_str()
        .ok_or_else(|| "Путь к скрипту содержит недопустимые символы".to_string())?;

    let mut cmd = Command::new(resolve_powershell_exe());
    cmd.current_dir(root)
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            script_str,
        ])
        .args(args);
    #[cfg(target_os = "windows")]
    cmd.creation_flags(CREATE_NO_WINDOW);

    let output = cmd
        .output()
        .map_err(|e| format!("{}: {}", spawn_error_prefix, e))?;

    let stdout = decode_powershell_output(&output.stdout).trim().to_string();
    let stderr = decode_powershell_output(&output.stderr).trim().to_string();
    let success = output.status.success();

    let message = if success {
        if stdout.is_empty() {
            success_fallback
        } else {
            stdout
                .lines()
                .filter(|l| !l.trim().is_empty())
                .rev()
                .take(3)
                .collect::<Vec<_>>()
                .into_iter()
                .rev()
                .collect::<Vec<_>>()
                .join(" | ")
        }
    } else {
        let mut err = String::new();
        if !stderr.is_empty() {
            err.push_str(&stderr);
        }
        if !stdout.is_empty() {
            if !err.is_empty() {
                err.push('\n');
            }
            err.push_str(&stdout);
        }
        if err.is_empty() {
            format!(
                "Процесс завершился с кодом ошибки {:?}",
                output.status.code()
            )
        } else {
            err
        }
    };

    Ok(ActionResult {
        success,
        message,
        log_entries: Vec::new(),
    })
}

pub fn run_execute_mode_action_sync(action: &str) -> Result<ActionResult, String> {
    let safe_action = match action {
        "Enable" => "Enable",
        "Restore" => "Restore",
        _ => return Err(format!("Недопустимое действие режима: {}", action)),
    };
    let Some(_mode_guard) = try_acquire_mode_action_guard() else {
        return Err("Операция переключения режима уже выполняется. Дождитесь завершения.".to_string());
    };
    let root = get_workspace_root();
    let script_path = root.join("UltraGamingMode.ps1");

    let res = run_powershell_script(
        &root,
        &script_path,
        &["-Action", safe_action, "-SkipUpdateCheck"],
        format!("Действие [{}] выполнено успешно.", safe_action),
        "Не удалось запустить PowerShell",
    );
    if safe_action == "Restore" {
        if TIMER_LOCKED.swap(false, Ordering::SeqCst) {
            let _ = timer::unlock_timer_resolution();
        }
    }
    invalidate_active_state_cache();
    res
}

pub fn run_finish_pending_restore_sync() -> Result<ActionResult, String> {
    let Some(_mode_guard) = try_acquire_mode_action_guard() else {
        return Err("Операция восстановления уже выполняется. Дождитесь завершения.".to_string());
    };
    let root = get_workspace_root();
    let script_path = root.join("UltraGamingMode.ps1");
    let state_file = root.join("Backups").join("active_state.json");
    let raw_state_name = std::fs::read_to_string(&state_file)
        .ok()
        .and_then(|s| serde_json::from_str::<serde_json::Value>(s.trim_start_matches('\u{feff}')).ok())
        .and_then(|v| v.get("State").and_then(|x| x.as_str()).map(|x| x.to_string()));

    let action_arg = if raw_state_name.as_deref() == Some("Restoring_UserDone") {
        #[cfg(target_os = "windows")]
        let elevated = win_hw::is_current_process_elevated();
        #[cfg(not(target_os = "windows"))]
        let elevated = true;
        if elevated { "Restore" } else { "RestoreUser" }
    } else {
        "RestoreUser"
    };

    let res = run_powershell_script(
        &root,
        &script_path,
        &["-Action", action_arg, "-SkipUpdateCheck"],
        "Восстановление профиля успешно завершено.".to_string(),
        "Не удалось завершить восстановление профиля",
    );
    if TIMER_LOCKED.swap(false, Ordering::SeqCst) {
        let _ = timer::unlock_timer_resolution();
    }
    invalidate_active_state_cache();
    res
}

pub(crate) fn clear_dir_contents(dir: &Path) -> (usize, u64) {
    let mut removed_files = 0usize;
    let mut freed_bytes = 0u64;
    let Ok(entries) = std::fs::read_dir(dir) else {
        return (0, 0);
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if let Ok(meta) = entry.metadata() {
            if meta.is_dir() {
                let (c, b) = clear_dir_contents(&path);
                removed_files += c;
                freed_bytes += b;
                let _ = std::fs::remove_dir(&path);
            } else {
                let len = meta.len();
                if std::fs::remove_file(&path).is_ok() {
                    removed_files += 1;
                    freed_bytes += len;
                }
            }
        }
    }
    (removed_files, freed_bytes)
}

pub fn flush_shader_cache_native_impl(
    local_app_data: Option<&Path>,
    app_data: Option<&Path>,
) -> (usize, f64) {
    const LOCAL_REL_DIRS: &[&str] = &[
        r"AMD\DxCache",
        r"AMD\VkCache",
        r"AMD\DxcCache",
        r"AMD\DX9Cache",
        r"AMD\OglCache",
        r"NVIDIA\DXCache",
        r"NVIDIA\GLCache",
        r"NVIDIA Corporation\NV_Cache",
        r"Intel\ShaderCache",
        r"Intel\D3DSCache",
        r"D3DSCache",
    ];
    let mut total_files = 0usize;
    let mut total_bytes = 0u64;

    if let Some(local) = local_app_data {
        for rel in LOCAL_REL_DIRS {
            let candidate = local.join(rel);
            if candidate.is_dir() {
                let (c, b) = clear_dir_contents(&candidate);
                total_files += c;
                total_bytes += b;
            }
        }
    }
    if let Some(roaming) = app_data {
        let nv_compute = roaming.join("NVIDIA").join("ComputeCache");
        if nv_compute.is_dir() {
            let (c, b) = clear_dir_contents(&nv_compute);
            total_files += c;
            total_bytes += b;
        }
    }

    let freed_mb = ((total_bytes as f64) / (1024.0 * 1024.0) * 10.0).round() / 10.0;
    (total_files, freed_mb)
}

pub fn clean_memory_native_sync() -> Result<ActionResult, String> {
    #[cfg(target_os = "windows")]
    {
        let freed_mb = win_hw::clean_memory_win32()?;
        Ok(ActionResult {
            success: true,
            message: format!(
                "Кэш ОЗУ (Standby List) очищен. Освобождено {:.1} МБ.",
                freed_mb
            ),
            log_entries: Vec::new(),
        })
    }
    #[cfg(not(target_os = "windows"))]
    {
        Ok(ActionResult {
            success: true,
            message: "Кэш ОЗУ очищен (симуляция вне Windows).".to_string(),
            log_entries: Vec::new(),
        })
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum VerifyVerdict {
    Passed {
        summary: String,
    },
    Failed {
        summary: Option<String>,
        fail_lines: Vec<String>,
        extra_error: Option<String>,
    },
    Unknown {
        reason: String,
    },
}

pub fn parse_test_results_counts(line: &str) -> Option<(u64, u64)> {
    let idx = line.find("TEST RESULTS:")?;
    let after = line[idx + "TEST RESULTS:".len()..].trim();
    let mut parts = after.split('|');
    let left = parts.next()?.trim();
    let right = parts.next()?.trim();
    let tests_run = left.split_whitespace().next()?.parse::<u64>().ok()?;
    let failures = right.split_whitespace().next()?.parse::<u64>().ok()?;
    Some((tests_run, failures))
}

pub(crate) fn extract_concise_non_pass_error(stdout: &str, stderr: &str) -> Option<String> {
    let mut candidates: Vec<&str> = Vec::new();
    for src in [stderr, stdout] {
        for raw in src.lines() {
            let t = raw.trim();
            if t.is_empty()
                || t.starts_with("[PASS]")
                || t.starts_with("[Test Group")
                || t.starts_with("===")
                || t.contains("ULTRA GAMING MODE ENGINE VERIFICATION SUITE")
            {
                continue;
            }
            candidates.push(t);
            if candidates.len() >= 3 {
                break;
            }
        }
        if !candidates.is_empty() {
            break;
        }
    }
    if candidates.is_empty() {
        None
    } else {
        Some(candidates.join(" | "))
    }
}

pub fn evaluate_verify_output(
    exit_success: bool,
    exit_code: Option<i32>,
    stdout: &str,
    stderr: &str,
) -> VerifyVerdict {
    let test_results_line = stdout
        .lines()
        .chain(stderr.lines())
        .rev()
        .map(|l| l.trim())
        .find(|l| l.contains("TEST RESULTS:"))
        .map(|s| s.to_string());

    let fail_lines: Vec<String> = stdout
        .lines()
        .chain(stderr.lines())
        .map(|l| l.trim())
        .filter(|l| l.starts_with("[FAIL]"))
        .map(|s| s.to_string())
        .collect();

    if !fail_lines.is_empty() {
        return VerifyVerdict::Failed {
            summary: test_results_line,
            fail_lines,
            extra_error: None,
        };
    }

    if let Some(summary) = test_results_line {
        match parse_test_results_counts(&summary) {
            Some((tests_run, 0)) if tests_run > 0 && exit_success => {
                VerifyVerdict::Passed { summary }
            }
            Some((0, _)) => VerifyVerdict::Unknown {
                reason: format!(
                    "В выводе проверки не выполнено ни одного теста ({}) — результат неизвестен.",
                    summary
                ),
            },
            Some((_, failures)) if failures > 0 || !exit_success => VerifyVerdict::Failed {
                summary: Some(summary),
                fail_lines,
                extra_error: extract_concise_non_pass_error(stdout, stderr),
            },
            _ => VerifyVerdict::Unknown {
                reason: format!(
                    "Не удалось разобрать итоговую строку проверки ({}) — результат неизвестен.",
                    summary
                ),
            },
        }
    } else if exit_success {
        VerifyVerdict::Unknown {
            reason: "Проверка завершилась без итоговой строки TEST RESULTS — результат неизвестен."
                .to_string(),
        }
    } else {
        let extra = extract_concise_non_pass_error(stdout, stderr);
        let suffix = extra
            .map(|e| format!(" ({})", e))
            .unwrap_or_default();
        VerifyVerdict::Unknown {
            reason: format!(
                "Проверка прервана до формирования TEST RESULTS (код {:?}) — результат неизвестен.{}",
                exit_code, suffix
            ),
        }
    }
}

pub fn format_local_hms() -> String {
    #[cfg(target_os = "windows")]
    {
        #[repr(C)]
        struct SystemTimeWin32 {
            year: u16,
            month: u16,
            day_of_week: u16,
            day: u16,
            hour: u16,
            minute: u16,
            second: u16,
            milliseconds: u16,
        }
        #[link(name = "kernel32")]
        extern "system" {
            fn GetLocalTime(lp_system_time: *mut SystemTimeWin32);
        }
        let mut st = SystemTimeWin32 {
            year: 1970,
            month: 1,
            day_of_week: 0,
            day: 1,
            hour: 0,
            minute: 0,
            second: 0,
            milliseconds: 0,
        };
        unsafe {
            GetLocalTime(&mut st);
        }
        format!("{:02}:{:02}:{:02}", st.hour, st.minute, st.second)
    }
    #[cfg(not(target_os = "windows"))]
    {
        let secs = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        let s = secs % 60;
        let m = (secs / 60) % 60;
        let h = (secs / 3600) % 24;
        format!("{:02}:{:02}:{:02}", h, m, s)
    }
}

pub(crate) fn format_verify_log_timestamp() -> (String, u16) {
    #[cfg(target_os = "windows")]
    {
        #[repr(C)]
        struct SystemTimeWin32 {
            year: u16,
            month: u16,
            day_of_week: u16,
            day: u16,
            hour: u16,
            minute: u16,
            second: u16,
            milliseconds: u16,
        }
        #[link(name = "kernel32")]
        extern "system" {
            fn GetLocalTime(lp_system_time: *mut SystemTimeWin32);
        }
        let mut st = SystemTimeWin32 {
            year: 1970,
            month: 1,
            day_of_week: 0,
            day: 1,
            hour: 0,
            minute: 0,
            second: 0,
            milliseconds: 0,
        };
        unsafe {
            GetLocalTime(&mut st);
        }
        let stamp = format!(
            "{:04}-{:02}-{:02}_{:02}-{:02}-{:02}",
            st.year, st.month, st.day, st.hour, st.minute, st.second
        );
        (stamp, st.milliseconds)
    }
    #[cfg(not(target_os = "windows"))]
    {
        let dur = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default();
        let secs = dur.as_secs();
        let ms = dur.subsec_millis() as u16;
        let days = (secs / 86_400) as i64;
        let rem = secs % 86_400;
        let h = rem / 3600;
        let m = (rem % 3600) / 60;
        let s = rem % 60;
        // Civil date from days since 1970-01-01 (Howard Hinnant algorithm)
        let z = days + 719_468;
        let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
        let doe = (z - era * 146_097) as u64;
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
        let mut y = (yoe as i64) + era * 400;
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        let mp = (5 * doy + 2) / 153;
        let d = doy - (153 * mp + 2) / 5 + 1;
        let mo = if mp < 10 { mp + 3 } else { mp - 9 };
        if mo <= 2 {
            y += 1;
        }
        (
            format!("{:04}-{:02}-{:02}_{:02}-{:02}-{:02}", y, mo, d, h, m, s),
            ms,
        )
    }
}

pub fn save_verify_full_log(
    root: &Path,
    migration_changes: &[String],
    exit_code: Option<i32>,
    stdout: &str,
    stderr: &str,
) -> Result<PathBuf, String> {
    let backups_dir = root.join("Backups");
    std::fs::create_dir_all(&backups_dir)
        .map_err(|e| format_fs_write_error(&backups_dir, &e))?;

    let (stamp, ms) = format_verify_log_timestamp();
    let mut log_path = backups_dir.join(format!("verify-{}.log", stamp));
    if log_path.exists() {
        log_path = backups_dir.join(format!("verify-{}-{:03}.log", stamp, ms));
    }

    let mut content = String::new();
    content.push_str(&format!(
        "# Ultra Gaming Mode v{} — Полный журнал проверки конфигов\n# Дата: {}\n# Каталог: {}\n# Код возврата: {:?}\n\n",
        APP_VERSION,
        stamp,
        root.display(),
        exit_code
    ));
    if !migration_changes.is_empty() {
        content.push_str("[Применённые автоисправления конфигов]\n");
        for ch in migration_changes {
            content.push_str("  - ");
            content.push_str(ch);
            content.push('\n');
        }
        content.push('\n');
    }
    if !stdout.is_empty() {
        content.push_str(stdout);
        if !stdout.ends_with('\n') {
            content.push('\n');
        }
    }
    if !stderr.is_empty() {
        content.push_str("\n[STDERR]\n");
        content.push_str(stderr);
        if !stderr.ends_with('\n') {
            content.push('\n');
        }
    }

    std::fs::write(&log_path, content.as_bytes())
        .map_err(|e| format_fs_write_error(&log_path, &e))?;
    Ok(log_path)
}

pub fn build_verify_action_result(
    verdict: VerifyVerdict,
    migration_changes: &[String],
    saved_log: Result<PathBuf, String>,
    root: &Path,
) -> ActionResult {
    let mut log_entries: Vec<(String, String)> = Vec::new();
    for ch in migration_changes {
        log_entries.push((
            "info".to_string(),
            format!("Автоисправление конфига: {}", ch),
        ));
    }

    let log_rel = match saved_log {
        Ok(ref p) => {
            let rel = p.strip_prefix(root).unwrap_or(p);
            Some(rel.to_string_lossy().replace('/', "\\"))
        }
        Err(err) => {
            log_entries.push((
                "warn".to_string(),
                format!("Не удалось сохранить полный лог проверки: {}", err),
            ));
            None
        }
    };

    match verdict {
        VerifyVerdict::Passed { summary } => {
            let log_suffix = log_rel
                .as_deref()
                .map(|r| format!(" (полный лог: {})", r))
                .unwrap_or_default();
            let mig_suffix = if migration_changes.is_empty() {
                String::new()
            } else {
                format!(" Исправлено конфигов: {}.", migration_changes.len())
            };
            let banner = format!(
                "Проверка конфигов и движка пройдена: {}.{}{}",
                summary, mig_suffix, log_suffix
            );
            log_entries.push((
                "success".to_string(),
                format!("Проверка конфигов пройдена: {}{}", summary, log_suffix),
            ));
            ActionResult {
                success: true,
                message: banner,
                log_entries,
            }
        }
        VerifyVerdict::Unknown { reason } => {
            let log_suffix = log_rel
                .as_deref()
                .map(|r| format!(" Полный лог: {}", r))
                .unwrap_or_default();
            let banner = format!("{}{}", reason, log_suffix);
            log_entries.push(("warn".to_string(), banner.clone()));
            ActionResult {
                success: false,
                message: banner,
                log_entries,
            }
        }
        VerifyVerdict::Failed {
            summary,
            fail_lines,
            extra_error,
        } => {
            let sum_str = summary
                .clone()
                .unwrap_or_else(|| format!("обнаружено ошибок: {}", fail_lines.len().max(1)));
            let log_suffix = log_rel
                .as_deref()
                .map(|r| format!(" (полный лог: {})", r))
                .unwrap_or_default();

            log_entries.push((
                "error".to_string(),
                format!("Проверка конфигов не пройдена: {}{}", sum_str, log_suffix),
            ));
            for fl in fail_lines.iter().take(25) {
                log_entries.push(("error".to_string(), fl.clone()));
            }
            if fail_lines.len() > 25 {
                log_entries.push((
                    "warn".to_string(),
                    format!("…и ещё {} ошибок (см. полный лог).", fail_lines.len() - 25),
                ));
            }
            if fail_lines.is_empty() {
                if let Some(ref extra) = extra_error {
                    log_entries.push(("error".to_string(), extra.clone()));
                }
            }

            let mut banner_lines: Vec<String> = Vec::new();
            banner_lines.push(format!(
                "Обнаружены проблемы при проверке конфигов ({}):",
                sum_str
            ));
            for fl in fail_lines.iter().take(8) {
                banner_lines.push(fl.clone());
            }
            if fail_lines.len() > 8 {
                banner_lines.push(format!("…и ещё {} ошибок.", fail_lines.len() - 8));
            }
            if fail_lines.is_empty() {
                if let Some(extra) = extra_error {
                    banner_lines.push(extra);
                }
            }
            if let Some(r) = log_rel {
                banner_lines.push(format!("Полный лог сохранён: {}", r));
            }

            ActionResult {
                success: false,
                message: banner_lines.join("\n"),
                log_entries,
            }
        }
    }
}

pub fn run_verify_engine_sync(root: &Path) -> Result<ActionResult, String> {
    if !is_dev_repo_root(root) {
        for asset in EMBEDDED_RUNTIME_ASSETS {
            if asset.preserve_if_exists {
                continue;
            }
            let mut dest = root.to_path_buf();
            for seg in asset.rel_path.split('/') {
                dest.push(seg);
            }
            let needs_update = match std::fs::read(&dest) {
                Ok(existing) => existing.as_slice() != asset.bytes,
                Err(_) => true,
            };
            if needs_update {
                if let Some(parent) = dest.parent() {
                    std::fs::create_dir_all(parent)
                        .map_err(|e| format_fs_write_error(parent, &e))?;
                }
                std::fs::write(&dest, asset.bytes)
                    .map_err(|e| format_fs_write_error(&dest, &e))?;
            }
        }
    }

    let migration_changes = migrate_user_configs_in_place(root).map_err(|e| {
        format!(
            "Не удалось автоматически обновить конфиги перед проверкой: {}",
            e
        )
    })?;

    let script_to_run = root.join("Tests").join("Verify-UniversalEngine.ps1");
    if !script_to_run.exists() {
        return Err(format!(
            "Скрипт проверки не найден по пути: {}",
            script_to_run.display()
        ));
    }
    let script_str = script_to_run
        .to_str()
        .ok_or_else(|| "Путь к скрипту проверки содержит недопустимые символы".to_string())?;

    let mut cmd = Command::new(resolve_powershell_exe());
    cmd.current_dir(root).args([
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        script_str,
        "-UserInstall",
    ]);
    #[cfg(target_os = "windows")]
    cmd.creation_flags(CREATE_NO_WINDOW);

    let output = cmd
        .output()
        .map_err(|e| format!("Не удалось запустить PowerShell для проверки конфигов: {}", e))?;

    let stdout = decode_powershell_output(&output.stdout).trim().to_string();
    let stderr = decode_powershell_output(&output.stderr).trim().to_string();
    let exit_success = output.status.success();
    let exit_code = output.status.code();

    let saved_log = save_verify_full_log(root, &migration_changes, exit_code, &stdout, &stderr);
    let verdict = evaluate_verify_output(exit_success, exit_code, &stdout, &stderr);
    invalidate_active_state_cache();

    Ok(build_verify_action_result(
        verdict,
        &migration_changes,
        saved_log,
        root,
    ))
}

pub fn execute_emergency_repair_sync(kind: &str) -> Result<ActionResult, String> {
    match kind {
        "memory" => return clean_memory_native_sync(),
        "shaders" => {
            let local = std::env::var_os("LOCALAPPDATA").map(PathBuf::from);
            let roaming = std::env::var_os("APPDATA").map(PathBuf::from);
            let (files, mb) = flush_shader_cache_native_impl(local.as_deref(), roaming.as_deref());
            return Ok(ActionResult {
                success: true,
                message: format!(
                    "Кэш шейдеров GPU очищен: удалено {} файлов ({:.1} МБ).",
                    files, mb
                ),
                log_entries: Vec::new(),
            });
        }
        "verify" => {
            let root = get_workspace_root();
            return run_verify_engine_sync(&root);
        }
        _ => {}
    }

    let root = get_workspace_root();
    let script_path = root.join("UltraGamingMode.ps1");

    let (args, script_to_run): (Vec<&'static str>, PathBuf) = match kind {
        "display" => (vec!["-Action", "RepairDisplay", "-SkipUpdateCheck"], script_path),
        "services" => (vec!["-Action", "RepairServices", "-SkipUpdateCheck"], script_path),
        "debloat" => (vec!["-Action", "Debloat", "-SkipUpdateCheck"], script_path),
        "restore_debloat" => (
            vec!["-Action", "RestoreDebloat", "-SkipUpdateCheck"],
            script_path,
        ),
        _ => return Err("Неизвестный тип операции".into()),
    };

    let res = run_powershell_script(
        &root,
        &script_to_run,
        &args,
        format!("Операция [{}] выполнена успешно.", kind),
        "Не удалось выполнить команду",
    );
    invalidate_active_state_cache();
    res
}

pub fn reboot_pc_sync() -> Result<ActionResult, String> {
    let shutdown_exe = resolve_system32_binary("shutdown.exe")
        .unwrap_or_else(|| PathBuf::from(r"C:\Windows\System32\shutdown.exe"));
    let mut cmd = Command::new(&shutdown_exe);
    cmd.args([
        "/r",
        "/t",
        "2",
        "/c",
        "UltraGamingMode: reboot to apply gaming optimizations",
    ]);
    #[cfg(target_os = "windows")]
    cmd.creation_flags(CREATE_NO_WINDOW);
    let output = cmd
        .output()
        .map_err(|e| format!("Не удалось запустить shutdown.exe: {}", e))?;
    if !output.status.success() {
        let stderr = decode_powershell_output(&output.stderr).trim().to_string();
        return Err(if stderr.is_empty() {
            format!("shutdown.exe завершился с кодом {:?}", output.status.code())
        } else {
            stderr
        });
    }
    Ok(ActionResult {
        success: true,
        message: "Команда перезагрузки ПК отправлена. Перезагрузка через 2 секунды.".to_string(),
        log_entries: Vec::new(),
    })
}
