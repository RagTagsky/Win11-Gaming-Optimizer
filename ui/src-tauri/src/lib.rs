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

#[derive(Serialize, Deserialize, Clone)]
pub struct ActionResult {
    pub success: bool,
    pub message: String,
}

fn get_workspace_root() -> PathBuf {
    if let Ok(exe) = std::env::current_exe() {
        if let Some(parent) = exe.parent() {
            if parent.join("UltraGamingMode.ps1").exists() {
                return parent.to_path_buf();
            }
            if let Some(grandparent) = parent.parent() {
                if let Some(great) = grandparent.parent() {
                    if let Some(root) = great.parent() {
                        if root.join("UltraGamingMode.ps1").exists() {
                            return root.to_path_buf();
                        }
                    }
                }
            }
        }
    }
    if let Ok(cwd) = std::env::current_dir() {
        if cwd.join("UltraGamingMode.ps1").exists() {
            return cwd;
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
async fn execute_mode_action(action: String, _profile: String) -> Result<ActionResult, String> {
    let root = get_workspace_root();
    let script_path = root.join("UltraGamingMode.ps1");

    let output = Command::new("powershell.exe")
        .current_dir(&root)
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            script_path.to_str().unwrap_or("UltraGamingMode.ps1"),
            "-Action",
            &action,
            "-SkipUpdateCheck",
        ])
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

    let mut cmd = Command::new("powershell.exe");
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
            execute_emergency_repair
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
