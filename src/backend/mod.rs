pub mod actions;
pub mod autostart;
pub mod config;
pub mod processes;
pub mod timer;
pub mod types;
pub mod updater;
#[cfg(target_os = "windows")]
pub mod win_hw;

pub use actions::*;
pub use autostart::*;
pub use config::*;
pub use processes::*;
pub use types::*;
pub use updater::*;

#[allow(unused_imports)]
pub(crate) use config::{decode_oem_line, infer_service_category, read_cached_active_state};
#[allow(unused_imports)]
pub(crate) use types::{
    record_startup_migration_log, write_json_no_bom, CachedActiveState, CachedHardwareStatic,
    ServiceFeaturePackDef, ACTIVE_STATE_CACHE, BACKUPS_ACL_INIT,
    CRITICAL_PROTECTED_PROCESSES, EXACT_FIXED_VERSION_SERVICES, EXE_METADATA_CACHE,
    HW_STATIC_CACHE, IMMUTABLE_CORE_SERVICES, RUNTIME_ROOT_CACHE, SERVICE_FEATURE_PACKS,
    SERVICE_SCM_DESC_CACHE, STARTUP_MIGRATION_LOGS,
};
#[cfg(target_os = "windows")]
#[allow(unused_imports)]
pub(crate) use types::CREATE_NO_WINDOW;
#[allow(unused_imports)]
pub(crate) use types::normalize_safety_level;
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_core_protection_guards() {
        let lists = read_services_lists_sync().expect("load service lists");
        for svc in ["FACEIT", "zapret", "WinDivert", "WinDivert14"] {
            assert!(lists.whitelist.iter().any(|s| s == svc));
            assert!(!lists.blacklist.iter().any(|s| s.name.eq_ignore_ascii_case(svc)));
        }
        assert!(is_immutable_core_service("RpcSs"));
        assert!(is_immutable_core_service("Audiosrv"));
        for proc_name in ["lsass", "dwm", "explorer", "UltraGamingMode", "vgk", "winws", "zapret"] {
            assert!(is_protected_process_name(proc_name));
        }
        assert_eq!(classify_process_protection("UltraGamingMode"), Some("self_app"));
        assert_eq!(classify_process_protection("msedgewebview2"), Some("os_core"));
    }

    #[test]
    fn test_config_migration_heals_corrupt_and_legacy_files() {
        let tmp = std::env::temp_dir().join(format!("ugm_min_mig_{}", std::process::id()));
        let cfg = tmp.join("Config");
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(&cfg).unwrap();

        std::fs::write(cfg.join("tuning.json"), "{corrupt").unwrap();
        std::fs::write(cfg.join("services_whitelist.json"), r#"{"ProtectedServices":["Audiosrv"]}"#).unwrap();
        std::fs::write(cfg.join("services_blacklist.json"), r#"{"TargetServices":[{"Name":"Spooler"},{"Name":"zapret"}]}"#).unwrap();
        std::fs::write(cfg.join("startup_apps.json"), r#"{"BlacklistProcesses":["Discord","winws"],"ProtectedStartupNames":[]}"#).unwrap();

        migrate_user_configs_in_place(&tmp).expect("migrate configs");
        let healed: TuningConfig = serde_json::from_str(&std::fs::read_to_string(cfg.join("tuning.json")).unwrap()).unwrap();
        assert_eq!(healed, TuningConfig::default());

        let bl: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(cfg.join("services_blacklist.json")).unwrap()).unwrap();
        assert!(!bl.to_string().contains("zapret"));
        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_verify_verdict_and_updater_sha256_guards() {
        assert!(matches!(
            evaluate_verify_output(true, Some(0), "  [PASS] partial\n", ""),
            VerifyVerdict::Unknown { .. }
        ));
        assert!(matches!(
            evaluate_verify_output(true, Some(0), "TEST RESULTS: 6 Tests Run | 0 Failures\n", ""),
            VerifyVerdict::Passed { .. }
        ));

        let ok_dl = "https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases/download/v9.9.0/UltraGamingMode.exe";
        let ok_sum = "https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases/download/v9.9.0/SHA256SUMS.txt";
        assert!(validate_release_update_urls(ok_dl, ok_sum, "UltraGamingMode.exe", "4.1.1").is_ok());
        assert!(validate_release_update_urls("https://evil.example.com/UltraGamingMode.exe", ok_sum, "UltraGamingMode.exe", "4.1.1").is_err());

        let payload = b"MZ_payload";
        let manifest = format!("{}  UltraGamingMode.exe\n", sha256_hex(payload));
        assert!(verify_sha256_manifest(&manifest, "UltraGamingMode.exe", payload).is_ok());
        assert!(verify_sha256_manifest(&manifest, "UltraGamingMode.exe", b"MZ_tampered").is_err());
    }
}
