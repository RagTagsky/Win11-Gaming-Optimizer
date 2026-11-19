import { invoke } from '@tauri-apps/api/core';
import type {
  ModeAction,
  ModeState,
  OptimizationProfile,
  HardwareInfo,
  TuningConfig,
  ServicesLists,
  RepairType,
  LiveProcessesSnapshot,
  ProcessConfigLists,
  ProcessListType,
  ServiceListType,
  ListMutationOperation,
  ServiceControlOperation,
  ServiceCategory,
  UpdateInfo
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
      Reason: 'Диагностическая телеметрия (Microsoft)',
      Status: 'Running',
      StartType: 'Automatic',
      SummaryRu: 'Собирает и отправляет диагностические данные и телеметрию использования Windows.',
      CanDisableHint: 'Можно отключить безопасно: не влияет на игры и работу системы.'
    },
    {
      Name: 'SysMain',
      DisplayName: 'SysMain (Superfetch)',
      Category: 'System',
      Reason: 'Фоновая предзагрузка данных в ОЗУ (конкуренция за диск и память)',
      Status: 'Running',
      StartType: 'Automatic',
      SummaryRu: 'Кэширует часто запускаемые программы в оперативной памяти.',
      CanDisableHint: 'Можно отключить безопасно на SSD/NVMe: снижает фоновую нагрузку на диск и ОЗУ.'
    },
    {
      Name: 'XblAuthManager',
      DisplayName: 'Диспетчер проверки подлинности Xbox Live',
      Category: 'Xbox',
      Reason: 'Служба авторизации Xbox Live',
      Status: 'Stopped',
      StartType: 'Manual'
    },
    {
      Name: 'Spooler',
      DisplayName: 'Диспетчер печати',
      Category: 'Print',
      Reason: 'Фоновая очередь печати (не требуется в играх)',
      Status: 'Running',
      StartType: 'Automatic'
    },
    {
      Name: 'WSearch',
      DisplayName: 'Windows Search',
      Category: 'System',
      Reason: 'Фоновая индексация файлов (высокий I/O диска)',
      Status: 'Running',
      StartType: 'Automatic'
    },
    {
      Name: 'SSDPSRV',
      DisplayName: 'Обнаружение SSDP',
      Category: 'Network',
      Reason: 'Сетевое обнаружение UPnP-устройств в фоне',
      Status: 'Stopped',
      StartType: 'Manual'
    }
  ],
  whitelist: ['AudioSrv', 'Audiosrv', 'Dhcp', 'Dnscache', 'EventLog', 'PlugPlay', 'Power', 'Winmgmt']
};

let previewBlacklistProcesses = ['Discord', 'Spotify', 'Widgets', 'chrome'];
let previewProtectedStartupNames = ['ctfmon', 'AMDNoiseSuppression', 'SecurityHealthSystray'];
let previewProcesses = [
  { pid: 4, name: 'System', memoryMb: 0.2, isProtected: true },
  { pid: 812, name: 'csrss', memoryMb: 6.4, isProtected: true },
  { pid: 940, name: 'lsass', memoryMb: 21.8, isProtected: true },
  { pid: 4120, name: 'UltraGamingMode', memoryMb: 84.5, isProtected: true },
  { pid: 11240, name: 'chrome', memoryMb: 412.6, isProtected: false },
  { pid: 13804, name: 'Discord', memoryMb: 268.1, isProtected: false },
  { pid: 15220, name: 'Spotify', memoryMb: 194.0, isProtected: false }
];

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
    whitelist: [...PREVIEW_SERVICES.whitelist],
    whitelistDescriptions: PREVIEW_SERVICES.whitelistDescriptions ?? {}
  };
}

export async function fetchRunningProcesses(): Promise<LiveProcessesSnapshot> {
  if (isTauri) {
    return await invoke<LiveProcessesSnapshot>('get_running_processes');
  }
  return {
    processes: previewProcesses.map((p) => ({
      ...p,
      isBlacklisted: previewBlacklistProcesses.some((b) => b.toLowerCase() === p.name.toLowerCase()),
      isStartupProtected: previewProtectedStartupNames.some(
        (s) => s.toLowerCase() === p.name.toLowerCase()
      )
    })),
    blacklistProcesses: [...previewBlacklistProcesses],
    protectedStartupNames: [...previewProtectedStartupNames]
  };
}

export async function killProcess(pid: number, name: string): Promise<ActionResult> {
  if (isTauri) {
    try {
      return await invoke<ActionResult>('kill_process', { pid, name });
    } catch (err) {
      return {
        success: false,
        message: formatIpcError(err)
      };
    }
  }
  const target = previewProcesses.find((p) => p.pid === pid);
  if (!target || target.isProtected) {
    return { success: false, message: `Процесс «${name}» защищён ОС.` };
  }
  previewProcesses = previewProcesses.filter((p) => p.pid !== pid);
  return { success: true, message: `Предпросмотр: процесс «${name}» (PID ${pid}) завершён.` };
}

