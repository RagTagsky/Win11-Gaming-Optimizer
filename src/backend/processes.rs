use super::*;
use std::path::Path;

pub fn read_process_lists_from_root(root: &Path) -> Result<ProcessConfigLists, String> {
    let path = root.join("Config").join("startup_apps.json");
    let raw = std::fs::read_to_string(&path)
        .map_err(|e| format!("Не удалось прочитать {}: {}", path.display(), e))?;
    let val: serde_json::Value = serde_json::from_str(raw.trim_start_matches('\u{feff}'))
        .map_err(|e| format!("Ошибка разбора {}: {}", path.display(), e))?;

    let blacklist_processes = val
        .get("BlacklistProcesses")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str().map(|s| s.to_string()))
                .collect()
        })
        .unwrap_or_default();

    let protected_startup_names = val
        .get("ProtectedStartupNames")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str().map(|s| s.to_string()))
                .collect()
        })
        .unwrap_or_default();

    Ok(ProcessConfigLists {
        blacklist_processes,
        protected_startup_names,
    })
}

pub fn update_process_list_in_root(
    root: &Path,
    list_type: &str,
    process_name: &str,
    operation: &str,
) -> Result<ProcessConfigLists, String> {
    let clean_name = strip_exe_suffix(process_name).trim().to_string();
    if !is_safe_identifier(&clean_name) {
        return Err(format!("Недопустимое имя процесса: '{}'", process_name));
    }

    let field = match list_type {
        "blacklist" => "BlacklistProcesses",
        "protected" => "ProtectedStartupNames",
        _ => return Err("Недопустимый тип списка процессов".into()),
    };
    if operation != "add" && operation != "remove" {
        return Err("Недопустимая операция со списком процессов".into());
    }

    let path = root.join("Config").join("startup_apps.json");
    let raw = std::fs::read_to_string(&path)
        .map_err(|e| format!("Не удалось прочитать {}: {}", path.display(), e))?;
    let mut doc: serde_json::Value = serde_json::from_str(raw.trim_start_matches('\u{feff}'))
        .map_err(|e| format!("Ошибка разбора {}: {}", path.display(), e))?;

    if operation == "add" && list_type == "blacklist" {
        if is_protected_process_name(&clean_name) {
            return Err(format!(
                "Процесс '{}' защищён ядром Windows/приложением и не может быть добавлен в чёрный список.",
                clean_name
            ));
        }
        let is_in_protected = doc
            .get("ProtectedStartupNames")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|x| x.as_str())
                    .any(|s| strip_exe_suffix(s).trim().eq_ignore_ascii_case(&clean_name))
            })
            .unwrap_or(false);
        if is_in_protected {
            return Err(format!(
                "Процесс '{}' находится в исключениях автозагрузки (ProtectedStartupNames).",
                clean_name
            ));
        }
    }

    let obj = doc
        .as_object_mut()
        .ok_or_else(|| "Некорректная структура startup_apps.json".to_string())?;
    let entry = obj
        .entry(field)
        .or_insert_with(|| serde_json::Value::Array(Vec::new()));
    let arr = entry
        .as_array_mut()
        .ok_or_else(|| format!("Поле {} должно быть массивом", field))?;

    if operation == "add" {
        if arr
            .iter()
            .filter_map(|v| v.as_str())
            .any(|s| strip_exe_suffix(s).trim().eq_ignore_ascii_case(&clean_name))
        {
            return Err(format!("Элемент '{}' уже присутствует в списке.", clean_name));
        }
        arr.push(serde_json::Value::String(clean_name.clone()));

        if list_type == "protected" {
            if let Some(bl_arr) = obj
                .get_mut("BlacklistProcesses")
                .and_then(|v| v.as_array_mut())
            {
                bl_arr.retain(|v| {
                    v.as_str()
                        .map(|s| !strip_exe_suffix(s).trim().eq_ignore_ascii_case(&clean_name))
                        .unwrap_or(true)
                });
            }
        }
    } else {
        let before = arr.len();
        arr.retain(|v| {
            v.as_str()
                .map(|s| !strip_exe_suffix(s).trim().eq_ignore_ascii_case(&clean_name))
                .unwrap_or(true)
        });
        if arr.len() == before {
            return Err(format!("Элемент '{}' не найден в списке.", clean_name));
        }
    }

    write_json_no_bom(&path, &doc)?;
    read_process_lists_from_root(root)
}

