<script lang="ts">
  import { onMount } from 'svelte';
  import { Search, ShieldCheck } from '@lucide/svelte';
  import { fetchServicesLists } from '../api';
  import type { BlacklistServiceItem } from '../types';

  let blacklist = $state<BlacklistServiceItem[]>([]);
  let whitelist = $state<string[]>([]);
  let viewMode = $state<'blacklist' | 'whitelist'>('blacklist');
  let searchQuery = $state('');
  let selectedCategory = $state<string>('all');

  onMount(async () => {
    try {
      const lists = await fetchServicesLists();
      blacklist = lists.blacklist;
      whitelist = lists.whitelist;
    } catch (e) {
      console.warn('Failed to load services lists:', e);
    }
  });

  const categories = $derived(() => {
    const set = new Set<string>();
    for (const item of blacklist) {
      if (item.Category) set.add(item.Category);
    }
    return ['all', ...Array.from(set)];
  });

  const filteredBlacklist = $derived(
    blacklist.filter((s) => {
      const q = searchQuery.trim().toLowerCase();
      const matchesSearch =
        !q ||
        s.Name.toLowerCase().includes(q) ||
        s.DisplayName.toLowerCase().includes(q) ||
        s.Reason.toLowerCase().includes(q);
      const matchesCat =
        selectedCategory === 'all' ||
        s.Category.toLowerCase() === selectedCategory.toLowerCase();
      return matchesSearch && matchesCat;
    })
  );

  const filteredWhitelist = $derived(
    whitelist.filter((name) => {
      const q = searchQuery.trim().toLowerCase();
      return !q || name.toLowerCase().includes(q);
    })
  );
</script>

