use std::cell::{Cell, RefCell};
use std::sync::{mpsc, Arc, Mutex, Once, OnceLock};

use muda::{CheckMenuItem, IsMenuItem, Menu, MenuEvent, MenuItem, PredefinedMenuItem};
use tray_icon::{Icon, MouseButton, MouseButtonState, TrayIcon, TrayIconBuilder, TrayIconEvent};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TrayCommand {
    OpenWindow,
    ToggleMode,
    CleanRam,
    ToggleTimer,
    RebootPc,
    ExitApp,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TrayStateSnapshot {
    pub mode: String,
    pub timer_locked: bool,
    pub mode_action_busy: bool,
}

impl Default for TrayStateSnapshot {
    fn default() -> Self {
        Self {
            mode: "Normal".to_string(),
            timer_locked: false,
            mode_action_busy: false,
        }
    }
}

pub const TRAY_MENU_ITEM_IDS: &[&str] = &[
    "tray-status",
    "tray-open",
    "tray-toggle",
    "tray-clean-ram",
    "tray-timer",
    "tray-reboot",
    "tray-exit",
];

pub fn tray_menu_item_ids() -> &'static [&'static str] {
    TRAY_MENU_ITEM_IDS
}

pub fn build_tray_icon_rgba(mode: &str) -> (Vec<u8>, u32, u32) {
    const SIZE: usize = 32;
    let mut rgba = vec![0u8; SIZE * SIZE * 4];
    let (fill_r, fill_g, fill_b, rim_r, rim_g, rim_b) = match mode {
        "Gaming" => (34u8, 197u8, 94u8, 21u8, 128u8, 61u8),
        "Armed" | "RestoringPending" => (245u8, 158u8, 11u8, 180u8, 83u8, 9u8),
        _ => (239u8, 68u8, 68u8, 185u8, 28u8, 28u8),
    };

    let center = 15.5_f32;
    let outer_r = 14.5_f32;
    let rim_inner_r = 12.2_f32;

    for y in 0..SIZE {
        for x in 0..SIZE {
            let dx = x as f32 - center;
            let dy = y as f32 - center;
            let dist = (dx * dx + dy * dy).sqrt();
            let idx = (y * SIZE + x) * 4;
            if dist <= outer_r {
                let alpha = if dist > outer_r - 1.1 {
                    ((outer_r - dist) / 1.1).clamp(0.0, 1.0)
                } else {
                    1.0
                };
                let (r, g, b) = if dist >= rim_inner_r {
                    (rim_r, rim_g, rim_b)
                } else {
                    (fill_r, fill_g, fill_b)
                };
                rgba[idx] = r;
                rgba[idx + 1] = g;
                rgba[idx + 2] = b;
                rgba[idx + 3] = (alpha * 255.0).round() as u8;
            }
        }
    }

    (rgba, SIZE as u32, SIZE as u32)
}

pub fn mode_to_tray_meta(mode: &str) -> (&'static str, &'static str, &'static str) {
    match mode {
        "Gaming" => (
            "Статус: Игровой режим активен",
            "Ultra Gaming Mode — Игровой режим активен (зелёный)",
            "Вернуть штатный режим",
        ),
        "Armed" => (
            "Статус: Ожидает перезагрузки",
            "Ultra Gaming Mode — Ожидает перезагрузки (оранжевый)",
            "Вернуть штатный режим",
        ),
        "RestoringPending" => (
            "Статус: Требуется завершить восстановление",
            "Ultra Gaming Mode — Незавершённое восстановление профиля (оранжевый)",
            "Завершить восстановление",
        ),
        _ => (
            "Статус: Штатный режим (неактивен)",
            "Ultra Gaming Mode — Штатный режим (красный)",
            "Включить игровой режим",
        ),
    }
}

pub fn map_menu_id_to_command(id: &str) -> Option<TrayCommand> {
    match id {
        "tray-open" => Some(TrayCommand::OpenWindow),
        "tray-toggle" => Some(TrayCommand::ToggleMode),
        "tray-clean-ram" => Some(TrayCommand::CleanRam),
        "tray-timer" => Some(TrayCommand::ToggleTimer),
        "tray-reboot" => Some(TrayCommand::RebootPc),
        "tray-exit" => Some(TrayCommand::ExitApp),
        _ => None,
    }
}

type DispatchTarget = (mpsc::Sender<TrayCommand>, Option<Arc<dyn Fn() + Send + Sync>>);

static TRAY_DISPATCH_TARGET: OnceLock<Mutex<Option<DispatchTarget>>> = OnceLock::new();
static TRAY_HANDLERS_INIT: Once = Once::new();

fn dispatch_tray_command(cmd: TrayCommand) {
    let slot = TRAY_DISPATCH_TARGET.get_or_init(|| Mutex::new(None));
    if let Ok(guard) = slot.lock() {
        if let Some((tx, wake_ui)) = guard.as_ref() {
            let _ = tx.send(cmd);
            if let Some(wake) = wake_ui {
                wake();
            }
        }
    }
}

