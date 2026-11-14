export type ModeState = 'Normal' | 'Armed' | 'Gaming' | 'Transitioning' | 'Error';

export type OptimizationProfile = 'competitive' | 'aaa' | 'custom';

export type ModeAction = 'Enable' | 'Restore';

export type ThemeMode = 'dark' | 'light';

export type TabId = 'dashboard' | 'services' | 'tweaks' | 'repair';

export type ServiceCategory = 'Xbox' | 'Print' | 'Telemetry' | 'Network' | 'System';

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

export interface BlacklistServiceItem {
  Name: string;
  DisplayName: string;
  Category: ServiceCategory;
  Reason: string;
  Status?: string;
}

export interface ServicesLists {
  blacklist: BlacklistServiceItem[];
  whitelist: string[];
}

export interface LogEntry {
  id: string;
  timestamp: string;
  level: 'info' | 'success' | 'warn' | 'error';
  message: string;
}

export interface ErrorBannerState {
  source: 'status' | 'tuning' | 'services' | 'action' | 'repair' | 'timer' | 'clipboard';
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
