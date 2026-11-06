<script lang="ts">
  import {
    AlertTriangle,
    CheckCircle,
    HardDrive,
    MonitorOff,
    RefreshCw,
    Search,
    ShieldAlert,
    Wrench,
  } from '@lucide/svelte';
  import { executeEmergencyRepair } from '../api';
  import type { LogEntry } from '../types';

  interface Props {
    onLog?: (level: LogEntry['level'], message: string) => void;
  }

  let { onLog }: Props = $props();

  let runningRepair = $state<string | null>(null);
  let statusMessage = $state<{ type: 'success' | 'error'; text: string } | null>(null);

  async function triggerRepair(repairType: 'display' | 'services' | 'shaders' | 'verify') {
    runningRepair = repairType;
    statusMessage = null;
    onLog?.('info', `Запуск аварийного ремонта [${repairType}]...`);

    try {
      const res = await executeEmergencyRepair(repairType);
      statusMessage = {
        type: res.success ? 'success' : 'error',
        text: res.message,
      };
      onLog?.(res.success ? 'success' : 'error', res.message);
    } catch (e: any) {
      const msg = `Ошибка выполнения: ${e?.message || e}`;
      statusMessage = {
        type: 'error',
        text: msg,
      };
      onLog?.('error', msg);
    } finally {
      runningRepair = null;
    }
  }
</script>

