Unicode true
ManifestDPIAware true
SetCompressor /SOLID lzma

!include "MUI2.nsh"
!include "x64.nsh"
!include "FileFunc.nsh"

!ifndef APP_VERSION
  !define APP_VERSION "4.1.0"
!endif
!ifndef OUT_FILE
  !define OUT_FILE "..\.bin\UltraGamingMode-Setup.exe"
!endif

!define APP_NAME "Ultra Gaming Mode"
!define APP_PUBLISHER "Ultra Gaming Mode Team"
!define APP_URL "https://github.com/RagTagsky/Win11-Gaming-Optimizer"
!define APP_EXE "UltraGamingMode.exe"
!define LEGACY_EXE "ultra-gaming-mode.exe"
!define LEGACY_SHORTCUT "UltraGamingMode.lnk"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\UltraGamingMode"
!define MSI_UPGRADE_CODE "{7630B84C-95F6-58D0-8C30-969D061C38B0}"

Var ExistingMsiProductCode

Name "${APP_NAME} v${APP_VERSION}"
OutFile "${OUT_FILE}"
InstallDir "$PROGRAMFILES64\UltraGamingMode"
InstallDirRegKey HKLM "${UNINST_KEY}" "InstallLocation"
RequestExecutionLevel admin
ShowInstDetails show
ShowUnInstDetails show

VIProductVersion "${APP_VERSION}.0"
VIAddVersionKey "ProductName" "${APP_NAME}"
VIAddVersionKey "CompanyName" "${APP_PUBLISHER}"
VIAddVersionKey "FileDescription" "${APP_NAME} Installer"
VIAddVersionKey "FileVersion" "${APP_VERSION}"
VIAddVersionKey "ProductVersion" "${APP_VERSION}"
VIAddVersionKey "LegalCopyright" "Ultra Gaming Mode Team"

!define MUI_ABORTWARNING
!define MUI_ICON "..\assets\icons\icon.ico"
!define MUI_UNICON "..\assets\icons\icon.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Запустить ${APP_NAME}"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Russian"
!insertmacro MUI_LANGUAGE "English"

Function .onInit
  SetShellVarContext all
  ${If} ${RunningX64}
    SetRegView 64
  ${EndIf}

  StrCpy $ExistingMsiProductCode ""
  System::Call 'msi::MsiEnumRelatedProductsW(w "${MSI_UPGRADE_CODE}", i 0, i 0, w .r1) i .r0'
  ${If} $0 == 0
    StrCpy $ExistingMsiProductCode $1
    ${IfNot} ${Silent}
      MessageBox MB_YESNO|MB_ICONQUESTION "Обнаружена установленная MSI-версия ${APP_NAME}. Удалить её автоматически перед установкой Setup-пакета (пользовательские конфиги будут сохранены)?" IDYES +2
      Abort
    ${EndIf}
  ${EndIf}
FunctionEnd

Function un.onInit
  SetShellVarContext all
  ${If} ${RunningX64}
    SetRegView 64
  ${EndIf}
FunctionEnd

!macro StopRunningAppInstances
  nsExec::ExecToStack '"$SYSDIR\taskkill.exe" /F /T /IM ${APP_EXE}'
  Pop $0
  Pop $1
  nsExec::ExecToStack '"$SYSDIR\taskkill.exe" /F /T /IM ${LEGACY_EXE}'
  Pop $0
  Pop $1
  Sleep 400
  ${If} ${FileExists} "$INSTDIR\${APP_EXE}"
    StrCpy $3 0
    ${DoWhile} $3 < 3
      ClearErrors
      FileOpen $2 "$INSTDIR\${APP_EXE}" a
      ${If} ${Errors}
        nsExec::ExecToStack '"$SYSDIR\taskkill.exe" /F /T /IM ${APP_EXE}'
        Pop $0
        Pop $1
        Sleep 700
        IntOp $3 $3 + 1
      ${Else}
        FileClose $2
        ${Break}
      ${EndIf}
    ${Loop}
  ${EndIf}
!macroend

