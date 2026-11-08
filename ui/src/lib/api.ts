import { invoke } from '@tauri-apps/api/core';
import type {
  HardwareInfo,
  ModeState,
  OptimizationProfile,
  ServicesLists,
  TuningConfig,
} from './types';

export const isTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

export interface ActionResult {
  success: boolean;
  message: string;
}

export async function fetchSystemStatus(): Promise<{
  mode: ModeState;
  profile: OptimizationProfile;
  hardware: HardwareInfo;
  activeSince?: string;
}> {
  if (isTauri) {
    try {
      return await invoke('get_system_status');
    } catch (e) {
      console.warn('Tauri invoke get_system_status failed:', e);
    }
  }

  return {
    mode: 'Normal',
    profile: 'competitive',
    hardware: {
      cpu: 'AMD Ryzen 5 5600X 6-Core Processor',
      gpu: 'AMD Radeon RX 6600',
      ram: '32 ГБ ОЗУ (доступно 24.5 ГБ)',
      display: '1920×1080 (MPO штатный, без мерцания)',
      dpcLatency: 'Потоковый DPC (оптимально) · Приоритет 0x26',
      mpoStatus: 'Штатный конвейер DWM (без мерцания)',
      timerResolution: '0.500 мс',
    },
  };
}

export async function fetchTuningConfig(): Promise<TuningConfig> {
  if (isTauri) {
    try {
      return await invoke('get_tuning_config');
    } catch (e) {
      console.warn('Tauri invoke get_tuning_config failed:', e);
    }
  }
  return {
    DisableFullscreenOptimizations: true,
    DisableMouseAccel: false,
    EnableNetAdapterMsi: true,
    InputBufferQueueSize: 100,
  };
}

export async function saveTuningConfig(config: TuningConfig): Promise<TuningConfig> {
  const safeConfig: TuningConfig = {
    ...config,
    InputBufferQueueSize: Math.max(32, Math.round(Number(config.InputBufferQueueSize) || 100)),
  };
  if (isTauri) {
    return await invoke('save_tuning_config', { config: safeConfig });
  }
  return safeConfig;
}

export async function fetchServicesLists(): Promise<ServicesLists> {
  if (isTauri) {
    try {
      return await invoke('get_services_lists');
    } catch (e) {
      console.warn('Tauri invoke get_services_lists failed:', e);
    }
  }
  return {
    blacklist: [
      {
        Name: 'DiagTrack',
        DisplayName: 'Connected User Experiences and Telemetry',
        Category: 'Telemetry',
        Reason: 'Фоновая отправка диагностических данных и телеметрии Windows.',
      },
      {
        Name: 'SysMain',
        DisplayName: 'SysMain (Superfetch)',
        Category: 'System',
        Reason: 'Фоновое кэширование диска, вызывающее пики чтения во время игры.',
      },
      {
        Name: 'WSearch',
        DisplayName: 'Windows Search',
        Category: 'Search',
        Reason: 'Фоновая индексация файлов (восстанавливается сразу после выхода из игрового режима).',
      },
      {
        Name: 'Spooler',
        DisplayName: 'Диспетчер печати',
        Category: 'Print',
        Reason: 'Очередь фоновой печати документов.',
      },
    ],
    whitelist: [
      'Audiosrv',
      'AudioEndpointBuilder',
      'Dhcp',
      'Dnscache',
      'Nsi',
      'CaptureService',
      'cbdhsvc',
      'CDPUserSvc',
      'RpcSs',
      'DcomLaunch',
    ],
  };
}

export async function setNativeWindowTheme(dark: boolean): Promise<void> {
  if (isTauri) {
    try {
      await invoke('set_window_theme', { dark });
    } catch (e) {
      console.warn('Tauri invoke set_window_theme failed:', e);
    }
  }
}

export async function executeModeAction(
  action: 'Enable' | 'Restore',
  profile: OptimizationProfile = 'competitive'
): Promise<ActionResult> {
  if (isTauri) {
    return await invoke('execute_mode_action', { action, profile });
  }

  return {
    success: true,
    message: `[Тестовый режим] Действие «${action}» выполнено (профиль: ${profile}).`,
  };
}

export async function executeEmergencyRepair(
  repairType:
    | 'display'
    | 'services'
    | 'shaders'
    | 'verify'
    | 'memory'
    | 'debloat'
    | 'restore_debloat'
): Promise<ActionResult> {
  if (isTauri) {
    return await invoke('execute_emergency_repair', { repairType });
  }

  return {
    success: true,
    message: `[Тестовый режим] Операция обслуживания «${repairType}» выполнена.`,
  };
}

export async function lockTimerResolution(): Promise<ActionResult> {
  if (isTauri) {
    return await invoke('lock_timer_resolution');
  }

  return {
    success: true,
    message: 'Разрешение системного таймера установлено: 0.500 мс',
  };
}
