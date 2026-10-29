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

  let runningRepair = $state<string | null>(null);
  let statusMessage = $state<{ type: 'success' | 'error'; text: string } | null>(null);

  async function triggerRepair(repairType: 'display' | 'services' | 'shaders' | 'verify') {
    runningRepair = repairType;
    statusMessage = null;

    try {
      const res = await executeEmergencyRepair(repairType);
      statusMessage = {
        type: res.success ? 'success' : 'error',
        text: res.message,
      };
    } catch (e: any) {
      statusMessage = {
        type: 'error',
        text: `Ошибка выполнения: ${e?.message || e}`,
      };
    } finally {
      runningRepair = null;
    }
  }
</script>

<div class="space-y-4">
  <!-- Status Banner if repair executed -->
  {#if statusMessage}
    <div
      class="p-3.5 rounded-lg border flex items-center justify-between text-xs {statusMessage.type === 'success'
        ? 'bg-emerald-950/40 border-emerald-800/60 text-emerald-300'
        : 'bg-rose-950/40 border-rose-800/60 text-rose-300'}"
    >
      <div class="flex items-center gap-2">
        {#if statusMessage.type === 'success'}
          <CheckCircle class="w-4 h-4 text-emerald-400" />
        {:else}
          <AlertTriangle class="w-4 h-4 text-rose-400" />
        {/if}
        <span>{statusMessage.text}</span>
      </div>
      <button
        onclick={() => (statusMessage = null)}
        class="text-zinc-500 hover:text-zinc-300 text-[11px] underline"
      >
        Закрыть
      </button>
    </div>
  {/if}

  <div class="flex items-center justify-between p-3.5 rounded-lg bg-[#14151a] border border-[#22242c]">
    <div class="flex items-center gap-2.5">
      <div class="w-8 h-8 rounded-md bg-[#221c17] flex items-center justify-center border border-[#3d2e20]">
        <Wrench class="w-4 h-4 text-amber-400" />
      </div>
      <div>
        <p class="text-xs font-semibold text-zinc-200">Аварийный ремонт и устранение сбоев в 1 клик</p>
        <p class="text-[11px] text-zinc-400">
          Быстрое исправление типичных проблем Windows без необходимости перезагрузки системы.
        </p>
      </div>
    </div>
  </div>

  <div class="grid grid-cols-2 gap-3">
    <!-- Display & MPO Repair -->
    <div class="p-4 rounded-lg bg-[#14151a] border border-[#22242c] flex flex-col justify-between space-y-4">
      <div class="space-y-1.5">
        <div class="flex items-center gap-2">
          <MonitorOff class="w-4 h-4 text-amber-400" />
          <span class="text-xs font-semibold text-zinc-200">Ремонт дисплея и мерцания MPO</span>
        </div>
        <p class="text-[11px] text-zinc-400 leading-relaxed">
          Мгновенно перезапускает DWM-слои, исправляет мерцание экрана в RDR2 / Deadlock и калибрует FreeSync 180Hz.
        </p>
      </div>
      <button
        onclick={() => triggerRepair('display')}
        disabled={runningRepair !== null}
        class="w-full flex items-center justify-center gap-2 py-2 px-3 rounded-lg text-xs font-semibold bg-[#1c1e25] hover:bg-[#252832] text-zinc-200 border border-[#2e313d] transition-all active:scale-[0.99] disabled:opacity-50"
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
    <div class="p-4 rounded-lg bg-[#14151a] border border-[#22242c] flex flex-col justify-between space-y-4">
      <div class="space-y-1.5">
        <div class="flex items-center gap-2">
          <Search class="w-4 h-4 text-sky-400" />
          <span class="text-xs font-semibold text-zinc-200">Ремонт поиска и служб Windows</span>
        </div>
        <p class="text-[11px] text-zinc-400 leading-relaxed">
          Проверяет и принудительно восстанавливает Windows Search (кнопка Win), диспетчер печати и SysMain в рабочий режим.
        </p>
      </div>
      <button
        onclick={() => triggerRepair('services')}
        disabled={runningRepair !== null}
        class="w-full flex items-center justify-center gap-2 py-2 px-3 rounded-lg text-xs font-semibold bg-[#1c1e25] hover:bg-[#252832] text-zinc-200 border border-[#2e313d] transition-all active:scale-[0.99] disabled:opacity-50"
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
    <div class="p-4 rounded-lg bg-[#14151a] border border-[#22242c] flex flex-col justify-between space-y-4">
      <div class="space-y-1.5">
        <div class="flex items-center gap-2">
          <HardDrive class="w-4 h-4 text-emerald-400" />
          <span class="text-xs font-semibold text-zinc-200">Очистка кэша шейдеров GPU</span>
        </div>
        <p class="text-[11px] text-zinc-400 leading-relaxed">
          Удаляет поврежденные кэши DirectX и AMD Radeon (`DxCache`, `D3DSCache`) для устранения статтеров в играх.
        </p>
      </div>
      <button
        onclick={() => triggerRepair('shaders')}
        disabled={runningRepair !== null}
        class="w-full flex items-center justify-center gap-2 py-2 px-3 rounded-lg text-xs font-semibold bg-[#1c1e25] hover:bg-[#252832] text-zinc-200 border border-[#2e313d] transition-all active:scale-[0.99] disabled:opacity-50"
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
    <div class="p-4 rounded-lg bg-[#14151a] border border-[#22242c] flex flex-col justify-between space-y-4">
      <div class="space-y-1.5">
        <div class="flex items-center gap-2">
          <ShieldAlert class="w-4 h-4 text-indigo-400" />
          <span class="text-xs font-semibold text-zinc-200">Верификация ядра (252 теста)</span>
        </div>
        <p class="text-[11px] text-zinc-400 leading-relaxed">
          Автоматический запуск Verify-UniversalEngine.ps1 для мгновенной валидации всех реестров и модулей.
        </p>
      </div>
      <button
        onclick={() => triggerRepair('verify')}
        disabled={runningRepair !== null}
        class="w-full flex items-center justify-center gap-2 py-2 px-3 rounded-lg text-xs font-semibold bg-[#1c1e25] hover:bg-[#252832] text-zinc-200 border border-[#2e313d] transition-all active:scale-[0.99] disabled:opacity-50"
      >
        {#if runningRepair === 'verify'}
          <RefreshCw class="w-3.5 h-3.5 animate-spin" />
          <span>Прогон 252 тестов...</span>
        {:else}
          <span>Запустить тест движка</span>
        {/if}
      </button>
    </div>
  </div>
</div>
