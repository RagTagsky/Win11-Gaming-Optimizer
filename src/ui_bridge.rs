use std::cell::RefCell;
use std::path::PathBuf;
use std::rc::Rc;
use std::sync::atomic::Ordering;
use std::sync::{mpsc, Arc, Mutex};

use slint::{ComponentHandle, ModelRc, SharedString, VecModel};

use crate::backend::{
    self, AutostartStatus, InstalledServiceItem, LiveProcessesSnapshot, ServiceFeaturePack,
    ServicesLists, SystemStatus, TuningConfig, ALLOW_APP_EXIT, APP_VERSION,
    AUTO_PURGE_RAM_POLL_SECS, MODE_ACTION_BUSY, PENDING_RESTORE_TRIGGERED, START_IN_TRAY,
    TIMER_LOCKED,
};
use crate::dwm::apply_dwm_dark_mode;
use crate::themes::{
    all_themes, get_theme_by_id, RgbaColor, ThemeDefinition, ThemeId, ThemePreferences,
};
use crate::tray::{TrayCommand, TrayController, TrayStateSnapshot};

slint::slint! {
    #[edition = "1.19"]
    export {
        MainWindow,
        ThemeTokens,
        ThemeCardItem,
        ProcessRowItem,
        ServiceRowItem,
        FeaturePackItem,
        LogRowItem
    } from "../slint/main.slint";
}

pub fn rgba_to_slint_color(c: RgbaColor) -> slint::Color {
    let (r, g, b, a) = c.to_rgba_u8();
    slint::Color::from_argb_u8(a, r, g, b)
}

pub const fn theme_polarity_to_dwm_flag(theme: &ThemeDefinition) -> bool {
    theme.is_dark
}

pub fn build_theme_card_items(active_id: ThemeId) -> [ThemeCardItem; 8] {
    let themes = all_themes();
    std::array::from_fn(|idx| {
        let t = &themes[idx];
        ThemeCardItem {
            id: SharedString::from(t.id_str),
            name_ru: SharedString::from(t.name_ru),
            is_dark: t.is_dark,
            is_active: t.id == active_id,
            preview_bg: rgba_to_slint_color(t.preview_bg),
            preview_surface: rgba_to_slint_color(t.preview_surface),
            preview_elevated: rgba_to_slint_color(t.preview_elevated),
            preview_border: rgba_to_slint_color(t.preview_border),
            preview_accent: rgba_to_slint_color(t.preview_accent),
            preview_accent_text: rgba_to_slint_color(t.preview_accent_text),
            preview_text: rgba_to_slint_color(t.preview_text),
        }
    })
}

pub fn extract_window_hwnd(window: &MainWindow) -> Option<isize> {
    use raw_window_handle::{HasWindowHandle, RawWindowHandle};
    let win_handle = window.window().window_handle();
    let handle = HasWindowHandle::window_handle(&win_handle).ok()?;
    match handle.as_raw() {
        RawWindowHandle::Win32(h) => Some(h.hwnd.get() as isize),
        _ => None,
    }
}

pub fn sync_window_dwm_theme(window: &MainWindow, is_dark: bool) {
    if let Some(hwnd) = extract_window_hwnd(window) {
        let _ = apply_dwm_dark_mode(hwnd, is_dark);
    }
}

