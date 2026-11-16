<script lang="ts">
  import { onMount } from 'svelte';
  import {
    Activity,
    AlertCircle,
    LayoutDashboard,
    ListChecks,
    RefreshCw,
    SlidersHorizontal,
    Wrench,
    X
  } from '@lucide/svelte';
  import TitleBar from './lib/components/TitleBar.svelte';
  import DashboardView from './lib/components/DashboardView.svelte';
  import ProcessesView, {
    type ProcessFilterMode,
    type ProcessViewMode
  } from './lib/components/ProcessesView.svelte';
  import ServicesView, {
    type ServiceCategoryFilter,
    type ServiceViewMode
  } from './lib/components/ServicesView.svelte';
  import TweaksView from './lib/components/TweaksView.svelte';
  import RepairView, { type RepairStatusMessage } from './lib/components/RepairView.svelte';
  import LogConsole from './lib/components/LogConsole.svelte';
  import ConfirmDialog from './lib/components/ConfirmDialog.svelte';
  import {
    buildProfileTuningPreset,
    controlService,
    executeEmergencyRepair,
    executeModeAction,
    fetchRunningProcesses,
    fetchServicesLists,
    fetchSystemStatus,
    fetchTuningConfig,
    formatIpcError,
    isTauri,
    killProcess,
    lockTimerResolution,
    resolveProfileFromTuning,
    saveTuningConfig,
    setWindowTheme,
    updateProcessList,
    updateServiceList
  } from './lib/api';
  import type {
    BlacklistServiceItem,
    ConfirmDialogRequest,
    ErrorBannerState,
    HardwareInfo,
    ListMutationOperation,
    LogEntry,
    ModeAction,
    ModeState,
    OptimizationProfile,
    ProcessItem,
    ProcessListType,
    RepairType,
    ServiceCategory,
    ServiceControlOperation,
    ServiceListType,
    TabId,
    ThemeMode,
    TuningConfig
  } from './lib/types';

  const TAB_META: Array<{ id: TabId; label: string }> = [
    { id: 'dashboard', label: 'Обзор' },
    { id: 'processes', label: 'Процессы' },
    { id: 'services', label: 'Службы' },
    { id: 'tweaks', label: 'Настройки' },
    { id: 'repair', label: 'Обслуживание' }
  ];

  const ruPlural = new Intl.PluralRules('ru-RU');
  const timeFormatter = new Intl.DateTimeFormat('ru-RU', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit'
  });

  function formatRussianPlural(
    count: number,
    forms: { one: string; few: string; many: string }
  ): string {
    const rule = ruPlural.select(count);
    if (rule === 'one') return `${count} ${forms.one}`;
    if (rule === 'few') return `${count} ${forms.few}`;
    return `${count} ${forms.many}`;
  }

  function getInitialTheme(): ThemeMode {
    if (typeof document !== 'undefined') {
      return document.documentElement.getAttribute('data-theme') === 'light' ? 'light' : 'dark';
    }
    return 'dark';
  }

  let theme = $state<ThemeMode>(getInitialTheme());
  let currentTab = $state<TabId>('dashboard');
  let tabButtons = $state<Array<HTMLButtonElement | null>>([null, null, null, null, null]);

  // System Status & Mode
  let mode = $state<ModeState>('Normal');
  let profile = $state<OptimizationProfile>('competitive');
  let customProfileSelected = $state(false);
  let hardware = $state<HardwareInfo | null>(null);
  let activeSince = $state<string | undefined>(undefined);
  let isStatusLoading = $state(true);
  let statusError = $state<string | null>(null);
  let isProcessing = $state(false);
  let timerLocked = $state(false);
  let isTimerLocking = $state(false);

  // Processes Tab State (persists across tabs)
  let processes = $state<ProcessItem[]>([]);
  let blacklistProcesses = $state<string[]>([]);
  let protectedStartupNames = $state<string[]>([]);
  let processesViewMode = $state<ProcessViewMode>('live');
  let processesFilterMode = $state<ProcessFilterMode>('all');
  let processesSearchQuery = $state('');
  let isProcessesLoading = $state(true);
  let processBusyKey = $state<string | null>(null);
  let processesError = $state<string | null>(null);

  // Services Tab State (persists across tabs)
  let blacklist = $state<BlacklistServiceItem[]>([]);
  let whitelist = $state<string[]>([]);
  let servicesViewMode = $state<ServiceViewMode>('blacklist');
  let servicesSearchQuery = $state('');
  let servicesCategory = $state<ServiceCategoryFilter>('all');
  let isServicesLoading = $state(true);
  let busyService = $state<string | null>(null);
  let servicesError = $state<string | null>(null);

  // Tuning Config State (persists across tabs, serialized save)
  let tuningConfig = $state<TuningConfig | null>(null);
  let isTuningLoading = $state(true);
  let isTuningSaving = $state(false);
  let tuningError = $state<string | null>(null);
  let tuningSaveChain: Promise<void> = Promise.resolve();
  let latestTuningReqId = 0;

  // Repair Tab State (persists across tabs)
  let runningRepair = $state<RepairType | null>(null);
  let repairStatus = $state<RepairStatusMessage | null>(null);

  // Global Alert, Live Announcements, Logs, Confirm Modal
  let globalError = $state<ErrorBannerState | null>(null);
  let dismissedStatusErrorDetail = $state<string | null>(null);
  let liveAnnouncement = $state('');
  let logs = $state<LogEntry[]>([]);
  let logExpanded = $state(false);
  let confirmRequest = $state<ConfirmDialogRequest | null>(null);
  let confirmResolver: ((confirmed: boolean) => void) | null = null;
  let logSeq = 0;

  function addLog(level: LogEntry['level'], message: string) {
    logSeq += 1;
    const entry: LogEntry = {
      id: `${Date.now()}-${logSeq}`,
      timestamp: timeFormatter.format(new Date()),
      level,
      message
    };
    const next = [...logs, entry];
    logs = next.length > 250 ? next.slice(next.length - 250) : next;
  }

  function setError(source: ErrorBannerState['source'], title: string, detail: string) {
    globalError = { source, title, detail };
  }

  function clearErrorIfSource(source: ErrorBannerState['source']) {
    if (globalError?.source === source) {
      globalError = null;
    }
  }

  function requestConfirm(req: ConfirmDialogRequest): Promise<boolean> {
    if (confirmResolver) {
      confirmResolver(false);
      confirmResolver = null;
    }
    confirmRequest = req;
    return new Promise<boolean>((resolve) => {
      confirmResolver = resolve;
    });
  }

  function handleConfirmResolve(confirmed: boolean) {
    const resolve = confirmResolver;
    confirmResolver = null;
    confirmRequest = null;
    resolve?.(confirmed);
  }

  function applyTheme(next: ThemeMode) {
    const style = document.createElement('style');
    style.textContent =
      '*, *::before, *::after { transition-duration: 0s !important; animation-duration: 0s !important; }';
    document.head.appendChild(style);
    void document.body.offsetHeight;

    document.documentElement.setAttribute('data-theme', next);
    document
      .querySelector('meta[name="color-scheme"]')
      ?.setAttribute('content', next);

    try {
      localStorage.setItem('ugm-theme', next);
    } catch {
      // ignore localStorage restrictions
    }

    theme = next;
    void setWindowTheme(next === 'dark').catch(() => {});

    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        style.remove();
      });
    });
  }

  function handleToggleTheme() {
    const next: ThemeMode = theme === 'dark' ? 'light' : 'dark';
    applyTheme(next);
    liveAnnouncement =
      next === 'light' ? 'Включена светлая тема.' : 'Включена тёмная тема.';
  }

  async function loadSystemStatus(silent = false) {
    if (!silent) {
      isStatusLoading = true;
      dismissedStatusErrorDetail = null;
    }
    try {
      const status = await fetchSystemStatus();
      if (isTauri || !silent) {
        mode = status.mode;
        activeSince = status.activeSince;
      }
      if (status.mode !== 'Normal' || !customProfileSelected) {
        profile = status.profile;
      }
      if (!isTauri && timerLocked) {
        hardware = { ...status.hardware, timerResolution: '0.500 мс (зафиксировано)' };
      } else {
        hardware = status.hardware;
      }
      statusError = null;
      dismissedStatusErrorDetail = null;
      clearErrorIfSource('status');
    } catch (err) {
      const detail = formatIpcError(err);
      statusError = detail;
      const shouldPreserveActiveError =
        silent && globalError !== null && globalError.source !== 'status';
      const wasDismissed = silent && dismissedStatusErrorDetail === detail;
      if (!shouldPreserveActiveError && !wasDismissed) {
        setError('status', 'Ошибка получения системного статуса', detail);
      }
      if (!silent) {
        addLog('error', `Сбой чтения статуса системы: ${detail}`);
      }
    } finally {
      isStatusLoading = false;
    }
  }

  async function loadProcesses(silent = false) {
    if (!silent) {
      isProcessesLoading = true;
    }
    try {
      const snap = await fetchRunningProcesses();
      processes = snap.processes;
      blacklistProcesses = snap.blacklistProcesses;
      protectedStartupNames = snap.protectedStartupNames;
      processesError = null;
      clearErrorIfSource('processes');
    } catch (err) {
      const detail = formatIpcError(err);
      processesError = detail;
      if (!silent) {
        setError('processes', 'Ошибка сканирования процессов Windows', detail);
        addLog('error', `Сбой чтения процессов: ${detail}`);
      }
    } finally {
      isProcessesLoading = false;
    }
  }

  async function loadServices() {
    isServicesLoading = true;
    try {
      const lists = await fetchServicesLists();
      blacklist = lists.blacklist;
      whitelist = lists.whitelist;
      servicesError = null;
      clearErrorIfSource('services');
    } catch (err) {
      const detail = formatIpcError(err);
      servicesError = detail;
      setError('services', 'Ошибка загрузки списка служб Windows', detail);
      addLog('error', `Сбой чтения служб: ${detail}`);
    } finally {
      isServicesLoading = false;
    }
  }

  async function loadTuning() {
    isTuningLoading = true;
    try {
      const loaded = await fetchTuningConfig();
      tuningConfig = loaded;
      if (mode === 'Normal' && !customProfileSelected) {
        profile = resolveProfileFromTuning(loaded);
      }
      tuningError = null;
      clearErrorIfSource('tuning');
    } catch (err) {
      const detail = formatIpcError(err);
      tuningError = detail;
      setError('tuning', 'Ошибка чтения параметров Config/tuning.json', detail);
      addLog('error', `Сбой чтения tuning.json: ${detail}`);
    } finally {
      isTuningLoading = false;
    }
  }

  async function bootstrapApp() {
    addLog(
      'info',
      isTauri
        ? 'Интерфейс подключён к модулю управления Windows.'
        : 'Запущен предпросмотр интерфейса вне среды Tauri.'
    );
    await Promise.all([loadSystemStatus(), loadServices(), loadTuning(), loadProcesses()]);
    if (blacklist.length > 0) {
      addLog(
        'info',
        `Загружено ${formatRussianPlural(blacklist.length, {
          one: 'оптимизируемая служба',
          few: 'оптимизируемые службы',
          many: 'оптимизируемых служб'
        })} и ${formatRussianPlural(whitelist.length, {
          one: 'защищённая служба',
          few: 'защищённые службы',
          many: 'защищённых служб'
        })}.`
      );
    }
  }

  onMount(() => {
    void setWindowTheme(theme === 'dark').catch(() => {});
    void bootstrapApp();

    const interval = setInterval(() => {
      if (
        typeof document !== 'undefined' &&
        document.visibilityState === 'visible' &&
        !isProcessing &&
        runningRepair === null
      ) {
        void loadSystemStatus(true);
      }
    }, 5000);

    return () => {
      clearInterval(interval);
    };
  });

  $effect(() => {
    const label = TAB_META.find((t) => t.id === currentTab)?.label ?? 'Обзор';
    document.title = `${label} — Ultra Gaming Mode`;
  });

  function profileLabel(p: OptimizationProfile): string {
    if (p === 'competitive') return 'Киберспорт';
    if (p === 'aaa') return 'AAA и стриминг';
    return 'Пользовательский';
  }

  async function handleToggleMode() {
    if (isProcessing || mode === 'Transitioning') return;
    const isCurrentlyActive = mode === 'Gaming' || mode === 'Armed';
    const action: ModeAction = isCurrentlyActive ? 'Restore' : 'Enable';
    const targetProfile = profile;

    isProcessing = true;
    const prevMode = mode;
    mode = 'Transitioning';
    addLog(
      'info',
      action === 'Enable'
        ? `Запуск игрового режима (профиль «${profileLabel(targetProfile)}»)...`
        : 'Выключение игрового режима и восстановление служб...'
    );

    try {
      const res = await executeModeAction(action, targetProfile);
      if (res.success) {
        addLog('success', res.message);
        if (action === 'Restore') {
          timerLocked = false;
        }
        clearErrorIfSource('action');
        if (!isTauri) {
          mode = action === 'Enable' ? 'Armed' : 'Normal';
          activeSince =
            action === 'Enable' ? timeFormatter.format(new Date()) : undefined;
          if (action === 'Enable' && (targetProfile === 'competitive' || targetProfile === 'aaa')) {
            tuningConfig = buildProfileTuningPreset(targetProfile);
          }
          if (action === 'Restore' && hardware) {
            hardware = { ...hardware, timerResolution: '1.000 мс (штатный)' };
          }
        } else {
          await Promise.all([loadSystemStatus(true), loadServices(), loadTuning()]);
        }
        liveAnnouncement = res.message;
      } else {
        mode = prevMode;
        setError('action', 'Не удалось переключить режим', res.message);
        addLog('error', res.message);
        liveAnnouncement = `Ошибка: ${res.message}`;
        if (isTauri) {
          await loadSystemStatus(true);
        }
      }
    } catch (err) {
      const detail = formatIpcError(err);
      mode = 'Error';
      setError('action', 'Сбой выполнения команды переключения', detail);
      addLog('error', detail);
    } finally {
      isProcessing = false;
    }
  }

  async function handleProfileChange(nextProfile: OptimizationProfile) {
    if (isProcessing || mode === 'Transitioning') return;

    if (nextProfile === 'custom') {
      customProfileSelected = true;
      profile = 'custom';
      addLog('info', 'Выбран пользовательский профиль (используются параметры Config/tuning.json).');
      liveAnnouncement = 'Выбран пользовательский профиль.';
      return;
    }

    const prevProfile = profile;
    customProfileSelected = false;
    profile = nextProfile;

    if (tuningConfig) {
      const nextCfg = buildProfileTuningPreset(nextProfile);
      const savedOk = await handleUpdateTuning(nextCfg, false);
      if (!savedOk) {
        profile = prevProfile;
        customProfileSelected = prevProfile === 'custom';
        return;
      }
    }

    const label = profileLabel(nextProfile);
    addLog('info', `Выбран профиль оптимизации: ${label}.`);
    liveAnnouncement = `Выбран профиль ${label}.`;
  }

  async function handleLockTimer() {
    if (isTimerLocking || isProcessing) return;
    isTimerLocking = true;
    addLog('info', 'Фиксация системного таймера Windows на 0.500 мс…');
    try {
      const res = await lockTimerResolution();
      if (res.success) {
        timerLocked = true;
        clearErrorIfSource('timer');
        addLog('success', res.message);
        if (hardware) {
          hardware = { ...hardware, timerResolution: '0.500 мс (зафиксировано)' };
        }
        liveAnnouncement = 'Разрешение таймера зафиксировано на 0.5 миллисекунды.';
      } else {
        setError('timer', 'Не удалось зафиксировать таймер 0.5 мс', res.message);
        addLog('error', res.message);
      }
    } catch (err) {
      const detail = formatIpcError(err);
      setError('timer', 'Ошибка запуска таймера высокого разрешения', detail);
      addLog('error', detail);
    } finally {
      isTimerLocking = false;
    }
  }

  async function handleUpdateTuning(next: TuningConfig, syncProfile = true): Promise<boolean> {
    const snapshot = tuningConfig ? { ...tuningConfig } : null;
    latestTuningReqId += 1;
    const reqId = latestTuningReqId;

    tuningConfig = next;
    isTuningSaving = true;
    let savedOk = false;

    const run = tuningSaveChain
      .catch(() => {})
      .then(async () => {
        const saved = await saveTuningConfig(next);
        if (reqId === latestTuningReqId) {
          tuningConfig = saved;
          if (syncProfile) {
            const resolved = resolveProfileFromTuning(saved);
            profile = resolved;
            customProfileSelected = resolved === 'custom';
          }
        }
        savedOk = true;
      });

    tuningSaveChain = run;

    try {
      await run;
      clearErrorIfSource('tuning');
      addLog(
        'success',
        `Параметры tuning.json обновлены (очередь ввода: ${next.InputBufferQueueSize}).`
      );
      liveAnnouncement = 'Параметры оптимизации сохранены.';
      return savedOk;
    } catch (err) {
      if (snapshot && reqId === latestTuningReqId) {
        tuningConfig = snapshot;
      }
      const detail = formatIpcError(err);
      setError('tuning', 'Не удалось сохранить настройки', detail);
      addLog('error', `Ошибка сохранения tuning.json: ${detail}`);
      liveAnnouncement = 'Ошибка сохранения настроек.';
      return false;
    } finally {
      if (reqId === latestTuningReqId) {
        isTuningSaving = false;
      }
    }
  }

  async function handleRunRepair(
    type: RepairType,
    title: string,
    confirm?: ConfirmDialogRequest
  ) {
    if (runningRepair !== null) return;

    if (confirm) {
      const approved = await requestConfirm(confirm);
      if (!approved) return;
    }

    runningRepair = type;
    repairStatus = null;
    addLog('info', `Запуск операции обслуживания: «${title}»…`);

    try {
      const res = await executeEmergencyRepair(type);
      if (res.success) {
        repairStatus = { type: 'success', text: res.message };
        clearErrorIfSource('repair');
        addLog('success', res.message);
        if (type === 'services') {
          await Promise.all([loadSystemStatus(true), loadServices()]);
        }
        liveAnnouncement = res.message;
      } else {
        repairStatus = { type: 'error', text: res.message };
        setError('repair', `Ошибка операции «${title}»`, res.message);
        addLog('error', res.message);
        liveAnnouncement = `Ошибка: ${res.message}`;
      }
    } catch (err) {
      const detail = formatIpcError(err);
      repairStatus = { type: 'error', text: detail };
      setError('repair', `Сбой операции «${title}»`, detail);
      addLog('error', detail);
    } finally {
      runningRepair = null;
    }
  }

  async function handleRequestClearLogs() {
    if (logs.length === 0) return;
    const approved = await requestConfirm({
      title: 'Очистить журнал событий?',
      description: `Будут удалены все записи текущей сессии (${formatRussianPlural(logs.length, {
        one: 'запись',
        few: 'записи',
        many: 'записей'
      })}). Это не повлияет на параметры Windows.`,
      confirmLabel: 'Очистить журнал',
      cancelLabel: 'Отмена',
      tone: 'warn'
    });
    if (!approved) return;
    logs = [];
    liveAnnouncement = 'Журнал событий очищен.';
  }

  async function handleKillProcess(proc: ProcessItem) {
    if (processBusyKey !== null || proc.isProtected) return;
    const approved = await requestConfirm({
      title: `Завершить процесс «${proc.name}»?`,
      description: `Вы собираетесь принудительно завершить процесс ${proc.name} (PID ${proc.pid}). Несохранённые данные в этом приложении будут потеряны.`,
      confirmLabel: 'Завершить процесс',
      cancelLabel: 'Отмена',
      tone: 'danger'
    });
    if (!approved) return;

    processBusyKey = `kill:${proc.pid}`;
    try {
      const res = await killProcess(proc.pid, proc.name);
      if (res.success) {
        clearErrorIfSource('processes');
        addLog('success', res.message);
        liveAnnouncement = res.message;
        await loadProcesses(true);
      } else {
        setError('processes', 'Не удалось завершить процесс', res.message);
        addLog('error', res.message);
      }
    } catch (err) {
      const detail = formatIpcError(err);
      setError('processes', 'Сбой завершения процесса', detail);
      addLog('error', detail);
    } finally {
      processBusyKey = null;
    }
  }

  async function handleUpdateProcessList(
    listType: ProcessListType,
    processName: string,
    operation: ListMutationOperation
  ) {
    if (processBusyKey !== null) return;
    processBusyKey = `proc:${processName}`;
    try {
      const updated = await updateProcessList(listType, processName, operation);
      blacklistProcesses = updated.blacklistProcesses;
      protectedStartupNames = updated.protectedStartupNames;
      clearErrorIfSource('processes');
      const targetLabel = listType === 'blacklist' ? 'чёрного списка' : 'исключений';
      const actionLabel = operation === 'add' ? 'добавлен в список' : 'удалён из списка';
      const msg = `Процесс «${processName}» ${actionLabel} (${targetLabel}).`;
      addLog('success', msg);
      liveAnnouncement = msg;
      await loadProcesses(true);
    } catch (err) {
      const detail = formatIpcError(err);
      setError('processes', 'Ошибка обновления правил процессов', detail);
      addLog('error', detail);
    } finally {
      processBusyKey = null;
    }
  }

  async function handleControlService(serviceName: string, operation: ServiceControlOperation) {
    if (busyService !== null) return;
    if (operation === 'Stop' || operation === 'Disabled') {
      const approved = await requestConfirm({
        title: `Остановить службу «${serviceName}»?`,
        description:
          operation === 'Stop'
            ? `Служба «${serviceName}» будет немедленно остановлена. При необходимости её можно запустить снова в этой же вкладке.`
            : `Тип запуска службы «${serviceName}» будет переключён на «Отключена».`,
        confirmLabel: operation === 'Stop' ? 'Остановить' : 'Отключить',
        cancelLabel: 'Отмена',
        tone: 'warn'
      });
      if (!approved) return;
    }

    busyService = serviceName;
    try {
      const res = await controlService(serviceName, operation);
      if (res.success) {
        clearErrorIfSource('services');
        addLog('success', res.message);
        liveAnnouncement = res.message;
        await loadServices();
      } else {
        setError('services', `Не удалось управлять службой «${serviceName}»`, res.message);
        addLog('error', res.message);
      }
    } catch (err) {
      const detail = formatIpcError(err);
      setError('services', `Сбой управления службой «${serviceName}»`, detail);
      addLog('error', detail);
    } finally {
      busyService = null;
    }
  }

  async function handleUpdateServiceList(params: {
    listType: ServiceListType;
    serviceName: string;
    displayName?: string;
    category?: ServiceCategory;
    reason?: string;
    operation: ListMutationOperation;
  }) {
    if (busyService !== null) return;
    if (params.listType === 'whitelist' && params.operation === 'remove') {
      const approved = await requestConfirm({
        title: `Убрать «${params.serviceName}» из белого списка?`,
        description:
          'Снятие защиты позволит добавлять эту службу в оптимизируемый список. Критические службы ОС всё равно останутся защищены на уровне бэкенда.',
        confirmLabel: 'Убрать защиту',
        cancelLabel: 'Отмена',
        tone: 'warn'
      });
      if (!approved) return;
    }

    busyService = params.serviceName;
    try {
      const updated = await updateServiceList(params);
      blacklist = updated.blacklist;
      whitelist = updated.whitelist;
      clearErrorIfSource('services');
      const scopeLabel =
        params.listType === 'blacklist' ? 'оптимизируемых служб' : 'белого списка';
      const msg =
        params.operation === 'add'
          ? `Служба «${params.serviceName}» добавлена в список (${scopeLabel}).`
          : `Служба «${params.serviceName}» удалена из списка (${scopeLabel}).`;
      addLog('success', msg);
      liveAnnouncement = msg;
    } catch (err) {
      const detail = formatIpcError(err);
      setError('services', 'Ошибка обновления списков служб', detail);
      addLog('error', detail);
    } finally {
      busyService = null;
    }
  }

  function handleRetryFromGlobalBanner() {
    if (!globalError) return;
    if (globalError.source === 'status') void loadSystemStatus();
    else if (globalError.source === 'processes') void loadProcesses();
    else if (globalError.source === 'services') void loadServices();
    else if (globalError.source === 'tuning') void loadTuning();
  }

  function handleTabKeyDown(e: KeyboardEvent, index: number) {
    let nextIndex: number | null = null;
    if (e.key === 'ArrowRight') nextIndex = (index + 1) % TAB_META.length;
    else if (e.key === 'ArrowLeft') nextIndex = (index - 1 + TAB_META.length) % TAB_META.length;
    else if (e.key === 'Home') nextIndex = 0;
    else if (e.key === 'End') nextIndex = TAB_META.length - 1;

    if (nextIndex !== null) {
      e.preventDefault();
      const targetTab = TAB_META[nextIndex].id;
      currentTab = targetTab;
      if (targetTab === 'processes') {
        void loadProcesses(true);
      }
      tabButtons[nextIndex]?.focus();
    }
  }
