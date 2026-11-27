use std::path::PathBuf;

fn main() {
    println!("cargo:rerun-if-changed=assets/icons/icon.ico");
    println!("cargo:rerun-if-changed=assets/icons/128x128.png");

    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        let out_dir = PathBuf::from(std::env::var("OUT_DIR").expect("OUT_DIR not set"));
        let manifest_dir = PathBuf::from(
            std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR not set"),
        );

        let manifest_xml = r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="requireAdministrator" uiAccess="false" />
      </requestedPrivileges>
    </security>
  </trustInfo>
  <dependency>
    <dependentAssembly>
      <assemblyIdentity
        type="win32"
        name="Microsoft.Windows.Common-Controls"
        version="6.0.0.0"
        processorArchitecture="*"
        publicKeyToken="6595b64144ccf1df"
        language="*"
      />
    </dependentAssembly>
  </dependency>
</assembly>
"#;
        let manifest_path = out_dir.join("app.manifest");
        std::fs::write(&manifest_path, manifest_xml.as_bytes())
            .expect("failed to write app.manifest");

        let icon_path = manifest_dir.join("assets").join("icons").join("icon.ico");
        let escaped_icon = icon_path.to_string_lossy().replace('\\', "\\\\");

        let rc_content = format!(
            r#"#pragma code_page(65001)

1 24 "app.manifest"
1 ICON "{icon}"

1 VERSIONINFO
FILEVERSION 4,1,0,0
PRODUCTVERSION 4,1,0,0
FILEFLAGSMASK 0x3fL
FILEFLAGS 0x0L
FILEOS 0x40004L
FILETYPE 0x1L
FILESUBTYPE 0x0L
BEGIN
  BLOCK "StringFileInfo"
  BEGIN
    BLOCK "040904B0"
    BEGIN
      VALUE "CompanyName", "Ultra Gaming Mode Team"
      VALUE "FileDescription", "Ultra Gaming Mode v4.1.0"
      VALUE "FileVersion", "4.1.0"
      VALUE "InternalName", "UltraGamingMode"
      VALUE "OriginalFilename", "UltraGamingMode.exe"
      VALUE "ProductName", "Ultra Gaming Mode"
      VALUE "ProductVersion", "4.1.0"
    END
  END
  BLOCK "VarFileInfo"
  BEGIN
    VALUE "Translation", 0x0409, 1200
  END
END
"#,
            icon = escaped_icon
        );

        let rc_path = out_dir.join("app.rc");
        std::fs::write(&rc_path, rc_content.as_bytes()).expect("failed to write app.rc");

        embed_resource::compile_for(&rc_path, &["UltraGamingMode"], embed_resource::NONE)
            .manifest_required()
            .expect("failed to compile Windows resource file");
    }
}
