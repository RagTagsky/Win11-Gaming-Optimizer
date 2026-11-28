use super::*;
#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;

pub fn parse_semver_tuple(raw: &str) -> Option<(u64, u64, u64)> {
    let trimmed = raw.trim().trim_start_matches(['v', 'V']);
    let core = trimmed.split(['-', '+']).next().unwrap_or("").trim();
    if core.is_empty() {
        return None;
    }
    let parts: Vec<&str> = core.split('.').collect();
    if parts.is_empty() || parts.len() > 4 {
        return None;
    }
    let major = parts[0].parse::<u64>().ok()?;
    let minor = parts.get(1).copied().unwrap_or("0").parse::<u64>().ok()?;
    let patch = parts.get(2).copied().unwrap_or("0").parse::<u64>().ok()?;
    Some((major, minor, patch))
}

pub fn is_newer_version(latest: &str, current: &str) -> bool {
    match (parse_semver_tuple(latest), parse_semver_tuple(current)) {
        (Some(l), Some(c)) => l > c,
        _ => false,
    }
}

pub fn is_allowed_github_url(url: &str) -> bool {
    let trimmed = url.trim();
    if trimmed.is_empty()
        || !trimmed.starts_with("https://")
        || trimmed.chars().any(|c| {
            c.is_control()
                || c.is_whitespace()
                || matches!(c, '"' | '\'' | '`' | '\\' | '<' | '>' | ';' | '|' | '&')
        })
    {
        return false;
    }
    let rest = &trimmed["https://".len()..];
    let authority_end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    let authority = &rest[..authority_end];
    if authority.is_empty() || authority.contains('@') || authority.contains(':') {
        return false;
    }
    let host = authority.to_ascii_lowercase();
    let path_lower = rest[authority_end..].to_ascii_lowercase();

    match host.as_str() {
        "github.com" => {
            path_lower == "/ragtagsky/win11-gaming-optimizer"
                || path_lower.starts_with("/ragtagsky/win11-gaming-optimizer/")
        }
        "api.github.com" => path_lower.starts_with("/repos/ragtagsky/win11-gaming-optimizer/"),
        _ => false,
    }
}

pub fn extract_release_download_tag(url: &str) -> Option<&str> {
    let trimmed = url.trim();
    if !trimmed.starts_with("https://") {
        return None;
    }
    let rest = &trimmed["https://".len()..];
    let path_start = rest.find('/')?;
    let path = &rest[path_start..];
    const PREFIX: &str = "/ragtagsky/win11-gaming-optimizer/releases/download/";
    if path.len() <= PREFIX.len() || !path.is_char_boundary(PREFIX.len()) {
        return None;
    }
    if !path[..PREFIX.len()].eq_ignore_ascii_case(PREFIX) {
        return None;
    }
    let after_dl = &path[PREFIX.len()..];
    let slash_idx = after_dl.find('/')?;
    let tag = &after_dl[..slash_idx];
    if tag.is_empty() || parse_semver_tuple(tag).is_none() {
        return None;
    }
    Some(tag)
}

pub(crate) fn extract_release_download_file(url: &str, tag: &str) -> Option<String> {
    let trimmed = url.trim();
    let rest = trimmed.strip_prefix("https://")?;
    let path_start = rest.find('/')?;
    let path = &rest[path_start..];
    let expected_prefix = format!(
        "/ragtagsky/win11-gaming-optimizer/releases/download/{}/",
        tag
    );
    if path.len() <= expected_prefix.len() || !path.is_char_boundary(expected_prefix.len()) {
        return None;
    }
    if !path[..expected_prefix.len()].eq_ignore_ascii_case(&expected_prefix) {
        return None;
    }
    let file_part = &path[expected_prefix.len()..];
    if file_part.is_empty() || file_part.contains(['/', '?', '#']) {
        return None;
    }
    Some(file_part.to_string())
}

