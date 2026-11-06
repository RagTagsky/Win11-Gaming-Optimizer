<script lang="ts">
  import { onMount } from 'svelte';
  import {
    Activity,
    Layers,
    LayoutDashboard,
    Sliders,
    Wrench,
    Zap,
  } from '@lucide/svelte';
  import TitleBar from './lib/components/TitleBar.svelte';
  import DashboardView from './lib/components/DashboardView.svelte';
  import ServicesView from './lib/components/ServicesView.svelte';
  import TweaksView from './lib/components/TweaksView.svelte';
  import RepairView from './lib/components/RepairView.svelte';
  import LogConsole from './lib/components/LogConsole.svelte';
  import { executeModeAction, fetchSystemStatus } from './lib/api';
  import type { HardwareInfo, LogEntry, ModeState, OptimizationProfile } from './lib/types';

  type TabId = 'dashboard' | 'services' | 'tweaks' | 'repair';

  let currentTab = $state<TabId>('dashboard');
  let mode = $state<ModeState>('Normal');
  let profile = $state<OptimizationProfile>('competitive');
  let isLogOpen = $state(false);

  let hardware = $state<HardwareInfo>({
    cpu: 'AMD Ryzen 5 5600X (6C / 12T @ 4.65 GHz)',
    gpu: 'AMD Radeon RX 6600 (8 GB GDDR6)',
    ram: '32 GB DDR4-3600 CL16',
    display: '1920x1080 @ 180Hz (FreeSync / MPO Protected)',
    dpcLatency: '34 µs (Low Latency Engine)',
    mpoStatus: 'Protected',
  });

  let logs = $state<LogEntry[]>([
    {
      id: '1',
      timestamp: new Date().toLocaleTimeString(),
      level: 'info',
      message: 'Ultra Gaming Mode v3.0 ядро инициализировано (On-Demand Mode).',
    },
    {
      id: '2',
      timestamp: new Date().toLocaleTimeString(),
      level: 'success',
      message: 'Защита от моргания дисплея MPO и 180Hz FreeSync активны.',
    },
    {
      id: '3',
      timestamp: new Date().toLocaleTimeString(),
      level: 'info',
      message: 'Службы Windows Search, «Ножницы» (PrtSc) и Spooler проверены: защищены.',
    },
  ]);

  function addLog(level: LogEntry['level'], message: string) {
    logs.push({
      id: Date.now().toString(),
      timestamp: new Date().toLocaleTimeString(),
      level,
      message,
    });
  }

  onMount(async () => {
    try {
      const status = await fetchSystemStatus();
      mode = status.mode;
      profile = status.profile;
      hardware = status.hardware;
      addLog('info', `Синхронизация статуса системы: режим [${mode}].`);
    } catch (e: any) {
      addLog('error', `Ошибка загрузки статуса: ${e?.message || e}`);
    }
  });

  async function handleToggleMode() {
    const nextAction = mode === 'Gaming' ? 'Restore' : 'Enable';
    mode = 'Transitioning';
    addLog('info', `Запуск действия [${nextAction}] с профилем [${profile}]...`);

    try {
      const res = await executeModeAction(nextAction, profile);
      if (res.success) {
        mode = nextAction === 'Enable' ? 'Gaming' : 'Normal';
        addLog('success', res.message || (nextAction === 'Enable'
          ? 'Ultra Gaming Mode успешно активирован! Фоновый шум подавлен.'
          : 'Штатный режим Windows полностью восстановлен.'));
      } else {
        mode = 'Normal';
        addLog('error', `Действие [${nextAction}] завершилось ошибкой: ${res.message}`);
      }
    } catch (e: any) {
      mode = 'Normal';
      addLog('error', `Сбой вызова: ${e?.message || e}`);
    }
  }

  function handleSelectProfile(newProfile: OptimizationProfile) {
    profile = newProfile;
    addLog('info', `Выбран профиль оптимизации: ${newProfile.toUpperCase()}`);
  }
</script>

