<script lang="ts">
  import {
    AlertCircle,
    AlertTriangle,
    Check,
    Cpu,
    Gamepad2,
    Keyboard,
    Loader2,
    Monitor,
    Mouse,
    Network,
    Power,
    RefreshCw,
    SlidersHorizontal,
    Timer
  } from '@lucide/svelte';
  import type { AutostartStatus, ModeState, TuningConfig } from '../types';

  interface Props {
    config: TuningConfig | null;
    isLoading: boolean;
    isSaving: boolean;
    loadError: string | null;
    mode: ModeState;
    autostartStatus: AutostartStatus | null;
    isAutostartLoading: boolean;
    isAutostartSaving: boolean;
    autostartError: string | null;
    onUpdateConfig: (next: TuningConfig) => Promise<boolean>;
    onRetryLoad: () => void;
    onSetAutostart: (enabled: boolean, startInTray: boolean) => Promise<void> | void;
    onRefreshAutostart: () => void;
  }

  let {
    config,
    isLoading,
    isSaving,
    loadError,
    mode,
    autostartStatus,
    isAutostartLoading,
    isAutostartSaving,
    autostartError,
    onUpdateConfig,
    onRetryLoad,
    onSetAutostart,
    onRefreshAutostart
  }: Props = $props();

  type BooleanTuningKey =
    | 'DisableFullscreenOptimizations'
    | 'EnableNetAdapterMsi'
    | 'DisableMouseAccel'
    | 'DisableNvidiaDynamicPstate'
    | 'AutoLockTimerInGaming';

  const PRESETS: Array<{ value: number; hint: string }> = [
    { value: 64, hint: 'Минимум' },
    { value: 100, hint: 'Стандарт' },
    { value: 150, hint: 'Запас' },
    { value: 200, hint: 'Максимум' }
  ];

  const TWEAK_ITEMS: Array<{
    key: BooleanTuningKey;
    title: string;
    description: string;
    technicalKey: string;
  }> = [
    {
      key: 'DisableFullscreenOptimizations',
      title: 'Классический полноэкранный режим (FSE)',
      description:
        'Отключает промежуточную композицию DWM для снижения задержки вывода кадра в играх.',
      technicalKey: 'DisableFullscreenOptimizations · GameDVR_FSEBehavior'
    },
    {
      key: 'EnableNetAdapterMsi',
      title: 'Прерывания MSI для сетевой карты',
      description:
        'Переводит сетевой контроллер на прямую доставку прерываний PCIe без общих очередей IRQ.',
      technicalKey: 'EnableNetAdapterMsi · MSISupported = 1'
    },
    {
      key: 'DisableMouseAccel',
      title: 'Точная мышь 1:1 (без акселерации)',
      description:
        'Фиксирует линейную кривую отклика курсора Windows для предсказуемого наведения.',
      technicalKey: 'DisableMouseAccel · MouseSpeed = 0, SmoothMouseCurve'
    },
    {
      key: 'DisableNvidiaDynamicPstate',
      title: 'Фиксация максимальной частоты GPU NVIDIA',
      description:
        'Удерживает производительное P-состояние видеочипа, исключая просадки из-за сброса частот.',
      technicalKey: 'DisableNvidiaDynamicPstate · DisableDynamicPstate'
    }
  ];

  let bufferDraft = $state('100');
  let bufferError = $state<string | null>(null);
  let lastSyncedQueue: number | null = null;
  let bufferInputEl = $state<HTMLInputElement | null>(null);
  let preferredStartInTray = $state(true);

  const isLiveMode = $derived(mode === 'Gaming' || mode === 'Armed');

  $effect(() => {
    if (autostartStatus?.taskExists) {
      preferredStartInTray = autostartStatus.startInTray;
    }
  });

  $effect(() => {
    if (!config) return;
    if (config.InputBufferQueueSize !== lastSyncedQueue) {
      lastSyncedQueue = config.InputBufferQueueSize;
      bufferDraft = String(config.InputBufferQueueSize);
      bufferError = null;
    }
  });

  async function selectAutostartMode(startInTray: boolean) {
    preferredStartInTray = startInTray;
    if (autostartStatus?.enabled && !isAutostartSaving) {
      await onSetAutostart(true, startInTray);
    }
  }

  async function toggleBooleanSetting(key: BooleanTuningKey) {
    if (!config || isSaving) return;
    const next: TuningConfig = {
      ...config,
      [key]: !config[key]
    };
    await onUpdateConfig(next);
  }

  async function selectQueuePreset(value: number) {
    if (!config || isSaving) return;
    bufferError = null;
    bufferDraft = String(value);
    const saved = await onUpdateConfig({
      ...config,
      InputBufferQueueSize: value
    });
    if (saved) {
      lastSyncedQueue = value;
      bufferDraft = String(value);
    } else {
      bufferDraft = String(config.InputBufferQueueSize);
    }
  }

  function validateBufferValue(raw: string): { value: number | null; error: string | null } {
    const trimmed = raw.trim();
    if (!trimmed) {
      return { value: null, error: 'Укажите размер очереди (целое число от 32 до 1024).' };
    }
    if (!/^\d+$/.test(trimmed)) {
      return { value: null, error: 'Допустимо только целое положительное число без дробной части.' };
    }
    const parsed = Number.parseInt(trimmed, 10);
    if (!Number.isSafeInteger(parsed) || parsed < 32 || parsed > 1024) {
      return {
        value: null,
        error: 'Защитный диапазон — от 32 до 1024 пакетов (ниже 32 возможна потеря событий мыши).'
      };
    }
    return { value: parsed, error: null };
  }

  async function handleBufferSubmit(e: SubmitEvent) {
    e.preventDefault();
    if (!config || isSaving) return;

    const { value, error } = validateBufferValue(bufferDraft);
    if (error || value === null) {
      bufferError = error;
      bufferInputEl?.focus();
      return;
    }

    bufferError = null;
    const saved = await onUpdateConfig({
      ...config,
      InputBufferQueueSize: value
    });
    if (saved) {
      lastSyncedQueue = value;
      bufferDraft = String(value);
    } else {
      bufferDraft = String(config.InputBufferQueueSize);
    }
  }
