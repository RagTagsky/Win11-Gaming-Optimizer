use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, OnceLock};

pub const APP_VERSION: &str = env!("CARGO_PKG_VERSION");
pub const GITHUB_REPO: &str = "RagTagsky/Win11-Gaming-Optimizer";

#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;

#[cfg(target_os = "windows")]
const CREATE_NO_WINDOW: u32 = 0x08000000;

pub struct EmbeddedAsset {
    pub rel_path: &'static str,
    pub bytes: &'static [u8],
    pub preserve_if_exists: bool,
}

pub const EMBEDDED_RUNTIME_ASSETS: &[EmbeddedAsset] = &[
    EmbeddedAsset {
        rel_path: "UltraGamingMode.ps1",
        bytes: include_bytes!("../UltraGamingMode.ps1"),
        preserve_if_exists: false,
    },
    EmbeddedAsset {
        rel_path: "UltraGamingMode.bat",
        bytes: include_bytes!("../UltraGamingMode.bat"),
        preserve_if_exists: false,
    },
    EmbeddedAsset {
        rel_path: "Core/ServiceManager.ps1",
        bytes: include_bytes!("../Core/ServiceManager.ps1"),
        preserve_if_exists: false,
    },
    EmbeddedAsset {
        rel_path: "Core/StateEngine.ps1",
        bytes: include_bytes!("../Core/StateEngine.ps1"),
        preserve_if_exists: false,
    },
    EmbeddedAsset {
        rel_path: "Core/SystemOptimizer.ps1",
        bytes: include_bytes!("../Core/SystemOptimizer.ps1"),
        preserve_if_exists: false,
    },
    EmbeddedAsset {
        rel_path: "Config/services_blacklist.json",
        bytes: include_bytes!("../Config/services_blacklist.json"),
        preserve_if_exists: true,
    },
    EmbeddedAsset {
        rel_path: "Config/services_whitelist.json",
        bytes: include_bytes!("../Config/services_whitelist.json"),
        preserve_if_exists: true,
    },
    EmbeddedAsset {
        rel_path: "Config/service_descriptions.json",
        bytes: include_bytes!("../Config/service_descriptions.json"),
        preserve_if_exists: false,
    },
    EmbeddedAsset {
        rel_path: "Config/process_descriptions.json",
        bytes: include_bytes!("../Config/process_descriptions.json"),
        preserve_if_exists: false,
    },
    EmbeddedAsset {
        rel_path: "Config/startup_apps.json",
        bytes: include_bytes!("../Config/startup_apps.json"),
        preserve_if_exists: true,
    },
    EmbeddedAsset {
        rel_path: "Config/tuning.json",
        bytes: include_bytes!("../Config/tuning.json"),
        preserve_if_exists: true,
    },
    EmbeddedAsset {
        rel_path: "Tests/Verify-UniversalEngine.ps1",
        bytes: include_bytes!("../Tests/Verify-UniversalEngine.ps1"),
        preserve_if_exists: false,
    },
];

static RUNTIME_ROOT_CACHE: OnceLock<PathBuf> = OnceLock::new();
static BACKUPS_ACL_INIT: OnceLock<()> = OnceLock::new();
pub static ALLOW_APP_EXIT: AtomicBool = AtomicBool::new(false);
pub static MODE_ACTION_BUSY: AtomicBool = AtomicBool::new(false);
pub static TIMER_LOCKED: AtomicBool = AtomicBool::new(false);
pub static START_IN_TRAY: AtomicBool = AtomicBool::new(false);
pub static PENDING_RESTORE_TRIGGERED: AtomicBool = AtomicBool::new(false);

pub const MIN_AUTO_PURGE_RAM_THRESHOLD_MB: u32 = 512;
pub const MAX_AUTO_PURGE_RAM_THRESHOLD_MB: u32 = 16384;
pub const DEFAULT_AUTO_PURGE_RAM_THRESHOLD_MB: u32 = 2048;
pub const AUTO_PURGE_RAM_POLL_SECS: u64 = 60;
pub const AUTO_PURGE_RAM_COOLDOWN_SECS: u64 = 180;

pub struct ModeActionGuard;