#[cfg(target_os = "windows")]
fn start_native_window_drag(window: &MainWindow) {
    if let Some(hwnd) = extract_window_hwnd(window) {
        #[link(name = "user32")]
        extern "system" {
            fn ReleaseCapture() -> i32;
            fn SendMessageW(hWnd: isize, Msg: u32, wParam: usize, lParam: isize) -> isize;
        }
        const WM_NCLBUTTONDOWN: u32 = 0x00A1;
        const HTCAPTION: usize = 2;
        unsafe {
            let _ = ReleaseCapture();
            let _ = SendMessageW(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
        }
    }
}

#[cfg(not(target_os = "windows"))]
fn start_native_window_drag(_window: &MainWindow) {}

pub fn apply_theme_to_window(window: &MainWindow, theme_id: ThemeId) {
    let t = get_theme_by_id(theme_id);
    let tokens = window.global::<ThemeTokens>();

    tokens.set_active_theme_id(SharedString::from(t.id_str));
    tokens.set_active_theme_name(SharedString::from(t.name_ru));
    tokens.set_is_dark(t.is_dark);

    tokens.set_bg_app(rgba_to_slint_color(t.bg_app));
    tokens.set_bg_surface(rgba_to_slint_color(t.bg_surface));
    tokens.set_bg_elevated(rgba_to_slint_color(t.bg_elevated));
    tokens.set_bg_hover(rgba_to_slint_color(t.bg_hover));
    tokens.set_bg_active(rgba_to_slint_color(t.bg_active));
    tokens.set_bg_titlebar(rgba_to_slint_color(t.bg_titlebar));
    tokens.set_border_subtle(rgba_to_slint_color(t.border_subtle));
    tokens.set_border_strong(rgba_to_slint_color(t.border_strong));
    tokens.set_border_input(rgba_to_slint_color(t.border_input));
    tokens.set_text_primary(rgba_to_slint_color(t.text_primary));
    tokens.set_text_secondary(rgba_to_slint_color(t.text_secondary));
    tokens.set_text_muted(rgba_to_slint_color(t.text_muted));
    tokens.set_accent_solid(rgba_to_slint_color(t.accent_solid));
    tokens.set_accent_solid_hover(rgba_to_slint_color(t.accent_solid_hover));
    tokens.set_accent_solid_active(rgba_to_slint_color(t.accent_solid_active));
    tokens.set_accent_text(rgba_to_slint_color(t.accent_text));
    tokens.set_accent_card_tint(rgba_to_slint_color(t.accent_card_tint));
    tokens.set_accent_soft(rgba_to_slint_color(t.accent_soft));
    tokens.set_accent_border(rgba_to_slint_color(t.accent_border));
    tokens.set_status_active_text(rgba_to_slint_color(t.status_active_text));
    tokens.set_status_active_soft(rgba_to_slint_color(t.status_active_soft));
    tokens.set_status_active_border(rgba_to_slint_color(t.status_active_border));
    tokens.set_status_warn_text(rgba_to_slint_color(t.status_warn_text));
    tokens.set_status_warn_soft(rgba_to_slint_color(t.status_warn_soft));
    tokens.set_status_warn_border(rgba_to_slint_color(t.status_warn_border));
    tokens.set_status_danger_solid(rgba_to_slint_color(t.status_danger_solid));
    tokens.set_status_danger_solid_hover(rgba_to_slint_color(t.status_danger_solid_hover));
    tokens.set_status_danger_text(rgba_to_slint_color(t.status_danger_text));
    tokens.set_status_danger_soft(rgba_to_slint_color(t.status_danger_soft));
    tokens.set_status_danger_border(rgba_to_slint_color(t.status_danger_border));
    tokens.set_focus_ring(rgba_to_slint_color(t.focus_ring));
    tokens.set_switch_off_bg(rgba_to_slint_color(t.switch_off_bg));
    tokens.set_switch_off_border(rgba_to_slint_color(t.switch_off_border));
    tokens.set_switch_off_thumb(rgba_to_slint_color(t.switch_off_thumb));
    tokens.set_text_on_solid(rgba_to_slint_color(t.text_on_solid));
    tokens.set_close_hover_bg(rgba_to_slint_color(t.close_hover_bg));
    tokens.set_close_active_bg(rgba_to_slint_color(t.close_active_bg));
    tokens.set_backdrop_overlay(rgba_to_slint_color(t.backdrop_overlay));

    let sc = t.shadow_card.primary();
    tokens.set_shadow_card_offset_y(sc.offset_y);
    tokens.set_shadow_card_blur(sc.blur);
    tokens.set_shadow_card_color(rgba_to_slint_color(sc.color));

    let sch = t.shadow_card_hover.primary();
    tokens.set_shadow_card_hover_offset_y(sch.offset_y);
    tokens.set_shadow_card_hover_blur(sch.blur);
    tokens.set_shadow_card_hover_color(rgba_to_slint_color(sch.color));

    let sd = t.shadow_dialog.primary();
    tokens.set_shadow_dialog_offset_y(sd.offset_y);
    tokens.set_shadow_dialog_blur(sd.blur);
    tokens.set_shadow_dialog_color(rgba_to_slint_color(sd.color));

    tokens.set_scrollbar_thumb(rgba_to_slint_color(t.scrollbar_thumb));
    tokens.set_scrollbar_thumb_hover(rgba_to_slint_color(t.scrollbar_thumb_hover));

    if let Some(glow) = t.bg_app_glow {
        tokens.set_has_bg_app_glow(true);
        tokens.set_bg_app_glow_color(rgba_to_slint_color(glow.color));
    } else {
        tokens.set_has_bg_app_glow(false);
        tokens.set_bg_app_glow_color(slint::Color::from_argb_u8(0, 0, 0, 0));
    }

    if let Some(hl) = t.surface_top_highlight {
        tokens.set_has_surface_top_highlight(true);
        tokens.set_surface_top_highlight(rgba_to_slint_color(hl));
    } else {
        tokens.set_has_surface_top_highlight(false);
        tokens.set_surface_top_highlight(slint::Color::from_argb_u8(0, 0, 0, 0));
    }

    let cards = build_theme_card_items(theme_id);
    window.set_theme_card_0(cards[0].clone());
    window.set_theme_card_1(cards[1].clone());
    window.set_theme_card_2(cards[2].clone());
    window.set_theme_card_3(cards[3].clone());
    window.set_theme_card_4(cards[4].clone());
    window.set_theme_card_5(cards[5].clone());
    window.set_theme_card_6(cards[6].clone());
    window.set_theme_card_7(cards[7].clone());

    sync_window_dwm_theme(window, theme_polarity_to_dwm_flag(t));
}

fn now_hms_string() -> String {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let s = secs % 60;
    let m = (secs / 60) % 60;
    let h = (secs / 3600) % 24;
    format!("{:02}:{:02}:{:02}", h, m, s)
}

struct UiAppState {
    runtime_root: PathBuf,
    theme_prefs: ThemePreferences,
    tuning: TuningConfig,
    processes_snap: Option<LiveProcessesSnapshot>,
    services_lists: Option<ServicesLists>,
    process_filter: String,
    process_search: String,
    process_show_os_core: bool,
    service_filter: String,
    service_search: String,
    logs: Vec<LogRowItem>,
}

impl UiAppState {
    fn push_log(&mut self, window: &MainWindow, level: &str, message: impl Into<String>) {
        self.logs.push(LogRowItem {
            timestamp: SharedString::from(now_hms_string()),
            level: SharedString::from(level),
            message: SharedString::from(message.into()),
        });
        if self.logs.len() > 200 {
            let drain = self.logs.len() - 200;
            self.logs.drain(0..drain);
        }
        window.set_log_count(self.logs.len() as i32);
        window.set_logs(ModelRc::new(VecModel::from(self.logs.clone())));
    }
}

fn protection_label_ru(kind: Option<&str>) -> &'static str {
    match kind {
        Some("os_core") => "Ядро Windows",
        Some("self_app") => "Это приложение",
        Some("anticheat") => "Античит",
        Some("game_client") => "Игровой клиент",
        Some("network_bypass") => "Zapret / Сеть",
        _ => "Защищено",
    }
}

fn format_mem_ru(mb: f64, count: usize) -> String {
    let mem_part = if mb >= 1024.0 {
        format!("{:.1} ГБ", mb / 1024.0)
    } else if mb >= 10.0 {
        format!("{:.0} МБ", mb.round())
    } else {
        format!("{:.1} МБ", mb)
    };
    if count > 1 {
        format!("{} ×{}", mem_part, count)
    } else {
        mem_part
    }
}