pub fn validate_release_update_urls(
    installer_url: &str,
    checksum_url: &str,
    expected_file_name: &str,
    current_version: &str,
) -> Result<String, String> {
    if !is_allowed_github_url(installer_url) || !is_allowed_github_url(checksum_url) {
        return Err("URL релиза не проходит проверку доверенного источника GitHub.".to_string());
    }
    if !is_safe_asset_filename(expected_file_name) {
        return Err("Недопустимое имя файла установщика.".to_string());
    }

    let tag_inst = extract_release_download_tag(installer_url)
        .ok_or_else(|| "URL установщика должен указывать на /releases/download/<tag>/<file>.".to_string())?;
    let tag_sum = extract_release_download_tag(checksum_url)
        .ok_or_else(|| "URL SHA256SUMS.txt должен указывать на /releases/download/<tag>/SHA256SUMS.txt.".to_string())?;

    if tag_inst != tag_sum {
        return Err(format!(
            "Несовпадение тегов релиза между установщиком ('{}') и SHA256SUMS.txt ('{}').",
            tag_inst, tag_sum
        ));
    }
    if !is_newer_version(tag_inst, current_version) {
        return Err(format!(
            "Отказ от понижения или повторной установки версии: релиз '{}' не новее текущей '{}'.",
            tag_inst, current_version
        ));
    }

    let inst_file = extract_release_download_file(installer_url, tag_inst)
        .ok_or_else(|| "Недопустимый путь файла в URL установщика.".to_string())?;
    if !inst_file.eq_ignore_ascii_case(expected_file_name.trim()) {
        return Err(format!(
            "Имя файла в URL ('{}') не совпадает с ожидаемым '{}'.",
            inst_file, expected_file_name
        ));
    }

    let sum_file = extract_release_download_file(checksum_url, tag_sum)
        .ok_or_else(|| "Недопустимый путь файла в URL SHA256SUMS.txt.".to_string())?;
    if !sum_file.eq_ignore_ascii_case("SHA256SUMS.txt") {
        return Err(format!(
            "URL контрольных сумм должен указывать на SHA256SUMS.txt, получено '{}'.",
            sum_file
        ));
    }

    Ok(tag_inst.to_string())
}

pub fn is_safe_asset_filename(name: &str) -> bool {
    let t = name.trim();
    if t.is_empty() || t.len() > 128 || t.contains("..") {
        return false;
    }
    t.chars()
        .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '_'))
}

pub fn sha256_hex(data: &[u8]) -> String {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
        0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
        0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
        0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
        0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
        0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2,
    ];
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
        0x5be0cd19,
    ];
    let bit_len = (data.len() as u64).wrapping_mul(8);
    let mut msg = data.to_vec();
    msg.push(0x80);
    while (msg.len() % 64) != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&bit_len.to_be_bytes());

    for chunk in msg.chunks_exact(64) {
        let mut w = [0u32; 64];
        for i in 0..16 {
            w[i] = u32::from_be_bytes([
                chunk[i * 4],
                chunk[i * 4 + 1],
                chunk[i * 4 + 2],
                chunk[i * 4 + 3],
            ]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }
        let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut hh] = h;
        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let temp1 = hh
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[i])
                .wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(maj);

            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
        }
        let next = [a, b, c, d, e, f, g, hh];
        for (dst, add) in h.iter_mut().zip(next.iter()) {
            *dst = dst.wrapping_add(*add);
        }
    }

    let mut hex = String::with_capacity(64);
    for word in h {
        hex.push_str(&format!("{:08x}", word));
    }
    hex
}

pub fn verify_sha256_manifest(
    manifest_text: &str,
    expected_filename: &str,
    file_bytes: &[u8],
) -> Result<(), String> {
    let mut expected_hash: Option<String> = None;
    for raw_line in manifest_text.trim_start_matches('\u{feff}').lines() {
        let line = raw_line.trim();
        if line.is_empty() {
            continue;
        }
        let mut parts = line.split_whitespace();
        let Some(hash_tok) = parts.next() else { continue };
        let Some(file_tok) = parts.next() else { continue };
        let clean_name = file_tok
            .trim_start_matches('*')
            .rsplit(['/', '\\'])
            .next()
            .unwrap_or("");
        if hash_tok.len() == 64
            && hash_tok.chars().all(|c| c.is_ascii_hexdigit())
            && clean_name.eq_ignore_ascii_case(expected_filename)
        {
            expected_hash = Some(hash_tok.to_ascii_lowercase());
            break;
        }
    }
    let expected = expected_hash.ok_or_else(|| {
        format!(
            "Файл '{}' не найден в SHA256SUMS.txt — установка отменена по соображениям безопасности.",
            expected_filename
        )
    })?;
    let actual = sha256_hex(file_bytes);
    if actual != expected {
        return Err(format!(
            "Несовпадение контрольной суммы SHA-256 для '{}': ожидалось {}, получено {}.",
            expected_filename, expected, actual
        ));
    }
    Ok(())
}

