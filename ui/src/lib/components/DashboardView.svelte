<script lang="ts">
  import {
    Activity,
    CheckCircle2,
    Cpu,
    HardDrive,
    Monitor,
    RefreshCw,
    Shield,
    Sliders,
    Sparkles,
    Timer,
    Zap,
  } from '@lucide/svelte';
  import { executeEmergencyRepair, fetchSystemStatus, lockTimerResolution } from '../api';
  import type { HardwareInfo, LogEntry, ModeState, OptimizationProfile } from '../types';

  interface Props {
    mode: ModeState;
    profile: OptimizationProfile;
    hardware: HardwareInfo;
    onToggleMode: () => void;
    onSelectProfile: (profile: OptimizationProfile) => void;
    onHardwareRefresh?: (hw: HardwareInfo) => void;
    onLog?: (level: LogEntry['level'], message: string) => void;
  }

  let {
    mode = 'Normal',
    profile = 'competitive',
    hardware,
    onToggleMode,
    onSelectProfile,
    onHardwareRefresh,
    onLog,
  }: Props = $props();

  const isGaming = $derived(mode === 'Gaming');
  const isArmed = $derived(mode === 'Armed');
  const isActiveOrArmed = $derived(mode === 'Gaming' || mode === 'Armed');
  const isTransitioning = $derived(mode === 'Transitioning');

  let isTimerLocking = $state(false);
  let isMemoryPurging = $state(false);
  let timerLocked = $state(false);

  const statusBadgeText = $derived(
    isGaming
      ? 'Игровой режим активен'
      : isArmed
        ? 'Активен в сессии (ожидает перезагрузки)'
        : 'Штатный режим'
  );

  const statusHeadline = $derived(
    isGaming
      ? 'Игровой режим полностью активирован'
      : isArmed
        ? 'Сессия оптимизирована · перезагрузите ПК для отключения 207 служб'
        : 'Штатный режим работы Windows'
  );

  const statusDescription = $derived(
    isGaming
      ? '207 неигровых фоновых служб остановлены, планировщик CPU/GPU и сетевой стек переведены в режим минимальной задержки. При следующей перезагрузке штатное состояние восстановится автоматически.'
      : isArmed
        ? 'Пользовательская автозагрузка, анимации, сетевые очереди и параметры ввода уже применены в текущей сессии. После перезагрузки ПК планировщик отключит 207 фоновых служб.'
        : 'Все системные службы, поиск Windows, буфер обмена, скриншоты (PrtSc) и печать работают в стандартном режиме. Выберите профиль и включите игровой режим перед запуском игры.'
  );

  async function handleLockTimer() {
    isTimerLocking = true;
    try {
      const res = await lockTimerResolution();
      timerLocked = res.success;
      onLog?.(res.success ? 'success' : 'error', res.message);
      const latest = await fetchSystemStatus();
      onHardwareRefresh?.(latest.hardware);
    } catch (e: any) {
      onLog?.('error', `Ошибка настройки таймера: ${e?.message || e}`);
    } finally {
      isTimerLocking = false;
    }
  }

  async function handlePurgeMemory() {
    isMemoryPurging = true;
    try {
      const res = await executeEmergencyRepair('memory');
      onLog?.(res.success ? 'success' : 'error', res.message);
      const latest = await fetchSystemStatus();
      onHardwareRefresh?.(latest.hardware);
    } catch (e: any) {
      onLog?.('error', `Ошибка очистки памяти: ${e?.message || e}`);
    } finally {
      isMemoryPurging = false;
    }
  }
</script>

