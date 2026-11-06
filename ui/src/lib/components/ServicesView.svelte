<script lang="ts">
  import { Filter, Search, ShieldCheck } from '@lucide/svelte';
  import type { ServiceItem } from '../types';

  // Sample real services directly from services_blacklist.json & system engine
  const defaultServices: ServiceItem[] = [
    { name: 'DiagTrack', reason: 'Connected User Experiences and Telemetry', category: 'telemetry', status: 'Disabled' },
    { name: 'dmwappushservice', reason: 'WAP Push Message Routing Service (Telemetry)', category: 'telemetry', status: 'Disabled' },
    { name: 'WSearch', reason: 'Windows Search (Отключается только во время игры, восстанавливается при выходе)', category: 'system', status: 'Stopped' },
    { name: 'SysMain', reason: 'SuperFetch / Prefetcher (Защищен от повреждения снимков)', category: 'system', status: 'Stopped' },
    { name: 'Spooler', reason: 'Диспетчер очереди печати (Print Spooler)', category: 'printing', status: 'Disabled' },
    { name: 'PrintNotify', reason: 'Printer Extensions and Notifications', category: 'printing', status: 'Disabled' },
    { name: 'Fax', reason: 'Служба факсов', category: 'printing', status: 'Disabled' },
    { name: 'XblAuthManager', reason: 'Диспетчер аутентификации Xbox Live', category: 'gaming', status: 'Disabled' },
    { name: 'XblGameSave', reason: 'Служба сохранений Xbox Live в облаке', category: 'gaming', status: 'Disabled' },
    { name: 'XboxNetApiSvc', reason: 'Сетевая служба Xbox Live', category: 'gaming', status: 'Disabled' },
    { name: 'MapsBroker', reason: 'Диспетчер загруженных карт', category: 'network', status: 'Disabled' },
    { name: 'RemoteRegistry', reason: 'Удаленный реестр', category: 'network', status: 'Disabled' },
    { name: 'TroubleshootingSvc', reason: 'Рекомендуемое устранение неполадок', category: 'system', status: 'Disabled' },
    { name: 'RetailDemo', reason: 'Служба демонстрации для розничной торговли', category: 'telemetry', status: 'Disabled' },
    { name: 'WerSvc', reason: 'Служба регистрации ошибок Windows (WER)', category: 'telemetry', status: 'Disabled' },
    { name: 'wisvc', reason: 'Служба программы предварительной оценки Windows (Insider)', category: 'telemetry', status: 'Disabled' },
    { name: 'SensorService', reason: 'Служба датчиков ориентации и освещения', category: 'system', status: 'Disabled' },
    { name: 'SensrSvc', reason: 'Служба наблюдения за датчиками', category: 'system', status: 'Disabled' },
    { name: 'SharedAccess', reason: 'Общий доступ к подключению к Интернету (ICS)', category: 'network', status: 'Disabled' },
    { name: 'DusmSvc', reason: 'Использование данных (Data Usage)', category: 'network', status: 'Disabled' },
  ];

  let searchQuery = $state('');
  let selectedCategory = $state<'all' | 'telemetry' | 'printing' | 'gaming' | 'network' | 'system'>('all');

  const filteredServices = $derived(
    defaultServices.filter((s) => {
      const matchesSearch =
        s.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
        s.reason.toLowerCase().includes(searchQuery.toLowerCase());
      const matchesCat = selectedCategory === 'all' || s.category === selectedCategory;
      return matchesSearch && matchesCat;
    })
  );
</script>

