<script lang="ts">
  import {
    Activity,
    AlertCircle,
    FilterX,
    ListFilter,
    Loader2,
    Plus,
    RefreshCw,
    Search,
    ShieldAlert,
    ShieldBan,
    ShieldCheck,
    Skull,
    Trash2,
    X
  } from '@lucide/svelte';
  import type {
    ListMutationOperation,
    ProcessItem,
    ProcessListType
  } from '../types';

  export type ProcessViewMode = 'live' | 'blacklist' | 'protected';
  export type ProcessFilterMode = 'all' | 'blacklisted' | 'user';

  interface Props {
    processes: ProcessItem[];
    blacklistProcesses: string[];
    protectedStartupNames: string[];
    viewMode: ProcessViewMode;
    filterMode: ProcessFilterMode;
    searchQuery: string;
    isLoading: boolean;
    busyKey: string | null;
    loadError: string | null;
    onViewModeChange: (mode: ProcessViewMode) => void;
    onFilterModeChange: (filter: ProcessFilterMode) => void;
    onSearchChange: (value: string) => void;
    onRefresh: () => void;
    onKillProcess: (proc: ProcessItem) => void;
    onUpdateList: (
      listType: ProcessListType,
      processName: string,
      operation: ListMutationOperation
    ) => Promise<void> | void;
  }

  let {
    processes,
    blacklistProcesses,
    protectedStartupNames,
    viewMode,
    filterMode,
    searchQuery,
    isLoading,
    busyKey,
    loadError,
    onViewModeChange,
    onFilterModeChange,
    onSearchChange,
    onRefresh,
    onKillProcess,
    onUpdateList
  }: Props = $props();

  let newProcessName = $state('');
  let debouncedQuery = $state('');
  let searchDebounceHandle: ReturnType<typeof setTimeout> | undefined;
  let visibleLiveLimit = $state(60);

  $effect(() => {
    const target = searchQuery.trim().toLowerCase();
    clearTimeout(searchDebounceHandle);
    if (!target) {
      debouncedQuery = '';
      return;
    }
    searchDebounceHandle = setTimeout(() => {
      debouncedQuery = target;
    }, 120);
    return () => clearTimeout(searchDebounceHandle);
  });

  const normalizedQuery = $derived(debouncedQuery);

  const filteredLiveProcesses = $derived.by(() => {
    return processes.filter((p) => {
      if (filterMode === 'blacklisted' && !p.isBlacklisted) return false;
      if (filterMode === 'user' && p.isProtected) return false;
      if (!normalizedQuery) return true;
      return (
        p.name.toLowerCase().includes(normalizedQuery) ||
        String(p.pid).includes(normalizedQuery)
      );
    });
  });

  $effect(() => {
    void normalizedQuery;
    void filterMode;
    void viewMode;
    visibleLiveLimit = 60;
  });

  const visibleLiveProcesses = $derived(filteredLiveProcesses.slice(0, visibleLiveLimit));

  const filteredBlacklistNames = $derived.by(() => {
    if (!normalizedQuery) return blacklistProcesses;
    return blacklistProcesses.filter((n) => n.toLowerCase().includes(normalizedQuery));
  });

  const filteredProtectedNames = $derived.by(() => {
    if (!normalizedQuery) return protectedStartupNames;
    return protectedStartupNames.filter((n) => n.toLowerCase().includes(normalizedQuery));
  });

  const hasActiveFilters = $derived(
    searchQuery.trim().length > 0 || (viewMode === 'live' && filterMode !== 'all')
  );

  function resetFilters() {
    onSearchChange('');
    onFilterModeChange('all');
  }

  async function handleAddSubmit(e: SubmitEvent) {
    e.preventDefault();
    const cleaned = newProcessName.trim().replace(/\.exe$/i, '');
    if (!cleaned) return;
    const targetType: ProcessListType = viewMode === 'protected' ? 'protected' : 'blacklist';
    await onUpdateList(targetType, cleaned, 'add');
    newProcessName = '';
  }
</script>