<div class="space-y-4">
  <!-- Summary & Mode Switcher -->
  <div
    class="flex flex-col md:flex-row md:items-center justify-between gap-3 p-4 rounded-xl border"
    style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
  >
    <div class="flex items-center gap-3">
      <div
        class="w-9 h-9 rounded-lg flex items-center justify-center border shrink-0"
        style="background-color: var(--active-soft); border-color: var(--active-border);"
      >
        <ShieldCheck class="w-4 h-4" style="color: var(--active-primary);" />
      </div>
      <div>
        <p class="text-xs font-semibold" style="color: var(--text-primary);">
          Управление системными службами ({blacklist.length || 207} отключаемых · {whitelist.length || 90} защищённых)
        </p>
        <p class="text-[11px]" style="color: var(--text-secondary);">
          Звук, сеть, видеодрайвер, буфер обмена, «Ножницы» (CaptureService / cbdhsvc) и античиты защищены белым списком.
        </p>
      </div>
    </div>

    <div
      class="flex items-center gap-1 p-1 rounded-lg border shrink-0"
      style="background-color: var(--bg-elevated); border-color: var(--border-subtle);"
    >
      <button
        type="button"
        onclick={() => (viewMode = 'blacklist')}
        class="px-3 py-1 rounded-md text-xs font-medium transition-colors cursor-pointer"
        style="
          background-color: {viewMode === 'blacklist' ? 'var(--bg-surface)' : 'transparent'};
          color: {viewMode === 'blacklist' ? 'var(--text-primary)' : 'var(--text-secondary)'};
        "
      >
        Отключаемые ({blacklist.length || 207})
      </button>
      <button
        type="button"
        onclick={() => (viewMode = 'whitelist')}
        class="px-3 py-1 rounded-md text-xs font-medium transition-colors cursor-pointer"
        style="
          background-color: {viewMode === 'whitelist' ? 'var(--bg-surface)' : 'transparent'};
          color: {viewMode === 'whitelist' ? 'var(--text-primary)' : 'var(--text-secondary)'};
        "
      >
        Белый список ({whitelist.length || 90})
      </button>
    </div>
  </div>

  <!-- Search & Category Filter -->
  <div class="flex flex-col md:flex-row items-stretch md:items-center gap-3">
    <div class="relative flex-1">
      <Search
        class="w-3.5 h-3.5 absolute left-3.5 top-1/2 -translate-y-1/2"
        style="color: var(--text-muted);"
      />
      <input
        type="text"
        bind:value={searchQuery}
        placeholder={viewMode === 'blacklist'
          ? 'Поиск по системному имени, названию или описанию службы...'
          : 'Поиск защищённой службы по имени...'}
        class="w-full pl-9 pr-3.5 py-2 text-xs rounded-xl border focus:outline-none transition-colors"
        style="
          background-color: var(--bg-surface);
          border-color: var(--border-subtle);
          color: var(--text-primary);
        "
      />
    </div>

    {#if viewMode === 'blacklist'}
      <div
        class="flex items-center gap-1 p-1 rounded-xl border overflow-x-auto"
        style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
      >
        {#each ['all', 'Telemetry', 'Xbox', 'Print', 'Network', 'System'] as cat}
          <button
            type="button"
            onclick={() => (selectedCategory = cat)}
            class="px-2.5 py-1 rounded-lg text-[11px] font-medium transition-colors cursor-pointer shrink-0"
            style="
              background-color: {selectedCategory === cat ? 'var(--accent-soft)' : 'transparent'};
              color: {selectedCategory === cat ? 'var(--accent-primary)' : 'var(--text-secondary)'};
            "
          >
            {cat === 'all'
              ? 'Все'
              : cat === 'Telemetry'
                ? 'Телеметрия'
                : cat === 'Print'
                  ? 'Печать'
                  : cat === 'Network'
                    ? 'Сеть'
                    : cat === 'System'
                      ? 'Система'
                      : cat}
          </button>
        {/each}
      </div>
    {/if}
  </div>

  <!-- Services List -->
  {#if viewMode === 'blacklist'}
    <div
      class="rounded-xl border overflow-hidden"
      style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
    >
      <div
        class="grid grid-cols-12 px-4 py-2.5 text-[11px] font-semibold border-b"
        style="background-color: var(--bg-elevated); border-color: var(--border-subtle); color: var(--text-secondary);"
      >
        <span class="col-span-3">Имя службы</span>
        <span class="col-span-3">Отображаемое имя</span>
        <span class="col-span-4">Причина временного отключения</span>
        <span class="col-span-2 text-right">Категория</span>
      </div>

      <div class="max-h-[340px] overflow-y-auto divide-y" style="border-color: var(--border-subtle);">
        {#each filteredBlacklist as s}
          <div
            class="grid grid-cols-12 px-4 py-2.5 text-xs items-center transition-colors"
            style="border-color: var(--border-subtle);"
          >
            <span class="col-span-3 font-mono font-medium truncate pr-2" style="color: var(--text-primary);">
              {s.Name}
            </span>
            <span class="col-span-3 truncate pr-2 text-[11px]" style="color: var(--text-secondary);" title={s.DisplayName}>
              {s.DisplayName}
            </span>
            <span class="col-span-4 truncate pr-2 text-[11px]" style="color: var(--text-muted);" title={s.Reason}>
              {s.Reason}
            </span>
            <div class="col-span-2 flex justify-end">
              <span
                class="px-2 py-0.5 rounded text-[10px] font-medium border"
                style="background-color: var(--bg-elevated); color: var(--text-secondary); border-color: var(--border-subtle);"
              >
                {s.Category}
              </span>
            </div>
          </div>
        {:else}
          <div class="py-10 text-center text-xs" style="color: var(--text-muted);">
            Службы по запросу «{searchQuery}» не найдены
          </div>
        {/each}
      </div>
    </div>
  {:else}
    <div
      class="rounded-xl border p-4 max-h-[360px] overflow-y-auto"
      style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
    >
      <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-2">
        {#each filteredWhitelist as svcName}
          <div
            class="flex items-center justify-between px-3 py-2 rounded-lg border text-xs font-mono"
            style="background-color: var(--bg-elevated); border-color: var(--border-subtle); color: var(--text-primary);"
          >
            <span class="truncate">{svcName}</span>
            <span
              class="text-[10px] font-sans font-medium px-1.5 py-0.5 rounded"
              style="background-color: var(--active-soft); color: var(--active-primary);"
            >
              Защищена
            </span>
          </div>
        {:else}
          <div class="col-span-4 py-8 text-center text-xs" style="color: var(--text-muted);">
            Защищённые службы по запросу «{searchQuery}» не найдены
          </div>
        {/each}
      </div>
    </div>
  {/if}
</div>
