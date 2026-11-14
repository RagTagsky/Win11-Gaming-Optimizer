import { invoke } from '@tauri-apps/api/core';
import type {
  ModeAction,
  ModeState,
  OptimizationProfile,
  HardwareInfo,
  TuningConfig,
  ServicesLists,
  RepairType
} from './types';

export interface SystemStatus {
  mode: ModeState;
  profile: OptimizationProfile;
  hardware: HardwareInfo;
  activeSince?: string;
}

export interface ActionResult {
  success: boolean;
  message: string;
  output?: string;
}

export const isTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

export function formatIpcError(err: unknown): string {
  if (err instanceof Error && err.message.trim().length > 0) {
    return err.message;
  }
  if (typeof err === 'string' && err.trim().length > 0) {
    return err;
  }
  if (err && typeof err === 'object') {
    const record = err as Record<string, unknown>;
    if (typeof record.message === 'string' && record.message.trim().length > 0) {
      return record.message;
    }
    if (typeof record.error === 'string' && record.error.trim().length > 0) {
      return record.error;
    }
  }
  return String(err || 'Неизвестная ошибка обмена с процессом Windows');
}

const PREVIEW_CONFIG: TuningConfig = {
  DisableFullscreenOptimizations: true,
  DisableMouseAccel: false,
  DisableNvidiaDynamicPstate: false,
  EnableNetAdapterMsi: true,
  InputBufferQueueSize: 100
};

let previewTuningState: TuningConfig = { ...PREVIEW_CONFIG };

export function resolveProfileFromTuning(cfg: TuningConfig): OptimizationProfile {
  const baseRestMatch =
    !cfg.DisableMouseAccel &&
    !cfg.DisableNvidiaDynamicPstate &&
    cfg.EnableNetAdapterMsi &&
    cfg.InputBufferQueueSize === 100;

  if (cfg.DisableFullscreenOptimizations && baseRestMatch) return 'competitive';
  if (!cfg.DisableFullscreenOptimizations && baseRestMatch) return 'aaa';
  return 'custom';
}

export function buildProfileTuningPreset(profile: 'competitive' | 'aaa'): TuningConfig {
  return {
    DisableFullscreenOptimizations: profile === 'competitive',
    DisableMouseAccel: false,
    DisableNvidiaDynamicPstate: false,
    EnableNetAdapterMsi: true,
    InputBufferQueueSize: 100
  };
}

const PREVIEW_SERVICES: ServicesLists = {
  blacklist: [
    {
      Name: 'DiagTrack',
      DisplayName: 'Функциональные возможности для подключенных пользователей и телеметрия',
      Category: 'Telemetry',
      Reason: 'Диагностическая телеметрия (Microsoft)'
    },
    {
      Name: 'SysMain',
      DisplayName: 'SysMain (Superfetch)',
      Category: 'System',
      Reason: 'Фоновая предзагрузка данных в ОЗУ (конкуренция за диск и память)'
    },
    {
      Name: 'XblAuthManager',
      DisplayName: 'Диспетчер проверки подлинности Xbox Live',
      Category: 'Xbox',
      Reason: 'Служба авторизации Xbox Live'
    },
    {
      Name: 'Spooler',
      DisplayName: 'Диспетчер печати',
      Category: 'Print',
      Reason: 'Фоновая очередь печати (не требуется в играх)'
    },
    {
      Name: 'WSearch',
      DisplayName: 'Windows Search',
      Category: 'System',
      Reason: 'Фоновая индексация файлов (высокий I/O диска)'
    },
    {
      Name: 'SSDPSRV',
      DisplayName: 'Обнаружение SSDP',
      Category: 'Network',
      Reason: 'Сетевое обнаружение UPnP-устройств в фоне'
    }
  ],
  whitelist: ['AudioSrv', 'Audiosrv', 'Dhcp', 'Dnscache', 'EventLog', 'PlugPlay', 'Power', 'Winmgmt']
};

