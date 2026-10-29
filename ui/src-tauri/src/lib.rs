use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::process::Command;
use tauri::Manager;

#[cfg(target_os = "windows")]
use window_vibrancy::apply_mica;

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
}

#[derive(Serialize, Deserialize, Clone)]
pub struct SystemStatus {
    pub mode: String,
    pub profile: String,
    pub hardware: HardwareInfo,
    #[serde(rename = "activeSince")]
    pub active_since: Option<String>,
}

#[derive(Serialize, Deserialize)]
pub struct RepairResult {
    pub success: bool,
    pub message: String,
}

fn get_workspace_root() -> PathBuf {
    // Current working directory or parent of src-tauri
    if let Ok(cwd) = std::env::current_dir() {
        if cwd.join("UltraGamingMode.ps1").exists() {
            return cwd;
        }
        if let Some(parent) = cwd.parent() {
            if parent.join("UltraGamingMode.ps1").exists() {
                return parent.to_path_buf();
            }
        }
    }
    PathBuf::from(r"C:\Users\ragtagsky\Documents\Workstation\E.Mode")
}

#[tauri::command]
fn get_system_status() -> Result<SystemStatus, String> {
    let root = get_workspace_root();
    let active_state_path = root.join("Backups").join("active_state.json");

    let is_gaming = if active_state_path.exists() {
        if let Ok(content) = std::fs::read_to_string(&active_state_path) {
            content.contains("\"State\":  \"GameMode_Active\"")
                || content.contains("\"State\":\"GameMode_Active\"")
        } else {
            false
        }
    } else {
        false
    };

    Ok(SystemStatus {
        mode: if is_gaming { "Gaming".into() } else { "Normal".into() },
        profile: "competitive".into(),
        hardware: HardwareInfo {
            cpu: "AMD Ryzen 5 5600X (6C / 12T @ 4.65 GHz)".into(),
            gpu: "AMD Radeon RX 6600 (8 GB GDDR6)".into(),
            ram: "32 GB DDR4-3600 CL16".into(),
            display: "1920x1080 @ 180Hz (FreeSync / MPO Protected)".into(),
            dpc_latency: "34 µs (Low Jitter TSC)".into(),
            mpo_status: "Protected (Overlay Flickering Suppressed)".into(),
        },
        active_since: if is_gaming { Some("Active".into()) } else { None },
    })
}

#[tauri::command]
async fn execute_mode_action(action: String, _profile: String) -> Result<bool, String> {
    let root = get_workspace_root();
    let script_path = root.join("UltraGamingMode.ps1");

    let output = Command::new("powershell.exe")
        .current_dir(&root)
        .args([
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            script_path.to_str().unwrap_or("UltraGamingMode.ps1"),
            "-Action",
            &action,
        ])
        .output()
        .map_err(|e| format!("Failed to spawn PowerShell: {}", e))?;

    Ok(output.status.success())
}

#[tauri::command]
async fn execute_emergency_repair(repair_type: String) -> Result<RepairResult, String> {
    let root = get_workspace_root();

    let cmd = match repair_type.as_str() {
        "display" => "Import-Module ./Modules/SystemOptimizer.ps1; Repair-DisplayPipeline; Stop-Process -Name dwm -Force -ErrorAction SilentlyContinue",
        "services" => "Import-Module ./Modules/SystemOptimizer.ps1; Repair-CoreServices",
        "shaders" => "Import-Module ./Modules/SystemOptimizer.ps1; Clear-AmdShaderCache",
        "verify" => "powershell.exe -ExecutionPolicy Bypass -NoProfile -File ./Tests/Verify-UniversalEngine.ps1",
        _ => return Err("Неизвестный тип ремонта".into()),
    };

    let output = Command::new("powershell.exe")
        .current_dir(&root)
        .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", cmd])
        .output()
        .map_err(|e| format!("Failed to execute command: {}", e))?;

    let success = output.status.success();
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();

    Ok(RepairResult {
        success,
        message: if success {
            format!("Операция [{}] выполнена успешно.", repair_type)
        } else {
            format!("Операция завершилась с кодом ошибки: {}", stdout)
        },
    })
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_log::Builder::default().build())
        .setup(|app| {
            let window = app.get_webview_window("main").unwrap();

            #[cfg(target_os = "windows")]
            {
                // Apply Windows 11 Mica backdrop effect
                let _ = apply_mica(&window, Some(true));
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_system_status,
            execute_mode_action,
            execute_emergency_repair
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