</script>

<div class="space-y-4">
  <!-- Header Card -->
  <section class="ui-card rounded-2xl p-5 space-y-2">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div class="space-y-1">
        <h1 class="text-base font-semibold text-[var(--text-primary)]">
          Параметры задержки и отклика системы
        </h1>
        <p class="text-sm text-[var(--text-secondary)]">
          Все изменения сохраняются в <code translate="no" class="font-mono text-xs px-1.5 py-0.5 rounded bg-[var(--bg-elevated)] select-text">Config/tuning.json</code>
          {isLiveMode
            ? 'и сразу применяются к активной игровой сессии.'
            : 'и применяются автоматически при следующем включении игрового режима.'}
        </p>
      </div>

      {#if isSaving}
        <span
          class="inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold bg-[var(--accent-soft)] text-[var(--accent-text)] border border-[var(--accent-border)]"
          role="status"
        >
          <Loader2 size={13} strokeWidth={2} class="ui-spin" aria-hidden="true" />
          <span>Сохраняю…</span>
        </span>
      {/if}
    </div>
  </section>

  {#if isLoading && !config}
    <div
      class="ui-card rounded-2xl p-8 flex items-center justify-center gap-3 text-sm text-[var(--text-secondary)]"
      role="status"
    >
      <Loader2 size={18} strokeWidth={2} class="ui-spin text-[var(--accent-text)]" aria-hidden="true" />
      <span>Загружаю параметры конфигурации…</span>
    </div>
  {:else if loadError && !config}
    <div
      class="ui-card rounded-2xl p-6 border border-[var(--status-danger-border)] bg-[var(--status-danger-soft)] flex flex-col sm:flex-row sm:items-center justify-between gap-4"
      role="alert"
    >
      <div class="flex items-start gap-3 min-w-0">
        <AlertCircle size={20} strokeWidth={1.75} class="text-[var(--status-danger-text)] shrink-0 mt-0.5" aria-hidden="true" />
        <div class="space-y-1 min-w-0">
          <p class="text-sm font-semibold text-[var(--status-danger-text)]">
            Не удалось загрузить файл конфигурации
          </p>
          <p class="text-sm text-[var(--text-secondary)] break-words">
            {loadError}
          </p>
        </div>
      </div>

      <button
        type="button"
        onclick={onRetryLoad}
        class="ui-btn-secondary ui-pressable rounded-lg px-4 py-2 min-h-9 text-[0.8125rem] font-medium flex items-center gap-1.5 shrink-0 cursor-pointer"
      >
        <RefreshCw size={14} strokeWidth={1.75} aria-hidden="true" />
        <span>Повторить</span>
      </button>
    </div>
  {:else if config}
    <!-- Autostart & Background Mode Card -->
    <section
      aria-labelledby="autostart-heading"
      class="ui-card rounded-2xl divide-y divide-[var(--border-subtle)] overflow-hidden"
    >
      <div class="px-5 py-3.5 bg-[var(--bg-elevated)] flex items-center justify-between gap-2">
        <div class="flex items-center gap-2">
          <Power size={16} strokeWidth={1.75} class="text-[var(--accent-text)]" aria-hidden="true" />
          <h2 id="autostart-heading" class="text-sm font-semibold text-[var(--text-primary)]">
            Запуск и фоновый режим
          </h2>
        </div>

        <button
          type="button"
          onclick={onRefreshAutostart}
          disabled={isAutostartLoading || isAutostartSaving}
          aria-label="Обновить статус автозапуска"
          class="ui-btn-ghost ui-pressable rounded-lg px-2.5 py-1 text-xs font-medium inline-flex items-center gap-1.5 disabled:opacity-50 cursor-pointer"
        >
          <RefreshCw
            size={13}
            strokeWidth={1.75}
            class={isAutostartLoading ? 'ui-spin' : ''}
            aria-hidden="true"
          />
          <span>Проверить</span>
        </button>
      </div>

      <div class="p-5 space-y-4">
        <div class="flex items-start justify-between gap-4">
          <div class="space-y-1 min-w-0">
            <div id="autostart-switch-title" class="text-sm font-semibold text-[var(--text-primary)]">
              Запускать вместе с Windows
            </div>
            <p id="autostart-switch-desc" class="text-sm leading-relaxed text-[var(--text-secondary)]">
              Регистрирует задачу Планировщика Windows с повышенными правами без лишних запросов UAC при входе в систему.
            </p>
            {#if autostartStatus?.taskExists && autostartStatus.registeredCommand}
              <p translate="no" class="font-mono text-xs text-[var(--text-muted)] break-all select-text">
                {autostartStatus.registeredCommand}
              </p>
            {/if}
          </div>

          <div class="flex items-center gap-2.5 shrink-0 pt-1">
            {#if isAutostartSaving}
              <Loader2 size={14} strokeWidth={2} class="ui-spin text-[var(--accent-text)]" aria-hidden="true" />
            {/if}
            <span class="hidden sm:inline text-xs font-medium text-[var(--text-muted)] min-w-10 text-right">
              {autostartStatus?.enabled ? 'Вкл' : 'Выкл'}
            </span>
            <button
              type="button"
              role="switch"
              aria-checked={Boolean(autostartStatus?.enabled)}
              aria-labelledby="autostart-switch-title"
              aria-describedby="autostart-switch-desc"
              disabled={isAutostartLoading || isAutostartSaving || (autostartStatus !== null && !autostartStatus.isAdminSession && !autostartStatus.enabled)}
              onclick={() =>
                onSetAutostart(
                  !(autostartStatus?.enabled ?? false),
                  autostartStatus?.taskExists ? autostartStatus.startInTray : preferredStartInTray
                )}
              class="ui-switch relative inline-flex items-center w-11 h-6 rounded-full shrink-0 disabled:opacity-55 disabled:cursor-not-allowed cursor-pointer"
            >
              <span
                class="ui-switch-thumb pointer-events-none block w-4 h-4 rounded-full {autostartStatus?.enabled
                  ? 'translate-x-[22px]'
                  : 'translate-x-[3px]'}"
              ></span>
            </button>
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-2" role="group" aria-label="Режим окна при автозапуске">
          <span class="text-xs font-medium text-[var(--text-muted)] mr-1">При входе в Windows:</span>
          <button
            type="button"
            disabled={isAutostartLoading || isAutostartSaving}
            aria-pressed={preferredStartInTray}
            onclick={() => selectAutostartMode(true)}
            class="{preferredStartInTray
              ? 'bg-[var(--accent-soft)] text-[var(--accent-text)] border-[var(--accent-border)]'
              : 'bg-[var(--bg-elevated)] text-[var(--text-secondary)] border-[var(--border-input)] hover:bg-[var(--bg-hover)]'} ui-pressable rounded-lg border px-3 py-1.5 min-h-8 text-[0.8125rem] font-medium disabled:opacity-50 cursor-pointer"
          >
            Сразу в трей (0 МБ ОЗУ)
          </button>
          <button
            type="button"
            disabled={isAutostartLoading || isAutostartSaving}
            aria-pressed={!preferredStartInTray}
            onclick={() => selectAutostartMode(false)}
            class="{!preferredStartInTray
              ? 'bg-[var(--accent-soft)] text-[var(--accent-text)] border-[var(--accent-border)]'
              : 'bg-[var(--bg-elevated)] text-[var(--text-secondary)] border-[var(--border-input)] hover:bg-[var(--bg-hover)]'} ui-pressable rounded-lg border px-3 py-1.5 min-h-8 text-[0.8125rem] font-medium disabled:opacity-50 cursor-pointer"
          >
            Открывать окно
          </button>
        </div>

        {#if autostartStatus?.taskExists && !autostartStatus.pathMatches}
          <div
            role="status"
            class="rounded-xl p-3.5 bg-[var(--status-warn-soft)] border border-[var(--status-warn-border)] flex flex-col sm:flex-row sm:items-center justify-between gap-3"
          >
            <div class="flex items-start gap-2.5 min-w-0">
              <AlertTriangle size={17} strokeWidth={1.85} class="text-[var(--status-warn-text)] shrink-0 mt-0.5" aria-hidden="true" />
              <div class="space-y-0.5 text-[0.8125rem] min-w-0">
                <p class="font-semibold text-[var(--status-warn-text)]">
                  Путь в задаче автозапуска устарел
                </p>
                <p class="text-[var(--text-secondary)] break-all">
                  Обнаружено расхождение с текущим <code translate="no" class="font-mono text-xs">{autostartStatus.currentExePath}</code>.
                </p>
              </div>
            </div>

            <button
              type="button"
              disabled={isAutostartSaving || !autostartStatus.isAdminSession}
              onclick={() => onSetAutostart(autostartStatus.enabled, preferredStartInTray)}
              class="ui-btn-warn ui-pressable rounded-lg px-3.5 py-2 min-h-9 text-xs font-semibold shrink-0 disabled:opacity-55 cursor-pointer"
            >
              Исправить путь
            </button>
          </div>
        {/if}

        {#if autostartError || (autostartStatus?.warning && !(autostartStatus.taskExists && !autostartStatus.pathMatches))}
          <div
            role="status"
            class="rounded-xl p-3 bg-[var(--status-warn-soft)] border border-[var(--status-warn-border)] text-[0.8125rem] text-[var(--status-warn-text)] flex items-start gap-2"
          >
            <AlertTriangle size={16} strokeWidth={1.85} class="shrink-0 mt-0.5" aria-hidden="true" />
            <span>{autostartError ?? autostartStatus?.warning}</span>
          </div>
        {/if}
      </div>

      <div class="p-5 flex items-start justify-between gap-4">
        <div class="flex items-start gap-3.5 min-w-0">
          <div
            class="w-9 h-9 rounded-xl flex items-center justify-center shrink-0 mt-0.5 {config.AutoLockTimerInGaming
              ? 'bg-[var(--accent-soft)] text-[var(--accent-text)]'
              : 'bg-[var(--bg-elevated)] text-[var(--text-muted)]'}"
          >
            <Timer size={18} strokeWidth={1.75} aria-hidden="true" />
          </div>

          <div class="min-w-0 space-y-1">
            <div id="tweak-title-AutoLockTimerInGaming" class="text-sm font-semibold text-[var(--text-primary)]">
              Автоматически фиксировать таймер 0.5 мс в игровом режиме
            </div>
            <p id="tweak-desc-AutoLockTimerInGaming" class="text-sm leading-relaxed text-[var(--text-secondary)]">
              При входе в систему в активном игровом режиме автоматически удерживает системный таймер 0.500 мс и снимает удержание при возврате к штатному режиму.
            </p>
            <p translate="no" class="font-mono text-xs text-[var(--text-muted)] select-text pt-0.5">
              AutoLockTimerInGaming · NtSetTimerResolution(0.5 ms)
            </p>
          </div>
        </div>

        <div class="flex items-center gap-2.5 shrink-0 pt-1">
          <span class="hidden sm:inline text-xs font-medium text-[var(--text-muted)] min-w-10 text-right">
            {config.AutoLockTimerInGaming ? 'Вкл' : 'Выкл'}
          </span>
          <button
            type="button"
            role="switch"
            aria-checked={config.AutoLockTimerInGaming}
            aria-labelledby="tweak-title-AutoLockTimerInGaming"
            aria-describedby="tweak-desc-AutoLockTimerInGaming"
            disabled={isSaving}
            onclick={() => toggleBooleanSetting('AutoLockTimerInGaming')}
            class="ui-switch relative inline-flex items-center w-11 h-6 rounded-full shrink-0 disabled:opacity-55 disabled:cursor-not-allowed cursor-pointer"
          >
            <span
              class="ui-switch-thumb pointer-events-none block w-4 h-4 rounded-full {config.AutoLockTimerInGaming
                ? 'translate-x-[22px]'
                : 'translate-x-[3px]'}"
            ></span>
          </button>
        </div>
      </div>
    </section>

    <!-- Primary Boolean Switches -->
    <section aria-labelledby="switches-heading" class="ui-card rounded-2xl divide-y divide-[var(--border-subtle)] overflow-hidden">
      <div class="px-5 py-3.5 bg-[var(--bg-elevated)] flex items-center gap-2">
        <SlidersHorizontal size={16} strokeWidth={1.75} class="text-[var(--accent-text)]" aria-hidden="true" />
        <h2 id="switches-heading" class="text-sm font-semibold text-[var(--text-primary)]">
          Тонкая настройка видео, сети и ввода
        </h2>
      </div>

      {#each TWEAK_ITEMS as item (item.key)}
        {@const enabled = config[item.key]}
        {@const titleId = `tweak-title-${item.key}`}
        {@const descId = `tweak-desc-${item.key}`}
        <div class="p-5 flex items-start justify-between gap-4">
          <div class="flex items-start gap-3.5 min-w-0">
            <div
              class="w-9 h-9 rounded-xl flex items-center justify-center shrink-0 mt-0.5 {enabled
                ? 'bg-[var(--accent-soft)] text-[var(--accent-text)]'
                : 'bg-[var(--bg-elevated)] text-[var(--text-muted)]'}"
            >
              {#if item.key === 'DisableFullscreenOptimizations'}
                <Monitor size={18} strokeWidth={1.75} aria-hidden="true" />
              {:else if item.key === 'EnableNetAdapterMsi'}
                <Network size={18} strokeWidth={1.75} aria-hidden="true" />
              {:else if item.key === 'DisableMouseAccel'}
                <Mouse size={18} strokeWidth={1.75} aria-hidden="true" />
              {:else}
                <Gamepad2 size={18} strokeWidth={1.75} aria-hidden="true" />
              {/if}
            </div>

            <div class="min-w-0 space-y-1">
              <div id={titleId} class="text-sm font-semibold text-[var(--text-primary)]">
                {item.title}
              </div>
              <p id={descId} class="text-sm leading-relaxed text-[var(--text-secondary)]">
                {item.description}
              </p>
              <p
                translate="no"
                class="font-mono text-xs text-[var(--text-muted)] break-all select-text pt-0.5"
              >
                {item.technicalKey}
              </p>
            </div>
          </div>

          <div class="flex items-center gap-2.5 shrink-0 pt-1">
            <span class="hidden sm:inline text-xs font-medium text-[var(--text-muted)] min-w-10 text-right">
              {enabled ? 'Вкл' : 'Выкл'}
            </span>
            <button
              type="button"
              role="switch"
              aria-checked={enabled}
              aria-labelledby={titleId}
              aria-describedby={descId}
              disabled={isSaving}
              onclick={() => toggleBooleanSetting(item.key)}
              class="ui-switch relative inline-flex items-center w-11 h-6 rounded-full shrink-0 disabled:opacity-55 disabled:cursor-not-allowed cursor-pointer"
            >
              <span
                class="ui-switch-thumb pointer-events-none block w-4 h-4 rounded-full {enabled
                  ? 'translate-x-[22px]'
                  : 'translate-x-[3px]'}"
              ></span>
            </button>
          </div>
        </div>
      {/each}
    </section>

    <!-- Input Buffer Queue Section -->
    <section aria-labelledby="buffer-heading" class="ui-card rounded-2xl p-5 space-y-4">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div class="flex items-start gap-3.5 min-w-0">
          <div class="w-9 h-9 rounded-xl bg-[var(--accent-soft)] text-[var(--accent-text)] flex items-center justify-center shrink-0 mt-0.5">
            <Keyboard size={18} strokeWidth={1.75} aria-hidden="true" />
          </div>
          <div class="space-y-1 min-w-0">
            <h2 id="buffer-heading" class="text-sm font-semibold text-[var(--text-primary)]">
              Буфер очереди событий мыши и клавиатуры
            </h2>
            <p id="input-buffer-help" class="text-sm leading-relaxed text-[var(--text-secondary)]">
              Размер буфера драйвера HID (<code translate="no" class="font-mono text-xs select-text">MouseDataQueueSize</code> и <code translate="no" class="font-mono text-xs select-text">KeyboardDataQueueSize</code>). Запас предотвращает потерю кликов при частоте опроса 2000–8000 Гц.
            </p>
            <p translate="no" class="font-mono text-xs text-[var(--text-muted)] select-text">
              InputBufferQueueSize = {config.InputBufferQueueSize} (мин. 32)
            </p>
          </div>
        </div>

        <span
          class="inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold tabular-nums bg-[var(--accent-soft)] text-[var(--accent-text)] border border-[var(--accent-border)] shrink-0"
        >
          Текущее: {config.InputBufferQueueSize}
        </span>
      </div>

      <!-- Presets Grid -->
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-2.5" role="group" aria-label="Быстрые пресеты размера буфера">
        {#each PRESETS as preset (preset.value)}
          {@const selected = config.InputBufferQueueSize === preset.value}
          <button
            type="button"
            onclick={() => selectQueuePreset(preset.value)}
            disabled={isSaving}
            aria-pressed={selected}
            class="{selected
              ? 'ui-card-selected'
              : 'ui-card-interactive'} rounded-xl px-3.5 py-2.5 text-left flex items-center justify-between gap-2 disabled:opacity-55 disabled:cursor-not-allowed cursor-pointer"
          >
            <span class="block">
              <span class="block text-sm font-semibold tabular-nums text-[var(--text-primary)]">
                {preset.value}
              </span>
              <span class="block text-xs text-[var(--text-muted)]">
                {preset.hint}
              </span>
            </span>

            {#if selected}
              <Check size={15} strokeWidth={2.25} class="text-[var(--accent-text)] shrink-0" aria-hidden="true" />
            {/if}
          </button>
        {/each}
      </div>

      <!-- Custom Numeric Input -->
      <form onsubmit={handleBufferSubmit} class="pt-1 space-y-2" novalidate>
        <div class="flex flex-col sm:flex-row sm:items-end gap-2.5">
          <div class="flex-1 min-w-0 space-y-1.5">
            <label for="input-buffer-size" class="block text-[0.8125rem] font-medium text-[var(--text-secondary)]">
              Произвольное значение (от 32 до 1024 пакетов)
            </label>
            <input
              bind:this={bufferInputEl}
              id="input-buffer-size"
              name="inputBufferQueueSize"
              type="number"
              inputmode="numeric"
              min="32"
              max="1024"
              step="1"
              value={bufferDraft}
              oninput={(e) => {
                bufferDraft = (e.currentTarget as HTMLInputElement).value;
                if (bufferError) {
                  bufferError = validateBufferValue(bufferDraft).error;
                }
              }}
              aria-invalid={bufferError ? 'true' : undefined}
              aria-describedby={bufferError ? 'input-buffer-error input-buffer-help' : 'input-buffer-help'}
              class="ui-input w-full sm:max-w-56 rounded-xl px-3.5 py-2 min-h-10 text-sm tabular-nums {bufferError
                ? '!border-[var(--status-danger-text)]'
                : ''}"
            />
          </div>

          <button
            type="submit"
            disabled={isSaving}
            class="ui-btn-primary ui-pressable rounded-xl px-4 py-2 min-h-10 text-sm font-semibold disabled:opacity-55 disabled:cursor-not-allowed cursor-pointer shrink-0"
          >
            Применить значение
          </button>
        </div>

        {#if bufferError}
          <p id="input-buffer-error" role="alert" class="text-[0.8125rem] font-medium text-[var(--status-danger-text)]">
            {bufferError}
          </p>
        {/if}
      </form>
    </section>

    <!-- Engine Modules Reference -->
    <section aria-labelledby="engine-modules-heading" class="ui-card rounded-2xl p-5 space-y-3">
      <div class="flex items-center gap-2">
        <Cpu size={16} strokeWidth={1.75} class="text-[var(--accent-text)]" aria-hidden="true" />
        <h2 id="engine-modules-heading" class="text-sm font-semibold text-[var(--text-primary)]">
          Системные модули игрового движка
        </h2>
      </div>

      <dl class="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <div class="rounded-xl p-3.5 bg-[var(--bg-elevated)] space-y-1">
          <dt class="text-[0.8125rem] font-semibold text-[var(--text-primary)]">
            Планировщик мультимедиа (MMCSS)
          </dt>
          <dd class="text-[0.8125rem] text-[var(--text-secondary)] leading-relaxed">
            Повышает приоритет потоков игр (<code translate="no" class="font-mono text-xs select-text">Games</code>) и ограничивает фоновый троттлинг сети.
          </dd>
          <dd translate="no" class="font-mono text-xs text-[var(--text-muted)] break-all select-text">
            SystemResponsiveness = 10 · NetworkThrottlingIndex = 0xFFFFFFFF
          </dd>
        </div>

        <div class="rounded-xl p-3.5 bg-[var(--bg-elevated)] space-y-1">
          <dt class="text-[0.8125rem] font-semibold text-[var(--text-primary)]">
            Питание шины PCIe и процессора
          </dt>
          <dd class="text-[0.8125rem] text-[var(--text-secondary)] leading-relaxed">
            Временный переход на схему максимальной производительности с автовосстановлением при выходе.
          </dd>
          <dd translate="no" class="font-mono text-xs text-[var(--text-muted)] break-all select-text">
            PowerPlan Snapshot + Restore · Core Parking Unparked
          </dd>
        </div>
      </dl>
    </section>
  {/if}
</div>
