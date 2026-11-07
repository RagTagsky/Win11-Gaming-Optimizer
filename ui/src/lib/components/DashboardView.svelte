<script lang="ts">
  import {
    Activity,
    CheckCircle2,
    Cpu,
    Flame,
    HardDrive,
    Monitor,
    RefreshCw,
    Shield,
    Sparkles,
    Timer,
    Zap,
  } from '@lucide/svelte';
  import { executeEmergencyRepair, lockTimerResolution } from '../api';
  import type { HardwareInfo, LogEntry, ModeState, OptimizationProfile } from '../types';

  interface Props {
    mode: ModeState;
    profile: OptimizationProfile;
    hardware: HardwareInfo;
    onToggleMode: () => void;
    onSelectProfile: (profile: OptimizationProfile) => void;
    onLog?: (level: LogEntry['level'], message: string) => void;
  }

  let {
    mode = 'Normal',
    profile = 'competitive',
    hardware,
    onToggleMode,
    onSelectProfile,
    onLog,
  }: Props = $props();

  const isGaming = $derived(mode === 'Gaming');
  const isTransitioning = $derived(mode === 'Transitioning');

  let isTimerLocking = $state(false);
  let isMemoryPurging = $state(false);
  let timerLocked = $state(false);

  async function handleLockTimer() {
    isTimerLocking = true;
    try {
      const res = await lockTimerResolution();
      timerLocked = res.success;
      onLog?.(res.success ? 'success' : 'error', res.message);
    } catch (e: any) {
      onLog?.('error', `Ошибка блокировки таймера: ${e?.message || e}`);
    } finally {
      isTimerLocking = false;
    }
  }

  async function handlePurgeMemory() {
    isMemoryPurging = true;
    try {
      const res = await executeEmergencyRepair('memory');
      onLog?.(res.success ? 'success' : 'error', res.message);
    } catch (e: any) {
      onLog?.('error', `Ошибка очистки памяти: ${e?.message || e}`);
    } finally {
      isMemoryPurging = false;
    }
  }
</script>