Section "MainApplication" SecMain
  SectionIn RO

  ; Stop running instances before modifying or migrating files
  !insertmacro StopRunningAppInstances

  ; Cleanly migrate away from an existing MSI installation while preserving user Config/*.json
  ${If} $ExistingMsiProductCode != ""
    InitPluginsDir
    ${If} ${FileExists} "$INSTDIR\Config\*.json"
      CreateDirectory "$PLUGINSDIR\cfg_backup"
      CopyFiles /SILENT "$INSTDIR\Config\*.json" "$PLUGINSDIR\cfg_backup"
    ${ElseIf} ${FileExists} "$PROGRAMFILES64\UltraGamingMode\Config\*.json"
      CreateDirectory "$PLUGINSDIR\cfg_backup"
      CopyFiles /SILENT "$PROGRAMFILES64\UltraGamingMode\Config\*.json" "$PLUGINSDIR\cfg_backup"
    ${EndIf}
    DetailPrint "Удаление предыдущего MSI-пакета ($ExistingMsiProductCode)..."
    nsExec::ExecToStack '"$SYSDIR\msiexec.exe" /x $ExistingMsiProductCode /qn REBOOT=ReallySuppress'
    Pop $0
    Pop $1
    ${If} ${FileExists} "$PLUGINSDIR\cfg_backup\*.json"
      CreateDirectory "$INSTDIR\Config"
      CopyFiles /SILENT "$PLUGINSDIR\cfg_backup\*.json" "$INSTDIR\Config"
    ${EndIf}
  ${EndIf}

  SetOutPath "$INSTDIR"
  SetOverwrite on
  File "..\.bin\${APP_EXE}"
  File "..\UltraGamingMode.ps1"
  File "..\UltraGamingMode.bat"
  Delete "$INSTDIR\${LEGACY_EXE}"

  SetOutPath "$INSTDIR\Core"
  File "..\Core\ServiceManager.ps1"
  File "..\Core\StateEngine.ps1"
  File "..\Core\SystemOptimizer.ps1"

  SetOutPath "$INSTDIR\Tests"
  File "..\Tests\Verify-UniversalEngine.ps1"

  SetOutPath "$INSTDIR\Config"
  ; Always update curated descriptions
  SetOverwrite on
  File "..\Config\service_descriptions.json"
  File "..\Config\process_descriptions.json"
  ; Preserve user-customized service/process/tuning configs across upgrades
  SetOverwrite off
  File "..\Config\services_blacklist.json"
  File "..\Config\services_whitelist.json"
  File "..\Config\startup_apps.json"
  File "..\Config\tuning.json"
  SetOverwrite on

  SetOutPath "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  ; Remove legacy root/per-user shortcuts so Explorer resolves a single clean shortcut
  SetShellVarContext current
  Delete "$SMPROGRAMS\${LEGACY_SHORTCUT}"
  Delete "$DESKTOP\${LEGACY_SHORTCUT}"
  Delete "$DESKTOP\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\Uninstall ${APP_NAME}.lnk"
  RMDir "$SMPROGRAMS\${APP_NAME}"

  SetShellVarContext all
  Delete "$SMPROGRAMS\${LEGACY_SHORTCUT}"
  Delete "$DESKTOP\${LEGACY_SHORTCUT}"

  ; Unified Start Menu & Desktop shortcuts with explicit icon resource
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\Uninstall ${APP_NAME}.lnk" "$INSTDIR\Uninstall.exe" "" "$INSTDIR\Uninstall.exe" 0
  CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0

  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'

  ; Add/Remove Programs registration
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKLM "${UNINST_KEY}" "Publisher" "${APP_PUBLISHER}"
  WriteRegStr HKLM "${UNINST_KEY}" "URLInfoAbout" "${APP_URL}"
  WriteRegStr HKLM "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\${APP_EXE},0"
  WriteRegStr HKLM "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINST_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "${UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINST_KEY}" "NoRepair" 1

  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKLM "${UNINST_KEY}" "EstimatedSize" "$0"
SectionEnd

Section "Uninstall"
  !insertmacro StopRunningAppInstances

  ; Remove elevated scheduled tasks registered at runtime so no orphaned triggers remain
  nsExec::ExecToStack '"$SYSDIR\schtasks.exe" /Delete /TN "UltraGamingMode_AutoStart" /F'
  Pop $0
  Pop $1
  nsExec::ExecToStack '"$SYSDIR\schtasks.exe" /Delete /TN "UltraGamingMode_BootTrigger" /F'
  Pop $0
  Pop $1
  nsExec::ExecToStack '"$SYSDIR\schtasks.exe" /Delete /TN "UltraGamingMode_Watchdog" /F'
  Pop $0
  Pop $1
  ReadEnvStr $0 "ProgramData"
  ${If} $0 != ""
    Delete "$0\UltraGamingMode\Tasks\autostart.xml"
    RMDir "$0\UltraGamingMode\Tasks"
  ${EndIf}

  SetShellVarContext current
  Delete "$SMPROGRAMS\${LEGACY_SHORTCUT}"
  Delete "$DESKTOP\${LEGACY_SHORTCUT}"
  Delete "$DESKTOP\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\Uninstall ${APP_NAME}.lnk"
  RMDir "$SMPROGRAMS\${APP_NAME}"

  SetShellVarContext all
  Delete "$SMPROGRAMS\${LEGACY_SHORTCUT}"
  Delete "$DESKTOP\${LEGACY_SHORTCUT}"
  Delete "$DESKTOP\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\Uninstall ${APP_NAME}.lnk"
  RMDir "$SMPROGRAMS\${APP_NAME}"

  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'

  Delete "$INSTDIR\${APP_EXE}"
  Delete "$INSTDIR\${LEGACY_EXE}"
  Delete "$INSTDIR\UltraGamingMode.ps1"
  Delete "$INSTDIR\UltraGamingMode.bat"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir /r "$INSTDIR\Core"
  RMDir /r "$INSTDIR\Tests"
  RMDir /r "$INSTDIR\Config"
  RMDir "$INSTDIR"

  DeleteRegKey HKLM "${UNINST_KEY}"
SectionEnd
