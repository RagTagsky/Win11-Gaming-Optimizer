<script lang="ts">
  import {
    AlertCircle,
    FilterX,
    ListFilter,
    Loader2,
    RefreshCw,
    Search,
    ShieldAlert,
    ShieldCheck,
    X
  } from '@lucide/svelte';
  import type { BlacklistServiceItem, ServiceCategory } from '../types';

  export type ServiceViewMode = 'blacklist' | 'whitelist';
  export type ServiceCategoryFilter = 'all' | ServiceCategory;

  interface Props {
    blacklist: BlacklistServiceItem[];
    whitelist: string[];
    viewMode: ServiceViewMode;
    searchQuery: string;
    selectedCategory: ServiceCategoryFilter;
    isLoading: boolean;
    loadError: string | null;
    onViewModeChange: (mode: ServiceViewMode) => void;
    onSearchChange: (value: string) => void;
    onCategoryChange: (category: ServiceCategoryFilter) => void;
    onRetry: () => void;
  }

  let {
    blacklist,
    whitelist,
    viewMode,
    searchQuery,
    selectedCategory,
    isLoading,
    loadError,
    onViewModeChange,
    onSearchChange,
    onCategoryChange,
    onRetry
  }: Props = $props();

  const CATEGORY_LABELS: Record<ServiceCategoryFilter, string> = {
    all: 'Все',
    Telemetry: 'Телеметрия',
    Xbox: 'Xbox',
    Print: 'Печать',
    Network: 'Сеть',
    System: 'Система'
  };

  const CATEGORIES: ServiceCategoryFilter[] = [
    'all',
    'Telemetry',
    'Xbox',
    'Print',
    'Network',
    'System'
  ];

  const normalizedQuery = $derived(searchQuery.trim().toLowerCase());

  const filteredBlacklist = $derived.by(() => {
    return blacklist.filter((item) => {
      if (selectedCategory !== 'all' && item.Category !== selectedCategory) {
        return false;
      }
      if (!normalizedQuery) return true;
      const catLabel = (CATEGORY_LABELS[item.Category] ?? item.Category).toLowerCase();
      return (
        item.Name.toLowerCase().includes(normalizedQuery) ||
        item.DisplayName.toLowerCase().includes(normalizedQuery) ||
        item.Reason.toLowerCase().includes(normalizedQuery) ||
        catLabel.includes(normalizedQuery)
      );
    });
  });

  const filteredWhitelist = $derived.by(() => {
    if (!normalizedQuery) return whitelist;
    return whitelist.filter((name) => name.toLowerCase().includes(normalizedQuery));
  });

  const hasActiveFilters = $derived(
    searchQuery.trim().length > 0 || (viewMode === 'blacklist' && selectedCategory !== 'all')
  );

  function resetFilters() {
    onSearchChange('');
    onCategoryChange('all');
  }
</script>

