export type ModeState =
  | 'Normal'
  | 'Armed'
  | 'Gaming'
  | 'RestoringPending'
  | 'Transitioning'
  | 'Error';

export type OptimizationProfile = 'competitive' | 'aaa' | 'custom';

export type ModeAction = 'Enable' | 'Restore';

export type ThemeMode = 'dark' | 'light';

export type TabId = 'dashboard' | 'processes' | 'services' | 'tweaks' | 'repair';

export type ServiceCategory =
  | 'Telemetry'
  | 'Updates'
  | 'Xbox'
  | 'Print'
  | 'Devices'
  | 'Network'
  | 'Remote'
  | 'System';

export type ProcessProtectionKind = 'os_core' | 'self_app' | 'anticheat' | 'game_client';

export type ServiceControlOperation = 'Start' | 'Stop' | 'Automatic' | 'Manual' | 'Disabled';

export type ServiceListType = 'blacklist' | 'whitelist';

export type ProcessListType = 'blacklist' | 'protected';

export type ListMutationOperation = 'add' | 'remove';

export type RepairType =
  | 'display'
  | 'services'
  | 'shaders'
  | 'verify'
  | 'memory'
  | 'debloat'
  | 'restore_debloat';

export interface HardwareInfo {
  cpu: string;
  gpu: string;
  ram: string;
  display: string;
  dpcLatency: string;
  mpoStatus: string;
  timerResolution?: string;
}

export interface TuningConfig {
  DisableFullscreenOptimizations: boolean;
  DisableMouseAccel: boolean;
  DisableNvidiaDynamicPstate: boolean;
  EnableNetAdapterMsi: boolean;
  InputBufferQueueSize: number;
  AutoLockTimerInGaming: boolean;
}

export interface AutostartStatus {
  enabled: boolean;
  startInTray: boolean;
  taskExists: boolean;
  pathMatches: boolean;
  isElevatedTask: boolean;
  currentExePath: string;
  registeredCommand?: string;
  isAdminSession: boolean;
  warning?: string;
}

export interface ServiceDescriptionEntry {
  summaryRu: string;
  canDisableRu: string;
}

export interface BlacklistServiceItem {
  Name: string;
  DisplayName: string;
  Category: ServiceCategory;
  Reason: string;
  Status?: string;
  StartType?: string;
  SummaryRu?: string;
  CanDisableHint?: string;
}

export interface WhitelistServiceItem {
  Name: string;
  DisplayName: string;
  Status: string;
  isCoreLocked: boolean;
  SummaryRu?: string;
  CanDisableHint?: string;
}

export interface InstalledServiceItem {
  Name: string;
  DisplayName: string;
  Status: string;
  StartType: string;
  Category: ServiceCategory;
  membership: 'core' | 'whitelist' | 'blacklist' | 'none';
  isCoreLocked: boolean;
  SummaryRu?: string;
  CanDisableHint?: string;
}

export interface ServiceFeaturePack {
  id: string;
  title: string;
  description: string;
  keepEnabledInGame: boolean;
  services: string[];
}

export interface ServicesLists {
  blacklist: BlacklistServiceItem[];
  whitelist: string[];
  whitelistDescriptions?: Record<string, ServiceDescriptionEntry>;
  whitelistItems?: WhitelistServiceItem[];
  allInstalledServices?: InstalledServiceItem[];
  wifiActive?: boolean;
  featurePacks?: ServiceFeaturePack[];
}

export interface UpdateInfo {
  currentVersion: string;
  latestVersion: string;
  hasUpdate: boolean;
  releaseUrl: string;
  publishedAt?: string;
  releaseNotes: string;
  installerUrl?: string;
  installerName?: string;
  checksumUrl?: string;
  sizeBytes?: number;
}

export interface ProcessItem {
  pid: number;
  name: string;
  displayName?: string;
  executablePath?: string;
  protectionKind?: ProcessProtectionKind | null;
  memoryMb: number;
  isProtected: boolean;
  isBlacklisted: boolean;
  isStartupProtected: boolean;
}

export interface StartupEntry {
  id: string;
  name: string;
  displayName: string;
  source: string;
  sourceLabel: string;
  target: string;
  enabled: boolean;
  isProtected: boolean;
  matchedRule?: string;
}

export interface ProcessConfigLists {
  blacklistProcesses: string[];
  protectedStartupNames: string[];
}

export interface LiveProcessesSnapshot {
  processes: ProcessItem[];
  blacklistProcesses: string[];
  protectedStartupNames: string[];
}

export interface LogEntry {
  id: string;
  timestamp: string;
  level: 'info' | 'success' | 'warn' | 'error';
  message: string;
}

export interface ErrorBannerState {
  source:
    | 'status'
    | 'tuning'
    | 'autostart'
    | 'processes'
    | 'services'
    | 'action'
    | 'repair'
    | 'timer'
    | 'clipboard';
  title: string;
  detail: string;
}

export interface ConfirmDialogRequest {
  title: string;
  description: string;
  confirmLabel: string;
  cancelLabel?: string;
  tone?: 'primary' | 'warn' | 'danger';
  details?: string;
}