fn install_global_tray_handlers() {
    TRAY_HANDLERS_INIT.call_once(|| {
        TrayIconEvent::set_event_handler(Some(|event: TrayIconEvent| {
            let is_left_click_up = matches!(
                event,
                TrayIconEvent::Click {
                    button: MouseButton::Left,
                    button_state: MouseButtonState::Up,
                    ..
                }
            );
            if is_left_click_up {
                dispatch_tray_command(TrayCommand::OpenWindow);
            }
        }));

        MenuEvent::set_event_handler(Some(|event: MenuEvent| {
            if let Some(cmd) = map_menu_id_to_command(event.id().as_ref()) {
                dispatch_tray_command(cmd);
            }
        }));
    });
}

/// Native system tray controller owned strictly by the UI thread.
pub struct TrayController {
    tray: TrayIcon,
    status_item: MenuItem,
    toggle_item: MenuItem,
    timer_item: CheckMenuItem,
    last_mode: RefCell<String>,
    last_timer_locked: Cell<bool>,
    last_busy: Cell<bool>,
    transient_tooltip_until: Cell<Option<std::time::Instant>>,
}

impl TrayController {
    pub fn new(
        initial: &TrayStateSnapshot,
        cmd_tx: mpsc::Sender<TrayCommand>,
        wake_ui: Option<Arc<dyn Fn() + Send + Sync>>,
    ) -> Result<Self, String> {
        let slot = TRAY_DISPATCH_TARGET.get_or_init(|| Mutex::new(None));
        if let Ok(mut guard) = slot.lock() {
            *guard = Some((cmd_tx, wake_ui));
        }
        install_global_tray_handlers();

        let (status_text, tooltip, toggle_text) = mode_to_tray_meta(&initial.mode);
        let safe_initial_tooltip = truncate_tray_tooltip(tooltip);
        let (rgba, w, h) = build_tray_icon_rgba(&initial.mode);
        let icon = Icon::from_rgba(rgba, w, h)
            .map_err(|e| format!("Не удалось создать иконку трея: {}", e))?;

        let status_item = MenuItem::with_id("tray-status", status_text, false, None);
        let sep1 = PredefinedMenuItem::separator();
        let open_item = MenuItem::with_id("tray-open", "Открыть панель управления", true, None);
        let sep2 = PredefinedMenuItem::separator();
        let toggle_item =
            MenuItem::with_id("tray-toggle", toggle_text, !initial.mode_action_busy, None);
        let clean_ram_item =
            MenuItem::with_id("tray-clean-ram", "Очистить кэш ОЗУ (Standby List)", true, None);
        let timer_item = CheckMenuItem::with_id(
            "tray-timer",
            "Таймер 0.500 мс",
            true,
            initial.timer_locked,
            None,
        );
        let reboot_item = MenuItem::with_id("tray-reboot", "Перезагрузить ПК...", true, None);
        let sep3 = PredefinedMenuItem::separator();
        let exit_item = MenuItem::with_id("tray-exit", "Выход (закрыть из трея)", true, None);

        let items: [&dyn IsMenuItem; 10] = [
            &status_item,
            &sep1,
            &open_item,
            &sep2,
            &toggle_item,
            &clean_ram_item,
            &timer_item,
            &reboot_item,
            &sep3,
            &exit_item,
        ];
        let menu = Menu::with_items(&items)
            .map_err(|e| format!("Не удалось построить меню трея: {}", e))?;

        let tray = TrayIconBuilder::new()
            .with_id("ugm-tray")
            .with_icon(icon)
            .with_tooltip(&safe_initial_tooltip)
            .with_menu(Box::new(menu))
            .with_menu_on_left_click(false)
            .build()
            .map_err(|e| format!("Не удалось создать иконку в системном трее: {}", e))?;

        Ok(Self {
            tray,
            status_item,
            toggle_item,
            timer_item,
            last_mode: RefCell::new(initial.mode.clone()),
            last_timer_locked: Cell::new(initial.timer_locked),
            last_busy: Cell::new(initial.mode_action_busy),
            transient_tooltip_until: Cell::new(None),
        })
    }

    pub fn sync_state(&self, state: &TrayStateSnapshot) {
        let mut transient_expired = false;
        if let Some(until) = self.transient_tooltip_until.get() {
            if std::time::Instant::now() >= until {
                self.transient_tooltip_until.set(None);
                transient_expired = true;
            }
        }

        let mode_changed = {
            let mut prev = self.last_mode.borrow_mut();
            if *prev != state.mode {
                *prev = state.mode.clone();
                true
            } else {
                false
            }
        };

        if mode_changed {
            self.transient_tooltip_until.set(None);
            let (status_text, tooltip, toggle_text) = mode_to_tray_meta(&state.mode);
            self.status_item.set_text(status_text);
            self.toggle_item.set_text(toggle_text);
            let (rgba, w, h) = build_tray_icon_rgba(&state.mode);
            if let Ok(icon) = Icon::from_rgba(rgba, w, h) {
                let _ = self.tray.set_icon(Some(icon));
            }
            self.set_tooltip(tooltip);
        } else if transient_expired {
            let (_, tooltip, _) = mode_to_tray_meta(&state.mode);
            self.set_tooltip(tooltip);
        }

        if self.last_timer_locked.get() != state.timer_locked {
            self.last_timer_locked.set(state.timer_locked);
            self.timer_item.set_checked(state.timer_locked);
        }

        if self.last_busy.get() != state.mode_action_busy {
            self.last_busy.set(state.mode_action_busy);
            self.toggle_item.set_enabled(!state.mode_action_busy);
        }
    }

