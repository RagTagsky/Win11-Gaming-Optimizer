pub mod backend;
pub mod dwm;
pub mod themes;
pub mod tray;
pub mod ui_bridge;

pub fn run() {
    ui_bridge::run_native_app();
}