pub fn set_process_gaming_mode_in_root(
    root: &Path,
    process_name: &str,
    disable_in_gaming: bool,
) -> Result<ProcessConfigLists, String> {
    let clean_name = strip_exe_suffix(process_name).trim().to_string();
    if !is_safe_identifier(&clean_name) {
        return Err(format!("Недопустимое имя процесса: '{}'", process_name));
    }
    if disable_in_gaming && is_protected_process_name(&clean_name) {
        return Err(format!(
            "Процесс '{}' защищён системой, античитом или приложением и не может отключаться в Gaming Mode.",
            clean_name
        ));
    }

    let path = root.join("Config").join("startup_apps.json");
    let raw = std::fs::read_to_string(&path)
        .map_err(|e| format!("Не удалось прочитать {}: {}", path.display(), e))?;
    let mut doc: serde_json::Value = serde_json::from_str(raw.trim_start_matches('\u{feff}'))
        .map_err(|e| format!("Ошибка разбора {}: {}", path.display(), e))?;

    let obj = doc
        .as_object_mut()
        .ok_or_else(|| "Некорректная структура startup_apps.json".to_string())?;

    if !obj.contains_key("BlacklistProcesses") {
        obj.insert(
            "BlacklistProcesses".to_string(),
            serde_json::Value::Array(Vec::new()),
        );
    }
    if !obj.contains_key("ProtectedStartupNames") {
        obj.insert(
            "ProtectedStartupNames".to_string(),
            serde_json::Value::Array(Vec::new()),
        );
    }

    if disable_in_gaming {
        if let Some(prot_arr) = obj
            .get_mut("ProtectedStartupNames")
            .and_then(|v| v.as_array_mut())
        {
            prot_arr.retain(|v| {
                v.as_str()
                    .map(|s| !strip_exe_suffix(s).eq_ignore_ascii_case(&clean_name))
                    .unwrap_or(true)
            });
        }
        let bl_arr = obj
            .get_mut("BlacklistProcesses")
            .and_then(|v| v.as_array_mut())
            .ok_or_else(|| "Поле BlacklistProcesses должно быть массивом".to_string())?;
        let exists = bl_arr
            .iter()
            .filter_map(|v| v.as_str())
            .any(|s| strip_exe_suffix(s).eq_ignore_ascii_case(&clean_name));
        if !exists {
            bl_arr.push(serde_json::Value::String(clean_name));
        }
    } else {
        if let Some(bl_arr) = obj
            .get_mut("BlacklistProcesses")
            .and_then(|v| v.as_array_mut())
        {
            bl_arr.retain(|v| {
                v.as_str()
                    .map(|s| !strip_exe_suffix(s).eq_ignore_ascii_case(&clean_name))
                    .unwrap_or(true)
            });
        }
        let prot_arr = obj
            .get_mut("ProtectedStartupNames")
            .and_then(|v| v.as_array_mut())
            .ok_or_else(|| "Поле ProtectedStartupNames должно быть массивом".to_string())?;
        let exists = prot_arr
            .iter()
            .filter_map(|v| v.as_str())
            .any(|s| strip_exe_suffix(s).eq_ignore_ascii_case(&clean_name));
        if !exists {
            prot_arr.push(serde_json::Value::String(clean_name));
        }
    }

    write_json_no_bom(&path, &doc)?;
    read_process_lists_from_root(root)
}