fn refresh_processes_model(state: &mut UiAppState, window: &MainWindow) {
    let Some(ref snap) = state.processes_snap else {
        return;
    };

    let bl_set: std::collections::HashSet<String> = snap
        .blacklist_processes
        .iter()
        .map(|s| backend::strip_exe_suffix(s).to_lowercase())
        .filter(|s| !s.is_empty())
        .collect();
    let prot_set: std::collections::HashSet<String> = snap
        .protected_startup_names
        .iter()
        .map(|s| backend::strip_exe_suffix(s).to_lowercase())
        .filter(|s| !s.is_empty())
        .collect();
    let startup_set: std::collections::HashSet<String> = snap
        .startup_process_names
        .iter()
        .map(|s| backend::strip_exe_suffix(s).to_lowercase())
        .filter(|s| !s.is_empty())
        .collect();

    struct AggProc {
        key: String,
        name: String,
        display_name: String,
        is_running: bool,
        total_mb: f64,
        count: usize,
        is_protected: bool,
        prot_kind: Option<String>,
        disable_in_gaming: bool,
        in_startup: bool,
        summary_ru: String,
        can_disable_hint: String,
        safety_level: String,
    }

    let mut map: std::collections::HashMap<String, AggProc> = std::collections::HashMap::new();

    for p in &snap.processes {
        let clean = backend::strip_exe_suffix(&p.name).to_string();
        let key = clean.to_lowercase();
        if key.is_empty() {
            continue;
        }
        let is_prot = p.is_protected || p.protection_kind.is_some();
        let disable = !is_prot && bl_set.contains(&key) && !prot_set.contains(&key);
        let in_st = p.in_startup || startup_set.contains(&key);

        if let Some(existing) = map.get_mut(&key) {
            existing.total_mb += p.memory_mb;
            existing.count += 1;
            existing.is_protected = existing.is_protected || is_prot;
            existing.in_startup = existing.in_startup || in_st;
            existing.disable_in_gaming =
                !existing.is_protected && bl_set.contains(&key) && !prot_set.contains(&key);
        } else {
            map.insert(
                key.clone(),
                AggProc {
                    key,
                    name: clean.clone(),
                    display_name: if p.display_name.trim().is_empty() {
                        clean
                    } else {
                        p.display_name.clone()
                    },
                    is_running: true,
                    total_mb: p.memory_mb,
                    count: 1,
                    is_protected: is_prot,
                    prot_kind: p.protection_kind.clone(),
                    disable_in_gaming: disable,
                    in_startup: in_st,
                    summary_ru: p.summary_ru.clone(),
                    can_disable_hint: p.can_disable_hint.clone(),
                    safety_level: p.safety_level.clone(),
                },
            );
        }
    }

    for raw_rule in snap
        .blacklist_processes
        .iter()
        .chain(snap.protected_startup_names.iter())
    {
        let clean = backend::strip_exe_suffix(raw_rule).to_string();
        let key = clean.to_lowercase();
        if key.is_empty() || map.contains_key(&key) {
            continue;
        }
        let desc = snap.process_descriptions.get(&key);
        let prot_kind = desc.and_then(|d| d.protection_kind.clone());
        let is_prot = prot_kind.is_some();
        let disable = !is_prot && bl_set.contains(&key) && !prot_set.contains(&key);
        let in_st = startup_set.contains(&key);
        map.insert(
            key.clone(),
            AggProc {
                key,
                name: clean.clone(),
                display_name: desc
                    .map(|d| d.display_name_ru.clone())
                    .filter(|s| !s.trim().is_empty())
                    .unwrap_or(clean),
                is_running: false,
                total_mb: 0.0,
                count: 0,
                is_protected: is_prot,
                prot_kind,
                disable_in_gaming: disable,
                in_startup: in_st,
                summary_ru: desc.map(|d| d.summary_ru.clone()).unwrap_or_default(),
                can_disable_hint: desc.map(|d| d.can_disable_ru.clone()).unwrap_or_default(),
                safety_level: desc
                    .map(|d| d.safety_level.clone())
                    .unwrap_or_else(|| "optional".to_string()),
            },
        );
    }

    let mut all_items: Vec<AggProc> = map.into_values().collect();
    all_items.sort_by(|a, b| {
        b.is_running
            .cmp(&a.is_running)
            .then_with(|| {
                b.total_mb
                    .partial_cmp(&a.total_mb)
                    .unwrap_or(std::cmp::Ordering::Equal)
            })
            .then_with(|| a.display_name.to_lowercase().cmp(&b.display_name.to_lowercase()))
    });

    let os_core_count = all_items
        .iter()
        .filter(|i| i.prot_kind.as_deref() == Some("os_core"))
        .count();
    let q = state.process_search.trim().to_lowercase();

    let scope: Vec<&AggProc> = all_items
        .iter()
        .filter(|i| {
            state.process_show_os_core || !q.is_empty() || i.prot_kind.as_deref() != Some("os_core")
        })
        .collect();

    let total_count = scope.len();
    let disabled_count = scope.iter().filter(|i| i.disable_in_gaming).count();
    let normal_count = total_count.saturating_sub(disabled_count);
    let running_count = scope.iter().filter(|i| i.is_running).count();

    let rows: Vec<ProcessRowItem> = scope
        .into_iter()
        .filter(|i| {
            if state.process_filter == "disable" && !i.disable_in_gaming {
                return false;
            }
            if state.process_filter == "normal" && i.disable_in_gaming {
                return false;
            }
            if q.is_empty() {
                return true;
            }
            i.name.to_lowercase().contains(&q)
                || i.display_name.to_lowercase().contains(&q)
                || i.summary_ru.to_lowercase().contains(&q)
        })
        .map(|i| ProcessRowItem {
            key: SharedString::from(&i.key),
            name: SharedString::from(&i.name),
            display_name: SharedString::from(&i.display_name),
            is_running: i.is_running,
            memory_label: SharedString::from(format_mem_ru(i.total_mb, i.count)),
            is_protected: i.is_protected,
            protection_label: SharedString::from(protection_label_ru(i.prot_kind.as_deref())),
            disable_in_gaming: i.disable_in_gaming,
            in_startup: i.in_startup,
            summary_ru: SharedString::from(&i.summary_ru),
            can_disable_hint: SharedString::from(&i.can_disable_hint),
            safety_level: SharedString::from(&i.safety_level),
        })
        .collect();

    window.set_process_os_core_count(os_core_count as i32);
    window.set_process_total_count(total_count as i32);
    window.set_process_disabled_count(disabled_count as i32);
    window.set_process_normal_count(normal_count as i32);
    window.set_process_running_count(running_count as i32);
    window.set_disabled_processes_count(disabled_count as i32);
    window.set_process_items(ModelRc::new(VecModel::from(rows)));
}

fn short_pack_title(id: &str, fallback: &str) -> String {
    match id {
        "wifi" => "Wi-Fi".to_string(),
        "bluetooth" => "Bluetooth".to_string(),
        "faceit" => "FACEIT AC".to_string(),
        "camera" => "Камера".to_string(),
        "xbox" => "Xbox / Store".to_string(),
        "vpn" => "VPN / PPPoE".to_string(),
        "printer" => "Принтер".to_string(),
        _ => fallback.to_string(),
    }
}

fn service_status_label_ru(st: &str) -> &'static str {
    match st {
        "Running" => "Работает",
        "Stopped" => "Остановлена",
        "StartPending" => "Запуск…",
        "StopPending" => "Остановка…",
        "Paused" => "Пауза",
        _ => "",
    }
}

