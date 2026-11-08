<script lang="ts">
  import { onMount } from 'svelte';
  import {
    Layers,
    LayoutDashboard,
    Sliders,
    Wrench,
  } from '@lucide/svelte';
  import TitleBar from './lib/components/TitleBar.svelte';
  import DashboardView from './lib/components/DashboardView.svelte';
  import ServicesView from './lib/components/ServicesView.svelte';
  import TweaksView from './lib/components/TweaksView.svelte';
  import RepairView from './lib/components/RepairView.svelte';
  import LogConsole from './lib/components/LogConsole.svelte';
  import {
    executeModeAction,
    fetchSystemStatus,
    fetchTuningConfig,
    saveTuningConfig,
    setNativeWindowTheme,
  } from './lib/api';
  import type {
    HardwareInfo,
    LogEntry,
    ModeState,
    OptimizationProfile,
    ThemeMode,
    TuningConfig,
  } from './lib/types';

  type TabId = 'dashboard' | 'services' | 'tweaks' | 'repair';

  let currentTab = $state<TabId>('dashboard');
  let mode = $state<ModeState>('Normal');
  let profile = $state<OptimizationProfile>('competitive');
  let theme = $state<ThemeMode>('dark');
  let isLogOpen = $state(false);

  let hardware = $state<HardwareInfo>({
    cpu: 'Определение процессора...',
    gpu: 'Определение видеокарты...',
    ram: 'Определение объёма ОЗУ...',
    display: 'Определение дисплея...',
    dpcLatency: 'Проверка планировщика...',
    mpoStatus: 'Проверка конвейера DWM...',
    timerResolution: '1.000 мс',
  });

  let logs = $state<LogEntry[]>([
    {
      id: '1',
      timestamp: new Date().toLocaleTimeString(),
      level: 'info',
      message: 'Интерфейс управления Ultra Gaming Mode готов к работе.',
    },
  ]);

  function addLog(level: LogEntry['level'], message: string) {
    logs.push({
      id: `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
      timestamp: new Date().toLocaleTimeString(),
      level,
      message,
    });
  }

  function applyTheme(nextTheme: ThemeMode) {
    theme = nextTheme;
    if (typeof document !== 'undefined') {
      document.documentElement.setAttribute('data-theme', nextTheme);
    }
    try {
      localStorage.setItem('ugm-theme', nextTheme);
    } catch {}
    setNativeWindowTheme(nextTheme === 'dark');
  }

  function handleToggleTheme() {
    const next: ThemeMode = theme === 'dark' ? 'light' : 'dark';
    applyTheme(next);
  }

  async function refreshStatus(preserveCustomProfile = true): Promise<ModeState> {
    const status = await fetchSystemStatus();
    mode = status.mode;
    if (!preserveCustomProfile || profile !== 'custom') {
      profile = status.profile;
    }
    hardware = status.hardware;
    return status.mode;
  }

  onMount(async () => {
    let savedTheme: ThemeMode = 'dark';
    try {
      const stored = localStorage.getItem('ugm-theme');
      if (stored === 'light' || stored === 'dark') {
        savedTheme = stored;
      }
    } catch {}
    applyTheme(savedTheme);

    try {
      await refreshStatus(false);
      addLog(
        'info',
        `Статус системы синхронизирован: ${
          mode === 'Gaming'
            ? 'Игровой режим'
            : mode === 'Armed'
              ? 'Активен в сессии (ожидает перезагрузки)'
              : 'Штатный режим'
        }.`
      );
    } catch (e: any) {
      addLog('error', `Не удалось получить статус системы: ${e?.message || e}`);
    }
  });

  async function handleToggleMode() {
    const nextAction = mode === 'Gaming' || mode === 'Armed' ? 'Restore' : 'Enable';
    const prevMode = mode;
    mode = 'Transitioning';
    addLog(
      'info',
      nextAction === 'Enable'
        ? `Включение игрового режима (профиль: ${profile})...`
        : 'Восстановление штатного режима Windows...'
    );

    try {
      const res = await executeModeAction(nextAction, profile);
      const latestMode = await refreshStatus(true);
      if (res.success) {
        if (nextAction === 'Enable' && latestMode === 'Normal') {
          mode = 'Armed';
        }
        addLog(
          'success',
          res.message ||
            (nextAction === 'Enable'
              ? 'Оптимизации сессии применены, триггер следующей загрузки подготовлен.'
              : 'Штатный режим Windows восстановлен.')
        );
      } else {
        mode = prevMode;
        addLog('error', `Операция завершилась с ошибкой: ${res.message}`);
      }
    } catch (e: any) {
      mode = prevMode;
      addLog('error', `Ошибка вызова PowerShell: ${e?.message || e}`);
    }
  }

  async function handleSelectProfile(newProfile: OptimizationProfile) {
    profile = newProfile;
    if (newProfile === 'competitive' || newProfile === 'aaa') {
      try {
        const current = await fetchTuningConfig();
        const updated: TuningConfig =
          newProfile === 'competitive'
            ? {
                ...current,
                DisableFullscreenOptimizations: true,
                DisableMouseAccel: false,
                EnableNetAdapterMsi: true,
                InputBufferQueueSize: 100,
              }
            : {
                ...current,
                DisableFullscreenOptimizations: false,
                DisableMouseAccel: false,
                EnableNetAdapterMsi: true,
                InputBufferQueueSize: 100,
              };
        await saveTuningConfig(updated);
      } catch {}
    }
    const label =
      newProfile === 'competitive'
        ? 'Киберспорт'
        : newProfile === 'aaa'
          ? 'AAA и стриминг'
          : 'Пользовательский';
    addLog('info', `Выбран профиль оптимизации: ${label}.`);
  }

  function handleCustomConfigChange(cfg: TuningConfig) {
    if (
      cfg.DisableFullscreenOptimizations &&
      !cfg.DisableMouseAccel &&
      cfg.EnableNetAdapterMsi &&
      cfg.InputBufferQueueSize === 100
    ) {
      profile = 'competitive';
    } else if (
      !cfg.DisableFullscreenOptimizations &&
      !cfg.DisableMouseAccel &&
      cfg.EnableNetAdapterMsi &&
      cfg.InputBufferQueueSize === 100
    ) {
      profile = 'aaa';
    } else {
      profile = 'custom';
    }
  }
</script>

<div
  class="min-h-screen flex flex-col font-sans select-none antialiased border transition-colors"
  style="background-color: var(--bg-app); color: var(--text-primary); border-color: var(--border-subtle);"
>
  <TitleBar title="Ultra Gaming Mode" {theme} onToggleTheme={handleToggleTheme} />

  <main class="flex-1 max-w-5xl w-full mx-auto px-6 pt-14 pb-4 flex flex-col space-y-4">
    <!-- Navigation Header -->
    <header
      class="flex flex-wrap items-center justify-between gap-3 border-b pb-3"
      style="border-color: var(--border-subtle);"
    >
      <nav
        class="flex items-center gap-1 p-1 rounded-xl border"
        style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
      >
        <button
          type="button"
          onclick={() => (currentTab = 'dashboard')}
          class="flex items-center gap-2 px-3.5 py-1.5 rounded-lg text-xs font-semibold transition-colors cursor-pointer"
          style="
            background-color: {currentTab === 'dashboard' ? 'var(--bg-elevated)' : 'transparent'};
            color: {currentTab === 'dashboard' ? 'var(--text-primary)' : 'var(--text-secondary)'};
          "
        >
          <LayoutDashboard
            class="w-3.5 h-3.5"
            style="color: {currentTab === 'dashboard' ? 'var(--accent-primary)' : 'var(--text-muted)'};"
          />
          <span>Панель управления</span>
        </button>

        <button
          type="button"
          onclick={() => (currentTab = 'services')}
          class="flex items-center gap-2 px-3.5 py-1.5 rounded-lg text-xs font-semibold transition-colors cursor-pointer"
          style="
            background-color: {currentTab === 'services' ? 'var(--bg-elevated)' : 'transparent'};
            color: {currentTab === 'services' ? 'var(--text-primary)' : 'var(--text-secondary)'};
          "
        >
          <Layers
            class="w-3.5 h-3.5"
            style="color: {currentTab === 'services' ? 'var(--accent-primary)' : 'var(--text-muted)'};"
          />
          <span>Службы (207)</span>
        </button>

        <button
          type="button"
          onclick={() => (currentTab = 'tweaks')}
          class="flex items-center gap-2 px-3.5 py-1.5 rounded-lg text-xs font-semibold transition-colors cursor-pointer"
          style="
            background-color: {currentTab === 'tweaks' ? 'var(--bg-elevated)' : 'transparent'};
            color: {currentTab === 'tweaks' ? 'var(--text-primary)' : 'var(--text-secondary)'};
          "
        >
          <Sliders
            class="w-3.5 h-3.5"
            style="color: {currentTab === 'tweaks' ? 'var(--accent-primary)' : 'var(--text-muted)'};"
          />
          <span>Настройки</span>
        </button>

        <button
          type="button"
          onclick={() => (currentTab = 'repair')}
          class="flex items-center gap-2 px-3.5 py-1.5 rounded-lg text-xs font-semibold transition-colors cursor-pointer"
          style="
            background-color: {currentTab === 'repair' ? 'var(--bg-elevated)' : 'transparent'};
            color: {currentTab === 'repair' ? 'var(--text-primary)' : 'var(--text-secondary)'};
          "
        >
          <Wrench
            class="w-3.5 h-3.5"
            style="color: {currentTab === 'repair' ? 'var(--warn-primary)' : 'var(--text-muted)'};"
          />
          <span>Обслуживание</span>
        </button>
      </nav>

      <!-- Current Status Pill -->
      <div
        class="flex items-center gap-2 px-3 py-1.5 rounded-xl border text-xs"
        style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
      >
        <span
          class="w-2 h-2 rounded-full"
          style="background-color: {mode === 'Gaming'
            ? 'var(--active-primary)'
            : mode === 'Armed'
              ? 'var(--warn-primary)'
              : 'var(--text-muted)'};"
        ></span>
        <span style="color: var(--text-secondary);">Режим:</span>
        <span class="font-semibold" style="color: var(--text-primary);">
          {mode === 'Gaming'
            ? 'Игровой'
            : mode === 'Armed'
              ? 'Ожидает перезагрузки'
              : 'Штатный'}
        </span>
      </div>
    </header>

    <!-- Main View Content -->
    <div class="flex-1">
      {#if currentTab === 'dashboard'}
        <DashboardView
          {mode}
          {profile}
          {hardware}
          onToggleMode={handleToggleMode}
          onSelectProfile={handleSelectProfile}
          onHardwareRefresh={(hw) => (hardware = hw)}
          onLog={addLog}
        />
      {:else if currentTab === 'services'}
        <ServicesView />
      {:else if currentTab === 'tweaks'}
        <TweaksView onLog={addLog} onConfigChange={handleCustomConfigChange} />
      {:else if currentTab === 'repair'}
        <RepairView onLog={addLog} />
      {/if}
    </div>

    <!-- Collapsible Event Log & Footer -->
    <footer class="pt-2">
      <LogConsole
        {logs}
        isOpen={isLogOpen}
        onToggle={() => (isLogOpen = !isLogOpen)}
        onClear={() => (logs = [])}
      />
      <div
        class="flex items-center justify-between text-[11px] pt-2 px-1"
        style="color: var(--text-muted);"
      >
        <span>Ultra Gaming Mode v3.1.1 · Обратимая оптимизация с резервным снимком состояния</span>
        <span>Тема: {theme === 'dark' ? 'Тёмная' : 'Светлая'}</span>
      </div>
    </footer>
  </main>
</div>