pub fn set_service_gaming_mode_in_root(
    root: &Path,
    service_name: &str,
    disable_in_gaming: bool,
    include_live_status: bool,
) -> Result<ServicesLists, String> {
    let clean_name = service_name.trim();
    if !is_safe_identifier(clean_name) {
        return Err(format!("Недопустимое имя службы: '{}'", service_name));
    }
    let canon_name = canonical_service_name(clean_name).to_string();
    if disable_in_gaming && is_immutable_core_service(clean_name) {
        return Err(format!(
            "Критическая служба ОС '{}' защищена ядром и не может отключаться в Gaming Mode.",
            clean_name
        ));
    }

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
    let bl_arr = doc_bl
        .get_mut("TargetServices")
        .and_then(|v| v.as_array_mut())
        .ok_or_else(|| "Отсутствует массив TargetServices".to_string())?;

    if disable_in_gaming {
        wl_arr.retain(|v| {
            let Some(name) = v.as_str() else { return true };
            if is_immutable_core_service(name) {
                return true;
            }
            !service_names_match(name, &canon_name)
        });
        let exists = bl_arr.iter().any(|item| {
            item.get("Name")
                .and_then(|v| v.as_str())
                .map(|n| service_names_match(n, &canon_name))
                .unwrap_or(false)
        });
        if !exists {
            let reason = lookup_service_description(&desc_map, &canon_name)
                .map(|d| d.summary_ru.clone())
                .filter(|s| !s.trim().is_empty())
                .unwrap_or_else(|| "Настроено пользователем".to_string());
            let cat = infer_service_category(&canon_name, &reason);
            let mut map = serde_json::Map::new();
            map.insert("Name".into(), serde_json::Value::String(canon_name.clone()));
            map.insert("Category".into(), serde_json::Value::String(cat));
            map.insert("Reason".into(), serde_json::Value::String(reason));
            bl_arr.push(serde_json::Value::Object(map));
        }
    } else {
        bl_arr.retain(|item| {
            item.get("Name")
                .and_then(|v| v.as_str())
                .map(|n| !service_names_match(n, &canon_name))
                .unwrap_or(true)
        });
        let exists = wl_arr
            .iter()
            .filter_map(|v| v.as_str())
            .any(|s| service_names_match(s, &canon_name));
        if !exists {
            wl_arr.push(serde_json::Value::String(canon_name));
        }
    }

    write_json_no_bom(&wl_path, &doc_wl)?;
    write_json_no_bom(&bl_path, &doc_bl)?;
    read_services_lists_from_root(root, include_live_status)
}

