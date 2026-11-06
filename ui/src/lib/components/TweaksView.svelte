<script lang="ts">
  import { Sliders } from '@lucide/svelte';
  import type { TweakSetting } from '../types';

  let tweaks: TweakSetting[] = $state([
    {
      id: 'fse',
      title: 'Отключение Fullscreen Optimizations (FSE)',
      description: 'Игры получают монопольный доступ к видеобуферу с минимальным инпут-лагом.',
      category: 'display',
      enabled: true,
      recommended: true,
    },
    {
      id: 'mpo',
      title: 'Аппаратная защита Multiplane Overlay (MPO)',
      description: 'Предотвращает мерцание экрана в RDR2 и Deadlock без отключения FreeSync 180Hz.',
      category: 'display',
      enabled: true,
      recommended: true,
    },
    {
      id: 'dpc',
      title: 'DPC Latency Mode & Resilient Timers',
      description: 'Фиксация TSC-синхронизации и предотвращение скачков латентности прерываний.',
      category: 'latency',
      enabled: true,
      recommended: true,
    },
    {
      id: 'core_parking',
      title: '100% Unpark всех ядер Ryzen 5 5600X',
      description: 'Все 6 ядер и 12 потоков всегда активны, исключая микрозадержки пробуждения ядер.',
      category: 'power',
      enabled: true,
      recommended: true,
    },
    {
      id: 'mmcss',
      title: 'Отключение сетевого троттлинга MMCSS',
      description: 'Снятие ограничения сетевых пакетов Windows при нагрузке на процессор для минимального пинга.',
      category: 'network',
      enabled: true,
      recommended: true,
    },
    {
      id: 'gpu_priority',
      title: 'Высокий системный приоритет GPU Scheduler',
      description: 'Приоритет потоков графического драйвера над системными фоновыми процессами.',
      category: 'latency',
      enabled: true,
      recommended: true,
    },
  ]);

  function toggleTweak(id: string) {
    const tweak = tweaks.find((t) => t.id === id);
    if (tweak) {
      tweak.enabled = !tweak.enabled;
    }
  }
</script>

<div class="space-y-4">
  <div class="flex items-center justify-between p-4 rounded-xl bg-[#131419] border border-[#20222a]">
    <div class="flex items-center gap-3">
      <div class="w-9 h-9 rounded-lg bg-[#181a22] flex items-center justify-center border border-[#2a2d39] shrink-0">
        <Sliders class="w-4 h-4 text-zinc-300" />
      </div>
      <div>
        <p class="text-xs font-bold text-zinc-100">Тонкие системные твики задержки и рендеринга</p>
        <p class="text-[11px] text-zinc-400">
          Все параметры подобраны с учетом архитектуры Zen 3 (Ryzen 5600X) и RDNA 2 (Radeon RX 6600).
        </p>
      </div>
    </div>
  </div>

  <div class="grid grid-cols-2 gap-3">
    {#each tweaks as tweak}
      <div
        class="p-4 rounded-xl border transition-all duration-200 flex flex-col justify-between {tweak.enabled
          ? 'bg-[#14151b] border-[#252834]'
          : 'bg-[#111215] border-[#1c1d22] opacity-75'}"
      >
        <div class="space-y-1.5 mb-3">
          <div class="flex items-center justify-between gap-2">
            <span class="text-xs font-bold text-zinc-200">{tweak.title}</span>
            {#if tweak.recommended}
              <span class="text-[10px] font-bold px-1.5 py-0.5 rounded bg-emerald-950/70 text-emerald-400 border border-emerald-800/60 shrink-0">
                REC
              </span>
            {/if}
          </div>
          <p class="text-[11px] text-zinc-400 leading-relaxed">{tweak.description}</p>
        </div>

        <div class="flex items-center justify-between pt-2.5 border-t border-[#1e2027]">
          <span class="text-[11px] font-mono uppercase text-zinc-500">{tweak.category}</span>
          <button
            type="button"
            onclick={() => toggleTweak(tweak.id)}
            class="relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none {tweak.enabled
              ? 'bg-emerald-600'
              : 'bg-zinc-700'}"
            role="switch"
            aria-checked={tweak.enabled}
            aria-label={tweak.title}
          >
            <span
              class="pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out {tweak.enabled
                ? 'translate-x-4'
                : 'translate-x-0'}"
            ></span>
          </button>
        </div>
      </div>
    {/each}
  </div>
</div>