impl Drop for ModeActionGuard {
    fn drop(&mut self) {
        MODE_ACTION_BUSY.store(false, Ordering::SeqCst);
    }
}

pub fn try_acquire_mode_action_guard() -> Option<ModeActionGuard> {
    if MODE_ACTION_BUSY
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_ok()
    {
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

#[derive(Clone, Default)]
pub struct ExeMetadata {
    pub display_name: Option<String>,
    pub file_description: Option<String>,
    pub product_name: Option<String>,
    pub company_name: Option<String>,
}

static ACTIVE_STATE_CACHE: Mutex<Option<CachedActiveState>> = Mutex::new(None);
static EXE_METADATA_CACHE: Mutex<Option<std::collections::HashMap<String, ExeMetadata>>> =
    Mutex::new(None);
static SERVICE_SCM_DESC_CACHE: Mutex<Option<std::collections::HashMap<String, Option<String>>>> =
    Mutex::new(None);
static STARTUP_MIGRATION_LOGS: Mutex<Vec<(String, String)>> = Mutex::new(Vec::new());

fn record_startup_migration_log(level: &str, message: impl Into<String>) {
    if let Ok(mut guard) = STARTUP_MIGRATION_LOGS.lock() {
        guard.push((level.to_string(), message.into()));
    }
}

pub fn take_startup_migration_logs() -> Vec<(String, String)> {
    if let Ok(mut guard) = STARTUP_MIGRATION_LOGS.lock() {
        std::mem::take(&mut *guard)
    } else {
        Vec::new()
    }
}

fn default_true() -> bool {
    true
}

fn default_auto_purge_ram_threshold_mb() -> u32 {
    DEFAULT_AUTO_PURGE_RAM_THRESHOLD_MB
}

#[derive(Serialize, Deserialize, Clone, Debug)]
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

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct TuningConfig {
    #[serde(rename = "AutoLockTimerInGaming", default = "default_true")]
    pub auto_lock_timer_in_gaming: bool,
    #[serde(rename = "AutoPurgeRamInGaming", default = "default_true")]
    pub auto_purge_ram_in_gaming: bool,
    #[serde(
        rename = "AutoPurgeRamThresholdMB",
        default = "default_auto_purge_ram_threshold_mb"
    )]
    pub auto_purge_ram_threshold_mb: u32,
}