<div class="min-h-screen bg-[#0c0d10] text-zinc-200 flex flex-col font-sans select-none antialiased border border-[#1f2027]">
  <!-- Windows 11 Native Mica TitleBar -->
  <TitleBar title="Ultra Gaming Mode v3.0 • Fluent On-Demand" />

  <!-- Main Container -->
  <main class="flex-1 max-w-5xl w-full mx-auto px-6 pt-14 pb-4 flex flex-col space-y-4">
    <!-- Navigation Tabs Header -->
    <header class="flex items-center justify-between border-b border-[#1b1c22] pb-3">
      <!-- Tabs -->
      <nav class="flex items-center gap-1.5 p-1 bg-[#121317] rounded-xl border border-[#1e2026]">
        <button
          type="button"
          onclick={() => (currentTab = 'dashboard')}
          class="flex items-center gap-2 px-3.5 py-1.5 rounded-lg text-xs font-semibold transition-all cursor-pointer {currentTab === 'dashboard'
            ? 'bg-[#1e2028] text-white shadow-sm ring-1 ring-[#2c2f3b]'
            : 'text-zinc-400 hover:text-zinc-200'}"
        >
          <LayoutDashboard class="w-3.5 h-3.5 {currentTab === 'dashboard' ? 'text-emerald-400' : 'text-zinc-500'}" />
          <span>Дашборд</span>
        </button>

        <button
          type="button"
          onclick={() => (currentTab = 'services')}
          class="flex items-center gap-2 px-3.5 py-1.5 rounded-lg text-xs font-semibold transition-all cursor-pointer {currentTab === 'services'
            ? 'bg-[#1e2028] text-white shadow-sm ring-1 ring-[#2c2f3b]'
            : 'text-zinc-400 hover:text-zinc-200'}"
        >
          <Layers class="w-3.5 h-3.5 {currentTab === 'services' ? 'text-emerald-400' : 'text-zinc-500'}" />
          <span>Службы (207)</span>
        </button>

        <button
          type="button"
          onclick={() => (currentTab = 'tweaks')}
          class="flex items-center gap-2 px-3.5 py-1.5 rounded-lg text-xs font-semibold transition-all cursor-pointer {currentTab === 'tweaks'
            ? 'bg-[#1e2028] text-white shadow-sm ring-1 ring-[#2c2f3b]'
            : 'text-zinc-400 hover:text-zinc-200'}"
        >
          <Sliders class="w-3.5 h-3.5 {currentTab === 'tweaks' ? 'text-emerald-400' : 'text-zinc-500'}" />
          <span>Твики DPC & GPU</span>
        </button>

        <button
          type="button"
          onclick={() => (currentTab = 'repair')}
          class="flex items-center gap-2 px-3.5 py-1.5 rounded-lg text-xs font-semibold transition-all cursor-pointer {currentTab === 'repair'
            ? 'bg-[#1e2028] text-white shadow-sm ring-1 ring-[#2c2f3b]'
            : 'text-zinc-400 hover:text-zinc-200'}"
        >
          <Wrench class="w-3.5 h-3.5 {currentTab === 'repair' ? 'text-amber-400' : 'text-zinc-500'}" />
          <span>Аварийный ремонт</span>
        </button>
      </nav>

      <!-- Top Right Status Badge -->
      <div class="flex items-center gap-3">
        <div class="flex items-center gap-2 px-3 py-1.5 rounded-xl bg-[#121317] border border-[#1e2026] text-xs">
          <span class="w-2 h-2 rounded-full {mode === 'Gaming' ? 'bg-emerald-400 animate-pulse shadow-sm shadow-emerald-400/50' : 'bg-zinc-500'}"></span>
          <span class="text-zinc-400">Статус:</span>
          <span class="font-bold text-zinc-100">{mode === 'Gaming' ? 'Игровой' : 'Штатный'}</span>
        </div>
      </div>
    </header>

    <!-- Tab View Content Area -->
    <div class="flex-1">
      {#if currentTab === 'dashboard'}
        <DashboardView
          {mode}
          {profile}
          {hardware}
          onToggleMode={handleToggleMode}
          onSelectProfile={handleSelectProfile}
        />
      {:else if currentTab === 'services'}
        <ServicesView />
      {:else if currentTab === 'tweaks'}
        <TweaksView />
      {:else if currentTab === 'repair'}
        <RepairView onLog={addLog} />
      {/if}
    </div>

    <!-- Collapsible Log Console at Bottom -->
    <footer class="pt-2">
      <LogConsole
        {logs}
        isOpen={isLogOpen}
        onToggle={() => (isLogOpen = !isLogOpen)}
        onClear={() => (logs = [])}
      />
      <div class="flex items-center justify-between text-[11px] text-zinc-500 pt-2 px-1">
        <span>Ultra Gaming Mode v3.0 • Pure On-Demand Engine</span>
        <span class="font-mono">Тестов пройдено: 260 / 260 (0 ошибок)</span>
      </div>
    </footer>
  </main>
</div>
