<script lang="ts">
  import {
    Activity,
    AlertCircle,
    ChevronDown,
    ChevronRight,
    FilterX,
    ListFilter,
    Loader2,
    Plus,
    Power,
    RefreshCw,
    Search,
    Shield,
    ShieldCheck,
    Skull,
    Trash2,
    X
  } from '@lucide/svelte';
  import type {
    ListMutationOperation,
    ProcessItem,
    ProcessListType,
    ProcessProtectionKind,
    StartupEntry
  } from '../types';

  export type ProcessViewMode = 'running' | 'autoclose' | 'startup';
  export type ProcessFilterMode = 'all' | 'autoclose' | 'protected';

  interface GroupedProcess {
    key: string;
    name: string;
    displayName: string;
    totalMemoryMb: number;
    pids: ProcessItem[];
    isProtected: boolean;
    protectionKind: ProcessProtectionKind | null;
    isBlacklisted: boolean;
    isStartupProtected: boolean;
  }

  interface Props {
    processes: ProcessItem[];
    blacklistProcesses: string[];
    protectedStartupNames: string[];
    startupEntries: StartupEntry[];
    viewMode: ProcessViewMode;
    filterMode: ProcessFilterMode;
    searchQuery: string;
    isLoading: boolean;
    isStartupLoading?: boolean;
    busyKey: string | null;
    loadError: string | null;
    onViewModeChange: (mode: ProcessViewMode) => void;
    onFilterModeChange: (filter: ProcessFilterMode) => void;
    onSearchChange: (value: string) => void;
    onRefresh: () => void;
    onRefreshStartup?: () => void;
    onKillProcess: (proc: ProcessItem) => void;
    onKillGroup?: (displayName: string, procs: ProcessItem[]) => void;
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
    startupEntries,
    viewMode,
    filterMode,
    searchQuery,
    isLoading,
    isStartupLoading = false,
    busyKey,
    loadError,
    onViewModeChange,
    onFilterModeChange,
    onSearchChange,
    onRefresh,
    onRefreshStartup,
    onKillProcess,
    onKillGroup,
    onUpdateList
  }: Props = $props();

  let newProcessName = $state('');
  let showOsCore = $state(false);
  let expandedGroups = $state<Record<string, boolean>>({});
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

  function protectionRank(kind?: ProcessProtectionKind | null): number {
    if (kind === 'os_core') return 4;
    if (kind === 'self_app') return 3;
    if (kind === 'anticheat') return 2;
    if (kind === 'game_client') return 1;
    return 0;
  }

  function protectionBadge(kind: ProcessProtectionKind | null): {
    label: string;
    cls: string;
  } | null {
    switch (kind) {
      case 'os_core':
        return {
          label: 'Ядро Windows',
          cls: 'bg-[var(--bg-elevated)] text-[var(--text-secondary)] border-[var(--border-subtle)]'
        };
      case 'self_app':
        return {
          label: 'Это приложение',
          cls: 'bg-[var(--accent-soft)] text-[var(--accent-text)] border-[var(--accent-border)]'
        };
      case 'anticheat':
        return {
          label: 'Античит',
          cls: 'bg-[var(--status-active-soft)] text-[var(--status-active-text)] border-[var(--status-active-border)]'
        };
      case 'game_client':
        return {
          label: 'Игровой клиент',
          cls: 'bg-[var(--status-active-soft)] text-[var(--status-active-text)] border-[var(--status-active-border)]'
        };
      default:
        return null;
    }
  }

  const groupedProcesses = $derived.by(() => {
    const map = new Map<string, GroupedProcess>();
    for (const p of processes) {
      const key = p.name.toLowerCase();
      const rawKind: ProcessProtectionKind | null =
        p.protectionKind ?? (p.isProtected ? 'os_core' : null);
      const existing = map.get(key);
      if (!existing) {
        const cleanDisp =
          p.displayName && p.displayName.trim().length > 0 ? p.displayName.trim() : p.name;
        map.set(key, {
          key,
          name: p.name,
          displayName: cleanDisp,
          totalMemoryMb: p.memoryMb,
          pids: [p],
          isProtected: p.isProtected,
          protectionKind: rawKind,
          isBlacklisted: p.isBlacklisted,
          isStartupProtected: p.isStartupProtected
        });
      } else {
        existing.totalMemoryMb = Math.round((existing.totalMemoryMb + p.memoryMb) * 10) / 10;
        existing.pids.push(p);
        existing.isProtected = existing.isProtected || p.isProtected;
        existing.isBlacklisted = existing.isBlacklisted || p.isBlacklisted;
        existing.isStartupProtected = existing.isStartupProtected || p.isStartupProtected;
        if (protectionRank(rawKind) > protectionRank(existing.protectionKind)) {
          existing.protectionKind = rawKind;
        }
        if (
          existing.displayName.toLowerCase() === existing.name.toLowerCase() &&
          p.displayName &&
          p.displayName.trim().toLowerCase() !== p.name.toLowerCase()
        ) {
          existing.displayName = p.displayName.trim();
        }
      }
    }

    const list = Array.from(map.values());
    for (const grp of list) {
      grp.pids.sort((a, b) => b.memoryMb - a.memoryMb);
    }
    list.sort((a, b) => {
      if (b.totalMemoryMb !== a.totalMemoryMb) return b.totalMemoryMb - a.totalMemoryMb;
      return a.displayName.toLowerCase().localeCompare(b.displayName.toLowerCase());
    });
    return list;
  });

  const osCoreGroupCount = $derived(
    groupedProcesses.filter((g) => g.protectionKind === 'os_core').length
  );

  const nonCoreGroupCount = $derived(groupedProcesses.length - osCoreGroupCount);

  const filteredGroups = $derived.by(() => {
    return groupedProcesses.filter((g) => {
      if (!showOsCore && g.protectionKind === 'os_core') return false;
      if (filterMode === 'autoclose' && !g.isBlacklisted) return false;
      if (filterMode === 'protected' && !g.isProtected && !g.isStartupProtected) return false;
      if (!normalizedQuery) return true;
      return (
        g.name.toLowerCase().includes(normalizedQuery) ||
        g.displayName.toLowerCase().includes(normalizedQuery) ||
        g.pids.some((p) => String(p.pid).includes(normalizedQuery))
      );
    });
  });

  $effect(() => {
    void normalizedQuery;
    void filterMode;
    void viewMode;
    void showOsCore;
    visibleLiveLimit = 60;
  });

  const visibleGroups = $derived(filteredGroups.slice(0, visibleLiveLimit));

  const runningDisplayMap = $derived.by(() => {
    const m = new Map<string, string>();
    for (const g of groupedProcesses) {
      if (g.displayName.toLowerCase() !== g.name.toLowerCase()) {
        m.set(g.name.toLowerCase(), g.displayName);
      }
    }
    return m;
  });

  const filteredBlacklistNames = $derived.by(() => {
    if (!normalizedQuery) return blacklistProcesses;
    return blacklistProcesses.filter((n) => {
      const disp = runningDisplayMap.get(n.toLowerCase()) ?? '';
      return (
        n.toLowerCase().includes(normalizedQuery) || disp.toLowerCase().includes(normalizedQuery)
      );
    });
  });

  const filteredStartupEntries = $derived.by(() => {
    if (!normalizedQuery) return startupEntries;
    return startupEntries.filter(
      (e) =>
        e.name.toLowerCase().includes(normalizedQuery) ||
        e.displayName.toLowerCase().includes(normalizedQuery) ||
        e.target.toLowerCase().includes(normalizedQuery) ||
        e.sourceLabel.toLowerCase().includes(normalizedQuery)
    );
  });

  const filteredProtectedNames = $derived.by(() => {
    if (!normalizedQuery) return protectedStartupNames;
    return protectedStartupNames.filter((n) => n.toLowerCase().includes(normalizedQuery));
  });

  const hasActiveFilters = $derived(
    searchQuery.trim().length > 0 || (viewMode === 'running' && filterMode !== 'all')
  );

  function resetFilters() {
    onSearchChange('');
    onFilterModeChange('all');
  }

  function toggleExpandGroup(key: string) {
    expandedGroups = { ...expandedGroups, [key]: !expandedGroups[key] };
  }

  function handleKillGroupOrSingle(group: GroupedProcess) {
    if (group.pids.length === 1) {
      onKillProcess(group.pids[0]);
    } else if (onKillGroup) {
      onKillGroup(group.displayName, group.pids);
    } else {
      onKillProcess(group.pids[0]);
    }
  }

  async function handleAddSubmit(e: SubmitEvent) {
    e.preventDefault();
    const cleaned = newProcessName.trim().replace(/\.exe$/i, '');
    if (!cleaned) return;
    const targetType: ProcessListType = viewMode === 'startup' ? 'protected' : 'blacklist';
    await onUpdateList(targetType, cleaned, 'add');
    newProcessName = '';
  }

  function handleRefreshActiveView() {
    if (viewMode === 'startup' && onRefreshStartup) {
      onRefreshStartup();
    } else {
      onRefresh();
    }
  }