impl Default for TuningConfig {
    fn default() -> Self {
        Self {
            auto_lock_timer_in_gaming: true,
            auto_purge_ram_in_gaming: true,
            auto_purge_ram_threshold_mb: DEFAULT_AUTO_PURGE_RAM_THRESHOLD_MB,
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
    #[serde(rename = "safetyLevel", default)]
    pub safety_level: String,
}

#[derive(Serialize, Deserialize, Clone, Debug, Default)]
pub struct ProcessDescriptionEntry {
    #[serde(rename = "displayNameRu", default)]
    pub display_name_ru: String,
    #[serde(rename = "summaryRu", default)]
    pub summary_ru: String,
    #[serde(rename = "canDisableRu", default)]
    pub can_disable_ru: String,
    #[serde(rename = "safetyLevel", default)]
    pub safety_level: String,
    #[serde(rename = "protectionKind", default, skip_serializing_if = "Option::is_none")]
    pub protection_kind: Option<String>,
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
    #[serde(rename = "safetyLevel", default)]
    pub safety_level: String,
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
    #[serde(rename = "safetyLevel", default)]
    pub safety_level: String,
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
    #[serde(rename = "disableInGaming", default)]
    pub disable_in_gaming: bool,
    #[serde(rename = "SummaryRu", default)]
    pub summary_ru: String,
    #[serde(rename = "CanDisableHint", default)]
    pub can_disable_hint: String,
    #[serde(rename = "safetyLevel", default)]
    pub safety_level: String,
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

#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
pub enum InstallKind {
    NsisSetup,
    WixMsi,
    Portable,
}

#[derive(Clone, Debug)]
pub struct PreparedUpdate {
    pub latest_version: String,
    pub kind: InstallKind,
    pub stage_dir: PathBuf,
    pub package_path: PathBuf,
    pub target_exe: PathBuf,
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
    #[serde(rename = "setupUrl", default)]
    pub setup_url: Option<String>,
    #[serde(rename = "setupSizeBytes", default)]
    pub setup_size_bytes: Option<u64>,
    #[serde(rename = "msiUrl", default)]
    pub msi_url: Option<String>,
    #[serde(rename = "msiSizeBytes", default)]
    pub msi_size_bytes: Option<u64>,
    #[serde(rename = "portableUrl", default)]
    pub portable_url: Option<String>,
    #[serde(rename = "portableSizeBytes", default)]
    pub portable_size_bytes: Option<u64>,
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
    #[serde(rename = "inStartup", default)]
    pub in_startup: bool,
    #[serde(rename = "summaryRu", default)]
    pub summary_ru: String,
    #[serde(rename = "canDisableHint", default)]
    pub can_disable_hint: String,
    #[serde(rename = "safetyLevel", default)]
    pub safety_level: String,
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
    #[serde(rename = "processDescriptions", default)]
    pub process_descriptions: std::collections::HashMap<String, ProcessDescriptionEntry>,
    #[serde(rename = "startupProcessNames", default)]
    pub startup_process_names: Vec<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct SystemStatus {
    pub mode: String,
    pub profile: String,
    pub hardware: HardwareInfo,
    #[serde(rename = "activeSince")]
    pub active_since: Option<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct ActionResult {
    pub success: bool,
    pub message: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub log_entries: Vec<(String, String)>,
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
    trimmed
        .bytes()
        .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'_' | b'.' | b'-' | b' '))
}

pub fn classify_process_protection(name: &str) -> Option<&'static str> {
    let clean = strip_exe_suffix(name);
    if !is_safe_identifier(clean) {
        return Some("os_core");
    }
    if ["UltraGamingMode", "com.ultragamingmode.optimizer"]
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
    if ["winws", "winws2", "zapret"]
        .iter()
        .any(|p| p.eq_ignore_ascii_case(clean))
    {
        return Some("network_bypass");
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

const EXACT_FIXED_VERSION_SERVICES: &[&str] = &["FontCache3.0.0.0", "igfxCUIService2.0.0.0"];

fn strip_per_user_service_suffix(name: &str) -> &str {
    if let Some(idx) = name.rfind('_') {
        let suffix = &name[idx + 1..];
        if (4..=16).contains(&suffix.len()) && suffix.chars().all(|c| c.is_ascii_hexdigit()) {
            return &name[..idx];
        }
    }
    name
}

pub fn strip_versioned_service_suffix(name: &str) -> &str {
    let trimmed = name.trim();
    if EXACT_FIXED_VERSION_SERVICES
        .iter()
        .any(|fixed| fixed.eq_ignore_ascii_case(trimmed))
    {
        return trimmed;
    }
    let bytes = trimmed.as_bytes();
    let mut i = bytes.len();
    let mut seg_count = 0usize;
    while seg_count < 4 {
        let seg_end = i;
        while i > 0 && bytes[i - 1].is_ascii_digit() {
            i -= 1;
        }
        if i == seg_end {
            return trimmed;
        }
        seg_count += 1;
        if seg_count < 4 {
            if i == 0 || bytes[i - 1] != b'.' {
                return trimmed;
            }
            i -= 1;
        }
    }
    if i > 0 && bytes[0].is_ascii_alphabetic() {
        &trimmed[..i]
    } else {
        trimmed
    }
}

pub fn canonical_service_name(name: &str) -> &str {
    let trimmed = name.trim();
    let without_luid = strip_per_user_service_suffix(trimmed);
    strip_versioned_service_suffix(without_luid)
}

pub fn service_names_match(a: &str, b: &str) -> bool {
    let a_t = a.trim();
    let b_t = b.trim();
    if a_t.is_empty() || b_t.is_empty() {
        return false;
    }
    a_t.eq_ignore_ascii_case(b_t)
        || canonical_service_name(a_t).eq_ignore_ascii_case(canonical_service_name(b_t))
}

fn normalize_safety_level(raw: &str, is_protected: bool) -> String {
    if is_protected {
        return "protected".to_string();
    }
    match raw.trim().to_ascii_lowercase().as_str() {
        "safe" => "safe".to_string(),
        "optional" => "optional".to_string(),
        "protected" => "protected".to_string(),
        _ => "optional".to_string(),
    }
}

pub fn is_immutable_core_service(name: &str) -> bool {
    let trimmed = name.trim();
    let canon = canonical_service_name(trimmed);
    IMMUTABLE_CORE_SERVICES
        .iter()
        .any(|s| s.eq_ignore_ascii_case(trimmed) || s.eq_ignore_ascii_case(canon))
}

fn format_fs_write_error(path: &Path, err: &std::io::Error) -> String {
    if err.kind() == std::io::ErrorKind::PermissionDenied || err.raw_os_error() == Some(5) {
        format!(
            "Нет прав на запись в '{}' ({}). Запустите приложение от имени администратора или проверьте атрибуты доступа.",
            path.display(),
            err
        )
    } else {
        format!("Не удалось записать '{}': {}", path.display(), err)
    }
}

fn write_json_no_bom(path: &Path, val: &impl Serialize) -> Result<(), String> {
    static TMP_WRITE_SEQ: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)
            .map_err(|e| format_fs_write_error(parent, &e))?;
    }
    let serialized = serde_json::to_string_pretty(val)
        .map_err(|e| format!("Ошибка сериализации {}: {}", path.display(), e))?;
    let seq = TMP_WRITE_SEQ.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    let tmp_path = path.with_extension(format!("tmp.{}.{}", std::process::id(), seq));
    if std::fs::write(&tmp_path, serialized.as_bytes()).is_ok() {
        if std::fs::rename(&tmp_path, path).is_ok() {
            return Ok(());
        }
        let _ = std::fs::remove_file(&tmp_path);
    }
    std::fs::write(path, serialized.as_bytes())
        .map_err(|e| format_fs_write_error(path, &e))
}

#[cfg(target_os = "windows")]
pub mod win_hw {
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
    struct SERVICE_DESCRIPTIONW {
        lp_description: *mut u16,
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
        fn QueryServiceConfig2W(
            hService: usize,
            dwInfoLevel: u32,
            lpBuffer: *mut u8,
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

    pub fn query_available_ram_mb() -> Option<u64> {
        unsafe {
            let mut mem: MEMORYSTATUSEX = std::mem::zeroed();
            mem.dw_length = std::mem::size_of::<MEMORYSTATUSEX>() as u32;
            if GlobalMemoryStatusEx(&mut mem) != 0 && mem.ull_total_phys > 0 {
                Some(mem.ull_avail_phys / (1024 * 1024))
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

    pub fn enumerate_live_services() -> std::collections::HashMap<String, (String, String, String)> {
        let mut out = std::collections::HashMap::new();
        unsafe {
            let scm = OpenSCManagerW(std::ptr::null(), std::ptr::null(), 0x0005);
            if scm == 0 {
                return out;
            }
            let mut bytes_needed: u32 = 0;
            let mut services_returned: u32 = 0;
            let mut resume_handle: u32 = 0;
            let _ = EnumServicesStatusExW(
                scm,
                0,
                0x30,
                0x03,
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

    pub fn read_service_scm_descriptions(
        names: &[String],
    ) -> std::collections::HashMap<String, String> {
        let mut out = std::collections::HashMap::new();
        if names.is_empty() {
            return out;
        }
        let mut missing: Vec<String> = Vec::new();
        if let Ok(guard) = super::SERVICE_SCM_DESC_CACHE.lock() {
            if let Some(cache) = guard.as_ref() {
                for name in names {
                    let key = name.to_lowercase();
                    if let Some(cached) = cache.get(&key) {
                        if let Some(text) = cached {
                            out.insert(key, text.clone());
                        }
                    } else {
                        missing.push(name.clone());
                    }
                }
            } else {
                missing.extend(names.iter().cloned());
            }
        } else {
            missing.extend(names.iter().cloned());
        }

        if missing.is_empty() {
            return out;
        }

        let mut newly_resolved: Vec<(String, Option<String>)> = Vec::with_capacity(missing.len());
        unsafe {
            let scm = OpenSCManagerW(std::ptr::null(), std::ptr::null(), 0x0001);
            if scm != 0 {
                for name in &missing {
                    let key = name.to_lowercase();
                    let name_w = to_wide(name);
                    let svc = OpenServiceW(scm, name_w.as_ptr(), 0x0001);
                    let mut resolved: Option<String> = None;
                    if svc != 0 {
                        let mut needed: u32 = 0;
                        let _ = QueryServiceConfig2W(svc, 1, std::ptr::null_mut(), 0, &mut needed);
                        if needed > 0 && needed <= 65536 {
                            let mut buf = vec![0u8; needed as usize];
                            if QueryServiceConfig2W(
                                svc,
                                1,
                                buf.as_mut_ptr(),
                                needed,
                                &mut needed,
                            ) != 0
                            {
                                let sd = &*(buf.as_ptr() as *const SERVICE_DESCRIPTIONW);
                                if !sd.lp_description.is_null() {
                                    let text = wide_ptr_to_string(sd.lp_description);
                                    if !text.is_empty() && !text.starts_with('@') {
                                        resolved = Some(text);
                                    }
                                }
                            }
                        }
                        let _ = CloseServiceHandle(svc);
                    }
                    if let Some(ref text) = resolved {
                        out.insert(key.clone(), text.clone());
                    }
                    newly_resolved.push((key, resolved));
                }
                let _ = CloseServiceHandle(scm);
            }
        }

        if let Ok(mut guard) = super::SERVICE_SCM_DESC_CACHE.lock() {
            let cache = guard.get_or_insert_with(std::collections::HashMap::new);
            if cache.len() > 2048 {
                cache.clear();
            }
            for (k, v) in newly_resolved {
                cache.insert(k, v);
            }
        }

        out
    }

    pub fn is_current_process_elevated() -> bool {
        unsafe {
            let mut token: isize = 0;
            if OpenProcessToken(GetCurrentProcess(), 0x0008, &mut token) == 0 {
                return false;
            }
            let mut elevation: u32 = 0;
            let mut ret_len: u32 = 0;
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

    pub fn read_exe_metadata(exe_path: &str) -> super::ExeMetadata {
        let trimmed_path = exe_path.trim();
        if trimmed_path.is_empty() {
            return super::ExeMetadata::default();
        }
        let cache_key = trimmed_path.to_ascii_lowercase();
        if let Ok(guard) = super::EXE_METADATA_CACHE.lock() {
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
                super::ExeMetadata::default()
            } else {
                let mut buf = vec![0u8; size as usize];
                if GetFileVersionInfoW(
                    path_w.as_ptr(),
                    0,
                    size,
                    buf.as_mut_ptr() as *mut std::ffi::c_void,
                ) == 0
                {
                    super::ExeMetadata::default()
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
                    for fallback in [
                        (0x0409, 0x04B0),
                        (0x0419, 0x04B0),
                        (0x0409, 0x04E4),
                        (0x0000, 0x04B0),
                    ] {
                        if !langs.contains(&fallback) {
                            langs.push(fallback);
                        }
                    }

                    let query_field = |field: &str| -> Option<String> {
                        for &(lang, cp) in &langs {
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
                                let end =
                                    units.iter().position(|&c| c == 0).unwrap_or(units.len());
                                let s =
                                    String::from_utf16_lossy(&units[..end]).trim().to_string();
                                if !s.is_empty() {
                                    return Some(s);
                                }
                            }
                        }
                        None
                    };

                    let file_description = query_field("FileDescription");
                    let product_name = query_field("ProductName");
                    let company_name = query_field("CompanyName");
                    let display_name = file_description.clone().or_else(|| product_name.clone());
                    super::ExeMetadata {
                        display_name,
                        file_description,
                        product_name,
                        company_name,
                    }
                }
            }
        };

        if let Ok(mut guard) = super::EXE_METADATA_CACHE.lock() {
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
                if wlan_enum(client, std::ptr::null_mut(), &mut list_ptr) == 0
                    && !list_ptr.is_null()
                {
                    let count = ((*list_ptr).number_of_items as usize).min(64);
                    let base = (*list_ptr).interface_info.as_ptr();
                    for i in 0..count {
                        let iface = &*base.add(i);
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
                    let end = wide_slice
                        .iter()
                        .position(|&c| c == 0)
                        .unwrap_or(wide_slice.len());
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

        let mut folder_sources: Vec<(
            std::path::PathBuf,
            &str,
            &str,
            &std::collections::HashMap<String, bool>,
        )> = Vec::new();
        if let Some(appdata) = std::env::var_os("APPDATA") {
            folder_sources.push((
                std::path::PathBuf::from(appdata)
                    .join(r"Microsoft\Windows\Start Menu\Programs\Startup"),
                "startup_user",
                "Папка автозагрузки",
                &hkcu_folder_app,
            ));
        }
        if let Some(progdata) =
            std::env::var_os("ProgramData").or_else(|| std::env::var_os("ALLUSERSPROFILE"))
        {
            folder_sources.push((
                std::path::PathBuf::from(progdata)
                    .join(r"Microsoft\Windows\Start Menu\Programs\Startup"),
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
                        if let Some(state) =
                            read_reg_dword_root(HKEY_CURRENT_USER, &task_sub, "State")
                        {
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
                                memory_mb =
                                    ((mem.working_set_size as f64) / (1024.0 * 1024.0) * 10.0)
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
                                exe_path =
                                    String::from_utf16_lossy(&path_buf[..(path_len as usize)])
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

    fn enable_privilege(privilege_name: &str) -> bool {
        unsafe {
            let mut token: isize = 0;
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
                    attributes: 0x0000_0002,
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

    pub fn confirm_reboot_dialog_win32() -> bool {
        unsafe {
            let text = to_wide("Перезагрузить компьютер сейчас?\nНесохранённые данные в открытых программах могут быть потеряны.");
            let caption = to_wide("Ultra Gaming Mode — Перезагрузка ПК");
            let flags = 0x0004 | 0x0030 | 0x0100 | 0x1_0000 | 0x4_0000;
            MessageBoxW(0, text.as_ptr(), caption.as_ptr(), flags) == 6
        }
    }

    pub fn query_installed_msi_product_code() -> Option<String> {
        type MsiEnumRelatedProductsWFn =
            unsafe extern "system" fn(*const u16, u32, u32, *mut u16) -> u32;
        unsafe {
            let h_msi = LoadLibraryA(b"msi.dll\0".as_ptr());
            if h_msi.is_null() {
                return None;
            }
            let proc = GetProcAddress(h_msi, b"MsiEnumRelatedProductsW\0".as_ptr());
            let mut found = None;
            if !proc.is_null() {
                let enum_fn: MsiEnumRelatedProductsWFn = std::mem::transmute(proc);
                let upgrade_code = to_wide("{7630B84C-95F6-58D0-8C30-969D061C38B0}");
                let mut prod_buf = [0u16; 40];
                if enum_fn(upgrade_code.as_ptr(), 0, 0, prod_buf.as_mut_ptr()) == 0 {
                    let end = prod_buf.iter().position(|&c| c == 0).unwrap_or(prod_buf.len());
                    let code = String::from_utf16_lossy(&prod_buf[..end]).trim().to_string();
                    if !code.is_empty() {
                        found = Some(code);
                    }
                }
            }
            let _ = FreeLibrary(h_msi);
            found
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
pub mod timer {
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

    pub fn lock_timer_resolution_05ms() -> Result<(f64, f64), String> {
        set_timer_resolution(5000)
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
            if status >= 0 || status == -1073741240 {
                let queried = query_timer_resolution().unwrap_or(final_res as f64 / 10000.0);
                Ok(queried)
            } else {
                Err(format!("Ошибка сброса NtSetTimerResolution: 0x{:08X}", status))
            }
        }
    }
}

#[cfg(not(target_os = "windows"))]
pub mod timer {
    pub fn query_timer_resolution() -> Option<f64> {
        Some(0.5)
    }
    pub fn set_timer_resolution(_desired_100ns: u32) -> Result<(f64, f64), String> {
        super::TIMER_LOCKED.store(true, std::sync::atomic::Ordering::SeqCst);
        Ok((0.5, 0.5))
    }
    pub fn lock_timer_resolution_05ms() -> Result<(f64, f64), String> {
        set_timer_resolution(5000)
    }
    pub fn unlock_timer_resolution() -> Result<f64, String> {
        super::TIMER_LOCKED.store(false, std::sync::atomic::Ordering::SeqCst);
        Ok(15.6)
    }
}

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

pub fn invalidate_active_state_cache() {
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
        String::from_utf8_lossy(include_bytes!("../Config/service_descriptions.json")).into_owned()
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
        String::from_utf8_lossy(include_bytes!("../Config/process_descriptions.json")).into_owned()
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

fn extract_concise_non_pass_error(stdout: &str, stderr: &str) -> Option<String> {
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

fn format_verify_log_timestamp() -> (String, u16) {
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

fn resolve_curl_exe() -> PathBuf {
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

fn norm_dir_key(p: &Path) -> String {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_core_protection_guards() {
        let lists = read_services_lists_sync().expect("load service lists");
        for svc in ["FACEIT", "zapret", "WinDivert", "WinDivert14"] {
            assert!(lists.whitelist.iter().any(|s| s == svc));
            assert!(!lists.blacklist.iter().any(|s| s.name.eq_ignore_ascii_case(svc)));
        }
        assert!(is_immutable_core_service("RpcSs"));
        assert!(is_immutable_core_service("Audiosrv"));
        for proc_name in ["lsass", "dwm", "explorer", "UltraGamingMode", "vgk", "winws", "zapret"] {
            assert!(is_protected_process_name(proc_name));
        }
        assert_eq!(classify_process_protection("UltraGamingMode"), Some("self_app"));
        assert_eq!(classify_process_protection("msedgewebview2"), Some("os_core"));
    }

    #[test]
    fn test_config_migration_heals_corrupt_and_legacy_files() {
        let tmp = std::env::temp_dir().join(format!("ugm_min_mig_{}", std::process::id()));
        let cfg = tmp.join("Config");
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(&cfg).unwrap();

        std::fs::write(cfg.join("tuning.json"), "{corrupt").unwrap();
        std::fs::write(cfg.join("services_whitelist.json"), r#"{"ProtectedServices":["Audiosrv"]}"#).unwrap();
        std::fs::write(cfg.join("services_blacklist.json"), r#"{"TargetServices":[{"Name":"Spooler"},{"Name":"zapret"}]}"#).unwrap();
        std::fs::write(cfg.join("startup_apps.json"), r#"{"BlacklistProcesses":["Discord","winws"],"ProtectedStartupNames":[]}"#).unwrap();

        migrate_user_configs_in_place(&tmp).expect("migrate configs");
        let healed: TuningConfig = serde_json::from_str(&std::fs::read_to_string(cfg.join("tuning.json")).unwrap()).unwrap();
        assert_eq!(healed, TuningConfig::default());

        let bl: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(cfg.join("services_blacklist.json")).unwrap()).unwrap();
        assert!(!bl.to_string().contains("zapret"));
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_verify_verdict_and_updater_sha256_guards() {
        assert!(matches!(
            evaluate_verify_output(true, Some(0), "  [PASS] partial\n", ""),
            VerifyVerdict::Unknown { .. }
        ));
        assert!(matches!(
            evaluate_verify_output(true, Some(0), "TEST RESULTS: 6 Tests Run | 0 Failures\n", ""),
            VerifyVerdict::Passed { .. }
        ));

        let ok_dl = "https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases/download/v9.9.0/UltraGamingMode.exe";
        let ok_sum = "https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases/download/v9.9.0/SHA256SUMS.txt";
        assert!(validate_release_update_urls(ok_dl, ok_sum, "UltraGamingMode.exe", "4.1.1").is_ok());
        assert!(validate_release_update_urls("https://evil.example.com/UltraGamingMode.exe", ok_sum, "UltraGamingMode.exe", "4.1.1").is_err());

        let payload = b"MZ_payload";
        let manifest = format!("{}  UltraGamingMode.exe\n", sha256_hex(payload));
        assert!(verify_sha256_manifest(&manifest, "UltraGamingMode.exe", payload).is_ok());
        assert!(verify_sha256_manifest(&manifest, "UltraGamingMode.exe", b"MZ_tampered").is_err());
    }
}