pub fn parse_github_release_json(
    raw_json: &str,
    current_version: &str,
) -> Result<UpdateInfo, String> {
    let val: serde_json::Value = serde_json::from_str(raw_json.trim_start_matches('\u{feff}'))
        .map_err(|e| format!("Ошибка разбора ответа GitHub Releases API: {}", e))?;

    let tag_raw = val
        .get("tag_name")
        .and_then(|v| v.as_str())
        .ok_or_else(|| "Ответ GitHub API не содержит tag_name".to_string())?;
    let latest_version = tag_raw.trim().trim_start_matches(['v', 'V']).to_string();
    let default_url = format!("https://github.com/{}/releases", GITHUB_REPO);
    let html_url = val
        .get("html_url")
        .and_then(|v| v.as_str())
        .filter(|u| is_allowed_github_url(u))
        .unwrap_or(&default_url)
        .to_string();
    let published_at = val
        .get("published_at")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());
    let release_notes = val
        .get("body")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .chars()
        .take(2000)
        .collect::<String>();

    let mut exe_setup: Option<(String, String, Option<u64>)> = None;
    let mut exe_portable: Option<(String, String, Option<u64>)> = None;
    let mut msi_any: Option<(String, String, Option<u64>)> = None;
    let mut checksum_url: Option<String> = None;

    if let Some(assets) = val.get("assets").and_then(|v| v.as_array()) {
        for asset in assets {
            let Some(name) = asset.get("name").and_then(|v| v.as_str()) else { continue };
            let Some(url) = asset
                .get("browser_download_url")
                .and_then(|v| v.as_str())
                .filter(|u| is_allowed_github_url(u))
            else {
                continue;
            };
            if !is_safe_asset_filename(name) {
                continue;
            }
            let size = asset.get("size").and_then(|v| v.as_u64());
            let lower = name.to_ascii_lowercase();
            if lower == "sha256sums.txt" {
                checksum_url = Some(url.to_string());
            } else if lower.ends_with(".exe") {
                if lower.contains("setup") && exe_setup.is_none() {
                    exe_setup = Some((url.to_string(), name.to_string(), size));
                } else if !lower.contains("setup") && exe_portable.is_none() {
                    exe_portable = Some((url.to_string(), name.to_string(), size));
                }
            } else if lower.ends_with(".msi") && msi_any.is_none() {
                msi_any = Some((url.to_string(), name.to_string(), size));
            }
        }
    }

    let setup_url = exe_setup.as_ref().map(|(u, _, _)| u.clone());
    let setup_size_bytes = exe_setup.as_ref().and_then(|(_, _, s)| *s);
    let msi_url = msi_any.as_ref().map(|(u, _, _)| u.clone());
    let msi_size_bytes = msi_any.as_ref().and_then(|(_, _, s)| *s);
    let portable_url = exe_portable.as_ref().map(|(u, _, _)| u.clone());
    let portable_size_bytes = exe_portable.as_ref().and_then(|(_, _, s)| *s);

    let chosen = exe_setup.or(exe_portable).or(msi_any);
    let (installer_url, installer_name, size_bytes) = match chosen {
        Some((u, n, s)) => (Some(u), Some(n), s),
        None => (None, None, None),
    };

    Ok(UpdateInfo {
        current_version: current_version.to_string(),
        latest_version: latest_version.clone(),
        has_update: is_newer_version(&latest_version, current_version),
        release_url: html_url,
        published_at,
        release_notes,
        installer_url,
        installer_name,
        checksum_url,
        size_bytes,
        setup_url,
        setup_size_bytes,
        msi_url,
        msi_size_bytes,
        portable_url,
        portable_size_bytes,
    })
}

pub(crate) fn resolve_curl_exe() -> PathBuf {
    resolve_system32_binary("curl.exe")
        .unwrap_or_else(|| PathBuf::from(r"C:\Windows\System32\curl.exe"))
}

