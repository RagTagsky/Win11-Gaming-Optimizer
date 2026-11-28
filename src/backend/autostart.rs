use super::*;
#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;

pub const AUTOSTART_TASK_NAME: &str = "UltraGamingMode_AutoStart";

pub fn escape_xml_text(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 8);
    for ch in s.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&apos;"),
            _ => out.push(ch),
        }
    }
    out
}

pub fn unescape_xml_text(s: &str) -> String {
    s.replace("&quot;", "\"")
        .replace("&apos;", "'")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&")
}

pub fn build_autostart_task_xml(user_sid: &str, exe_path: &str, start_in_tray: bool) -> String {
    let clean_exe = exe_path.trim().trim_matches('"');
    let clean_exe = clean_exe.strip_prefix(r"\\?\").unwrap_or(clean_exe);
    let work_dir = Path::new(clean_exe)
        .parent()
        .and_then(|p| p.to_str())
        .unwrap_or("");
    let sid_esc = escape_xml_text(user_sid.trim());
    let exe_esc = escape_xml_text(clean_exe);
    let dir_esc = escape_xml_text(work_dir);
    let args_xml = if start_in_tray {
        "\r\n      <Arguments>--tray</Arguments>"
    } else {
        ""
    };
    let dir_xml = if dir_esc.is_empty() {
        String::new()
    } else {
        format!("\r\n      <WorkingDirectory>{}</WorkingDirectory>", dir_esc)
    };

    format!(
        concat!(
            "<?xml version=\"1.0\" encoding=\"UTF-16\"?>\r\n",
            "<Task version=\"1.2\" xmlns=\"http://schemas.microsoft.com/windows/2004/02/mit/task\">\r\n",
            "  <RegistrationInfo>\r\n",
            "    <Author>UltraGamingMode</Author>\r\n",
            "    <Description>Elevated Windows logon autostart for Ultra Gaming Mode</Description>\r\n",
            "  </RegistrationInfo>\r\n",
            "  <Triggers>\r\n",
            "    <LogonTrigger>\r\n",
            "      <Enabled>true</Enabled>\r\n",
            "      <Delay>PT3S</Delay>\r\n",
            "      <UserId>{sid}</UserId>\r\n",
            "    </LogonTrigger>\r\n",
            "  </Triggers>\r\n",
            "  <Principals>\r\n",
            "    <Principal id=\"Author\">\r\n",
            "      <UserId>{sid}</UserId>\r\n",
            "      <LogonType>InteractiveToken</LogonType>\r\n",
            "      <RunLevel>HighestAvailable</RunLevel>\r\n",
            "    </Principal>\r\n",
            "  </Principals>\r\n",
            "  <Settings>\r\n",
            "    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>\r\n",
            "    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>\r\n",
            "    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>\r\n",
            "    <AllowHardTerminate>false</AllowHardTerminate>\r\n",
            "    <StartWhenAvailable>true</StartWhenAvailable>\r\n",
            "    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>\r\n",
            "    <IdleSettings>\r\n",
            "      <StopOnIdleEnd>false</StopOnIdleEnd>\r\n",
            "      <RestartOnIdle>false</RestartOnIdle>\r\n",
            "    </IdleSettings>\r\n",
            "    <AllowStartOnDemand>true</AllowStartOnDemand>\r\n",
            "    <Enabled>true</Enabled>\r\n",
            "    <Hidden>false</Hidden>\r\n",
            "    <RunOnlyIfIdle>false</RunOnlyIfIdle>\r\n",
            "    <WakeToRun>false</WakeToRun>\r\n",
            "    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>\r\n",
            "    <Priority>5</Priority>\r\n",
            "  </Settings>\r\n",
            "  <Actions Context=\"Author\">\r\n",
            "    <Exec>\r\n",
            "      <Command>{exe}</Command>{args}{dir}\r\n",
            "    </Exec>\r\n",
            "  </Actions>\r\n",
            "</Task>\r\n"
        ),
        sid = sid_esc,
        exe = exe_esc,
        args = args_xml,
        dir = dir_xml
    )
}

pub fn encode_utf16le_with_bom(text: &str) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(2 + text.len() * 2);
    bytes.push(0xFF);
    bytes.push(0xFE);
    for unit in text.encode_utf16() {
        bytes.extend_from_slice(&unit.to_le_bytes());
    }
    bytes
}

