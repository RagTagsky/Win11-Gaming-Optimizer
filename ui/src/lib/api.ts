import { invoke } from '@tauri-apps/api/core';
import type {
  AutostartStatus,
  ModeAction,
  ModeState,
  OptimizationProfile,
  HardwareInfo,
  TuningConfig,
  ServicesLists,
  RepairType,
  LiveProcessesSnapshot,
  ProcessConfigLists,
  ProcessDescriptionEntry,
  ProcessListType,
  ProcessProtectionKind,
  SafetyLevel,
  ServiceListType,
  ListMutationOperation,
  ServiceControlOperation,
  ServiceCategory,
  ServiceFeaturePack,
  StartupEntry,
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
  InputBufferQueueSize: 100,
  AutoLockTimerInGaming: true,
  AutoPurgeRamInGaming: true,
  AutoPurgeRamThresholdMB: 2048
};

let previewTuningState: TuningConfig = { ...PREVIEW_CONFIG };
let previewAutostartState: AutostartStatus = {
  enabled: false,
  startInTray: true,
  taskExists: false,
  pathMatches: true,
  isElevatedTask: true,
  currentExePath: 'C:\\Program Files\\UltraGamingMode\\UltraGamingMode.exe',
  isAdminSession: true
};

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

export function buildProfileTuningPreset(
  profile: 'competitive' | 'aaa',
  existing?: Partial<TuningConfig> | null
): TuningConfig {
  const thresholdMb =
    typeof existing?.AutoPurgeRamThresholdMB === 'number' &&
    Number.isFinite(existing.AutoPurgeRamThresholdMB)
      ? Math.min(16384, Math.max(512, Math.round(existing.AutoPurgeRamThresholdMB)))
      : 2048;

  return {
    DisableFullscreenOptimizations: profile === 'competitive',
    DisableMouseAccel: false,
    DisableNvidiaDynamicPstate: false,
    EnableNetAdapterMsi: true,
    InputBufferQueueSize: 100,
    AutoLockTimerInGaming:
      existing?.AutoLockTimerInGaming !== undefined ? Boolean(existing.AutoLockTimerInGaming) : true,
    AutoPurgeRamInGaming:
      existing?.AutoPurgeRamInGaming !== undefined ? Boolean(existing.AutoPurgeRamInGaming) : true,
    AutoPurgeRamThresholdMB: thresholdMb
  };
}

let previewBlacklist: Array<{
  Name: string;
  DisplayName: string;
  Category: ServiceCategory;
  Reason: string;
  Status: string;
  StartType: string;
  SummaryRu: string;
  CanDisableHint: string;
  safetyLevel: SafetyLevel;
}> = [
  {
    Name: 'DiagTrack',
    DisplayName: 'Функциональные возможности для подключенных пользователей и телеметрия',
    Category: 'Telemetry',
    Reason: 'Диагностическая телеметрия (Microsoft)',
    Status: 'Running',
    StartType: 'Automatic',
    SummaryRu: 'Собирает и отправляет диагностические данные и телеметрию использования Windows.',
    CanDisableHint: 'Можно отключить безопасно: не влияет на игры и работу системы.',
    safetyLevel: 'safe'
  },
  {
    Name: 'SysMain',
    DisplayName: 'SysMain (Superfetch)',
    Category: 'System',
    Reason: 'Фоновая предзагрузка данных в ОЗУ',
    Status: 'Running',
    StartType: 'Automatic',
    SummaryRu: 'Кэширует часто запускаемые программы в оперативной памяти.',
    CanDisableHint: 'Можно отключить безопасно на SSD/NVMe: снижает фоновую нагрузку на диск и ОЗУ.',
    safetyLevel: 'safe'
  },
  {
    Name: 'WlanSvc',
    DisplayName: 'Служба автонастройки WLAN',
    Category: 'Network',
    Reason: 'Беспроводное подключение Wi-Fi',
    Status: 'Stopped',
    StartType: 'Manual',
    SummaryRu: 'Управляет беспроводным Wi-Fi соединением и поиском сетей.',
    CanDisableHint: 'Отключайте, только если ПК подключён по кабелю Ethernet и Wi-Fi не используется.',
    safetyLevel: 'optional'
  },
  {
    Name: 'Spooler',
    DisplayName: 'Диспетчер печати',
    Category: 'Print',
    Reason: 'Фоновая очередь печати',
    Status: 'Stopped',
    StartType: 'Automatic',
    SummaryRu: 'Управляет очередью печати принтеров и виртуального PDF-принтера.',
    CanDisableHint: 'Безопасно отключать во время игры, если не печатаете документы.',
    safetyLevel: 'optional'
  }
];