pub fn http_get_text_github(url: &str, timeout_secs: &str) -> Result<String, String> {
    if !is_allowed_github_url(url) {
        return Err("URL не прошёл проверку белого списка GitHub.".to_string());
    }
    let curl = resolve_curl_exe();
    let mut cmd = Command::new(&curl);
    cmd.args([
        "-fsSL",
        "--proto",
        "=https",
        "--max-redirs",
        "5",
        "--max-time",
        timeout_secs,
        "-A",
        &format!("UltraGamingMode/{}", APP_VERSION),
        "-H",
        "Accept: application/vnd.github+json",
        "--",
        url,
    ]);
    #[cfg(target_os = "windows")]
    cmd.creation_flags(CREATE_NO_WINDOW);
    let output = cmd
        .output()
        .map_err(|e| format!("Не удалось запустить curl.exe: {}", e))?;
    if !output.status.success() {
        let stderr = decode_powershell_output(&output.stderr).trim().to_string();
        return Err(if stderr.is_empty() {
            format!("HTTP-запрос завершился с кодом {:?}", output.status.code())
        } else {
            stderr
        });
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

pub fn http_download_file_github(url: &str, dest_path: &Path) -> Result<(), String> {
    if !is_allowed_github_url(url) {
        return Err("URL скачивания не прошёл проверку белого списка GitHub.".to_string());
    }
    let dest_str = dest_path
        .to_str()
        .ok_or_else(|| "Недопустимый временный путь скачивания".to_string())?;
    let curl = resolve_curl_exe();
    let mut cmd = Command::new(&curl);
    cmd.args([
        "-fsSL",
        "--proto",
        "=https",
        "--max-redirs",
        "6",
        "--max-time",
        "180",
        "-A",
        &format!("UltraGamingMode/{}", APP_VERSION),
        "-o",
        dest_str,
        "--",
        url,
    ]);
    #[cfg(target_os = "windows")]
    cmd.creation_flags(CREATE_NO_WINDOW);
    let output = cmd
        .output()
        .map_err(|e| format!("Не удалось запустить curl.exe для загрузки: {}", e))?;
    if !output.status.success() {
        let stderr = decode_powershell_output(&output.stderr).trim().to_string();
        return Err(if stderr.is_empty() {
            format!("Ошибка загрузки (код {:?})", output.status.code())
        } else {
            stderr
        });
    }
    Ok(())
}

pub fn resolve_latest_release_via_redirect(current_version: &str) -> Result<UpdateInfo, String> {
    let url = format!("https://github.com/{}/releases/latest", GITHUB_REPO);
    let curl = resolve_curl_exe();
    let mut cmd = Command::new(&curl);
    cmd.args([
        "-sSLI",
        "--proto",
        "=https",
        "--max-redirs",
        "5",
        "--max-time",
        "10",
        "-A",
        &format!("UltraGamingMode/{}", APP_VERSION),
        "-o",
        "NUL",
        "-w",
        "%{url_effective}",
        "--",
        &url,
    ]);
    #[cfg(target_os = "windows")]
    cmd.creation_flags(CREATE_NO_WINDOW);
    let output = cmd
        .output()
        .map_err(|e| format!("Не удалось проверить редирект GitHub: {}", e))?;
    let effective = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if !output.status.success() || !is_allowed_github_url(&effective) {
        return Err("GitHub API и страница релизов временно недоступны.".to_string());
    }
    let tag = effective
        .split("/releases/tag/")
        .nth(1)
        .and_then(|s| s.split(['?', '#']).next())
        .map(|s| s.trim())
        .filter(|s| !s.is_empty() && parse_semver_tuple(s).is_some())
        .ok_or_else(|| "Не удалось определить тег последнего релиза на GitHub.".to_string())?;
    let clean_ver = tag.trim_start_matches(['v', 'V']).to_string();
    let dl_base = format!(
        "https://github.com/{}/releases/download/{}",
        GITHUB_REPO, tag
    );
    let setup_url = Some(format!("{}/UltraGamingMode-Setup.exe", dl_base));
    let msi_url = Some(format!("{}/UltraGamingMode.msi", dl_base));
    let portable_url = Some(format!("{}/UltraGamingMode.exe", dl_base));
    let checksum_url = Some(format!("{}/SHA256SUMS.txt", dl_base));
    Ok(UpdateInfo {
        current_version: current_version.to_string(),
        latest_version: clean_ver.clone(),
        has_update: is_newer_version(&clean_ver, current_version),
        release_url: effective,
        published_at: None,
        release_notes: "Подробности изменений доступны на странице релиза GitHub (API временно ограничен по лимиту).".to_string(),
        installer_url: setup_url.clone(),
        installer_name: Some("UltraGamingMode-Setup.exe".to_string()),
        checksum_url,
        size_bytes: None,
        setup_url,
        setup_size_bytes: None,
        msi_url,
        msi_size_bytes: None,
        portable_url,
        portable_size_bytes: None,
    })
}

pub fn clean_win_path(p: &Path) -> PathBuf {
    let raw = p.to_string_lossy();
    if let Some(stripped) = raw.strip_prefix(r"\\?\") {
        PathBuf::from(stripped)
    } else {
        p.to_path_buf()
    }
}

pub(crate) fn norm_dir_key(p: &Path) -> String {
    clean_win_path(p)
        .to_string_lossy()
        .trim()
        .trim_matches('"')
        .trim_end_matches(['\\', '/'])
        .replace('/', "\\")
        .to_lowercase()
}

pub fn detect_install_kind_with(
    exe_path: &Path,
    nsis_reg_install_dir: Option<&str>,
    msi_installed: bool,
    program_files_dir: Option<&str>,
) -> InstallKind {
    let cleaned_exe = clean_win_path(exe_path);
    let Some(exe_dir) = cleaned_exe.parent() else {
        return InstallKind::Portable;
    };
    if exe_dir.join("Uninstall.exe").is_file() {
        return InstallKind::NsisSetup;
    }
    let exe_dir_key = norm_dir_key(exe_dir);
    if let Some(nsis_dir) = nsis_reg_install_dir {
        let trimmed = nsis_dir.trim().trim_matches('"');
        if !trimmed.is_empty() && norm_dir_key(Path::new(trimmed)) == exe_dir_key {
            return InstallKind::NsisSetup;
        }
    }
    if msi_installed {
        let pf = program_files_dir
            .filter(|s| !s.trim().is_empty())
            .unwrap_or(r"C:\Program Files");
        let default_msi_dir = Path::new(pf).join("UltraGamingMode");
        if norm_dir_key(&default_msi_dir) == exe_dir_key {
            return InstallKind::WixMsi;
        }
    }
    InstallKind::Portable
}

pub fn detect_install_kind_for_exe(exe_path: &Path) -> InstallKind {
    #[cfg(target_os = "windows")]
    {
        let nsis_dir = win_hw::read_reg_string(
            r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\UltraGamingMode",
            "InstallLocation",
        );
        let msi_installed = win_hw::query_installed_msi_product_code().is_some();
        let pf = std::env::var("ProgramW6432")
            .ok()
            .or_else(|| std::env::var("ProgramFiles").ok());
        detect_install_kind_with(
            exe_path,
            nsis_dir.as_deref(),
            msi_installed,
            pf.as_deref(),
        )
    }
    #[cfg(not(target_os = "windows"))]
    {
        detect_install_kind_with(exe_path, None, false, None)
    }
}

pub fn select_update_target_for_kind(
    info: &UpdateInfo,
    kind: InstallKind,
) -> Result<(String, String, String, Option<u64>), String> {
    let checksum_url = info.checksum_url.clone().ok_or_else(|| {
        "В релизе отсутствует SHA256SUMS.txt — автоматическая установка отменена для защиты целостности."
            .to_string()
    })?;
    match kind {
        InstallKind::NsisSetup => {
            let url = info.setup_url.clone().ok_or_else(|| {
                "В релизе не найден пакет обновления UltraGamingMode-Setup.exe.".to_string()
            })?;
            Ok((
                url,
                "UltraGamingMode-Setup.exe".to_string(),
                checksum_url,
                info.setup_size_bytes,
            ))
        }
        InstallKind::WixMsi => {
            let url = info.msi_url.clone().ok_or_else(|| {
                "В релизе не найден пакет обновления UltraGamingMode.msi.".to_string()
            })?;
            Ok((
                url,
                "UltraGamingMode.msi".to_string(),
                checksum_url,
                info.msi_size_bytes,
            ))
        }
        InstallKind::Portable => {
            let url = info.portable_url.clone().ok_or_else(|| {
                "В релизе не найден портативный бинарник UltraGamingMode.exe.".to_string()
            })?;
            Ok((
                url,
                "UltraGamingMode.exe".to_string(),
                checksum_url,
                info.portable_size_bytes,
            ))
        }
    }
}

pub fn cleanup_stale_update_artifacts() {
    if let Ok(exe) = std::env::current_exe() {
        let cleaned = clean_win_path(&exe);
        if let Some(fname) = cleaned.file_name().and_then(|n| n.to_str()) {
            let old_bak = cleaned.with_file_name(format!("{}.old", fname));
            if old_bak.exists() {
                let _ = std::fs::remove_file(&old_bak);
            }
        }
    }
    if let Ok(entries) = std::fs::read_dir(std::env::temp_dir()) {
        let cutoff = std::time::Duration::from_secs(30 * 60);
        for entry in entries.flatten() {
            let name = entry.file_name();
            if name
                .to_str()
                .map(|s| s.starts_with("ugm_update_"))
                .unwrap_or(false)
            {
                let is_stale = entry
                    .metadata()
                    .and_then(|m| m.modified())
                    .ok()
                    .and_then(|t| t.elapsed().ok())
                    .map(|age| age > cutoff)
                    .unwrap_or(false);
                if is_stale {
                    let _ = std::fs::remove_dir_all(entry.path());
                }
            }
        }
    }
}

pub fn build_update_applier_script() -> &'static str {
    concat!(
        "$ErrorActionPreference = 'Stop'\n",
        "$waitPid   = 0\n",
        "[void][int]::TryParse($env:UGM_UPD_PID, [ref]$waitPid)\n",
        "$mode      = $env:UGM_UPD_MODE\n",
        "$pkg       = $env:UGM_UPD_PKG\n",
        "$targetExe = $env:UGM_UPD_TARGET_EXE\n",
        "$stageDir  = $env:UGM_UPD_STAGE_DIR\n",
        "$noRelaunch = ($env:UGM_UPD_NO_RELAUNCH -eq '1')\n",
        "$targetDir = Split-Path -Parent $targetExe\n",
        "\n",
        "if ($waitPid -gt 0) {\n",
        "    for ($i = 0; $i -lt 60; $i++) {\n",
        "        $proc = Get-Process -Id $waitPid -ErrorAction SilentlyContinue\n",
        "        if ($null -eq $proc) { break }\n",
        "        Start-Sleep -Milliseconds 250\n",
        "    }\n",
        "    Start-Sleep -Milliseconds 250\n",
        "}\n",
        "\n",
        "$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)\n",
        "\n",
        "try {\n",
        "    if ($mode -eq 'portable') {\n",
        "        $bak = \"$targetExe.old\"\n",
        "        if (Test-Path -LiteralPath $bak) {\n",
        "            Remove-Item -LiteralPath $bak -Force -ErrorAction SilentlyContinue\n",
        "        }\n",
        "        if (Test-Path -LiteralPath $targetExe) {\n",
        "            Move-Item -LiteralPath $targetExe -Destination $bak -Force\n",
        "        }\n",
        "        try {\n",
        "            Copy-Item -LiteralPath $pkg -Destination $targetExe -Force\n",
        "            if (Test-Path -LiteralPath $bak) {\n",
        "                Remove-Item -LiteralPath $bak -Force -ErrorAction SilentlyContinue\n",
        "            }\n",
        "        } catch {\n",
        "            if ((-not (Test-Path -LiteralPath $targetExe)) -and (Test-Path -LiteralPath $bak)) {\n",
        "                Move-Item -LiteralPath $bak -Destination $targetExe -Force -ErrorAction SilentlyContinue\n",
        "            }\n",
        "            throw\n",
        "        }\n",
        "    } elseif ($mode -eq 'nsis') {\n",
        "        $argStr = \"/S /D=$targetDir\"\n",
        "        if ($isAdmin) {\n",
        "            [void](Start-Process -FilePath $pkg -ArgumentList $argStr -Wait -PassThru)\n",
        "        } else {\n",
        "            [void](Start-Process -FilePath $pkg -ArgumentList $argStr -Verb RunAs -Wait -PassThru)\n",
        "        }\n",
        "    } elseif ($mode -eq 'msi') {\n",
        "        $msiExe = Join-Path $env:SystemRoot 'System32\\msiexec.exe'\n",
        "        if ($isAdmin) {\n",
        "            [void](Start-Process -FilePath $msiExe -ArgumentList @('/i', \"`\"$pkg`\"\", '/qn', 'REBOOT=ReallySuppress') -Wait -PassThru)\n",
        "        } else {\n",
        "            [void](Start-Process -FilePath $msiExe -ArgumentList @('/i', \"`\"$pkg`\"\", '/passive', 'REBOOT=ReallySuppress') -Verb RunAs -Wait -PassThru)\n",
        "        }\n",
        "    }\n",
        "} catch {\n",
        "}\n",
        "\n",
        "if ((-not $noRelaunch) -and (Test-Path -LiteralPath $targetExe)) {\n",
        "    try {\n",
        "        [void](Start-Process -FilePath $targetExe -WorkingDirectory $targetDir)\n",
        "    } catch {}\n",
        "}\n",
        "\n",
        "if (-not [string]::IsNullOrWhiteSpace($pkg) -and (Test-Path -LiteralPath $pkg)) {\n",
        "    Remove-Item -LiteralPath $pkg -Force -ErrorAction SilentlyContinue\n",
        "}\n",
        "if (-not [string]::IsNullOrWhiteSpace($stageDir) -and (Test-Path -LiteralPath $stageDir)) {\n",
        "    Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue\n",
        "}\n"
    )
}

pub fn prepare_verified_update_sync<F>(
    cached_info: Option<UpdateInfo>,
    mut on_progress: F,
) -> Result<PreparedUpdate, String>
where
    F: FnMut(&str),
{
    let raw_exe = std::env::current_exe()
        .map_err(|e| format!("Не удалось определить путь текущего исполняемого файла: {}", e))?;
    let target_exe = clean_win_path(&raw_exe);
    let kind = detect_install_kind_for_exe(&target_exe);

    if kind == InstallKind::Portable {
        let Some(exe_dir) = target_exe.parent() else {
            return Err("Не удалось определить каталог установки программы.".to_string());
        };
        if !is_dir_writable(exe_dir) {
            return Err(
                "Папка с программой недоступна для записи. Переместите UltraGamingMode.exe в доступную папку или запустите от имени администратора."
                    .to_string(),
            );
        }
    }

    let info = match cached_info.filter(|c| c.has_update && c.checksum_url.is_some()) {
        Some(c) => c,
        None => {
            on_progress("Получение метаданных релиза…");
            check_for_updates_sync()?
        }
    };

    if !info.has_update || !is_newer_version(&info.latest_version, APP_VERSION) {
        return Err(format!(
            "Установлена актуальная версия v{} — обновление не требуется.",
            APP_VERSION
        ));
    }

    let (asset_url, asset_name, checksum_url, expected_size) =
        select_update_target_for_kind(&info, kind)?;
    validate_release_update_urls(&asset_url, &checksum_url, &asset_name, APP_VERSION)?;

    on_progress("Загрузка контрольных сумм SHA-256…");
    let manifest_text = http_get_text_github(&checksum_url, "20")?;

    let safe_ver: String = info
        .latest_version
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '_'))
        .collect();
    let stage_dir = std::env::temp_dir().join(format!(
        "ugm_update_{}_{}",
        if safe_ver.is_empty() { "next" } else { &safe_ver },
        std::process::id()
    ));
    let _ = std::fs::remove_dir_all(&stage_dir);
    std::fs::create_dir_all(&stage_dir)
        .map_err(|e| format!("Не удалось создать временный каталог обновления: {}", e))?;

    let dl_label = match expected_size {
        Some(sz) if sz > 0 => format!(
            "Скачивание {} ({:.1} МБ)…",
            asset_name,
            sz as f64 / (1024.0 * 1024.0)
        ),
        _ => format!("Скачивание {}…", asset_name),
    };
    on_progress(&dl_label);

    let part_path = stage_dir.join(format!("{}.part", asset_name));
    if let Err(e) = http_download_file_github(&asset_url, &part_path) {
        let _ = std::fs::remove_dir_all(&stage_dir);
        return Err(e);
    }

    on_progress("Проверка контрольной суммы SHA-256…");
    let file_bytes = match std::fs::read(&part_path) {
        Ok(b) => b,
        Err(e) => {
            let _ = std::fs::remove_dir_all(&stage_dir);
            return Err(format!("Не удалось прочитать скачанный пакет обновления: {}", e));
        }
    };

    if file_bytes.len() < 512 * 1024 {
        let _ = std::fs::remove_dir_all(&stage_dir);
        return Err("Скачанный файл обновления повреждён или неполный (слишком малый размер).".to_string());
    }
    if let Some(exp_sz) = expected_size {
        if exp_sz > 0 && file_bytes.len() as u64 != exp_sz {
            let _ = std::fs::remove_dir_all(&stage_dir);
            return Err(format!(
                "Размер скачанного файла ({} байт) не совпадает с ожидаемым ({} байт).",
                file_bytes.len(),
                exp_sz
            ));
        }
    }

    let valid_magic = if asset_name.to_ascii_lowercase().ends_with(".msi") {
        file_bytes.starts_with(&[0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
    } else {
        file_bytes.starts_with(b"MZ")
    };
    if !valid_magic {
        let _ = std::fs::remove_dir_all(&stage_dir);
        return Err("Скачанный пакет не прошёл проверку сигнатуры исполняемого файла.".to_string());
    }

    if let Err(e) = verify_sha256_manifest(&manifest_text, &asset_name, &file_bytes) {
        let _ = std::fs::remove_dir_all(&stage_dir);
        return Err(e);
    }

    let package_path = stage_dir.join(&asset_name);
    if let Err(e) = std::fs::rename(&part_path, &package_path) {
        let _ = std::fs::remove_dir_all(&stage_dir);
        return Err(format!("Не удалось подготовить проверенный пакет обновления: {}", e));
    }

    Ok(PreparedUpdate {
        latest_version: info.latest_version,
        kind,
        stage_dir,
        package_path,
        target_exe,
    })
}

pub fn spawn_detached_update_applier(prepared: &PreparedUpdate) -> Result<(), String> {
    let script_path = prepared.stage_dir.join("apply_update.ps1");
    std::fs::write(&script_path, build_update_applier_script().as_bytes())
        .map_err(|e| format!("Не удалось записать сценарий применения обновления: {}", e))?;

    let mode_str = match prepared.kind {
        InstallKind::Portable => "portable",
        InstallKind::NsisSetup => "nsis",
        InstallKind::WixMsi => "msi",
    };

    let ps_exe = resolve_powershell_exe();
    let mut cmd = Command::new(&ps_exe);
    cmd.args([
        "-NoProfile",
        "-NonInteractive",
        "-WindowStyle",
        "Hidden",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
    ])
    .arg(&script_path)
    .env("UGM_UPD_PID", std::process::id().to_string())
    .env("UGM_UPD_MODE", mode_str)
    .env("UGM_UPD_PKG", &prepared.package_path)
    .env("UGM_UPD_TARGET_EXE", &prepared.target_exe)
    .env("UGM_UPD_STAGE_DIR", &prepared.stage_dir);

    #[cfg(target_os = "windows")]
    {
        const CREATE_NEW_PROCESS_GROUP: u32 = 0x0000_0200;
        cmd.creation_flags(CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP);
    }

    cmd.spawn()
        .map_err(|e| format!("Не удалось запустить фоновый процесс обновления: {}", e))?;
    Ok(())
}

pub fn check_for_updates_sync() -> Result<UpdateInfo, String> {
    let api_url = format!(
        "https://api.github.com/repos/{}/releases/latest",
        GITHUB_REPO
    );
    match http_get_text_github(&api_url, "10")
        .and_then(|body| parse_github_release_json(&body, APP_VERSION))
    {
        Ok(info) => Ok(info),
        Err(_) => resolve_latest_release_via_redirect(APP_VERSION),
    }
}

pub fn open_release_url_sync(url: &str) -> Result<(), String> {
    let trimmed = url.trim().to_string();
    if !is_allowed_github_url(&trimmed) {
        return Err("Открытие разрешено только для официальных URL GitHub этого репозитория.".to_string());
    }
    let explorer = std::env::var_os("SystemRoot")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(r"C:\Windows"))
        .join("explorer.exe");
    Command::new(&explorer)
        .arg(&trimmed)
        .spawn()
        .map_err(|e| format!("Не удалось открыть браузер: {}", e))?;
    Ok(())
}