    pub fn set_tooltip(&self, tooltip: &str) {
        let safe = truncate_tray_tooltip(tooltip);
        let _ = self.tray.set_tooltip(Some(&safe));
    }

    pub fn set_action_tooltip(&self, mode: &str, detail: &str) {
        self.transient_tooltip_until
            .set(Some(std::time::Instant::now() + std::time::Duration::from_secs(6)));
        let (_, base_tooltip, _) = mode_to_tray_meta(mode);
        let combined = format!("{} · {}", base_tooltip, detail.trim());
        self.set_tooltip(&combined);
    }

    pub fn set_toggle_enabled(&self, enabled: bool) {
        self.last_busy.set(!enabled);
        self.toggle_item.set_enabled(enabled);
    }
}

pub fn truncate_tray_tooltip(raw: &str) -> String {
    const MAX_UTF16_UNITS: usize = 120;
    let single_line: String = raw
        .chars()
        .map(|c| if c == '\r' || c == '\n' { ' ' } else { c })
        .collect();
    if single_line.encode_utf16().count() <= MAX_UTF16_UNITS {
        return single_line;
    }
    let mut out = String::new();
    let mut units = 0usize;
    for ch in single_line.chars() {
        let len = ch.len_utf16();
        if units + len + 1 > MAX_UTF16_UNITS {
            out.push('…');
            break;
        }
        out.push(ch);
        units += len;
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tray_icon_pixel_colors_for_all_three_modes() {
        let center_idx = (15 * 32 + 15) * 4;

        let (red_rgba, rw, rh) = build_tray_icon_rgba("Normal");
        assert_eq!((rw, rh), (32, 32));
        assert_eq!(red_rgba[3], 0, "Corner must be transparent");
        assert_eq!(&red_rgba[center_idx..center_idx + 4], &[239, 68, 68, 255]);

        let (orange_rgba, _, _) = build_tray_icon_rgba("Armed");
        assert_eq!(
            &orange_rgba[center_idx..center_idx + 4],
            &[245, 158, 11, 255]
        );

        let (pending_rgba, _, _) = build_tray_icon_rgba("RestoringPending");
        assert_eq!(
            &pending_rgba[center_idx..center_idx + 4],
            &[245, 158, 11, 255]
        );

        let (green_rgba, _, _) = build_tray_icon_rgba("Gaming");
        assert_eq!(
            &green_rgba[center_idx..center_idx + 4],
            &[34, 197, 94, 255]
        );
    }

    #[test]
    fn test_tray_menu_excludes_profile_submenu_and_maps_commands() {
        let ids = tray_menu_item_ids();
        assert_eq!(ids.len(), 7);
        for removed in [
            "tray-profile-menu",
            "tray-profile-aaa",
            "tray-profile-legacy-1",
            "tray-profile-legacy-2",
        ] {
            assert!(
                !ids.contains(&removed),
                "Profile submenu item '{}' must not exist in v4.0.0",
                removed
            );
            assert!(map_menu_id_to_command(removed).is_none());
        }

        assert_eq!(
            map_menu_id_to_command("tray-open"),
            Some(TrayCommand::OpenWindow)
        );
        assert_eq!(
            map_menu_id_to_command("tray-toggle"),
            Some(TrayCommand::ToggleMode)
        );
        assert_eq!(
            map_menu_id_to_command("tray-clean-ram"),
            Some(TrayCommand::CleanRam)
        );
        assert_eq!(
            map_menu_id_to_command("tray-timer"),
            Some(TrayCommand::ToggleTimer)
        );
        assert_eq!(
            map_menu_id_to_command("tray-reboot"),
            Some(TrayCommand::RebootPc)
        );
        assert_eq!(
            map_menu_id_to_command("tray-exit"),
            Some(TrayCommand::ExitApp)
        );
        assert_eq!(map_menu_id_to_command("tray-status"), None);

        let (st, tt, tog) = mode_to_tray_meta("RestoringPending");
        assert!(st.contains("восстановление"));
        assert!(tt.contains("оранжевый"));
        assert_eq!(tog, "Завершить восстановление");

        let long_ru = "Ultra Gaming Mode — ".to_string() + &"Очень длинное сообщение о состоянии памяти ".repeat(5);
        let clamped = truncate_tray_tooltip(&long_ru);
        assert!(
            clamped.encode_utf16().count() <= 120,
            "Win32 NOTIFYICONDATAW szTip must stay within 127 WCHAR limit"
        );
        assert!(clamped.ends_with('…'));
    }
}
