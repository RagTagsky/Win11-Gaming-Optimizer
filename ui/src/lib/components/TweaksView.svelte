<script lang="ts">
  import { Check, Sliders, Sparkles } from '@lucide/svelte';
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
      description: 'Снятие ограничения сетевых пакетов Windows при загрузке процессора для стабильного пинга.',
      category: 'network',
      enabled: true,
      recommended: true,
    },
    {
      id: 'gpu_priority',
      title: 'Высокий системный приоритет GPU Scheduler',
      description: 'Приоритет потоков графического драйвера над системными фоновыми задачами.',
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
  <div class="flex items-center justify-between p-3.5 rounded-lg bg-[#14151a] border border-[#22242c]">
    <div class="flex items-center gap-2.5">
      <div class="w-8 h-8 rounded-md bg-[#1e2027] flex items-center justify-center border border-[#2c2e38]">
        <Sliders class="w-4 h-4 text-zinc-300" />
      </div>
      <div>
        <p class="text-xs font-semibold text-zinc-200">Тонкие системные твики задержки и рендеринга</p>
        <p class="text-[11px] text-zinc-400">
          Все параметры подобраны с учетом архитектуры Zen 3 (Ryzen 5600X) и RDNA 2 (Radeon RX 6600).
        </p>
      </div>
    </div>
  </div>

  <div class="grid grid-cols-2 gap-3">
    {#each tweaks as tweak}
      <div
        class="p-4 rounded-lg border transition-all flex flex-col justify-between {tweak.enabled
          ? 'bg-[#15161c] border-[#292b36]'
          : 'bg-[#121317] border-[#1d1e24] opacity-75'}"
      >
        <div class="space-y-1.5 mb-3">
          <div class="flex items-center justify-between">
            <span class="text-xs font-semibold text-zinc-200">{tweak.title}</span>
            {#if tweak.recommended}
              <span class="text-[10px] font-medium px-1.5 py-0.5 rounded bg-emerald-950/60 text-emerald-400 border border-emerald-900/50">
                REC
              </span>
            {/if}
          </div>
          <p class="text-[11px] text-zinc-400 leading-relaxed">{tweak.description}</p>
        </div>

        <div class="flex items-center justify-between pt-2 border-t border-[#1e2027]">
          <span class="text-[11px] text-zinc-500 capitalize">{tweak.category}</span>
          <button
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