<div class="space-y-4">
  <!-- Top Stats & Protection Banner -->
  <div class="flex items-center justify-between p-4 rounded-xl bg-[#131419] border border-[#20222a]">
    <div class="flex items-center gap-3">
      <div class="w-9 h-9 rounded-lg bg-emerald-950/60 flex items-center justify-center border border-emerald-800/50 shadow-sm shrink-0">
        <ShieldCheck class="w-4 h-4 text-emerald-400" />
      </div>
      <div>
        <p class="text-xs font-bold text-zinc-100">207 системных служб под контролем движка</p>
        <p class="text-[11px] text-zinc-400">
          Защищены: аудио, видеодрайвер, сеть, «Ножницы» (PrtSc / CaptureService / cbdhsvc), EasyAntiCheat, BattlEye и Vanguard.
        </p>
      </div>
    </div>
  </div>

  <!-- Search & Category Filters -->
  <div class="flex items-center gap-3">
    <!-- Search Bar -->
    <div class="relative flex-1">
      <Search class="w-3.5 h-3.5 text-zinc-500 absolute left-3.5 top-1/2 -translate-y-1/2" />
      <input
        type="text"
        bind:value={searchQuery}
        placeholder="Поиск по имени службы или описанию..."
        class="w-full pl-9 pr-3.5 py-2 text-xs bg-[#131418] border border-[#22242c] rounded-xl text-zinc-200 placeholder-zinc-500 focus:outline-none focus:border-emerald-500/60 focus:ring-1 focus:ring-emerald-500/30 transition-all"
      />
    </div>

    <!-- Category Pills -->
    <div class="flex items-center gap-1 text-xs bg-[#121316] p-1 rounded-xl border border-[#202127]">
      <button
        type="button"
        onclick={() => (selectedCategory = 'all')}
        class="px-2.5 py-1 rounded-lg text-[11px] font-medium transition-all cursor-pointer {selectedCategory === 'all'
          ? 'bg-[#20222a] text-white shadow-sm'
          : 'text-zinc-400 hover:text-zinc-200'}"
      >
        Все
      </button>
      <button
        type="button"
        onclick={() => (selectedCategory = 'telemetry')}
        class="px-2.5 py-1 rounded-lg text-[11px] font-medium transition-all cursor-pointer {selectedCategory === 'telemetry'
          ? 'bg-[#20222a] text-white shadow-sm'
          : 'text-zinc-400 hover:text-zinc-200'}"
      >
        Телеметрия
      </button>
      <button
        type="button"
        onclick={() => (selectedCategory = 'printing')}
        class="px-2.5 py-1 rounded-lg text-[11px] font-medium transition-all cursor-pointer {selectedCategory === 'printing'
          ? 'bg-[#20222a] text-white shadow-sm'
          : 'text-zinc-400 hover:text-zinc-200'}"
      >
        Печать
      </button>
      <button
        type="button"
        onclick={() => (selectedCategory = 'gaming')}
        class="px-2.5 py-1 rounded-lg text-[11px] font-medium transition-all cursor-pointer {selectedCategory === 'gaming'
          ? 'bg-[#20222a] text-white shadow-sm'
          : 'text-zinc-400 hover:text-zinc-200'}"
      >
        Xbox
      </button>
      <button
        type="button"
        onclick={() => (selectedCategory = 'network')}
        class="px-2.5 py-1 rounded-lg text-[11px] font-medium transition-all cursor-pointer {selectedCategory === 'network'
          ? 'bg-[#20222a] text-white shadow-sm'
          : 'text-zinc-400 hover:text-zinc-200'}"
      >
        Сеть
      </button>
    </div>
  </div>

  <!-- Services Table / List -->
  <div class="rounded-xl border border-[#20222a] bg-[#121317] overflow-hidden shadow-sm">
    <div class="grid grid-cols-12 px-4 py-2.5 text-[11px] font-bold uppercase tracking-wider text-zinc-400 border-b border-[#1f2027] bg-[#101115]">
      <span class="col-span-3">Служба</span>
      <span class="col-span-6">Назначение / Причина отключения</span>
      <span class="col-span-2">Категория</span>
      <span class="col-span-1 text-right">Статус</span>
    </div>

    <div class="max-h-[320px] overflow-y-auto divide-y divide-[#1b1c22]">
      {#each filteredServices as s}
        <div class="grid grid-cols-12 px-4 py-2.5 text-xs items-center hover:bg-[#161820] transition-colors">
          <span class="col-span-3 font-mono font-medium text-zinc-200">{s.name}</span>
          <span class="col-span-6 text-zinc-400 truncate pr-4 text-[11px]">{s.reason}</span>
          <span class="col-span-2 text-zinc-500 capitalize text-[11px]">{s.category}</span>
          <div class="col-span-1 flex justify-end">
            <span
              class="px-2 py-0.5 rounded text-[10px] font-semibold tracking-wide {s.status === 'Disabled'
                ? 'bg-rose-950/40 text-rose-400 border border-rose-900/40'
                : 'bg-amber-950/40 text-amber-400 border border-amber-900/40'}"
            >
              {s.status}
            </span>
          </div>
        </div>
      {:else}
        <div class="py-10 text-center text-xs text-zinc-500">
          Службы по запросу "{searchQuery}" не найдены
        </div>
      {/each}
    </div>
  </div>
</div>
