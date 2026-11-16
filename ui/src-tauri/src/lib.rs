use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::OnceLock;

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
}

impl Default for TuningConfig {
    fn default() -> Self {
        Self {
            disable_fullscreen_optimizations: true,
            disable_mouse_accel: false,
            disable_nvidia_dynamic_pstate: false,
            enable_net_adapter_msi: true,
            input_buffer_queue_size: 100,
        }
    }
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
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct ServicesLists {
    pub blacklist: Vec<BlacklistServiceItem>,
    pub whitelist: Vec<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct ProcessItem {
    pub pid: u32,
    pub name: String,
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

pub fn is_protected_process_name(name: &str) -> bool {
    let clean = strip_exe_suffix(name);
    if !is_safe_identifier(clean) {
        return true;
    }
    CRITICAL_PROTECTED_PROCESSES
        .iter()
        .any(|p| p.eq_ignore_ascii_case(clean))
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
    const HKEY_LOCAL_MACHINE: usize = 0x80000002;
    const KEY_READ: u32 = 0x20019;
    const REG_SZ: u32 = 1;
    const REG_EXPAND_SZ: u32 = 2;
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
        fn RegCloseKey(hKey: usize) -> i32;
        fn OpenSCManagerW(
            lpMachineName: *const u16,
            lpDatabaseName: *const u16,
            dwDesiredAccess: u32,
        ) -> usize;
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
        fn GetLastError() -> u32;
    }

    #[link(name = "user32")]
    extern "system" {
        fn GetSystemMetrics(nIndex: i32) -> i32;
    }

    fn to_wide(s: &str) -> Vec<u16> {
        s.encode_utf16().chain(std::iter::once(0)).collect()
    }

    pub fn read_reg_string(subkey: &str, value_name: &str) -> Option<String> {
        unsafe {
            let mut hkey: usize = 0;
            let subkey_w = to_wide(subkey);
            if RegOpenKeyExW(HKEY_LOCAL_MACHINE, subkey_w.as_ptr(), 0, KEY_READ, &mut hkey) != 0 {
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

    pub fn read_reg_dword(subkey: &str, value_name: &str) -> Option<u32> {
        unsafe {
            let mut hkey: usize = 0;
            let subkey_w = to_wide(subkey);
            if RegOpenKeyExW(HKEY_LOCAL_MACHINE, subkey_w.as_ptr(), 0, KEY_READ, &mut hkey) != 0 {
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
    ) -> std::collections::HashMap<String, (String, String)> {
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
                        out.insert(name.to_lowercase(), (status, disp));
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

    pub fn enumerate_running_processes_raw() -> Vec<(u32, String, f64)> {
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
                            let _ = CloseHandle(h_proc);
                        }
                        out.push((pid, clean_name, memory_mb));
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
                let cur_ms = final_res as f64 / 10000.0;
                let max_ms = max_res as f64 / 10000.0;
                Ok((cur_ms, max_ms))
            } else {
                Err(format!("Ошибка NtSetTimerResolution: 0x{:08X}", status))
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
        Ok((0.5, 0.5))
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
    let n = name.to_lowercase();
    let r = reason.to_lowercase();
    if n.starts_with("xbl")
        || n.starts_with("xbox")
        || n == "gamingservices"
        || n == "gamingservicesnet"
        || n == "bcastdvruserservice"
        || r.contains("xbox")
        || r.contains("gamedvr")
    {
        "Xbox".to_string()
    } else if n == "spooler"
        || n == "printnotify"
        || n == "printworkflowusersvc"
        || n == "printdeviceconfigurationservice"
        || n == "fax"
        || n == "stisvc"
        || n == "wia"
        || n == "wiarpc"
        || r.contains("print")
        || r.contains("fax")
        || r.contains("scanner")
        || r.contains("imaging")
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
        || n == "wdi"
        || n == "wdisystemhost"
        || n == "wdiservicehost"
        || n == "trkwks"
        || n == "ceip"
        || n == "uhssvc"
        || r.contains("telemetry")
        || r.contains("diagnostic")
        || r.contains("error reporting")
        || r.contains("customer experience")
        || r.contains("crash")
    {
        "Telemetry".to_string()
    } else if n.starts_with("lanman")
        || n.starts_with("remote")
        || n == "termservice"
        || n == "umrdpservice"
        || n == "sessionenv"
        || n == "icssvc"
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
        || n == "winrm"
        || n == "workfolderssvc"
        || n == "cscservice"
        || n == "peerdistsvc"
        || n == " RasAuto".trim().to_lowercase()
        || r.contains("network")
        || r.contains("remote")
        || r.contains("routing")
        || r.contains("discovery")
        || r.contains("sharing")
        || r.contains("smb")
        || r.contains("netbios")
        || r.contains("upnp")
        || r.contains("ipv6")
        || r.contains("vpn")
    {
        "Network".to_string()
    } else {
        "System".to_string()
    }
}

fn read_system_status_sync() -> Result<SystemStatus, String> {
    let root = get_workspace_root();
    let active_state_path = root.join("Backups").join("active_state.json");

    let mut mode = "Normal".to_string();
    let mut active_since: Option<String> = None;

    #[cfg(target_os = "windows")]
    let mut cpu = win_hw::detect_cpu_name().unwrap_or_else(|| "Неизвестный процессор".to_string());
    #[cfg(not(target_os = "windows"))]
    let mut cpu = "Processor".to_string();

    #[cfg(target_os = "windows")]
    let mut gpu = win_hw::detect_gpu_name().unwrap_or_else(|| "Видеоадаптер".to_string());
    #[cfg(not(target_os = "windows"))]
    let mut gpu = "Graphics Adapter".to_string();

    #[cfg(target_os = "windows")]
    let mut ram = win_hw::detect_ram_gb().unwrap_or_else(|| "ОЗУ".to_string());
    #[cfg(not(target_os = "windows"))]
    let mut ram = "RAM".to_string();

    if active_state_path.exists() {
        if let Ok(content) = std::fs::read_to_string(&active_state_path) {
            let clean = content.trim_start_matches('\u{feff}');
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(clean) {
                if let Some(state_str) = json.get("State").and_then(|v| v.as_str()) {
                    mode = match state_str {
                        "GameMode_Active" => "Gaming".to_string(),
                        "Armed" => "Armed".to_string(),
                        _ => "Normal".to_string(),
                    };
                }
                if mode == "Gaming" || mode == "Armed" {
                    active_since = json
                        .get("Timestamp")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string());
                }
                if let Some(hw) = json.get("HardwareProfile") {
                    if let Some(c) = hw.get("CpuName").and_then(|v| v.as_str()) {
                        if !c.trim().is_empty() {
                            cpu = c.trim().to_string();
                        }
                    }
                    if let Some(g) = hw.get("GpuName").and_then(|v| v.as_str()) {
                        if !g.trim().is_empty() {
                            gpu = g.trim().to_string();
                        }
                    }
                    if ram == "ОЗУ" {
                        if let Some(r) = hw.get("TotalRamGB").and_then(|v| v.as_f64()) {
                            if r > 0.0 {
                                ram = format!("{:.0} ГБ ОЗУ", r);
                            }
                        }
                    }
                }
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
    let active_state_path = root.join("Backups").join("active_state.json");

    let mut localized_names = std::collections::HashMap::<String, String>::new();
    if let Ok(raw_state) = std::fs::read_to_string(&active_state_path) {
        let clean_state = raw_state.trim_start_matches('\u{feff}');
        if let Ok(state_val) = serde_json::from_str::<serde_json::Value>(clean_state) {
            if let Some(svcs) = state_val.get("Services").and_then(|v| v.as_array()) {
                for s in svcs {
                    let s_name = s.get("Name").and_then(|v| v.as_str()).unwrap_or("").trim();
                    let s_disp = s
                        .get("DisplayName")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .trim();
                    if !s_name.is_empty() && !s_disp.is_empty() {
                        localized_names.insert(s_name.to_lowercase(), s_disp.to_string());
                    }
                }
            }
        }
    }

    #[cfg(target_os = "windows")]
    let live_map = if include_live_status {
        win_hw::enumerate_live_services()
    } else {
        std::collections::HashMap::new()
    };

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

    let mut blacklist: Vec<BlacklistServiceItem> = Vec::with_capacity(arr_bl.len());
    for item in arr_bl {
        if let Ok(mut parsed) = serde_json::from_value::<BlacklistServiceItem>(item.clone()) {
            #[cfg(target_os = "windows")]
            if include_live_status {
                let lower = parsed.name.to_lowercase();
                let mut matched = live_map.get(&lower);
                if matched.is_none() {
                    let prefix_under = format!("{}_", lower);
                    for (k, v) in &live_map {
                        if k.starts_with(&prefix_under)
                            || (k.starts_with(&lower)
                                && k.len() > lower.len()
                                && k.as_bytes()[lower.len()].is_ascii_digit())
                        {
                            matched = Some(v);
                            break;
                        }
                    }
                }
                if let Some((status, scm_disp)) = matched {
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
                    parsed.start_type = win_hw::read_service_start_type(&parsed.name);
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
    for item in arr_wl {
        if let Some(s) = item.as_str() {
            whitelist.push(s.to_string());
        }
    }

    Ok(ServicesLists {
        blacklist,
        whitelist,
    })
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

#[tauri::command]
async fn execute_mode_action(action: String, profile: String) -> Result<ActionResult, String> {
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

    tauri::async_runtime::spawn_blocking(move || {
        let root = get_workspace_root();
        let script_path = root.join("UltraGamingMode.ps1");

        if safe_action == "Enable" {
            let mut current = load_tuning_from_disk(&root);
            match safe_profile {
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

        run_powershell_script(
            &root,
            &script_path,
            &["-Action", safe_action, "-SkipUpdateCheck"],
            format!("Действие [{}] выполнено успешно.", safe_action),
            "Не удалось запустить PowerShell",
        )
    })
    .await
    .map_err(|e| format!("Сбой фонового выполнения PowerShell: {}", e))?
}

#[tauri::command]
async fn execute_emergency_repair(repair_type: String) -> Result<ActionResult, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let root = get_workspace_root();
        let script_path = root.join("UltraGamingMode.ps1");

        let (args, script_to_run): (Vec<&'static str>, PathBuf) = match repair_type.as_str() {
            "display" => (vec!["-Action", "RepairDisplay", "-SkipUpdateCheck"], script_path),
            "services" => (vec!["-Action", "RepairServices", "-SkipUpdateCheck"], script_path),
            "shaders" => (vec!["-Action", "FlushShaderCache", "-SkipUpdateCheck"], script_path),
            "memory" => (vec!["-Action", "CleanMemory", "-SkipUpdateCheck"], script_path),
            "debloat" => (vec!["-Action", "Debloat", "-SkipUpdateCheck"], script_path),
            "restore_debloat" => (
                vec!["-Action", "RestoreDebloat", "-SkipUpdateCheck"],
                script_path,
            ),
            "verify" => (Vec::new(), root.join("Tests").join("Verify-UniversalEngine.ps1")),
            _ => return Err("Неизвестный тип операции".into()),
        };

        run_powershell_script(
            &root,
            &script_to_run,
            &args,
            format!("Операция [{}] выполнена успешно.", repair_type),
            "Не удалось выполнить команду",
        )
    })
    .await
    .map_err(|e| format!("Сбой фоновой операции обслуживания: {}", e))?
}

#[tauri::command]
fn close_window(window: tauri::WebviewWindow) {
    let _ = window.destroy();
    std::process::exit(0);
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
        arr.push(serde_json::Value::String(clean_name));
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
                        matches!(*s, "Telemetry" | "Xbox" | "Print" | "Network" | "System")
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
        let raw_procs: Vec<(u32, String, f64)> = Vec::new();

        let self_pid = std::process::id();
        let mut processes: Vec<ProcessItem> = raw_procs
            .into_iter()
            .map(|(pid, name, memory_mb)| {
                let is_protected = pid <= 4 || pid == self_pid || is_protected_process_name(&name);
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

        let script_path = root.join("UltraGamingMode.ps1");
        run_powershell_script(
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
        )
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

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_log::Builder::default().build())
        .setup(|_app| {
            std::thread::spawn(|| {
                let _ = get_workspace_root();
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_system_status,
            get_tuning_config,
            save_tuning_config,
            get_services_lists,
            get_running_processes,
            kill_process,
            update_process_list,
            control_service,
            update_service_list,
            set_window_theme,
            execute_mode_action,
            execute_emergency_repair,
            lock_timer_resolution,
            close_window,
            minimize_window,
            toggle_maximize_window,
            start_dragging
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_services_lists_deserializes_all_207_blacklist_and_90_whitelist() {
        let lists = read_services_lists_sync().expect("read_services_lists_sync should succeed");
        assert_eq!(
            lists.blacklist.len(),
            207,
            "Expected 207 blacklisted services from Config/services_blacklist.json"
        );
        assert_eq!(
            lists.whitelist.len(),
            90,
            "Expected 90 whitelisted services from Config/services_whitelist.json"
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
                    "Telemetry" | "Xbox" | "Print" | "Network" | "System"
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
        };
        assert_eq!(resolve_profile_name(&comp), "competitive");

        let aaa = TuningConfig {
            disable_fullscreen_optimizations: false,
            disable_mouse_accel: false,
            disable_nvidia_dynamic_pstate: false,
            enable_net_adapter_msi: true,
            input_buffer_queue_size: 100,
        };
        assert_eq!(resolve_profile_name(&aaa), "aaa");

        let custom_mouse = TuningConfig {
            disable_fullscreen_optimizations: true,
            disable_mouse_accel: true,
            disable_nvidia_dynamic_pstate: false,
            enable_net_adapter_msi: true,
            input_buffer_queue_size: 100,
        };
        assert_eq!(resolve_profile_name(&custom_mouse), "custom");

        let custom_nvidia = TuningConfig {
            disable_fullscreen_optimizations: true,
            disable_mouse_accel: false,
            disable_nvidia_dynamic_pstate: true,
            enable_net_adapter_msi: true,
            input_buffer_queue_size: 100,
        };
        assert_eq!(resolve_profile_name(&custom_nvidia), "custom");

        let custom_queue = TuningConfig {
            disable_fullscreen_optimizations: true,
            disable_mouse_accel: false,
            disable_nvidia_dynamic_pstate: false,
            enable_net_adapter_msi: true,
            input_buffer_queue_size: 120,
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
}