let previewWhitelist = [
  'AudioSrv',
  'Dhcp',
  'Dnscache',
  'EventLog',
  'FACEIT',
  'FACEITService',
  'PlugPlay',
  'Power',
  'Winmgmt'
];

const PREVIEW_FEATURE_PACK_DEFS: Array<Omit<ServiceFeaturePack, 'keepEnabledInGame'>> = [
  {
    id: 'wifi',
    title: 'Wi-Fi и мобильный интернет',
    description: 'Беспроводная сеть Wi-Fi, 4G/5G модем и точка доступа',
    services: ['WlanSvc', 'WwanSvc', 'icssvc']
  },
  {
    id: 'bluetooth',
    title: 'Bluetooth',
    description: 'Беспроводные наушники, колонки, геймпады и периферия',
    services: ['bthserv', 'BTAGService', 'BthAvctpSvc', 'BluetoothUserService']
  },
  {
    id: 'faceit',
    title: 'FACEIT AC',
    description: 'Античит и клиент FACEIT для матчей CS2 (включён по умолчанию)',
    services: ['FACEIT', 'FACEITService']
  },
  {
    id: 'camera',
    title: 'Веб-камера',
    description: 'Камера для OBS, Discord, трансляций и видеозвонков',
    services: ['FrameServer', 'FrameServerMonitor', 'StiSvc']
  },
  {
    id: 'xbox',
    title: 'Xbox / Store / Геймпад',
    description: 'Microsoft Store, Game Pass, Xbox Live, Game Bar и геймпад Xbox',
    services: [
      'XblAuthManager',
      'XblGameSave',
      'XboxGipSvc',
      'XboxNetApiSvc',
      'GamingServices',
      'GamingServicesNet',
      'BcastDVRUserService',
      'InstallService'
    ]
  },
  {
    id: 'vpn',
    title: 'VPN / PPPoE',
    description: 'Подключения VPN (L2TP/IKEv2/SSTP) и проводной PPPoE',
    services: ['RasMan', 'RasAuto', 'IKEEXT', 'PolicyAgent']
  },
  {
    id: 'printer',
    title: 'Принтер / PDF',
    description: 'Печать документов, виртуальный принтер PDF и сканеры',
    services: [
      'Spooler',
      'PrintNotify',
      'PrintWorkflowUserSvc',
      'PrintDeviceConfigurationService',
      'PrintScanBrokerService',
      'Fax'
    ]
  }
];

const PREVIEW_SERVICE_CATALOG: Record<
  string,
  {
    DisplayName: string;
    Category: ServiceCategory;
    Reason: string;
    Status: string;
    StartType: string;
    SummaryRu: string;
    CanDisableHint: string;
    safetyLevel: SafetyLevel;
  }
> = Object.fromEntries(
  previewBlacklist.map((b) => [
    b.Name.toLowerCase(),
    {
      DisplayName: b.DisplayName,
      Category: b.Category,
      Reason: b.Reason,
      Status: b.Status,
      StartType: b.StartType,
      SummaryRu: b.SummaryRu,
      CanDisableHint: b.CanDisableHint,
      safetyLevel: b.safetyLevel
    }
  ])
);

