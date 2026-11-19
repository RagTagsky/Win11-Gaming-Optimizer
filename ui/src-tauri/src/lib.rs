use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, OnceLock};
use tauri::{Emitter, Manager};

pub const APP_VERSION: &str = env!("CARGO_PKG_VERSION");
pub const GITHUB_REPO: &str = "RagTagsky/Win11-Gaming-Optimizer";

#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;

#[cfg(target_os = "windows")]
const CREATE_NO_WINDOW: u32 = 0x08000000;

struct EmbeddedAsset {
    rel_path: &'static str,
    bytes: &'static [u8],
    preserve_if_exists: bool,
}

const EMBEDDED_RUNTIME_ASSETS: &[EmbeddedAsset] = &[
    EmbeddedAsset {
        rel_path: "UltraGamingMode.ps1",
        bytes: include_bytes!("../../../UltraGamingMode.ps1"),
        preserve_if_exists: false,
    },
    EmbeddedAsset {
        rel_path: "UltraGamingMode.bat",
        bytes: include_bytes!("../../../UltraGamingMode.bat"),
        preserve_if_exists: false,
    },
    EmbeddedAsset {
        rel_path: "Core/ServiceManager.ps1",
        bytes: include_bytes!("../../../Core/ServiceManager.ps1"),
        preserve_if_exists: false,
    },
    EmbeddedAsset {
        rel_path: "Core/StateEngine.ps1",
        bytes: include_bytes!("../../../Core/StateEngine.ps1"),
        preserve_if_exists: false,
    },
    EmbeddedAsset {
        rel_path: "Core/SystemOptimizer.ps1",
        bytes: include_bytes!("../../../Core/SystemOptimizer.ps1"),
        preserve_if_exists: false,
    },
    EmbeddedAsset {
        rel_path: "Config/services_blacklist.json",
        bytes: include_bytes!("../../../Config/services_blacklist.json"),
        preserve_if_exists: true,
    },
    EmbeddedAsset {
        rel_path: "Config/services_whitelist.json",
        bytes: include_bytes!("../../../Config/services_whitelist.json"),
        preserve_if_exists: true,
    },
    EmbeddedAsset {
        rel_path: "Config/service_descriptions.json",
        bytes: include_bytes!("../../../Config/service_descriptions.json"),
        preserve_if_exists: false,
    },
    EmbeddedAsset {
        rel_path: "Config/startup_apps.json",
        bytes: include_bytes!("../../../Config/startup_apps.json"),
        preserve_if_exists: true,
    },
    EmbeddedAsset {
        rel_path: "Config/tuning.json",
        bytes: include_bytes!("../../../Config/tuning.json"),
        preserve_if_exists: true,
    },
    EmbeddedAsset {
        rel_path: "Tests/Verify-UniversalEngine.ps1",
        bytes: include_bytes!("../../../Tests/Verify-UniversalEngine.ps1"),
        preserve_if_exists: false,
    },
];

static RUNTIME_ROOT_CACHE: OnceLock<PathBuf> = OnceLock::new();
static BACKUPS_ACL_INIT: OnceLock<()> = OnceLock::new();
static ALLOW_APP_EXIT: AtomicBool = AtomicBool::new(false);
static MODE_ACTION_BUSY: AtomicBool = AtomicBool::new(false);
static TIMER_LOCKED: AtomicBool = AtomicBool::new(false);
static START_IN_TRAY: AtomicBool = AtomicBool::new(false);
static PENDING_RESTORE_TRIGGERED: AtomicBool = AtomicBool::new(false);

#[cfg(not(test))]
fn set_tray_toggle_enabled(enabled: bool) {
    if let Some(ctrl) = TRAY_CONTROLLER.get() {
        let _ = ctrl.toggle_item.set_enabled(enabled);
    }
}

#[cfg(test)]
fn set_tray_toggle_enabled(_enabled: bool) {}

struct ModeActionGuard;

impl Drop for ModeActionGuard {
    fn drop(&mut self) {
        MODE_ACTION_BUSY.store(false, Ordering::SeqCst);
        set_tray_toggle_enabled(true);
    }
}

fn try_acquire_mode_action_guard() -> Option<ModeActionGuard> {
    if MODE_ACTION_BUSY
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_ok()
    {
        set_tray_toggle_enabled(false);
        Some(ModeActionGuard)
    } else {
        None
    }
}

struct CachedHardwareStatic {
    cpu: String,
    gpu: String,
}

static HW_STATIC_CACHE: OnceLock<CachedHardwareStatic> = OnceLock::new();

#[derive(Clone)]
struct CachedActiveState {
    path: PathBuf,
    modified: Option<std::time::SystemTime>,
    len: u64,
    mode: String,
    active_since: Option<String>,
    state_cpu: Option<String>,
    state_gpu: Option<String>,
    state_ram_gb: Option<f64>,
    localized_service_names: std::collections::HashMap<String, String>,
}

static ACTIVE_STATE_CACHE: Mutex<Option<CachedActiveState>> = Mutex::new(None);
static EXE_DISPLAY_NAME_CACHE: Mutex<Option<std::collections::HashMap<String, Option<String>>>> =
    Mutex::new(None);
static TRAY_CONTROLLER: OnceLock<TrayController> = OnceLock::new();

fn default_true() -> bool {
    true
}