fn refresh_services_model(state: &mut UiAppState, window: &MainWindow) {
    let Some(ref lists) = state.services_lists else {
        return;
    };

    let all: &[InstalledServiceItem] = &lists.all_installed_services;
    let total_count = all.len();
    let disabled_count = all
        .iter()
        .filter(|s| !s.is_core_locked && s.disable_in_gaming)
        .count();
    let normal_count = total_count.saturating_sub(disabled_count);
    let running_count = all.iter().filter(|s| s.status == "Running").count();

    let wlan_disabled = all
        .iter()
        .find(|s| s.name.eq_ignore_ascii_case("WlanSvc"))
        .map(|s| !s.is_core_locked && s.disable_in_gaming)
        .unwrap_or(false);
    window.set_show_wifi_warning(lists.wifi_active && wlan_disabled);

    let packs: Vec<FeaturePackItem> = lists
        .feature_packs
        .iter()
        .map(|p: &ServiceFeaturePack| FeaturePackItem {
            id: SharedString::from(&p.id),
            title: SharedString::from(&p.title),
            short_title: SharedString::from(short_pack_title(&p.id, &p.title)),
            description: SharedString::from(&p.description),
            keep_enabled_in_game: p.keep_enabled_in_game,
        })
        .collect();
    window.set_feature_packs(ModelRc::new(VecModel::from(packs)));

    let q = state.service_search.trim().to_lowercase();
    let rows: Vec<ServiceRowItem> = all
        .iter()
        .filter(|s| {
            let dis = !s.is_core_locked && s.disable_in_gaming;
            if state.service_filter == "disable" && !dis {
                return false;
            }
            if state.service_filter == "normal" && dis {
                return false;
            }
            if q.is_empty() {
                return true;
            }
            s.name.to_lowercase().contains(&q)
                || s.display_name.to_lowercase().contains(&q)
                || s.summary_ru.to_lowercase().contains(&q)
        })
        .map(|s| ServiceRowItem {
            name: SharedString::from(&s.name),
            display_name: SharedString::from(&s.display_name),
            status_label: SharedString::from(service_status_label_ru(&s.status)),
            is_running: s.status == "Running",
            is_core_locked: s.is_core_locked,
            disable_in_gaming: !s.is_core_locked && s.disable_in_gaming,
            summary_ru: SharedString::from(&s.summary_ru),
            can_disable_hint: SharedString::from(&s.can_disable_hint),
            safety_level: SharedString::from(&s.safety_level),
        })
        .collect();

    window.set_service_total_count(total_count as i32);
    window.set_service_disabled_count(disabled_count as i32);
    window.set_service_normal_count(normal_count as i32);
    window.set_service_running_count(running_count as i32);
    window.set_disabled_services_count(if disabled_count > 0 {
        disabled_count as i32
    } else {
        lists.blacklist.len() as i32
    });
    window.set_service_items(ModelRc::new(VecModel::from(rows)));
}

fn apply_status_to_window(window: &MainWindow, status: &SystemStatus) {
    window.set_mode(SharedString::from(&status.mode));
    window.set_active_since(SharedString::from(
        status.active_since.as_deref().unwrap_or(""),
    ));
    window.set_cpu_name(SharedString::from(&status.hardware.cpu));
    window.set_gpu_name(SharedString::from(&status.hardware.gpu));
    window.set_ram_summary(SharedString::from(&status.hardware.ram));
    window.set_display_summary(SharedString::from(&status.hardware.display));
    window.set_dpc_latency(SharedString::from(&status.hardware.dpc_latency));
    window.set_mpo_status(SharedString::from(&status.hardware.mpo_status));
    let tr = status
        .hardware
        .timer_resolution
        .as_deref()
        .unwrap_or("1.000 мс (штатный)");
    window.set_timer_resolution(SharedString::from(tr));
    window.set_timer_locked(TIMER_LOCKED.load(Ordering::SeqCst) || tr.contains("зафиксировано"));
}

fn apply_tuning_to_window(window: &MainWindow, cfg: &TuningConfig) {
    window.set_auto_lock_timer_in_gaming(cfg.auto_lock_timer_in_gaming);
    window.set_auto_purge_ram_in_gaming(cfg.auto_purge_ram_in_gaming);
    window.set_auto_purge_ram_threshold_mb(cfg.auto_purge_ram_threshold_mb as i32);
}

fn apply_autostart_to_window(window: &MainWindow, st: &AutostartStatus) {
    window.set_autostart_enabled(st.enabled);
    window.set_autostart_start_in_tray(st.start_in_tray);
    window.set_autostart_path_mismatch(st.task_exists && !st.path_matches);
    window.set_autostart_warning(SharedString::from(st.warning.as_deref().unwrap_or("")));
}

