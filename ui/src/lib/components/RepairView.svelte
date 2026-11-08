<script lang="ts">
  import {
    AlertTriangle,
    CheckCircle,
    Cpu,
    HardDrive,
    MonitorOff,
    RefreshCw,
    RotateCcw,
    Search,
    ShieldAlert,
    Sparkles,
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

  async function triggerRepair(
    repairType:
      | 'display'
      | 'services'
      | 'shaders'
      | 'verify'
      | 'memory'
      | 'debloat'
      | 'restore_debloat'
  ) {
    runningRepair = repairType;
    statusMessage = null;
    onLog?.('info', `Запуск операции обслуживания [${repairType}]...`);

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
  {#if statusMessage}
    <div
      class="p-4 rounded-xl border flex items-center justify-between text-xs transition-all"
      style="
        background-color: {statusMessage.type === 'success'
        ? 'var(--active-soft)'
        : 'var(--danger-soft)'};
        border-color: {statusMessage.type === 'success'
        ? 'var(--active-border)'
        : 'var(--danger-border)'};
        color: var(--text-primary);
      "
    >
      <div class="flex items-center gap-2.5">
        {#if statusMessage.type === 'success'}
          <CheckCircle class="w-4 h-4 shrink-0" style="color: var(--active-primary);" />
        {:else}
          <AlertTriangle class="w-4 h-4 shrink-0" style="color: var(--danger-primary);" />
        {/if}
        <span class="font-medium leading-relaxed">{statusMessage.text}</span>
      </div>
      <button
        type="button"
        onclick={() => (statusMessage = null)}
        class="text-xs underline cursor-pointer ml-4 shrink-0"
        style="color: var(--text-secondary);"
      >
        Закрыть
      </button>
    </div>
  {/if}

  <div
    class="flex items-center justify-between p-4 rounded-xl border"
    style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
  >
    <div class="flex items-center gap-3">
      <div
        class="w-9 h-9 rounded-lg flex items-center justify-center border shrink-0"
        style="background-color: var(--warn-soft); border-color: var(--warn-border);"
      >
        <Wrench class="w-4 h-4" style="color: var(--warn-primary);" />
      </div>
      <div>
        <p class="text-xs font-semibold" style="color: var(--text-primary);">
          Обслуживание и восстановление компонентов Windows
        </p>
        <p class="text-[11px]" style="color: var(--text-secondary);">
          Инструменты для точечного сброса видеоконвейера, восстановления поиска, очистки кэшей и проверки целостности.
        </p>
      </div>
    </div>
  </div>

  <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
    <!-- 1. Display & MPO Repair -->
    <div
      class="p-4 rounded-xl border flex flex-col justify-between space-y-4"
      style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
    >
      <div class="space-y-1.5">
        <div class="flex items-center gap-2">
          <MonitorOff class="w-4 h-4 shrink-0" style="color: var(--warn-primary);" />
          <span class="text-xs font-semibold" style="color: var(--text-primary);">
            Сброс видеоконвейера и защита от мерцания MPO
          </span>
        </div>
        <p class="text-[11px] leading-relaxed" style="color: var(--text-secondary);">
          Удаляет устаревшие переопределения OverlayTestMode и DisableOverlays, очищает кэш топологии DisplayPort/HDMI и перезапускает DWM.
        </p>
      </div>
      <button
        type="button"
        onclick={() => triggerRepair('display')}
        disabled={runningRepair !== null}
        class="w-full flex items-center justify-center gap-2 py-2.5 px-3 rounded-lg text-xs font-semibold border transition-colors cursor-pointer disabled:opacity-50"
        style="background-color: var(--bg-elevated); border-color: var(--border-subtle); color: var(--text-primary);"
      >
        {#if runningRepair === 'display'}
          <RefreshCw class="w-3.5 h-3.5 animate-spin" />
          <span>Сброс конвейера дисплея...</span>
        {:else}
          <span>Выполнить сброс дисплея</span>
        {/if}
      </button>
    </div>

    <!-- 2. Windows Search & Core Services Repair -->
    <div
      class="p-4 rounded-xl border flex flex-col justify-between space-y-4"
      style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
    >
      <div class="space-y-1.5">
        <div class="flex items-center gap-2">
          <Search class="w-4 h-4 shrink-0" style="color: var(--accent-primary);" />
          <span class="text-xs font-semibold" style="color: var(--text-primary);">
            Восстановление поиска, скриншотов и базовых служб
          </span>
        </div>
        <p class="text-[11px] leading-relaxed" style="color: var(--text-secondary);">
          Восстанавливает Windows Search, «Ножницы» (PrtSc / CaptureService / cbdhsvc), права AppContainer, диспетчер печати и аудиослужбы.
        </p>
      </div>
      <button
        type="button"
        onclick={() => triggerRepair('services')}
        disabled={runningRepair !== null}
        class="w-full flex items-center justify-center gap-2 py-2.5 px-3 rounded-lg text-xs font-semibold border transition-colors cursor-pointer disabled:opacity-50"
        style="background-color: var(--bg-elevated); border-color: var(--border-subtle); color: var(--text-primary);"
      >
        {#if runningRepair === 'services'}
          <RefreshCw class="w-3.5 h-3.5 animate-spin" />
          <span>Восстановление служб...</span>
        {:else}
          <span>Восстановить службы и поиск</span>
        {/if}
      </button>
    </div>

    <!-- 3. Shader Cache Flush -->
    <div
      class="p-4 rounded-xl border flex flex-col justify-between space-y-4"
      style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
    >
      <div class="space-y-1.5">
        <div class="flex items-center gap-2">
          <HardDrive class="w-4 h-4 shrink-0" style="color: var(--active-primary);" />
          <span class="text-xs font-semibold" style="color: var(--text-primary);">
            Очистка кэша шейдеров видеокарты
          </span>
        </div>
        <p class="text-[11px] leading-relaxed" style="color: var(--text-secondary);">
          Очищает кэши шейдеров DirectX, Vulkan и драйвера GPU (DxCache, D3DSCache, GLCache) для устранения статтеров после обновления игр.
        </p>
      </div>
      <button
        type="button"
        onclick={() => triggerRepair('shaders')}
        disabled={runningRepair !== null}
        class="w-full flex items-center justify-center gap-2 py-2.5 px-3 rounded-lg text-xs font-semibold border transition-colors cursor-pointer disabled:opacity-50"
        style="background-color: var(--bg-elevated); border-color: var(--border-subtle); color: var(--text-primary);"
      >
        {#if runningRepair === 'shaders'}
          <RefreshCw class="w-3.5 h-3.5 animate-spin" />
          <span>Очистка кэшей...</span>
        {:else}
          <span>Очистить кэш шейдеров</span>
        {/if}
      </button>
    </div>

    <!-- 4. Standby RAM Purge -->
    <div
      class="p-4 rounded-xl border flex flex-col justify-between space-y-4"
      style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
    >
      <div class="space-y-1.5">
        <div class="flex items-center gap-2">
          <Cpu class="w-4 h-4 shrink-0" style="color: var(--accent-primary);" />
          <span class="text-xs font-semibold" style="color: var(--text-primary);">
            Очистка резервного кэша ОЗУ (Standby List)
          </span>
        </div>
        <p class="text-[11px] leading-relaxed" style="color: var(--text-secondary);">
          Освобождает рабочие наборы фоновых процессов и очищает резервный список страниц памяти перед запуском ресурсоёмких игр.
        </p>
      </div>
      <button
        type="button"
        onclick={() => triggerRepair('memory')}
        disabled={runningRepair !== null}
        class="w-full flex items-center justify-center gap-2 py-2.5 px-3 rounded-lg text-xs font-semibold border transition-colors cursor-pointer disabled:opacity-50"
        style="background-color: var(--bg-elevated); border-color: var(--border-subtle); color: var(--text-primary);"
      >
        {#if runningRepair === 'memory'}
          <RefreshCw class="w-3.5 h-3.5 animate-spin" />
          <span>Очистка памяти...</span>
        {:else}
          <span>Очистить кэш ОЗУ</span>
        {/if}
      </button>
    </div>

    <!-- 5. Windows 11 Debloat & Restore -->
    <div
      class="p-4 rounded-xl border flex flex-col justify-between space-y-4"
      style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
    >
      <div class="space-y-1.5">
        <div class="flex items-center gap-2">
          <Sparkles class="w-4 h-4 shrink-0" style="color: var(--accent-primary);" />
          <span class="text-xs font-semibold" style="color: var(--text-primary);">
            Отключение фоновых компонентов Windows 11
          </span>
        </div>
        <p class="text-[11px] leading-relaxed" style="color: var(--text-secondary);">
          Отключает фоновую активность Xbox GameBar/PresenceWriter, Edge Startup Boost, Copilot, Recall и рекламные рекомендации в меню «Пуск».
        </p>
      </div>
      <div class="flex items-center gap-2">
        <button
          type="button"
          onclick={() => triggerRepair('debloat')}
          disabled={runningRepair !== null}
          class="flex-1 flex items-center justify-center gap-1.5 py-2.5 px-3 rounded-lg text-xs font-semibold border transition-colors cursor-pointer disabled:opacity-50"
          style="background-color: var(--bg-elevated); border-color: var(--border-subtle); color: var(--text-primary);"
        >
          {#if runningRepair === 'debloat'}
            <RefreshCw class="w-3.5 h-3.5 animate-spin" />
            <span>Применение...</span>
          {:else}
            <span>Применить очистку</span>
          {/if}
        </button>
        <button
          type="button"
          onclick={() => triggerRepair('restore_debloat')}
          disabled={runningRepair !== null}
          class="flex items-center justify-center gap-1.5 py-2.5 px-3 rounded-lg text-xs font-medium border transition-colors cursor-pointer disabled:opacity-50"
          style="background-color: var(--bg-surface); border-color: var(--border-subtle); color: var(--text-secondary);"
          title="Вернуть стандартные параметры Windows 11"
        >
          {#if runningRepair === 'restore_debloat'}
            <RefreshCw class="w-3.5 h-3.5 animate-spin" />
          {:else}
            <RotateCcw class="w-3.5 h-3.5" />
            <span>Сброс</span>
          {/if}
        </button>
      </div>
    </div>

    <!-- 6. Self-Verification Suite -->
    <div
      class="p-4 rounded-xl border flex flex-col justify-between space-y-4"
      style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
    >
      <div class="space-y-1.5">
        <div class="flex items-center gap-2">
          <ShieldAlert class="w-4 h-4 shrink-0" style="color: var(--active-primary);" />
          <span class="text-xs font-semibold" style="color: var(--text-primary);">
            Самодиагностика модулей (Verify-UniversalEngine.ps1)
          </span>
        </div>
        <p class="text-[11px] leading-relaxed" style="color: var(--text-secondary);">
          Запускает встроенный набор автоматических проверок синтаксиса, профилей оборудования, белого списка служб и целостности реестра.
        </p>
      </div>
      <button
        type="button"
        onclick={() => triggerRepair('verify')}
        disabled={runningRepair !== null}
        class="w-full flex items-center justify-center gap-2 py-2.5 px-3 rounded-lg text-xs font-semibold border transition-colors cursor-pointer disabled:opacity-50"
        style="background-color: var(--bg-elevated); border-color: var(--border-subtle); color: var(--text-primary);"
      >
        {#if runningRepair === 'verify'}
          <RefreshCw class="w-3.5 h-3.5 animate-spin" />
          <span>Выполнение самодиагностики...</span>
        {:else}
          <span>Запустить проверку целостности</span>
        {/if}
      </button>
    </div>
  </div>
</div>
