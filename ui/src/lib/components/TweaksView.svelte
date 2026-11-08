<script lang="ts">
  import { onMount } from 'svelte';
  import { CheckCircle2, RefreshCw, Sliders } from '@lucide/svelte';
  import { fetchTuningConfig, saveTuningConfig } from '../api';
  import type { LogEntry, TuningConfig } from '../types';

  interface Props {
    onLog?: (level: LogEntry['level'], message: string) => void;
    onConfigChange?: (cfg: TuningConfig) => void;
  }

  let { onLog, onConfigChange }: Props = $props();

  let config = $state<TuningConfig>({
    DisableFullscreenOptimizations: true,
    DisableMouseAccel: false,
    EnableNetAdapterMsi: true,
    InputBufferQueueSize: 100,
  });
  let isSaving = $state(false);
  let savedSuccess = $state(false);

  onMount(async () => {
    try {
      config = await fetchTuningConfig();
    } catch (e: any) {
      onLog?.('error', `Не удалось прочитать Config/tuning.json: ${e?.message || e}`);
    }
  });

  async function persistConfig(updated: TuningConfig, description: string) {
    isSaving = true;
    savedSuccess = false;
    try {
      const saved = await saveTuningConfig(updated);
      config = saved;
      savedSuccess = true;
      onConfigChange?.(saved);
      onLog?.('info', `Настройка сохранена (${description}).`);
      setTimeout(() => (savedSuccess = false), 2000);
    } catch (e: any) {
      onLog?.('error', `Ошибка сохранения tuning.json: ${e?.message || e}`);
    } finally {
      isSaving = false;
    }
  }

  function toggleBooleanKey(
    key: 'DisableFullscreenOptimizations' | 'DisableMouseAccel' | 'EnableNetAdapterMsi',
    label: string
  ) {
    const next: TuningConfig = {
      ...config,
      [key]: !config[key],
    };
    persistConfig(next, `${label}: ${next[key] ? 'вкл.' : 'выкл.'}`);
  }

  function setQueueSize(size: number) {
    const clamped = Math.max(32, size);
    const next: TuningConfig = {
      ...config,
      InputBufferQueueSize: clamped,
    };
    persistConfig(next, `Очередь буфера ввода: ${clamped} пакетов`);
  }

  const automaticModules = [
    {
      title: 'Быстрый путь сокетов Winsock AFD и NDIS RSS',
      detail: 'FastSendDatagramThreshold = 65536, FastCopyReceiveThreshold = 65536, MaxNumRssCpus = 4',
    },
    {
      title: 'Планировщик ядра и отключение телеметрии питания',
      detail: 'Win32PrioritySeparation = 0x26, DisableTaggedEnergyLogging = 1, CoalescingTimerInterval = 0',
    },
    {
      title: 'Консолидация процессов svchost и защита ОЗУ',
      detail: 'SvcHostSplitThresholdInKB = 64 ГБ (на ПК с ≥16 ГБ ОЗУ), отключение сжатия памяти во время игры',
    },
    {
      title: 'Анти-статтер AMD Radeon DXNAVI и защита DWM MPO',
      detail: 'StutterMode = 0, PP_SclkDeepSleepDisable = 1, EnableUlps = 0, SwapEffectUpgradeEnable = 1',
    },
  ];
</script>

