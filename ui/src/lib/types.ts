export type ModeState = 'Normal' | 'Gaming' | 'Transitioning' | 'Error';

export type OptimizationProfile = 'competitive' | 'aaa' | 'custom';

export interface HardwareInfo {
  cpu: string;
  gpu: string;
  ram: string;
  display: string;
  dpcLatency: string;
  mpoStatus: string;
}

export interface ServiceItem {
  name: string;
  reason: string;
  category: 'telemetry' | 'printing' | 'network' | 'gaming' | 'system';
  status: 'Running' | 'Stopped' | 'Disabled' | 'Manual';
}

export interface BloatProcess {
  name: string;
  description: string;
}

export interface TweakSetting {
  id: string;
  title: string;
  description: string;
  category: 'display' | 'latency' | 'power' | 'network';
  enabled: boolean;
  recommended: boolean;
}

export interface LogEntry {
  id: string;
  timestamp: string;
  level: 'info' | 'success' | 'warn' | 'error';
  message: string;
}
