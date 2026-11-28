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