export async function fetchSystemStatus(): Promise<SystemStatus> {
  if (isTauri) {
    return await invoke<SystemStatus>('get_system_status');
  }

  return {
    mode: 'Normal',
    profile: resolveProfileFromTuning(previewTuningState),
    hardware: {
      cpu: 'Демо-режим браузера (вне Tauri)',
      gpu: 'Интерактивный предпросмотр интерфейса',
      ram: '32 ГБ DDR4 (предпросмотр)',
      display: '2560×1440 · композиция DWM (предпросмотр)',
      dpcLatency: 'Threaded DPC (предпросмотр)',
      mpoStatus: 'Отключено',
      timerResolution: '1.000 мс (штатный)'
    }
  };
}

export async function fetchTuningConfig(): Promise<TuningConfig> {
  if (isTauri) {
    return await invoke<TuningConfig>('get_tuning_config');
  }
  return { ...previewTuningState };
}

export async function saveTuningConfig(config: TuningConfig): Promise<TuningConfig> {
  const queueSize = Number.isFinite(config.InputBufferQueueSize)
    ? Math.max(32, Math.round(config.InputBufferQueueSize))
    : 100;

  const safeConfig: TuningConfig = {
    DisableFullscreenOptimizations: Boolean(config.DisableFullscreenOptimizations),
    DisableMouseAccel: Boolean(config.DisableMouseAccel),
    DisableNvidiaDynamicPstate: Boolean(config.DisableNvidiaDynamicPstate),
    EnableNetAdapterMsi: Boolean(config.EnableNetAdapterMsi),
    InputBufferQueueSize: queueSize
  };

  if (isTauri) {
    return await invoke<TuningConfig>('save_tuning_config', { config: safeConfig });
  }

  previewTuningState = { ...safeConfig };
  return { ...previewTuningState };
}

export async function fetchServicesLists(): Promise<ServicesLists> {
  if (isTauri) {
    return await invoke<ServicesLists>('get_services_lists');
  }
  return {
    blacklist: PREVIEW_SERVICES.blacklist.map((item) => ({ ...item })),
    whitelist: [...PREVIEW_SERVICES.whitelist]
  };
}

export async function setWindowTheme(dark: boolean): Promise<void> {
  if (isTauri) {
    await invoke('set_window_theme', { dark });
  }
}

export async function executeModeAction(
  action: ModeAction,
  profile: OptimizationProfile = 'competitive'
): Promise<ActionResult> {
  if (isTauri) {
    try {
      return await invoke<ActionResult>('execute_mode_action', { action, profile });
    } catch (err) {
      return {
        success: false,
        message: formatIpcError(err)
      };
    }
  }

  if (action === 'Enable' && (profile === 'competitive' || profile === 'aaa')) {
    previewTuningState = buildProfileTuningPreset(profile);
  }

  await new Promise((r) => setTimeout(r, 300));
  return {
    success: true,
    message:
      action === 'Enable'
        ? `Предпросмотр: игровой режим подготовлен (${profile === 'competitive' ? 'Киберспорт' : profile === 'aaa' ? 'AAA и стриминг' : 'Пользовательский'}).`
        : 'Предпросмотр: система возвращена в штатный режим.'
  };
}

export async function executeEmergencyRepair(repairType: RepairType): Promise<ActionResult> {
  if (isTauri) {
    try {
      return await invoke<ActionResult>('execute_emergency_repair', { repairType });
    } catch (err) {
      return {
        success: false,
        message: formatIpcError(err)
      };
    }
  }

  await new Promise((r) => setTimeout(r, 350));
  return {
    success: true,
    message: `Предпросмотр: операция «${repairType}» смоделирована.`
  };
}

export async function lockTimerResolution(): Promise<ActionResult> {
  if (isTauri) {
    try {
      return await invoke<ActionResult>('lock_timer_resolution');
    } catch (err) {
      return {
        success: false,
        message: formatIpcError(err)
      };
    }
  }

  await new Promise((r) => setTimeout(r, 250));
  return {
    success: true,
    message: 'Предпросмотр: точность таймера Windows зафиксирована на 0.500 мс.'
  };
}