<div class="space-y-5">
  <!-- Main System State Card -->
  <div
    class="rounded-xl p-6 border transition-all duration-200"
    style="
      background-color: var(--bg-surface);
      border-color: {isGaming
      ? 'var(--active-border)'
      : isArmed
        ? 'var(--warn-border)'
        : 'var(--border-subtle)'};
    "
  >
    <div class="flex flex-col md:flex-row md:items-center justify-between gap-5">
      <div class="space-y-2">
        <div class="flex items-center gap-2.5">
          <span
            class="inline-flex items-center gap-2 px-2.5 py-1 rounded-md text-xs font-semibold border"
            style="
              background-color: {isGaming
              ? 'var(--active-soft)'
              : isArmed
                ? 'var(--warn-soft)'
                : 'var(--bg-elevated)'};
              color: {isGaming
              ? 'var(--active-primary)'
              : isArmed
                ? 'var(--warn-primary)'
                : 'var(--text-secondary)'};
              border-color: {isGaming
              ? 'var(--active-border)'
              : isArmed
                ? 'var(--warn-border)'
                : 'var(--border-subtle)'};
            "
          >
            <span
              class="w-2 h-2 rounded-full"
              style="background-color: {isGaming
                ? 'var(--active-primary)'
                : isArmed
                  ? 'var(--warn-primary)'
                  : 'var(--text-muted)'};"
            ></span>
            {statusBadgeText}
          </span>
        </div>

        <h2 class="text-xl font-bold tracking-tight" style="color: var(--text-primary);">
          {statusHeadline}
        </h2>

        <p class="text-xs max-w-2xl leading-relaxed" style="color: var(--text-secondary);">
          {statusDescription}
        </p>
      </div>

      <!-- Primary Control Action -->
      <div class="flex flex-col items-start md:items-end gap-1.5 shrink-0">
        <button
          type="button"
          onclick={onToggleMode}
          disabled={isTransitioning}
          class="flex items-center gap-2.5 px-5 py-3 rounded-lg text-sm font-semibold transition-all duration-150 select-none cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed text-white shadow-sm"
          style="
            background-color: {isActiveOrArmed ? 'var(--bg-elevated)' : 'var(--accent-primary)'};
            color: {isActiveOrArmed ? 'var(--text-primary)' : '#ffffff'};
            border: 1px solid {isActiveOrArmed ? 'var(--border-strong)' : 'transparent'};
          "
        >
          {#if isTransitioning}
            <RefreshCw class="w-4 h-4 animate-spin" />
            <span>Выполнение...</span>
          {:else if isActiveOrArmed}
            <RefreshCw class="w-4 h-4" />
            <span>Вернуть штатный режим</span>
          {:else}
            <Zap class="w-4 h-4" />
            <span>Включить игровой режим</span>
          {/if}
        </button>
        <span class="text-[11px]" style="color: var(--text-muted);">
          {isActiveOrArmed
            ? 'Восстанавливает все службы и настройки из резервной копии'
            : 'Создаёт снимок состояния и применяет выбранный профиль'}
        </span>
      </div>
    </div>
  </div>

  <!-- Profile Selector -->
  <div class="space-y-2.5">
    <div class="flex items-center justify-between">
      <span class="text-xs font-semibold" style="color: var(--text-secondary);">
        Профиль оптимизации
      </span>
      <span class="text-xs" style="color: var(--text-muted);">
        Выбран:
        <strong style="color: var(--text-primary);">
          {profile === 'competitive'
            ? 'Киберспорт'
            : profile === 'aaa'
              ? 'AAA и стриминг'
              : 'Пользовательский'}
        </strong>
      </span>
    </div>

    <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
      <!-- Esports / Competitive -->
      <button
        type="button"
        onclick={() => onSelectProfile('competitive')}
        class="text-left p-4 rounded-xl border transition-all duration-150 cursor-pointer"
        style="
          background-color: {profile === 'competitive' ? 'var(--accent-soft)' : 'var(--bg-surface)'};
          border-color: {profile === 'competitive' ? 'var(--accent-border)' : 'var(--border-subtle)'};
        "
      >
        <div class="flex items-center gap-2 mb-1.5">
          <Zap
            class="w-4 h-4"
            style="color: {profile === 'competitive' ? 'var(--accent-primary)' : 'var(--text-muted)'};"
          />
          <span class="text-xs font-semibold" style="color: var(--text-primary);">
            Киберспорт
          </span>
        </div>
        <p class="text-[11px] leading-relaxed" style="color: var(--text-secondary);">
          Классический полноэкранный режим (FSE), MSI сетевой карты, очередь ввода 100 пакетов и высокий приоритет CS2 / Deadlock.
        </p>
      </button>

      <!-- AAA & Streaming -->
      <button
        type="button"
        onclick={() => onSelectProfile('aaa')}
        class="text-left p-4 rounded-xl border transition-all duration-150 cursor-pointer"
        style="
          background-color: {profile === 'aaa' ? 'var(--accent-soft)' : 'var(--bg-surface)'};
          border-color: {profile === 'aaa' ? 'var(--accent-border)' : 'var(--border-subtle)'};
        "
      >
        <div class="flex items-center gap-2 mb-1.5">
          <Sparkles
            class="w-4 h-4"
            style="color: {profile === 'aaa' ? 'var(--accent-primary)' : 'var(--text-muted)'};"
          />
          <span class="text-xs font-semibold" style="color: var(--text-primary);">
            AAA и стриминг
          </span>
        </div>
        <p class="text-[11px] leading-relaxed" style="color: var(--text-secondary);">
          Современный Flip Model без принудительного FSE, плавный Alt-Tab для OBS/Discord, защита от мерцания дисплея (MPO).
        </p>
      </button>

      <!-- Custom -->
      <button
        type="button"
        onclick={() => onSelectProfile('custom')}
        class="text-left p-4 rounded-xl border transition-all duration-150 cursor-pointer"
        style="
          background-color: {profile === 'custom' ? 'var(--accent-soft)' : 'var(--bg-surface)'};
          border-color: {profile === 'custom' ? 'var(--accent-border)' : 'var(--border-subtle)'};
        "
      >
        <div class="flex items-center gap-2 mb-1.5">
          <Sliders
            class="w-4 h-4"
            style="color: {profile === 'custom' ? 'var(--accent-primary)' : 'var(--text-muted)'};"
          />
          <span class="text-xs font-semibold" style="color: var(--text-primary);">
            Пользовательский
          </span>
        </div>
        <p class="text-[11px] leading-relaxed" style="color: var(--text-secondary);">
          Использует индивидуальные параметры из вкладки «Настройки» (Config/tuning.json).
        </p>
      </button>
    </div>
  </div>

  <!-- Hardware & System Metrics Grid -->
  <div class="space-y-2.5">
    <span class="text-xs font-semibold" style="color: var(--text-secondary);">
      Оборудование и ключевые показатели
    </span>

    <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
      <!-- CPU -->
      <div
        class="flex items-center gap-3.5 p-3.5 rounded-xl border transition-colors"
        style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
      >
        <div
          class="w-9 h-9 rounded-lg flex items-center justify-center border shrink-0"
          style="background-color: var(--bg-elevated); border-color: var(--border-subtle);"
        >
          <Cpu class="w-4 h-4" style="color: var(--accent-primary);" />
        </div>
        <div class="space-y-0.5 min-w-0">
          <span class="text-[11px]" style="color: var(--text-muted);">Процессор</span>
          <p class="text-xs font-semibold truncate" style="color: var(--text-primary);" title={hardware.cpu}>
            {hardware.cpu}
          </p>
        </div>
      </div>

      <!-- GPU -->
      <div
        class="flex items-center gap-3.5 p-3.5 rounded-xl border transition-colors"
        style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
      >
        <div
          class="w-9 h-9 rounded-lg flex items-center justify-center border shrink-0"
          style="background-color: var(--bg-elevated); border-color: var(--border-subtle);"
        >
          <Activity class="w-4 h-4" style="color: var(--accent-primary);" />
        </div>
        <div class="space-y-0.5 min-w-0">
          <span class="text-[11px]" style="color: var(--text-muted);">Видеокарта</span>
          <p class="text-xs font-semibold truncate" style="color: var(--text-primary);" title={hardware.gpu}>
            {hardware.gpu}
          </p>
        </div>
      </div>

      <!-- Display & MPO -->
      <div
        class="flex items-center gap-3.5 p-3.5 rounded-xl border transition-colors"
        style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
      >
        <div
          class="w-9 h-9 rounded-lg flex items-center justify-center border shrink-0"
          style="background-color: var(--bg-elevated); border-color: var(--border-subtle);"
        >
          <Monitor class="w-4 h-4" style="color: var(--active-primary);" />
        </div>
        <div class="space-y-0.5 min-w-0">
          <span class="text-[11px]" style="color: var(--text-muted);">Дисплей и композитор DWM</span>
          <p class="text-xs font-semibold truncate" style="color: var(--text-primary);" title={hardware.display}>
            {hardware.display}
          </p>
        </div>
      </div>

      <!-- Kernel DPC & Scheduler -->
      <div
        class="flex items-center gap-3.5 p-3.5 rounded-xl border transition-colors"
        style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
      >
        <div
          class="w-9 h-9 rounded-lg flex items-center justify-center border shrink-0"
          style="background-color: var(--bg-elevated); border-color: var(--border-subtle);"
        >
          <CheckCircle2 class="w-4 h-4" style="color: var(--active-primary);" />
        </div>
        <div class="space-y-0.5 min-w-0">
          <span class="text-[11px]" style="color: var(--text-muted);">Планировщик ядра и DPC</span>
          <p class="text-xs font-semibold truncate" style="color: var(--text-primary);" title={hardware.dpcLatency}>
            {hardware.dpcLatency}
          </p>
        </div>
      </div>

      <!-- RAM & Standby Cache -->
      <div
        class="flex items-center justify-between gap-2 p-3.5 rounded-xl border transition-colors"
        style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
      >
        <div class="flex items-center gap-3.5 min-w-0">
          <div
            class="w-9 h-9 rounded-lg flex items-center justify-center border shrink-0"
            style="background-color: var(--bg-elevated); border-color: var(--border-subtle);"
          >
            <HardDrive class="w-4 h-4" style="color: var(--accent-primary);" />
          </div>
          <div class="space-y-0.5 min-w-0">
            <span class="text-[11px]" style="color: var(--text-muted);">Оперативная память</span>
            <p class="text-xs font-semibold truncate" style="color: var(--text-primary);" title={hardware.ram}>
              {hardware.ram}
            </p>
          </div>
        </div>
        <button
          type="button"
          onclick={handlePurgeMemory}
          disabled={isMemoryPurging}
          class="shrink-0 flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium border transition-colors cursor-pointer disabled:opacity-50"
          style="background-color: var(--bg-elevated); border-color: var(--border-subtle); color: var(--text-primary);"
          title="Очистить резервный кэш памяти (Standby List)"
        >
          {#if isMemoryPurging}
            <RefreshCw class="w-3.5 h-3.5 animate-spin" />
          {:else}
            <span>Очистить кэш</span>
          {/if}
        </button>
      </div>

      <!-- System Timer Resolution -->
      <div
        class="flex items-center justify-between gap-2 p-3.5 rounded-xl border transition-colors"
        style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
      >
        <div class="flex items-center gap-3.5 min-w-0">
          <div
            class="w-9 h-9 rounded-lg flex items-center justify-center border shrink-0"
            style="background-color: var(--bg-elevated); border-color: var(--border-subtle);"
          >
            <Timer
              class="w-4 h-4"
              style="color: {timerLocked ? 'var(--active-primary)' : 'var(--accent-primary)'};"
            />
          </div>
          <div class="space-y-0.5 min-w-0">
            <span class="text-[11px]" style="color: var(--text-muted);">Системный таймер ядра</span>
            <p class="text-xs font-semibold truncate" style="color: var(--text-primary);">
              {hardware.timerResolution || '1.000 мс'}
            </p>
          </div>
        </div>
        <button
          type="button"
          onclick={handleLockTimer}
          disabled={isTimerLocking}
          class="shrink-0 flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium border transition-colors cursor-pointer disabled:opacity-50"
          style="
            background-color: {timerLocked ? 'var(--active-soft)' : 'var(--bg-elevated)'};
            border-color: {timerLocked ? 'var(--active-border)' : 'var(--border-subtle)'};
            color: {timerLocked ? 'var(--active-primary)' : 'var(--text-primary)'};
          "
          title="Зафиксировать разрешение системного таймера на 0.5 мс"
        >
          {#if isTimerLocking}
            <RefreshCw class="w-3.5 h-3.5 animate-spin" />
          {:else if timerLocked}
            <span>0.5 мс активен</span>
          {:else}
            <span>Задать 0.5 мс</span>
          {/if}
        </button>
      </div>
    </div>
  </div>
</div>
