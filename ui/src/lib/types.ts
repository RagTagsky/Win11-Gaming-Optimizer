export type ModeState = 'Normal' | 'Armed' | 'Gaming' | 'Transitioning' | 'Error';

export type OptimizationProfile = 'competitive' | 'aaa' | 'custom';

export type ThemeMode = 'dark' | 'light';

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
  EnableNetAdapterMsi: boolean;
  InputBufferQueueSize: number;
}

export interface BlacklistServiceItem {
  Name: string;
  DisplayName: string;
  Category: string;
  Reason: string;
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
