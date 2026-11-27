pub const DWMWA_USE_IMMUTABLE_DARK_MODE: u32 = 20;
pub const DWMWA_USE_IMMUTABLE_DARK_MODE_BEFORE_20H1: u32 = 19;
pub const DWMWA_WINDOW_CORNER_PREFERENCE: u32 = 33;
pub const DWMWA_BORDER_COLOR: u32 = 34;
pub const DWMWCP_ROUND: i32 = 2;

pub const WM_SETICON: u32 = 0x0080;
pub const ICON_SMALL: usize = 0;
pub const ICON_BIG: usize = 1;
pub const IMAGE_ICON: u32 = 1;
pub const LR_DEFAULTCOLOR: u32 = 0x0000;
pub const LR_SHARED: u32 = 0x8000;
pub const SM_CXICON: i32 = 11;
pub const SM_CYICON: i32 = 12;
pub const SM_CXSMICON: i32 = 49;
pub const SM_CYSMICON: i32 = 50;
pub const GCLP_HICON: i32 = -14;
pub const GCLP_HICONSM: i32 = -34;

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
#[link(name = "kernel32")]
extern "system" {
    fn GetModuleHandleW(lp_module_name: *const u16) -> isize;
}

#[cfg(target_os = "windows")]
#[link(name = "user32")]
extern "system" {
    fn GetSystemMetrics(n_index: i32) -> i32;
    fn LoadImageW(
        h_inst: isize,
        name: *const u16,
        img_type: u32,
        cx: i32,
        cy: i32,
        fu_load: u32,
    ) -> isize;
    fn SendMessageW(hwnd: isize, msg: u32, w_param: usize, l_param: isize) -> isize;
    #[cfg(target_pointer_width = "64")]
    fn SetClassLongPtrW(hwnd: isize, n_index: i32, dw_new_long: isize) -> usize;
    #[cfg(target_pointer_width = "32")]
    fn SetClassLongW(hwnd: isize, n_index: i32, dw_new_long: i32) -> u32;
}

#[cfg(target_os = "windows")]
unsafe fn set_window_class_icon(hwnd: isize, n_index: i32, hicon: isize) {
    #[cfg(target_pointer_width = "64")]
    {
        let _ = SetClassLongPtrW(hwnd, n_index, hicon);
    }
    #[cfg(target_pointer_width = "32")]
    {
        let _ = SetClassLongW(hwnd, n_index, hicon as i32);
    }
}

#[cfg(target_os = "windows")]
pub fn apply_window_icon_from_exe_resource(hwnd: isize) -> bool {
    if hwnd == 0 {
        return false;
    }
    unsafe {
        let hinst = GetModuleHandleW(std::ptr::null());
        if hinst == 0 {
            return false;
        }
        let res_id = 1usize as *const u16;
        let big_w = GetSystemMetrics(SM_CXICON).max(32);
        let big_h = GetSystemMetrics(SM_CYICON).max(32);
        let small_w = GetSystemMetrics(SM_CXSMICON).max(16);
        let small_h = GetSystemMetrics(SM_CYSMICON).max(16);

        let hicon_big = LoadImageW(hinst, res_id, IMAGE_ICON, big_w, big_h, LR_DEFAULTCOLOR | LR_SHARED);
        let hicon_small = LoadImageW(hinst, res_id, IMAGE_ICON, small_w, small_h, LR_DEFAULTCOLOR | LR_SHARED);

        let mut applied = false;
        if hicon_big != 0 {
            let _ = SendMessageW(hwnd, WM_SETICON, ICON_BIG, hicon_big);
            set_window_class_icon(hwnd, GCLP_HICON, hicon_big);
            applied = true;
        }
        if hicon_small != 0 {
            let _ = SendMessageW(hwnd, WM_SETICON, ICON_SMALL, hicon_small);
            set_window_class_icon(hwnd, GCLP_HICONSM, hicon_small);
            applied = true;
        }
        applied
    }
}

#[cfg(not(target_os = "windows"))]
pub fn apply_window_icon_from_exe_resource(_hwnd: isize) -> bool {
    false
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
        assert_eq!(WM_SETICON, 0x0080);
        assert_eq!(ICON_SMALL, 0);
        assert_eq!(ICON_BIG, 1);
        assert_eq!(IMAGE_ICON, 1);
        assert!(!apply_window_icon_from_exe_resource(0));

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