pub(crate) fn extract_xml_tag(xml: &str, tag: &str) -> Option<String> {
    let open = format!("<{}", tag);
    let close = format!("</{}>", tag);
    let low_xml = xml.to_ascii_lowercase();
    let open_low = open.to_ascii_lowercase();
    let close_low = close.to_ascii_lowercase();
    let mut search_from = 0usize;
    while let Some(rel_start) = low_xml[search_from..].find(&open_low) {
        let tag_start = search_from + rel_start;
        let after_name = tag_start + open_low.len();
        if after_name >= xml.len() {
            break;
        }
        let next_ch = xml.as_bytes()[after_name];
        if next_ch != b'>' && !next_ch.is_ascii_whitespace() {
            search_from = after_name;
            continue;
        }
        let Some(rel_gt) = xml[after_name..].find('>') else {
            break;
        };
        let content_start = after_name + rel_gt + 1;
        let Some(rel_end) = low_xml[content_start..].find(&close_low) else {
            break;
        };
        let raw_inner = xml[content_start..content_start + rel_end].trim();
        return Some(unescape_xml_text(raw_inner));
    }
    None
}

pub fn parse_autostart_task_xml(xml: &str) -> (bool, Option<String>, Option<String>, bool) {
    let low = xml.to_ascii_lowercase();
    let enabled = !low.is_empty() && !low.contains("<enabled>false</enabled>");
    let command = extract_xml_tag(xml, "Command").map(|c| {
        let t = c.trim().trim_matches('"');
        t.strip_prefix(r"\\?\").unwrap_or(t).to_string()
    });
    let arguments = extract_xml_tag(xml, "Arguments").filter(|s| !s.trim().is_empty());
    let is_highest_available = extract_xml_tag(xml, "RunLevel")
        .map(|r| r.trim().eq_ignore_ascii_case("HighestAvailable"))
        .unwrap_or(false);
    (enabled, command, arguments, is_highest_available)
}

pub(crate) fn check_not_reparse_or_symlink(path: &Path) -> Result<(), String> {
    let meta = std::fs::symlink_metadata(path)
        .map_err(|e| format!("Не удалось проверить путь '{}': {}", path.display(), e))?;
    if meta.file_type().is_symlink() {
        return Err(format!(
            "Обнаружена символическая ссылка по пути '{}'.",
            path.display()
        ));
    }
    #[cfg(target_os = "windows")]
    {
        use std::os::windows::fs::MetadataExt;
        if (meta.file_attributes() & 0x0400) != 0 {
            return Err(format!(
                "Обнаружена точка повторного анализа (reparse point) по пути '{}'.",
                path.display()
            ));
        }
    }
    Ok(())
}

pub(crate) fn prepare_secure_tasks_dir() -> Result<PathBuf, String> {
    #[cfg(target_os = "windows")]
    let base = std::env::var_os("ProgramData")
        .or_else(|| std::env::var_os("ALLUSERSPROFILE"))
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(r"C:\ProgramData"))
        .join("UltraGamingMode")
        .join("Tasks");
    #[cfg(not(target_os = "windows"))]
    let base = std::env::temp_dir().join("UltraGamingModeTasks");

    if let Some(parent) = base.parent() {
        if parent.exists() {
            check_not_reparse_or_symlink(parent)?;
        }
    }
    if base.exists() {
        check_not_reparse_or_symlink(&base)?;
    }

    std::fs::create_dir_all(&base)
        .map_err(|e| format!("Не удалось создать папку задач '{}': {}", base.display(), e))?;
    check_not_reparse_or_symlink(&base)?;

    #[cfg(target_os = "windows")]
    {
        let icacls = resolve_system32_binary("icacls.exe")
            .ok_or_else(|| "Не найден системный утилита icacls.exe в System32.".to_string())?;
        let base_str = base
            .to_str()
            .ok_or_else(|| "Недопустимый путь папки задач.".to_string())?;
        let mut cmd = Command::new(&icacls);
        cmd.args([
            base_str,
            "/inheritance:r",
            "/grant:r",
            "*S-1-5-32-544:(OI)(CI)F",
            "*S-1-5-18:(OI)(CI)F",
            "/Q",
        ]);
        cmd.creation_flags(CREATE_NO_WINDOW);
        let out = cmd
            .output()
            .map_err(|e| format!("Не удалось ограничить ACL папки задач: {}", e))?;
        if !out.status.success() {
            return Err(format!(
                "Не удалось закрепить права Администратора на '{}': код {:?}",
                base.display(),
                out.status.code()
            ));
        }
    }

    Ok(base)
}

