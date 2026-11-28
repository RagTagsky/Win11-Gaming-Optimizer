use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, OnceLock};

pub const APP_VERSION: &str = env!("CARGO_PKG_VERSION");
pub const GITHUB_REPO: &str = "RagTagsky/Win11-Gaming-Optimizer";

#[cfg(target_os = "windows")]
pub(crate) const CREATE_NO_WINDOW: u32 = 0x08000000;

pub struct EmbeddedAsset {
    pub rel_path: &'static str,
    pub bytes: &'static [u8],
    pub preserve_if_exists: bool,
}

pub const EMBEDDED_RUNTIME_ASSETS: &[EmbeddedAsset] = &[
    EmbeddedAsset {
        rel_path: "UltraGamingMode.ps1",
        bytes: include_bytes!("../../UltraGamingMode.ps1"),
        preserve_if_exists: false,
    },
    EmbeddedAsset {
        rel_path: "UltraGamingMode.bat",
        bytes: include_bytes!("../../UltraGamingMode.bat"),
        preserve_if_exists: false,
    },
    EmbeddedAsset {
        rel_path: "Core/ServiceManager.ps1",
        bytes: include_bytes!("../../Core/ServiceManager.ps1"),
        preserve_if_exists: false,
    },
    EmbeddedAsset {
        rel_path: "Core/StateEngine.ps1",
        bytes: include_bytes!("../../Core/StateEngine.ps1"),
        preserve_if_exists: false,
    },
    EmbeddedAsset {
        rel_path: "Core/SystemOptimizer.ps1",
        bytes: include_bytes!("../../Core/SystemOptimizer.ps1"),
        preserve_if_exists: false,
    },
    EmbeddedAsset {
        rel_path: "Config/services_blacklist.json",
        bytes: include_bytes!("../../Config/services_blacklist.json"),
        preserve_if_exists: true,
    },
    EmbeddedAsset {
        rel_path: "Config/services_whitelist.json",
        bytes: include_bytes!("../../Config/services_whitelist.json"),
        preserve_if_exists: true,
    },
    EmbeddedAsset {
        rel_path: "Config/service_descriptions.json",
        bytes: include_bytes!("../../Config/service_descriptions.json"),
        preserve_if_exists: false,
    },
    EmbeddedAsset {
        rel_path: "Config/process_descriptions.json",
        bytes: include_bytes!("../../Config/process_descriptions.json"),
        preserve_if_exists: false,
    },
    EmbeddedAsset {
        rel_path: "Config/startup_apps.json",
        bytes: include_bytes!("../../Config/startup_apps.json"),
        preserve_if_exists: true,
    },
    EmbeddedAsset {
        rel_path: "Config/tuning.json",
        bytes: include_bytes!("../../Config/tuning.json"),
        preserve_if_exists: true,
    },
    EmbeddedAsset {
        rel_path: "Tests/Verify-UniversalEngine.ps1",
        bytes: include_bytes!("../../Tests/Verify-UniversalEngine.ps1"),
        preserve_if_exists: false,
    },
];

pub(crate) static RUNTIME_ROOT_CACHE: OnceLock<PathBuf> = OnceLock::new();
pub(crate) static BACKUPS_ACL_INIT: OnceLock<()> = OnceLock::new();
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

pub(crate) struct CachedHardwareStatic {
    pub(crate) cpu: String,
    pub(crate) gpu: String,
}

pub(crate) static HW_STATIC_CACHE: OnceLock<CachedHardwareStatic> = OnceLock::new();

#[derive(Clone)]
pub(crate) struct CachedActiveState {
    pub(crate) path: PathBuf,
    pub(crate) modified: Option<std::time::SystemTime>,
    pub(crate) len: u64,
    pub(crate) mode: String,
    pub(crate) active_since: Option<String>,
    pub(crate) state_cpu: Option<String>,
    pub(crate) state_gpu: Option<String>,
    pub(crate) state_ram_gb: Option<f64>,
    pub(crate) localized_service_names: std::collections::HashMap<String, String>,
}

#[derive(Clone, Default)]
pub struct ExeMetadata {
    pub display_name: Option<String>,
    pub file_description: Option<String>,
    pub product_name: Option<String>,
    pub company_name: Option<String>,
}

pub(crate) static ACTIVE_STATE_CACHE: Mutex<Option<CachedActiveState>> = Mutex::new(None);
pub(crate) static EXE_METADATA_CACHE: Mutex<Option<std::collections::HashMap<String, ExeMetadata>>> =
    Mutex::new(None);
pub(crate) static SERVICE_SCM_DESC_CACHE: Mutex<Option<std::collections::HashMap<String, Option<String>>>> =
    Mutex::new(None);
pub(crate) static STARTUP_MIGRATION_LOGS: Mutex<Vec<(String, String)>> = Mutex::new(Vec::new());

pub(crate) fn record_startup_migration_log(level: &str, message: impl Into<String>) {
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

pub(crate) fn default_true() -> bool {
    true
}

pub(crate) fn default_auto_purge_ram_threshold_mb() -> u32 {
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

pub(crate) const CRITICAL_PROTECTED_PROCESSES: &[&str] = &[
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

pub(crate) const IMMUTABLE_CORE_SERVICES: &[&str] = &[
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

pub(crate) struct ServiceFeaturePackDef {
    pub(crate) id: &'static str,
    pub(crate) title: &'static str,
    pub(crate) description: &'static str,
    pub(crate) services: &'static [&'static str],
}

pub(crate) const SERVICE_FEATURE_PACKS: &[ServiceFeaturePackDef] = &[
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

pub(crate) const EXACT_FIXED_VERSION_SERVICES: &[&str] = &["FontCache3.0.0.0", "igfxCUIService2.0.0.0"];

pub(crate) fn strip_per_user_service_suffix(name: &str) -> &str {
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

pub(crate) fn normalize_safety_level(raw: &str, is_protected: bool) -> String {
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

pub(crate) fn format_fs_write_error(path: &Path, err: &std::io::Error) -> String {
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

pub(crate) fn write_json_no_bom(path: &Path, val: &impl Serialize) -> Result<(), String> {
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