<div class="space-y-5">
  <!-- Header Card -->
  <div
    class="flex items-center justify-between p-4 rounded-xl border"
    style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
  >
    <div class="flex items-center gap-3">
      <div
        class="w-9 h-9 rounded-lg flex items-center justify-center border shrink-0"
        style="background-color: var(--bg-elevated); border-color: var(--border-subtle);"
      >
        <Sliders class="w-4 h-4" style="color: var(--accent-primary);" />
      </div>
      <div>
        <p class="text-xs font-semibold" style="color: var(--text-primary);">
          Параметры конфигурации (Config/tuning.json)
        </p>
        <p class="text-[11px]" style="color: var(--text-secondary);">
          Изменения сохраняются напрямую в файл конфигурации и применяются при включении игрового режима.
        </p>
      </div>
    </div>

    <div class="flex items-center gap-2">
      {#if isSaving}
        <span class="inline-flex items-center gap-1.5 text-xs" style="color: var(--text-secondary);">
          <RefreshCw class="w-3.5 h-3.5 animate-spin" />
          Сохранение...
        </span>
      {:else if savedSuccess}
        <span class="inline-flex items-center gap-1.5 text-xs font-medium" style="color: var(--active-primary);">
          <CheckCircle2 class="w-3.5 h-3.5" />
          Сохранено
        </span>
      {/if}
    </div>
  </div>

  <!-- Interactive Tuning Controls -->
  <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
    <!-- 1. DisableFullscreenOptimizations -->
    <div
      class="p-4 rounded-xl border flex flex-col justify-between gap-3"
      style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
    >
      <div class="space-y-1">
        <div class="flex items-center justify-between gap-2">
          <span class="text-xs font-semibold" style="color: var(--text-primary);">
            Отключение оптимизации во весь экран (FSE)
          </span>
          <span
            class="text-[10px] font-medium px-2 py-0.5 rounded border"
            style="background-color: var(--bg-elevated); color: var(--text-secondary); border-color: var(--border-subtle);"
          >
            Дисплей
          </span>
        </div>
        <p class="text-[11px] leading-relaxed" style="color: var(--text-secondary);">
          Переводит игры в классический эксклюзивный полноэкранный режим (GameDVR_FSEBehaviorMode = 2). Для быстрого Alt-Tab с одним монитором рекомендуется отключать.
        </p>
      </div>

      <div
        class="flex items-center justify-between pt-2.5 border-t"
        style="border-color: var(--border-subtle);"
      >
        <span class="text-[11px] font-mono" style="color: var(--text-muted);">
          DisableFullscreenOptimizations
        </span>
        <button
          type="button"
          onclick={() => toggleBooleanKey('DisableFullscreenOptimizations', 'Классический FSE')}
          class="relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-150 focus:outline-none"
          style="background-color: {config.DisableFullscreenOptimizations
            ? 'var(--accent-primary)'
            : 'var(--border-strong)'};"
          role="switch"
          aria-checked={config.DisableFullscreenOptimizations}
          aria-label="Отключение оптимизации во весь экран"
        >
          <span
            class="pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow transition duration-150 {config.DisableFullscreenOptimizations
              ? 'translate-x-4'
              : 'translate-x-0'}"
          ></span>
        </button>
      </div>
    </div>

    <!-- 2. EnableNetAdapterMsi -->
    <div
      class="p-4 rounded-xl border flex flex-col justify-between gap-3"
      style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
    >
      <div class="space-y-1">
        <div class="flex items-center justify-between gap-2">
          <span class="text-xs font-semibold" style="color: var(--text-primary);">
            Режим прерываний MSI для сетевой карты PCIe
          </span>
          <span
            class="text-[10px] font-medium px-2 py-0.5 rounded border"
            style="background-color: var(--active-soft); color: var(--active-primary); border-color: var(--active-border);"
          >
            Рекомендуется
          </span>
        </div>
        <p class="text-[11px] leading-relaxed" style="color: var(--text-secondary);">
          Переводит физический PCIe сетевой адаптер на прерывания, сигнализируемые сообщениями (MSISupported = 1), снижая джиттер DPC в сетевых матчах.
        </p>
      </div>

      <div
        class="flex items-center justify-between pt-2.5 border-t"
        style="border-color: var(--border-subtle);"
      >
        <span class="text-[11px] font-mono" style="color: var(--text-muted);">
          EnableNetAdapterMsi
        </span>
        <button
          type="button"
          onclick={() => toggleBooleanKey('EnableNetAdapterMsi', 'MSI сетевой карты PCIe')}
          class="relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-150 focus:outline-none"
          style="background-color: {config.EnableNetAdapterMsi
            ? 'var(--accent-primary)'
            : 'var(--border-strong)'};"
          role="switch"
          aria-checked={config.EnableNetAdapterMsi}
          aria-label="Режим прерываний MSI для сетевой карты PCIe"
        >
          <span
            class="pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow transition duration-150 {config.EnableNetAdapterMsi
              ? 'translate-x-4'
              : 'translate-x-0'}"
          ></span>
        </button>
      </div>
    </div>

    <!-- 3. DisableMouseAccel -->
    <div
      class="p-4 rounded-xl border flex flex-col justify-between gap-3"
      style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
    >
      <div class="space-y-1">
        <div class="flex items-center justify-between gap-2">
          <span class="text-xs font-semibold" style="color: var(--text-primary);">
            Отключение акселерации указателя мыши Windows
          </span>
          <span
            class="text-[10px] font-medium px-2 py-0.5 rounded border"
            style="background-color: var(--bg-elevated); color: var(--text-secondary); border-color: var(--border-subtle);"
          >
            Ввод
          </span>
        </div>
        <p class="text-[11px] leading-relaxed" style="color: var(--text-secondary);">
          Устанавливает линейную кривую MouseSpeed = 0, MouseThreshold1 = 0, MouseThreshold2 = 0 для точного перемещения курсора 1:1 без сглаживания ОС.
        </p>
      </div>

      <div
        class="flex items-center justify-between pt-2.5 border-t"
        style="border-color: var(--border-subtle);"
      >
        <span class="text-[11px] font-mono" style="color: var(--text-muted);">
          DisableMouseAccel
        </span>
        <button
          type="button"
          onclick={() => toggleBooleanKey('DisableMouseAccel', 'Отключение акселерации мыши')}
          class="relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-150 focus:outline-none"
          style="background-color: {config.DisableMouseAccel
            ? 'var(--accent-primary)'
            : 'var(--border-strong)'};"
          role="switch"
          aria-checked={config.DisableMouseAccel}
          aria-label="Отключение акселерации указателя мыши Windows"
        >
          <span
            class="pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow transition duration-150 {config.DisableMouseAccel
              ? 'translate-x-4'
              : 'translate-x-0'}"
          ></span>
        </button>
      </div>
    </div>

    <!-- 4. InputBufferQueueSize -->
    <div
      class="p-4 rounded-xl border flex flex-col justify-between gap-3"
      style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
    >
      <div class="space-y-1">
        <div class="flex items-center justify-between gap-2">
          <span class="text-xs font-semibold" style="color: var(--text-primary);">
            Размер очереди буфера ввода (mouclass / kbdclass)
          </span>
          <span
            class="text-[10px] font-medium px-2 py-0.5 rounded border"
            style="background-color: var(--bg-elevated); color: var(--text-secondary); border-color: var(--border-subtle);"
          >
            Минимум 32
          </span>
        </div>
        <p class="text-[11px] leading-relaxed" style="color: var(--text-secondary);">
          Задаёт MouseDataQueueSize и KeyboardDataQueueSize. Защитный порог ≥ 32 предотвращает потерю пакетов на мышах с частотой опроса 1000–8000 Гц.
        </p>
      </div>

      <div
        class="flex items-center justify-between pt-2.5 border-t"
        style="border-color: var(--border-subtle);"
      >
        <span class="text-[11px] font-mono" style="color: var(--text-muted);">
          InputBufferQueueSize
        </span>
        <div class="flex items-center gap-1.5">
          {#each [64, 100, 150, 200] as qSize}
            <button
              type="button"
              onclick={() => setQueueSize(qSize)}
              class="px-2.5 py-1 rounded text-xs font-medium border transition-colors cursor-pointer"
              style="
                background-color: {config.InputBufferQueueSize === qSize
                ? 'var(--accent-primary)'
                : 'var(--bg-elevated)'};
                border-color: {config.InputBufferQueueSize === qSize
                ? 'var(--accent-primary)'
                : 'var(--border-subtle)'};
                color: {config.InputBufferQueueSize === qSize ? '#ffffff' : 'var(--text-primary)'};
              "
            >
              {qSize}
            </button>
          {/each}
        </div>
      </div>
    </div>
  </div>

  <!-- Built-in Kernel & System Modules Summary -->
  <div
    class="p-4 rounded-xl border space-y-3"
    style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
  >
    <div class="flex items-center justify-between">
      <span class="text-xs font-semibold" style="color: var(--text-primary);">
        Встроенные модули оптимизации ядра (применяются автоматически с полным откатом)
      </span>
      <span class="text-[11px]" style="color: var(--text-muted);">
        79 параметров реестра и питания
      </span>
    </div>

    <div class="grid grid-cols-1 md:grid-cols-2 gap-2.5">
      {#each automaticModules as mod}
        <div
          class="p-3 rounded-lg border space-y-1"
          style="background-color: var(--bg-elevated); border-color: var(--border-subtle);"
        >
          <p class="text-xs font-medium" style="color: var(--text-primary);">{mod.title}</p>
          <p class="text-[11px] font-mono" style="color: var(--text-secondary);">{mod.detail}</p>
        </div>
      {/each}
    </div>
  </div>
</div>
