#[cfg(target_os = "windows")]
mod imp {
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
                crate::backend::TIMER_LOCKED.store(true, std::sync::atomic::Ordering::SeqCst);
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
            crate::backend::TIMER_LOCKED.store(false, std::sync::atomic::Ordering::SeqCst);
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
mod imp {
    pub fn query_timer_resolution() -> Option<f64> {
        Some(0.5)
    }
    pub fn set_timer_resolution(_desired_100ns: u32) -> Result<(f64, f64), String> {
        crate::backend::TIMER_LOCKED.store(true, std::sync::atomic::Ordering::SeqCst);
        Ok((0.5, 0.5))
    }
    pub fn lock_timer_resolution_05ms() -> Result<(f64, f64), String> {
        set_timer_resolution(5000)
    }
    pub fn unlock_timer_resolution() -> Result<f64, String> {
        crate::backend::TIMER_LOCKED.store(false, std::sync::atomic::Ordering::SeqCst);
        Ok(15.6)
    }
}

pub use imp::*;
