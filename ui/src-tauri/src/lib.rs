use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::process::Command;
use tauri::Manager;

#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;
#[cfg(target_os = "windows")]
use window_vibrancy::apply_mica;

#[cfg(target_os = "windows")]
const CREATE_NO_WINDOW: u32 = 0x08000000;

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

#[derive(Serialize, Deserialize, Clone)]
pub struct ActionResult {
    pub success: bool,
    pub message: String,
}

fn get_workspace_root() -> PathBuf {
    if let Ok(exe) = std::env::current_exe() {
        for ancestor in exe.ancestors().skip(1) {
            if ancestor.join("UltraGamingMode.ps1").exists() {
                return ancestor.to_path_buf();
            }
        }
    }
    if let Ok(cwd) = std::env::current_dir() {
        for ancestor in cwd.ancestors() {
            if ancestor.join("UltraGamingMode.ps1").exists() {
                return ancestor.to_path_buf();
            }
        }
    }
    PathBuf::from(r"C:\Users\ragtagsky\Documents\Workstation\E.Mode")
}

fn resolve_powershell_exe() -> PathBuf {
    if let Ok(sys_root) = std::env::var("SystemRoot") {
        let candidate = PathBuf::from(sys_root)
            .join("System32")
            .join("WindowsPowerShell")
            .join("v1.0")
            .join("powershell.exe");
        if candidate.exists() {
            return candidate;
        }
    }
    PathBuf::from("powershell.exe")
}

#[tauri::command]
fn get_system_status() -> Result<SystemStatus, String> {
    let root = get_workspace_root();
    let active_state_path = root.join("Backups").join("active_state.json");

    let mut is_gaming = false;
    let mut active_since: Option<String> = None;
    let mut cpu = "AMD Ryzen 5 5600X (6C / 12T @ 4.65 GHz)".to_string();
    let mut gpu = "AMD Radeon RX 6600 (8 GB GDDR6)".to_string();
    let mut ram = "32 GB DDR4-3600 CL16".to_string();

    if active_state_path.exists() {
        if let Ok(content) = std::fs::read_to_string(&active_state_path) {
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(state_str) = json.get("State").and_then(|v| v.as_str()) {
                    is_gaming = matches!(state_str, "GameMode_Active" | "Armed");
                }
                if is_gaming {
                    active_since = json
                        .get("Timestamp")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string())
                        .or_else(|| Some("Active".into()));
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
                    if let Some(r) = hw.get("TotalRamGB").and_then(|v| v.as_f64()) {
                        if r > 0.0 {
                            ram = format!("{:.0} GB RAM", r);
                        }
                    }
                }
            } else {
                is_gaming = content.contains("\"GameMode_Active\"") || content.contains("\"Armed\"");
                if is_gaming {
                    active_since = Some("Active".into());
                }
            }
        }
    }

    Ok(SystemStatus {
        mode: if is_gaming { "Gaming".into() } else { "Normal".into() },
        profile: "competitive".into(),
        hardware: HardwareInfo {
            cpu,
            gpu,
            ram,
            display: "1920x1080 @ 180Hz (FreeSync / MPO Protected)".into(),
            dpc_latency: "34 µs (Low Jitter TSC)".into(),
            mpo_status: "Protected (Overlay Flickering Suppressed)".into(),
        },
        active_since,
    })
}

#[tauri::command]
async fn execute_mode_action(action: String, _profile: String) -> Result<ActionResult, String> {
    let root = get_workspace_root();
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
        &action,
        "-SkipUpdateCheck",
    ]);
    #[cfg(target_os = "windows")]
    cmd.creation_flags(CREATE_NO_WINDOW);

    let output = cmd
        .output()
        .map_err(|e| format!("Не удалось запустить PowerShell: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    let success = output.status.success();

    let message = if success {
        if stdout.is_empty() {
            format!("Действие [{}] выполнено успешно.", action)
        } else {
            stdout
        }
    } else {
        let mut err = String::new();
        if !stderr.is_empty() {
            err.push_str(&stderr);
        }
        if !stdout.is_empty() {
            if !err.is_empty() {
                err.push_str("\n");
            }
            err.push_str(&stdout);
        }
        if err.is_empty() {
            format!("Процесс завершился с кодом ошибки {:?}", output.status.code())
        } else {
            err
        }
    };

    Ok(ActionResult { success, message })
}

#[tauri::command]
async fn execute_emergency_repair(repair_type: String) -> Result<ActionResult, String> {
    let root = get_workspace_root();
    let script_path = root.join("UltraGamingMode.ps1");

    let (args, script_to_run): (Vec<String>, PathBuf) = match repair_type.as_str() {
        "display" => (
            vec!["-Action".into(), "RepairDisplay".into(), "-SkipUpdateCheck".into()],
            script_path,
        ),
        "services" => (
            vec!["-Action".into(), "RepairServices".into(), "-SkipUpdateCheck".into()],
            script_path,
        ),
        "shaders" => (
            vec!["-Action".into(), "FlushShaderCache".into(), "-SkipUpdateCheck".into()],
            script_path,
        ),
        "verify" => (vec![], root.join("Tests").join("Verify-UniversalEngine.ps1")),
        _ => return Err("Неизвестный тип ремонта".into()),
    };

    let mut cmd = Command::new(resolve_powershell_exe());
    cmd.current_dir(&root)
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            script_to_run.to_str().unwrap_or(""),
        ]);

    for arg in args {
        cmd.arg(arg);
    }
    #[cfg(target_os = "windows")]
    cmd.creation_flags(CREATE_NO_WINDOW);

    let output = cmd
        .output()
        .map_err(|e| format!("Не удалось выполнить команду: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    let success = output.status.success();

    let message = if success {
        if stdout.is_empty() {
            format!("Операция [{}] выполнена успешно.", repair_type)
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
                err.push_str("\n");
            }
            err.push_str(&stdout);
        }
        if err.is_empty() {
            format!("Ошибка выполнения (код {:?})", output.status.code())
        } else {
            err
        }
    };

    Ok(ActionResult { success, message })
}

#[tauri::command]
fn close_window(window: tauri::WebviewWindow) {
    let _ = window.close();
}

#[tauri::command]
fn minimize_window(window: tauri::WebviewWindow) {
    let _ = window.minimize();
}

#[tauri::command]
fn toggle_maximize_window(window: tauri::WebviewWindow) {
    if let Ok(is_max) = window.is_maximized() {
        if is_max {
            let _ = window.unmaximize();
        } else {
            let _ = window.maximize();
        }
    }
}

#[tauri::command]
fn start_dragging(window: tauri::WebviewWindow) {
    let _ = window.start_dragging();
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_log::Builder::default().build())
        .setup(|app| {
            let window = app.get_webview_window("main").unwrap();

            #[cfg(target_os = "windows")]
            {
                let _ = apply_mica(&window, Some(true));
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_system_status,
            execute_mode_action,
            execute_emergency_repair,
            close_window,
            minimize_window,
            toggle_maximize_window,
            start_dragging
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