</script>

<div class="space-y-4">
  <!-- Header & Mode Toggle -->
  <section class="ui-card rounded-2xl p-5 space-y-4">
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
      <div class="space-y-1">
        <h1 class="text-base font-semibold text-[var(--text-primary)]">
          Программы и автозагрузка Windows
        </h1>
        <p class="text-sm text-[var(--text-secondary)]">
          Выберите, какие фоновые программы закрывать при запуске игрового режима и что оставлять в автозагрузке Windows.
        </p>
      </div>

      <button
        type="button"
        onclick={handleRefreshActiveView}
        disabled={isLoading || isStartupLoading}
        class="ui-btn-secondary ui-pressable rounded-lg px-3.5 py-2 min-h-9 text-[0.8125rem] font-medium flex items-center gap-1.5 shrink-0 self-start sm:self-center disabled:opacity-55 disabled:cursor-not-allowed cursor-pointer"
      >
        <RefreshCw
          size={14}
          strokeWidth={1.75}
          class={isLoading || isStartupLoading ? 'ui-spin' : ''}
          aria-hidden="true"
        />
        <span>Обновить</span>
      </button>
    </div>

    <!-- Segmented View Toggle + Search -->
    <div class="flex flex-col lg:flex-row lg:items-center gap-3">
      <div
        class="inline-flex flex-wrap gap-1.5 p-1 rounded-xl bg-[var(--bg-elevated)] border border-[var(--border-subtle)]"
        role="group"
        aria-label="Раздел программ и автозагрузки"
      >
        <button
          type="button"
          onclick={() => onViewModeChange('running')}
          aria-pressed={viewMode === 'running'}
          class="{viewMode === 'running'
            ? 'ui-btn-primary'
            : 'ui-btn-ghost'} ui-pressable rounded-lg px-3 py-2 min-h-9 text-[0.8125rem] font-medium flex items-center gap-2 cursor-pointer"
        >
          <Activity size={15} strokeWidth={1.75} aria-hidden="true" />
          <span>Запущены сейчас</span>
          <span class="tabular-nums opacity-90">({nonCoreGroupCount})</span>
        </button>

        <button
          type="button"
          onclick={() => onViewModeChange('autoclose')}
          aria-pressed={viewMode === 'autoclose'}
          class="{viewMode === 'autoclose'
            ? 'ui-btn-primary'
            : 'ui-btn-ghost'} ui-pressable rounded-lg px-3 py-2 min-h-9 text-[0.8125rem] font-medium flex items-center gap-2 cursor-pointer"
        >
          <Power size={15} strokeWidth={1.75} aria-hidden="true" />
          <span>Закрывать в игре</span>
          <span class="tabular-nums opacity-90">({blacklistProcesses.length})</span>
        </button>

        <button
          type="button"
          onclick={() => onViewModeChange('startup')}
          aria-pressed={viewMode === 'startup'}
          class="{viewMode === 'startup'
            ? 'ui-btn-primary'
            : 'ui-btn-ghost'} ui-pressable rounded-lg px-3 py-2 min-h-9 text-[0.8125rem] font-medium flex items-center gap-2 cursor-pointer"
        >
          <ShieldCheck size={15} strokeWidth={1.75} aria-hidden="true" />
          <span>Автозагрузка Windows</span>
          <span class="tabular-nums opacity-90">({startupEntries.length})</span>
        </button>
      </div>

      <div class="relative flex-1 min-w-0">
        <label for="processes-search" class="sr-only">
          Поиск программ по названию, процессу или PID
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
          placeholder={viewMode === 'running'
            ? 'Найти программу, .exe или PID…'
            : viewMode === 'autoclose'
              ? 'Найти в списке автозакрытия…'
              : 'Найти в автозагрузке Windows…'}
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

    {#if viewMode === 'running'}
      <div class="flex flex-wrap items-center justify-between gap-2 pt-1">
        <div class="flex flex-wrap items-center gap-1.5" role="group" aria-label="Фильтр программ">
          <span class="inline-flex items-center gap-1 text-xs font-medium text-[var(--text-muted)] mr-1">
            <ListFilter size={13} strokeWidth={1.75} aria-hidden="true" />
            <span>Показать:</span>
          </span>
          {#each [
            { id: 'all', label: 'Все программы' },
            { id: 'autoclose', label: 'Закрываются в игре' },
            { id: 'protected', label: 'Защищённые / Античиты' }
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

        <div class="flex flex-wrap items-center gap-3">
          <label class="inline-flex items-center gap-2 text-xs font-medium text-[var(--text-secondary)] cursor-pointer select-none">
            <input
              type="checkbox"
              bind:checked={showOsCore}
              class="w-4 h-4 rounded accent-[var(--accent-solid)] cursor-pointer"
            />
            <span>Показать системные процессы Windows ({osCoreGroupCount})</span>
          </label>

          <p class="text-[0.8125rem] text-[var(--text-muted)] tabular-nums" aria-live="polite">
            {visibleGroups.length} из {filteredGroups.length} программ
          </p>
        </div>
      </div>
    {:else}
      <form onsubmit={handleAddSubmit} class="flex flex-col sm:flex-row gap-2 pt-1">
        <label for="new-process-input" class="sr-only">
          Имя процесса для добавления в правило
        </label>
        <input
          id="new-process-input"
          type="text"
          autocomplete="off"
          spellcheck={false}
          bind:value={newProcessName}
          placeholder={viewMode === 'autoclose'
            ? 'Имя процесса для автозакрытия в игре (например: EpicGamesLauncher)…'
            : 'Добавить шаблон исключения автозагрузки (например: ctfmon)…'}
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
      <span>Сканирую запущенные программы Windows…</span>
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
            Не удалось получить список программ
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
  {:else if viewMode === 'running'}
    {#if filteredGroups.length === 0}
      <div class="ui-card rounded-2xl p-8 text-center space-y-3">
        <p class="text-sm font-semibold text-[var(--text-primary)]">
          Программы не найдены
        </p>
        <p class="text-sm text-[var(--text-secondary)]">
          {showOsCore
            ? 'Измените поисковый запрос или сбросьте фильтр.'
            : 'Возможно, нужный системный процесс скрыт фильтром ядра Windows.'}
        </p>
        <div class="flex flex-wrap justify-center gap-2">
          {#if !showOsCore && osCoreGroupCount > 0}
            <button
              type="button"
              onclick={() => (showOsCore = true)}
              class="ui-btn-secondary ui-pressable rounded-lg px-4 py-2 min-h-9 text-[0.8125rem] font-medium cursor-pointer"
            >
              Показать системные ({osCoreGroupCount})
            </button>
          {/if}
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
      </div>
    {:else}
      <ul class="ui-card rounded-2xl divide-y divide-[var(--border-subtle)] overflow-hidden">
        {#each visibleGroups as group (group.key)}
          {@const rowBusy =
            busyKey === `proc:${group.name}` ||
            busyKey === `killgroup:${group.name}` ||
            group.pids.some((p) => busyKey === `kill:${p.pid}`)}
          {@const badge = protectionBadge(group.protectionKind)}
          {@const expanded = Boolean(expandedGroups[group.key])}
          {@const hasSeparateExeName =
            group.displayName.toLowerCase() !== group.name.toLowerCase()}
          <li class="p-3.5 sm:px-4 space-y-2.5">
            <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
              <div class="min-w-0 flex-1 space-y-1">
                <div class="flex flex-wrap items-center gap-2">
                  <span class="text-sm font-semibold text-[var(--text-primary)] break-words">
                    {group.displayName}
                  </span>

                  {#if hasSeparateExeName}
                    <code
                      translate="no"
                      class="font-mono text-xs px-2 py-0.5 rounded-md bg-[var(--bg-elevated)] text-[var(--text-secondary)]"
                    >
                      {group.name}.exe
                    </code>
                  {:else}
                    <code
                      translate="no"
                      class="font-mono text-xs px-2 py-0.5 rounded-md bg-[var(--bg-elevated)] text-[var(--text-secondary)]"
                    >
                      {group.name}
                    </code>
                  {/if}

                  <span class="text-xs font-medium text-[var(--text-muted)] tabular-nums">
                    {group.totalMemoryMb.toFixed(1)} МБ
                  </span>

                  {#if group.pids.length > 1}
                    <button
                      type="button"
                      onclick={() => toggleExpandGroup(group.key)}
                      aria-expanded={expanded}
                      class="inline-flex items-center gap-1 rounded-md px-2 py-0.5 text-xs font-medium bg-[var(--bg-elevated)] text-[var(--accent-text)] border border-[var(--border-subtle)] hover:bg-[var(--bg-hover)] cursor-pointer tabular-nums"
                    >
                      {#if expanded}
                        <ChevronDown size={12} strokeWidth={2} aria-hidden="true" />
                      {:else}
                        <ChevronRight size={12} strokeWidth={2} aria-hidden="true" />
                      {/if}
                      <span>{group.pids.length} процессов</span>
                    </button>
                  {:else}
                    <span class="text-xs text-[var(--text-muted)] tabular-nums">
                      PID {group.pids[0].pid}
                    </span>
                  {/if}

                  {#if badge}
                    <span
                      class="inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-medium border {badge.cls}"
                    >
                      <Shield size={11} strokeWidth={2} aria-hidden="true" />
                      <span>{badge.label}</span>
                    </span>
                  {/if}

                  {#if group.isStartupProtected}
                    <span
                      class="inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-medium bg-[var(--accent-soft)] text-[var(--accent-text)] border border-[var(--accent-border)]"
                    >
                      <ShieldCheck size={11} strokeWidth={2} aria-hidden="true" />
                      <span>Остаётся в автозагрузке</span>
                    </span>
                  {/if}
                </div>
              </div>

              <div class="flex flex-wrap items-center gap-3 shrink-0">
                {#if !group.isProtected}
                  <div class="flex items-center gap-2">
                    <span
                      id="autoclose-lbl-{group.key}"
                      class="text-xs font-medium {group.isBlacklisted
                        ? 'text-[var(--status-warn-text)]'
                        : 'text-[var(--text-muted)]'}"
                    >
                      Закрывать в игре
                    </span>
                    <button
                      type="button"
                      role="switch"
                      aria-checked={group.isBlacklisted}
                      aria-labelledby="autoclose-lbl-{group.key}"
                      disabled={rowBusy || busyKey !== null}
                      onclick={() =>
                        onUpdateList(
                          'blacklist',
                          group.name,
                          group.isBlacklisted ? 'remove' : 'add'
                        )}
                      class="ui-switch relative inline-flex items-center w-10 h-5 rounded-full shrink-0 disabled:opacity-50 cursor-pointer"
                    >
                      <span
                        class="ui-switch-thumb pointer-events-none block w-3.5 h-3.5 rounded-full {group.isBlacklisted
                          ? 'translate-x-[21px]'
                          : 'translate-x-[3px]'}"
                      ></span>
                    </button>
                  </div>

                  <button
                    type="button"
                    disabled={rowBusy || busyKey !== null}
                    onclick={() => handleKillGroupOrSingle(group)}
                    class="ui-btn-warn ui-pressable rounded-lg px-2.5 py-1.5 min-h-8 text-xs font-medium inline-flex items-center gap-1.5 disabled:opacity-50 cursor-pointer"
                  >
                    <Skull size={13} strokeWidth={1.75} aria-hidden="true" />
                    <span>Закрыть сейчас</span>
                  </button>
                {:else}
                  <span class="text-xs text-[var(--text-muted)] px-1">
                    {group.protectionKind === 'anticheat'
                      ? 'Защита античита'
                      : group.protectionKind === 'game_client'
                        ? 'Нельзя закрывать из игры'
                        : 'Системный компонент'}
                  </span>
                {/if}
              </div>
            </div>

            {#if expanded && group.pids.length > 1}
              <ul class="ml-3 pl-3 border-l border-[var(--border-subtle)] space-y-1.5">
                {#each group.pids as proc (proc.pid)}
                  <li class="flex items-center justify-between gap-2 text-xs text-[var(--text-secondary)]">
                    <div class="flex items-center gap-2 tabular-nums">
                      <code translate="no" class="font-mono px-1.5 py-0.5 rounded bg-[var(--bg-elevated)]">
                        PID {proc.pid}
                      </code>
                      <span class="text-[var(--text-muted)]">{proc.memoryMb.toFixed(1)} МБ</span>
                    </div>

                    {#if !proc.isProtected}
                      <button
                        type="button"
                        disabled={busyKey !== null}
                        onclick={() => onKillProcess(proc)}
                        class="ui-btn-ghost rounded-md px-2 py-1 text-xs font-medium text-[var(--status-warn-text)] hover:bg-[var(--status-warn-soft)] disabled:opacity-50 cursor-pointer"
                      >
                        Закрыть PID {proc.pid}
                      </button>
                    {/if}
                  </li>
                {/each}
              </ul>
            {/if}
          </li>
        {/each}
      </ul>
      {#if filteredGroups.length > visibleGroups.length}
        <div class="flex justify-center pt-1">
          <button
            type="button"
            onclick={() => (visibleLiveLimit += 60)}
            class="ui-btn-secondary ui-pressable rounded-xl px-4 py-2 min-h-9 text-[0.8125rem] font-medium cursor-pointer"
          >
            Показать ещё ({Math.min(60, filteredGroups.length - visibleGroups.length)} из {filteredGroups.length - visibleGroups.length} оставшихся)
          </button>
        </div>
      {/if}
    {/if}
  {:else if viewMode === 'autoclose'}
    <div class="ui-card rounded-2xl p-4 sm:p-5 space-y-3">
      <p class="text-[0.8125rem] text-[var(--text-secondary)]">
        Эти программы автоматически закрываются при включении игрового режима (чтобы не занимать ОЗУ и процессор во время игры). Защищённые процессы ОС, античиты и это приложение не затрагиваются.
      </p>
      {#if filteredBlacklistNames.length === 0}
        <p class="text-sm text-[var(--text-muted)] py-4 text-center">Список пуст.</p>
      {:else}
        <ul class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2.5">
          {#each filteredBlacklistNames as name (name)}
            {@const friendly = runningDisplayMap.get(name.toLowerCase())}
            <li
              class="rounded-xl px-3.5 py-2.5 bg-[var(--bg-elevated)] border border-[var(--border-subtle)] flex items-center justify-between gap-2 min-w-0"
            >
              <div class="min-w-0">
                <div class="text-[0.8125rem] font-medium text-[var(--text-primary)] truncate">
                  {friendly ?? name}
                </div>
                {#if friendly}
                  <code translate="no" class="font-mono text-xs text-[var(--text-muted)] truncate block">
                    {name}.exe
                  </code>
                {/if}
              </div>
              <button
                type="button"
                disabled={busyKey !== null}
                onclick={() => onUpdateList('blacklist', name, 'remove')}
                aria-label={`Не закрывать ${name} в игровом режиме`}
                title="Убрать из автозакрытия"
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
    <!-- Windows Startup View -->
    <div class="space-y-4">
      <section class="ui-card rounded-2xl p-4 sm:p-5 space-y-3">
        <div class="space-y-1">
          <h2 class="text-sm font-semibold text-[var(--text-primary)]">
            Программы в автозагрузке Windows
          </h2>
          <p class="text-[0.8125rem] text-[var(--text-secondary)]">
            При входе в игровой режим автозагрузка временно приостанавливается (а при выходе полностью возвращается на место). Включите «Оставлять в игре» для программ, которые нужны при запуске ПК в игровом режиме.
          </p>
        </div>

        {#if isStartupLoading && startupEntries.length === 0}
          <div class="py-6 flex items-center justify-center gap-2.5 text-sm text-[var(--text-secondary)]">
            <Loader2 size={16} strokeWidth={2} class="ui-spin text-[var(--accent-text)]" aria-hidden="true" />
            <span>Сканирую автозагрузку Windows…</span>
          </div>
        {:else if filteredStartupEntries.length === 0}
          <p class="text-sm text-[var(--text-muted)] py-4 text-center">
            Элементы автозагрузки не найдены.
          </p>
        {:else}
          <ul class="divide-y divide-[var(--border-subtle)] rounded-xl border border-[var(--border-subtle)] overflow-hidden">
            {#each filteredStartupEntries as entry (entry.id)}
              <li class="p-3.5 bg-[var(--bg-surface)] flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                <div class="min-w-0 flex-1 space-y-1">
                  <div class="flex flex-wrap items-center gap-2">
                    <span class="text-sm font-medium text-[var(--text-primary)] break-words">
                      {entry.displayName}
                    </span>
                    <span class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium bg-[var(--bg-elevated)] text-[var(--text-secondary)] border border-[var(--border-subtle)]">
                      {entry.sourceLabel}
                    </span>
                    <span
                      class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium border {entry.enabled
                        ? 'bg-[var(--status-active-soft)] text-[var(--status-active-text)] border-[var(--status-active-border)]'
                        : 'bg-[var(--bg-elevated)] text-[var(--text-muted)] border-[var(--border-subtle)]'}"
                    >
                      {entry.enabled ? 'Вкл в Windows' : 'Откл в Windows'}
                    </span>
                  </div>
                  {#if entry.target}
                    <p translate="no" class="font-mono text-xs text-[var(--text-muted)] truncate" title={entry.target}>
                      {entry.target}
                    </p>
                  {/if}
                </div>

                <div class="flex items-center gap-2.5 shrink-0">
                  <span
                    id="startup-keep-{entry.id}"
                    class="text-xs font-medium {entry.isProtected
                      ? 'text-[var(--status-active-text)]'
                      : 'text-[var(--text-muted)]'}"
                  >
                    Оставлять в игре
                  </span>
                  <button
                    type="button"
                    role="switch"
                    aria-checked={entry.isProtected}
                    aria-labelledby="startup-keep-{entry.id}"
                    disabled={busyKey !== null}
                    onclick={() =>
                      onUpdateList(
                        'protected',
                        entry.isProtected ? (entry.matchedRule ?? entry.name) : entry.name,
                        entry.isProtected ? 'remove' : 'add'
                      )}
                    class="ui-switch relative inline-flex items-center w-10 h-5 rounded-full shrink-0 disabled:opacity-50 cursor-pointer"
                  >
                    <span
                      class="ui-switch-thumb pointer-events-none block w-3.5 h-3.5 rounded-full {entry.isProtected
                        ? 'translate-x-[21px]'
                        : 'translate-x-[3px]'}"
                    ></span>
                  </button>
                </div>
              </li>
            {/each}
          </ul>
        {/if}
      </section>

      <section class="ui-card rounded-2xl p-4 sm:p-5 space-y-3">
        <div class="space-y-0.5">
          <h3 class="text-sm font-semibold text-[var(--text-primary)]">
            Сохранённые шаблоны исключений ({filteredProtectedNames.length})
          </h3>
          <p class="text-xs text-[var(--text-secondary)]">
            Совпадения по имени (<code translate="no" class="font-mono">ProtectedStartupNames</code>), которые никогда не скрываются при переходе в игровой режим.
          </p>
        </div>
        {#if filteredProtectedNames.length === 0}
          <p class="text-sm text-[var(--text-muted)] py-2 text-center">Список правил пуст.</p>
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
                  aria-label={`Удалить правило ${name}`}
                  class="ui-btn-ghost w-7 h-7 rounded-lg flex items-center justify-center shrink-0 text-[var(--text-muted)] hover:text-[var(--status-danger-text)] cursor-pointer"
                >
                  <Trash2 size={14} strokeWidth={1.75} aria-hidden="true" />
                </button>
              </li>
            {/each}
          </ul>
        {/if}
      </section>
    </div>
  {/if}
</div>
