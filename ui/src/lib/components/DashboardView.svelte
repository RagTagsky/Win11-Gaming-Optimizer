<script lang="ts">
  import {
    AlertTriangle,
    Check,
    Clock,
    Cpu,
    HardDrive,
    Layers,
    Loader2,
    Monitor,
    Power,
    RefreshCw,
    RotateCcw,
    Shield,
    ShieldCheck,
    SlidersHorizontal,
    Sparkles,
    Timer,
    Zap
  } from '@lucide/svelte';
  import type { HardwareInfo, ModeState, OptimizationProfile } from '../types';

  interface Props {
    mode: ModeState;
    profile: OptimizationProfile;
    hardware: HardwareInfo | null;
    isProcessing: boolean;
    isStatusLoading: boolean;
    statusError: string | null;
    activeSince?: string;
    timerLocked: boolean;
    isTimerLocking: boolean;
    onToggleMode: () => void;
    onProfileChange: (p: OptimizationProfile) => void;
    onLockTimer: () => void;
    onRetryStatus: () => void;
  }

  let {
    mode,
    profile,
    hardware,
    isProcessing,
    isStatusLoading,
    statusError,
    activeSince,
    timerLocked,
    isTimerLocking,
    onToggleMode,
    onProfileChange,
    onLockTimer,
    onRetryStatus
  }: Props = $props();

  const isActiveMode = $derived(mode === 'Gaming' || mode === 'Armed');
  const isBusy = $derived(isProcessing || mode === 'Transitioning');

  const isTimerActive = $derived.by(() => {
    if (timerLocked) return true;
    const raw = hardware?.timerResolution ?? '';
    const match = raw.match(/(\d+(?:[.,]\d+)?)/);
    if (!match) return false;
    const numeric = Number.parseFloat(match[1].replace(',', '.'));
    return Number.isFinite(numeric) && numeric > 0 && numeric <= 0.6;
  });

  const modeBadge = $derived.by(() => {
    switch (mode) {
      case 'Gaming':
        return {
          title: 'Игровой режим активен',
          subtitle: 'Фоновые службы приостановлены, применён профиль высокой отзывчивости.',
          badgeText: 'Активен',
          pillClass:
            'bg-[var(--status-active-soft)] text-[var(--status-active-text)] border-[var(--status-active-border)]'
        };
      case 'Armed':
        return {
          title: 'Авторежим включён',
          subtitle: 'Движок отслеживает запуск игры и автоматически переключит систему при старте.',
          badgeText: 'Ожидание игры',
          pillClass:
            'bg-[var(--status-warn-soft)] text-[var(--status-warn-text)] border-[var(--status-warn-border)]'
        };
      case 'Transitioning':
        return {
          title: 'Переключение конфигурации…',
          subtitle: 'Применяются параметры служб, сети и ввода Windows. Подождите завершения.',
          badgeText: 'Выполняется',
          pillClass:
            'bg-[var(--accent-soft)] text-[var(--accent-text)] border-[var(--accent-border)]'
        };
      case 'Error':
        return {
          title: 'Сбой переключения режима',
          subtitle: 'Состояние служб может отличаться от целевого. Проверьте журнал или запустите восстановление.',
          badgeText: 'Ошибка',
          pillClass:
            'bg-[var(--status-danger-soft)] text-[var(--status-danger-text)] border-[var(--status-danger-border)]'
        };
      default:
        return {
          title: 'Штатный режим Windows',
          subtitle: 'Все службы работают в обычном порядке. Выберите профиль и включите игровой режим.',
          badgeText: 'Штатный',
          pillClass:
            'bg-[var(--bg-elevated)] text-[var(--text-secondary)] border-[var(--border-strong)]'
        };
    }
  });

  const profiles: Array<{
    id: OptimizationProfile;
    title: string;
    subtitle: string;
    detail: string;
    recommended?: boolean;
  }> = [
    {
      id: 'competitive',
      title: 'Киберспорт',
      subtitle: 'Минимальная задержка',
      detail:
        'Классический полноэкранный режим (FSE), MSI сетевой карты и очередь ввода 100 пакетов для максимальной отзывчивости.',
      recommended: true
    },
    {
      id: 'aaa',
      title: 'AAA и стриминг',
      subtitle: 'Flip Model + OBS / HDR',
      detail:
        'Современный вывод Flip без принудительного FSE, плавный Alt-Tab для OBS/Discord и защита от мерцания дисплея (MPO).'
    },
    {
      id: 'custom',
      title: 'Пользовательский',
      subtitle: 'Конфиг tuning.json',
      detail:
        'Применяет индивидуальные переключатели, параметры GPU/сети и размер буфера ввода из вкладки «Настройки».'
    }
  ];