<div class="space-y-4">
  <!-- Header & Mode Toggle -->
  <section class="ui-card rounded-2xl p-5 space-y-4">
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
      <div class="space-y-1">
        <h1 class="text-base font-semibold text-[var(--text-primary)]">
          Контроль системных служб Windows
        </h1>
        <p class="text-sm text-[var(--text-secondary)]">
          Временная приостановка фоновых служб во время игры и защищённый белый список ядра ОС.
        </p>
      </div>

      <button
        type="button"
        onclick={onRetry}
        disabled={isLoading}
        class="ui-btn-secondary ui-pressable rounded-lg px-3.5 py-2 min-h-9 text-[0.8125rem] font-medium flex items-center gap-1.5 shrink-0 self-start sm:self-center disabled:opacity-55 disabled:cursor-not-allowed cursor-pointer"
      >
        <RefreshCw size={14} strokeWidth={1.75} class={isLoading ? 'ui-spin' : ''} aria-hidden="true" />
        <span>Обновить список</span>
      </button>
    </div>

    <!-- Segmented View Toggle + Search -->
    <div class="flex flex-col lg:flex-row lg:items-center gap-3">
      <div
        class="inline-flex flex-wrap gap-1.5 p-1 rounded-xl bg-[var(--bg-elevated)] border border-[var(--border-subtle)]"
        role="group"
        aria-label="Список служб"
      >
        <button
          type="button"
          onclick={() => onViewModeChange('blacklist')}
          aria-pressed={viewMode === 'blacklist'}
          class="{viewMode === 'blacklist'
            ? 'ui-btn-primary'
            : 'ui-btn-ghost'} ui-pressable rounded-lg px-3.5 py-2 min-h-9 text-[0.8125rem] font-medium flex items-center gap-2 cursor-pointer"
        >
          <ShieldAlert size={15} strokeWidth={1.75} aria-hidden="true" />
          <span>Оптимизируемые</span>
          <span class="tabular-nums opacity-90">({blacklist.length})</span>
        </button>

        <button
          type="button"
          onclick={() => onViewModeChange('whitelist')}
          aria-pressed={viewMode === 'whitelist'}
          class="{viewMode === 'whitelist'
            ? 'ui-btn-primary'
            : 'ui-btn-ghost'} ui-pressable rounded-lg px-3.5 py-2 min-h-9 text-[0.8125rem] font-medium flex items-center gap-2 cursor-pointer"
        >
          <ShieldCheck size={15} strokeWidth={1.75} aria-hidden="true" />
          <span>Белый список</span>
          <span class="tabular-nums opacity-90">({whitelist.length})</span>
        </button>
      </div>

      <div class="relative flex-1 min-w-0">
        <label for="services-search" class="sr-only">
          Поиск служб по системному имени, описанию или категории
        </label>
        <Search
          size={16}
          strokeWidth={1.75}
          class="absolute left-3 top-1/2 -translate-y-1/2 text-[var(--text-muted)] pointer-events-none"
          aria-hidden="true"
        />
        <input
          id="services-search"
          name="services-search"
          type="search"
          autocomplete="off"
          autocorrect="off"
          autocapitalize="none"
          spellcheck={false}
          value={searchQuery}
          oninput={(e) => onSearchChange((e.currentTarget as HTMLInputElement).value)}
          placeholder={viewMode === 'blacklist'
            ? 'Найти по имени службы, причине или категории…'
            : 'Найти защищённую службу…'}
          class="ui-input w-full rounded-xl pl-9 pr-10 py-2 min-h-10 text-sm appearance-none [&::-webkit-search-cancel-button]:hidden"
        />
        {#if searchQuery.length > 0}
          <button
            type="button"
            onclick={() => onSearchChange('')}
            aria-label="Очистить строку поиска"
            class="ui-btn-ghost absolute right-1 top-1/2 -translate-y-1/2 w-8 h-8 rounded-lg flex items-center justify-center cursor-pointer"
          >
            <X size={15} strokeWidth={1.75} aria-hidden="true" />
          </button>
        {/if}
      </div>
    </div>

    <!-- Category Filters (only in Blacklist view) -->
    {#if viewMode === 'blacklist'}
      <div class="flex flex-wrap items-center justify-between gap-2 pt-1">
        <div class="flex flex-wrap items-center gap-1.5" role="group" aria-label="Фильтр по категории">
          <span class="inline-flex items-center gap-1 text-xs font-medium text-[var(--text-muted)] mr-1">
            <ListFilter size={13} strokeWidth={1.75} aria-hidden="true" />
            <span>Категория:</span>
          </span>
          {#each CATEGORIES as cat (cat)}
            {@const active = selectedCategory === cat}
            <button
              type="button"
              onclick={() => onCategoryChange(cat)}
              aria-pressed={active}
              class="{active
                ? 'bg-[var(--accent-soft)] text-[var(--accent-text)] border-[var(--accent-border)]'
                : 'bg-[var(--bg-elevated)] text-[var(--text-secondary)] border-[var(--border-input)] hover:bg-[var(--bg-hover)]'} ui-pressable rounded-lg border px-3 py-1.5 min-h-8 text-[0.8125rem] font-medium cursor-pointer"
            >
              {CATEGORY_LABELS[cat]}
            </button>
          {/each}
        </div>

        <p class="text-[0.8125rem] text-[var(--text-muted)] tabular-nums" aria-live="polite">
          Показано {filteredBlacklist.length} из {blacklist.length}
        </p>
      </div>
    {:else}
      <p class="text-[0.8125rem] text-[var(--text-muted)] tabular-nums" aria-live="polite">
        Показано {filteredWhitelist.length} из {whitelist.length} защищённых служб
      </p>
    {/if}
  </section>

  <!-- Main Content -->
  {#if isLoading && blacklist.length === 0 && whitelist.length === 0}
    <div
      class="ui-card rounded-2xl p-8 flex items-center justify-center gap-3 text-sm text-[var(--text-secondary)]"
      role="status"
    >
      <Loader2 size={18} strokeWidth={2} class="ui-spin text-[var(--accent-text)]" aria-hidden="true" />
      <span>Загружаю списки служб Windows…</span>
    </div>
  {:else if loadError && blacklist.length === 0 && whitelist.length === 0}
    <div
      class="ui-card rounded-2xl p-6 border border-[var(--status-danger-border)] bg-[var(--status-danger-soft)] flex flex-col sm:flex-row sm:items-center justify-between gap-4"
      role="alert"
    >
      <div class="flex items-start gap-3 min-w-0">
        <AlertCircle size={20} strokeWidth={1.75} class="text-[var(--status-danger-text)] shrink-0 mt-0.5" aria-hidden="true" />
        <div class="space-y-1 min-w-0">
          <p class="text-sm font-semibold text-[var(--status-danger-text)]">
            Не удалось прочитать списки служб
          </p>
          <p class="text-sm text-[var(--text-secondary)] break-words">
            {loadError}
          </p>
        </div>
      </div>

      <button
        type="button"
        onclick={onRetry}
        class="ui-btn-secondary ui-pressable rounded-lg px-4 py-2 min-h-9 text-[0.8125rem] font-medium shrink-0 cursor-pointer"
      >
        Повторить
      </button>
    </div>
  {:else if viewMode === 'blacklist'}
    {#if filteredBlacklist.length === 0}
      <div class="ui-card rounded-2xl p-8 text-center space-y-3">
        <p class="text-sm font-semibold text-[var(--text-primary)]">
          Ничего не найдено по заданным условиям
        </p>
        <p class="text-sm text-[var(--text-secondary)]">
          Попробуйте изменить поисковый запрос или сбросить фильтр категории.
        </p>
        {#if hasActiveFilters}
          <button
            type="button"
            onclick={resetFilters}
            class="ui-btn-secondary ui-pressable rounded-lg px-4 py-2 min-h-9 text-[0.8125rem] font-medium inline-flex items-center gap-1.5 cursor-pointer"
          >
            <FilterX size={15} strokeWidth={1.75} aria-hidden="true" />
            <span>Сбросить фильтры</span>
          </button>
        {/if}
      </div>
    {:else}
      <ul class="ui-card rounded-2xl divide-y divide-[var(--border-subtle)] overflow-hidden">
        {#each filteredBlacklist as svc (svc.Name)}
          {@const showDisplay =
            svc.DisplayName.trim().length > 0 &&
            svc.DisplayName.trim() !== svc.Reason.trim() &&
            svc.DisplayName.trim() !== svc.Name.trim()}
          <li class="p-4 flex flex-col sm:flex-row sm:items-start justify-between gap-3">
            <div class="min-w-0 flex-1 space-y-1">
              <div class="flex flex-wrap items-baseline gap-2">
                <span class="text-sm font-medium text-[var(--text-primary)] break-words">
                  {showDisplay ? svc.DisplayName : svc.Reason}
                </span>
                <code
                  translate="no"
                  class="font-mono text-xs px-2 py-0.5 rounded-md bg-[var(--bg-elevated)] text-[var(--text-secondary)] select-text"
                >
                  {svc.Name}
                </code>
              </div>

              {#if showDisplay}
                <p class="text-[0.8125rem] leading-relaxed text-[var(--text-secondary)] break-words">
                  {svc.Reason}
                </p>
              {/if}
            </div>

            <div class="flex flex-wrap items-center gap-2 shrink-0">
              <span
                class="inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium bg-[var(--bg-elevated)] text-[var(--text-secondary)] border border-[var(--border-subtle)]"
              >
                {CATEGORY_LABELS[svc.Category] ?? svc.Category}
              </span>
            </div>
          </li>
        {/each}
      </ul>
    {/if}
  {:else}
    <!-- Whitelist View -->
    {#if filteredWhitelist.length === 0}
      <div class="ui-card rounded-2xl p-8 text-center space-y-3">
        <p class="text-sm font-semibold text-[var(--text-primary)]">
          Совпадений в белом списке не найдено
        </p>
        <p class="text-sm text-[var(--text-secondary)]">
          Проверьте правильность системного имени службы.
        </p>
        {#if hasActiveFilters}
          <button
            type="button"
            onclick={resetFilters}
            class="ui-btn-secondary ui-pressable rounded-lg px-4 py-2 min-h-9 text-[0.8125rem] font-medium inline-flex items-center gap-1.5 cursor-pointer"
          >
            <FilterX size={15} strokeWidth={1.75} aria-hidden="true" />
            <span>Сбросить поиск</span>
          </button>
        {/if}
      </div>
    {:else}
      <div class="ui-card rounded-2xl p-4 sm:p-5 space-y-3">
        <p class="text-[0.8125rem] text-[var(--text-secondary)]">
          Эти критически важные системные компоненты защищены от остановки в любом профиле.
        </p>

        <ul class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2.5">
          {#each filteredWhitelist as svcName (svcName)}
            <li
              class="rounded-xl px-3.5 py-2.5 bg-[var(--bg-elevated)] border border-[var(--border-subtle)] flex items-center gap-2.5 min-w-0"
            >
              <ShieldCheck
                size={15}
                strokeWidth={1.75}
                class="text-[var(--status-active-text)] shrink-0"
                aria-hidden="true"
              />
              <code
                translate="no"
                class="font-mono text-[0.8125rem] font-medium text-[var(--text-primary)] break-all select-text"
              >
                {svcName}
              </code>
            </li>
          {/each}
        </ul>
      </div>
    {/if}
  {/if}
</div>