function buildPreviewServicesResponse(): ServicesLists {
  const coreSet = new Set(['audiosrv', 'dhcp', 'dnscache', 'eventlog', 'plugplay', 'power', 'winmgmt']);
  const whitelistItems = previewWhitelist.map((name) => {
    const isCoreLocked = coreSet.has(name.toLowerCase());
    const meta = PREVIEW_SERVICE_CATALOG[name.toLowerCase()];
    return {
      Name: name,
      DisplayName: meta?.DisplayName ?? (name === 'FACEIT' ? 'FACEIT Anti-Cheat Service' : name),
      Status: meta?.Status ?? 'Running',
      isCoreLocked,
      SummaryRu:
        meta?.SummaryRu ??
        (name === 'FACEIT'
          ? 'Драйверная служба античита FACEIT AC.'
          : 'Защищённая системная служба Windows.'),
      CanDisableHint:
        meta?.CanDisableHint ??
        (isCoreLocked
          ? 'Критическая служба ядра Windows — отключать нельзя.'
          : 'Сохраняется включённой в игровом режиме (режим «Без утилки»).'),
      safetyLevel: (isCoreLocked ? 'protected' : meta?.safetyLevel ?? 'protected') as SafetyLevel
    };
  });
  const allInstalledServices = [
    ...previewBlacklist.map((b) => ({
      Name: b.Name,
      DisplayName: b.DisplayName,
      Status: b.Status ?? 'Stopped',
      StartType: b.StartType ?? 'Manual',
      Category: b.Category,
      membership: 'blacklist' as const,
      isCoreLocked: false,
      disableInGaming: true,
      SummaryRu: b.SummaryRu,
      CanDisableHint: b.CanDisableHint,
      safetyLevel: b.safetyLevel
    })),
    ...whitelistItems.map((w) => {
      const meta = PREVIEW_SERVICE_CATALOG[w.Name.toLowerCase()];
      return {
        Name: w.Name,
        DisplayName: w.DisplayName,
        Status: w.Status,
        StartType: meta?.StartType ?? 'Automatic',
        Category: (meta?.Category ?? 'System') as ServiceCategory,
        membership: (w.isCoreLocked ? 'core' : 'whitelist') as 'core' | 'whitelist',
        isCoreLocked: w.isCoreLocked,
        disableInGaming: false,
        SummaryRu: w.SummaryRu,
        CanDisableHint: w.CanDisableHint,
        safetyLevel: w.safetyLevel
      };
    })
  ].sort((a, b) => {
    const aRun = a.Status === 'Running' ? 0 : 1;
    const bRun = b.Status === 'Running' ? 0 : 1;
    if (aRun !== bRun) return aRun - bRun;
    return a.DisplayName.toLowerCase().localeCompare(b.DisplayName.toLowerCase());
  });
  const featurePacks: ServiceFeaturePack[] = PREVIEW_FEATURE_PACK_DEFS.map((p) => ({
    ...p,
    keepEnabledInGame: p.services.every(
      (s) =>
        previewWhitelist.some((w) => w.toLowerCase() === s.toLowerCase()) &&
        !previewBlacklist.some((b) => b.Name.toLowerCase() === s.toLowerCase())
    )
  }));
  return {
    blacklist: previewBlacklist.map((item) => ({ ...item })),
    whitelist: [...previewWhitelist],
    whitelistDescriptions: {},
    whitelistItems,
    allInstalledServices,
    wifiActive: false,
    featurePacks
  };
}

let previewBlacklistProcesses = ['Discord', 'Spotify', 'Widgets', 'chrome'];
let previewProtectedStartupNames = ['ctfmon', 'AMDNoiseSuppression', 'SecurityHealthSystray'];
let previewProcesses: Array<{
  pid: number;
  name: string;
  displayName: string;
  memoryMb: number;
  isProtected: boolean;
  protectionKind: ProcessProtectionKind | null;
  inStartup?: boolean;
  summaryRu: string;
  canDisableHint: string;
  safetyLevel: SafetyLevel;
}> = [
  {
    pid: 4,
    name: 'System',
    displayName: 'Ядро Windows (System)',
    memoryMb: 0.2,
    isProtected: true,
    protectionKind: 'os_core',
    summaryRu: 'Базовый системный процесс ядра Windows и драйверов устройств.',
    canDisableHint: 'Критический компонент ядра ОС — отключать нельзя.',
    safetyLevel: 'protected'
  },
  {
    pid: 940,
    name: 'lsass',
    displayName: 'Служба локальной безопасности (LSASS)',
    memoryMb: 21.8,
    isProtected: true,
    protectionKind: 'os_core',
    summaryRu: 'Проверка подлинности входа, политик безопасности и прав доступа.',
    canDisableHint: 'Критический процесс безопасности — остановка перезагрузит ПК.',
    safetyLevel: 'protected'
  },
  {
    pid: 4120,
    name: 'UltraGamingMode',
    displayName: 'Ultra Gaming Mode',
    memoryMb: 84.5,
    isProtected: true,
    protectionKind: 'self_app',
    summaryRu: 'Текущее приложение оптимизации Ultra Gaming Mode.',
    canDisableHint: 'Защищено от самоотключения.',
    safetyLevel: 'protected'
  },
  {
    pid: 7112,
    name: 'steam',
    displayName: 'Steam Client',
    memoryMb: 188.4,
    isProtected: true,
    protectionKind: 'game_client',
    inStartup: true,
    summaryRu: 'Игровой клиент и оверлей Steam для запуска игр.',
    canDisableHint: 'Защищён как игровой клиент — нужен для стабильного запуска игр.',
    safetyLevel: 'protected'
  },
  {
    pid: 11240,
    name: 'chrome',
    displayName: 'Google Chrome',
    memoryMb: 412.6,
    isProtected: false,
    protectionKind: null,
    summaryRu: 'Веб-браузер Google Chrome (часто занимает много ОЗУ и процессорного времени).',
    canDisableHint: 'Можно смело выключить в Gaming Mode — освободит память и снизит микрофризы.',
    safetyLevel: 'safe'
  },
  {
    pid: 13804,
    name: 'Discord',
    displayName: 'Discord',
    memoryMb: 268.1,
    isProtected: false,
    protectionKind: null,
    inStartup: true,
    summaryRu: 'Голосовой и текстовый мессенджер Discord.',
    canDisableHint: 'По желанию: оставьте «Без утилки», если общаетесь в голосе во время игры.',
    safetyLevel: 'optional'
  },
  {
    pid: 15220,
    name: 'Spotify',
    displayName: 'Spotify',
    memoryMb: 194.0,
    isProtected: false,
    protectionKind: null,
    summaryRu: 'Музыкальный плеер Spotify.',
    canDisableHint: 'Можно выключить в Gaming Mode, если не слушаете музыку во время игры.',
    safetyLevel: 'optional'
  }
];