pub fn update_service_list_in_root(
    root: &Path,
    list_type: &str,
    service_name: &str,
    display_name: Option<&str>,
    category: Option<&str>,
    reason: Option<&str>,
    operation: &str,
    include_live_status: bool,
) -> Result<ServicesLists, String> {
    let raw_trimmed = service_name.trim();
    if !is_safe_identifier(raw_trimmed) {
        return Err(format!("Недопустимое имя службы: '{}'", service_name));
    }
    let clean_name = canonical_service_name(raw_trimmed).to_string();
    if operation != "add" && operation != "remove" {
        return Err("Недопустимая операция со списком служб".into());
    }

    let bl_path = root.join("Config").join("services_blacklist.json");
    let wl_path = root.join("Config").join("services_whitelist.json");

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

    match list_type {
        "blacklist" => {
            if operation == "add" {
                if is_immutable_core_service(&clean_name) {
                    return Err(format!(
                        "Критическая служба ОС '{}' не может быть добавлена в чёрный список.",
                        clean_name
                    ));
                }
                let in_whitelist = doc_wl
                    .get("ProtectedServices")
                    .and_then(|v| v.as_array())
                    .map(|arr| {
                        arr.iter()
                            .filter_map(|v| v.as_str())
                            .any(|s| service_names_match(s, &clean_name))
                    })
                    .unwrap_or(false);
                if in_whitelist {
                    return Err(format!(
                        "Служба '{}' защищена белым списком (ProtectedServices).",
                        clean_name
                    ));
                }
            }

            let arr = doc_bl
                .get_mut("TargetServices")
                .and_then(|v| v.as_array_mut())
                .ok_or_else(|| "Отсутствует массив TargetServices".to_string())?;

            if operation == "add" {
                let exists = arr.iter().any(|item| {
                    item.get("Name")
                        .and_then(|v| v.as_str())
                        .map(|n| service_names_match(n, &clean_name))
                        .unwrap_or(false)
                });
                if exists {
                    return Err(format!(
                        "Служба '{}' уже находится в списке оптимизируемых.",
                        clean_name
                    ));
                }
                let clean_reason = reason
                    .map(|s| s.trim())
                    .filter(|s| !s.is_empty())
                    .unwrap_or("Добавлено пользователем")
                    .to_string();
                let clean_cat = category
                    .map(|s| s.trim())
                    .filter(|s| {
                        matches!(
                            *s,
                            "Telemetry"
                                | "Updates"
                                | "Xbox"
                                | "Print"
                                | "Devices"
                                | "Network"
                                | "Remote"
                                | "System"
                        )
                    })
                    .map(|s| s.to_string())
                    .unwrap_or_else(|| infer_service_category(&clean_name, &clean_reason));

                let mut map = serde_json::Map::new();
                map.insert("Name".into(), serde_json::Value::String(clean_name));
                if let Some(disp) = display_name.map(|s| s.trim()).filter(|s| !s.is_empty()) {
                    map.insert(
                        "DisplayName".into(),
                        serde_json::Value::String(disp.to_string()),
                    );
                }
                map.insert("Category".into(), serde_json::Value::String(clean_cat));
                map.insert("Reason".into(), serde_json::Value::String(clean_reason));
                arr.push(serde_json::Value::Object(map));
            } else {
                let before = arr.len();
                arr.retain(|item| {
                    item.get("Name")
                        .and_then(|v| v.as_str())
                        .map(|n| !service_names_match(n, &clean_name))
                        .unwrap_or(true)
                });
                if arr.len() == before {
                    return Err(format!("Служба '{}' не найдена в чёрном списке.", clean_name));
                }
            }
            write_json_no_bom(&bl_path, &doc_bl)?;
        }
        "whitelist" => {
            if operation == "remove" && is_immutable_core_service(&clean_name) {
                return Err(format!(
                    "Служба '{}' является критической системной службой ОС и не может быть удалена из белого списка.",
                    clean_name
                ));
            }
            let wl_arr = doc_wl
                .get_mut("ProtectedServices")
                .and_then(|v| v.as_array_mut())
                .ok_or_else(|| "Отсутствует массив ProtectedServices".to_string())?;

            if operation == "add" {
                let exists = wl_arr
                    .iter()
                    .filter_map(|v| v.as_str())
                    .any(|s| service_names_match(s, &clean_name));
                if exists {
                    return Err(format!("Служба '{}' уже находится в белом списке.", clean_name));
                }
                wl_arr.push(serde_json::Value::String(clean_name.clone()));

                if let Some(bl_arr) = doc_bl
                    .get_mut("TargetServices")
                    .and_then(|v| v.as_array_mut())
                {
                    let before_bl = bl_arr.len();
                    bl_arr.retain(|item| {
                        item.get("Name")
                            .and_then(|v| v.as_str())
                            .map(|n| !service_names_match(n, &clean_name))
                            .unwrap_or(true)
                    });
                    if bl_arr.len() != before_bl {
                        write_json_no_bom(&bl_path, &doc_bl)?;
                    }
                }
            } else {
                let before = wl_arr.len();
                wl_arr.retain(|v| {
                    v.as_str()
                        .map(|s| !service_names_match(s, &clean_name))
                        .unwrap_or(true)
                });
                if wl_arr.len() == before {
                    return Err(format!("Служба '{}' не найдена в белом списке.", clean_name));
                }
            }
            write_json_no_bom(&wl_path, &doc_wl)?;
        }
        _ => return Err("Недопустимый тип списка служб".into()),
    }

    read_services_lists_from_root(root, include_live_status)
}

pub fn startup_entry_matches_process(
    entry_name: &str,
    entry_display: &str,
    entry_target: &str,
    process_name: &str,
) -> bool {
    let target_clean = strip_exe_suffix(process_name).trim().to_lowercase();
    if target_clean.is_empty() {
        return false;
    }
    let matches_token = |haystack: &str| -> bool {
        let lower = strip_exe_suffix(haystack.trim()).to_lowercase();
        if lower == target_clean {
            return true;
        }
        let bytes = lower.as_bytes();
        let t_bytes = target_clean.as_bytes();
        let mut search_from = 0usize;
        while let Some(rel) = lower[search_from..].find(&target_clean) {
            let pos = search_from + rel;
            let end = pos + t_bytes.len();
            let before_ok = pos == 0 || !bytes[pos - 1].is_ascii_alphanumeric();
            let after_ok = end == bytes.len() || !bytes[end].is_ascii_alphanumeric();
            if before_ok && after_ok {
                return true;
            }
            search_from = pos + 1;
        }
        false
    };
    if matches_token(entry_name) || matches_token(entry_display) {
        return true;
    }
    let lower_target = entry_target.to_lowercase();
    for quote in ['"', '\''] {
        let mut rest = lower_target.as_str();
        while let Some(open) = rest.find(quote) {
            let after_open = &rest[open + 1..];
            let Some(close) = after_open.find(quote) else {
                break;
            };
            let quoted = after_open[..close].trim();
            if let Some(stem_part) = quoted.strip_suffix(".exe") {
                let stem_start = stem_part
                    .rfind(|c: char| matches!(c, '\\' | '/'))
                    .map(|i| i + 1)
                    .unwrap_or(0);
                if stem_part[stem_start..].trim() == target_clean {
                    return true;
                }
            }
            rest = &after_open[close + 1..];
        }
    }
    let mut start = 0;
    while let Some(pos) = lower_target[start..].find(".exe") {
        let abs_end = start + pos;
        let prefix = &lower_target[..abs_end];
        let stem_start = prefix
            .rfind(|c: char| matches!(c, '\\' | '/' | '"' | '\'' | ' ' | '\t'))
            .map(|i| i + 1)
            .unwrap_or(0);
        if &prefix[stem_start..] == target_clean {
            return true;
        }
        start = abs_end + 4;
    }
    false
}

