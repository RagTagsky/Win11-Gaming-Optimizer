pub const DWMWA_USE_IMMUTABLE_DARK_MODE: u32 = 20;
pub const DWMWA_USE_IMMUTABLE_DARK_MODE_BEFORE_20H1: u32 = 19;

#[cfg(target_os = "windows")]
#[link(name = "dwmapi")]
extern "system" {
    fn DwmSetWindowAttribute(
        hwnd: isize,
        dw_attribute: u32,
        pv_attribute: *const std::ffi::c_void,
        cb_attribute: u32,
    ) -> i32;
}

#[cfg(target_os = "windows")]
pub fn apply_dwm_dark_mode(hwnd: isize, is_dark: bool) -> Result<(), String> {
    if hwnd == 0 {
        return Err("Недопустимый дескриптор окна (HWND = 0) для DwmSetWindowAttribute.".to_string());
    }

    unsafe {
        let dark_flag: i32 = if is_dark { 1 } else { 0 };
        let flag_ptr = &dark_flag as *const i32 as *const std::ffi::c_void;
        let flag_size = std::mem::size_of::<i32>() as u32;

        let mut hr = DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMUTABLE_DARK_MODE, flag_ptr, flag_size);
        if hr != 0 {
            hr = DwmSetWindowAttribute(
                hwnd,
                DWMWA_USE_IMMUTABLE_DARK_MODE_BEFORE_20H1,
                flag_ptr,
                flag_size,
            );
        }

        if hr == 0 {
            Ok(())
        } else {
            Err(format!(
                "DwmSetWindowAttribute завершилась с ошибкой: HRESULT 0x{:08X}",
                hr as u32
            ))
        }
    }
}

#[cfg(not(target_os = "windows"))]
pub fn apply_dwm_dark_mode(_hwnd: isize, _is_dark: bool) -> Result<(), String> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_apply_dwm_dark_mode_constants_and_zero_hwnd() {
        assert_eq!(DWMWA_USE_IMMUTABLE_DARK_MODE, 20);
        assert_eq!(DWMWA_USE_IMMUTABLE_DARK_MODE_BEFORE_20H1, 19);

        let res = apply_dwm_dark_mode(0, true);
        #[cfg(target_os = "windows")]
        assert!(res.is_err(), "HWND = 0 must return an Err on Windows");
        #[cfg(not(target_os = "windows"))]
        assert!(res.is_ok());
    }
}