const PREVIEW_PROCESS_DESCRIPTIONS: Record<string, ProcessDescriptionEntry> = {
  widgets: {
    displayNameRu: 'Виджеты Windows 11',
    summaryRu: 'Панель новостей, погоды и виджетов Windows 11 на базе WebView2.',
    canDisableRu: 'Рекомендуется выключить в Gaming Mode — убирает фоновую нагрузку на ОЗУ и ЦП.',
    safetyLevel: 'safe'
  },
  ctfmon: {
    displayNameRu: 'Служба ввода текста (CTF Loader)',
    summaryRu: 'Отвечает за переключение раскладки клавиатуры и ввод текста в Windows.',
    canDisableRu: 'Системный процесс ввода — отключать нельзя.',
    safetyLevel: 'protected',
    protectionKind: 'os_core'
  },
  amdnoisesuppression: {
    displayNameRu: 'AMD Noise Suppression',
    summaryRu: 'Шумоподавление микрофона от драйвера AMD Adrenalin.',
    canDisableRu: 'По желанию: оставьте «Без утилки», если используете шумоподавление микрофона AMD.',
    safetyLevel: 'optional'
  },
  securityhealthsystray: {
    displayNameRu: 'Значок Безопасности Windows',
    summaryRu: 'Системный значок уведомлений Центра безопасности Windows в трее.',
    canDisableRu: 'Рекомендуется оставить «Без утилки» для уведомлений о защите системы.',
    safetyLevel: 'optional'
  }
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
      mpoStatus: 'Штатный конвейер DWM (без мерцания)',
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
    ? Math.min(1024, Math.max(32, Math.round(config.InputBufferQueueSize)))
    : 100;
  const purgeThresholdMb = Number.isFinite(config.AutoPurgeRamThresholdMB)
    ? Math.min(16384, Math.max(512, Math.round(config.AutoPurgeRamThresholdMB)))
    : 2048;

  const safeConfig: TuningConfig = {
    DisableFullscreenOptimizations: Boolean(config.DisableFullscreenOptimizations),
    DisableMouseAccel: Boolean(config.DisableMouseAccel),
    DisableNvidiaDynamicPstate: Boolean(config.DisableNvidiaDynamicPstate),
    EnableNetAdapterMsi: Boolean(config.EnableNetAdapterMsi),
    InputBufferQueueSize: queueSize,
    AutoLockTimerInGaming:
      config.AutoLockTimerInGaming !== undefined ? Boolean(config.AutoLockTimerInGaming) : true,
    AutoPurgeRamInGaming:
      config.AutoPurgeRamInGaming !== undefined ? Boolean(config.AutoPurgeRamInGaming) : true,
    AutoPurgeRamThresholdMB: purgeThresholdMb
  };

  if (isTauri) {
    return await invoke<TuningConfig>('save_tuning_config', { config: safeConfig });
  }

  previewTuningState = { ...safeConfig };
  return { ...previewTuningState };
}

export async function fetchAutostartStatus(): Promise<AutostartStatus> {
  if (isTauri) {
    return await invoke<AutostartStatus>('get_autostart_status');
  }
  return { ...previewAutostartState };
}