#[derive(Serialize, Deserialize, Clone)]
pub struct HardwareInfo {
    pub cpu: String,
    pub gpu: String,
    pub ram: String,
    pub display: String,
    #[serde(rename = "dpcLatency")]
    pub dpc_latency: String,
    #[serde(rename = "mpoStatus")]
    pub mpo_status: String,
    #[serde(rename = "timerResolution", default)]
    pub timer_resolution: Option<String>,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct TuningConfig {
    #[serde(rename = "DisableFullscreenOptimizations")]
    pub disable_fullscreen_optimizations: bool,
    #[serde(rename = "DisableMouseAccel")]
    pub disable_mouse_accel: bool,
    #[serde(rename = "DisableNvidiaDynamicPstate", default)]
    pub disable_nvidia_dynamic_pstate: bool,
    #[serde(rename = "EnableNetAdapterMsi")]
    pub enable_net_adapter_msi: bool,
    #[serde(rename = "InputBufferQueueSize")]
    pub input_buffer_queue_size: u32,
    #[serde(rename = "AutoLockTimerInGaming", default = "default_true")]
    pub auto_lock_timer_in_gaming: bool,
}

impl Default for TuningConfig {
    fn default() -> Self {
        Self {
            disable_fullscreen_optimizations: true,
            disable_mouse_accel: false,
            disable_nvidia_dynamic_pstate: false,
            enable_net_adapter_msi: true,
            input_buffer_queue_size: 100,
            auto_lock_timer_in_gaming: true,
        }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct AutostartStatus {
    pub enabled: bool,
    #[serde(rename = "startInTray")]
    pub start_in_tray: bool,
    #[serde(rename = "taskExists")]
    pub task_exists: bool,
    #[serde(rename = "pathMatches")]
    pub path_matches: bool,
    #[serde(rename = "isElevatedTask")]
    pub is_elevated_task: bool,
    #[serde(rename = "currentExePath")]
    pub current_exe_path: String,
    #[serde(rename = "registeredCommand", default)]
    pub registered_command: Option<String>,
    #[serde(rename = "isAdminSession")]
    pub is_admin_session: bool,
    #[serde(default)]
    pub warning: Option<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug, Default)]
pub struct ServiceDescriptionEntry {
    #[serde(rename = "summaryRu", default)]
    pub summary_ru: String,
    #[serde(rename = "canDisableRu", default)]
    pub can_disable_ru: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct BlacklistServiceItem {
    #[serde(rename = "Name")]
    pub name: String,
    #[serde(rename = "DisplayName", default)]
    pub display_name: String,
    #[serde(rename = "Category", default)]
    pub category: String,
    #[serde(rename = "Reason")]
    pub reason: String,
    #[serde(rename = "Status", default)]
    pub status: String,
    #[serde(rename = "StartType", default)]
    pub start_type: String,
    #[serde(rename = "SummaryRu", default)]
    pub summary_ru: String,
    #[serde(rename = "CanDisableHint", default)]
    pub can_disable_hint: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct WhitelistServiceItem {
    #[serde(rename = "Name")]
    pub name: String,
    #[serde(rename = "DisplayName")]
    pub display_name: String,
    #[serde(rename = "Status")]
    pub status: String,
    #[serde(rename = "isCoreLocked")]
    pub is_core_locked: bool,
    #[serde(rename = "SummaryRu", default)]
    pub summary_ru: String,
    #[serde(rename = "CanDisableHint", default)]
    pub can_disable_hint: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct InstalledServiceItem {
    #[serde(rename = "Name")]
    pub name: String,
    #[serde(rename = "DisplayName")]
    pub display_name: String,
    #[serde(rename = "Status")]
    pub status: String,
    #[serde(rename = "StartType")]
    pub start_type: String,
    #[serde(rename = "Category")]
    pub category: String,
    pub membership: String,
    #[serde(rename = "isCoreLocked")]
    pub is_core_locked: bool,
    #[serde(rename = "SummaryRu", default)]
    pub summary_ru: String,
    #[serde(rename = "CanDisableHint", default)]
    pub can_disable_hint: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct ServiceFeaturePack {
    pub id: String,
    pub title: String,
    pub description: String,
    #[serde(rename = "keepEnabledInGame")]
    pub keep_enabled_in_game: bool,
    pub services: Vec<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct ServicesLists {
    pub blacklist: Vec<BlacklistServiceItem>,
    pub whitelist: Vec<String>,
    #[serde(rename = "whitelistDescriptions", default)]
    pub whitelist_descriptions: std::collections::HashMap<String, ServiceDescriptionEntry>,
    #[serde(rename = "whitelistItems", default)]
    pub whitelist_items: Vec<WhitelistServiceItem>,
    #[serde(rename = "allInstalledServices", default)]
    pub all_installed_services: Vec<InstalledServiceItem>,
    #[serde(rename = "wifiActive", default)]
    pub wifi_active: bool,
    #[serde(rename = "featurePacks", default)]
    pub feature_packs: Vec<ServiceFeaturePack>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct UpdateInfo {
    #[serde(rename = "currentVersion")]
    pub current_version: String,
    #[serde(rename = "latestVersion")]
    pub latest_version: String,
    #[serde(rename = "hasUpdate")]
    pub has_update: bool,
    #[serde(rename = "releaseUrl")]
    pub release_url: String,
    #[serde(rename = "publishedAt", default)]
    pub published_at: Option<String>,
    #[serde(rename = "releaseNotes")]
    pub release_notes: String,
    #[serde(rename = "installerUrl", default)]
    pub installer_url: Option<String>,
    #[serde(rename = "installerName", default)]
    pub installer_name: Option<String>,
    #[serde(rename = "checksumUrl", default)]
    pub checksum_url: Option<String>,
    #[serde(rename = "sizeBytes", default)]
    pub size_bytes: Option<u64>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct ProcessItem {
    pub pid: u32,
    pub name: String,
    #[serde(rename = "displayName", default)]
    pub display_name: String,
    #[serde(rename = "executablePath", default)]
    pub executable_path: String,
    #[serde(rename = "protectionKind", default)]
    pub protection_kind: Option<String>,
    #[serde(rename = "memoryMb")]
    pub memory_mb: f64,
    #[serde(rename = "isProtected")]
    pub is_protected: bool,
    #[serde(rename = "isBlacklisted")]
    pub is_blacklisted: bool,
    #[serde(rename = "isStartupProtected")]
    pub is_startup_protected: bool,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct StartupEntry {
    pub id: String,
    pub name: String,
    #[serde(rename = "displayName")]
    pub display_name: String,
    pub source: String,
    #[serde(rename = "sourceLabel")]
    pub source_label: String,
    pub target: String,
    pub enabled: bool,
    #[serde(rename = "isProtected")]
    pub is_protected: bool,
    #[serde(rename = "matchedRule", default)]
    pub matched_rule: Option<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct ProcessConfigLists {
    #[serde(rename = "blacklistProcesses")]
    pub blacklist_processes: Vec<String>,
    #[serde(rename = "protectedStartupNames")]
    pub protected_startup_names: Vec<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct LiveProcessesSnapshot {
    pub processes: Vec<ProcessItem>,
    #[serde(rename = "blacklistProcesses")]
    pub blacklist_processes: Vec<String>,
    #[serde(rename = "protectedStartupNames")]
    pub protected_startup_names: Vec<String>,
}

const CRITICAL_PROTECTED_PROCESSES: &[&str] = &[
    "System",
    "Idle",
    "Registry",
    "Secure System",
    "Memory Compression",
    "smss",
    "csrss",
    "wininit",
    "services",
    "lsass",
    "lsm",
    "svchost",
    "fontdrvhost",
    "dwm",
    "winlogon",
    "LogonUI",
    "sihost",
    "taskhostw",
    "explorer",
    "ShellExperienceHost",
    "StartMenuExperienceHost",
    "SearchHost",
    "TextInputHost",
    "LockApp",
    "RuntimeBroker",
    "ApplicationFrameHost",
    "dllhost",
    "conhost",
    "OpenConsole",
    "WindowsTerminal",
    "ctfmon",
    "audiodg",
    "spoolsv",
    "MsMpEng",
    "NisSrv",
    "SecurityHealthService",
    "SecurityHealthSystray",
    "SgrmBroker",
    "WmiPrvSE",
    "unsecapp",
    "TrustedInstaller",
    "TiWorker",
    "msiexec",
    "powershell",
    "pwsh",
    "cmd",
    "UltraGamingMode",
    "com.ultragamingmode.optimizer",
    "msedgewebview2",
    "vgk",
    "vgc",
    "EasyAntiCheat",
    "EasyAntiCheat_EOS",
    "BEService",
    "FACEIT",
    "steam",
    "steamservice",
    "steamwebhelper",
];

const IMMUTABLE_CORE_SERVICES: &[&str] = &[
    "RpcSs",
    "DcomLaunch",
    "RpcEptMapper",
    "PlugPlay",
    "Power",
    "LSM",
    "SamSs",
    "EventLog",
    "BFE",
    "mpssvc",
    "ProfSvc",
    "UserManager",
    "CryptSvc",
    "KeyIso",
    "VaultSvc",
    "CoreMessagingRegistrar",
    "SystemEventsBroker",
    "BrokerInfrastructure",
    "nsi",
    "Dhcp",
    "Dnscache",
    "Winmgmt",
    "Schedule",
    "TrustedInstaller",
    "Audiosrv",
    "AudioEndpointBuilder",
    "MMCSS",
];

struct ServiceFeaturePackDef {
    id: &'static str,
    title: &'static str,
    description: &'static str,
    services: &'static [&'static str],
}

const SERVICE_FEATURE_PACKS: &[ServiceFeaturePackDef] = &[
    ServiceFeaturePackDef {
        id: "wifi",
        title: "Wi-Fi и мобильный интернет",
        description: "Беспроводная сеть Wi-Fi, 4G/5G модем и точка доступа",
        services: &["WlanSvc", "WwanSvc", "icssvc"],
    },
    ServiceFeaturePackDef {
        id: "bluetooth",
        title: "Bluetooth",
        description: "Беспроводные наушники, колонки, геймпады и периферия",
        services: &["bthserv", "BTAGService", "BthAvctpSvc", "BluetoothUserService"],
    },
    ServiceFeaturePackDef {
        id: "faceit",
        title: "FACEIT AC",
        description: "Античит и клиент FACEIT для матчей CS2 (включён по умолчанию)",
        services: &["FACEIT", "FACEITService"],
    },
    ServiceFeaturePackDef {
        id: "camera",
        title: "Веб-камера",
        description: "Камера для OBS, Discord, трансляций и видеозвонков",
        services: &["FrameServer", "FrameServerMonitor", "StiSvc"],
    },
    ServiceFeaturePackDef {
        id: "xbox",
        title: "Xbox / Store / Геймпад",
        description: "Microsoft Store, Game Pass, Xbox Live, Game Bar и геймпад Xbox",
        services: &[
            "XblAuthManager",
            "XblGameSave",
            "XboxGipSvc",
            "XboxNetApiSvc",
            "GamingServices",
            "GamingServicesNet",
            "BcastDVRUserService",
            "InstallService",
        ],
    },
    ServiceFeaturePackDef {
        id: "vpn",
        title: "VPN / PPPoE",
        description: "Подключения VPN (L2TP/IKEv2/SSTP) и проводной PPPoE",
        services: &["RasMan", "RasAuto", "IKEEXT", "PolicyAgent"],
    },
    ServiceFeaturePackDef {
        id: "printer",
        title: "Принтер / PDF",
        description: "Печать документов, виртуальный принтер PDF и сканеры",
        services: &[
            "Spooler",
            "PrintNotify",
            "PrintWorkflowUserSvc",
            "PrintDeviceConfigurationService",
            "PrintScanBrokerService",
            "Fax",
        ],
    },
];

pub fn strip_exe_suffix(name: &str) -> &str {
    let trimmed = name.trim();
    if trimmed.len() >= 4 && trimmed[trimmed.len() - 4..].eq_ignore_ascii_case(".exe") {
        &trimmed[..trimmed.len() - 4]
    } else {
        trimmed
    }
}

pub fn is_safe_identifier(name: &str) -> bool {
    let trimmed = name.trim();
    if trimmed.is_empty() || trimmed.len() > 128 || trimmed.contains("..") {
        return false;
    }
    trimmed.bytes().all(|b| {
        b.is_ascii_alphanumeric() || matches!(b, b'_' | b'.' | b'-' | b' ')
    })
}

pub fn classify_process_protection(name: &str) -> Option<&'static str> {
    let clean = strip_exe_suffix(name);
    if !is_safe_identifier(clean) {
        return Some("os_core");
    }
    if [
        "UltraGamingMode",
        "com.ultragamingmode.optimizer",
        "msedgewebview2",
    ]
    .iter()
    .any(|p| p.eq_ignore_ascii_case(clean))
    {
        return Some("self_app");
    }
    if [
        "vgk",
        "vgc",
        "EasyAntiCheat",
        "EasyAntiCheat_EOS",
        "BEService",
        "FACEIT",
        "FACEITClient",
        "FACEITService",
    ]
    .iter()
    .any(|p| p.eq_ignore_ascii_case(clean))
    {
        return Some("anticheat");
    }
    if ["steam", "steamservice", "steamwebhelper"]
        .iter()
        .any(|p| p.eq_ignore_ascii_case(clean))
    {
        return Some("game_client");
    }
    if CRITICAL_PROTECTED_PROCESSES
        .iter()
        .any(|p| p.eq_ignore_ascii_case(clean))
    {
        return Some("os_core");
    }
    None
}

pub fn is_protected_process_name(name: &str) -> bool {
    classify_process_protection(name).is_some()
}

fn strip_per_user_service_suffix(name: &str) -> &str {
    if let Some(idx) = name.rfind('_') {
        let suffix = &name[idx + 1..];
        if !suffix.is_empty() && suffix.chars().all(|c| c.is_ascii_hexdigit()) {
            return &name[..idx];
        }
    }
    name
}

pub fn is_immutable_core_service(name: &str) -> bool {
    let trimmed = name.trim();
    let base = strip_per_user_service_suffix(trimmed);
    IMMUTABLE_CORE_SERVICES
        .iter()
        .any(|s| s.eq_ignore_ascii_case(trimmed) || s.eq_ignore_ascii_case(base))
}

fn write_json_no_bom(path: &Path, val: &impl Serialize) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|e| format!("Не удалось создать каталог {}: {}", parent.display(), e))?;
    }
    let serialized = serde_json::to_string_pretty(val)
        .map_err(|e| format!("Ошибка сериализации {}: {}", path.display(), e))?;
    let tmp_path = path.with_extension(format!("tmp.{}", std::process::id()));
    if std::fs::write(&tmp_path, serialized.as_bytes()).is_ok() {
        if std::fs::rename(&tmp_path, path).is_ok() {
            return Ok(());
        }
        let _ = std::fs::remove_file(&tmp_path);
    }
    std::fs::write(path, serialized.as_bytes())
        .map_err(|e| format!("Не удалось записать {}: {}", path.display(), e))
}

#[cfg(target_os = "windows")]
mod win_hw {
    const HKEY_CURRENT_USER: usize = 0x80000001;
    const HKEY_LOCAL_MACHINE: usize = 0x80000002;
    const KEY_READ: u32 = 0x20019;
    const KEY_ENUMERATE_SUB_KEYS: u32 = 0x0008;
    const REG_SZ: u32 = 1;
    const REG_EXPAND_SZ: u32 = 2;
    const REG_BINARY: u32 = 3;
    const REG_DWORD: u32 = 4;

    #[repr(C)]
    struct MEMORYSTATUSEX {
        dw_length: u32,
        dw_memory_load: u32,
        ull_total_phys: u64,
        ull_avail_phys: u64,
        ull_total_page_file: u64,
        ull_avail_page_file: u64,
        ull_total_virtual: u64,
        ull_avail_virtual: u64,
        ull_avail_extended_virtual: u64,
    }

    #[repr(C)]
    struct PROCESSENTRY32W {
        dw_size: u32,
        cnt_usage: u32,
        th32_process_id: u32,
        th32_default_heap_id: usize,
        th32_module_id: u32,
        cnt_threads: u32,
        th32_parent_process_id: u32,
        pc_pri_class_base: i32,
        dw_flags: u32,
        sz_exe_file: [u16; 260],
    }

    #[repr(C)]
    #[derive(Default)]
    struct PROCESS_MEMORY_COUNTERS {
        cb: u32,
        page_fault_count: u32,
        peak_working_set_size: usize,
        working_set_size: usize,
        quota_peak_paged_pool_usage: usize,
        quota_paged_pool_usage: usize,
        quota_peak_non_paged_pool_usage: usize,
        quota_non_paged_pool_usage: usize,
        pagefile_usage: usize,
        peak_pagefile_usage: usize,
    }

    #[repr(C)]
    #[derive(Clone, Copy)]
    struct SERVICE_STATUS_PROCESS {
        dw_service_type: u32,
        dw_current_state: u32,
        dw_controls_accepted: u32,
        dw_win32_exit_code: u32,
        dw_service_specific_exit_code: u32,
        dw_check_point: u32,
        dw_wait_hint: u32,
        dw_process_id: u32,
        dw_service_flags: u32,
    }

    #[repr(C)]
    #[derive(Clone, Copy)]
    struct ENUM_SERVICE_STATUS_PROCESSW {
        lp_service_name: *mut u16,
        lp_display_name: *mut u16,
        service_status_process: SERVICE_STATUS_PROCESS,
    }

    #[repr(C)]
    #[derive(Clone, Copy)]
    struct LUID {
        low_part: u32,
        high_part: i32,
    }

    #[repr(C)]
    #[derive(Clone, Copy)]
    struct LUID_AND_ATTRIBUTES {
        luid: LUID,
        attributes: u32,
    }

    #[repr(C)]
    #[derive(Clone, Copy)]
    struct TOKEN_PRIVILEGES {
        privilege_count: u32,
        privileges: [LUID_AND_ATTRIBUTES; 1],
    }

    #[repr(C)]
    #[derive(Default, Clone, Copy)]
    struct SERVICE_STATUS {
        dw_service_type: u32,
        dw_current_state: u32,
        dw_controls_accepted: u32,
        dw_win32_exit_code: u32,
        dw_service_specific_exit_code: u32,
        dw_check_point: u32,
        dw_wait_hint: u32,
    }

    #[repr(C)]
    struct QUERY_SERVICE_CONFIGW {
        dw_service_type: u32,
        dw_start_type: u32,
        dw_error_control: u32,
        lp_binary_path_name: *mut u16,
        lp_load_order_group: *mut u16,
        dw_tag_id: u32,
        lp_dependencies: *mut u16,
        lp_service_start_name: *mut u16,
        lp_display_name: *mut u16,
    }

    #[repr(C)]
    struct TOKEN_USER {
        sid: *mut std::ffi::c_void,
        attributes: u32,
    }

    #[repr(C)]
    #[derive(Clone, Copy)]
    struct WLAN_INTERFACE_INFO {
        interface_guid: [u8; 16],
        description: [u16; 256],
        is_state: u32,
    }

    #[repr(C)]
    struct WLAN_INTERFACE_INFO_LIST {
        number_of_items: u32,
        index: u32,
        interface_info: [WLAN_INTERFACE_INFO; 1],
    }

    #[link(name = "advapi32")]
    extern "system" {
        fn RegOpenKeyExW(
            hKey: usize,
            lpSubKey: *const u16,
            ulOptions: u32,
            samDesired: u32,
            phkResult: *mut usize,
        ) -> i32;
        fn RegQueryValueExW(
            hKey: usize,
            lpValueName: *const u16,
            lpReserved: *const u32,
            lpType: *mut u32,
            lpData: *mut u8,
            lpcbData: *mut u32,
        ) -> i32;
        fn RegEnumValueW(
            hKey: usize,
            dwIndex: u32,
            lpValueName: *mut u16,
            lpcchValueName: *mut u32,
            lpReserved: *const u32,
            lpType: *mut u32,
            lpData: *mut u8,
            lpcbData: *mut u32,
        ) -> i32;
        fn RegEnumKeyExW(
            hKey: usize,
            dwIndex: u32,
            lpName: *mut u16,
            lpcchName: *mut u32,
            lpReserved: *const u32,
            lpClass: *mut u16,
            lpcchClass: *mut u32,
            lpftLastWriteTime: *mut std::ffi::c_void,
        ) -> i32;
        fn RegCloseKey(hKey: usize) -> i32;
        fn OpenSCManagerW(
            lpMachineName: *const u16,
            lpDatabaseName: *const u16,
            dwDesiredAccess: u32,
        ) -> usize;
        fn OpenServiceW(
            hSCManager: usize,
            lpServiceName: *const u16,
            dwDesiredAccess: u32,
        ) -> usize;
        fn StartServiceW(
            hService: usize,
            dwNumServiceArgs: u32,
            lpServiceArgVectors: *const *const u16,
        ) -> i32;
        fn ControlService(
            hService: usize,
            dwControl: u32,
            lpServiceStatus: *mut SERVICE_STATUS,
        ) -> i32;
        fn QueryServiceStatus(
            hService: usize,
            lpServiceStatus: *mut SERVICE_STATUS,
        ) -> i32;
        fn ChangeServiceConfigW(
            hService: usize,
            dwServiceType: u32,
            dwStartType: u32,
            dwErrorControl: u32,
            lpBinaryPathName: *const u16,
            lpLoadOrderGroup: *const u16,
            lpdwTagId: *mut u32,
            lpDependencies: *const u16,
            lpServiceStartName: *const u16,
            lpPassword: *const u16,
            lpDisplayName: *const u16,
        ) -> i32;
        fn QueryServiceConfigW(
            hService: usize,
            lpServiceConfig: *mut u8,
            cbBufSize: u32,
            pcbBytesNeeded: *mut u32,
        ) -> i32;
        fn EnumServicesStatusExW(
            hSCManager: usize,
            InfoLevel: u32,
            dwServiceType: u32,
            dwServiceState: u32,
            lpServices: *mut u8,
            cbBufSize: u32,
            pcbBytesNeeded: *mut u32,
            lpServicesReturned: *mut u32,
            lpResumeHandle: *mut u32,
            pszGroupName: *const u16,
        ) -> i32;
        fn CloseServiceHandle(hSCObject: usize) -> i32;
        fn OpenProcessToken(
            ProcessHandle: isize,
            DesiredAccess: u32,
            TokenHandle: *mut isize,
        ) -> i32;
        fn GetTokenInformation(
            TokenHandle: isize,
            TokenInformationClass: u32,
            TokenInformation: *mut std::ffi::c_void,
            TokenInformationLength: u32,
            ReturnLength: *mut u32,
        ) -> i32;
        fn ConvertSidToStringSidW(
            Sid: *mut std::ffi::c_void,
            StringSid: *mut *mut u16,
        ) -> i32;
        fn LookupPrivilegeValueW(
            lpSystemName: *const u16,
            lpName: *const u16,
            lpLuid: *mut LUID,
        ) -> i32;
        fn AdjustTokenPrivileges(
            TokenHandle: isize,
            DisableAllPrivileges: i32,
            NewState: *const TOKEN_PRIVILEGES,
            BufferLength: u32,
            PreviousState: *mut TOKEN_PRIVILEGES,
            ReturnLength: *mut u32,
        ) -> i32;
    }

    #[link(name = "kernel32")]
    extern "system" {
        fn GlobalMemoryStatusEx(lpBuffer: *mut MEMORYSTATUSEX) -> i32;
        fn CreateToolhelp32Snapshot(dwFlags: u32, th32ProcessID: u32) -> isize;
        fn Process32FirstW(hSnapshot: isize, lppe: *mut PROCESSENTRY32W) -> i32;
        fn Process32NextW(hSnapshot: isize, lppe: *mut PROCESSENTRY32W) -> i32;
        fn OpenProcess(dwDesiredAccess: u32, bInheritHandle: i32, dwProcessId: u32) -> isize;
        fn TerminateProcess(hProcess: isize, uExitCode: u32) -> i32;
        fn CloseHandle(hObject: isize) -> i32;
        fn QueryFullProcessImageNameW(
            hProcess: isize,
            dwFlags: u32,
            lpExeName: *mut u16,
            lpdwSize: *mut u32,
        ) -> i32;
        fn K32GetProcessMemoryInfo(
            Process: isize,
            ppsmemCounters: *mut PROCESS_MEMORY_COUNTERS,
            cb: u32,
        ) -> i32;
        fn GetCurrentProcess() -> isize;
        fn GetModuleHandleA(lpModuleName: *const u8) -> *mut std::ffi::c_void;
        fn LoadLibraryA(lpLibFileName: *const u8) -> *mut std::ffi::c_void;
        fn FreeLibrary(hLibModule: *mut std::ffi::c_void) -> i32;
        fn GetProcAddress(
            hModule: *mut std::ffi::c_void,
            lpProcName: *const u8,
        ) -> *mut std::ffi::c_void;
        fn LocalFree(hMem: *mut std::ffi::c_void) -> *mut std::ffi::c_void;
        fn GetLastError() -> u32;
        fn CreateMutexW(
            lpMutexAttributes: *const std::ffi::c_void,
            bInitialOwner: i32,
            lpName: *const u16,
        ) -> isize;
        fn CreateEventW(
            lpEventAttributes: *const std::ffi::c_void,
            bManualReset: i32,
            bInitialState: i32,
            lpName: *const u16,
        ) -> isize;
        fn OpenEventW(
            dwDesiredAccess: u32,
            bInheritHandle: i32,
            lpName: *const u16,
        ) -> isize;
        fn SetEvent(hEvent: isize) -> i32;
        fn WaitForSingleObject(hHandle: isize, dwMilliseconds: u32) -> u32;
    }

    #[link(name = "version")]
    extern "system" {
        fn GetFileVersionInfoSizeW(lptstrFilename: *const u16, lpdwHandle: *mut u32) -> u32;
        fn GetFileVersionInfoW(
            lptstrFilename: *const u16,
            dwHandle: u32,
            dwLen: u32,
            lpData: *mut std::ffi::c_void,
        ) -> i32;
        fn VerQueryValueW(
            pBlock: *const std::ffi::c_void,
            lpSubBlock: *const u16,
            lplpBuffer: *mut *const std::ffi::c_void,
            puLen: *mut u32,
        ) -> i32;
    }

    #[link(name = "user32")]
    extern "system" {
        fn GetSystemMetrics(nIndex: i32) -> i32;
        fn MessageBoxW(
            hWnd: isize,
            lpText: *const u16,
            lpCaption: *const u16,
            uType: u32,
        ) -> i32;
    }

    fn to_wide(s: &str) -> Vec<u16> {
        s.encode_utf16().chain(std::iter::once(0)).collect()
    }

    pub fn read_reg_string_root(hkey_root: usize, subkey: &str, value_name: &str) -> Option<String> {
        unsafe {
            let mut hkey: usize = 0;
            let subkey_w = to_wide(subkey);
            if RegOpenKeyExW(hkey_root, subkey_w.as_ptr(), 0, KEY_READ, &mut hkey) != 0 {
                return None;
            }
            let val_w = to_wide(value_name);
            let mut reg_type: u32 = 0;
            let mut data_len: u32 = 0;
            let status = RegQueryValueExW(
                hkey,
                val_w.as_ptr(),
                std::ptr::null(),
                &mut reg_type,
                std::ptr::null_mut(),
                &mut data_len,
            );
            if status != 0 || (reg_type != REG_SZ && reg_type != REG_EXPAND_SZ) || data_len < 2 {
                let _ = RegCloseKey(hkey);
                return None;
            }
            let mut buf: Vec<u16> = vec![0u16; (data_len as usize) / 2 + 1];
            let status2 = RegQueryValueExW(
                hkey,
                val_w.as_ptr(),
                std::ptr::null(),
                &mut reg_type,
                buf.as_mut_ptr() as *mut u8,
                &mut data_len,
            );
            let _ = RegCloseKey(hkey);
            if status2 != 0 {
                return None;
            }
            let end = buf.iter().position(|&c| c == 0).unwrap_or(buf.len());
            let s = String::from_utf16_lossy(&buf[..end]).trim().to_string();
            if s.is_empty() {
                None
            } else {
                Some(s)
            }
        }
    }

    pub fn read_reg_string(subkey: &str, value_name: &str) -> Option<String> {
        read_reg_string_root(HKEY_LOCAL_MACHINE, subkey, value_name)
    }

    pub fn read_reg_dword_root(hkey_root: usize, subkey: &str, value_name: &str) -> Option<u32> {
        unsafe {
            let mut hkey: usize = 0;
            let subkey_w = to_wide(subkey);
            if RegOpenKeyExW(hkey_root, subkey_w.as_ptr(), 0, KEY_READ, &mut hkey) != 0 {
                return None;
            }
            let val_w = to_wide(value_name);
            let mut reg_type: u32 = 0;
            let mut val: u32 = 0;
            let mut data_len: u32 = 4;
            let status = RegQueryValueExW(
                hkey,
                val_w.as_ptr(),
                std::ptr::null(),
                &mut reg_type,
                &mut val as *mut u32 as *mut u8,
                &mut data_len,
            );
            let _ = RegCloseKey(hkey);
            if status == 0 && reg_type == REG_DWORD {
                Some(val)
            } else {
                None
            }
        }
    }

    pub fn read_reg_dword(subkey: &str, value_name: &str) -> Option<u32> {
        read_reg_dword_root(HKEY_LOCAL_MACHINE, subkey, value_name)
    }

    pub fn detect_cpu_name() -> Option<String> {
        read_reg_string(
            r"HARDWARE\DESCRIPTION\System\CentralProcessor\0",
            "ProcessorNameString",
        )
    }

    pub fn detect_gpu_name() -> Option<String> {
        let base = r"SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}";
        let mut discrete: Option<String> = None;
        let mut integrated: Option<String> = None;
        let mut fallback: Option<String> = None;
        for idx in 0..16 {
            let sub = format!(r"{}\{:04}", base, idx);
            if let Some(desc) = read_reg_string(&sub, "DriverDesc") {
                let lower = desc.to_lowercase();
                if lower.contains("basic")
                    || lower.contains("virtual")
                    || lower.contains("remote")
                    || lower.contains("parsec")
                    || lower.contains("indirect")
                {
                    continue;
                }
                let is_igpu = lower == "amd radeon(tm) graphics"
                    || lower == "amd radeon graphics"
                    || lower.contains("uhd graphics")
                    || lower.contains("hd graphics")
                    || lower.contains("iris");
                if !is_igpu
                    && (lower.contains("radeon")
                        || lower.contains("geforce")
                        || lower.contains("rtx")
                        || lower.contains("gtx")
                        || lower.contains("arc"))
                {
                    discrete = Some(desc);
                    break;
                }
                if is_igpu && integrated.is_none() {
                    integrated = Some(desc);
                } else if fallback.is_none() {
                    fallback = Some(desc);
                }
            }
        }
        discrete.or(integrated).or(fallback)
    }

    pub fn detect_ram_gb() -> Option<String> {
        unsafe {
            let mut mem: MEMORYSTATUSEX = std::mem::zeroed();
            mem.dw_length = std::mem::size_of::<MEMORYSTATUSEX>() as u32;
            if GlobalMemoryStatusEx(&mut mem) != 0 && mem.ull_total_phys > 0 {
                let total_gb = (mem.ull_total_phys as f64) / (1024.0 * 1024.0 * 1024.0);
                let avail_gb = (mem.ull_avail_phys as f64) / (1024.0 * 1024.0 * 1024.0);
                Some(format!(
                    "{:.0} ГБ ОЗУ (доступно {:.1} ГБ)",
                    total_gb.round(),
                    avail_gb
                ))
            } else {
                None
            }
        }
    }

    pub fn detect_display_summary() -> String {
        unsafe {
            let w = GetSystemMetrics(0);
            let h = GetSystemMetrics(1);
            let mpo_override = read_reg_dword(r"SOFTWARE\Microsoft\Windows\Dwm", "OverlayTestMode");
            let mpo_note = if mpo_override == Some(5) {
                "MPO отключён"
            } else {
                "MPO штатный (защита от мерцания)"
            };
            if w > 0 && h > 0 {
                format!("{}×{} ({})", w, h, mpo_note)
            } else {
                format!("Основной дисплей ({})", mpo_note)
            }
        }
    }

    pub fn detect_dpc_status() -> String {
        let threaded = read_reg_dword(
            r"SYSTEM\CurrentControlSet\Control\Session Manager\kernel",
            "ThreadDpcEnable",
        );
        let prio = read_reg_dword(
            r"SYSTEM\CurrentControlSet\Control\PriorityControl",
            "Win32PrioritySeparation",
        );
        let dpc_label = match threaded {
            Some(0) => "Прямой DPC (нерекомендуемо)",
            _ => "Потоковый DPC (оптимально)",
        };
        if prio == Some(38) {
            format!("{} · Приоритет 0x26", dpc_label)
        } else {
            dpc_label.to_string()
        }
    }

    pub fn detect_mpo_status() -> String {
        let mpo_override = read_reg_dword(r"SOFTWARE\Microsoft\Windows\Dwm", "OverlayTestMode");
        if mpo_override == Some(5) {
            "Принудительно отключён (OverlayTestMode = 5)".to_string()
        } else {
            "Штатный конвейер DWM (без мерцания)".to_string()
        }
    }

    unsafe fn wide_ptr_to_string(ptr: *const u16) -> String {
        if ptr.is_null() {
            return String::new();
        }
        let mut len = 0usize;
        while len < 512 && *ptr.add(len) != 0 {
            len += 1;
        }
        let slice = std::slice::from_raw_parts(ptr, len);
        String::from_utf16_lossy(slice).trim().to_string()
    }

    pub fn enumerate_live_services(
    ) -> std::collections::HashMap<String, (String, String, String)> {
        let mut out = std::collections::HashMap::new();
        unsafe {
            // SC_MANAGER_CONNECT (0x1) | SC_MANAGER_ENUMERATE_SERVICE (0x4)
            let scm = OpenSCManagerW(std::ptr::null(), std::ptr::null(), 0x0005);
            if scm == 0 {
                return out;
            }
            let mut bytes_needed: u32 = 0;
            let mut services_returned: u32 = 0;
            let mut resume_handle: u32 = 0;
            let _ = EnumServicesStatusExW(
                scm,
                0,    // SC_ENUM_PROCESS_INFO
                0x30, // SERVICE_WIN32
                0x03, // SERVICE_STATE_ALL
                std::ptr::null_mut(),
                0,
                &mut bytes_needed,
                &mut services_returned,
                &mut resume_handle,
                std::ptr::null(),
            );
            if bytes_needed > 0 {
                let u64_len = (bytes_needed as usize + 7) / 8 + 128;
                let mut buf: Vec<u64> = vec![0u64; u64_len];
                resume_handle = 0;
                services_returned = 0;
                let ok = EnumServicesStatusExW(
                    scm,
                    0,
                    0x30,
                    0x03,
                    buf.as_mut_ptr() as *mut u8,
                    (buf.len() * 8) as u32,
                    &mut bytes_needed,
                    &mut services_returned,
                    &mut resume_handle,
                    std::ptr::null(),
                );
                if ok != 0 && services_returned > 0 {
                    let entries = std::slice::from_raw_parts(
                        buf.as_ptr() as *const ENUM_SERVICE_STATUS_PROCESSW,
                        services_returned as usize,
                    );
                    for entry in entries {
                        let name = wide_ptr_to_string(entry.lp_service_name);
                        if name.is_empty() {
                            continue;
                        }
                        let disp = wide_ptr_to_string(entry.lp_display_name);
                        let status = match entry.service_status_process.dw_current_state {
                            4 => "Running",
                            1 => "Stopped",
                            2 => "StartPending",
                            3 => "StopPending",
                            7 => "Paused",
                            _ => "Unknown",
                        }
                        .to_string();
                        out.insert(name.to_lowercase(), (name, status, disp));
                    }
                }
            }
            let _ = CloseServiceHandle(scm);
        }
        out
    }

    pub fn read_service_start_type(service_name: &str) -> String {
        let subkey = format!(r"SYSTEM\CurrentControlSet\Services\{}", service_name);
        match read_reg_dword(&subkey, "Start") {
            Some(0 | 1 | 2) => "Automatic".to_string(),
            Some(3) => "Manual".to_string(),
            Some(4) => "Disabled".to_string(),
            _ => String::new(),
        }
    }

    pub fn is_current_process_elevated() -> bool {
        unsafe {
            let mut token: isize = 0;
            // TOKEN_QUERY (0x0008)
            if OpenProcessToken(GetCurrentProcess(), 0x0008, &mut token) == 0 {
                return false;
            }
            let mut elevation: u32 = 0;
            let mut ret_len: u32 = 0;
            // TokenElevation = 20
            let ok = GetTokenInformation(
                token,
                20,
                &mut elevation as *mut u32 as *mut std::ffi::c_void,
                std::mem::size_of::<u32>() as u32,
                &mut ret_len,
            );
            let _ = CloseHandle(token);
            ok != 0 && elevation != 0
        }
    }

    pub fn get_current_user_sid_string() -> Result<String, String> {
        unsafe {
            let mut token: isize = 0;
            if OpenProcessToken(GetCurrentProcess(), 0x0008, &mut token) == 0 {
                return Err(format!(
                    "OpenProcessToken завершился с ошибкой Win32 {}",
                    GetLastError()
                ));
            }
            let mut needed: u32 = 0;
            // TokenUser = 1
            let _ = GetTokenInformation(token, 1, std::ptr::null_mut(), 0, &mut needed);
            if needed == 0 || needed > 4096 {
                let _ = CloseHandle(token);
                return Err("Не удалось определить размер TokenUser SID".to_string());
            }
            let mut buf = vec![0u8; needed as usize];
            if GetTokenInformation(
                token,
                1,
                buf.as_mut_ptr() as *mut std::ffi::c_void,
                needed,
                &mut needed,
            ) == 0
            {
                let err = GetLastError();
                let _ = CloseHandle(token);
                return Err(format!("GetTokenInformation(TokenUser) ошибка Win32 {}", err));
            }
            let _ = CloseHandle(token);
            let tu = &*(buf.as_ptr() as *const TOKEN_USER);
            if tu.sid.is_null() {
                return Err("Пустой SID текущего пользователя".to_string());
            }
            let mut str_ptr: *mut u16 = std::ptr::null_mut();
            if ConvertSidToStringSidW(tu.sid, &mut str_ptr) == 0 || str_ptr.is_null() {
                return Err(format!(
                    "ConvertSidToStringSidW ошибка Win32 {}",
                    GetLastError()
                ));
            }
            let sid = wide_ptr_to_string(str_ptr);
            let _ = LocalFree(str_ptr as *mut std::ffi::c_void);
            if sid.is_empty() {
                Err("Получен пустой строковый SID".to_string())
            } else {
                Ok(sid)
            }
        }
    }

    pub fn read_exe_display_name(exe_path: &str) -> Option<String> {
        let trimmed_path = exe_path.trim();
        if trimmed_path.is_empty() {
            return None;
        }
        let cache_key = trimmed_path.to_ascii_lowercase();
        if let Ok(guard) = super::EXE_DISPLAY_NAME_CACHE.lock() {
            if let Some(map) = guard.as_ref() {
                if let Some(cached) = map.get(&cache_key) {
                    return cached.clone();
                }
            }
        }

        let resolved = unsafe {
            let path_w = to_wide(trimmed_path);
            let mut handle: u32 = 0;
            let size = GetFileVersionInfoSizeW(path_w.as_ptr(), &mut handle);
            if size == 0 || size > 16 * 1024 * 1024 {
                None
            } else {
                let mut buf = vec![0u8; size as usize];
                if GetFileVersionInfoW(
                    path_w.as_ptr(),
                    0,
                    size,
                    buf.as_mut_ptr() as *mut std::ffi::c_void,
                ) == 0
                {
                    None
                } else {
                    let mut langs: Vec<(u16, u16)> = Vec::new();
                    let trans_w = to_wide(r"\VarFileInfo\Translation");
                    let mut trans_ptr: *const std::ffi::c_void = std::ptr::null();
                    let mut trans_len: u32 = 0;
                    if VerQueryValueW(
                        buf.as_ptr() as *const std::ffi::c_void,
                        trans_w.as_ptr(),
                        &mut trans_ptr,
                        &mut trans_len,
                    ) != 0
                        && !trans_ptr.is_null()
                        && trans_len >= 4
                    {
                        let pair_count = (trans_len as usize / 4).min(8);
                        let raw_pairs =
                            std::slice::from_raw_parts(trans_ptr as *const [u16; 2], pair_count);
                        for &[lang, cp] in raw_pairs {
                            langs.push((lang, cp));
                        }
                    }
                    for fallback in [(0x0409, 0x04B0), (0x0419, 0x04B0), (0x0409, 0x04E4), (0x0000, 0x04B0)] {
                        if !langs.contains(&fallback) {
                            langs.push(fallback);
                        }
                    }

                    let mut found: Option<String> = None;
                    'outer: for (lang, cp) in langs {
                        for field in ["FileDescription", "ProductName"] {
                            let sub = format!(r"\StringFileInfo\{:04x}{:04x}\{}", lang, cp, field);
                            let sub_w = to_wide(&sub);
                            let mut val_ptr: *const std::ffi::c_void = std::ptr::null();
                            let mut val_len: u32 = 0;
                            if VerQueryValueW(
                                buf.as_ptr() as *const std::ffi::c_void,
                                sub_w.as_ptr(),
                                &mut val_ptr,
                                &mut val_len,
                            ) != 0
                                && !val_ptr.is_null()
                                && val_len > 1
                            {
                                let units = std::slice::from_raw_parts(
                                    val_ptr as *const u16,
                                    (val_len as usize).min(512),
                                );
                                let end = units.iter().position(|&c| c == 0).unwrap_or(units.len());
                                let s = String::from_utf16_lossy(&units[..end]).trim().to_string();
                                if !s.is_empty() {
                                    found = Some(s);
                                    break 'outer;
                                }
                            }
                        }
                    }
                    found
                }
            }
        };

        if let Ok(mut guard) = super::EXE_DISPLAY_NAME_CACHE.lock() {
            let map = guard.get_or_insert_with(std::collections::HashMap::new);
            if map.len() > 1024 {
                map.clear();
            }
            map.insert(cache_key, resolved.clone());
        }
        resolved
    }

    pub fn is_wifi_connected() -> bool {
        type WlanOpenHandleFn =
            unsafe extern "system" fn(u32, *mut std::ffi::c_void, *mut u32, *mut isize) -> u32;
        type WlanEnumInterfacesFn = unsafe extern "system" fn(
            isize,
            *mut std::ffi::c_void,
            *mut *mut WLAN_INTERFACE_INFO_LIST,
        ) -> u32;
        type WlanFreeMemoryFn = unsafe extern "system" fn(*mut std::ffi::c_void);
        type WlanCloseHandleFn = unsafe extern "system" fn(isize, *mut std::ffi::c_void) -> u32;

        unsafe {
            let lib = LoadLibraryA(b"wlanapi.dll\0".as_ptr());
            if lib.is_null() {
                return false;
            }
            let p_open = GetProcAddress(lib, b"WlanOpenHandle\0".as_ptr());
            let p_enum = GetProcAddress(lib, b"WlanEnumInterfaces\0".as_ptr());
            let p_free = GetProcAddress(lib, b"WlanFreeMemory\0".as_ptr());
            let p_close = GetProcAddress(lib, b"WlanCloseHandle\0".as_ptr());
            if p_open.is_null() || p_enum.is_null() || p_free.is_null() || p_close.is_null() {
                let _ = FreeLibrary(lib);
                return false;
            }
            let wlan_open: WlanOpenHandleFn = std::mem::transmute(p_open);
            let wlan_enum: WlanEnumInterfacesFn = std::mem::transmute(p_enum);
            let wlan_free: WlanFreeMemoryFn = std::mem::transmute(p_free);
            let wlan_close: WlanCloseHandleFn = std::mem::transmute(p_close);

            let mut neg_ver: u32 = 0;
            let mut client: isize = 0;
            let mut connected = false;
            if wlan_open(2, std::ptr::null_mut(), &mut neg_ver, &mut client) == 0 && client != 0 {
                let mut list_ptr: *mut WLAN_INTERFACE_INFO_LIST = std::ptr::null_mut();
                if wlan_enum(client, std::ptr::null_mut(), &mut list_ptr) == 0 && !list_ptr.is_null() {
                    let count = ((*list_ptr).number_of_items as usize).min(64);
                    let base = (*list_ptr).interface_info.as_ptr();
                    for i in 0..count {
                        let iface = &*base.add(i);
                        // wlan_interface_state_connected = 1
                        if iface.is_state == 1 {
                            connected = true;
                            break;
                        }
                    }
                    wlan_free(list_ptr as *mut std::ffi::c_void);
                }
                let _ = wlan_close(client, std::ptr::null_mut());
            }
            let _ = FreeLibrary(lib);
            connected
        }
    }

    fn read_startup_approved_map(
        hkey_root: usize,
        subkey: &str,
    ) -> std::collections::HashMap<String, bool> {
        let mut out = std::collections::HashMap::new();
        unsafe {
            let mut hkey: usize = 0;
            let sub_w = to_wide(subkey);
            if RegOpenKeyExW(hkey_root, sub_w.as_ptr(), 0, KEY_READ, &mut hkey) != 0 {
                return out;
            }
            let mut index: u32 = 0;
            loop {
                let mut name_buf = [0u16; 260];
                let mut name_len: u32 = name_buf.len() as u32;
                let mut reg_type: u32 = 0;
                let mut data = [0u8; 32];
                let mut data_len: u32 = data.len() as u32;
                let res = RegEnumValueW(
                    hkey,
                    index,
                    name_buf.as_mut_ptr(),
                    &mut name_len,
                    std::ptr::null(),
                    &mut reg_type,
                    data.as_mut_ptr(),
                    &mut data_len,
                );
                if res != 0 {
                    break;
                }
                index += 1;
                if reg_type == REG_BINARY && data_len >= 1 {
                    let val_name = String::from_utf16_lossy(&name_buf[..(name_len as usize)])
                        .trim()
                        .to_lowercase();
                    if !val_name.is_empty() {
                        // Odd byte in position 0 (e.g., 0x03) marks entry disabled in Task Manager
                        let enabled = (data[0] & 1) == 0;
                        out.insert(val_name, enabled);
                    }
                }
            }
            let _ = RegCloseKey(hkey);
        }
        out
    }

    pub fn enumerate_windows_startup_raw(
    ) -> Vec<(String, String, String, String, String, String, bool)> {
        // Returns (id, name, display_name, source, source_label, target, enabled)
        let mut out: Vec<(String, String, String, String, String, String, bool)> = Vec::new();

        let hkcu_run_app = read_startup_approved_map(
            HKEY_CURRENT_USER,
            r"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run",
        );
        let hklm_run_app = read_startup_approved_map(
            HKEY_LOCAL_MACHINE,
            r"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run",
        );
        let hklm32_run_app = read_startup_approved_map(
            HKEY_LOCAL_MACHINE,
            r"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32",
        );
        let hkcu_folder_app = read_startup_approved_map(
            HKEY_CURRENT_USER,
            r"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder",
        );
        let hklm_folder_app = read_startup_approved_map(
            HKEY_LOCAL_MACHINE,
            r"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder",
        );

        let run_sources = [
            (
                HKEY_CURRENT_USER,
                r"Software\Microsoft\Windows\CurrentVersion\Run",
                "hkcu_run",
                "Реестр пользователя",
                &hkcu_run_app,
            ),
            (
                HKEY_LOCAL_MACHINE,
                r"Software\Microsoft\Windows\CurrentVersion\Run",
                "hklm_run",
                "Реестр системы",
                &hklm_run_app,
            ),
            (
                HKEY_LOCAL_MACHINE,
                r"Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
                "hklm32_run",
                "Реестр системы (32-bit)",
                &hklm32_run_app,
            ),
        ];

        for (hive, subkey, source, label, approved) in run_sources {
            unsafe {
                let mut hkey: usize = 0;
                let sub_w = to_wide(subkey);
                if RegOpenKeyExW(hive, sub_w.as_ptr(), 0, KEY_READ, &mut hkey) != 0 {
                    continue;
                }
                let mut index: u32 = 0;
                loop {
                    let mut name_buf = [0u16; 260];
                    let mut name_len: u32 = name_buf.len() as u32;
                    let mut reg_type: u32 = 0;
                    let mut data_buf = [0u8; 2048];
                    let mut data_len: u32 = data_buf.len() as u32;
                    let res = RegEnumValueW(
                        hkey,
                        index,
                        name_buf.as_mut_ptr(),
                        &mut name_len,
                        std::ptr::null(),
                        &mut reg_type,
                        data_buf.as_mut_ptr(),
                        &mut data_len,
                    );
                    if res != 0 {
                        break;
                    }
                    index += 1;
                    if reg_type != REG_SZ && reg_type != REG_EXPAND_SZ {
                        continue;
                    }
                    let name = String::from_utf16_lossy(&name_buf[..(name_len as usize)])
                        .trim()
                        .to_string();
                    if name.is_empty() {
                        continue;
                    }
                    let u16_count = (data_len as usize) / 2;
                    let wide_slice = std::slice::from_raw_parts(
                        data_buf.as_ptr() as *const u16,
                        u16_count,
                    );
                    let end = wide_slice.iter().position(|&c| c == 0).unwrap_or(wide_slice.len());
                    let target = String::from_utf16_lossy(&wide_slice[..end])
                        .trim()
                        .to_string();
                    let enabled = *approved.get(&name.to_lowercase()).unwrap_or(&true);
                    out.push((
                        format!("{}:{}", source, name),
                        name.clone(),
                        name,
                        source.to_string(),
                        label.to_string(),
                        target,
                        enabled,
                    ));
                }
                let _ = RegCloseKey(hkey);
            }
        }

        // Startup folders (.lnk / .url)
        let mut folder_sources: Vec<(std::path::PathBuf, &str, &str, &std::collections::HashMap<String, bool>)> = Vec::new();
        if let Some(appdata) = std::env::var_os("APPDATA") {
            folder_sources.push((
                std::path::PathBuf::from(appdata).join(r"Microsoft\Windows\Start Menu\Programs\Startup"),
                "startup_user",
                "Папка автозагрузки",
                &hkcu_folder_app,
            ));
        }
        if let Some(progdata) = std::env::var_os("ProgramData").or_else(|| std::env::var_os("ALLUSERSPROFILE")) {
            folder_sources.push((
                std::path::PathBuf::from(progdata).join(r"Microsoft\Windows\Start Menu\Programs\Startup"),
                "startup_common",
                "Общая папка автозагрузки",
                &hklm_folder_app,
            ));
        }
        for (dir, source, label, approved) in folder_sources {
            if let Ok(entries) = std::fs::read_dir(&dir) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    let ext_ok = path
                        .extension()
                        .and_then(|e| e.to_str())
                        .map(|e| e.eq_ignore_ascii_case("lnk") || e.eq_ignore_ascii_case("url"))
                        .unwrap_or(false);
                    if !ext_ok {
                        continue;
                    }
                    let file_name = path
                        .file_name()
                        .and_then(|s| s.to_str())
                        .unwrap_or("")
                        .to_string();
                    let stem = path
                        .file_stem()
                        .and_then(|s| s.to_str())
                        .unwrap_or(&file_name)
                        .trim()
                        .to_string();
                    if stem.is_empty() {
                        continue;
                    }
                    let enabled = *approved.get(&file_name.to_lowercase()).unwrap_or(&true);
                    out.push((
                        format!("{}:{}", source, file_name),
                        stem,
                        file_name,
                        source.to_string(),
                        label.to_string(),
                        path.to_string_lossy().into_owned(),
                        enabled,
                    ));
                }
            }
        }

        // UWP AppModel startup tasks
        let uwp_root = r"Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData";
        unsafe {
            let mut h_root: usize = 0;
            let root_w = to_wide(uwp_root);
            if RegOpenKeyExW(
                HKEY_CURRENT_USER,
                root_w.as_ptr(),
                0,
                KEY_READ | KEY_ENUMERATE_SUB_KEYS,
                &mut h_root,
            ) == 0
            {
                let mut pkg_idx: u32 = 0;
                loop {
                    let mut pkg_buf = [0u16; 260];
                    let mut pkg_len: u32 = pkg_buf.len() as u32;
                    if RegEnumKeyExW(
                        h_root,
                        pkg_idx,
                        pkg_buf.as_mut_ptr(),
                        &mut pkg_len,
                        std::ptr::null(),
                        std::ptr::null_mut(),
                        std::ptr::null_mut(),
                        std::ptr::null_mut(),
                    ) != 0
                    {
                        break;
                    }
                    pkg_idx += 1;
                    let pkg_name = String::from_utf16_lossy(&pkg_buf[..(pkg_len as usize)])
                        .trim()
                        .to_string();
                    if pkg_name.is_empty() {
                        continue;
                    }
                    let pkg_sub = format!(r"{}\{}", uwp_root, pkg_name);
                    let pkg_sub_w = to_wide(&pkg_sub);
                    let mut h_pkg: usize = 0;
                    if RegOpenKeyExW(
                        HKEY_CURRENT_USER,
                        pkg_sub_w.as_ptr(),
                        0,
                        KEY_READ | KEY_ENUMERATE_SUB_KEYS,
                        &mut h_pkg,
                    ) != 0
                    {
                        continue;
                    }
                    let mut task_idx: u32 = 0;
                    loop {
                        let mut task_buf = [0u16; 260];
                        let mut task_len: u32 = task_buf.len() as u32;
                        if RegEnumKeyExW(
                            h_pkg,
                            task_idx,
                            task_buf.as_mut_ptr(),
                            &mut task_len,
                            std::ptr::null(),
                            std::ptr::null_mut(),
                            std::ptr::null_mut(),
                            std::ptr::null_mut(),
                        ) != 0
                        {
                            break;
                        }
                        task_idx += 1;
                        let task_name = String::from_utf16_lossy(&task_buf[..(task_len as usize)])
                            .trim()
                            .to_string();
                        if task_name.is_empty() {
                            continue;
                        }
                        let task_sub = format!(r"{}\{}", pkg_sub, task_name);
                        if let Some(state) = read_reg_dword_root(HKEY_CURRENT_USER, &task_sub, "State") {
                            let pkg_base = pkg_name
                                .rsplit_once('_')
                                .map(|(prefix, _)| prefix)
                                .unwrap_or(&pkg_name);
                            let short_name = pkg_base
                                .split_once('.')
                                .map(|(_, r)| r)
                                .unwrap_or(pkg_base);
                            let rule_key = if super::is_safe_identifier(pkg_base) {
                                pkg_base.to_string()
                            } else {
                                task_name.clone()
                            };
                            let display_name = if task_name.eq_ignore_ascii_case(short_name) {
                                short_name.to_string()
                            } else {
                                format!("{} ({})", short_name, task_name)
                            };
                            out.push((
                                format!("uwp:{}:{}", pkg_name, task_name),
                                rule_key,
                                display_name,
                                "uwp".to_string(),
                                "Приложение Microsoft Store".to_string(),
                                format!("{}\\{}", pkg_name, task_name),
                                state == 2,
                            ));
                        }
                    }
                    let _ = RegCloseKey(h_pkg);
                }
                let _ = RegCloseKey(h_root);
            }
        }

        out
    }

    pub fn enumerate_running_processes_raw() -> Vec<(u32, String, String, f64)> {
        let mut out = Vec::new();
        unsafe {
            let snap = CreateToolhelp32Snapshot(0x00000002, 0);
            if snap == -1 {
                return out;
            }
            let mut entry: PROCESSENTRY32W = std::mem::zeroed();
            entry.dw_size = std::mem::size_of::<PROCESSENTRY32W>() as u32;
            if Process32FirstW(snap, &mut entry) != 0 {
                loop {
                    let pid = entry.th32_process_id;
                    let end = entry
                        .sz_exe_file
                        .iter()
                        .position(|&c| c == 0)
                        .unwrap_or(entry.sz_exe_file.len());
                    let raw_name = String::from_utf16_lossy(&entry.sz_exe_file[..end]);
                    let clean_name = super::strip_exe_suffix(&raw_name).trim().to_string();
                    if !clean_name.is_empty() {
                        let mut memory_mb = 0.0;
                        let mut exe_path = String::new();
                        let mut h_proc = OpenProcess(0x1010, 0, pid);
                        if h_proc == 0 {
                            h_proc = OpenProcess(0x1000, 0, pid);
                        }
                        if h_proc != 0 {
                            let mut mem: PROCESS_MEMORY_COUNTERS = std::mem::zeroed();
                            mem.cb = std::mem::size_of::<PROCESS_MEMORY_COUNTERS>() as u32;
                            if K32GetProcessMemoryInfo(h_proc, &mut mem, mem.cb) != 0 {
                                memory_mb = ((mem.working_set_size as f64) / (1024.0 * 1024.0) * 10.0)
                                    .round()
                                    / 10.0;
                            }
                            let mut path_buf = [0u16; 512];
                            let mut path_len = path_buf.len() as u32;
                            if QueryFullProcessImageNameW(
                                h_proc,
                                0,
                                path_buf.as_mut_ptr(),
                                &mut path_len,
                            ) != 0
                                && path_len > 0
                            {
                                exe_path = String::from_utf16_lossy(&path_buf[..(path_len as usize)])
                                    .trim()
                                    .to_string();
                            }
                            let _ = CloseHandle(h_proc);
                        }
                        out.push((pid, clean_name, exe_path, memory_mb));
                    }
                    entry = std::mem::zeroed();
                    entry.dw_size = std::mem::size_of::<PROCESSENTRY32W>() as u32;
                    if Process32NextW(snap, &mut entry) == 0 {
                        break;
                    }
                }
            }
            let _ = CloseHandle(snap);
        }
        out
    }

    pub fn terminate_process_win32(pid: u32, expected_name: &str) -> Result<String, String> {
        if pid <= 4 || pid == std::process::id() {
            return Err(format!(
                "Запрещено завершение защищённого или собственного PID {}",
                pid
            ));
        }
        let expected_clean = super::strip_exe_suffix(expected_name).trim();
        if !super::is_safe_identifier(expected_clean)
            || super::is_protected_process_name(expected_clean)
        {
            return Err(format!(
                "Процесс '{}' защищён от завершения.",
                expected_clean
            ));
        }

        unsafe {
            // PROCESS_TERMINATE (0x0001) | PROCESS_QUERY_LIMITED_INFORMATION (0x1000)
            let h_proc = OpenProcess(0x1001, 0, pid);
            if h_proc == 0 {
                let err = GetLastError();
                return Err(format!(
                    "Не удалось открыть процесс '{}' (PID {}): код Win32 {}",
                    expected_clean, pid, err
                ));
            }

            let mut path_buf = [0u16; 512];
            let mut path_len = path_buf.len() as u32;
            if QueryFullProcessImageNameW(h_proc, 0, path_buf.as_mut_ptr(), &mut path_len) != 0
                && path_len > 0
            {
                let full_path = String::from_utf16_lossy(&path_buf[..(path_len as usize)]);
                let actual_name = std::path::Path::new(&full_path)
                    .file_stem()
                    .and_then(|s| s.to_str())
                    .unwrap_or("")
                    .trim();
                if actual_name.is_empty()
                    || !actual_name.eq_ignore_ascii_case(expected_clean)
                    || super::is_protected_process_name(actual_name)
                {
                    let _ = CloseHandle(h_proc);
                    return Err(format!(
                        "Несовпадение имени процесса или попытка завершить защищённый процесс (PID {}: '{}').",
                        pid, actual_name
                    ));
                }
            } else {
                let _ = CloseHandle(h_proc);
                return Err(format!(
                    "Не удалось подтвердить образ процесса '{}' (PID {}). Завершение отменено.",
                    expected_clean, pid
                ));
            }

            let term_ok = TerminateProcess(h_proc, 1);
            let term_err = if term_ok == 0 { GetLastError() } else { 0 };
            let _ = CloseHandle(h_proc);

            if term_ok == 0 {
                return Err(format!(
                    "TerminateProcess не удалось для '{}' (PID {}): код Win32 {}",
                    expected_clean, pid, term_err
                ));
            }
        }

        Ok(format!(
            "Процесс '{}' (PID: {}) успешно завершён.",
            expected_clean, pid
        ))
    }

    fn enable_privilege(privilege_name: &str) -> bool {
        unsafe {
            let mut token: isize = 0;
            // TOKEN_ADJUST_PRIVILEGES (0x0020) | TOKEN_QUERY (0x0008)
            if OpenProcessToken(GetCurrentProcess(), 0x0028, &mut token) == 0 {
                return false;
            }
            let priv_w = to_wide(privilege_name);
            let mut luid = LUID {
                low_part: 0,
                high_part: 0,
            };
            if LookupPrivilegeValueW(std::ptr::null(), priv_w.as_ptr(), &mut luid) == 0 {
                let _ = CloseHandle(token);
                return false;
            }
            let tp = TOKEN_PRIVILEGES {
                privilege_count: 1,
                privileges: [LUID_AND_ATTRIBUTES {
                    luid,
                    attributes: 0x0000_0002, // SE_PRIVILEGE_ENABLED
                }],
            };
            let ok = AdjustTokenPrivileges(
                token,
                0,
                &tp,
                0,
                std::ptr::null_mut(),
                std::ptr::null_mut(),
            );
            let err = GetLastError();
            let _ = CloseHandle(token);
            ok != 0 && err == 0
        }
    }

    type NtSetSystemInformationFn =
        unsafe extern "system" fn(i32, *mut std::ffi::c_void, i32) -> i32;

    pub fn clean_memory_win32() -> Result<f64, String> {
        unsafe {
            let mut before_mem: MEMORYSTATUSEX = std::mem::zeroed();
            before_mem.dw_length = std::mem::size_of::<MEMORYSTATUSEX>() as u32;
            let before_avail = if GlobalMemoryStatusEx(&mut before_mem) != 0 {
                before_mem.ull_avail_phys
            } else {
                0
            };

            let _ = enable_privilege("SeProfileSingleProcessPrivilege");
            let _ = enable_privilege("SeIncreaseQuotaPrivilege");

            let ntdll = GetModuleHandleA(b"ntdll.dll\0".as_ptr());
            if ntdll.is_null() {
                return Err("Не удалось получить дескриптор ntdll.dll".to_string());
            }
            let fn_ptr = GetProcAddress(ntdll, b"NtSetSystemInformation\0".as_ptr());
            if fn_ptr.is_null() {
                return Err("Функция NtSetSystemInformation не найдена в ntdll.dll".to_string());
            }
            let nt_set: NtSetSystemInformationFn = std::mem::transmute(fn_ptr);
            let mut command: i32 = 4; // MemoryPurgeStandbyList
            let status = nt_set(
                80, // SystemMemoryListInformation
                &mut command as *mut i32 as *mut std::ffi::c_void,
                std::mem::size_of::<i32>() as i32,
            );
            if status < 0 {
                return Err(format!(
                    "NtSetSystemInformation(MemoryPurgeStandbyList) отклонена: NTSTATUS 0x{:08X} (требуются права администратора)",
                    status
                ));
            }

            let mut after_mem: MEMORYSTATUSEX = std::mem::zeroed();
            after_mem.dw_length = std::mem::size_of::<MEMORYSTATUSEX>() as u32;
            let after_avail = if GlobalMemoryStatusEx(&mut after_mem) != 0 {
                after_mem.ull_avail_phys
            } else {
                before_avail
            };

            let freed_bytes = after_avail.saturating_sub(before_avail);
            let freed_mb = ((freed_bytes as f64) / (1024.0 * 1024.0) * 10.0).round() / 10.0;
            Ok(freed_mb)
        }
    }

    pub fn control_service_win32(
        service_name: &str,
        operation: &str,
    ) -> Result<Result<String, u32>, String> {
        const SERVICE_NO_CHANGE: u32 = 0xFFFF_FFFF;
        const SERVICE_AUTO_START: u32 = 2;
        const SERVICE_DEMAND_START: u32 = 3;
        const SERVICE_DISABLED: u32 = 4;
        const SERVICE_CONTROL_STOP: u32 = 1;

        let desired_access: u32 = match operation {
            "Start" => 0x0017, // QUERY_CONFIG | CHANGE_CONFIG | QUERY_STATUS | START
            "Stop" => 0x0024,  // STOP | QUERY_STATUS
            "Automatic" | "Manual" | "Disabled" => 0x0002, // CHANGE_CONFIG
            _ => return Err(format!("Недопустимая операция над службой: {}", operation)),
        };

        unsafe {
            let scm = OpenSCManagerW(std::ptr::null(), std::ptr::null(), 0x0001);
            if scm == 0 {
                return Err(format!(
                    "Не удалось открыть диспетчер служб Windows (Win32 {})",
                    GetLastError()
                ));
            }

            let mut resolved_name = service_name.to_string();
            let mut svc_w = to_wide(&resolved_name);
            let mut h_svc = OpenServiceW(scm, svc_w.as_ptr(), desired_access);
            if h_svc == 0 && GetLastError() == 1060 {
                // Fallback for per-user template services like CDPUserSvc -> CDPUserSvc_XXXX
                let lower = service_name.to_lowercase();
                let prefix_under = format!("{}_", lower);
                let live = enumerate_live_services();
                if let Some((orig_name, _, _)) = live.iter().find(|(k, _)| {
                    k.starts_with(&prefix_under)
                        || (k.starts_with(&lower)
                            && k.len() > lower.len()
                            && k.as_bytes()[lower.len()].is_ascii_digit())
                }).map(|(_, v)| v) {
                    resolved_name = orig_name.clone();
                    svc_w = to_wide(&resolved_name);
                    h_svc = OpenServiceW(scm, svc_w.as_ptr(), desired_access);
                }
            }

            if h_svc == 0 {
                let err = GetLastError();
                let _ = CloseServiceHandle(scm);
                return Err(format!(
                    "Не удалось открыть службу '{}' (Win32 {})",
                    resolved_name, err
                ));
            }

            let result: Result<Result<String, u32>, String> = match operation {
                "Start" => {
                    let mut cfg_buf = vec![0u64; 1024];
                    let mut needed: u32 = 0;
                    if QueryServiceConfigW(
                        h_svc,
                        cfg_buf.as_mut_ptr() as *mut u8,
                        (cfg_buf.len() * 8) as u32,
                        &mut needed,
                    ) != 0
                    {
                        let cfg = &*(cfg_buf.as_ptr() as *const QUERY_SERVICE_CONFIGW);
                        if cfg.dw_start_type == SERVICE_DISABLED {
                            let _ = ChangeServiceConfigW(
                                h_svc,
                                SERVICE_NO_CHANGE,
                                SERVICE_DEMAND_START,
                                SERVICE_NO_CHANGE,
                                std::ptr::null(),
                                std::ptr::null(),
                                std::ptr::null_mut(),
                                std::ptr::null(),
                                std::ptr::null(),
                                std::ptr::null(),
                                std::ptr::null(),
                            );
                        }
                    }
                    if StartServiceW(h_svc, 0, std::ptr::null()) == 0 {
                        let err = GetLastError();
                        if err == 1056 {
                            Ok(Ok(format!("Служба '{}' уже запущена.", resolved_name)))
                        } else {
                            Err(format!(
                                "StartServiceW завершилась с ошибкой Win32 {} для '{}'",
                                err, resolved_name
                            ))
                        }
                    } else {
                        let mut st = SERVICE_STATUS::default();
                        for _ in 0..20 {
                            if QueryServiceStatus(h_svc, &mut st) == 0 || st.dw_current_state != 2 {
                                break;
                            }
                            std::thread::sleep(std::time::Duration::from_millis(75));
                        }
                        Ok(Ok(format!("Служба '{}' запущена.", resolved_name)))
                    }
                }
                "Stop" => {
                    let mut st = SERVICE_STATUS::default();
                    if ControlService(h_svc, SERVICE_CONTROL_STOP, &mut st) == 0 {
                        let err = GetLastError();
                        if err == 1062 {
                            Ok(Ok(format!("Служба '{}' уже остановлена.", resolved_name)))
                        } else if err == 1051 {
                            Ok(Err(1051))
                        } else {
                            Err(format!(
                                "ControlService(STOP) завершилась с ошибкой Win32 {} для '{}'",
                                err, resolved_name
                            ))
                        }
                    } else {
                        for _ in 0..20 {
                            if st.dw_current_state != 3 {
                                break;
                            }
                            std::thread::sleep(std::time::Duration::from_millis(75));
                            if QueryServiceStatus(h_svc, &mut st) == 0 {
                                break;
                            }
                        }
                        Ok(Ok(format!("Служба '{}' остановлена.", resolved_name)))
                    }
                }
                "Automatic" | "Manual" | "Disabled" => {
                    let target_start = match operation {
                        "Automatic" => SERVICE_AUTO_START,
                        "Manual" => SERVICE_DEMAND_START,
                        _ => SERVICE_DISABLED,
                    };
                    if ChangeServiceConfigW(
                        h_svc,
                        SERVICE_NO_CHANGE,
                        target_start,
                        SERVICE_NO_CHANGE,
                        std::ptr::null(),
                        std::ptr::null(),
                        std::ptr::null_mut(),
                        std::ptr::null(),
                        std::ptr::null(),
                        std::ptr::null(),
                        std::ptr::null(),
                    ) == 0
                    {
                        let err = GetLastError();
                        Err(format!(
                            "ChangeServiceConfigW завершилась с ошибкой Win32 {} для '{}'",
                            err, resolved_name
                        ))
                    } else {
                        Ok(Ok(format!(
                            "Тип запуска службы '{}' изменён на {}.",
                            resolved_name, operation
                        )))
                    }
                }
                _ => Err("Неизвестная операция".to_string()),
            };

            let _ = CloseServiceHandle(h_svc);
            let _ = CloseServiceHandle(scm);
            result
        }
    }

    pub fn confirm_reboot_dialog_win32() -> bool {
        unsafe {
            let text = to_wide("Перезагрузить компьютер сейчас?\nНесохранённые данные в открытых программах могут быть потеряны.");
            let caption = to_wide("Ultra Gaming Mode — Перезагрузка ПК");
            // MB_YESNO (0x04) | MB_ICONWARNING (0x30) | MB_DEFBUTTON2 (0x100) | MB_SETFOREGROUND (0x10000) | MB_TOPMOST (0x40000)
            let flags = 0x0004 | 0x0030 | 0x0100 | 0x1_0000 | 0x4_0000;
            MessageBoxW(0, text.as_ptr(), caption.as_ptr(), flags) == 6 // IDYES
        }
    }

    pub fn acquire_single_instance_or_wake(wake_existing: bool) -> Option<isize> {
        const ERROR_ALREADY_EXISTS: u32 = 183;
        const EVENT_MODIFY_STATE: u32 = 0x0002;
        unsafe {
            let mutex_name = to_wide(r"Local\UltraGamingMode_SingleInstance_v3");
            let h_mutex = CreateMutexW(std::ptr::null(), 0, mutex_name.as_ptr());
            if h_mutex != 0 && GetLastError() == ERROR_ALREADY_EXISTS {
                let _ = CloseHandle(h_mutex);
                if wake_existing {
                    let wake_name = to_wide(r"Local\UltraGamingMode_WakeWindow_v3");
                    let h_wake = OpenEventW(EVENT_MODIFY_STATE, 0, wake_name.as_ptr());
                    if h_wake != 0 {
                        let _ = SetEvent(h_wake);
                        let _ = CloseHandle(h_wake);
                    }
                }
                return None;
            }
            Some(h_mutex)
        }
    }

    pub fn create_wake_event() -> isize {
        unsafe {
            let wake_name = to_wide(r"Local\UltraGamingMode_WakeWindow_v3");
            CreateEventW(std::ptr::null(), 0, 0, wake_name.as_ptr())
        }
    }

    pub fn wait_wake_event_ms(handle: isize, timeout_ms: u32) -> bool {
        if handle == 0 {
            std::thread::sleep(std::time::Duration::from_millis(timeout_ms as u64));
            return false;
        }
        unsafe { WaitForSingleObject(handle, timeout_ms) == 0 }
    }
}

#[cfg(target_os = "windows")]
mod timer {
    type NtQueryTimerResolutionFn = unsafe extern "system" fn(*mut u32, *mut u32, *mut u32) -> i32;
    type NtSetTimerResolutionFn = unsafe extern "system" fn(u32, u8, *mut u32) -> i32;

    extern "system" {
        fn GetModuleHandleA(lpModuleName: *const u8) -> *mut std::ffi::c_void;
        fn GetProcAddress(
            hModule: *mut std::ffi::c_void,
            lpProcName: *const u8,
        ) -> *mut std::ffi::c_void;
    }

    pub fn query_timer_resolution() -> Option<f64> {
        unsafe {
            let ntdll = GetModuleHandleA(b"ntdll.dll\0".as_ptr());
            if ntdll.is_null() {
                return None;
            }
            let query_fn_ptr = GetProcAddress(ntdll, b"NtQueryTimerResolution\0".as_ptr());
            if query_fn_ptr.is_null() {
                return None;
            }
            let query_fn: NtQueryTimerResolutionFn = std::mem::transmute(query_fn_ptr);
            let mut min_res: u32 = 0;
            let mut max_res: u32 = 0;
            let mut cur_res: u32 = 0;
            if query_fn(&mut min_res, &mut max_res, &mut cur_res) >= 0 && cur_res > 0 {
                Some(cur_res as f64 / 10000.0)
            } else {
                None
            }
        }
    }

    pub fn set_timer_resolution(desired_100ns: u32) -> Result<(f64, f64), String> {
        unsafe {
            let ntdll = GetModuleHandleA(b"ntdll.dll\0".as_ptr());
            if ntdll.is_null() {
                return Err("Не удалось получить дескриптор ntdll.dll".into());
            }

            let query_fn_ptr = GetProcAddress(ntdll, b"NtQueryTimerResolution\0".as_ptr());
            let set_fn_ptr = GetProcAddress(ntdll, b"NtSetTimerResolution\0".as_ptr());

            if query_fn_ptr.is_null() || set_fn_ptr.is_null() {
                return Err("Не удалось найти функции NtTimer".into());
            }

            let query_fn: NtQueryTimerResolutionFn = std::mem::transmute(query_fn_ptr);
            let set_fn: NtSetTimerResolutionFn = std::mem::transmute(set_fn_ptr);

            let mut min_res: u32 = 0;
            let mut max_res: u32 = 0;
            let mut cur_res: u32 = 0;
            let _ = query_fn(&mut min_res, &mut max_res, &mut cur_res);

            let target = if desired_100ns < max_res {
                max_res
            } else {
                desired_100ns
            };
            let mut final_res: u32 = 0;
            let status = set_fn(target, 1, &mut final_res);

            if status >= 0 {
                super::TIMER_LOCKED.store(true, std::sync::atomic::Ordering::SeqCst);
                let cur_ms = final_res as f64 / 10000.0;
                let max_ms = max_res as f64 / 10000.0;
                Ok((cur_ms, max_ms))
            } else {
                Err(format!("Ошибка NtSetTimerResolution: 0x{:08X}", status))
            }
        }
    }

    pub fn unlock_timer_resolution() -> Result<f64, String> {
        unsafe {
            let ntdll = GetModuleHandleA(b"ntdll.dll\0".as_ptr());
            if ntdll.is_null() {
                return Err("Не удалось получить дескриптор ntdll.dll".into());
            }
            let set_fn_ptr = GetProcAddress(ntdll, b"NtSetTimerResolution\0".as_ptr());
            if set_fn_ptr.is_null() {
                return Err("Не удалось найти функцию NtSetTimerResolution".into());
            }
            let set_fn: NtSetTimerResolutionFn = std::mem::transmute(set_fn_ptr);
            let mut final_res: u32 = 0;
            let status = set_fn(5000, 0, &mut final_res);
            super::TIMER_LOCKED.store(false, std::sync::atomic::Ordering::SeqCst);
            if status >= 0 || status == -1073741240 /* STATUS_TIMER_RESOLUTION_NOT_SET */ {
                let queried = query_timer_resolution().unwrap_or(final_res as f64 / 10000.0);
                Ok(queried)
            } else {
                Err(format!("Ошибка сброса NtSetTimerResolution: 0x{:08X}", status))
            }
        }
    }
}

#[cfg(not(target_os = "windows"))]
mod timer {
    pub fn query_timer_resolution() -> Option<f64> {
        Some(0.5)
    }
    pub fn set_timer_resolution(_desired_100ns: u32) -> Result<(f64, f64), String> {
        super::TIMER_LOCKED.store(true, std::sync::atomic::Ordering::SeqCst);
        Ok((0.5, 0.5))
    }
    pub fn unlock_timer_resolution() -> Result<f64, String> {
        super::TIMER_LOCKED.store(false, std::sync::atomic::Ordering::SeqCst);
        Ok(15.6)
    }
}

#[derive(Serialize, Deserialize, Clone)]
pub struct SystemStatus {
    pub mode: String,
    pub profile: String,
    pub hardware: HardwareInfo,
    #[serde(rename = "activeSince")]
    pub active_since: Option<String>,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct ActionResult {
    pub success: bool,
    pub message: String,
}

fn is_dev_repo_root(dir: &Path) -> bool {
    dir.join("UltraGamingMode.ps1").exists()
        && dir.join("Core").join("StateEngine.ps1").exists()
        && (dir.join(".git").exists() || dir.join("Build-Release.ps1").exists())
}

fn is_dir_writable(dir: &Path) -> bool {
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

fn sync_embedded_runtime(root: &Path) -> Result<(), String> {
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
            std::fs::write(&dest, asset.bytes).map_err(|e| {
                format!(
                    "Не удалось записать встроенный ресурс {}: {}",
                    dest.display(),
                    e
                )
            })?;
        }
    }

    Ok(())
}

fn ensure_backups_writable(root: &Path) {
    let backups_dir = root.join("Backups");
    let user_quarantine_dir = backups_dir.join("QuarantinedShortcuts").join("User");
    let _ = std::fs::create_dir_all(&user_quarantine_dir);

    #[cfg(target_os = "windows")]
    {
        BACKUPS_ACL_INIT.get_or_init(|| {
            // Restrict non-admin write access ONLY to User startup shortcut quarantine (not active_state.json or ProgramData shortcuts),
            // preventing Local Privilege Escalation via HKLM/SYSTEM state injection.
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

fn standalone_runtime_candidates() -> Vec<PathBuf> {
    let mut out = Vec::new();
    #[cfg(target_os = "windows")]
    {
        if let Some(pf) = std::env::var_os("ProgramW6432")
            .or_else(|| std::env::var_os("ProgramFiles"))
        {
            out.push(PathBuf::from(pf).join("UltraGamingMode"));
        } else {
            out.push(PathBuf::from(r"C:\Program Files\UltraGamingMode"));
        }
        if let Some(pd) = std::env::var_os("ProgramData")
            .or_else(|| std::env::var_os("ALLUSERSPROFILE"))
        {
            out.push(PathBuf::from(pd).join("UltraGamingMode"));
        } else {
            out.push(PathBuf::from(r"C:\ProgramData\UltraGamingMode"));
        }
        #[cfg(any(debug_assertions, test))]
        if let Some(local) = std::env::var_os("LOCALAPPDATA") {
            out.push(PathBuf::from(local).join("UltraGamingMode").join("Runtime"));
        }
    }
    #[cfg(any(debug_assertions, test, not(target_os = "windows")))]
    out.push(std::env::temp_dir().join("UltraGamingMode"));
    out
}

fn resolve_runtime_root_fresh() -> PathBuf {
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
        if let Some(repo_root) = manifest_dir.parent().and_then(|p| p.parent()) {
            if is_dev_repo_root(repo_root) {
                return repo_root.to_path_buf();
            }
        }
    }

    // Installed bundle (NSIS/MSI placed scripts beside exe via bundle.resources)
    if let Ok(exe) = std::env::current_exe() {
        if let Some(exe_dir) = exe.parent() {
            if exe_dir.join("UltraGamingMode.ps1").exists() && is_dir_writable(exe_dir) {
                let _ = sync_embedded_runtime(exe_dir);
                ensure_backups_writable(exe_dir);
                return exe_dir.to_path_buf();
            }
        }
    }

    // Single-file portable UltraGamingMode.exe or read-only install directory:
    // materialize all scripts & configs into a shared writable runtime location.
    for candidate in standalone_runtime_candidates() {
        if std::fs::create_dir_all(&candidate).is_ok()
            && is_dir_writable(&candidate)
            && sync_embedded_runtime(&candidate).is_ok()
        {
            ensure_backups_writable(&candidate);
            return candidate;
        }
    }

    std::env::current_dir().unwrap_or_default()
}

fn get_workspace_root() -> PathBuf {
    let root = RUNTIME_ROOT_CACHE
        .get_or_init(resolve_runtime_root_fresh)
        .clone();
    if !is_dev_repo_root(&root) && !root.join("UltraGamingMode.ps1").exists() {
        let _ = sync_embedded_runtime(&root);
    }
    root
}

fn resolve_system32_binary(binary_name: &str) -> Option<PathBuf> {
    std::env::var_os("SystemRoot").map(|sys_root| {
        PathBuf::from(sys_root)
            .join("System32")
            .join(binary_name)
    })
}

fn resolve_powershell_exe() -> PathBuf {
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
fn decode_oem_line(bytes: &[u8]) -> Option<String> {
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
        let cp = GetOEMCP();
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

fn decode_powershell_output(bytes: &[u8]) -> String {
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

fn load_tuning_from_disk(root: &PathBuf) -> TuningConfig {
    let tuning_path = root.join("Config").join("tuning.json");
    if let Ok(raw) = std::fs::read_to_string(&tuning_path) {
        let clean = raw.trim_start_matches('\u{feff}');
        if let Ok(cfg) = serde_json::from_str::<TuningConfig>(clean) {
            return cfg;
        }
    }
    TuningConfig::default()
}

fn write_tuning_to_disk(root: &Path, cfg: &TuningConfig) -> Result<(), String> {
    let config_dir = root.join("Config");
    std::fs::create_dir_all(&config_dir)
        .map_err(|e| format!("Не удалось создать папку Config: {}", e))?;
    let tuning_path = config_dir.join("tuning.json");
    let mut safe_cfg = cfg.clone();
    safe_cfg.input_buffer_queue_size = safe_cfg.input_buffer_queue_size.clamp(32, 1024);
    let serialized = serde_json::to_string_pretty(&safe_cfg)
        .map_err(|e| format!("Ошибка сериализации tuning.json: {}", e))?;
    std::fs::write(&tuning_path, serialized.as_bytes())
        .map_err(|e| format!("Не удалось записать tuning.json: {}", e))
}

fn resolve_profile_name(cfg: &TuningConfig) -> String {
    if cfg.disable_fullscreen_optimizations
        && !cfg.disable_mouse_accel
        && !cfg.disable_nvidia_dynamic_pstate
        && cfg.enable_net_adapter_msi
        && cfg.input_buffer_queue_size == 100
    {
        "competitive".to_string()
    } else if !cfg.disable_fullscreen_optimizations
        && !cfg.disable_mouse_accel
        && !cfg.disable_nvidia_dynamic_pstate
        && cfg.enable_net_adapter_msi
        && cfg.input_buffer_queue_size == 100
    {
        "aaa".to_string()
    } else {
        "custom".to_string()
    }
}

fn infer_service_category(name: &str, reason: &str) -> String {
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

fn invalidate_active_state_cache() {
    if let Ok(mut guard) = ACTIVE_STATE_CACHE.lock() {
        *guard = None;
    }
}

fn read_cached_active_state(root: &Path) -> Option<CachedActiveState> {
    let active_state_path = root.join("Backups").join("active_state.json");
    let meta = std::fs::metadata(&active_state_path).ok()?;
    let modified = meta.modified().ok();
    let len = meta.len();

    if let Ok(guard) = ACTIVE_STATE_CACHE.lock() {
        if let Some(cached) = guard.as_ref() {
            if cached.path == active_state_path
                && cached.modified == modified
                && cached.len == len
            {
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

fn read_current_mode_fast(root: &Path) -> String {
    read_cached_active_state(root)
        .map(|s| s.mode)
        .unwrap_or_else(|| "Normal".to_string())
}

fn load_service_descriptions_map(
    root: &Path,
) -> std::collections::HashMap<String, ServiceDescriptionEntry> {
    let disk_path = root.join("Config").join("service_descriptions.json");
    let raw = std::fs::read_to_string(&disk_path).unwrap_or_else(|_| {
        String::from_utf8_lossy(include_bytes!("../../../Config/service_descriptions.json"))
            .into_owned()
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

fn lookup_service_description<'a>(
    map: &'a std::collections::HashMap<String, ServiceDescriptionEntry>,
    service_name: &str,
) -> Option<&'a ServiceDescriptionEntry> {
    let trimmed = service_name.trim();
    let lower = trimmed.to_lowercase();
    if let Some(entry) = map.get(&lower) {
        return Some(entry);
    }
    let base = strip_per_user_service_suffix(trimmed).to_lowercase();
    map.get(&base)
}

fn get_cached_hw_static() -> &'static CachedHardwareStatic {
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

fn read_system_status_sync() -> Result<SystemStatus, String> {
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

    let tuning = load_tuning_from_disk(&root);
    let profile = resolve_profile_name(&tuning);

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

    let timer_resolution = timer::query_timer_resolution()
        .map(|ms| format!("{:.3} мс", ms))
        .or_else(|| Some("1.000 мс (штатный)".into()));

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

#[tauri::command]
async fn get_system_status() -> Result<SystemStatus, String> {
    tauri::async_runtime::spawn_blocking(read_system_status_sync)
        .await
        .map_err(|e| format!("Сбой фоновой задачи статуса: {}", e))?
}

fn read_tuning_config_sync() -> Result<TuningConfig, String> {
    let root = get_workspace_root();
    Ok(load_tuning_from_disk(&root))
}

#[tauri::command]
async fn get_tuning_config() -> Result<TuningConfig, String> {
    tauri::async_runtime::spawn_blocking(read_tuning_config_sync)
        .await
        .map_err(|e| format!("Сбой фоновой задачи конфигурации: {}", e))?
}

fn should_trigger_live_tuning(raw_state: &str) -> bool {
    let clean_state = raw_state.trim_start_matches('\u{feff}');
    if let Ok(state_val) = serde_json::from_str::<serde_json::Value>(clean_state) {
        if let Some(state_str) = state_val.get("State").and_then(|v| v.as_str()) {
            return state_str == "Armed" || state_str == "GameMode_Active";
        }
    }
    false
}

fn write_tuning_config_sync(config: TuningConfig) -> Result<TuningConfig, String> {
    let root = get_workspace_root();
    let mut normalized = config;
    normalized.input_buffer_queue_size = normalized.input_buffer_queue_size.clamp(32, 1024);
    write_tuning_to_disk(&root, &normalized)?;

    let active_state_path = root.join("Backups").join("active_state.json");
    if let Ok(raw_state) = std::fs::read_to_string(&active_state_path) {
        if should_trigger_live_tuning(&raw_state) {
            let script_path = root.join("UltraGamingMode.ps1");
            let mut cmd = Command::new(resolve_powershell_exe());
            cmd.current_dir(&root).args([
                "-NoProfile",
                "-NonInteractive",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                script_path.to_str().unwrap_or("UltraGamingMode.ps1"),
                "-Action",
                "ApplyTuning",
                "-SkipUpdateCheck",
            ]);
            #[cfg(target_os = "windows")]
            cmd.creation_flags(CREATE_NO_WINDOW);
            let _ = cmd.spawn();
        }
    }

    Ok(normalized)
}

#[tauri::command]
async fn save_tuning_config(config: TuningConfig) -> Result<TuningConfig, String> {
    tauri::async_runtime::spawn_blocking(move || write_tuning_config_sync(config))
        .await
        .map_err(|e| format!("Сбой сохранения конфигурации: {}", e))?
}

fn read_services_lists_from_root(
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
        let lower = svc_name.trim().to_lowercase();
        if let Some(exact) = live_map.get(&lower) {
            return Some(exact);
        }
        let prefix_under = format!("{}_", lower);
        for (k, v) in &live_map {
            if k.starts_with(&prefix_under)
                || (k.starts_with(&lower)
                    && k.len() > lower.len()
                    && k.as_bytes()[lower.len()].is_ascii_digit())
            {
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
            if let Some(desc) = lookup_service_description(&desc_map, &parsed.name) {
                if parsed.summary_ru.trim().is_empty() {
                    parsed.summary_ru = desc.summary_ru.clone();
                }
                if parsed.can_disable_hint.trim().is_empty() {
                    parsed.can_disable_hint = desc.can_disable_ru.clone();
                }
            }
            bl_category_map.insert(parsed.name.to_lowercase(), parsed.category.clone());
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
            let summary_ru = desc.map(|d| d.summary_ru.clone()).unwrap_or_default();
            let can_disable_hint = desc.map(|d| d.can_disable_ru.clone()).unwrap_or_default();
            whitelist_items.push(WhitelistServiceItem {
                name: s.to_string(),
                display_name,
                status,
                is_core_locked: is_immutable_core_service(s),
                summary_ru,
                can_disable_hint,
            });
            whitelist.push(s.to_string());
        }
    }

    let in_whitelist = |svc: &str| -> bool {
        let base = strip_per_user_service_suffix(svc);
        whitelist
            .iter()
            .any(|w| w.eq_ignore_ascii_case(svc) || w.eq_ignore_ascii_case(base))
    };
    let in_blacklist = |svc: &str| -> bool {
        let base = strip_per_user_service_suffix(svc);
        blacklist
            .iter()
            .any(|b| b.name.eq_ignore_ascii_case(svc) || b.name.eq_ignore_ascii_case(base))
    };

    let mut all_installed_services: Vec<InstalledServiceItem> = Vec::new();
    if include_live_status {
        for (orig_name, status, scm_disp) in live_map.values() {
            let is_core = is_immutable_core_service(orig_name);
            let membership = if is_core {
                "core"
            } else if in_whitelist(orig_name) {
                "whitelist"
            } else if in_blacklist(orig_name) {
                "blacklist"
            } else {
                "none"
            }
            .to_string();

            let disp = if scm_disp.trim().is_empty() {
                orig_name.clone()
            } else {
                scm_disp.trim().to_string()
            };
            let base = strip_per_user_service_suffix(orig_name);
            let cat = bl_category_map
                .get(&orig_name.to_lowercase())
                .or_else(|| bl_category_map.get(&base.to_lowercase()))
                .cloned()
                .unwrap_or_else(|| infer_service_category(orig_name, &disp));
            let desc = lookup_service_description(&desc_map, orig_name);
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
                summary_ru: desc.map(|d| d.summary_ru.clone()).unwrap_or_default(),
                can_disable_hint: desc.map(|d| d.can_disable_ru.clone()).unwrap_or_default(),
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

fn apply_service_feature_pack_in_root(
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
                .any(|s| s.eq_ignore_ascii_case(svc))
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
                !pack.services.iter().any(|s| s.eq_ignore_ascii_case(name))
            });
        }
    } else {
        wl_arr.retain(|v| {
            let Some(name) = v.as_str() else { return true };
            if is_immutable_core_service(name) {
                return true;
            }
            !pack.services.iter().any(|s| s.eq_ignore_ascii_case(name))
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
                    .map(|n| n.eq_ignore_ascii_case(svc))
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

#[tauri::command]
async fn apply_service_feature_pack(
    pack_id: String,
    keep_enabled_in_game: bool,
) -> Result<ServicesLists, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let root = get_workspace_root();
        apply_service_feature_pack_in_root(
            &root,
            &pack_id,
            keep_enabled_in_game,
            cfg!(target_os = "windows"),
        )
    })
    .await
    .map_err(|e| format!("Сбой обновления пакета функций служб: {}", e))?
}

fn read_services_lists_sync() -> Result<ServicesLists, String> {
    let root = get_workspace_root();
    read_services_lists_from_root(&root, cfg!(target_os = "windows"))
}

#[tauri::command]
async fn get_services_lists() -> Result<ServicesLists, String> {
    tauri::async_runtime::spawn_blocking(read_services_lists_sync)
        .await
        .map_err(|e| format!("Сбой загрузки списков служб: {}", e))?
}

fn run_powershell_script(
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
        .args(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script_str])
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

    Ok(ActionResult { success, message })
}

#[tauri::command]
fn set_window_theme(window: tauri::WebviewWindow, dark: bool) -> Result<(), String> {
    let (theme, bg) = if dark {
        (tauri::Theme::Dark, tauri::window::Color(12, 14, 18, 255))
    } else {
        (tauri::Theme::Light, tauri::window::Color(244, 246, 250, 255))
    };
    let _ = window.set_background_color(Some(bg));
    let _ = window.set_theme(Some(theme));
    Ok(())
}

fn run_execute_mode_action_sync(
    action: &str,
    profile: &str,
) -> Result<ActionResult, String> {
    let Some(_mode_guard) = try_acquire_mode_action_guard() else {
        return Err("Операция переключения режима уже выполняется. Дождитесь завершения.".to_string());
    };
    let root = get_workspace_root();
    let script_path = root.join("UltraGamingMode.ps1");

    if action == "Enable" {
        let mut current = load_tuning_from_disk(&root);
        match profile {
            "competitive" => {
                current.disable_fullscreen_optimizations = true;
                current.disable_mouse_accel = false;
                current.disable_nvidia_dynamic_pstate = false;
                current.enable_net_adapter_msi = true;
                current.input_buffer_queue_size = 100;
                let _ = write_tuning_to_disk(&root, &current);
            }
            "aaa" => {
                current.disable_fullscreen_optimizations = false;
                current.disable_mouse_accel = false;
                current.disable_nvidia_dynamic_pstate = false;
                current.enable_net_adapter_msi = true;
                current.input_buffer_queue_size = 100;
                let _ = write_tuning_to_disk(&root, &current);
            }
            _ => {}
        }
    }

    let res = run_powershell_script(
        &root,
        &script_path,
        &["-Action", action, "-SkipUpdateCheck"],
        format!("Действие [{}] выполнено успешно.", action),
        "Не удалось запустить PowerShell",
    );
    if action == "Restore" {
        if TIMER_LOCKED.swap(false, Ordering::SeqCst) {
            let _ = timer::unlock_timer_resolution();
        }
    }
    invalidate_active_state_cache();
    res
}

fn run_finish_pending_restore_sync() -> Result<ActionResult, String> {
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

#[tauri::command]
async fn finish_pending_restore(app: tauri::AppHandle) -> Result<ActionResult, String> {
    let result = tauri::async_runtime::spawn_blocking(run_finish_pending_restore_sync)
        .await
        .map_err(|e| format!("Сбой завершения восстановления: {}", e))?;
    sync_tray_and_emit(&app, true);
    result
}

#[tauri::command]
async fn execute_mode_action(
    app: tauri::AppHandle,
    action: String,
    profile: String,
) -> Result<ActionResult, String> {
    let safe_action = match action.as_str() {
        "Enable" => "Enable",
        "Restore" => "Restore",
        _ => return Err(format!("Недопустимое действие режима: {}", action)),
    };
    let safe_profile = match profile.as_str() {
        "competitive" => "competitive",
        "aaa" => "aaa",
        "custom" => "custom",
        _ => return Err(format!("Недопустимый профиль оптимизации: {}", profile)),
    };

    let result = tauri::async_runtime::spawn_blocking(move || {
        run_execute_mode_action_sync(safe_action, safe_profile)
    })
    .await
    .map_err(|e| format!("Сбой фонового выполнения PowerShell: {}", e))?;

    sync_tray_and_emit(&app, true);
    result
}

fn clear_dir_contents(dir: &Path) -> (usize, u64) {
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

fn clean_memory_native_sync() -> Result<ActionResult, String> {
    #[cfg(target_os = "windows")]
    {
        let freed_mb = win_hw::clean_memory_win32()?;
        Ok(ActionResult {
            success: true,
            message: format!(
                "Кэш ОЗУ (Standby List) очищен. Освобождено {:.1} МБ.",
                freed_mb
            ),
        })
    }
    #[cfg(not(target_os = "windows"))]
    {
        Ok(ActionResult {
            success: true,
            message: "Кэш ОЗУ очищен (симуляция вне Windows).".to_string(),
        })
    }
}

#[tauri::command]
async fn execute_emergency_repair(
    app: tauri::AppHandle,
    repair_type: String,
) -> Result<ActionResult, String> {
    let kind = repair_type.clone();
    let result = tauri::async_runtime::spawn_blocking(move || {
        match kind.as_str() {
            "memory" => return clean_memory_native_sync(),
            "shaders" => {
                let local = std::env::var_os("LOCALAPPDATA").map(PathBuf::from);
                let roaming = std::env::var_os("APPDATA").map(PathBuf::from);
                let (files, mb) =
                    flush_shader_cache_native_impl(local.as_deref(), roaming.as_deref());
                return Ok(ActionResult {
                    success: true,
                    message: format!(
                        "Кэш шейдеров GPU очищен: удалено {} файлов ({:.1} МБ).",
                        files, mb
                    ),
                });
            }
            _ => {}
        }

        let root = get_workspace_root();
        let script_path = root.join("UltraGamingMode.ps1");

        let (args, script_to_run): (Vec<&'static str>, PathBuf) = match kind.as_str() {
            "display" => (vec!["-Action", "RepairDisplay", "-SkipUpdateCheck"], script_path),
            "services" => (vec!["-Action", "RepairServices", "-SkipUpdateCheck"], script_path),
            "debloat" => (vec!["-Action", "Debloat", "-SkipUpdateCheck"], script_path),
            "restore_debloat" => (
                vec!["-Action", "RestoreDebloat", "-SkipUpdateCheck"],
                script_path,
            ),
            "verify" => (Vec::new(), root.join("Tests").join("Verify-UniversalEngine.ps1")),
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
    })
    .await
    .map_err(|e| format!("Сбой фоновой операции обслуживания: {}", e))?;

    sync_tray_and_emit(&app, false);
    result
}

#[tauri::command]
fn close_window(window: tauri::WebviewWindow) {
    // Destroy the WebView2 window so zero msedgewebview2 processes remain in RAM while idle;
    // RunEvent::ExitRequested keeps the lightweight Rust tray host alive.
    let _ = window.destroy();
}

#[tauri::command]
fn exit_app(app: tauri::AppHandle) {
    ALLOW_APP_EXIT.store(true, Ordering::SeqCst);
    app.exit(0);
}

fn reboot_pc_sync() -> Result<ActionResult, String> {
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
    })
}

#[tauri::command]
async fn reboot_pc() -> Result<ActionResult, String> {
    tauri::async_runtime::spawn_blocking(reboot_pc_sync)
        .await
        .map_err(|e| format!("Сбой запуска перезагрузки: {}", e))?
}

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

fn extract_release_download_file(url: &str, tag: &str) -> Option<String> {
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
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
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

pub fn parse_github_release_json(raw_json: &str, current_version: &str) -> Result<UpdateInfo, String> {
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
    let mut exe_any: Option<(String, String, Option<u64>)> = None;
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
                } else if exe_any.is_none() {
                    exe_any = Some((url.to_string(), name.to_string(), size));
                }
            } else if lower.ends_with(".msi") && msi_any.is_none() {
                msi_any = Some((url.to_string(), name.to_string(), size));
            }
        }
    }

    let chosen = exe_setup.or(exe_any).or(msi_any);
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
    })
}

fn resolve_curl_exe() -> PathBuf {
    resolve_system32_binary("curl.exe")
        .unwrap_or_else(|| PathBuf::from(r"C:\Windows\System32\curl.exe"))
}

fn http_get_text_github(url: &str, timeout_secs: &str) -> Result<String, String> {
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

fn http_download_file_github(url: &str, dest_path: &Path) -> Result<(), String> {
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

fn resolve_latest_release_via_redirect(current_version: &str) -> Result<UpdateInfo, String> {
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
    Ok(UpdateInfo {
        current_version: current_version.to_string(),
        latest_version: clean_ver.clone(),
        has_update: is_newer_version(&clean_ver, current_version),
        release_url: effective,
        published_at: None,
        release_notes: "Подробности изменений доступны на странице релиза GitHub (API временно ограничен по лимиту).".to_string(),
        installer_url: None,
        installer_name: None,
        checksum_url: None,
        size_bytes: None,
    })
}

#[tauri::command]
async fn check_for_updates() -> Result<UpdateInfo, String> {
    tauri::async_runtime::spawn_blocking(|| {
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
    })
    .await
    .map_err(|e| format!("Сбой проверки обновлений: {}", e))?
}

fn check_not_reparse_or_symlink(path: &Path) -> Result<(), String> {
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

fn prepare_secure_update_dir() -> Result<PathBuf, String> {
    #[cfg(target_os = "windows")]
    let base = std::env::var_os("ProgramData")
        .or_else(|| std::env::var_os("ALLUSERSPROFILE"))
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(r"C:\ProgramData"))
        .join("UltraGamingMode")
        .join("Updates");
    #[cfg(not(target_os = "windows"))]
    let base = std::env::temp_dir().join("UltraGamingModeUpdates");

    if let Some(parent) = base.parent() {
        if parent.exists() {
            check_not_reparse_or_symlink(parent)?;
        }
    }
    if base.exists() {
        check_not_reparse_or_symlink(&base)?;
    }

    std::fs::create_dir_all(&base)
        .map_err(|e| format!("Не удалось создать папку обновлений '{}': {}", base.display(), e))?;
    check_not_reparse_or_symlink(&base)?;

    #[cfg(target_os = "windows")]
    {
        let icacls = resolve_system32_binary("icacls.exe")
            .ok_or_else(|| "Не найден системный утилита icacls.exe в System32.".to_string())?;
        let base_str = base
            .to_str()
            .ok_or_else(|| "Недопустимый путь папки обновлений.".to_string())?;
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
            .map_err(|e| format!("Не удалось ограничить ACL папки обновлений: {}", e))?;
        if !out.status.success() {
            return Err(format!(
                "Не удалось закрепить права Администратора на '{}': код {:?}",
                base.display(),
                out.status.code()
            ));
        }
    }

    if let Ok(entries) = std::fs::read_dir(&base) {
        for entry in entries.flatten() {
            if let Some(name) = entry.file_name().to_str() {
                if name.starts_with("run_") {
                    let _ = std::fs::remove_dir_all(entry.path());
                }
            }
        }
    }

    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let run_dir = base.join(format!("run_{}_{}", std::process::id(), nanos));
    std::fs::create_dir(&run_dir)
        .map_err(|e| format!("Не удалось создать каталог загрузки обновления: {}", e))?;
    check_not_reparse_or_symlink(&run_dir)?;
    Ok(run_dir)
}

#[tauri::command]
async fn install_github_update(
    app: tauri::AppHandle,
    installer_url: String,
    checksum_url: Option<String>,
    expected_file_name: String,
) -> Result<ActionResult, String> {
    let clean_name = expected_file_name.trim().to_string();
    if !is_safe_asset_filename(&clean_name) {
        return Err("Недопустимое имя файла установщика.".to_string());
    }
    let lower_name = clean_name.to_ascii_lowercase();
    if !lower_name.ends_with(".exe") && !lower_name.ends_with(".msi") {
        return Err("Поддерживается установка только .exe или .msi пакетов.".to_string());
    }
    let safe_checksum_url = checksum_url
        .map(|u| u.trim().to_string())
        .filter(|u| is_allowed_github_url(u))
        .ok_or_else(|| {
            "В этом релизе отсутствует SHA256SUMS.txt — скачайте обновление вручную со страницы GitHub Releases."
                .to_string()
        })?;
    let _validated_tag =
        validate_release_update_urls(&installer_url, &safe_checksum_url, &clean_name, APP_VERSION)?;

    let launched_name = clean_name.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let manifest_text = http_get_text_github(&safe_checksum_url, "15")?;

        let update_dir = prepare_secure_update_dir()?;
        let dest_path = update_dir.join(&clean_name);
        if dest_path.exists() {
            return Err("Целевой файл обновления уже существует; загрузка отклонена.".to_string());
        }

        http_download_file_github(&installer_url, &dest_path)?;

        check_not_reparse_or_symlink(&dest_path)?;
        let file_meta = std::fs::symlink_metadata(&dest_path)
            .map_err(|e| format!("Не удалось проверить файл установщика: {}", e))?;
        if !file_meta.is_file() {
            let _ = std::fs::remove_file(&dest_path);
            return Err("Скачанный объект не является обычным файлом.".to_string());
        }

        let bytes = std::fs::read(&dest_path)
            .map_err(|e| format!("Не удалось прочитать скачанный установщик: {}", e))?;
        if let Err(err) = verify_sha256_manifest(&manifest_text, &clean_name, &bytes) {
            let _ = std::fs::remove_file(&dest_path);
            return Err(err);
        }

        if lower_name.ends_with(".exe") {
            Command::new(&dest_path)
                .args(["/S", "/UPDATE", "/R"])
                .spawn()
                .map_err(|e| format!("Не удалось запустить установщик: {}", e))?;
        } else {
            let msiexec = resolve_system32_binary("msiexec.exe")
                .unwrap_or_else(|| PathBuf::from(r"C:\Windows\System32\msiexec.exe"));
            let path_str = dest_path
                .to_str()
                .ok_or_else(|| "Недопустимый путь MSI".to_string())?;
            Command::new(&msiexec)
                .args(["/i", path_str, "/passive"])
                .spawn()
                .map_err(|e| format!("Не удалось запустить msiexec: {}", e))?;
        }

        Ok::<(), String>(())
    })
    .await
    .map_err(|e| format!("Сбой фоновой загрузки обновления: {}", e))??;

    // Exit the running app after spawning installer so files under Program Files unlock cleanly.
    ALLOW_APP_EXIT.store(true, Ordering::SeqCst);
    app.exit(0);

    Ok(ActionResult {
        success: true,
        message: format!("Установщик '{}' проверен по SHA-256 и запущен.", launched_name),
    })
}

#[tauri::command]
async fn open_release_url(url: String) -> Result<(), String> {
    let trimmed = url.trim().to_string();
    if !is_allowed_github_url(&trimmed) {
        return Err("Открытие разрешено только для официальных URL GitHub этого репозитория.".to_string());
    }
    tauri::async_runtime::spawn_blocking(move || {
        let explorer = std::env::var_os("SystemRoot")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(r"C:\Windows"))
            .join("explorer.exe");
        Command::new(&explorer)
            .arg(&trimmed)
            .spawn()
            .map_err(|e| format!("Не удалось открыть браузер: {}", e))?;
        Ok(())
    })
    .await
    .map_err(|e| format!("Сбой открытия ссылки: {}", e))?
}

#[tauri::command]
fn minimize_window(window: tauri::WebviewWindow) {
    let _ = window.minimize();
}

#[tauri::command]
fn toggle_maximize_window(window: tauri::WebviewWindow) -> Result<bool, String> {
    let is_max = window.is_maximized().map_err(|e| e.to_string())?;
    if is_max {
        window.unmaximize().map_err(|e| e.to_string())?;
        Ok(false)
    } else {
        window.maximize().map_err(|e| e.to_string())?;
        Ok(true)
    }
}

#[tauri::command]
fn start_dragging(window: tauri::WebviewWindow) {
    let _ = window.start_dragging();
}

#[tauri::command]
async fn lock_timer_resolution() -> Result<ActionResult, String> {
    tauri::async_runtime::spawn_blocking(|| match timer::set_timer_resolution(5000) {
        Ok((cur_ms, _max_ms)) => Ok(ActionResult {
            success: true,
            message: format!("Разрешение системного таймера установлено: {:.3} мс", cur_ms),
        }),
        Err(e) => Err(format!("Ошибка синхронизации таймера: {}", e)),
    })
    .await
    .map_err(|e| format!("Сбой установки системного таймера: {}", e))?
}

#[tauri::command]
async fn unlock_timer_resolution() -> Result<ActionResult, String> {
    tauri::async_runtime::spawn_blocking(|| match timer::unlock_timer_resolution() {
        Ok(cur_ms) => Ok(ActionResult {
            success: true,
            message: format!(
                "Фиксация системного таймера снята (текущее значение: {:.3} мс)",
                cur_ms
            ),
        }),
        Err(e) => Err(format!("Ошибка сброса системного таймера: {}", e)),
    })
    .await
    .map_err(|e| format!("Сбой сброса системного таймера: {}", e))?
}

const AUTOSTART_TASK_NAME: &str = "UltraGamingMode_AutoStart";

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

fn extract_xml_tag(xml: &str, tag: &str) -> Option<String> {
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

fn prepare_secure_tasks_dir() -> Result<PathBuf, String> {
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

fn normalized_current_exe_path() -> String {
    std::env::current_exe()
        .ok()
        .and_then(|p| p.to_str().map(|s| s.to_string()))
        .map(|s| {
            let trimmed = s.trim().trim_matches('"');
            trimmed.strip_prefix(r"\\?\").unwrap_or(trimmed).to_string()
        })
        .unwrap_or_default()
}

fn get_autostart_status_sync() -> Result<AutostartStatus, String> {
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

fn set_autostart_sync(enabled: bool, start_in_tray: bool) -> Result<AutostartStatus, String> {
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
                // Only treat failure as error if the task still exists
                let current = get_autostart_status_sync()?;
                if current.task_exists {
                    let stderr = decode_powershell_output(&out.stderr).trim().to_string();
                    return Err(if stderr.is_empty() {
                        "Не удалось удалить задачу автозапуска (требуются права администратора).".to_string()
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

#[tauri::command]
async fn get_autostart_status() -> Result<AutostartStatus, String> {
    tauri::async_runtime::spawn_blocking(get_autostart_status_sync)
        .await
        .map_err(|e| format!("Сбой проверки автозапуска: {}", e))?
}

#[tauri::command]
async fn set_autostart(enabled: bool, start_in_tray: bool) -> Result<AutostartStatus, String> {
    tauri::async_runtime::spawn_blocking(move || set_autostart_sync(enabled, start_in_tray))
        .await
        .map_err(|e| format!("Сбой настройки автозапуска: {}", e))?
}

fn read_process_lists_from_root(root: &Path) -> Result<ProcessConfigLists, String> {
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

fn update_process_list_in_root(
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
                    .any(|s| s.eq_ignore_ascii_case(&clean_name))
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
            .any(|s| s.eq_ignore_ascii_case(&clean_name))
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
                        .map(|s| !strip_exe_suffix(s).eq_ignore_ascii_case(&clean_name))
                        .unwrap_or(true)
                });
            }
        }
    } else {
        let before = arr.len();
        arr.retain(|v| {
            v.as_str()
                .map(|s| !s.eq_ignore_ascii_case(&clean_name))
                .unwrap_or(true)
        });
        if arr.len() == before {
            return Err(format!("Элемент '{}' не найден в списке.", clean_name));
        }
    }

    write_json_no_bom(&path, &doc)?;
    read_process_lists_from_root(root)
}

fn update_service_list_in_root(
    root: &Path,
    list_type: &str,
    service_name: &str,
    display_name: Option<&str>,
    category: Option<&str>,
    reason: Option<&str>,
    operation: &str,
    include_live_status: bool,
) -> Result<ServicesLists, String> {
    let clean_name = service_name.trim().to_string();
    if !is_safe_identifier(&clean_name) {
        return Err(format!("Недопустимое имя службы: '{}'", service_name));
    }
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
                let base_clean = strip_per_user_service_suffix(&clean_name);
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
                        arr.iter().filter_map(|v| v.as_str()).any(|s| {
                            s.eq_ignore_ascii_case(&clean_name)
                                || s.eq_ignore_ascii_case(base_clean)
                        })
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
                        .map(|n| n.eq_ignore_ascii_case(&clean_name))
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
                        .map(|n| !n.eq_ignore_ascii_case(&clean_name))
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
                    .any(|s| s.eq_ignore_ascii_case(&clean_name));
                if exists {
                    return Err(format!("Служба '{}' уже находится в белом списке.", clean_name));
                }
                wl_arr.push(serde_json::Value::String(clean_name.clone()));

                // Remove from blacklist automatically if present to maintain whitelist > blacklist invariant
                if let Some(bl_arr) = doc_bl
                    .get_mut("TargetServices")
                    .and_then(|v| v.as_array_mut())
                {
                    let before_bl = bl_arr.len();
                    bl_arr.retain(|item| {
                        item.get("Name")
                            .and_then(|v| v.as_str())
                            .map(|n| !n.eq_ignore_ascii_case(&clean_name))
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
                        .map(|s| !s.eq_ignore_ascii_case(&clean_name))
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

#[tauri::command]
async fn get_running_processes() -> Result<LiveProcessesSnapshot, String> {
    tauri::async_runtime::spawn_blocking(|| {
        let root = get_workspace_root();
        let cfg = read_process_lists_from_root(&root)?;

        #[cfg(target_os = "windows")]
        let raw_procs = win_hw::enumerate_running_processes_raw();
        #[cfg(not(target_os = "windows"))]
        let raw_procs: Vec<(u32, String, String, f64)> = Vec::new();

        let self_pid = std::process::id();
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
                let display_name = win_hw::read_exe_display_name(&executable_path)
                    .filter(|d| !d.trim().is_empty())
                    .unwrap_or_else(|| name.clone());
                #[cfg(not(target_os = "windows"))]
                let display_name = name.clone();
                let is_blacklisted = cfg
                    .blacklist_processes
                    .iter()
                    .any(|b| strip_exe_suffix(b).eq_ignore_ascii_case(&name));
                let is_startup_protected = cfg
                    .protected_startup_names
                    .iter()
                    .any(|p| p.eq_ignore_ascii_case(&name));
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
                }
            })
            .collect();

        processes.sort_by(|a, b| {
            b.memory_mb
                .partial_cmp(&a.memory_mb)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
        });

        Ok(LiveProcessesSnapshot {
            processes,
            blacklist_processes: cfg.blacklist_processes,
            protected_startup_names: cfg.protected_startup_names,
        })
    })
    .await
    .map_err(|e| format!("Сбой получения списка процессов: {}", e))?
}

fn find_matching_startup_rule(protected_rules: &[String], candidates: &[&str]) -> Option<String> {
    for rule in protected_rules {
        let r_trim = rule.trim();
        if r_trim.is_empty() {
            continue;
        }
        let r_low = r_trim.to_lowercase();
        if candidates.iter().any(|c| c.to_lowercase().contains(&r_low)) {
            return Some(r_trim.to_string());
        }
    }
    None
}

#[tauri::command]
async fn get_windows_startup_entries() -> Result<Vec<StartupEntry>, String> {
    tauri::async_runtime::spawn_blocking(|| {
        let root = get_workspace_root();
        let cfg = read_process_lists_from_root(&root)?;
        #[cfg(target_os = "windows")]
        let raw_entries = win_hw::enumerate_windows_startup_raw();
        #[cfg(not(target_os = "windows"))]
        let raw_entries: Vec<(String, String, String, String, String, String, bool)> = Vec::new();

        let mut entries: Vec<StartupEntry> = raw_entries
            .into_iter()
            .map(
                |(id, name, display_name, source, source_label, target, enabled)| {
                    let matched_rule = find_matching_startup_rule(
                        &cfg.protected_startup_names,
                        &[&name, &display_name, &target],
                    );
                    let is_protected = matched_rule.is_some();
                    StartupEntry {
                        id,
                        name,
                        display_name,
                        source,
                        source_label,
                        target,
                        enabled,
                        is_protected,
                        matched_rule,
                    }
                },
            )
            .collect();

        entries.sort_by(|a, b| {
            b.enabled
                .cmp(&a.enabled)
                .then_with(|| b.is_protected.cmp(&a.is_protected))
                .then_with(|| a.display_name.to_lowercase().cmp(&b.display_name.to_lowercase()))
        });
        Ok(entries)
    })
    .await
    .map_err(|e| format!("Сбой чтения автозагрузки Windows: {}", e))?
}

#[tauri::command]
async fn kill_process(pid: u32, name: String) -> Result<ActionResult, String> {
    let clean_name = strip_exe_suffix(&name).trim().to_string();
    if !is_safe_identifier(&clean_name) {
        return Err(format!("Недопустимое имя процесса: '{}'", name));
    }
    if pid <= 4 || pid == std::process::id() || is_protected_process_name(&clean_name) {
        return Err(format!(
            "Процесс '{}' (PID: {}) защищён ядром ОС или приложением и не может быть завершён.",
            clean_name, pid
        ));
    }

    tauri::async_runtime::spawn_blocking(move || {
        #[cfg(target_os = "windows")]
        {
            match win_hw::terminate_process_win32(pid, &clean_name) {
                Ok(msg) => Ok(ActionResult {
                    success: true,
                    message: msg,
                }),
                Err(e) => Ok(ActionResult {
                    success: false,
                    message: e,
                }),
            }
        }
        #[cfg(not(target_os = "windows"))]
        {
            Ok(ActionResult {
                success: false,
                message: "Управление процессами поддерживается только на Windows.".into(),
            })
        }
    })
    .await
    .map_err(|e| format!("Сбой завершения процесса: {}", e))?
}

#[tauri::command]
async fn update_process_list(
    list_type: String,
    process_name: String,
    operation: String,
) -> Result<ProcessConfigLists, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let root = get_workspace_root();
        update_process_list_in_root(&root, &list_type, &process_name, &operation)
    })
    .await
    .map_err(|e| format!("Сбой обновления списка процессов: {}", e))?
}

#[tauri::command]
async fn control_service(
    service_name: String,
    operation: String,
) -> Result<ActionResult, String> {
    let clean_name = service_name.trim().to_string();
    if !is_safe_identifier(&clean_name) {
        return Err(format!("Недопустимое системное имя службы: '{}'", service_name));
    }
    let safe_op = match operation.as_str() {
        "Start" => "Start",
        "Stop" => "Stop",
        "Automatic" => "Automatic",
        "Manual" => "Manual",
        "Disabled" => "Disabled",
        _ => return Err(format!("Недопустимая операция над службой: {}", operation)),
    };

    tauri::async_runtime::spawn_blocking(move || {
        let root = get_workspace_root();
        let lists = read_services_lists_from_root(&root, false)?;
        let base_name = strip_per_user_service_suffix(&clean_name);
        let is_protected = is_immutable_core_service(&clean_name)
            || lists.whitelist.iter().any(|w| {
                w.eq_ignore_ascii_case(&clean_name) || w.eq_ignore_ascii_case(base_name)
            });

        if (safe_op == "Stop" || safe_op == "Disabled") && is_protected {
            return Err(format!(
                "Служба '{}' защищена белым списком и не может быть остановлена или отключена.",
                clean_name
            ));
        }

        #[cfg(target_os = "windows")]
        {
            match win_hw::control_service_win32(&clean_name, safe_op)? {
                Ok(msg) => return Ok(ActionResult { success: true, message: msg }),
                Err(1051) => {
                    // Dependent services running: fall back cleanly to Stop-Service -Force
                    let script_path = root.join("UltraGamingMode.ps1");
                    return run_powershell_script(
                        &root,
                        &script_path,
                        &[
                            "-Action",
                            "ServiceControl",
                            "-TargetName",
                            clean_name.as_str(),
                            "-ServiceOperation",
                            safe_op,
                            "-SkipUpdateCheck",
                        ],
                        format!("Операция [{}] для службы '{}' выполнена.", safe_op, clean_name),
                        "Не удалось выполнить управление службой",
                    );
                }
                Err(code) => {
                    return Err(format!(
                        "Не удалось выполнить операцию '{}' для службы '{}' (Win32 {})",
                        safe_op, clean_name, code
                    ));
                }
            }
        }

        #[cfg(not(target_os = "windows"))]
        {
            Ok(ActionResult {
                success: true,
                message: format!("Операция [{}] для службы '{}' выполнена.", safe_op, clean_name),
            })
        }
    })
    .await
    .map_err(|e| format!("Сбой управления службой: {}", e))?
}

#[tauri::command]
async fn update_service_list(
    list_type: String,
    service_name: String,
    display_name: Option<String>,
    category: Option<String>,
    reason: Option<String>,
    operation: String,
) -> Result<ServicesLists, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let root = get_workspace_root();
        update_service_list_in_root(
            &root,
            &list_type,
            &service_name,
            display_name.as_deref(),
            category.as_deref(),
            reason.as_deref(),
            &operation,
            cfg!(target_os = "windows"),
        )
    })
    .await
    .map_err(|e| format!("Сбой обновления списка служб: {}", e))?
}

struct TrayController {
    tray: tauri::tray::TrayIcon<tauri::Wry>,
    status_item: tauri::menu::MenuItem<tauri::Wry>,
    toggle_item: tauri::menu::MenuItem<tauri::Wry>,
    last_mode: Mutex<String>,
}

pub fn build_tray_icon(mode: &str) -> tauri::image::Image<'static> {
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

    tauri::image::Image::new_owned(rgba, SIZE as u32, SIZE as u32)
}

fn mode_to_tray_meta(mode: &str) -> (&'static str, &'static str, &'static str) {
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

fn sync_tray_and_emit(app: &tauri::AppHandle, force_emit: bool) {
    let mode = read_current_mode_fast(&get_workspace_root());
    let mut changed = force_emit;

    if let Some(ctrl) = TRAY_CONTROLLER.get() {
        if let Ok(mut prev) = ctrl.last_mode.lock() {
            if *prev != mode {
                *prev = mode.clone();
                changed = true;
            } else if !force_emit {
                return;
            }
        }
        let (status_text, tooltip, toggle_text) = mode_to_tray_meta(&mode);
        let _ = ctrl.status_item.set_text(status_text);
        let _ = ctrl.toggle_item.set_text(toggle_text);
        let _ = ctrl.tray.set_icon(Some(build_tray_icon(&mode)));
        let _ = ctrl.tray.set_tooltip(Some(tooltip));
    }

    if changed && app.get_webview_window("main").is_some() {
        let _ = app.emit("ugm://state-changed", mode);
    }
}

fn show_or_recreate_main_window(app: &tauri::AppHandle) {
    if let Some(win) = app.get_webview_window("main") {
        let _ = win.unminimize();
        let _ = win.show();
        let _ = win.set_focus();
        return;
    }

    if let Some(win_cfg) = app.config().app.windows.first().cloned() {
        if let Ok(builder) = tauri::WebviewWindowBuilder::from_config(app, &win_cfg) {
            if let Ok(win) = builder.build() {
                let _ = win.set_focus();
            }
        }
    }
}

fn setup_tray_and_watcher(app: &mut tauri::App) -> Result<(), Box<dyn std::error::Error>> {
    let initial_mode = read_current_mode_fast(&get_workspace_root());
    let (status_text, tooltip, toggle_text) = mode_to_tray_meta(&initial_mode);

    let status_item = tauri::menu::MenuItemBuilder::with_id("tray-status", status_text)
        .enabled(false)
        .build(app)?;
    let open_item = tauri::menu::MenuItemBuilder::with_id("tray-open", "Открыть окно")
        .build(app)?;
    let toggle_item = tauri::menu::MenuItemBuilder::with_id("tray-toggle", toggle_text)
        .build(app)?;
    let clean_ram_item = tauri::menu::MenuItemBuilder::with_id("tray-clean-ram", "Очистить кэш ОЗУ")
        .build(app)?;
    let reboot_item = tauri::menu::MenuItemBuilder::with_id("tray-reboot", "Перезагрузить ПК...")
        .build(app)?;
    let exit_item = tauri::menu::MenuItemBuilder::with_id("tray-exit", "Выход")
        .build(app)?;

    let menu = tauri::menu::MenuBuilder::new(app)
        .item(&status_item)
        .separator()
        .item(&open_item)
        .separator()
        .item(&toggle_item)
        .item(&clean_ram_item)
        .item(&reboot_item)
        .separator()
        .item(&exit_item)
        .build()?;

    let tray = tauri::tray::TrayIconBuilder::with_id("ugm-tray")
        .icon(build_tray_icon(&initial_mode))
        .tooltip(tooltip)
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_tray_icon_event(|tray_icon, event| {
            let open = matches!(
                event,
                tauri::tray::TrayIconEvent::Click {
                    button: tauri::tray::MouseButton::Left,
                    button_state: tauri::tray::MouseButtonState::Up,
                    ..
                }
            );
            if open {
                show_or_recreate_main_window(tray_icon.app_handle());
            }
        })
        .on_menu_event(|app_handle, event| {
            let app_clone = app_handle.clone();
            match event.id().as_ref() {
                "tray-open" => show_or_recreate_main_window(app_handle),
                "tray-toggle" => {
                    std::thread::spawn(move || {
                        let root = get_workspace_root();
                        let cur = read_current_mode_fast(&root);
                        if cur == "RestoringPending" {
                            let _ = run_finish_pending_restore_sync();
                        } else {
                            let action = if cur == "Gaming" || cur == "Armed" {
                                "Restore"
                            } else {
                                "Enable"
                            };
                            let profile = resolve_profile_name(&load_tuning_from_disk(&root));
                            let _ = run_execute_mode_action_sync(action, &profile);
                        }
                        sync_tray_and_emit(&app_clone, true);
                    });
                }
                "tray-clean-ram" => {
                    std::thread::spawn(|| {
                        let _ = clean_memory_native_sync();
                    });
                }
                "tray-reboot" => {
                    std::thread::spawn(|| {
                        #[cfg(target_os = "windows")]
                        if win_hw::confirm_reboot_dialog_win32() {
                            let _ = reboot_pc_sync();
                        }
                    });
                }
                "tray-exit" => {
                    ALLOW_APP_EXIT.store(true, Ordering::SeqCst);
                    app_handle.exit(0);
                }
                _ => {}
            }
        })
        .build(app)?;

    let _ = TRAY_CONTROLLER.set(TrayController {
        tray,
        status_item,
        toggle_item,
        last_mode: Mutex::new(initial_mode),
    });

    #[cfg(target_os = "windows")]
    let wake_event = win_hw::create_wake_event();
    #[cfg(not(target_os = "windows"))]
    let wake_event: isize = 0;

    let watcher_app = app.handle().clone();
    std::thread::spawn(move || {
        let root = get_workspace_root();
        let active_state_path = root.join("Backups").join("active_state.json");
        let mut last_sig: Option<(Option<std::time::SystemTime>, u64)> =
            std::fs::metadata(&active_state_path)
                .ok()
                .map(|m| (m.modified().ok(), m.len()));
        loop {
            #[cfg(target_os = "windows")]
            let woken = win_hw::wait_wake_event_ms(wake_event, 3000);
            #[cfg(not(target_os = "windows"))]
            let woken = {
                let _ = wake_event;
                std::thread::sleep(std::time::Duration::from_secs(3));
                false
            };

            if ALLOW_APP_EXIT.load(Ordering::SeqCst) {
                break;
            }
            if woken {
                show_or_recreate_main_window(&watcher_app);
            }

            let sig = std::fs::metadata(&active_state_path)
                .ok()
                .map(|m| (m.modified().ok(), m.len()));
            if sig != last_sig {
                last_sig = sig;
                invalidate_active_state_cache();
                sync_tray_and_emit(&watcher_app, false);
            }
        }
    });

    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let start_in_tray = std::env::args()
        .skip(1)
        .any(|a| a.eq_ignore_ascii_case("--tray") || a.eq_ignore_ascii_case("--minimized"));
    START_IN_TRAY.store(start_in_tray, Ordering::SeqCst);

    #[cfg(target_os = "windows")]
    let _single_instance_guard = match win_hw::acquire_single_instance_or_wake(!start_in_tray) {
        Some(h) => h,
        None => return,
    };

    let app = tauri::Builder::default()
        .plugin(tauri_plugin_log::Builder::default().build())
        .setup(|app| {
            setup_tray_and_watcher(app)?;
            if !START_IN_TRAY.load(Ordering::SeqCst) {
                show_or_recreate_main_window(app.handle());
            }
            let startup_app = app.handle().clone();
            std::thread::spawn(move || {
                let root = get_workspace_root();
                let mode = read_current_mode_fast(&root);
                if mode == "Gaming" && load_tuning_from_disk(&root).auto_lock_timer_in_gaming {
                    let _ = timer::set_timer_resolution(5000);
                }
                if START_IN_TRAY.load(Ordering::SeqCst)
                    && mode == "RestoringPending"
                    && PENDING_RESTORE_TRIGGERED
                        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
                        .is_ok()
                {
                    let _ = run_finish_pending_restore_sync();
                    sync_tray_and_emit(&startup_app, true);
                }
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_system_status,
            get_tuning_config,
            save_tuning_config,
            get_autostart_status,
            set_autostart,
            get_services_lists,
            apply_service_feature_pack,
            get_running_processes,
            get_windows_startup_entries,
            kill_process,
            update_process_list,
            control_service,
            update_service_list,
            set_window_theme,
            execute_mode_action,
            finish_pending_restore,
            execute_emergency_repair,
            lock_timer_resolution,
            unlock_timer_resolution,
            reboot_pc,
            check_for_updates,
            install_github_update,
            open_release_url,
            close_window,
            exit_app,
            minimize_window,
            toggle_maximize_window,
            start_dragging
        ])
        .build(tauri::generate_context!())
        .expect("error while building tauri application");

    app.run(|_app_handle, event| {
        if let tauri::RunEvent::ExitRequested { code, api, .. } = event {
            if code.is_none() && !ALLOW_APP_EXIT.load(Ordering::SeqCst) {
                api.prevent_exit();
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_services_lists_deserializes_all_205_blacklist_and_92_whitelist() {
        let lists = read_services_lists_sync().expect("read_services_lists_sync should succeed");
        assert_eq!(
            lists.blacklist.len(),
            205,
            "Expected 205 blacklisted services from Config/services_blacklist.json"
        );
        assert_eq!(
            lists.whitelist.len(),
            92,
            "Expected 92 whitelisted services from Config/services_whitelist.json"
        );
        assert!(lists.whitelist.iter().any(|s| s == "FACEIT"));
        assert!(lists.whitelist.iter().any(|s| s == "FACEITService"));
        assert!(!lists.blacklist.iter().any(|s| s.name == "FACEIT" || s.name == "FACEITService"));
        assert_eq!(lists.feature_packs.len(), 7);
        let faceit_pack = lists
            .feature_packs
            .iter()
            .find(|p| p.id == "faceit")
            .expect("faceit feature pack present");
        assert!(
            faceit_pack.keep_enabled_in_game,
            "FACEIT feature pack should be kept enabled in game by default"
        );
        for item in &lists.blacklist {
            assert!(!item.name.trim().is_empty(), "Service name must not be empty");
            assert!(
                !item.display_name.trim().is_empty(),
                "DisplayName must be populated for {}",
                item.name
            );
            assert!(
                matches!(
                    item.category.as_str(),
                    "Telemetry"
                        | "Updates"
                        | "Xbox"
                        | "Print"
                        | "Devices"
                        | "Network"
                        | "Remote"
                        | "System"
                ),
                "Unexpected category '{}' for {}",
                item.category,
                item.name
            );
            assert!(!item.reason.trim().is_empty(), "Reason must not be empty");
        }
    }

    #[test]
    fn test_resolve_profile_name_recognizes_presets_and_custom() {
        let comp = TuningConfig {
            disable_fullscreen_optimizations: true,
            disable_mouse_accel: false,
            disable_nvidia_dynamic_pstate: false,
            enable_net_adapter_msi: true,
            input_buffer_queue_size: 100,
            auto_lock_timer_in_gaming: true,
        };
        assert_eq!(resolve_profile_name(&comp), "competitive");

        let aaa = TuningConfig {
            disable_fullscreen_optimizations: false,
            disable_mouse_accel: false,
            disable_nvidia_dynamic_pstate: false,
            enable_net_adapter_msi: true,
            input_buffer_queue_size: 100,
            auto_lock_timer_in_gaming: true,
        };
        assert_eq!(resolve_profile_name(&aaa), "aaa");

        let custom_mouse = TuningConfig {
            disable_fullscreen_optimizations: true,
            disable_mouse_accel: true,
            disable_nvidia_dynamic_pstate: false,
            enable_net_adapter_msi: true,
            input_buffer_queue_size: 100,
            auto_lock_timer_in_gaming: true,
        };
        assert_eq!(resolve_profile_name(&custom_mouse), "custom");

        let custom_nvidia = TuningConfig {
            disable_fullscreen_optimizations: true,
            disable_mouse_accel: false,
            disable_nvidia_dynamic_pstate: true,
            enable_net_adapter_msi: true,
            input_buffer_queue_size: 100,
            auto_lock_timer_in_gaming: true,
        };
        assert_eq!(resolve_profile_name(&custom_nvidia), "custom");

        let custom_queue = TuningConfig {
            disable_fullscreen_optimizations: true,
            disable_mouse_accel: false,
            disable_nvidia_dynamic_pstate: false,
            enable_net_adapter_msi: true,
            input_buffer_queue_size: 120,
            auto_lock_timer_in_gaming: true,
        };
        assert_eq!(resolve_profile_name(&custom_queue), "custom");
    }

    #[test]
    fn test_tuning_config_reads_and_enforces_safety_floor() {
        let cfg = read_tuning_config_sync().expect("read_tuning_config_sync should succeed");
        assert!(
            cfg.input_buffer_queue_size >= 32,
            "InputBufferQueueSize must respect >= 32 safety floor, got {}",
            cfg.input_buffer_queue_size
        );
        let serialized = serde_json::to_string(&cfg).expect("TuningConfig should serialize");
        assert!(serialized.contains("\"DisableFullscreenOptimizations\""));
        assert!(serialized.contains("\"DisableMouseAccel\""));
        assert!(serialized.contains("\"DisableNvidiaDynamicPstate\""));
        assert!(serialized.contains("\"EnableNetAdapterMsi\""));
        assert!(serialized.contains("\"InputBufferQueueSize\""));
        assert!(serialized.contains("\"AutoLockTimerInGaming\""));
    }

    #[test]
    fn test_live_tuning_trigger_and_disk_roundtrip() {
        assert!(should_trigger_live_tuning(r#"{"State":"Armed"}"#));
        assert!(should_trigger_live_tuning("\u{feff}{\"State\":\"GameMode_Active\"}"));
        assert!(!should_trigger_live_tuning(r#"{"State":"Normal"}"#));
        assert!(!should_trigger_live_tuning(r#"{"State":"Restored"}"#));
        assert!(!should_trigger_live_tuning("{invalid"));

        let temp_root = std::env::temp_dir().join(format!("ugm_rust_test_{}", std::process::id()));
        let cfg_dir = temp_root.join("Config");
        std::fs::create_dir_all(&cfg_dir).expect("create temp Config dir");

        let cfg = TuningConfig {
            disable_fullscreen_optimizations: false,
            disable_mouse_accel: true,
            disable_nvidia_dynamic_pstate: true,
            enable_net_adapter_msi: false,
            input_buffer_queue_size: 16,
            auto_lock_timer_in_gaming: false,
        };
        write_tuning_to_disk(&temp_root, &cfg).expect("write_tuning_to_disk should succeed");

        let raw_bytes = std::fs::read(cfg_dir.join("tuning.json")).expect("read tuning.json");
        assert!(
            !raw_bytes.starts_with(&[0xEF, 0xBB, 0xBF]),
            "tuning.json must be pure UTF-8 without BOM"
        );
        let reloaded = load_tuning_from_disk(&temp_root);
        assert_eq!(reloaded.disable_fullscreen_optimizations, false);
        assert_eq!(reloaded.disable_mouse_accel, true);
        assert_eq!(reloaded.disable_nvidia_dynamic_pstate, true);
        assert_eq!(reloaded.enable_net_adapter_msi, false);
        assert_eq!(reloaded.input_buffer_queue_size, 32);
        assert_eq!(reloaded.auto_lock_timer_in_gaming, false);

        let _ = std::fs::remove_dir_all(&temp_root);
    }

    #[test]
    fn test_sync_embedded_runtime_materializes_all_assets_and_preserves_custom_tuning() {
        let temp_root =
            std::env::temp_dir().join(format!("ugm_embedded_test_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&temp_root);

        sync_embedded_runtime(&temp_root).expect("sync_embedded_runtime should extract all files");

        for asset in EMBEDDED_RUNTIME_ASSETS {
            let mut dest = temp_root.clone();
            for seg in asset.rel_path.split('/') {
                dest.push(seg);
            }
            assert!(
                dest.exists(),
                "Embedded asset '{}' must exist after extraction",
                asset.rel_path
            );
            let bytes = std::fs::read(&dest).expect("read extracted asset");
            assert!(
                !bytes.starts_with(&[0xEF, 0xBB, 0xBF]),
                "Extracted asset '{}' must not have UTF-8 BOM",
                asset.rel_path
            );
            assert_eq!(bytes.as_slice(), asset.bytes);
        }
        assert!(temp_root.join("Backups").is_dir());

        // User-customized tuning.json must survive runtime upgrade/repair, while stale script gets refreshed.
        let custom_tuning = br#"{"DisableFullscreenOptimizations":false,"DisableMouseAccel":true,"DisableNvidiaDynamicPstate":true,"EnableNetAdapterMsi":false,"InputBufferQueueSize":150}"#;
        std::fs::write(temp_root.join("Config").join("tuning.json"), custom_tuning)
            .expect("write custom tuning.json");
        std::fs::write(temp_root.join("UltraGamingMode.ps1"), b"stale-script")
            .expect("write stale script");

        sync_embedded_runtime(&temp_root).expect("re-sync should succeed");

        assert_eq!(
            std::fs::read(temp_root.join("Config").join("tuning.json"))
                .expect("read preserved tuning.json"),
            custom_tuning
        );
        assert_ne!(
            std::fs::read(temp_root.join("UltraGamingMode.ps1"))
                .expect("read repaired script"),
            b"stale-script"
        );

        let _ = std::fs::remove_dir_all(&temp_root);
    }

    #[test]
    fn test_decode_powershell_output_handles_utf8_utf16_and_oem_bytes() {
        let utf8_bom = "\u{feff}Строка UTF-8\r\nВторая строка";
        assert_eq!(
            decode_powershell_output(utf8_bom.as_bytes()),
            "Строка UTF-8\nВторая строка"
        );

        let mut utf16 = vec![0xFFu8, 0xFEu8];
        for unit in "Привет UTF-16".encode_utf16() {
            utf16.extend_from_slice(&unit.to_le_bytes());
        }
        assert_eq!(decode_powershell_output(&utf16), "Привет UTF-16");

        // Non-UTF-8 OEM bytes (CP866 for "Аргумент"): must never emit U+FFFD replacement chars on Windows.
        let oem_bytes: &[u8] = &[0x80, 0xE0, 0xA3, 0xE3, 0xAC, 0xA5, 0xAD, 0xE2];
        let decoded = decode_powershell_output(oem_bytes);
        #[cfg(target_os = "windows")]
        assert!(
            !decoded.is_empty() && !decoded.contains('\u{FFFD}'),
            "Windows OEM decoding produced replacement chars: {:?}",
            decoded
        );
        #[cfg(not(target_os = "windows"))]
        assert!(!decoded.is_empty());
    }

    #[test]
    fn test_standalone_runtime_candidates_prioritize_program_files() {
        let candidates = standalone_runtime_candidates();
        assert!(!candidates.is_empty());
        #[cfg(target_os = "windows")]
        {
            let first = candidates[0].to_string_lossy().to_lowercase();
            assert!(
                first.contains("program files") && first.ends_with("ultragamingmode"),
                "Expected Program Files candidate first, got: {}",
                candidates[0].display()
            );
        }
    }

    #[test]
    fn test_security_identifier_and_protected_process_guards() {
        assert!(is_safe_identifier("Discord"));
        assert!(is_safe_identifier("logi_lamparray_service.AMD64"));
        assert!(is_safe_identifier("AMD External Events Utility"));

        assert!(!is_safe_identifier(""));
        assert!(!is_safe_identifier("..\\System32\\cmd"));
        assert!(!is_safe_identifier("svc*"));
        assert!(!is_safe_identifier("svc; calc.exe"));
        assert!(!is_safe_identifier("svc|whoami"));
        assert!(!is_safe_identifier("path/traversal"));

        for critical in [
            "lsass",
            "lsass.exe",
            "csrss",
            "winlogon",
            "dwm",
            "explorer",
            "svchost",
            "UltraGamingMode",
            "msedgewebview2",
            "vgk",
            "EasyAntiCheat",
        ] {
            assert!(
                is_protected_process_name(critical),
                "Critical process '{}' must be strictly protected",
                critical
            );
        }
        assert!(!is_protected_process_name("Discord.exe"));
        assert!(!is_protected_process_name("Spotify"));

        assert!(is_immutable_core_service("RpcSs"));
        assert!(is_immutable_core_service("Audiosrv"));
        assert!(!is_immutable_core_service("Spooler"));
    }

    #[test]
    fn test_process_list_crud_and_protection_enforcement() {
        let temp_root = std::env::temp_dir().join(format!("ugm_proc_test_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&temp_root);
        sync_embedded_runtime(&temp_root).expect("sync_embedded_runtime");

        // Protected OS and UI processes must be rejected
        for forbidden in ["lsass", "csrss.exe", "UltraGamingMode", "msedgewebview2", "ctfmon"] {
            assert!(
                update_process_list_in_root(&temp_root, "blacklist", forbidden, "add").is_err(),
                "Expected '{}' to be blocked from BlacklistProcesses",
                forbidden
            );
        }

        // Valid add & remove round-trip in BlacklistProcesses
        let added = update_process_list_in_root(&temp_root, "blacklist", "MyCustomOverlay.exe", "add")
            .expect("adding custom process should succeed");
        assert!(added.blacklist_processes.iter().any(|p| p == "MyCustomOverlay"));

        let removed = update_process_list_in_root(&temp_root, "blacklist", "MyCustomOverlay", "remove")
            .expect("removing custom process should succeed");
        assert!(!removed.blacklist_processes.iter().any(|p| p == "MyCustomOverlay"));

        // Ensure pure UTF-8 without BOM
        let raw_bytes = std::fs::read(temp_root.join("Config").join("startup_apps.json")).unwrap();
        assert!(!raw_bytes.starts_with(&[0xEF, 0xBB, 0xBF]));

        let _ = std::fs::remove_dir_all(&temp_root);
    }

    #[test]
    fn test_service_list_crud_and_immutable_whitelist_guard() {
        let temp_root = std::env::temp_dir().join(format!("ugm_svc_test_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&temp_root);
        sync_embedded_runtime(&temp_root).expect("sync_embedded_runtime");

        // Immutable core or already whitelisted services cannot be blacklisted
        assert!(update_service_list_in_root(
            &temp_root,
            "blacklist",
            "RpcSs",
            None,
            None,
            None,
            "add",
            false
        )
        .is_err());
        assert!(update_service_list_in_root(
            &temp_root,
            "blacklist",
            "Audiosrv",
            None,
            None,
            None,
            "add",
            false
        )
        .is_err());

        // Immutable core services cannot be removed from whitelist
        assert!(update_service_list_in_root(
            &temp_root,
            "whitelist",
            "RpcSs",
            None,
            None,
            None,
            "remove",
            false
        )
        .is_err());

        // Custom service add -> whitelist move -> remove round-trip
        let lists1 = update_service_list_in_root(
            &temp_root,
            "blacklist",
            "CustomTelemetrySvc",
            Some("Custom Telemetry"),
            Some("Telemetry"),
            Some("Test custom entry"),
            "add",
            false,
        )
        .expect("adding non-protected service to blacklist");
        assert!(lists1.blacklist.iter().any(|s| s.name == "CustomTelemetrySvc"));

        let lists2 = update_service_list_in_root(
            &temp_root,
            "whitelist",
            "CustomTelemetrySvc",
            None,
            None,
            None,
            "add",
            false,
        )
        .expect("moving custom service to whitelist");
        assert!(lists2.whitelist.iter().any(|s| s == "CustomTelemetrySvc"));
        assert!(!lists2.blacklist.iter().any(|s| s.name == "CustomTelemetrySvc"));

        let lists3 = update_service_list_in_root(
            &temp_root,
            "whitelist",
            "CustomTelemetrySvc",
            None,
            None,
            None,
            "remove",
            false,
        )
        .expect("removing non-core service from whitelist");
        assert!(!lists3.whitelist.iter().any(|s| s == "CustomTelemetrySvc"));

        let _ = std::fs::remove_dir_all(&temp_root);
    }

    #[test]
    fn test_service_descriptions_cover_all_blacklist_and_whitelist_services() {
        let root = get_workspace_root();
        let lists =
            read_services_lists_from_root(&root, false).expect("read_services_lists_from_root");
        assert_eq!(lists.blacklist.len(), 205);
        assert_eq!(lists.whitelist.len(), 92);
        for item in &lists.blacklist {
            assert!(
                !item.summary_ru.trim().is_empty(),
                "Missing SummaryRu for blacklisted service {}",
                item.name
            );
            assert!(
                !item.can_disable_hint.trim().is_empty(),
                "Missing CanDisableHint for blacklisted service {}",
                item.name
            );
        }
        for wl_name in &lists.whitelist {
            let desc = lists
                .whitelist_descriptions
                .get(wl_name)
                .unwrap_or_else(|| panic!("Missing whitelist description for {}", wl_name));
            assert!(
                !desc.summary_ru.trim().is_empty(),
                "Empty summaryRu for whitelisted service {}",
                wl_name
            );
            assert!(
                !desc.can_disable_ru.trim().is_empty(),
                "Empty canDisableRu for whitelisted service {}",
                wl_name
            );
        }
    }

    #[test]
    fn test_tray_icon_pixel_colors_for_all_three_modes() {
        let center_idx = (15 * 32 + 15) * 4;
        let red_icon = build_tray_icon("Normal");
        assert_eq!(red_icon.width(), 32);
        assert_eq!(red_icon.height(), 32);
        assert_eq!(red_icon.rgba()[3], 0, "Corner must be transparent");
        assert_eq!(
            &red_icon.rgba()[center_idx..center_idx + 4],
            &[239, 68, 68, 255]
        );

        let orange_icon = build_tray_icon("Armed");
        assert_eq!(
            &orange_icon.rgba()[center_idx..center_idx + 4],
            &[245, 158, 11, 255]
        );

        let green_icon = build_tray_icon("Gaming");
        assert_eq!(
            &green_icon.rgba()[center_idx..center_idx + 4],
            &[34, 197, 94, 255]
        );
    }

    #[test]
    fn test_semver_and_github_allowlist_and_release_json_parser() {
        assert_eq!(parse_semver_tuple("v3.5.0"), Some((3, 5, 0)));
        assert_eq!(parse_semver_tuple("3.5"), Some((3, 5, 0)));
        assert!(is_newer_version("v3.5.1", "3.5.0"));
        assert!(!is_newer_version("3.5.0", "3.5.0"));
        assert!(!is_newer_version("3.4.0", "3.5.0"));

        assert!(is_allowed_github_url(
            "https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases/latest"
        ));
        assert!(is_allowed_github_url(
            "https://api.github.com/repos/RagTagsky/Win11-Gaming-Optimizer/releases/latest"
        ));
        assert!(!is_allowed_github_url(
            "https://objects.githubusercontent.com/github-production-release-asset/foo"
        ));
        assert!(!is_allowed_github_url(
            "https://release-assets.githubusercontent.com/foo"
        ));
        assert!(!is_allowed_github_url(
            "https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases\"test"
        ));
        assert!(!is_allowed_github_url(
            "https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases;calc"
        ));
        assert!(!is_allowed_github_url(
            "https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases|cmd"
        ));
        assert!(!is_allowed_github_url(
            "https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases\\foo"
        ));
        assert!(!is_allowed_github_url(
            "http://github.com/RagTagsky/Win11-Gaming-Optimizer/releases"
        ));
        assert!(!is_allowed_github_url(
            "https://evil.example.com/RagTagsky/Win11-Gaming-Optimizer"
        ));
        assert!(!is_allowed_github_url(
            "https://github.com/OtherUser/Repo/releases"
        ));
        assert!(!is_allowed_github_url(
            "https://github.com@evil.com/RagTagsky/Win11-Gaming-Optimizer"
        ));

        let sample_json = r#"{
          "tag_name": "v3.5.0",
          "html_url": "https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases/tag/v3.5.0",
          "published_at": "2026-12-01T12:00:00Z",
          "body": "Performance improvements",
          "assets": [
            {
              "name": "UltraGamingMode_3.5.0_x64_en-US.msi",
              "browser_download_url": "https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases/download/v3.5.0/UltraGamingMode_3.5.0_x64_en-US.msi",
              "size": 123456
            },
            {
              "name": "UltraGamingMode_3.5.0_x64-setup.exe",
              "browser_download_url": "https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases/download/v3.5.0/UltraGamingMode_3.5.0_x64-setup.exe",
              "size": 234567
            },
            {
              "name": "SHA256SUMS.txt",
              "browser_download_url": "https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases/download/v3.5.0/SHA256SUMS.txt",
              "size": 512
            }
          ]
        }"#;
        let info = parse_github_release_json(sample_json, "3.4.0").expect("parse release JSON");
        assert!(info.has_update);
        assert_eq!(info.latest_version, "3.5.0");
        assert_eq!(
            info.installer_name.as_deref(),
            Some("UltraGamingMode_3.5.0_x64-setup.exe")
        );
        assert!(info.checksum_url.is_some());

        let up_to_date = parse_github_release_json(sample_json, "3.5.0").expect("parse current release");
        assert!(!up_to_date.has_update);
    }

    #[test]
    fn test_sha256_manifest_verification_and_shader_flush_temp() {
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        let payload = b"ultra gaming mode installer payload";
        let digest = sha256_hex(payload);
        let manifest = format!("{}  UltraGamingMode_3.5.0_x64-setup.exe\n", digest);
        assert!(verify_sha256_manifest(
            &manifest,
            "UltraGamingMode_3.5.0_x64-setup.exe",
            payload
        )
        .is_ok());
        assert!(verify_sha256_manifest(
            &manifest,
            "UltraGamingMode_3.5.0_x64-setup.exe",
            b"tampered payload"
        )
        .is_err());

        let temp_local =
            std::env::temp_dir().join(format!("ugm_shader_test_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&temp_local);
        let dx_dir = temp_local.join("AMD").join("DxCache");
        std::fs::create_dir_all(&dx_dir).expect("create shader test dir");
        std::fs::write(dx_dir.join("shader.bin"), vec![1u8; 2048]).expect("write shader cache");
        let (files, _mb) = flush_shader_cache_native_impl(Some(&temp_local), None);
        assert_eq!(files, 1);
        assert!(dx_dir.exists(), "Parent DxCache folder should remain intact");
        assert!(!dx_dir.join("shader.bin").exists());
        let _ = std::fs::remove_dir_all(&temp_local);
    }

    #[test]
    fn test_validate_release_update_urls_enforces_same_tag_and_no_downgrade() {
        let valid_inst = "https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases/download/v3.6.0/UltraGamingMode-Setup.exe";
        let valid_sum = "https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases/download/v3.6.0/SHA256SUMS.txt";
        assert_eq!(
            validate_release_update_urls(valid_inst, valid_sum, "UltraGamingMode-Setup.exe", "3.5.0"),
            Ok("v3.6.0".to_string())
        );

        // Downgrade or same-version install must be rejected
        let old_inst = "https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases/download/v3.4.0/UltraGamingMode-Setup.exe";
        let old_sum = "https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases/download/v3.4.0/SHA256SUMS.txt";
        assert!(validate_release_update_urls(old_inst, old_sum, "UltraGamingMode-Setup.exe", "3.5.0").is_err());

        let same_inst = "https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases/download/v3.5.0/UltraGamingMode-Setup.exe";
        let same_sum = "https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases/download/v3.5.0/SHA256SUMS.txt";
        assert!(validate_release_update_urls(same_inst, same_sum, "UltraGamingMode-Setup.exe", "3.5.0").is_err());

        // Mismatched tags across installer & SHA256SUMS.txt must fail
        assert!(validate_release_update_urls(valid_inst, old_sum, "UltraGamingMode-Setup.exe", "3.2.0").is_err());

        // Non-matching installer filename or non-github.com host must fail
        assert!(validate_release_update_urls(valid_inst, valid_sum, "OtherSetup.exe", "3.5.0").is_err());
        let cdn_inst = "https://objects.githubusercontent.com/github-production-release-asset/12345";
        assert!(validate_release_update_urls(cdn_inst, valid_sum, "UltraGamingMode-Setup.exe", "3.5.0").is_err());
    }

    #[test]
    fn test_mode_action_busy_guard_prevents_concurrent_entry() {
        let g1 = try_acquire_mode_action_guard();
        assert!(g1.is_some(), "First guard acquisition should succeed");
        assert!(
            try_acquire_mode_action_guard().is_none(),
            "Concurrent second acquisition must be rejected while first guard is held"
        );
        drop(g1);
        assert!(
            try_acquire_mode_action_guard().is_some(),
            "Acquisition must succeed again once previous guard is dropped"
        );
    }

    #[test]
    fn test_autostart_task_xml_encoding_escaping_and_roundtrip() {
        let xml = build_autostart_task_xml(
            "S-1-5-21-1000-2000-3000-1001",
            r"C:\Program Files\R&D Apps\UltraGamingMode.exe",
            true,
        );
        assert!(xml.contains("&amp;"), "Ampersands in paths must be XML escaped");
        assert!(xml.contains("<Delay>PT3S</Delay>"));
        assert!(xml.contains("<RunLevel>HighestAvailable</RunLevel>"));
        assert!(xml.contains("<MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>"));
        assert!(xml.contains("<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>"));
        assert!(xml.contains("<Arguments>--tray</Arguments>"));

        let utf16 = encode_utf16le_with_bom(&xml);
        assert!(utf16.starts_with(&[0xFF, 0xFE]), "XML must start with UTF-16 LE BOM");
        let decoded = decode_powershell_output(&utf16);
        let (enabled, cmd, args, is_highest) = parse_autostart_task_xml(&decoded);
        assert!(enabled);
        assert_eq!(
            cmd.as_deref(),
            Some(r"C:\Program Files\R&D Apps\UltraGamingMode.exe")
        );
        assert_eq!(args.as_deref(), Some("--tray"));
        assert!(is_highest);

        let xml_window = build_autostart_task_xml(
            "S-1-5-21-1000-2000-3000-1001",
            r"C:\Program Files\UltraGamingMode\UltraGamingMode.exe",
            false,
        );
        let (enabled2, cmd2, args2, is_highest2) = parse_autostart_task_xml(&xml_window);
        assert!(enabled2);
        assert_eq!(
            cmd2.as_deref(),
            Some(r"C:\Program Files\UltraGamingMode\UltraGamingMode.exe")
        );
        assert!(args2.is_none());
        assert!(is_highest2);
    }

    #[test]
    fn test_process_protection_classification_and_mutual_exclusion() {
        assert_eq!(classify_process_protection("lsass"), Some("os_core"));
        assert_eq!(classify_process_protection("UltraGamingMode.exe"), Some("self_app"));
        assert_eq!(classify_process_protection("FACEITClient"), Some("anticheat"));
        assert_eq!(classify_process_protection("vgk"), Some("anticheat"));
        assert_eq!(classify_process_protection("steam.exe"), Some("game_client"));
        assert_eq!(classify_process_protection("Discord"), None);

        let temp_root =
            std::env::temp_dir().join(format!("ugm_proc_mutex_test_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&temp_root);
        sync_embedded_runtime(&temp_root).expect("sync_embedded_runtime");

        let step1 = update_process_list_in_root(&temp_root, "blacklist", "CustomApp.exe", "add")
            .expect("add CustomApp to blacklist");
        assert!(step1.blacklist_processes.iter().any(|p| p == "CustomApp"));

        let step2 = update_process_list_in_root(&temp_root, "protected", "CustomApp", "add")
            .expect("add CustomApp to protected should remove from blacklist");
        assert!(step2.protected_startup_names.iter().any(|p| p == "CustomApp"));
        assert!(
            !step2
                .blacklist_processes
                .iter()
                .any(|p| p.eq_ignore_ascii_case("CustomApp")),
            "Adding to ProtectedStartupNames must clear duplicate entry from BlacklistProcesses"
        );

        let _ = std::fs::remove_dir_all(&temp_root);
    }

    #[test]
    fn test_service_feature_pack_atomic_toggle_and_faceit_default() {
        let temp_root =
            std::env::temp_dir().join(format!("ugm_pack_test_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&temp_root);
        sync_embedded_runtime(&temp_root).expect("sync_embedded_runtime");

        let wifi_on = apply_service_feature_pack_in_root(&temp_root, "wifi", true, false)
            .expect("enable wifi pack");
        for svc in ["WlanSvc", "WwanSvc", "icssvc"] {
            assert!(wifi_on.whitelist.iter().any(|w| w.eq_ignore_ascii_case(svc)));
            assert!(!wifi_on.blacklist.iter().any(|b| b.name.eq_ignore_ascii_case(svc)));
        }
        assert!(
            wifi_on
                .feature_packs
                .iter()
                .find(|p| p.id == "wifi")
                .unwrap()
                .keep_enabled_in_game
        );

        let faceit_off = apply_service_feature_pack_in_root(&temp_root, "faceit", false, false)
            .expect("disable faceit pack in game");
        for svc in ["FACEIT", "FACEITService"] {
            assert!(faceit_off.blacklist.iter().any(|b| b.name.eq_ignore_ascii_case(svc)));
            assert!(!faceit_off.whitelist.iter().any(|w| w.eq_ignore_ascii_case(svc)));
        }
        assert!(
            !faceit_off
                .feature_packs
                .iter()
                .find(|p| p.id == "faceit")
                .unwrap()
                .keep_enabled_in_game
        );

        let faceit_on = apply_service_feature_pack_in_root(&temp_root, "faceit", true, false)
            .expect("re-enable faceit pack");
        assert!(
            faceit_on
                .feature_packs
                .iter()
                .find(|p| p.id == "faceit")
                .unwrap()
                .keep_enabled_in_game
        );

        let _ = std::fs::remove_dir_all(&temp_root);
    }

    #[test]
    fn test_read_cached_active_state_maps_partial_restore_to_restoring_pending() {
        let base_temp =
            std::env::temp_dir().join(format!("ugm_restoring_test_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base_temp);

        let root_sys = base_temp.join("sys_done");
        let root_usr = base_temp.join("usr_done");
        std::fs::create_dir_all(root_sys.join("Backups")).expect("create sys backups dir");
        std::fs::create_dir_all(root_usr.join("Backups")).expect("create usr backups dir");

        std::fs::write(
            root_sys.join("Backups").join("active_state.json"),
            br#"{"State":"Restoring_SystemDone","Timestamp":"2026-11-19 12:00:00"}"#,
        )
        .expect("write Restoring_SystemDone");
        invalidate_active_state_cache();
        let parsed_sys = read_cached_active_state(&root_sys).expect("read sys state");
        assert_eq!(parsed_sys.mode, "RestoringPending");
        assert_eq!(parsed_sys.active_since.as_deref(), Some("2026-11-19 12:00:00"));

        std::fs::write(
            root_usr.join("Backups").join("active_state.json"),
            br#"{"State":"Restoring_UserDone","Timestamp":"2026-11-19 12:05:00"}"#,
        )
        .expect("write Restoring_UserDone");
        invalidate_active_state_cache();
        let parsed_usr = read_cached_active_state(&root_usr).expect("read usr state");
        assert_eq!(parsed_usr.mode, "RestoringPending");

        let center_idx = (15 * 32 + 15) * 4;
        let pending_icon = build_tray_icon("RestoringPending");
        assert_eq!(&pending_icon.rgba()[center_idx..center_idx + 4], &[245, 158, 11, 255]);

        let _ = std::fs::remove_dir_all(&base_temp);
    }
}