<div class="space-y-4">
  <!-- Status Banner if repair executed -->
  {#if statusMessage}
    <div
      class="p-4 rounded-xl border flex items-center justify-between text-xs transition-all {statusMessage.type === 'success'
        ? 'bg-emerald-950/40 border-emerald-800/60 text-emerald-300 shadow-sm'
        : 'bg-rose-950/40 border-rose-800/60 text-rose-300 shadow-sm'}"
    >
      <div class="flex items-center gap-2.5">
        {#if statusMessage.type === 'success'}
          <CheckCircle class="w-4 h-4 text-emerald-400 shrink-0" />
        {:else}
          <AlertTriangle class="w-4 h-4 text-rose-400 shrink-0" />
        {/if}
        <span class="font-medium leading-relaxed">{statusMessage.text}</span>
      </div>
      <button
        type="button"
        onclick={() => (statusMessage = null)}
        class="text-zinc-400 hover:text-zinc-200 text-xs underline cursor-pointer ml-4 shrink-0"
      >
        Закрыть
      </button>
    </div>
  {/if}

  <div class="flex items-center justify-between p-4 rounded-xl bg-[#131419] border border-[#20222a]">
    <div class="flex items-center gap-3">
      <div class="w-9 h-9 rounded-lg bg-[#221c17] flex items-center justify-center border border-[#3d2e20] shrink-0">
        <Wrench class="w-4 h-4 text-amber-400" />
      </div>
      <div>
        <p class="text-xs font-bold text-zinc-100">Аварийный ремонт и устранение сбоев в 1 клик</p>
        <p class="text-[11px] text-zinc-400">
          Быстрое восстановление штатных функций Windows без необходимости перезагрузки системы.
        </p>
      </div>
    </div>
  </div>

  <div class="grid grid-cols-2 gap-3">
    <!-- Display & MPO Repair -->
    <div class="p-4 rounded-xl bg-[#131419] border border-[#20222a] hover:border-[#2b2e3b] transition-colors flex flex-col justify-between space-y-4">
      <div class="space-y-1.5">
        <div class="flex items-center gap-2">
          <MonitorOff class="w-4 h-4 text-amber-400 shrink-0" />
          <span class="text-xs font-bold text-zinc-200">Ремонт дисплея и мерцания MPO</span>
        </div>
        <p class="text-[11px] text-zinc-400 leading-relaxed">
          Мгновенно перезапускает DWM-слои, устраняет мерцание экрана в RDR2 / Deadlock и калибрует FreeSync 180Hz.
        </p>
      </div>
      <button
        type="button"
        onclick={() => triggerRepair('display')}
        disabled={runningRepair !== null}
        class="w-full flex items-center justify-center gap-2 py-2.5 px-3 rounded-lg text-xs font-bold bg-[#1c1e26] hover:bg-[#252834] text-zinc-200 border border-[#2c2f3d] transition-all cursor-pointer active:scale-[0.99] disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {#if runningRepair === 'display'}
          <RefreshCw class="w-3.5 h-3.5 animate-spin" />
          <span>Сброс слоев DWM...</span>
        {:else}
          <span>Выполнить сброс дисплея</span>
        {/if}
      </button>
    </div>

    <!-- Windows Search & Services Repair -->
    <div class="p-4 rounded-xl bg-[#131419] border border-[#20222a] hover:border-[#2b2e3b] transition-colors flex flex-col justify-between space-y-4">
      <div class="space-y-1.5">
        <div class="flex items-center gap-2">
          <Search class="w-4 h-4 text-sky-400 shrink-0" />
          <span class="text-xs font-bold text-zinc-200">Ремонт поиска, скриншотов и служб</span>
        </div>
        <p class="text-[11px] text-zinc-400 leading-relaxed">
          Восстанавливает Windows Search (Win), «Ножницы» (PrtSc / CaptureService / cbdhsvc), права AppContainer, печать и SysMain.
        </p>
      </div>
      <button
        type="button"
        onclick={() => triggerRepair('services')}
        disabled={runningRepair !== null}
        class="w-full flex items-center justify-center gap-2 py-2.5 px-3 rounded-lg text-xs font-bold bg-[#1c1e26] hover:bg-[#252834] text-zinc-200 border border-[#2c2f3d] transition-all cursor-pointer active:scale-[0.99] disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {#if runningRepair === 'services'}
          <RefreshCw class="w-3.5 h-3.5 animate-spin" />
          <span>Восстановление служб...</span>
        {:else}
          <span>Восстановить службы и поиск</span>
        {/if}
      </button>
    </div>

    <!-- Shader Cache Flush -->
    <div class="p-4 rounded-xl bg-[#131419] border border-[#20222a] hover:border-[#2b2e3b] transition-colors flex flex-col justify-between space-y-4">
      <div class="space-y-1.5">
        <div class="flex items-center gap-2">
          <HardDrive class="w-4 h-4 text-emerald-400 shrink-0" />
          <span class="text-xs font-bold text-zinc-200">Очистка кэша шейдеров GPU</span>
        </div>
        <p class="text-[11px] text-zinc-400 leading-relaxed">
          Удаляет поврежденные кэши DirectX и AMD Radeon (`DxCache`, `D3DSCache`) для устранения микростаттеров в играх.
        </p>
      </div>
      <button
        type="button"
        onclick={() => triggerRepair('shaders')}
        disabled={runningRepair !== null}
        class="w-full flex items-center justify-center gap-2 py-2.5 px-3 rounded-lg text-xs font-bold bg-[#1c1e26] hover:bg-[#252834] text-zinc-200 border border-[#2c2f3d] transition-all cursor-pointer active:scale-[0.99] disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {#if runningRepair === 'shaders'}
          <RefreshCw class="w-3.5 h-3.5 animate-spin" />
          <span>Очистка кэшей...</span>
        {:else}
          <span>Очистить кэш шейдеров</span>
        {/if}
      </button>
    </div>

    <!-- Test Suite Verification -->
    <div class="p-4 rounded-xl bg-[#131419] border border-[#20222a] hover:border-[#2b2e3b] transition-colors flex flex-col justify-between space-y-4">
      <div class="space-y-1.5">
        <div class="flex items-center gap-2">
          <ShieldAlert class="w-4 h-4 text-indigo-400 shrink-0" />
          <span class="text-xs font-bold text-zinc-200">Верификация ядра (260 тестов)</span>
        </div>
        <p class="text-[11px] text-zinc-400 leading-relaxed">
          Автоматический запуск Verify-UniversalEngine.ps1 для мгновенной валидации всех реестров и модулей.
        </p>
      </div>
      <button
        type="button"
        onclick={() => triggerRepair('verify')}
        disabled={runningRepair !== null}
        class="w-full flex items-center justify-center gap-2 py-2.5 px-3 rounded-lg text-xs font-bold bg-[#1c1e26] hover:bg-[#252834] text-zinc-200 border border-[#2c2f3d] transition-all cursor-pointer active:scale-[0.99] disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {#if runningRepair === 'verify'}
          <RefreshCw class="w-3.5 h-3.5 animate-spin" />
          <span>Прогон 260 тестов...</span>
        {:else}
          <span>Запустить тест движка</span>
        {/if}
      </button>
    </div>
  </div>
</div>