export async function setAutostart(enabled: boolean, startInTray: boolean): Promise<AutostartStatus> {
  if (isTauri) {
    return await invoke<AutostartStatus>('set_autostart', { enabled, startInTray });
  }
  previewAutostartState = {
    ...previewAutostartState,
    enabled,
    startInTray,
    taskExists: enabled,
    pathMatches: true,
    registeredCommand: enabled ? previewAutostartState.currentExePath : undefined
  };
  return { ...previewAutostartState };
}

export async function fetchServicesLists(): Promise<ServicesLists> {
  if (isTauri) {
    return await invoke<ServicesLists>('get_services_lists');
  }
  return buildPreviewServicesResponse();
}

export async function applyServiceFeaturePack(
  packId: string,
  keepEnabledInGame: boolean
): Promise<ServicesLists> {
  if (isTauri) {
    return await invoke<ServicesLists>('apply_service_feature_pack', {
      packId,
      keepEnabledInGame
    });
  }
  const pack = PREVIEW_FEATURE_PACK_DEFS.find((p) => p.id === packId);
  if (pack) {
    if (keepEnabledInGame) {
      for (const s of pack.services) {
        if (!previewWhitelist.some((w) => w.toLowerCase() === s.toLowerCase())) {
          previewWhitelist.push(s);
        }
      }
      previewBlacklist = previewBlacklist.filter(
        (b) => !pack.services.some((s) => s.toLowerCase() === b.Name.toLowerCase())
      );
    } else {
      previewWhitelist = previewWhitelist.filter(
        (w) => !pack.services.some((s) => s.toLowerCase() === w.toLowerCase())
      );
      for (const s of pack.services) {
        if (!previewBlacklist.some((b) => b.Name.toLowerCase() === s.toLowerCase())) {
          previewBlacklist.push({
            Name: s,
            DisplayName: s,
            Category: 'System',
            Reason: pack.description,
            Status: 'Stopped',
            StartType: 'Manual',
            SummaryRu: pack.description,
            CanDisableHint: 'Временное отключение в игровом режиме.',
            safetyLevel: 'optional'
          });
        }
      }
    }
  }
  return buildPreviewServicesResponse();
}

export async function setServiceGamingMode(
  serviceName: string,
  disableInGaming: boolean
): Promise<ServicesLists> {
  if (isTauri) {
    return await invoke<ServicesLists>('set_service_gaming_mode', {
      serviceName,
      disableInGaming
    });
  }
  const clean = serviceName.trim();
  if (disableInGaming) {
    previewWhitelist = previewWhitelist.filter((w) => w.toLowerCase() !== clean.toLowerCase());
    if (!previewBlacklist.some((b) => b.Name.toLowerCase() === clean.toLowerCase())) {
      const meta = PREVIEW_SERVICE_CATALOG[clean.toLowerCase()];
      previewBlacklist.push({
        Name: clean,
        DisplayName: meta?.DisplayName ?? clean,
        Category: meta?.Category ?? 'System',
        Reason: meta?.Reason ?? 'Настроено пользователем',
        Status: meta?.Status ?? 'Running',
        StartType: meta?.StartType ?? 'Automatic',
        SummaryRu: meta?.SummaryRu ?? 'Настроено пользователем.',
        CanDisableHint:
          meta?.CanDisableHint ??
          'Временно отключается в Gaming Mode и восстанавливается при выходе.',
        safetyLevel: meta?.safetyLevel ?? 'optional'
      });
    }
  } else {
    previewBlacklist = previewBlacklist.filter((b) => b.Name.toLowerCase() !== clean.toLowerCase());
    if (!previewWhitelist.some((w) => w.toLowerCase() === clean.toLowerCase())) {
      previewWhitelist.push(clean);
    }
  }
  return buildPreviewServicesResponse();
}

