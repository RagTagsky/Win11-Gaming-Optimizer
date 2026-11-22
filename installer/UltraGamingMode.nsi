Unicode true
ManifestDPIAware true
SetCompressor /SOLID lzma

!include "MUI2.nsh"
!include "x64.nsh"
!include "FileFunc.nsh"

!ifndef APP_VERSION
  !define APP_VERSION "4.0.0"
!endif
!ifndef OUT_FILE
  !define OUT_FILE "..\.bin\UltraGamingMode-Setup.exe"
!endif

!define APP_NAME "Ultra Gaming Mode"
!define APP_PUBLISHER "Ultra Gaming Mode Team"
!define APP_URL "https://github.com/RagTagsky/Win11-Gaming-Optimizer"
!define APP_EXE "UltraGamingMode.exe"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\UltraGamingMode"

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
FunctionEnd

Function un.onInit
  SetShellVarContext all
  ${If} ${RunningX64}
    SetRegView 64
  ${EndIf}
FunctionEnd

Section "MainApplication" SecMain
  SectionIn RO

  ; Stop running instances before updating files
  nsExec::ExecToStack '"$SYSDIR\taskkill.exe" /F /IM ${APP_EXE}'
  Pop $0
  Pop $1
  Sleep 300

  SetOutPath "$INSTDIR"
  SetOverwrite on
  File "..\.bin\${APP_EXE}"
  File "..\UltraGamingMode.ps1"
  File "..\UltraGamingMode.bat"

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

  ; Start Menu & Desktop shortcuts with explicit icon resource
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
  CreateShortcut "$SMPROGRAMS\${APP_NAME}\Uninstall ${APP_NAME}.lnk" "$INSTDIR\Uninstall.exe" "" "$INSTDIR\Uninstall.exe" 0
  CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0

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
  nsExec::ExecToStack '"$SYSDIR\taskkill.exe" /F /IM ${APP_EXE}'
  Pop $0
  Pop $1
  Sleep 300

  Delete "$DESKTOP\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\Uninstall ${APP_NAME}.lnk"
  RMDir "$SMPROGRAMS\${APP_NAME}"

  Delete "$INSTDIR\${APP_EXE}"
  Delete "$INSTDIR\UltraGamingMode.ps1"
  Delete "$INSTDIR\UltraGamingMode.bat"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir /r "$INSTDIR\Core"
  RMDir /r "$INSTDIR\Tests"
  RMDir /r "$INSTDIR\Config"
  RMDir "$INSTDIR"

  DeleteRegKey HKLM "${UNINST_KEY}"
SectionEnd
