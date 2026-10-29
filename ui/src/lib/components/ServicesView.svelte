<script lang="ts">
  import { Check, Filter, Search, ShieldCheck } from '@lucide/svelte';
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
  <div class="flex items-center justify-between p-3.5 rounded-lg bg-[#14151a] border border-[#22242c]">
    <div class="flex items-center gap-2.5">
      <div class="w-8 h-8 rounded-md bg-emerald-950/50 flex items-center justify-center border border-emerald-800/40">
        <ShieldCheck class="w-4 h-4 text-emerald-400" />
      </div>
      <div>
        <p class="text-xs font-semibold text-zinc-200">212 системных служб под контролем ядра</p>
        <p class="text-[11px] text-zinc-400">
          Критические службы защищены: аудио, дисплей, сеть, EasyAntiCheat, BattlEye и Vanguard никогда не затрагиваются.
        </p>
      </div>
    </div>
  </div>

  <!-- Search & Category Filters -->
  <div class="flex items-center gap-3">
    <!-- Search Bar -->
    <div class="relative flex-1">
      <Search class="w-3.5 h-3.5 text-zinc-500 absolute left-3 top-1/2 -translate-y-1/2" />
      <input
        type="text"
        bind:value={searchQuery}
        placeholder="Поиск по имени службы или описанию..."
        class="w-full pl-9 pr-3 py-2 text-xs bg-[#131418] border border-[#22242c] rounded-lg text-zinc-200 placeholder-zinc-500 focus:outline-none focus:border-zinc-500 transition-colors"
      />
    </div>

    <!-- Category Pills -->
    <div class="flex items-center gap-1.5 text-xs bg-[#121316] p-1 rounded-lg border border-[#202127]">
      <button
        onclick={() => (selectedCategory = 'all')}
        class="px-2.5 py-1 rounded text-[11px] font-medium transition-colors {selectedCategory === 'all'
          ? 'bg-[#22242c] text-zinc-100'
          : 'text-zinc-400 hover:text-zinc-200'}"
      >
        Все
      </button>
      <button
        onclick={() => (selectedCategory = 'telemetry')}
        class="px-2.5 py-1 rounded text-[11px] font-medium transition-colors {selectedCategory === 'telemetry'
          ? 'bg-[#22242c] text-zinc-100'
          : 'text-zinc-400 hover:text-zinc-200'}"
      >
        Телеметрия
      </button>
      <button
        onclick={() => (selectedCategory = 'printing')}
        class="px-2.5 py-1 rounded text-[11px] font-medium transition-colors {selectedCategory === 'printing'
          ? 'bg-[#22242c] text-zinc-100'
          : 'text-zinc-400 hover:text-zinc-200'}"
      >
        Печать
      </button>
      <button
        onclick={() => (selectedCategory = 'gaming')}
        class="px-2.5 py-1 rounded text-[11px] font-medium transition-colors {selectedCategory === 'gaming'
          ? 'bg-[#22242c] text-zinc-100'
          : 'text-zinc-400 hover:text-zinc-200'}"
      >
        Xbox
      </button>
      <button
        onclick={() => (selectedCategory = 'network')}
        class="px-2.5 py-1 rounded text-[11px] font-medium transition-colors {selectedCategory === 'network'
          ? 'bg-[#22242c] text-zinc-100'
          : 'text-zinc-400 hover:text-zinc-200'}"
      >
        Сеть
      </button>
    </div>
  </div>

  <!-- Services Table / List -->
  <div class="rounded-lg border border-[#22242c] bg-[#131418] overflow-hidden">
    <div class="grid grid-cols-12 px-4 py-2 text-[11px] font-medium uppercase tracking-wider text-zinc-400 border-b border-[#202229] bg-[#111215]">
      <span class="col-span-3">Служба</span>
      <span class="col-span-6">Назначение / Причина отключения</span>
      <span class="col-span-2">Категория</span>
      <span class="col-span-1 text-right">Статус</span>
    </div>

    <div class="max-h-[300px] overflow-y-auto divide-y divide-[#1c1d23]">
      {#each filteredServices as s}
        <div class="grid grid-cols-12 px-4 py-2.5 text-xs items-center hover:bg-[#17181f] transition-colors">
          <span class="col-span-3 font-mono font-medium text-zinc-200">{s.name}</span>
          <span class="col-span-6 text-zinc-400 truncate pr-4 text-[11px]">{s.reason}</span>
          <span class="col-span-2 text-zinc-500 capitalize text-[11px]">{s.category}</span>
          <div class="col-span-1 flex justify-end">
            <span
              class="px-1.5 py-0.5 rounded text-[10px] font-medium {s.status === 'Disabled'
                ? 'bg-rose-950/40 text-rose-400 border border-rose-900/40'
                : 'bg-amber-950/40 text-amber-400 border border-amber-900/40'}"
            >
              {s.status}
            </span>
          </div>
        </div>
      {:else}
        <div class="py-8 text-center text-xs text-zinc-500">
          Службы по запросу "{searchQuery}" не найдены
        </div>
      {/each}
    </div>
  </div>
</div>