pub(crate) fn normalized_current_exe_path() -> String {
    std::env::current_exe()
        .ok()
        .and_then(|p| p.to_str().map(|s| s.to_string()))
        .map(|s| {
            let trimmed = s.trim().trim_matches('"');
            trimmed.strip_prefix(r"\\?\").unwrap_or(trimmed).to_string()
        })
        .unwrap_or_default()
}

pub fn get_autostart_status_sync() -> Result<AutostartStatus, String> {
    let current_exe_path = normalized_current_exe_path();
    #[cfg(target_os = "windows")]
    let is_admin_session = win_hw::is_current_process_elevated();
    #[cfg(not(target_os = "windows"))]
    let is_admin_session = true;

    #[cfg(not(target_os = "windows"))]
    {
        return Ok(AutostartStatus {
            enabled: false,
            start_in_tray: true,
            task_exists: false,
            path_matches: false,
            is_elevated_task: false,
            current_exe_path,
            registered_command: None,
            is_admin_session,
            warning: None,
        });
    }

    #[cfg(target_os = "windows")]
    {
        let schtasks = resolve_system32_binary("schtasks.exe")
            .unwrap_or_else(|| PathBuf::from(r"C:\Windows\System32\schtasks.exe"));
        let mut cmd = Command::new(&schtasks);
        cmd.args(["/Query", "/TN", AUTOSTART_TASK_NAME, "/XML"]);
        cmd.creation_flags(CREATE_NO_WINDOW);
        let out = cmd
            .output()
            .map_err(|e| format!("Не удалось запустить schtasks.exe: {}", e))?;

        if !out.status.success() {
            let warning = if !is_admin_session {
                Some("Приложение запущено без прав администратора: для включения или изменения автозапуска запустите от имени администратора.".to_string())
            } else {
                None
            };
            return Ok(AutostartStatus {
                enabled: false,
                start_in_tray: true,
                task_exists: false,
                path_matches: false,
                is_elevated_task: false,
                current_exe_path,
                registered_command: None,
                is_admin_session,
                warning,
            });
        }

        let xml = decode_powershell_output(&out.stdout);
        let (task_enabled, registered_command, arguments, is_elevated_task) =
            parse_autostart_task_xml(&xml);
        let start_in_tray = arguments
            .as_deref()
            .map(|a| {
                let low = a.to_ascii_lowercase();
                low.contains("--tray") || low.contains("--minimized")
            })
            .unwrap_or(false);
        let path_matches = match (&registered_command, current_exe_path.is_empty()) {
            (Some(reg), false) => reg.trim().eq_ignore_ascii_case(current_exe_path.trim()),
            _ => false,
        };

        let warning = if !is_admin_session {
            Some("Приложение запущено без прав администратора: изменение или перерегистрация задачи автозапуска требует запуска от администратора.".to_string())
        } else if !path_matches {
            Some("Путь в задаче автозапуска отличается от текущего расположения UltraGamingMode.exe. Нажмите «Исправить путь», чтобы обновить задачу.".to_string())
        } else {
            None
        };

        Ok(AutostartStatus {
            enabled: task_enabled,
            start_in_tray,
            task_exists: true,
            path_matches,
            is_elevated_task,
            current_exe_path,
            registered_command,
            is_admin_session,
            warning,
        })
    }
}

pub fn set_autostart_sync(enabled: bool, start_in_tray: bool) -> Result<AutostartStatus, String> {
    #[cfg(not(target_os = "windows"))]
    {
        let _ = (enabled, start_in_tray);
        return get_autostart_status_sync();
    }

    #[cfg(target_os = "windows")]
    {
        let schtasks = resolve_system32_binary("schtasks.exe")
            .unwrap_or_else(|| PathBuf::from(r"C:\Windows\System32\schtasks.exe"));

        if !enabled {
            let mut cmd = Command::new(&schtasks);
            cmd.args(["/Delete", "/TN", AUTOSTART_TASK_NAME, "/F"]);
            cmd.creation_flags(CREATE_NO_WINDOW);
            let out = cmd
                .output()
                .map_err(|e| format!("Не удалось запустить schtasks.exe: {}", e))?;
            if !out.status.success() {
                let current = get_autostart_status_sync()?;
                if current.task_exists {
                    let stderr = decode_powershell_output(&out.stderr).trim().to_string();
                    return Err(if stderr.is_empty() {
                        "Не удалось удалить задачу автозапуска (требуются права администратора)."
                            .to_string()
                    } else {
                        stderr
                    });
                }
            }
            return get_autostart_status_sync();
        }

        if !win_hw::is_current_process_elevated() {
            return Err("Для создания повышенного автозапуска Windows требуются права администратора. Перезапустите UltraGamingMode от имени администратора.".to_string());
        }

        let user_sid = win_hw::get_current_user_sid_string()?;
        let exe_path = normalized_current_exe_path();
        if exe_path.is_empty() {
            return Err("Не удалось определить путь к текущему файлу UltraGamingMode.exe.".to_string());
        }

        let xml_text = build_autostart_task_xml(&user_sid, &exe_path, start_in_tray);
        let xml_bytes = encode_utf16le_with_bom(&xml_text);
        let tasks_dir = prepare_secure_tasks_dir()?;
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let xml_path = tasks_dir.join(format!("autostart_{}_{}.xml", std::process::id(), nanos));

        std::fs::write(&xml_path, &xml_bytes)
            .map_err(|e| format!("Не удалось записать XML задачи автозапуска: {}", e))?;
        let symlink_check = check_not_reparse_or_symlink(&xml_path);
        if let Err(err) = symlink_check {
            let _ = std::fs::remove_file(&xml_path);
            return Err(err);
        }

        let xml_str = xml_path
            .to_str()
            .ok_or_else(|| "Недопустимый путь XML задачи автозапуска".to_string())?;
        let mut cmd = Command::new(&schtasks);
        cmd.args(["/Create", "/TN", AUTOSTART_TASK_NAME, "/XML", xml_str, "/F"]);
        cmd.creation_flags(CREATE_NO_WINDOW);
        let out = cmd.output();
        let _ = std::fs::remove_file(&xml_path);

        let out = out.map_err(|e| format!("Не удалось запустить schtasks.exe: {}", e))?;
        if !out.status.success() {
            let stderr = decode_powershell_output(&out.stderr).trim().to_string();
            let stdout = decode_powershell_output(&out.stdout).trim().to_string();
            return Err(format!(
                "schtasks.exe /Create завершился с ошибкой: {}",
                if !stderr.is_empty() { stderr } else { stdout }
            ));
        }

        get_autostart_status_sync()
    }
}