</script>

<a href="#main-content" class="skip-link">Перейти к основному содержимому</a>

<div class="min-h-screen flex flex-col bg-[var(--bg-app)] text-[var(--text-primary)] pt-11">
  <TitleBar {theme} onToggleTheme={handleToggleTheme} />

  <div class="w-full max-w-5xl mx-auto px-4 sm:px-6 py-4 flex-1 flex flex-col gap-4">
    <!-- Top Tab Navigation -->
    <nav aria-label="Разделы приложения" class="ui-card rounded-2xl p-1.5">
      <div
        role="tablist"
        aria-label="Разделы управления"
        class="grid grid-cols-2 sm:grid-cols-5 gap-1.5"
      >
        {#each TAB_META as tab, index (tab.id)}
          {@const selected = currentTab === tab.id}
          <button
            bind:this={tabButtons[index]}
            id="tab-{tab.id}"
            type="button"
            role="tab"
            aria-selected={selected}
            aria-controls="panel-{tab.id}"
            tabindex={selected ? 0 : -1}
            onclick={() => {
              currentTab = tab.id;
              if (tab.id === 'processes') {
                void loadProcesses(true);
              }
            }}
            onkeydown={(e) => handleTabKeyDown(e, index)}
            class="ui-tab ui-pressable rounded-xl px-3 py-2.5 min-h-10 text-sm font-medium flex items-center justify-center gap-2 cursor-pointer"
          >
            {#if tab.id === 'dashboard'}
              <LayoutDashboard size={16} strokeWidth={1.75} aria-hidden="true" />
            {:else if tab.id === 'processes'}
              <Activity size={16} strokeWidth={1.75} aria-hidden="true" />
            {:else if tab.id === 'services'}
              <ListChecks size={16} strokeWidth={1.75} aria-hidden="true" />
            {:else if tab.id === 'tweaks'}
              <SlidersHorizontal size={16} strokeWidth={1.75} aria-hidden="true" />
            {:else}
              <Wrench size={16} strokeWidth={1.75} aria-hidden="true" />
            {/if}

            <span>
              {tab.label}{#if tab.id === 'services' && blacklist.length > 0}&nbsp;<span class="tabular-nums opacity-85">({blacklist.length})</span>{:else if tab.id === 'processes' && processes.length > 0}&nbsp;<span class="tabular-nums opacity-85">({processes.length})</span>{/if}
            </span>
          </button>
        {/each}
      </div>
    </nav>

    <!-- Main Content Area -->
    <main id="main-content" tabindex="-1" class="flex-1 flex flex-col gap-4 outline-none">
      {#if globalError}
        <div
          role="alert"
          class="ui-card rounded-2xl p-4 border border-[var(--status-danger-border)] bg-[var(--status-danger-soft)] flex flex-col sm:flex-row sm:items-center justify-between gap-3"
        >
          <div class="flex items-start gap-3 min-w-0">
            <AlertCircle
              size={18}
              strokeWidth={1.75}
              class="text-[var(--status-danger-text)] shrink-0 mt-0.5"
              aria-hidden="true"
            />
            <div class="min-w-0 space-y-0.5">
              <p class="text-sm font-semibold text-[var(--status-danger-text)]">
                {globalError.title}
              </p>
              <p class="text-sm text-[var(--text-secondary)] break-words">
                {globalError.detail}
              </p>
            </div>
          </div>

          <div class="flex flex-wrap items-center gap-2 shrink-0">
            {#if globalError.source === 'status' || globalError.source === 'processes' || globalError.source === 'services' || globalError.source === 'tuning'}
              <button
                type="button"
                onclick={handleRetryFromGlobalBanner}
                class="ui-btn-secondary ui-pressable rounded-lg px-3 py-1.5 min-h-9 text-[0.8125rem] font-medium flex items-center gap-1.5 cursor-pointer"
              >
                <RefreshCw size={14} strokeWidth={1.75} aria-hidden="true" />
                <span>Повторить</span>
              </button>
            {/if}

            {#if !logExpanded && logs.length > 0}
              <button
                type="button"
                onclick={() => (logExpanded = true)}
                class="ui-btn-secondary ui-pressable rounded-lg px-3 py-1.5 min-h-9 text-[0.8125rem] font-medium cursor-pointer"
              >
                Открыть журнал
              </button>
            {/if}

            <button
              type="button"
              onclick={() => {
                if (globalError?.source === 'status') {
                  dismissedStatusErrorDetail = globalError.detail;
                }
                globalError = null;
              }}
              aria-label="Скрыть сообщение об ошибке"
              class="ui-btn-ghost w-9 h-9 rounded-lg flex items-center justify-center cursor-pointer"
            >
              <X size={16} strokeWidth={1.75} aria-hidden="true" />
            </button>
          </div>
        </div>
      {/if}

      <div
        id="panel-dashboard"
        role="tabpanel"
        aria-labelledby="tab-dashboard"
        hidden={currentTab !== 'dashboard'}
      >
        <DashboardView
          {mode}
          {profile}
          {hardware}
          {isProcessing}
          {isStatusLoading}
          {statusError}
          {activeSince}
          {timerLocked}
          {isTimerLocking}
          onToggleMode={handleToggleMode}
          onProfileChange={handleProfileChange}
          onLockTimer={handleLockTimer}
          onRetryStatus={() => loadSystemStatus()}
        />
      </div>

      <div
        id="panel-processes"
        role="tabpanel"
        aria-labelledby="tab-processes"
        hidden={currentTab !== 'processes'}
      >
        <ProcessesView
          {processes}
          {blacklistProcesses}
          {protectedStartupNames}
          viewMode={processesViewMode}
          filterMode={processesFilterMode}
          searchQuery={processesSearchQuery}
          isLoading={isProcessesLoading}
          busyKey={processBusyKey}
          loadError={processesError}
          onViewModeChange={(m) => (processesViewMode = m)}
          onFilterModeChange={(f) => (processesFilterMode = f)}
          onSearchChange={(q) => (processesSearchQuery = q)}
          onRefresh={() => loadProcesses()}
          onKillProcess={handleKillProcess}
          onUpdateList={handleUpdateProcessList}
        />
      </div>

      <div
        id="panel-services"
        role="tabpanel"
        aria-labelledby="tab-services"
        hidden={currentTab !== 'services'}
      >
        <ServicesView
          {blacklist}
          {whitelist}
          viewMode={servicesViewMode}
          searchQuery={servicesSearchQuery}
          selectedCategory={servicesCategory}
          isLoading={isServicesLoading}
          {busyService}
          loadError={servicesError}
          onViewModeChange={(m) => (servicesViewMode = m)}
          onSearchChange={(q) => (servicesSearchQuery = q)}
          onCategoryChange={(c) => (servicesCategory = c)}
          onRetry={loadServices}
          onControlService={handleControlService}
          onUpdateServiceList={handleUpdateServiceList}
        />
      </div>

      <div
        id="panel-tweaks"
        role="tabpanel"
        aria-labelledby="tab-tweaks"
        hidden={currentTab !== 'tweaks'}
      >
        <TweaksView
          config={tuningConfig}
          isLoading={isTuningLoading}
          isSaving={isTuningSaving}
          loadError={tuningError}
          {mode}
          onUpdateConfig={handleUpdateTuning}
          onRetryLoad={loadTuning}
        />
      </div>

      <div
        id="panel-repair"
        role="tabpanel"
        aria-labelledby="tab-repair"
        hidden={currentTab !== 'repair'}
      >
        <RepairView
          {runningRepair}
          statusMessage={repairStatus}
          onRunRepair={handleRunRepair}
          onDismissStatus={() => (repairStatus = null)}
        />
      </div>
    </main>

    <!-- Collapsible Event Console -->
    <LogConsole
      {logs}
      expanded={logExpanded}
      onToggleExpand={() => (logExpanded = !logExpanded)}
      onRequestClear={handleRequestClearLogs}
      onCopyError={(detail) => {
        setError('clipboard', 'Не удалось скопировать журнал', detail);
        addLog('error', `Ошибка буфера обмена: ${detail}`);
      }}
    />
  </div>
</div>

<div class="sr-only" aria-live="polite" aria-atomic="true">
  {liveAnnouncement}
</div>

<ConfirmDialog request={confirmRequest} onResolve={handleConfirmResolve} />