<div class="space-y-4">
  <!-- Header & Mode Toggle -->
  <section class="ui-card rounded-2xl p-5 space-y-4">
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
      <div class="space-y-1">
        <h1 class="text-base font-semibold text-[var(--text-primary)]">
          Мониторинг процессов и чёрный список
        </h1>
        <p class="text-sm text-[var(--text-secondary)]">
          Точечное завершение фоновых процессов и настройка правил <code translate="no" class="font-mono text-xs">startup_apps.json</code> с защитой ядра Windows.
        </p>
      </div>

      <button
        type="button"
        onclick={onRefresh}
        disabled={isLoading}
        class="ui-btn-secondary ui-pressable rounded-lg px-3.5 py-2 min-h-9 text-[0.8125rem] font-medium flex items-center gap-1.5 shrink-0 self-start sm:self-center disabled:opacity-55 disabled:cursor-not-allowed cursor-pointer"
      >
        <RefreshCw size={14} strokeWidth={1.75} class={isLoading ? 'ui-spin' : ''} aria-hidden="true" />
        <span>Обновить</span>
      </button>
    </div>

    <!-- Segmented View Toggle + Search -->
    <div class="flex flex-col lg:flex-row lg:items-center gap-3">
      <div
        class="inline-flex flex-wrap gap-1.5 p-1 rounded-xl bg-[var(--bg-elevated)] border border-[var(--border-subtle)]"
        role="group"
        aria-label="Режим списка процессов"
      >
        <button
          type="button"
          onclick={() => onViewModeChange('live')}
          aria-pressed={viewMode === 'live'}
          class="{viewMode === 'live'
            ? 'ui-btn-primary'
            : 'ui-btn-ghost'} ui-pressable rounded-lg px-3 py-2 min-h-9 text-[0.8125rem] font-medium flex items-center gap-2 cursor-pointer"
        >
          <Activity size={15} strokeWidth={1.75} aria-hidden="true" />
          <span>Активные</span>
          <span class="tabular-nums opacity-90">({processes.length})</span>
        </button>

        <button
          type="button"
          onclick={() => onViewModeChange('blacklist')}
          aria-pressed={viewMode === 'blacklist'}
          class="{viewMode === 'blacklist'
            ? 'ui-btn-primary'
            : 'ui-btn-ghost'} ui-pressable rounded-lg px-3 py-2 min-h-9 text-[0.8125rem] font-medium flex items-center gap-2 cursor-pointer"
        >
          <ShieldAlert size={15} strokeWidth={1.75} aria-hidden="true" />
          <span>Чёрный список</span>
          <span class="tabular-nums opacity-90">({blacklistProcesses.length})</span>
        </button>

        <button
          type="button"
          onclick={() => onViewModeChange('protected')}
          aria-pressed={viewMode === 'protected'}
          class="{viewMode === 'protected'
            ? 'ui-btn-primary'
            : 'ui-btn-ghost'} ui-pressable rounded-lg px-3 py-2 min-h-9 text-[0.8125rem] font-medium flex items-center gap-2 cursor-pointer"
        >
          <ShieldCheck size={15} strokeWidth={1.75} aria-hidden="true" />
          <span>Исключения</span>
          <span class="tabular-nums opacity-90">({protectedStartupNames.length})</span>
        </button>
      </div>

      <div class="relative flex-1 min-w-0">
        <label for="processes-search" class="sr-only">
          Поиск процессов по имени или PID
        </label>
        <Search
          size={16}
          strokeWidth={1.75}
          class="absolute left-3 top-1/2 -translate-y-1/2 text-[var(--text-muted)] pointer-events-none"
          aria-hidden="true"
        />
        <input
          id="processes-search"
          name="processes-search"
          type="search"
          autocomplete="off"
          autocorrect="off"
          autocapitalize="none"
          spellcheck={false}
          value={searchQuery}
          oninput={(e) => onSearchChange((e.currentTarget as HTMLInputElement).value)}
          placeholder={viewMode === 'live'
            ? 'Найти по имени процесса или PID…'
            : 'Фильтр по имени процесса…'}
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

    {#if viewMode === 'live'}
      <div class="flex flex-wrap items-center justify-between gap-2 pt-1">
        <div class="flex flex-wrap items-center gap-1.5" role="group" aria-label="Фильтр процессов">
          <span class="inline-flex items-center gap-1 text-xs font-medium text-[var(--text-muted)] mr-1">
            <ListFilter size={13} strokeWidth={1.75} aria-hidden="true" />
            <span>Фильтр:</span>
          </span>
          {#each [
            { id: 'all', label: 'Все' },
            { id: 'user', label: 'Завершаемые' },
            { id: 'blacklisted', label: 'В чёрном списке' }
          ] as f (f.id)}
            {@const active = filterMode === f.id}
            <button
              type="button"
              onclick={() => onFilterModeChange(f.id as ProcessFilterMode)}
              aria-pressed={active}
              class="{active
                ? 'bg-[var(--accent-soft)] text-[var(--accent-text)] border-[var(--accent-border)]'
                : 'bg-[var(--bg-elevated)] text-[var(--text-secondary)] border-[var(--border-input)] hover:bg-[var(--bg-hover)]'} ui-pressable rounded-lg border px-3 py-1.5 min-h-8 text-[0.8125rem] font-medium cursor-pointer"
            >
              {f.label}
            </button>
          {/each}
        </div>

        <p class="text-[0.8125rem] text-[var(--text-muted)] tabular-nums" aria-live="polite">
          Показано {visibleLiveProcesses.length} из {filteredLiveProcesses.length}{#if filteredLiveProcesses.length !== processes.length} (всего {processes.length}){/if}
        </p>
      </div>
    {:else}
      <form onsubmit={handleAddSubmit} class="flex flex-col sm:flex-row gap-2 pt-1">
        <label for="new-process-input" class="sr-only">
          Имя процесса для добавления в список
        </label>
        <input
          id="new-process-input"
          type="text"
          autocomplete="off"
          spellcheck={false}
          bind:value={newProcessName}
          placeholder={viewMode === 'blacklist'
            ? 'Добавить процесс в чёрный список (например: EpicGamesLauncher)…'
            : 'Добавить имя в исключения автозагрузки (например: ctfmon)…'}
          class="ui-input flex-1 rounded-xl px-3.5 py-2 min-h-10 text-sm"
        />
        <button
          type="submit"
          disabled={!newProcessName.trim() || busyKey !== null}
          class="ui-btn-primary ui-pressable rounded-xl px-4 py-2 min-h-10 text-[0.8125rem] font-medium inline-flex items-center justify-center gap-1.5 shrink-0 disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer"
        >
          <Plus size={15} strokeWidth={2} aria-hidden="true" />
          <span>Добавить</span>
        </button>
      </form>
    {/if}
  </section>

  <!-- Content Area -->
  {#if isLoading && processes.length === 0 && blacklistProcesses.length === 0}
    <div
      class="ui-card rounded-2xl p-8 flex items-center justify-center gap-3 text-sm text-[var(--text-secondary)]"
      role="status"
    >
      <Loader2 size={18} strokeWidth={2} class="ui-spin text-[var(--accent-text)]" aria-hidden="true" />
      <span>Сканирую активные процессы Windows…</span>
    </div>
  {:else if loadError && processes.length === 0}
    <div
      class="ui-card rounded-2xl p-6 border border-[var(--status-danger-border)] bg-[var(--status-danger-soft)] flex flex-col sm:flex-row sm:items-center justify-between gap-4"
      role="alert"
    >
      <div class="flex items-start gap-3 min-w-0">
        <AlertCircle size={20} strokeWidth={1.75} class="text-[var(--status-danger-text)] shrink-0 mt-0.5" aria-hidden="true" />
        <div class="space-y-1 min-w-0">
          <p class="text-sm font-semibold text-[var(--status-danger-text)]">
            Не удалось получить список процессов
          </p>
          <p class="text-sm text-[var(--text-secondary)] break-words">
            {loadError}
          </p>
        </div>
      </div>

      <button
        type="button"
        onclick={onRefresh}
        class="ui-btn-secondary ui-pressable rounded-lg px-4 py-2 min-h-9 text-[0.8125rem] font-medium shrink-0 cursor-pointer"
      >
        Повторить
      </button>
    </div>
  {:else if viewMode === 'live'}
    {#if filteredLiveProcesses.length === 0}
      <div class="ui-card rounded-2xl p-8 text-center space-y-3">
        <p class="text-sm font-semibold text-[var(--text-primary)]">
          Процессы не найдены
        </p>
        <p class="text-sm text-[var(--text-secondary)]">
          Измените поисковый запрос или сбросьте фильтр.
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
        {#each visibleLiveProcesses as proc (`${proc.pid}-${proc.name}`)}
          {@const rowBusy = busyKey === `kill:${proc.pid}` || busyKey === `proc:${proc.name}`}
          <li class="p-3.5 sm:px-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
            <div class="min-w-0 flex-1 space-y-1">
              <div class="flex flex-wrap items-center gap-2">
                <span class="text-sm font-medium text-[var(--text-primary)] break-all">
                  {proc.name}
                </span>
                <code
                  translate="no"
                  class="font-mono text-xs px-2 py-0.5 rounded-md bg-[var(--bg-elevated)] text-[var(--text-secondary)] tabular-nums"
                >
                  PID {proc.pid}
                </code>
                <span class="text-xs font-medium text-[var(--text-muted)] tabular-nums">
                  {proc.memoryMb.toFixed(1)} МБ
                </span>

                {#if proc.isProtected}
                  <span
                    class="inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-medium bg-[var(--status-active-soft)] text-[var(--status-active-text)] border border-[var(--status-active-border)]"
                  >
                    <ShieldCheck size={12} strokeWidth={2} aria-hidden="true" />
                    <span>Защищён ОС</span>
                  </span>
                {:else if proc.isBlacklisted}
                  <span
                    class="inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-medium bg-[var(--status-warn-soft)] text-[var(--status-warn-text)] border border-[var(--status-warn-border)]"
                  >
                    <ShieldAlert size={12} strokeWidth={2} aria-hidden="true" />
                    <span>Чёрный список</span>
                  </span>
                {:else if proc.isStartupProtected}
                  <span
                    class="inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-medium bg-[var(--accent-soft)] text-[var(--accent-text)] border border-[var(--accent-border)]"
                  >
                    <ShieldCheck size={12} strokeWidth={2} aria-hidden="true" />
                    <span>Исключение</span>
                  </span>
                {/if}
              </div>
            </div>

            <div class="flex flex-wrap items-center gap-1.5 shrink-0">
              {#if !proc.isProtected}
                <button
                  type="button"
                  disabled={rowBusy || busyKey !== null}
                  onclick={() =>
                    onUpdateList(
                      'blacklist',
                      proc.name,
                      proc.isBlacklisted ? 'remove' : 'add'
                    )}
                  class="ui-btn-secondary ui-pressable rounded-lg px-2.5 py-1.5 min-h-8 text-xs font-medium inline-flex items-center gap-1.5 disabled:opacity-50 cursor-pointer"
                  title={proc.isBlacklisted
                    ? 'Удалить из чёрного списка автозакрытия'
                    : 'Добавить в чёрный список игрового режима'}
                >
                  <ShieldBan size={13} strokeWidth={1.75} aria-hidden="true" />
                  <span>{proc.isBlacklisted ? 'Убрать из ЧС' : 'В ЧС'}</span>
                </button>

                <button
                  type="button"
                  disabled={rowBusy || busyKey !== null}
                  onclick={() =>
                    onUpdateList(
                      'protected',
                      proc.name,
                      proc.isStartupProtected ? 'remove' : 'add'
                    )}
                  class="ui-btn-secondary ui-pressable rounded-lg px-2.5 py-1.5 min-h-8 text-xs font-medium inline-flex items-center gap-1.5 disabled:opacity-50 cursor-pointer"
                  title={proc.isStartupProtected
                    ? 'Удалить из исключений автозагрузки'
                    : 'Защитить от скрытия при включении режима'}
                >
                  <ShieldCheck size={13} strokeWidth={1.75} aria-hidden="true" />
                  <span>{proc.isStartupProtected ? 'Убрать искл.' : 'Исключение'}</span>
                </button>

                <button
                  type="button"
                  disabled={rowBusy || busyKey !== null}
                  onclick={() => onKillProcess(proc)}
                  class="ui-btn-warn ui-pressable rounded-lg px-2.5 py-1.5 min-h-8 text-xs font-medium inline-flex items-center gap-1.5 disabled:opacity-50 cursor-pointer"
                >
                  <Skull size={13} strokeWidth={1.75} aria-hidden="true" />
                  <span>Завершить</span>
                </button>
              {:else}
                <span class="text-xs text-[var(--text-muted)] px-2">Системный компонент</span>
              {/if}
            </div>
          </li>
        {/each}
      </ul>
      {#if filteredLiveProcesses.length > visibleLiveProcesses.length}
        <div class="flex justify-center pt-1">
          <button
            type="button"
            onclick={() => (visibleLiveLimit += 60)}
            class="ui-btn-secondary ui-pressable rounded-xl px-4 py-2 min-h-9 text-[0.8125rem] font-medium cursor-pointer"
          >
            Показать ещё ({Math.min(60, filteredLiveProcesses.length - visibleLiveProcesses.length)} из {filteredLiveProcesses.length - visibleLiveProcesses.length} оставшихся)
          </button>
        </div>
      {/if}
    {/if}
  {:else if viewMode === 'blacklist'}
    <div class="ui-card rounded-2xl p-4 sm:p-5 space-y-3">
      <p class="text-[0.8125rem] text-[var(--text-secondary)]">
        Процессы из этого списка автоматически завершаются при включении игрового режима (за исключением защищённых процессов ОС и WebView2).
      </p>
      {#if filteredBlacklistNames.length === 0}
        <p class="text-sm text-[var(--text-muted)] py-4 text-center">Список пуст.</p>
      {:else}
        <ul class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2.5">
          {#each filteredBlacklistNames as name (name)}
            <li
              class="rounded-xl px-3.5 py-2.5 bg-[var(--bg-elevated)] border border-[var(--border-subtle)] flex items-center justify-between gap-2 min-w-0"
            >
              <code translate="no" class="font-mono text-[0.8125rem] font-medium text-[var(--text-primary)] truncate">
                {name}
              </code>
              <button
                type="button"
                disabled={busyKey !== null}
                onclick={() => onUpdateList('blacklist', name, 'remove')}
                aria-label={`Удалить ${name} из чёрного списка`}
                class="ui-btn-ghost w-7 h-7 rounded-lg flex items-center justify-center shrink-0 text-[var(--text-muted)] hover:text-[var(--status-danger-text)] cursor-pointer"
              >
                <Trash2 size={14} strokeWidth={1.75} aria-hidden="true" />
              </button>
            </li>
          {/each}
        </ul>
      {/if}
    </div>
  {:else}
    <div class="ui-card rounded-2xl p-4 sm:p-5 space-y-3">
      <p class="text-[0.8125rem] text-[var(--text-secondary)]">
        Элементы автозагрузки из этого списка сохраняются при переходе в игровой режим (<code translate="no" class="font-mono text-xs">ProtectedStartupNames</code>).
      </p>
      {#if filteredProtectedNames.length === 0}
        <p class="text-sm text-[var(--text-muted)] py-4 text-center">Список пуст.</p>
      {:else}
        <ul class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2.5">
          {#each filteredProtectedNames as name (name)}
            <li
              class="rounded-xl px-3.5 py-2.5 bg-[var(--bg-elevated)] border border-[var(--border-subtle)] flex items-center justify-between gap-2 min-w-0"
            >
              <span class="flex items-center gap-2 min-w-0">
                <ShieldCheck size={14} strokeWidth={1.75} class="text-[var(--status-active-text)] shrink-0" aria-hidden="true" />
                <code translate="no" class="font-mono text-[0.8125rem] font-medium text-[var(--text-primary)] truncate">
                  {name}
                </code>
              </span>
              <button
                type="button"
                disabled={busyKey !== null}
                onclick={() => onUpdateList('protected', name, 'remove')}
                aria-label={`Удалить ${name} из исключений`}
                class="ui-btn-ghost w-7 h-7 rounded-lg flex items-center justify-center shrink-0 text-[var(--text-muted)] hover:text-[var(--status-danger-text)] cursor-pointer"
              >
                <Trash2 size={14} strokeWidth={1.75} aria-hidden="true" />
              </button>
            </li>
          {/each}
        </ul>
      {/if}
    </div>
  {/if}
</div>