pub fn build_process_tooltip_meta(
    name: &str,
    protection_kind: Option<&str>,
    curated: Option<&ProcessDescriptionEntry>,
    exe_meta: &ExeMetadata,
) -> (String, String, String, String) {
    let is_protected = protection_kind.is_some();
    let display_name = curated
        .map(|c| c.display_name_ru.trim())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
        .or_else(|| exe_meta.display_name.clone().filter(|s| !s.trim().is_empty()))
        .unwrap_or_else(|| name.to_string());

    let summary_ru = if let Some(c) = curated.filter(|c| !c.summary_ru.trim().is_empty()) {
        c.summary_ru.clone()
    } else if let Some(fd) = exe_meta
        .file_description
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        if let Some(comp) = exe_meta
            .company_name
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty() && !fd.to_lowercase().contains(&s.to_lowercase()))
        {
            format!("{} ({}).", fd, comp)
        } else {
            format!("{}.", fd)
        }
    } else if let Some(pn) = exe_meta
        .product_name
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        if let Some(comp) = exe_meta
            .company_name
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty() && !pn.to_lowercase().contains(&s.to_lowercase()))
        {
            format!("{} ({}).", pn, comp)
        } else {
            format!("{}.", pn)
        }
    } else if is_protected {
        match protection_kind {
            Some("anticheat") => format!("Процесс античита ({}).", name),
            Some("game_client") => format!("Компонент игрового клиента ({}).", name),
            Some("network_bypass") => format!("Компонент обхода DPI Zapret ({}).", name),
            Some("self_app") => "Процесс самого приложения Ultra Gaming Mode.".to_string(),
            _ => format!("Системный процесс ядра Windows ({}).", name),
        }
    } else {
        format!("Фоновый процесс сторонней программы ({}.exe).", name)
    };

    let can_disable_hint = if let Some(c) = curated.filter(|c| !c.can_disable_ru.trim().is_empty()) {
        c.can_disable_ru.clone()
    } else if is_protected {
        match protection_kind {
            Some("anticheat") => {
                "Защищён как античит — принудительное отключение нарушит запуск онлайн-игр."
                    .to_string()
            }
            Some("game_client") => {
                "Защищён как игровой клиент — нужен для стабильного запуска игр.".to_string()
            }
            Some("network_bypass") => {
                "Защищён как обход DPI (Zapret) — остаётся работать в Gaming Mode.".to_string()
            }
            Some("self_app") => "Текущее приложение защищено от самоотключения.".to_string(),
            _ => "Системный компонент Windows — отключать нельзя.".to_string(),
        }
    } else {
        "Сторонняя программа. Выключайте в Gaming Mode, если она не нужна во время игры (её автозагрузка также будет временно приостановлена)."
            .to_string()
    };

    let safety_level = normalize_safety_level(
        curated.map(|c| c.safety_level.as_str()).unwrap_or("optional"),
        is_protected,
    );

    (display_name, summary_ru, can_disable_hint, safety_level)
}