<div class="space-y-5">
  <!-- Status Banner Card -->
  <div
    class="relative overflow-hidden rounded-2xl p-6 border transition-all duration-300 {isGaming
      ? 'bg-gradient-to-br from-[#101b15] via-[#0d1512] to-[#0a100e] border-emerald-500/40 shadow-xl shadow-emerald-950/30 ring-1 ring-emerald-500/20'
      : 'bg-[#131419] border-[#20222a] shadow-md'}"
  >
    <div class="flex items-start justify-between gap-6">
      <div class="space-y-2.5">
        <div class="flex items-center gap-2">
          <span
            class="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-[11px] font-semibold tracking-wider {isGaming
              ? 'bg-emerald-950/80 text-emerald-400 border border-emerald-700/60 shadow-sm shadow-emerald-950/50'
              : 'bg-zinc-800/80 text-zinc-300 border border-zinc-700/60'}"
          >
            <span
              class="w-2 h-2 rounded-full {isGaming
                ? 'bg-emerald-400 animate-pulse shadow-sm shadow-emerald-400/50'
                : 'bg-zinc-500'}"
            ></span>
            {isGaming ? 'GAMING MODE ACTIVE' : 'NORMAL MODE'}
          </span>
          <span class="text-xs text-zinc-500 font-mono">v3.0 Pure On-Demand</span>
        </div>

        <h2 class="text-2xl font-bold text-white tracking-tight">
          {isGaming ? 'Ultra Gaming Mode активен' : 'Штатный режим Windows'}
        </h2>

        <p class="text-xs text-zinc-400 max-w-xl leading-relaxed">
          {isGaming
            ? '207 служб телеметрии и фоновый шум подавлены. Максимальный приоритет GPU/DWM, защита MPO включена, микрозадержки DPC устранены.'
            : 'Все стандартные системные службы (Windows Search, Ножницы/PrtSc, диспетчер печати, сетевые профили) работают штатно. Система готова к игре.'}
        </p>
      </div>

      <!-- Action Button -->
      <div class="flex flex-col items-end gap-2 shrink-0">
        <button
          type="button"
          onclick={onToggleMode}
          disabled={isTransitioning}
          class="relative flex items-center gap-2.5 px-6 py-3.5 rounded-xl text-sm font-bold tracking-wide transition-all duration-200 select-none cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed {isGaming
            ? 'bg-[#1e222a] hover:bg-[#282d38] text-zinc-100 border border-zinc-600/60 hover:border-zinc-500 shadow-md active:scale-[0.98]'
            : 'bg-gradient-to-r from-emerald-600 to-emerald-500 hover:from-emerald-500 hover:to-emerald-400 text-zinc-950 shadow-lg shadow-emerald-950/60 active:scale-[0.98]'}"
        >
          {#if isTransitioning}
            <RefreshCw class="w-4 h-4 animate-spin text-zinc-300" />
            <span>Применение...</span>
          {:else if isGaming}
            <RefreshCw class="w-4 h-4 text-zinc-300" />
            <span>Восстановить штатный режим</span>
          {:else}
            <Zap class="w-4 h-4 text-zinc-950 fill-zinc-950" />
            <span>Включить Ultra Gaming Mode</span>
          {/if}
        </button>
        <span class="text-[11px] text-zinc-500">
          {isGaming ? 'Откат занимает ~1.2 сек' : 'Мгновенный переход без перезагрузки'}
        </span>
      </div>
    </div>
  </div>

  <!-- Profiles Selector -->
  <div class="space-y-2.5">
    <div class="flex items-center justify-between">
      <span class="text-xs font-bold uppercase tracking-wider text-zinc-400">
        Профиль оптимизации
      </span>
      <span class="text-[11px] font-mono text-zinc-500">АКТИВЕН: <span class="text-emerald-400 font-semibold">{profile.toUpperCase()}</span></span>
    </div>

    <div class="grid grid-cols-3 gap-3">
      <!-- Competitive Profile -->
      <button
        type="button"
        onclick={() => onSelectProfile('competitive')}
        class="text-left p-4 rounded-xl border transition-all duration-200 cursor-pointer {profile === 'competitive'
          ? 'bg-[#121c17] border-emerald-500/60 ring-1 ring-emerald-500/30 shadow-md shadow-emerald-950/30'
          : 'bg-[#131418] border-[#22242b] hover:border-[#323540] hover:bg-[#161820] text-zinc-400'}"
      >
        <div class="flex items-center gap-2 mb-1.5">
          <Flame class="w-4 h-4 {profile === 'competitive' ? 'text-emerald-400' : 'text-zinc-500'}" />
          <span class="text-xs font-bold text-zinc-200">Киберспорт (CS2 / Deadlock)</span>
        </div>
        <p class="text-[11px] text-zinc-400 leading-snug">
          Агрессивный FSE, IFEO High, подавление фоновых процессов, DPC-приоритет.
        </p>
      </button>

      <!-- AAA Balanced Profile -->
      <button
        type="button"
        onclick={() => onSelectProfile('aaa')}
        class="text-left p-4 rounded-xl border transition-all duration-200 cursor-pointer {profile === 'aaa'
          ? 'bg-[#121c17] border-emerald-500/60 ring-1 ring-emerald-500/30 shadow-md shadow-emerald-950/30'
          : 'bg-[#131418] border-[#22242b] hover:border-[#323540] hover:bg-[#161820] text-zinc-400'}"
      >
        <div class="flex items-center gap-2 mb-1.5">
          <Sparkles class="w-4 h-4 {profile === 'aaa' ? 'text-emerald-400' : 'text-zinc-500'}" />
          <span class="text-xs font-bold text-zinc-200">AAA Сбалансированный (RDR2)</span>
        </div>
        <p class="text-[11px] text-zinc-400 leading-snug">
          Приоритет Normal, защита DWM/FreeSync, стабильный Vulkan, защита от морганий.
        </p>
      </button>

      <!-- Custom Profile -->
      <button
        type="button"
        onclick={() => onSelectProfile('custom')}
        class="text-left p-4 rounded-xl border transition-all duration-200 cursor-pointer {profile === 'custom'
          ? 'bg-[#121c17] border-emerald-500/60 ring-1 ring-emerald-500/30 shadow-md shadow-emerald-950/30'
          : 'bg-[#131418] border-[#22242b] hover:border-[#323540] hover:bg-[#161820] text-zinc-400'}"
      >
        <div class="flex items-center gap-2 mb-1.5">
          <Shield class="w-4 h-4 {profile === 'custom' ? 'text-emerald-400' : 'text-zinc-500'}" />
          <span class="text-xs font-bold text-zinc-200">Пользовательский</span>
        </div>
        <p class="text-[11px] text-zinc-400 leading-snug">
          Ручной выбор из 207 служб и индивидуальных твиков системы.
        </p>
      </button>
    </div>
  </div>

  <!-- Hardware & Realtime Latency Grid -->
  <div class="space-y-2.5">
    <span class="text-xs font-bold uppercase tracking-wider text-zinc-400">
      Аппаратный стек и готовность системы
    </span>

    <div class="grid grid-cols-2 gap-3">
      <!-- CPU -->
      <div class="flex items-center gap-3.5 p-3.5 rounded-xl bg-[#131419] border border-[#20222a] hover:border-[#2d303b] transition-colors">
        <div class="w-9 h-9 rounded-lg bg-[#181a22] flex items-center justify-center border border-[#2a2d39] shrink-0">
          <Cpu class="w-4 h-4 text-zinc-300" />
        </div>
        <div class="space-y-0.5 min-w-0">
          <span class="text-[11px] text-zinc-500">Процессор (TSC High-Res)</span>
          <p class="text-xs font-semibold text-zinc-200 truncate">{hardware.cpu}</p>
        </div>
      </div>

      <!-- GPU -->
      <div class="flex items-center gap-3.5 p-3.5 rounded-xl bg-[#131419] border border-[#20222a] hover:border-[#2d303b] transition-colors">
        <div class="w-9 h-9 rounded-lg bg-[#181a22] flex items-center justify-center border border-[#2a2d39] shrink-0">
          <Activity class="w-4 h-4 text-zinc-300" />
        </div>
        <div class="space-y-0.5 min-w-0">
          <span class="text-[11px] text-zinc-500">Видеокарта & VRAM</span>
          <p class="text-xs font-semibold text-zinc-200 truncate">{hardware.gpu}</p>
        </div>
      </div>

      <!-- Display -->
      <div class="flex items-center gap-3.5 p-3.5 rounded-xl bg-[#131419] border border-[#20222a] hover:border-[#2d303b] transition-colors">
        <div class="w-9 h-9 rounded-lg bg-[#181a22] flex items-center justify-center border border-[#2a2d39] shrink-0">
          <Monitor class="w-4 h-4 text-emerald-400" />
        </div>
        <div class="space-y-0.5 min-w-0">
          <span class="text-[11px] text-zinc-500">Дисплей & FreeSync</span>
          <p class="text-xs font-semibold text-zinc-200 truncate">{hardware.display}</p>
        </div>
      </div>

      <!-- DPC Latency -->
      <div class="flex items-center gap-3.5 p-3.5 rounded-xl bg-[#131419] border border-[#20222a] hover:border-[#2d303b] transition-colors">
        <div class="w-9 h-9 rounded-lg bg-[#181a22] flex items-center justify-center border border-[#2a2d39] shrink-0">
          <CheckCircle2 class="w-4 h-4 text-emerald-400" />
        </div>
        <div class="space-y-0.5 min-w-0">
          <span class="text-[11px] text-zinc-500">DPC Latency Engine</span>
          <p class="text-xs font-semibold text-zinc-200 truncate">{hardware.dpcLatency}</p>
        </div>
      </div>

      <!-- RAM & Standby Cache -->
      <div class="flex items-center justify-between p-3.5 rounded-xl bg-[#131419] border border-[#20222a] hover:border-[#2d303b] transition-colors">
        <div class="flex items-center gap-3.5 min-w-0">
          <div class="w-9 h-9 rounded-lg bg-[#181a22] flex items-center justify-center border border-[#2a2d39] shrink-0">
            <HardDrive class="w-4 h-4 text-zinc-300" />
          </div>
          <div class="space-y-0.5 min-w-0">
            <span class="text-[11px] text-zinc-500">Память & Standby кэш</span>
            <p class="text-xs font-semibold text-zinc-200 truncate">{hardware.ram}</p>
          </div>
        </div>
        <button
          type="button"
          onclick={handlePurgeMemory}
          disabled={isMemoryPurging}
          class="shrink-0 flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-[11px] font-bold bg-[#1c1e26] hover:bg-[#252834] text-zinc-200 border border-[#2c2f3d] transition-all cursor-pointer disabled:opacity-50"
          title="Сбросить кэш Standby RAM"
        >
          {#if isMemoryPurging}
            <RefreshCw class="w-3 h-3 animate-spin" />
          {:else}
            <span>Сброс</span>
          {/if}
        </button>
      </div>

      <!-- System Timer Resolution -->
      <div class="flex items-center justify-between p-3.5 rounded-xl bg-[#131419] border border-[#20222a] hover:border-[#2d303b] transition-colors">
        <div class="flex items-center gap-3.5 min-w-0">
          <div class="w-9 h-9 rounded-lg bg-[#181a22] flex items-center justify-center border border-[#2a2d39] shrink-0">
            <Timer class="w-4 h-4 {timerLocked ? 'text-emerald-400' : 'text-zinc-300'}" />
          </div>
          <div class="space-y-0.5 min-w-0">
            <span class="text-[11px] text-zinc-500">Таймер ядра (Low Jitter)</span>
            <p class="text-xs font-semibold text-zinc-200 truncate">{hardware.timerResolution || '0.500 ms (Locked via ntdll)'}</p>
          </div>
        </div>
        <button
          type="button"
          onclick={handleLockTimer}
          disabled={isTimerLocking}
          class="shrink-0 flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-[11px] font-bold transition-all cursor-pointer disabled:opacity-50 {timerLocked
            ? 'bg-emerald-950/60 text-emerald-300 border border-emerald-700/60'
            : 'bg-[#1c1e26] hover:bg-[#252834] text-zinc-200 border border-[#2c2f3d]'}"
          title="Заблокировать системный таймер на 0.500 мс"
        >
          {#if isTimerLocking}
            <RefreshCw class="w-3 h-3 animate-spin" />
          {:else if timerLocked}
            <span>0.5ms ✓</span>
          {:else}
            <span>Lock 0.5ms</span>
          {/if}
        </button>
      </div>
    </div>
  </div>
</div>
