pub const DWMWA_USE_IMMUTABLE_DARK_MODE: u32 = 20;
pub const DWMWA_USE_IMMUTABLE_DARK_MODE_BEFORE_20H1: u32 = 19;
pub const DWMWA_WINDOW_CORNER_PREFERENCE: u32 = 33;
pub const DWMWA_BORDER_COLOR: u32 = 34;
pub const DWMWCP_ROUND: i32 = 2;

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

#[cfg(target_os = "windows")]
pub fn apply_dwm_window_chrome_with_border_status(
    hwnd: isize,
    is_dark: bool,
    border_rgb: (u8, u8, u8),
) -> (Result<(), String>, bool) {
    let res = apply_dwm_dark_mode(hwnd, is_dark);
    let mut dwm_border_active = false;
    if hwnd != 0 {
        unsafe {
            let corner_pref: i32 = DWMWCP_ROUND;
            let hr_corner = DwmSetWindowAttribute(
                hwnd,
                DWMWA_WINDOW_CORNER_PREFERENCE,
                &corner_pref as *const i32 as *const std::ffi::c_void,
                std::mem::size_of::<i32>() as u32,
            );
            let colorref: u32 =
                (border_rgb.0 as u32) | ((border_rgb.1 as u32) << 8) | ((border_rgb.2 as u32) << 16);
            let hr_border = DwmSetWindowAttribute(
                hwnd,
                DWMWA_BORDER_COLOR,
                &colorref as *const u32 as *const std::ffi::c_void,
                std::mem::size_of::<u32>() as u32,
            );
            dwm_border_active = hr_corner == 0 && hr_border == 0;
        }
    }
    (res, dwm_border_active)
}

#[cfg(target_os = "windows")]
pub fn apply_dwm_window_chrome(hwnd: isize, is_dark: bool, border_rgb: (u8, u8, u8)) -> Result<(), String> {
    apply_dwm_window_chrome_with_border_status(hwnd, is_dark, border_rgb).0
}

#[cfg(not(target_os = "windows"))]
pub fn apply_dwm_dark_mode(_hwnd: isize, _is_dark: bool) -> Result<(), String> {
    Ok(())
}

#[cfg(not(target_os = "windows"))]
pub fn apply_dwm_window_chrome_with_border_status(
    _hwnd: isize,
    _is_dark: bool,
    _border_rgb: (u8, u8, u8),
) -> (Result<(), String>, bool) {
    (Ok(()), false)
}

#[cfg(not(target_os = "windows"))]
pub fn apply_dwm_window_chrome(_hwnd: isize, _is_dark: bool, _border_rgb: (u8, u8, u8)) -> Result<(), String> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_apply_dwm_dark_mode_constants_and_zero_hwnd() {
        assert_eq!(DWMWA_USE_IMMUTABLE_DARK_MODE, 20);
        assert_eq!(DWMWA_USE_IMMUTABLE_DARK_MODE_BEFORE_20H1, 19);
        assert_eq!(DWMWA_WINDOW_CORNER_PREFERENCE, 33);
        assert_eq!(DWMWA_BORDER_COLOR, 34);
        assert_eq!(DWMWCP_ROUND, 2);

        let res = apply_dwm_dark_mode(0, true);
        let (chrome_res, border_active) = apply_dwm_window_chrome_with_border_status(0, true, (0x24, 0x2b, 0x38));
        assert!(!border_active, "HWND = 0 must never report active DWM border");
        #[cfg(target_os = "windows")]
        {
            assert!(res.is_err(), "HWND = 0 must return an Err on Windows");
            assert!(chrome_res.is_err(), "HWND = 0 chrome sync must return an Err on Windows");
        }
        #[cfg(not(target_os = "windows"))]
        {
            assert!(res.is_ok());
            assert!(chrome_res.is_ok());
        }
    }
}