export async function setProcessGamingMode(
  processName: string,
  disableInGaming: boolean
): Promise<ProcessConfigLists> {
  if (isTauri) {
    return await invoke<ProcessConfigLists>('set_process_gaming_mode', {
      processName,
      disableInGaming
    });
  }
  const clean = processName.trim().replace(/\.exe$/i, '');
  if (disableInGaming) {
    previewProtectedStartupNames = previewProtectedStartupNames.filter(
      (x) => x.toLowerCase() !== clean.toLowerCase()
    );
    if (!previewBlacklistProcesses.some((x) => x.toLowerCase() === clean.toLowerCase())) {
      previewBlacklistProcesses = [...previewBlacklistProcesses, clean];
    }
  } else {
    previewBlacklistProcesses = previewBlacklistProcesses.filter(
      (x) => x.toLowerCase() !== clean.toLowerCase()
    );
    if (!previewProtectedStartupNames.some((x) => x.toLowerCase() === clean.toLowerCase())) {
      previewProtectedStartupNames = [...previewProtectedStartupNames, clean];
    }
  }
  return {
    blacklistProcesses: [...previewBlacklistProcesses],
    protectedStartupNames: [...previewProtectedStartupNames]
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
    protectedStartupNames: [...previewProtectedStartupNames],
    processDescriptions: { ...PREVIEW_PROCESS_DESCRIPTIONS },
    startupProcessNames: ['discord', 'steam', 'securityhealthsystray']
  };
}

export async function fetchWindowsStartupEntries(): Promise<StartupEntry[]> {
  if (isTauri) {
    return await invoke<StartupEntry[]>('get_windows_startup_entries');
  }
  return [
    {
      id: 'hkcu_run:Discord',
      name: 'Discord',
      displayName: 'Discord',
      source: 'hkcu_run',
      sourceLabel: 'Реестр пользователя',
      target: 'C:\\Users\\Player\\AppData\\Local\\Discord\\Update.exe --processStart Discord.exe',
      enabled: true,
      isProtected: previewProtectedStartupNames.some((p) => 'discord'.includes(p.toLowerCase())),
      matchedRule: previewProtectedStartupNames.find((p) => 'discord'.includes(p.toLowerCase()))
    },
    {
      id: 'hkcu_run:SecurityHealthSystray',
      name: 'SecurityHealthSystray',
      displayName: 'SecurityHealthSystray',
      source: 'hklm_run',
      sourceLabel: 'Реестр системы',
      target: 'C:\\Windows\\System32\\SecurityHealthSystray.exe',
      enabled: true,
      isProtected: previewProtectedStartupNames.some((p) =>
        'securityhealthsystray'.includes(p.toLowerCase())
      ),
      matchedRule: previewProtectedStartupNames.find((p) =>
        'securityhealthsystray'.includes(p.toLowerCase())
      )
    }
  ];
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
    return { success: false, message: `Процесс «${name}» защищён от завершения.` };
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
      previewBlacklistProcesses = previewBlacklistProcesses.filter(
        (x) => x.toLowerCase() !== clean.toLowerCase()
      );
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
  const item = previewBlacklist.find((s) => s.Name.toLowerCase() === serviceName.toLowerCase());
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
      previewBlacklist.push({
        Name: clean,
        DisplayName: params.displayName?.trim() || params.reason?.trim() || clean,
        Category: params.category ?? 'System',
        Reason: params.reason?.trim() || 'Добавлено пользователем',
        Status: 'Stopped',
        StartType: 'Manual',
        SummaryRu: params.reason?.trim() || 'Добавлено пользователем.',
        CanDisableHint: 'Можно отключить в игровом режиме.',
        safetyLevel: 'optional'
      });
    } else {
      previewBlacklist = previewBlacklist.filter((s) => s.Name.toLowerCase() !== clean.toLowerCase());
    }
  } else {
    if (params.operation === 'add') {
      if (!previewWhitelist.some((w) => w.toLowerCase() === clean.toLowerCase())) {
        previewWhitelist.push(clean);
      }
      previewBlacklist = previewBlacklist.filter((s) => s.Name.toLowerCase() !== clean.toLowerCase());
    } else {
      previewWhitelist = previewWhitelist.filter((w) => w.toLowerCase() !== clean.toLowerCase());
    }
  }
  return buildPreviewServicesResponse();
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
    previewTuningState = buildProfileTuningPreset(profile, previewTuningState);
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

export async function finishPendingRestore(): Promise<ActionResult> {
  if (isTauri) {
    try {
      return await invoke<ActionResult>('finish_pending_restore');
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
    message: 'Предпросмотр: восстановление пользовательского профиля завершено.'
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

export async function unlockTimerResolution(): Promise<ActionResult> {
  if (isTauri) {
    try {
      return await invoke<ActionResult>('unlock_timer_resolution');
    } catch (err) {
      return {
        success: false,
        message: formatIpcError(err)
      };
    }
  }

  await new Promise((r) => setTimeout(r, 150));
  return {
    success: true,
    message: 'Предпросмотр: фиксация системного таймера снята.'
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
    currentVersion: '3.6.0',
    latestVersion: '3.6.0',
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
