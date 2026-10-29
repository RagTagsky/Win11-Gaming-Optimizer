<script lang="ts">
  import {
    Activity,
    CheckCircle2,
    Cpu,
    Flame,
    Monitor,
    RefreshCw,
    Shield,
    Sparkles,
    Zap,
  } from '@lucide/svelte';
  import type { HardwareInfo, ModeState, OptimizationProfile } from '../types';

  interface Props {
    mode: ModeState;
    profile: OptimizationProfile;
    hardware: HardwareInfo;
    onToggleMode: () => void;
    onSelectProfile: (profile: OptimizationProfile) => void;
  }

  let {
    mode = 'Normal',
    profile = 'competitive',
    hardware,
    onToggleMode,
    onSelectProfile,
  }: Props = $props();

  const isGaming = $derived(mode === 'Gaming');
  const isTransitioning = $derived(mode === 'Transitioning');
</script>

<div class="space-y-6">
  <!-- Status Banner Card -->
  <div
    class="relative overflow-hidden rounded-xl p-6 border transition-all duration-300 {isGaming
      ? 'bg-gradient-to-br from-[#111815] to-[#0e1210] border-emerald-900/40 shadow-lg shadow-emerald-950/20'
      : 'bg-[#14151a] border-[#22242c]'}"
  >
    <div class="flex items-start justify-between">
      <div class="space-y-2">
        <div class="flex items-center gap-2">
          <span
            class="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-[11px] font-medium {isGaming
              ? 'bg-emerald-950/80 text-emerald-400 border border-emerald-800/60'
              : 'bg-zinc-800/80 text-zinc-400 border border-zinc-700/60'}"
          >
            <span
              class="w-1.5 h-1.5 rounded-full {isGaming
                ? 'bg-emerald-400 animate-pulse'
                : 'bg-zinc-500'}"
            ></span>
            {isGaming ? 'GAMING MODE ACTIVE' : 'NORMAL MODE'}
          </span>
          <span class="text-xs text-zinc-500">v3.0 Strict Core</span>
        </div>

        <h2 class="text-xl font-semibold text-zinc-100 tracking-tight">
          {isGaming ? 'Ultra Gaming Mode активен' : 'Штатный режим Windows'}
        </h2>

        <p class="text-xs text-zinc-400 max-w-xl leading-relaxed">
          {isGaming
            ? '212 служб телеметрии и фоновый шум подавлены. Максимальный приоритет GPU/DWM, защита MPO включена, частота кадров стабилизирована.'
            : 'Все стандартные системные службы (Windows Search, диспетчер печати, кэши) работают штатно. Готов к переходу в игровой режим.'}
        </p>
      </div>

      <!-- Action Button -->
      <div class="flex flex-col items-end gap-2">
        <button
          onclick={onToggleMode}
          disabled={isTransitioning}
          class="relative flex items-center gap-2.5 px-6 py-3.5 rounded-lg text-sm font-semibold tracking-wide transition-all select-none disabled:opacity-50 disabled:cursor-not-allowed {isGaming
            ? 'bg-[#1e2027] hover:bg-[#252832] text-zinc-200 border border-zinc-700/80 hover:border-zinc-600 active:scale-[0.98]'
            : 'bg-emerald-600 hover:bg-emerald-500 text-zinc-950 font-bold shadow-lg shadow-emerald-950/40 active:scale-[0.98]'}"
        >
          {#if isTransitioning}
            <RefreshCw class="w-4 h-4 animate-spin text-zinc-300" />
            <span>Применение...</span>
          {:else if isGaming}
            <RefreshCw class="w-4 h-4 text-zinc-400" />
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
  <div class="space-y-2">
    <div class="flex items-center justify-between">
      <span class="text-xs font-semibold uppercase tracking-wider text-zinc-400">
        Профиль оптимизации
      </span>
      <span class="text-[11px] text-zinc-500">Выбран: {profile.toUpperCase()}</span>
    </div>

    <div class="grid grid-cols-3 gap-3">
      <!-- Competitive Profile -->
      <button
        onclick={() => onSelectProfile('competitive')}
        class="text-left p-3.5 rounded-lg border transition-all {profile === 'competitive'
          ? 'bg-[#181a22] border-emerald-500/50 shadow-sm'
          : 'bg-[#131418] border-[#22242b] hover:bg-[#16181f] text-zinc-400'}"
      >
        <div class="flex items-center gap-2 mb-1.5">
          <Flame class="w-4 h-4 {profile === 'competitive' ? 'text-emerald-400' : 'text-zinc-500'}" />
          <span class="text-xs font-semibold text-zinc-200">Киберспорт (CS2 / Deadlock)</span>
        </div>
        <p class="text-[11px] text-zinc-400 leading-snug">
          Агрессивный FSE, IFEO High, подавление фоновых процессов, DPC-приоритет.
        </p>
      </button>

      <!-- AAA Balanced Profile -->
      <button
        onclick={() => onSelectProfile('aaa')}
        class="text-left p-3.5 rounded-lg border transition-all {profile === 'aaa'
          ? 'bg-[#181a22] border-emerald-500/50 shadow-sm'
          : 'bg-[#131418] border-[#22242b] hover:bg-[#16181f] text-zinc-400'}"
      >
        <div class="flex items-center gap-2 mb-1.5">
          <Sparkles class="w-4 h-4 {profile === 'aaa' ? 'text-emerald-400' : 'text-zinc-500'}" />
          <span class="text-xs font-semibold text-zinc-200">AAA Сбалансированный (RDR2)</span>
        </div>
        <p class="text-[11px] text-zinc-400 leading-snug">
          Приоритет Normal, защита DWM/FreeSync, стабильный Vulkan, защита от морганий.
        </p>
      </button>

      <!-- Custom Profile -->
      <button
        onclick={() => onSelectProfile('custom')}
        class="text-left p-3.5 rounded-lg border transition-all {profile === 'custom'
          ? 'bg-[#181a22] border-emerald-500/50 shadow-sm'
          : 'bg-[#131418] border-[#22242b] hover:bg-[#16181f] text-zinc-400'}"
      >
        <div class="flex items-center gap-2 mb-1.5">
          <Shield class="w-4 h-4 {profile === 'custom' ? 'text-emerald-400' : 'text-zinc-500'}" />
          <span class="text-xs font-semibold text-zinc-200">Пользовательский</span>
        </div>
        <p class="text-[11px] text-zinc-400 leading-snug">
          Ручной выбор из 212 служб и тонких настроек системы.
        </p>
      </button>
    </div>
  </div>

  <!-- Hardware & Realtime Latency Grid -->
  <div class="space-y-2">
    <span class="text-xs font-semibold uppercase tracking-wider text-zinc-400">
      Аппаратный стек и готовность системы
    </span>

    <div class="grid grid-cols-2 gap-3">
      <!-- CPU -->
      <div class="flex items-center gap-3 p-3.5 rounded-lg bg-[#14151a] border border-[#22242c]">
        <div class="w-9 h-9 rounded-md bg-[#1a1c24] flex items-center justify-center border border-[#2b2d38]">
          <Cpu class="w-4 h-4 text-zinc-300" />
        </div>
        <div class="space-y-0.5">
          <span class="text-[11px] text-zinc-500">Процессор (TSC High-Res)</span>
          <p class="text-xs font-medium text-zinc-200">{hardware.cpu}</p>
        </div>
      </div>

      <!-- GPU -->
      <div class="flex items-center gap-3 p-3.5 rounded-lg bg-[#14151a] border border-[#22242c]">
        <div class="w-9 h-9 rounded-md bg-[#1a1c24] flex items-center justify-center border border-[#2b2d38]">
          <Activity class="w-4 h-4 text-zinc-300" />
        </div>
        <div class="space-y-0.5">
          <span class="text-[11px] text-zinc-500">Видеокарта & VRAM</span>
          <p class="text-xs font-medium text-zinc-200">{hardware.gpu}</p>
        </div>
      </div>

      <!-- Display -->
      <div class="flex items-center gap-3 p-3.5 rounded-lg bg-[#14151a] border border-[#22242c]">
        <div class="w-9 h-9 rounded-md bg-[#1a1c24] flex items-center justify-center border border-[#2b2d38]">
          <Monitor class="w-4 h-4 text-emerald-400" />
        </div>
        <div class="space-y-0.5">
          <span class="text-[11px] text-zinc-500">Дисплей & FreeSync</span>
          <p class="text-xs font-medium text-zinc-200">{hardware.display}</p>
        </div>
      </div>

      <!-- DPC Latency -->
      <div class="flex items-center gap-3 p-3.5 rounded-lg bg-[#14151a] border border-[#22242c]">
        <div class="w-9 h-9 rounded-md bg-[#1a1c24] flex items-center justify-center border border-[#2b2d38]">
          <CheckCircle2 class="w-4 h-4 text-emerald-400" />
        </div>
        <div class="space-y-0.5">
          <span class="text-[11px] text-zinc-500">DPC Latency Engine</span>
          <p class="text-xs font-medium text-zinc-200">{hardware.dpcLatency}</p>
        </div>
      </div>
    </div>
  </div>
</div>