pub fn run_native_app() {
    let start_in_tray = std::env::args()
        .skip(1)
        .any(|a| a.eq_ignore_ascii_case("--tray") || a.eq_ignore_ascii_case("--minimized"));
    START_IN_TRAY.store(start_in_tray, Ordering::SeqCst);

    #[cfg(target_os = "windows")]
    let _single_instance_guard = match backend::win_hw::acquire_single_instance_or_wake(!start_in_tray) {
        Some(h) => h,
        None => return,
    };

    let runtime_root = backend::get_workspace_root();
    let theme_prefs = ThemePreferences::load_from_runtime(&runtime_root);
    let initial_tuning = backend::load_tuning_from_disk(&runtime_root);
    let initial_mode = backend::read_current_mode_fast(&runtime_root);

    if initial_mode == "Gaming" && initial_tuning.auto_lock_timer_in_gaming {
        let _ = backend::timer::lock_timer_resolution_05ms();
    }

    let window = MainWindow::new().expect("Не удалось инициализировать нативное окно Slint");
    window.set_app_version(SharedString::from(APP_VERSION));
    apply_theme_to_window(&window, theme_prefs.theme);
    apply_tuning_to_window(&window, &initial_tuning);
    let (init_disabled_services, init_disabled_processes) =
        backend::compute_initial_disabled_counts(&runtime_root);
    window.set_disabled_services_count(init_disabled_services as i32);
    window.set_disabled_processes_count(init_disabled_processes as i32);

    if let Ok(st) = backend::read_system_status_sync() {
        apply_status_to_window(&window, &st);
    }

    let state = Arc::new(Mutex::new(UiAppState {
        runtime_root: runtime_root.clone(),
        theme_prefs,
        tuning: initial_tuning,
        processes_snap: None,
        services_lists: None,
        process_filter: "all".to_string(),
        process_search: String::new(),
        process_show_os_core: false,
        service_filter: "all".to_string(),
        service_search: String::new(),
        logs: Vec::new(),
    }));

    state.lock().unwrap().push_log(
        &window,
        "info",
        format!(
            "Нативный интерфейс Slint инициализирован (v{}, тема «{}», профиль AAA).",
            APP_VERSION,
            get_theme_by_id(theme_prefs.theme).name_ru
        ),
    );

    // Initialize native system tray on UI thread
    let (tray_tx, tray_rx) = mpsc::channel::<TrayCommand>();
    let tray_rx = Arc::new(Mutex::new(tray_rx));
    let initial_tray_snap = TrayStateSnapshot {
        mode: initial_mode.clone(),
        timer_locked: TIMER_LOCKED.load(Ordering::SeqCst),
        mode_action_busy: MODE_ACTION_BUSY.load(Ordering::SeqCst),
    };
    let tray_controller = Rc::new(RefCell::new(
        TrayController::new(&initial_tray_snap, tray_tx.clone(), None).ok(),
    ));

    let sync_tray = {
        let tray_controller = tray_controller.clone();
        let runtime_root = runtime_root.clone();
        move || {
            if let Some(ref ctrl) = *tray_controller.borrow() {
                let snap = TrayStateSnapshot {
                    mode: backend::read_current_mode_fast(&runtime_root),
                    timer_locked: TIMER_LOCKED.load(Ordering::SeqCst),
                    mode_action_busy: MODE_ACTION_BUSY.load(Ordering::SeqCst),
                };
                ctrl.sync_state(&snap);
            }
        }
    };

    // Intercept window close button -> hide to tray
    {
        let weak = window.as_weak();
        window.window().on_close_requested(move || {
            if ALLOW_APP_EXIT.load(Ordering::SeqCst) {
                slint::CloseRequestResponse::HideWindow
            } else {
                if let Some(w) = weak.upgrade() {
                    let _ = w.hide();
                }
                slint::CloseRequestResponse::KeepWindowShown
            }
        });
    }

    // Window header callbacks
    {
        let weak = window.as_weak();
        window.on_drag_window(move || {
            if let Some(w) = weak.upgrade() {
                start_native_window_drag(&w);
            }
        });
    }
    {
        let weak = window.as_weak();
        window.on_minimize_window(move || {
            if let Some(w) = weak.upgrade() {
                w.window().set_minimized(true);
            }
        });
    }
    {
        let weak = window.as_weak();
        window.on_toggle_maximize_window(move || {
            if let Some(w) = weak.upgrade() {
                let next = !w.get_is_maximized();
                w.window().set_maximized(next);
                w.set_is_maximized(next);
            }
        });
    }
    {
        let weak = window.as_weak();
        window.on_close_to_tray(move || {
            if let Some(w) = weak.upgrade() {
                let _ = w.hide();
            }
        });
    }

    // Theme Polarity Smart Toggle & 4x2 Grid Theme Selection
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_toggle_theme_polarity(move || {
            if let Some(w) = weak.upgrade() {
                let mut st = state.lock().unwrap();
                let next_id = st.theme_prefs.toggle_polarity();
                let _ = st.theme_prefs.save_to_runtime(&st.runtime_root);
                apply_theme_to_window(&w, next_id);
                let name = get_theme_by_id(next_id).name_ru;
                st.push_log(&w, "info", format!("Переключена тема оформления: «{}».", name));
            }
        });
    }
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_select_theme(move |raw_id| {
            if let Some(w) = weak.upgrade() {
                if let Some(id) = ThemeId::parse(raw_id.as_str()) {
                    let mut st = state.lock().unwrap();
                    st.theme_prefs.select_theme(id);
                    let _ = st.theme_prefs.save_to_runtime(&st.runtime_root);
                    apply_theme_to_window(&w, id);
                    let name = get_theme_by_id(id).name_ru;
                    st.push_log(&w, "info", format!("Выбрана тема оформления: «{}».", name));
                }
            }
        });
    }

    // Lazy load processes & services when switching tabs
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_tab_selected(move |tab_idx| {
            if let Some(w) = weak.upgrade() {
                let mut st = state.lock().unwrap();
                if tab_idx == 1 && st.processes_snap.is_none() {
                    if let Ok(snap) = backend::get_running_processes_sync() {
                        st.processes_snap = Some(snap);
                        refresh_processes_model(&mut st, &w);
                    }
                } else if tab_idx == 2 && st.services_lists.is_none() {
                    if let Ok(lists) = backend::read_services_lists_sync() {
                        st.services_lists = Some(lists);
                        refresh_services_model(&mut st, &w);
                    }
                } else if tab_idx == 3 {
                    drop(st);
                    let weak_bg = weak.clone();
                    std::thread::spawn(move || {
                        if let Ok(auto_st) = backend::get_autostart_status_sync() {
                            let _ = slint::invoke_from_event_loop(move || {
                                if let Some(w) = weak_bg.upgrade() {
                                    apply_autostart_to_window(&w, &auto_st);
                                }
                            });
                        }
                    });
                }
            }
        });
    }

    // Mode Toggle (Enable / Restore)
    {
        let weak = window.as_weak();
        let state = state.clone();
        let sync_tray = sync_tray.clone();
        window.on_toggle_mode(move || {
            let Some(w) = weak.upgrade() else { return };
            if w.get_is_busy() {
                return;
            }
            let cur_mode = w.get_mode().to_string();
            let action = if cur_mode == "Gaming" || cur_mode == "Armed" {
                "Restore"
            } else {
                "Enable"
            };
            w.set_is_busy(true);
            state.lock().unwrap().push_log(
                &w,
                "info",
                if action == "Enable" {
                    "Включение игрового режима AAA…"
                } else {
                    "Возврат штатного режима Windows…"
                },
            );
            sync_tray();

            let weak_bg = weak.clone();
            let state_bg = state.clone();
            std::thread::spawn(move || {
                let res = backend::run_execute_mode_action_sync(action);
                let status = backend::read_system_status_sync().ok();
                let _ = slint::invoke_from_event_loop(move || {
                    if let Some(w) = weak_bg.upgrade() {
                        w.set_is_busy(false);
                        if let Some(st_now) = status {
                            apply_status_to_window(&w, &st_now);
                        }
                        let mut st = state_bg.lock().unwrap();
                        match res {
                            Ok(r) if r.success => st.push_log(&w, "success", r.message),
                            Ok(r) => st.push_log(&w, "error", r.message),
                            Err(e) => st.push_log(&w, "error", e),
                        }
                    }
                });
            });
        });
    }

    // Finish Pending Restore
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_finish_pending_restore(move || {
            let Some(w) = weak.upgrade() else { return };
            if w.get_is_busy() {
                return;
            }
            w.set_is_busy(true);
            let weak_bg = weak.clone();
            let state_bg = state.clone();
            std::thread::spawn(move || {
                let res = backend::run_finish_pending_restore_sync();
                let status = backend::read_system_status_sync().ok();
                let _ = slint::invoke_from_event_loop(move || {
                    if let Some(w) = weak_bg.upgrade() {
                        w.set_is_busy(false);
                        if let Some(st_now) = status {
                            apply_status_to_window(&w, &st_now);
                        }
                        let mut st = state_bg.lock().unwrap();
                        match res {
                            Ok(r) if r.success => st.push_log(&w, "success", r.message),
                            Ok(r) => st.push_log(&w, "error", r.message),
                            Err(e) => st.push_log(&w, "error", e),
                        }
                    }
                });
            });
        });
    }

    // Timer Lock / Unlock
    {
        let weak = window.as_weak();
        let state = state.clone();
        let sync_tray = sync_tray.clone();
        window.on_toggle_timer_lock(move || {
            if let Some(w) = weak.upgrade() {
                let mut st = state.lock().unwrap();
                match backend::timer::lock_timer_resolution_05ms() {
                    Ok((cur_ms, _)) => {
                        w.set_timer_locked(true);
                        w.set_timer_resolution(SharedString::from(format!(
                            "{:.3} мс (зафиксировано)",
                            cur_ms
                        )));
                        st.push_log(
                            &w,
                            "success",
                            format!("Разрешение системного таймера зафиксировано: {:.3} мс.", cur_ms),
                        );
                    }
                    Err(e) => st.push_log(&w, "error", e),
                }
                sync_tray();
            }
        });
    }
    {
        let weak = window.as_weak();
        let state = state.clone();
        let sync_tray = sync_tray.clone();
        window.on_unlock_timer(move || {
            if let Some(w) = weak.upgrade() {
                let mut st = state.lock().unwrap();
                match backend::timer::unlock_timer_resolution() {
                    Ok(cur_ms) => {
                        w.set_timer_locked(false);
                        w.set_timer_resolution(SharedString::from(format!("{:.3} мс", cur_ms)));
                        st.push_log(
                            &w,
                            "info",
                            format!("Фиксация системного таймера снята ({:.3} мс).", cur_ms),
                        );
                    }
                    Err(e) => st.push_log(&w, "error", e),
                }
                sync_tray();
            }
        });
    }

    // Open Offline 3D Architecture Teardown
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_open_teardown(move || {
            if let Some(w) = weak.upgrade() {
                let mut st = state.lock().unwrap();
                let root = st.runtime_root.clone();
                match backend::open_teardown_page_sync(&root) {
                    Ok(path) => st.push_log(
                        &w,
                        "info",
                        format!("Открыта 3D-разборка архитектуры: {}", path.display()),
                    ),
                    Err(e) => st.push_log(&w, "error", e),
                }
            }
        });
    }

    // Check Updates & Open Releases Page
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_check_updates(move || {
            let weak_bg = weak.clone();
            let state_bg = state.clone();
            std::thread::spawn(move || {
                let res = backend::check_for_updates_sync();
                let _ = slint::invoke_from_event_loop(move || {
                    if let Some(w) = weak_bg.upgrade() {
                        let mut st = state_bg.lock().unwrap();
                        match res {
                            Ok(info) => {
                                w.set_latest_version(SharedString::from(&info.latest_version));
                                w.set_has_update(info.has_update);
                                let msg = if info.has_update {
                                    format!(
                                        "Доступно обновление v{} (текущая v{}).",
                                        info.latest_version, info.current_version
                                    )
                                } else {
                                    format!(
                                        "Установлена актуальная версия v{} (последний релиз v{}).",
                                        info.current_version, info.latest_version
                                    )
                                };
                                w.set_update_status_text(SharedString::from(&msg));
                                st.push_log(&w, "success", msg);
                            }
                            Err(e) => {
                                w.set_update_status_text(SharedString::from(&e));
                                st.push_log(&w, "warn", e);
                            }
                        }
                    }
                });
            });
        });
    }
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_open_releases_page(move || {
            let url = format!("https://github.com/{}/releases", backend::GITHUB_REPO);
            if let Err(e) = backend::open_release_url_sync(&url) {
                if let Some(w) = weak.upgrade() {
                    state.lock().unwrap().push_log(&w, "error", e);
                }
            }
        });
    }

    // Processes Callbacks
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_process_filter_changed(move |mode| {
            if let Some(w) = weak.upgrade() {
                w.set_process_filter_mode(mode.clone());
                let mut st = state.lock().unwrap();
                st.process_filter = mode.to_string();
                refresh_processes_model(&mut st, &w);
            }
        });
    }
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_process_search_changed(move |q| {
            if let Some(w) = weak.upgrade() {
                let mut st = state.lock().unwrap();
                st.process_search = q.to_string();
                refresh_processes_model(&mut st, &w);
            }
        });
    }
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_process_toggle_os_core(move |show| {
            if let Some(w) = weak.upgrade() {
                let mut st = state.lock().unwrap();
                st.process_show_os_core = show;
                refresh_processes_model(&mut st, &w);
            }
        });
    }
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_refresh_processes(move || {
            if let Some(w) = weak.upgrade() {
                let mut st = state.lock().unwrap();
                if let Ok(snap) = backend::get_running_processes_sync() {
                    st.processes_snap = Some(snap);
                    refresh_processes_model(&mut st, &w);
                }
            }
        });
    }
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_set_process_mode(move |name, disable| {
            if let Some(w) = weak.upgrade() {
                let mut st = state.lock().unwrap();
                let root = st.runtime_root.clone();
                match backend::set_process_gaming_mode_in_root(&root, name.as_str(), disable) {
                    Ok(_) => {
                        if let Ok(snap) = backend::get_running_processes_sync() {
                            st.processes_snap = Some(snap);
                            refresh_processes_model(&mut st, &w);
                        }
                        st.push_log(
                            &w,
                            "success",
                            format!(
                                "Процесс {}: {}.",
                                name,
                                if disable {
                                    "Выкл. в Gaming Mode"
                                } else {
                                    "Без утилки"
                                }
                            ),
                        );
                    }
                    Err(e) => st.push_log(&w, "error", e),
                }
            }
        });
    }
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_add_process(move |raw_name| {
            if let Some(w) = weak.upgrade() {
                let mut st = state.lock().unwrap();
                let root = st.runtime_root.clone();
                let clean = backend::strip_exe_suffix(raw_name.as_str()).trim().to_string();
                if clean.is_empty() {
                    return;
                }
                match backend::set_process_gaming_mode_in_root(&root, &clean, true) {
                    Ok(_) => {
                        w.set_new_process_name(SharedString::default());
                        if let Ok(snap) = backend::get_running_processes_sync() {
                            st.processes_snap = Some(snap);
                            refresh_processes_model(&mut st, &w);
                        }
                        st.push_log(
                            &w,
                            "success",
                            format!("Процесс '{}' добавлен для выключения в Gaming Mode.", clean),
                        );
                    }
                    Err(e) => st.push_log(&w, "error", e),
                }
            }
        });
    }

    // Services Callbacks
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_service_filter_changed(move |mode| {
            if let Some(w) = weak.upgrade() {
                w.set_service_filter_mode(mode.clone());
                let mut st = state.lock().unwrap();
                st.service_filter = mode.to_string();
                refresh_services_model(&mut st, &w);
            }
        });
    }
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_service_search_changed(move |q| {
            if let Some(w) = weak.upgrade() {
                let mut st = state.lock().unwrap();
                st.service_search = q.to_string();
                refresh_services_model(&mut st, &w);
            }
        });
    }
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_refresh_services(move || {
            if let Some(w) = weak.upgrade() {
                let mut st = state.lock().unwrap();
                if let Ok(lists) = backend::read_services_lists_sync() {
                    st.services_lists = Some(lists);
                    refresh_services_model(&mut st, &w);
                }
            }
        });
    }
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_toggle_feature_pack(move |pack_id, keep| {
            if let Some(w) = weak.upgrade() {
                let mut st = state.lock().unwrap();
                let root = st.runtime_root.clone();
                match backend::apply_service_feature_pack_in_root(
                    &root,
                    pack_id.as_str(),
                    keep,
                    cfg!(target_os = "windows"),
                ) {
                    Ok(lists) => {
                        st.services_lists = Some(lists);
                        refresh_services_model(&mut st, &w);
                        st.push_log(
                            &w,
                            "success",
                            format!(
                                "Пресет служб '{}': {}.",
                                pack_id,
                                if keep {
                                    "Без утилки"
                                } else {
                                    "Выкл. в Gaming Mode"
                                }
                            ),
                        );
                    }
                    Err(e) => st.push_log(&w, "error", e),
                }
            }
        });
    }
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_set_service_mode(move |name, disable| {
            if let Some(w) = weak.upgrade() {
                let mut st = state.lock().unwrap();
                let root = st.runtime_root.clone();
                match backend::set_service_gaming_mode_in_root(
                    &root,
                    name.as_str(),
                    disable,
                    cfg!(target_os = "windows"),
                ) {
                    Ok(lists) => {
                        st.services_lists = Some(lists);
                        refresh_services_model(&mut st, &w);
                        st.push_log(
                            &w,
                            "success",
                            format!(
                                "Служба {}: {}.",
                                name,
                                if disable {
                                    "Выкл. в Gaming Mode"
                                } else {
                                    "Без утилки"
                                }
                            ),
                        );
                    }
                    Err(e) => st.push_log(&w, "error", e),
                }
            }
        });
    }

    // Settings Callbacks (Autostart + AAA Automation)
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_toggle_autostart(move |enabled, start_in_tray| {
            if let Some(w) = weak.upgrade() {
                let mut st = state.lock().unwrap();
                match backend::set_autostart_sync(enabled, start_in_tray) {
                    Ok(auto_st) => {
                        apply_autostart_to_window(&w, &auto_st);
                        st.push_log(
                            &w,
                            "success",
                            if auto_st.enabled {
                                "Повышенный автозапуск вместе с Windows включён."
                            } else {
                                "Автозапуск вместе с Windows отключён."
                            },
                        );
                    }
                    Err(e) => {
                        w.set_autostart_warning(SharedString::from(&e));
                        st.push_log(&w, "error", e);
                    }
                }
            }
        });
    }
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_toggle_auto_lock_timer(move || {
            if let Some(w) = weak.upgrade() {
                let mut st = state.lock().unwrap();
                st.tuning.auto_lock_timer_in_gaming = !st.tuning.auto_lock_timer_in_gaming;
                if let Ok(saved) = backend::write_tuning_config_sync(st.tuning.clone()) {
                    st.tuning = saved;
                    apply_tuning_to_window(&w, &st.tuning);
                    let enabled = st.tuning.auto_lock_timer_in_gaming;
                    st.push_log(
                        &w,
                        "info",
                        format!(
                            "Автофиксация таймера 0.500 мс: {}.",
                            if enabled { "Вкл" } else { "Выкл" }
                        ),
                    );
                }
            }
        });
    }
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_toggle_auto_purge_ram(move || {
            if let Some(w) = weak.upgrade() {
                let mut st = state.lock().unwrap();
                st.tuning.auto_purge_ram_in_gaming = !st.tuning.auto_purge_ram_in_gaming;
                if let Ok(saved) = backend::write_tuning_config_sync(st.tuning.clone()) {
                    st.tuning = saved;
                    apply_tuning_to_window(&w, &st.tuning);
                    let enabled = st.tuning.auto_purge_ram_in_gaming;
                    st.push_log(
                        &w,
                        "info",
                        format!(
                            "Автоочистка Standby-кэша ОЗУ: {}.",
                            if enabled { "Вкл" } else { "Выкл" }
                        ),
                    );
                }
            }
        });
    }
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_set_ram_threshold(move |mb| {
            if let Some(w) = weak.upgrade() {
                let mut st = state.lock().unwrap();
                st.tuning.auto_purge_ram_threshold_mb = mb as u32;
                if let Ok(saved) = backend::write_tuning_config_sync(st.tuning.clone()) {
                    st.tuning = saved;
                    apply_tuning_to_window(&w, &st.tuning);
                    let threshold = st.tuning.auto_purge_ram_threshold_mb;
                    st.push_log(
                        &w,
                        "info",
                        format!("Порог автоочистки ОЗУ установлен: {} МБ.", threshold),
                    );
                }
            }
        });
    }

    // Maintenance & Confirm Dialog Actions
    let run_repair_action = {
        let weak = window.as_weak();
        let state = state.clone();
        move |kind: String| {
            let Some(w) = weak.upgrade() else { return };
            if !w.get_running_repair().is_empty() {
                return;
            }
            w.set_running_repair(SharedString::from(&kind));
            let weak_bg = weak.clone();
            let state_bg = state.clone();
            std::thread::spawn(move || {
                let res = backend::execute_emergency_repair_sync(&kind);
                let _ = slint::invoke_from_event_loop(move || {
                    if let Some(w) = weak_bg.upgrade() {
                        w.set_running_repair(SharedString::default());
                        let mut st = state_bg.lock().unwrap();
                        match res {
                            Ok(r) => {
                                w.set_repair_status_text(SharedString::from(&r.message));
                                w.set_repair_status_is_error(!r.success);
                                st.push_log(
                                    &w,
                                    if r.success { "success" } else { "error" },
                                    r.message,
                                );
                            }
                            Err(e) => {
                                w.set_repair_status_text(SharedString::from(&e));
                                w.set_repair_status_is_error(true);
                                st.push_log(&w, "error", e);
                            }
                        }
                    }
                });
            });
        }
    };

    {
        let run_repair_action = run_repair_action.clone();
        window.on_run_repair(move |kind| {
            run_repair_action(kind.to_string());
        });
    }
    {
        let weak = window.as_weak();
        let state = state.clone();
        let run_repair_action = run_repair_action.clone();
        window.on_confirm_action(move |action| {
            let act = action.to_string();
            if act == "reboot" {
                if let Some(w) = weak.upgrade() {
                    let mut st = state.lock().unwrap();
                    match backend::reboot_pc_sync() {
                        Ok(r) => st.push_log(&w, "warn", r.message),
                        Err(e) => st.push_log(&w, "error", e),
                    }
                }
            } else if !act.is_empty() {
                run_repair_action(act);
            }
        });
    }
    {
        let weak = window.as_weak();
        let state = state.clone();
        window.on_clear_logs(move || {
            if let Some(w) = weak.upgrade() {
                let mut st = state.lock().unwrap();
                st.logs.clear();
                w.set_log_count(0);
                w.set_logs(ModelRc::new(VecModel::from(Vec::<LogRowItem>::new())));
            }
        });
    }

    // Periodic timer on UI thread to process tray commands and refresh status
    let poll_timer = slint::Timer::default();
    {
        let weak = window.as_weak();
        let state = state.clone();
        let tray_controller = tray_controller.clone();
        let sync_tray = sync_tray.clone();
        let tray_rx = tray_rx.clone();
        poll_timer.start(
            slint::TimerMode::Repeated,
            std::time::Duration::from_millis(250),
            move || {
                sync_tray();
                let cmds: Vec<TrayCommand> = tray_rx
                    .lock()
                    .map(|rx| rx.try_iter().collect())
                    .unwrap_or_default();

                for cmd in cmds {
                    match cmd {
                        TrayCommand::OpenWindow => {
                            if let Some(w) = weak.upgrade() {
                                let _ = w.show();
                                w.window().set_minimized(false);
                                let is_dark = w.global::<ThemeTokens>().get_is_dark();
                                sync_window_dwm_theme(&w, is_dark);
                            }
                        }
                        TrayCommand::ToggleMode => {
                            if let Some(w) = weak.upgrade() {
                                if w.get_mode() == "RestoringPending" {
                                    w.invoke_finish_pending_restore();
                                } else {
                                    w.invoke_toggle_mode();
                                }
                            }
                        }
                        TrayCommand::CleanRam => {
                            if let Ok(res) = backend::clean_memory_native_sync() {
                                if let Some(ref ctrl) = *tray_controller.borrow() {
                                    ctrl.set_tooltip(&format!(
                                        "Ultra Gaming Mode — {}",
                                        res.message
                                    ));
                                }
                                if let Some(w) = weak.upgrade() {
                                    state.lock().unwrap().push_log(&w, "success", res.message);
                                }
                            }
                        }
                        TrayCommand::ToggleTimer => {
                            if TIMER_LOCKED.load(Ordering::SeqCst) {
                                let _ = backend::timer::unlock_timer_resolution();
                            } else {
                                let _ = backend::timer::lock_timer_resolution_05ms();
                            }
                            if let Some(w) = weak.upgrade() {
                                if let Ok(st) = backend::read_system_status_sync() {
                                    apply_status_to_window(&w, &st);
                                }
                            }
                            sync_tray();
                        }
                        TrayCommand::RebootPc => {
                            std::thread::spawn(|| {
                                #[cfg(target_os = "windows")]
                                if backend::win_hw::confirm_reboot_dialog_win32() {
                                    let _ = backend::reboot_pc_sync();
                                }
                            });
                        }
                        TrayCommand::ExitApp => {
                            ALLOW_APP_EXIT.store(true, Ordering::SeqCst);
                            let _ = slint::quit_event_loop();
                            return;
                        }
                    }
                }
            },
        );
    }

    // Background watcher thread: Single-instance wake event, active_state.json changes, 60s Standby RAM auto-purge
    {
        let weak_watcher = window.as_weak();
        let tray_tx_watcher = tray_tx.clone();
        let runtime_root_watcher = runtime_root.clone();
        std::thread::spawn(move || {
            #[cfg(target_os = "windows")]
            let wake_event = backend::win_hw::create_wake_event();
            #[cfg(not(target_os = "windows"))]
            let wake_event: isize = 0;

            let active_state_path = runtime_root_watcher.join("Backups").join("active_state.json");
            let mut last_sig: Option<(Option<std::time::SystemTime>, u64)> =
                std::fs::metadata(&active_state_path)
                    .ok()
                    .map(|m| (m.modified().ok(), m.len()));
            let mut last_ram_check = std::time::Instant::now();
            let mut last_auto_ram_purge: Option<std::time::Instant> = None;

            if START_IN_TRAY.load(Ordering::SeqCst)
                && backend::read_current_mode_fast(&runtime_root_watcher) == "RestoringPending"
                && PENDING_RESTORE_TRIGGERED
                    .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
                    .is_ok()
            {
                let _ = backend::run_finish_pending_restore_sync();
            }

            loop {
                #[cfg(target_os = "windows")]
                let woken = backend::win_hw::wait_wake_event_ms(wake_event, 2000);
                #[cfg(not(target_os = "windows"))]
                let woken = {
                    let _ = wake_event;
                    std::thread::sleep(std::time::Duration::from_secs(2));
                    false
                };

                if ALLOW_APP_EXIT.load(Ordering::SeqCst) {
                    break;
                }

                if woken {
                    let _ = tray_tx_watcher.send(TrayCommand::OpenWindow);
                }

                let sig = std::fs::metadata(&active_state_path)
                    .ok()
                    .map(|m| (m.modified().ok(), m.len()));
                if sig != last_sig {
                    last_sig = sig;
                    backend::invalidate_active_state_cache();
                    let weak_ui = weak_watcher.clone();
                    let _ = slint::invoke_from_event_loop(move || {
                        if let Some(w) = weak_ui.upgrade() {
                            if let Ok(st) = backend::read_system_status_sync() {
                                apply_status_to_window(&w, &st);
                            }
                        }
                    });
                }

                if last_ram_check.elapsed()
                    >= std::time::Duration::from_secs(AUTO_PURGE_RAM_POLL_SECS)
                {
                    last_ram_check = std::time::Instant::now();
                    let mode_now = backend::read_current_mode_fast(&runtime_root_watcher);
                    let tuning_now = backend::load_tuning_from_disk(&runtime_root_watcher);
                    let elapsed_since_purge = last_auto_ram_purge.map(|t| t.elapsed().as_secs());
                    #[cfg(target_os = "windows")]
                    if let Some(avail_mb) = backend::win_hw::query_available_ram_mb() {
                        if backend::should_auto_purge_ram(
                            &mode_now,
                            &tuning_now,
                            avail_mb,
                            elapsed_since_purge,
                        ) {
                            if backend::clean_memory_native_sync().is_ok() {
                                last_auto_ram_purge = Some(std::time::Instant::now());
                            }
                        }
                    }
                    #[cfg(not(target_os = "windows"))]
                    {
                        let _ = (
                            mode_now,
                            tuning_now,
                            elapsed_since_purge,
                            &mut last_auto_ram_purge,
                        );
                    }
                }
            }
        });
    }

    if !start_in_tray {
        let _ = window.show();
        sync_window_dwm_theme(&window, get_theme_by_id(theme_prefs.theme).is_dark);
    }

    let _ = slint::run_event_loop_until_quit();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_all_8_themes_map_to_slint_colors_and_dwm_polarity() {
        for t in all_themes() {
            let dwm_flag = theme_polarity_to_dwm_flag(t);
            match t.id {
                ThemeId::Dark
                | ThemeId::OledObsidian
                | ThemeId::EmeraldOps
                | ThemeId::GraphiteAmber
                | ThemeId::MidnightViolet => {
                    assert!(dwm_flag, "Dark theme {} must map to DWM true", t.id_str);
                }
                ThemeId::Light | ThemeId::DaylightWarm | ThemeId::FrostSlate => {
                    assert!(!dwm_flag, "Light theme {} must map to DWM false", t.id_str);
                }
            }
            let c = rgba_to_slint_color(t.bg_app);
            assert_eq!(c.red(), t.bg_app.r);
            assert_eq!(c.green(), t.bg_app.g);
            assert_eq!(c.blue(), t.bg_app.b);

            let cards = build_theme_card_items(t.id);
            assert_eq!(cards.len(), 8);
            assert_eq!(cards.iter().filter(|c| c.is_active).count(), 1);
            assert!(cards.iter().any(|c| c.id.as_str() == t.id_str && c.is_active));
        }
    }
}