</script>

<div class="space-y-5">
  <!-- Hero Status Card -->
  <section class="ui-card rounded-2xl p-5 sm:p-6">
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
      <div class="flex items-start gap-4 min-w-0">
        <div
          class="w-12 h-12 rounded-xl flex items-center justify-center shrink-0 border {modeBadge.pillClass}"
        >
          {#if isBusy}
            <Loader2 size={22} strokeWidth={2} class="ui-spin" aria-hidden="true" />
          {:else if mode === 'Gaming'}
            <ShieldCheck size={22} strokeWidth={1.75} aria-hidden="true" />
          {:else if mode === 'Armed'}
            <Clock size={22} strokeWidth={1.75} aria-hidden="true" />
          {:else if mode === 'Error'}
            <AlertTriangle size={22} strokeWidth={1.75} aria-hidden="true" />
          {:else}
            <Shield size={22} strokeWidth={1.75} aria-hidden="true" />
          {/if}
        </div>

        <div class="min-w-0 space-y-1.5">
          <div class="flex flex-wrap items-center gap-2">
            <h1 class="text-lg font-semibold leading-snug text-[var(--text-primary)]">
              {modeBadge.title}
            </h1>
            <span
              class="inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-semibold border {modeBadge.pillClass}"
            >
              {modeBadge.badgeText}
            </span>
          </div>

          <p class="text-sm leading-relaxed text-[var(--text-secondary)]">
            {modeBadge.subtitle}
          </p>

          {#if activeSince && isActiveMode}
            <p class="text-xs font-medium text-[var(--text-muted)] tabular-nums">
              Активен с {activeSince} · профиль «{profile === 'competitive'
                ? 'Киберспорт'
                : profile === 'aaa'
                  ? 'AAA и стриминг'
                  : 'Пользовательский'}»
            </p>
          {/if}
        </div>
      </div>

      <div class="flex items-center gap-2.5 shrink-0">
        <button
          type="button"
          onclick={onToggleMode}
          disabled={isBusy}
          class="{isActiveMode ? 'ui-btn-danger' : 'ui-btn-primary'} ui-pressable min-h-11 px-5 py-2.5 rounded-xl font-semibold text-sm flex items-center justify-center gap-2 w-full sm:w-auto disabled:opacity-55 disabled:cursor-not-allowed cursor-pointer"
        >
          {#if isBusy}
            <Loader2 size={17} strokeWidth={2} class="ui-spin" aria-hidden="true" />
            <span>{isActiveMode ? 'Восстанавливаю…' : 'Применяю…'}</span>
          {:else if isActiveMode}
            <RotateCcw size={17} strokeWidth={2} aria-hidden="true" />
            <span>Вернуть штатный режим</span>
          {:else}
            <Power size={17} strokeWidth={2} aria-hidden="true" />
            <span>Включить игровой режим</span>
          {/if}
        </button>
      </div>
    </div>
  </section>

  <!-- Profile Selector -->
  <section aria-labelledby="profiles-heading" class="space-y-3">
    <div class="flex flex-wrap items-center justify-between gap-2">
      <div>
        <h2 id="profiles-heading" class="text-[0.9375rem] font-semibold text-[var(--text-primary)]">
          Профиль оптимизации
        </h2>
        <p class="text-[0.8125rem] text-[var(--text-secondary)]">
          Задаёт режим вывода кадра и базовый набор параметров <code translate="no" class="font-mono text-xs select-text">Config/tuning.json</code> перед запуском игры.
        </p>
      </div>
    </div>

    <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
      {#each profiles as item (item.id)}
        {@const selected = profile === item.id}
        <button
          type="button"
          onclick={() => onProfileChange(item.id)}
          disabled={isBusy}
          aria-pressed={selected}
          class="{selected ? 'ui-card-selected' : 'ui-card-interactive'} rounded-xl p-4 text-left flex flex-col justify-between gap-3 disabled:opacity-55 disabled:cursor-not-allowed cursor-pointer"
        >
          <span class="block space-y-2 w-full">
            <span class="flex items-start justify-between gap-2 w-full">
              <span class="flex items-center gap-2 min-w-0">
                <span
                  class="w-8 h-8 rounded-lg flex items-center justify-center shrink-0 {selected
                    ? 'bg-[var(--accent-solid)] text-white'
                    : 'bg-[var(--bg-elevated)] text-[var(--accent-text)]'}"
                >
                  {#if item.id === 'competitive'}
                    <Zap size={16} strokeWidth={1.75} aria-hidden="true" />
                  {:else if item.id === 'aaa'}
                    <Sparkles size={16} strokeWidth={1.75} aria-hidden="true" />
                  {:else}
                    <SlidersHorizontal size={16} strokeWidth={1.75} aria-hidden="true" />
                  {/if}
                </span>

                <span class="block min-w-0">
                  <span class="block text-sm font-semibold text-[var(--text-primary)]">
                    {item.title}
                  </span>
                  <span class="block text-xs text-[var(--text-muted)]">
                    {item.subtitle}
                  </span>
                </span>
              </span>

              {#if selected}
                <span
                  class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-semibold bg-[var(--accent-solid)] text-white shrink-0"
                >
                  <Check size={12} strokeWidth={2.25} aria-hidden="true" />
                  <span>Выбран</span>
                </span>
              {:else if item.recommended}
                <span
                  class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium bg-[var(--bg-elevated)] text-[var(--text-secondary)] border border-[var(--border-subtle)] shrink-0"
                >
                  Рекомендуемый
                </span>
              {/if}
            </span>

            <span class="block text-[0.8125rem] leading-relaxed text-[var(--text-secondary)]">
              {item.detail}
            </span>
          </span>
        </button>
      {/each}
    </div>
  </section>

  <!-- System Telemetry & Timer Lock -->
  <section aria-labelledby="hardware-heading" class="ui-card rounded-2xl p-5 space-y-4">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div class="space-y-0.5">
        <h2 id="hardware-heading" class="text-[0.9375rem] font-semibold text-[var(--text-primary)]">
          Оборудование и системный таймер
        </h2>
        <p class="text-[0.8125rem] text-[var(--text-secondary)]">
          Актуальная телеметрия процессора, видеокарты, дисплея, DPC и разрешения таймера Windows.
        </p>
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <span
          class="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-semibold border tabular-nums {isTimerActive
            ? 'bg-[var(--status-active-soft)] text-[var(--status-active-text)] border-[var(--status-active-border)]'
            : 'bg-[var(--bg-elevated)] text-[var(--text-secondary)] border-[var(--border-subtle)]'}"
        >
          <Timer size={13} strokeWidth={1.75} aria-hidden="true" />
          <span>{isTimerActive ? 'Таймер 0.5 мс активен' : 'Штатный таймер'}</span>
        </span>

        <button
          type="button"
          onclick={onLockTimer}
          disabled={isTimerLocking || isBusy}
          class="{isTimerActive ? 'ui-btn-secondary' : 'ui-btn-primary'} ui-pressable rounded-lg px-3.5 py-2 min-h-9 text-[0.8125rem] font-medium flex items-center gap-1.5 disabled:opacity-55 disabled:cursor-not-allowed cursor-pointer"
        >
          {#if isTimerLocking}
            <Loader2 size={14} strokeWidth={2} class="ui-spin" aria-hidden="true" />
            <span>Фиксация…</span>
          {:else}
            <Timer size={14} strokeWidth={1.75} aria-hidden="true" />
            <span>{isTimerActive ? 'Переприменить 0.5 мс' : 'Зафиксировать 0.5 мс'}</span>
          {/if}
        </button>
      </div>
    </div>

    {#if isStatusLoading && !hardware}
      <div class="flex items-center gap-2.5 py-4 text-sm text-[var(--text-secondary)]">
        <Loader2 size={16} strokeWidth={2} class="ui-spin text-[var(--accent-text)]" aria-hidden="true" />
        <span>Считываю параметры оборудования…</span>
      </div>
    {:else if hardware}
      <dl class="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <div class="rounded-xl p-3.5 bg-[var(--bg-elevated)] flex items-start gap-3">
          <Cpu size={18} strokeWidth={1.75} class="text-[var(--accent-text)] shrink-0 mt-0.5" aria-hidden="true" />
          <div class="min-w-0 space-y-0.5">
            <dt class="text-xs font-medium text-[var(--text-muted)]">Процессор</dt>
            <dd class="text-sm font-medium text-[var(--text-primary)] break-words select-text">
              {hardware.cpu}
            </dd>
          </div>
        </div>

        <div class="rounded-xl p-3.5 bg-[var(--bg-elevated)] flex items-start gap-3">
          <Monitor size={18} strokeWidth={1.75} class="text-[var(--accent-text)] shrink-0 mt-0.5" aria-hidden="true" />
          <div class="min-w-0 space-y-0.5">
            <dt class="text-xs font-medium text-[var(--text-muted)]">Видеоадаптер</dt>
            <dd class="text-sm font-medium text-[var(--text-primary)] break-words select-text">
              {hardware.gpu}
            </dd>
          </div>
        </div>

        <div class="rounded-xl p-3.5 bg-[var(--bg-elevated)] flex items-start gap-3">
          <HardDrive size={18} strokeWidth={1.75} class="text-[var(--accent-text)] shrink-0 mt-0.5" aria-hidden="true" />
          <div class="min-w-0 space-y-0.5">
            <dt class="text-xs font-medium text-[var(--text-muted)]">Оперативная память</dt>
            <dd class="text-sm font-medium text-[var(--text-primary)] break-words tabular-nums select-text">
              {hardware.ram}
            </dd>
          </div>
        </div>

        <div class="rounded-xl p-3.5 bg-[var(--bg-elevated)] flex items-start gap-3">
          <Monitor size={18} strokeWidth={1.75} class="text-[var(--accent-text)] shrink-0 mt-0.5" aria-hidden="true" />
          <div class="min-w-0 space-y-0.5">
            <dt class="text-xs font-medium text-[var(--text-muted)]">Дисплей и композитор DWM</dt>
            <dd class="text-sm font-medium text-[var(--text-primary)] break-words select-text">
              {hardware.display}
            </dd>
          </div>
        </div>

        <div class="rounded-xl p-3.5 bg-[var(--bg-elevated)] flex items-start gap-3">
          <Clock size={18} strokeWidth={1.75} class="text-[var(--accent-text)] shrink-0 mt-0.5" aria-hidden="true" />
          <div class="min-w-0 space-y-0.5">
            <dt class="text-xs font-medium text-[var(--text-muted)]">Планировщик ядра и DPC</dt>
            <dd class="text-sm font-medium text-[var(--text-primary)] break-words select-text">
              {hardware.dpcLatency}
            </dd>
          </div>
        </div>

        <div class="rounded-xl p-3.5 bg-[var(--bg-elevated)] flex items-start gap-3">
          <Layers size={18} strokeWidth={1.75} class="text-[var(--accent-text)] shrink-0 mt-0.5" aria-hidden="true" />
          <div class="min-w-0 space-y-0.5">
            <dt class="text-xs font-medium text-[var(--text-muted)]">Мультиплейн-оверлеи (MPO)</dt>
            <dd class="text-sm font-medium text-[var(--text-primary)] break-words select-text">
              {hardware.mpoStatus}
            </dd>
          </div>
        </div>

        <div class="sm:col-span-2 rounded-xl p-3.5 bg-[var(--bg-elevated)] flex items-start gap-3">
          <Timer size={18} strokeWidth={1.75} class="text-[var(--accent-text)] shrink-0 mt-0.5" aria-hidden="true" />
          <div class="min-w-0 space-y-0.5">
            <dt class="text-xs font-medium text-[var(--text-muted)]">Разрешение таймера Windows</dt>
            <dd class="text-sm font-medium text-[var(--text-primary)] tabular-nums select-text">
              {timerLocked && !(hardware.timerResolution ?? '').includes('0.5')
                ? '0.500 мс (зафиксировано)'
                : (hardware.timerResolution ?? 'Штатный системный таймер')}
            </dd>
          </div>
        </div>
      </dl>
    {:else if statusError}
      <div class="rounded-xl p-4 bg-[var(--status-danger-soft)] border border-[var(--status-danger-border)] flex flex-wrap items-center justify-between gap-3">
        <p class="text-sm text-[var(--status-danger-text)]">
          Не удалось загрузить данные оборудования: {statusError}
        </p>
        <button
          type="button"
          onclick={onRetryStatus}
          class="ui-btn-secondary ui-pressable rounded-lg px-3 py-1.5 min-h-9 text-[0.8125rem] font-medium flex items-center gap-1.5 cursor-pointer"
        >
          <RefreshCw size={14} strokeWidth={1.75} aria-hidden="true" />
          <span>Повторить</span>
        </button>
      </div>
    {/if}
  </section>
</div>
