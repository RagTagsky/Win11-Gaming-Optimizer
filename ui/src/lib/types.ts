export type ModeState = 'Normal' | 'Armed' | 'Gaming' | 'Transitioning' | 'Error';

export type OptimizationProfile = 'competitive' | 'aaa' | 'custom';

export type ModeAction = 'Enable' | 'Restore';

export type ThemeMode = 'dark' | 'light';

export type TabId = 'dashboard' | 'processes' | 'services' | 'tweaks' | 'repair';

export type ServiceCategory = 'Xbox' | 'Print' | 'Telemetry' | 'Network' | 'System';

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

export interface ServicesLists {
  blacklist: BlacklistServiceItem[];
  whitelist: string[];
  whitelistDescriptions?: Record<string, ServiceDescriptionEntry>;
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
  memoryMb: number;
  isProtected: boolean;
  isBlacklisted: boolean;
  isStartupProtected: boolean;
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