pub fn get_running_processes_sync() -> Result<LiveProcessesSnapshot, String> {
    let root = get_workspace_root();
    let cfg = read_process_lists_from_root(&root)?;
    let proc_desc_map = load_process_descriptions_map(&root);

    #[cfg(target_os = "windows")]
    let raw_procs = win_hw::enumerate_running_processes_raw();
    #[cfg(not(target_os = "windows"))]
    let raw_procs: Vec<(u32, String, String, f64)> = Vec::new();

    #[cfg(target_os = "windows")]
    let raw_startup: Vec<(String, String, String)> = win_hw::enumerate_windows_startup_raw()
        .into_iter()
        .filter(|(_, _, _, _, _, _, enabled)| *enabled)
        .map(|(_, name, display, _, _, target, _)| (name, display, target))
        .collect();
    #[cfg(not(target_os = "windows"))]
    let raw_startup: Vec<(String, String, String)> = Vec::new();

    let is_in_startup = |proc_name: &str| -> bool {
        raw_startup.iter().any(|(s_name, s_disp, s_target)| {
            startup_entry_matches_process(s_name, s_disp, s_target, proc_name)
        })
    };

    let self_pid = std::process::id();
    let mut startup_process_names_set: std::collections::HashSet<String> =
        std::collections::HashSet::new();
    let mut processes: Vec<ProcessItem> = raw_procs
        .into_iter()
        .map(|(pid, name, executable_path, memory_mb)| {
            let protection_kind = if pid <= 4 {
                Some("os_core".to_string())
            } else if pid == self_pid {
                Some("self_app".to_string())
            } else {
                classify_process_protection(&name).map(|s| s.to_string())
            };
            let is_protected = protection_kind.is_some();
            #[cfg(target_os = "windows")]
            let exe_meta = win_hw::read_exe_metadata(&executable_path);
            #[cfg(not(target_os = "windows"))]
            let exe_meta = ExeMetadata::default();
            let curated = lookup_process_description(&proc_desc_map, &name);
            let (display_name, summary_ru, can_disable_hint, safety_level) =
                build_process_tooltip_meta(
                    &name,
                    protection_kind.as_deref(),
                    curated,
                    &exe_meta,
                );
            let is_blacklisted = cfg
                .blacklist_processes
                .iter()
                .any(|b| strip_exe_suffix(b).eq_ignore_ascii_case(&name));
            let is_startup_protected = cfg
                .protected_startup_names
                .iter()
                .any(|p| strip_exe_suffix(p).eq_ignore_ascii_case(&name));
            let in_startup = is_in_startup(&name);
            if in_startup {
                startup_process_names_set.insert(name.to_lowercase());
            }
            ProcessItem {
                pid,
                name,
                display_name,
                executable_path,
                protection_kind,
                memory_mb,
                is_protected,
                is_blacklisted,
                is_startup_protected,
                in_startup,
                summary_ru,
                can_disable_hint,
                safety_level,
            }
        })
        .collect();

    let mut process_descriptions = std::collections::HashMap::new();
    for rule_name in cfg
        .blacklist_processes
        .iter()
        .chain(cfg.protected_startup_names.iter())
    {
        let clean = strip_exe_suffix(rule_name).trim();
        if clean.is_empty() {
            continue;
        }
        if is_in_startup(clean) {
            startup_process_names_set.insert(clean.to_lowercase());
        }
        let prot_kind = classify_process_protection(clean);
        let curated = lookup_process_description(&proc_desc_map, clean);
        let (disp, sum, hint, lvl) =
            build_process_tooltip_meta(clean, prot_kind, curated, &ExeMetadata::default());
        process_descriptions.insert(
            clean.to_lowercase(),
            ProcessDescriptionEntry {
                display_name_ru: disp,
                summary_ru: sum,
                can_disable_ru: hint,
                safety_level: lvl,
                protection_kind: prot_kind.map(|s| s.to_string()),
            },
        );
    }

    processes.sort_by(|a, b| {
        b.memory_mb
            .partial_cmp(&a.memory_mb)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });

    let mut startup_process_names: Vec<String> = startup_process_names_set.into_iter().collect();
    startup_process_names.sort();

    Ok(LiveProcessesSnapshot {
        processes,
        blacklist_processes: cfg.blacklist_processes,
        protected_startup_names: cfg.protected_startup_names,
        process_descriptions,
        startup_process_names,
    })
}