export async function updateProcessList(
  listType: ProcessListType,
  processName: string,
  operation: ListMutationOperation
): Promise<ProcessConfigLists> {
  if (isTauri) {
    return await invoke<ProcessConfigLists>('update_process_list', {
      listType,
      processName,
      operation
    });
  }
  const clean = processName.trim().replace(/\.exe$/i, '');
  if (listType === 'blacklist') {
    if (operation === 'add') {
      if (!previewBlacklistProcesses.some((x) => x.toLowerCase() === clean.toLowerCase())) {
        previewBlacklistProcesses = [...previewBlacklistProcesses, clean];
      }
    } else {
      previewBlacklistProcesses = previewBlacklistProcesses.filter(
        (x) => x.toLowerCase() !== clean.toLowerCase()
      );
    }
  } else {
    if (operation === 'add') {
      if (!previewProtectedStartupNames.some((x) => x.toLowerCase() === clean.toLowerCase())) {
        previewProtectedStartupNames = [...previewProtectedStartupNames, clean];
      }
    } else {
      previewProtectedStartupNames = previewProtectedStartupNames.filter(
        (x) => x.toLowerCase() !== clean.toLowerCase()
      );
    }
  }
  return {
    blacklistProcesses: [...previewBlacklistProcesses],
    protectedStartupNames: [...previewProtectedStartupNames]
  };
}

export async function controlService(
  serviceName: string,
  operation: ServiceControlOperation
): Promise<ActionResult> {
  if (isTauri) {
    try {
      return await invoke<ActionResult>('control_service', { serviceName, operation });
    } catch (err) {
      return {
        success: false,
        message: formatIpcError(err)
      };
    }
  }
  const item = PREVIEW_SERVICES.blacklist.find(
    (s) => s.Name.toLowerCase() === serviceName.toLowerCase()
  );
  if (item) {
    if (operation === 'Start') item.Status = 'Running';
    else if (operation === 'Stop') item.Status = 'Stopped';
    else item.StartType = operation;
  }
  return {
    success: true,
    message: `Предпросмотр: служба «${serviceName}» -> ${operation}.`
  };
}

export async function updateServiceList(params: {
  listType: ServiceListType;
  serviceName: string;
  displayName?: string;
  category?: ServiceCategory;
  reason?: string;
  operation: ListMutationOperation;
}): Promise<ServicesLists> {
  if (isTauri) {
    return await invoke<ServicesLists>('update_service_list', {
      listType: params.listType,
      serviceName: params.serviceName,
      displayName: params.displayName ?? null,
      category: params.category ?? null,
      reason: params.reason ?? null,
      operation: params.operation
    });
  }
  const clean = params.serviceName.trim();
  if (params.listType === 'blacklist') {
    if (params.operation === 'add') {
      PREVIEW_SERVICES.blacklist.push({
        Name: clean,
        DisplayName: params.displayName?.trim() || params.reason?.trim() || clean,
        Category: params.category ?? 'System',
        Reason: params.reason?.trim() || 'Добавлено пользователем',
        Status: 'Stopped',
        StartType: 'Manual'
      });
    } else {
      PREVIEW_SERVICES.blacklist = PREVIEW_SERVICES.blacklist.filter(
        (s) => s.Name.toLowerCase() !== clean.toLowerCase()
      );
    }
  } else {
    if (params.operation === 'add') {
      if (!PREVIEW_SERVICES.whitelist.some((w) => w.toLowerCase() === clean.toLowerCase())) {
        PREVIEW_SERVICES.whitelist.push(clean);
      }
      PREVIEW_SERVICES.blacklist = PREVIEW_SERVICES.blacklist.filter(
        (s) => s.Name.toLowerCase() !== clean.toLowerCase()
      );
    } else {
      PREVIEW_SERVICES.whitelist = PREVIEW_SERVICES.whitelist.filter(
        (w) => w.toLowerCase() !== clean.toLowerCase()
      );
    }
  }
  return {
    blacklist: PREVIEW_SERVICES.blacklist.map((item) => ({ ...item })),
    whitelist: [...PREVIEW_SERVICES.whitelist],
    whitelistDescriptions: PREVIEW_SERVICES.whitelistDescriptions ?? {}
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

export async function rebootPc(): Promise<ActionResult> {
  if (isTauri) {
    try {
      return await invoke<ActionResult>('reboot_pc');
    } catch (err) {
      return {
        success: false,
        message: formatIpcError(err)
      };
    }
  }
  return {
    success: true,
    message: 'Предпросмотр: инициирована перезагрузка ПК.'
  };
}

export async function checkForUpdates(): Promise<UpdateInfo> {
  if (isTauri) {
    return await invoke<UpdateInfo>('check_for_updates');
  }
  await new Promise((r) => setTimeout(r, 250));
  return {
    currentVersion: '3.4.0',
    latestVersion: '3.4.0',
    hasUpdate: false,
    releaseUrl: 'https://github.com/RagTagsky/Win11-Gaming-Optimizer/releases/latest',
    releaseNotes: ''
  };
}

export async function installGithubUpdate(
  installerUrl: string,
  checksumUrl: string | undefined,
  expectedFileName: string
): Promise<ActionResult> {
  if (isTauri) {
    try {
      return await invoke<ActionResult>('install_github_update', {
        installerUrl,
        checksumUrl: checksumUrl ?? null,
        expectedFileName
      });
    } catch (err) {
      return {
        success: false,
        message: formatIpcError(err)
      };
    }
  }
  return {
    success: true,
    message: `Предпросмотр: установка ${expectedFileName}`
  };
}

export async function openReleaseUrl(url: string): Promise<void> {
  if (isTauri) {
    await invoke('open_release_url', { url });
    return;
  }
  window.open(url, '_blank', 'noopener,noreferrer');
}

export async function exitApp(): Promise<void> {
  if (isTauri) {
    await invoke('exit_app');
  }
}
