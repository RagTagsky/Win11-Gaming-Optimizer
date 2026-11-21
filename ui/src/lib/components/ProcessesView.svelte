<script lang="ts">
  import { onDestroy } from 'svelte';
  import {
    AlertCircle,
    FilterX,
    Info,
    Loader2,
    Lock,
    Plus,
    RefreshCw,
    Search,
    X
  } from '@lucide/svelte';
  import ItemTooltip, { type TooltipPayload } from './ItemTooltip.svelte';
  import type {
    ProcessDescriptionEntry,
    ProcessItem,
    ProcessProtectionKind,
    SafetyLevel
  } from '../types';

  export type ProcessFilterMode = 'all' | 'disable' | 'normal';

  interface UnifiedProcessItem {
    key: string;
    name: string;
    displayName: string;
    isRunning: boolean;
    totalMemoryMb: number;
    instanceCount: number;
    isProtected: boolean;
    protectionKind: ProcessProtectionKind | null;
    disableInGaming: boolean;
    inStartup: boolean;
    summaryRu: string;
    canDisableHint: string;
    safetyLevel: SafetyLevel;
  }

  interface Props {
    active?: boolean;
    processes: ProcessItem[];
    blacklistProcesses: string[];
    protectedStartupNames: string[];
    processDescriptions?: Record<string, ProcessDescriptionEntry>;
    startupProcessNames?: string[];
    filterMode: ProcessFilterMode;
    searchQuery: string;
    isLoading: boolean;
    busyKey: string | null;
    loadError: string | null;
    onFilterModeChange: (filter: ProcessFilterMode) => void;
    onSearchChange: (value: string) => void;
    onRefresh: () => void;
    onSetProcessMode: (
      processName: string,
      disableInGaming: boolean,
      safetyLevel?: SafetyLevel
    ) => Promise<boolean> | boolean | Promise<void> | void;
  }

  let {
    active = true,
    processes = [],
    blacklistProcesses = [],
    protectedStartupNames = [],
    processDescriptions = {},
    startupProcessNames = [],
    filterMode,
    searchQuery,
    isLoading,
    busyKey,
    loadError,
    onFilterModeChange,
    onSearchChange,
    onRefresh,
    onSetProcessMode
  }: Props = $props();

  let showOsCore = $state(false);
  let showAddForm = $state(false);
  let newProcessName = $state('');
  let visibleLimit = $state(60);
  let debouncedQuery = $state('');
  let searchDebounceHandle: ReturnType<typeof setTimeout> | undefined;

  // Hover / keyboard tooltip state (payload derived reactively so it never goes stale)
  let activeAnchorEl = $state<HTMLElement | null>(null);
  let activeTooltipKey = $state<string | null>(null);
  let pinnedTooltipKey = $state<string | null>(null);
  let suppressFocusOpen = false;
  let openTimer: ReturnType<typeof setTimeout> | undefined;
  let closeTimer: ReturnType<typeof setTimeout> | undefined;

  function clearTooltipTimers() {
    if (openTimer) {
      clearTimeout(openTimer);
      openTimer = undefined;
    }
    if (closeTimer) {
      clearTimeout(closeTimer);
      closeTimer = undefined;
    }
  }

  function dismissTooltip() {
    clearTooltipTimers();
    activeAnchorEl = null;
    activeTooltipKey = null;
    pinnedTooltipKey = null;
  }

  onDestroy(() => {
    clearTooltipTimers();
    clearTimeout(searchDebounceHandle);
  });

  function stripExe(name: string): string {
    return name.trim().replace(/\.exe$/i, '');
  }

  function protectionRank(kind?: ProcessProtectionKind | null): number {
    if (kind === 'os_core') return 5;
    if (kind === 'self_app') return 4;
    if (kind === 'anticheat') return 3;
    if (kind === 'game_client') return 2;
    if (kind === 'network_bypass') return 1;
    return 0;
  }

  function protectionLabel(kind: ProcessProtectionKind | null): string {
    switch (kind) {
      case 'os_core':
        return 'Ядро Windows';
      case 'self_app':
        return 'Это приложение';
      case 'anticheat':
        return 'Античит';
      case 'game_client':
        return 'Игровой клиент';
      case 'network_bypass':
        return 'Zapret / Сеть';
      default:
        return 'Защищено';
    }
  }

  function normalizeSafety(raw?: string, isProtected = false): SafetyLevel {
    if (isProtected) return 'protected';
    if (raw === 'safe' || raw === 'optional' || raw === 'protected') return raw;
    return 'optional';
  }

  function safetyDotClass(level: SafetyLevel): string {
    if (level === 'safe') return 'bg-[var(--status-active-text)]';
    if (level === 'protected') return 'bg-[var(--status-danger-text)]';
    return 'bg-[var(--status-warn-text)]';
  }

  function formatMem(mb: number): string {
    if (mb >= 1024) return `${(mb / 1024).toFixed(1)} ГБ`;
    if (mb >= 10) return `${Math.round(mb)} МБ`;
    return `${mb.toFixed(1)} МБ`;
  }

  function buildProcessTooltip(item: UnifiedProcessItem): TooltipPayload {
    const statusPart = item.isRunning
      ? `Работает · ${formatMem(item.totalMemoryMb)}${item.instanceCount > 1 ? ` · ${item.instanceCount} проц.` : ''}`
      : 'Не запущен (настроенное правило)';
    const startupPart = item.inStartup ? 'Есть в автозагрузке Windows' : '';
    const modePart = item.isProtected
      ? `Защищено (${protectionLabel(item.protectionKind)})`
      : item.disableInGaming
        ? 'Выкл. в Gaming Mode'
        : 'Без утилки';

    return {
      id: item.key,
      title: item.displayName,
      subtitle: `${item.name}.exe`,
      safetyLevel: item.safetyLevel,
      summary: item.summaryRu,
      impact: item.canDisableHint,
      metaNote: [statusPart, startupPart, `Режим: ${modePart}`].filter(Boolean).join(' · ')
    };
  }

  function scheduleOpenTooltip(item: UnifiedProcessItem, anchor: HTMLElement, immediate = false) {
    if (pinnedTooltipKey !== null && !immediate) {
      return;
    }
    if (closeTimer) {
      clearTimeout(closeTimer);
      closeTimer = undefined;
    }
    const show = () => {
      activeAnchorEl = anchor;
      activeTooltipKey = item.key;
    };
    if (immediate || activeTooltipKey !== null) {
      if (openTimer) {
        clearTimeout(openTimer);
        openTimer = undefined;
      }
      show();
    } else {
      if (openTimer) clearTimeout(openTimer);
      openTimer = setTimeout(() => {
        openTimer = undefined;
        show();
      }, 130);
    }
  }

  function scheduleCloseTooltip() {
    if (pinnedTooltipKey !== null) return;
    if (openTimer) {
      clearTimeout(openTimer);
      openTimer = undefined;
    }
    if (closeTimer) clearTimeout(closeTimer);
    closeTimer = setTimeout(() => {
      closeTimer = undefined;
      activeAnchorEl = null;
      activeTooltipKey = null;
    }, 140);
  }

  function cancelCloseTooltip() {
    if (closeTimer) {
      clearTimeout(closeTimer);
      closeTimer = undefined;
    }
  }

  function togglePinnedTooltip(item: UnifiedProcessItem, anchor: HTMLElement) {
    suppressFocusOpen = false;
    clearTooltipTimers();
    if (pinnedTooltipKey === item.key) {
      dismissTooltip();
    } else {
      pinnedTooltipKey = item.key;
      activeTooltipKey = item.key;
      activeAnchorEl = anchor;
    }
  }

  $effect(() => {
    const target = searchQuery.trim().toLowerCase();
    clearTimeout(searchDebounceHandle);
    if (!target) {
      debouncedQuery = '';
      return;
    }
    searchDebounceHandle = setTimeout(() => {
      debouncedQuery = target;
    }, 110);
    return () => clearTimeout(searchDebounceHandle);
  });

  const normalizedQuery = $derived(debouncedQuery);

  const unifiedProcesses = $derived.by((): UnifiedProcessItem[] => {
    const blSet = new Set(blacklistProcesses.map((n) => stripExe(n).toLowerCase()).filter(Boolean));
    const protStartupSet = new Set(
      protectedStartupNames.map((n) => stripExe(n).toLowerCase()).filter(Boolean)
    );
    const startupSet = new Set(
      startupProcessNames.map((n) => stripExe(n).toLowerCase()).filter(Boolean)
    );

    const map = new Map<string, UnifiedProcessItem>();

    // 1. Group currently running processes
    for (const p of processes) {
      const cleanName = stripExe(p.name);
      const key = cleanName.toLowerCase();
      if (!key) continue;

      const rawKind: ProcessProtectionKind | null =
        p.protectionKind ?? (p.isProtected ? 'os_core' : null);
      const isProtected = Boolean(p.isProtected || rawKind !== null);
      const disableInGaming = !isProtected && blSet.has(key) && !protStartupSet.has(key);
      const inStartup = Boolean(p.inStartup || startupSet.has(key));
      const curated = processDescriptions[key];
      const cleanDisp =
        p.displayName && p.displayName.trim().length > 0
          ? p.displayName.trim()
          : curated?.displayNameRu?.trim() || cleanName;
      const summary =
        p.summaryRu?.trim() ||
        curated?.summaryRu?.trim() ||
        `Фоновый процесс программы (${cleanName}.exe).`;
      const impact =
        p.canDisableHint?.trim() ||
        curated?.canDisableRu?.trim() ||
        (isProtected
          ? 'Системный или защищённый компонент — отключать нельзя.'
          : 'Сторонняя программа. Выключайте в Gaming Mode, если она не нужна во время игры.');
      const safety = normalizeSafety(p.safetyLevel ?? curated?.safetyLevel, isProtected);

      const existing = map.get(key);
      if (!existing) {
        map.set(key, {
          key,
          name: cleanName,
          displayName: cleanDisp,
          isRunning: true,
          totalMemoryMb: p.memoryMb,
          instanceCount: 1,
          isProtected,
          protectionKind: rawKind,
          disableInGaming,
          inStartup,
          summaryRu: summary,
          canDisableHint: impact,
          safetyLevel: safety
        });
      } else {
        existing.totalMemoryMb = Math.round((existing.totalMemoryMb + p.memoryMb) * 10) / 10;
        existing.instanceCount += 1;
        existing.isProtected = existing.isProtected || isProtected;
        existing.inStartup = existing.inStartup || inStartup;
        if (protectionRank(rawKind) > protectionRank(existing.protectionKind)) {
          existing.protectionKind = rawKind;
        }
        existing.disableInGaming =
          !existing.isProtected && blSet.has(key) && !protStartupSet.has(key);
        if (existing.isProtected) {
          existing.safetyLevel = 'protected';
        }
        if (
          existing.displayName.toLowerCase() === existing.name.toLowerCase() &&
          cleanDisp.toLowerCase() !== cleanName.toLowerCase()
        ) {
          existing.displayName = cleanDisp;
        }
      }
    }

    // 2. Append configured offline rules (so Discord, Spotify, Widgets, etc. are toggleable even when closed)
    const configuredRules = [...blacklistProcesses, ...protectedStartupNames];
    for (const rawRule of configuredRules) {
      const cleanName = stripExe(rawRule);
      const key = cleanName.toLowerCase();
      if (!key || map.has(key)) continue;

      const desc = processDescriptions[key];
      const protKind: ProcessProtectionKind | null = desc?.protectionKind ?? null;
      const isProtected = protKind !== null;
      const disableInGaming = !isProtected && blSet.has(key) && !protStartupSet.has(key);
      const inStartup = startupSet.has(key);
      const safety = normalizeSafety(desc?.safetyLevel, isProtected);

      map.set(key, {
        key,
        name: cleanName,
        displayName: desc?.displayNameRu?.trim() || cleanName,
        isRunning: false,
        totalMemoryMb: 0,
        instanceCount: 0,
        isProtected,
        protectionKind: protKind,
        disableInGaming,
        inStartup,
        summaryRu: desc?.summaryRu?.trim() || `Настроенное правило для процесса ${cleanName}.exe.`,
        canDisableHint:
          desc?.canDisableRu?.trim() ||
          (isProtected
            ? 'Защищённый системный компонент — отключать нельзя.'
            : 'Управляет закрытием процесса и его автозагрузкой при входе в Gaming Mode.'),
        safetyLevel: safety
      });
    }

    const list = Array.from(map.values());
    list.sort((a, b) => {
      if (a.isRunning !== b.isRunning) return a.isRunning ? -1 : 1;
      if (a.isRunning && b.isRunning && b.totalMemoryMb !== a.totalMemoryMb) {
        return b.totalMemoryMb - a.totalMemoryMb;
      }
      if (!a.isRunning && !b.isRunning && a.disableInGaming !== b.disableInGaming) {
        return a.disableInGaming ? -1 : 1;
      }
      return a.displayName.toLowerCase().localeCompare(b.displayName.toLowerCase());
    });
    return list;
  });

  const osCoreCount = $derived(
    unifiedProcesses.filter((item) => item.protectionKind === 'os_core').length
  );

  const visibleScopeItems = $derived.by(() => {
    if (showOsCore || normalizedQuery.length > 0) return unifiedProcesses;
    return unifiedProcesses.filter((item) => item.protectionKind !== 'os_core');
  });

  const totalCount = $derived(visibleScopeItems.length);
  const disabledCount = $derived(
    visibleScopeItems.filter((item) => item.disableInGaming).length
  );
  const normalCount = $derived(totalCount - disabledCount);
  const runningCount = $derived(
    visibleScopeItems.filter((item) => item.isRunning).length
  );

  const filteredProcesses = $derived.by(() => {
    return visibleScopeItems.filter((item) => {
      if (filterMode === 'disable' && !item.disableInGaming) return false;
      if (filterMode === 'normal' && item.disableInGaming) return false;
      if (!normalizedQuery) return true;
      return (
        item.name.toLowerCase().includes(normalizedQuery) ||
        item.displayName.toLowerCase().includes(normalizedQuery) ||
        item.summaryRu.toLowerCase().includes(normalizedQuery) ||
        item.canDisableHint.toLowerCase().includes(normalizedQuery)
      );
    });
  });

  $effect(() => {
    if (!active) {
      dismissTooltip();
    }
  });

  $effect(() => {
    void normalizedQuery;
    void filterMode;
    void showOsCore;
    visibleLimit = 60;
    dismissTooltip();
  });

  const visibleProcesses = $derived(filteredProcesses.slice(0, visibleLimit));
  const activeTooltip = $derived.by((): TooltipPayload | null => {
    if (!activeTooltipKey) return null;
    const item = visibleProcesses.find((p) => p.key === activeTooltipKey);
    return item ? buildProcessTooltip(item) : null;
  });

  $effect(() => {
    if (activeTooltipKey !== null && activeTooltip === null) {
      clearTooltipTimers();
      activeTooltipKey = null;
      pinnedTooltipKey = null;
      activeAnchorEl = null;
    }
  });

  const hasActiveFilters = $derived(searchQuery.trim().length > 0 || filterMode !== 'all');

  function resetFilters() {
    onSearchChange('');
    onFilterModeChange('all');
  }

  async function handleAddSubmit(e: SubmitEvent) {
    e.preventDefault();
    const cleaned = stripExe(newProcessName);
    if (!cleaned) return;
    dismissTooltip();
    const ok = await onSetProcessMode(cleaned, true);
    if (ok !== false) {
      newProcessName = '';
      showAddForm = false;
    }
  }
</script>

<div class="space-y-4">
  <!-- Header Card -->
  <section class="ui-card rounded-2xl p-5 space-y-4">
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
      <div class="space-y-1">
        <h1 class="text-base font-semibold text-[var(--text-primary)]">
          Процессы в Gaming Mode
        </h1>
        <p class="text-sm text-[var(--text-secondary)]">
          Выберите для каждого процесса: работает <strong class="font-medium text-[var(--text-primary)]">без утилки</strong> (автозагрузка сохраняется) или <strong class="font-medium text-[var(--text-primary)]">выключается в Gaming Mode</strong>. Наведите на любую строку для описания.
        </p>
      </div>

      <div class="flex flex-wrap items-center gap-2 shrink-0 self-start sm:self-center">
        <button
          type="button"
          onclick={() => (showAddForm = !showAddForm)}
          aria-expanded={showAddForm}
          class="ui-btn-ghost ui-pressable rounded-lg px-3 py-2 min-h-9 text-[0.8125rem] font-medium inline-flex items-center gap-1.5 border border-[var(--border-subtle)] cursor-pointer"
        >
          <Plus size={14} strokeWidth={1.85} aria-hidden="true" />
          <span>Добавить процесс</span>
        </button>

        <button
          type="button"
          onclick={onRefresh}
          disabled={isLoading}
          class="ui-btn-secondary ui-pressable rounded-lg px-3.5 py-2 min-h-9 text-[0.8125rem] font-medium flex items-center gap-1.5 disabled:opacity-55 disabled:cursor-not-allowed cursor-pointer"
        >
          <RefreshCw size={14} strokeWidth={1.75} class={isLoading ? 'ui-spin' : ''} aria-hidden="true" />
          <span>Обновить</span>
        </button>
      </div>
    </div>

    {#if showAddForm}
      <form
        onsubmit={handleAddSubmit}
        class="rounded-xl p-3 bg-[var(--bg-elevated)] border border-[var(--border-subtle)] flex flex-col sm:flex-row gap-2"
      >
        <label for="new-process-input" class="sr-only">
          Имя процесса для выключения в Gaming Mode
        </label>
        <input
          id="new-process-input"
          type="text"
          autocomplete="off"
          spellcheck={false}
          bind:value={newProcessName}
          placeholder="Имя процесса (например: EpicGamesLauncher или Telegram)…"
          class="ui-input flex-1 rounded-lg px-3 py-1.5 min-h-9 text-sm"
        />
        <div class="flex items-center gap-2 shrink-0">
          <button
            type="submit"
            disabled={!newProcessName.trim() || busyKey !== null}
            class="ui-btn-primary ui-pressable rounded-lg px-3.5 py-1.5 min-h-9 text-xs font-semibold inline-flex items-center gap-1.5 disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer"
          >
            <Plus size={14} strokeWidth={2} aria-hidden="true" />
            <span>Выкл. в Gaming Mode</span>
          </button>
          <button
            type="button"
            onclick={() => {
              showAddForm = false;
              newProcessName = '';
            }}
            aria-label="Закрыть форму добавления"
            class="ui-btn-ghost w-9 h-9 rounded-lg flex items-center justify-center cursor-pointer"
          >
            <X size={15} strokeWidth={1.75} aria-hidden="true" />
          </button>
        </div>
      </form>
    {/if}

    <!-- Filter Pills + Search -->
    <div class="flex flex-col lg:flex-row lg:items-center gap-3 pt-1">
      <div
        class="inline-flex flex-wrap gap-1 p-1 rounded-xl bg-[var(--bg-elevated)] border border-[var(--border-subtle)]"
        role="group"
        aria-label="Фильтр процессов по режиму"
      >
        {#each [
          { id: 'all', label: 'Все', count: totalCount },
          { id: 'disable', label: 'Выкл. в Gaming Mode', count: disabledCount },
          { id: 'normal', label: 'Без утилки', count: normalCount }
        ] as item (item.id)}
          {@const active = filterMode === item.id}
          <button
            type="button"
            onclick={() => onFilterModeChange(item.id as ProcessFilterMode)}
            aria-pressed={active}
            class="{active
              ? 'ui-btn-primary'
              : 'ui-btn-ghost'} ui-pressable rounded-lg px-3 py-1.5 min-h-8 text-[0.8125rem] font-medium inline-flex items-center gap-1.5 cursor-pointer"
          >
            <span>{item.label}</span>
            <span class="tabular-nums opacity-85 text-xs">({item.count})</span>
          </button>
        {/each}
      </div>

      <div class="relative flex-1 min-w-0">
        <label for="processes-search" class="sr-only">
          Поиск процессов по названию, .exe или описанию
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
          placeholder="Найти процесс, .exe или описание…"
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

    <!-- Legend + OS Core Toggle + Counters -->
    <div class="flex flex-wrap items-center justify-between gap-2 text-xs text-[var(--text-muted)]">
      <div class="flex flex-wrap items-center gap-3">
        <span class="inline-flex items-center gap-1.5">
          <span class="w-2 h-2 rounded-full bg-[var(--status-active-text)]" aria-hidden="true"></span>
          <span>Можно выключить</span>
        </span>
        <span class="inline-flex items-center gap-1.5">
          <span class="w-2 h-2 rounded-full bg-[var(--status-warn-text)]" aria-hidden="true"></span>
          <span>По желанию</span>
        </span>
        <span class="inline-flex items-center gap-1.5">
          <span class="w-2 h-2 rounded-full bg-[var(--status-danger-text)]" aria-hidden="true"></span>
          <span>Нельзя выключать</span>
        </span>
      </div>

      <div class="flex flex-wrap items-center gap-3">
        <label class="inline-flex items-center gap-1.5 font-medium text-[var(--text-secondary)] cursor-pointer select-none">
          <input
            type="checkbox"
            bind:checked={showOsCore}
            class="w-3.5 h-3.5 rounded accent-[var(--accent-solid)] cursor-pointer"
          />
          <span>Ядро Windows ({osCoreCount})</span>
        </label>

        <p class="tabular-nums" aria-live="polite">
          Показано {visibleProcesses.length} из {filteredProcesses.length} · запущено: {runningCount}
        </p>
      </div>
    </div>
  </section>

  <!-- Unified Processes List -->
  {#if isLoading && unifiedProcesses.length === 0}
    <div
      class="ui-card rounded-2xl p-8 flex items-center justify-center gap-3 text-sm text-[var(--text-secondary)]"
      role="status"
    >
      <Loader2 size={18} strokeWidth={2} class="ui-spin text-[var(--accent-text)]" aria-hidden="true" />
      <span>Сканирую процессы Windows…</span>
    </div>
  {:else if loadError && unifiedProcesses.length === 0}
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
  {:else if filteredProcesses.length === 0}
    <div class="ui-card rounded-2xl p-8 text-center space-y-3">
      <p class="text-sm font-semibold text-[var(--text-primary)]">
        Процессы не найдены
      </p>
      <p class="text-sm text-[var(--text-secondary)]">
        Попробуйте изменить поисковый запрос или сбросить фильтр.
      </p>
      <div class="flex flex-wrap justify-center gap-2">
        {#if !showOsCore && osCoreCount > 0}
          <button
            type="button"
            onclick={() => (showOsCore = true)}
            class="ui-btn-secondary ui-pressable rounded-lg px-4 py-2 min-h-9 text-[0.8125rem] font-medium cursor-pointer"
          >
            Показать ядро Windows ({osCoreCount})
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
      {#each visibleProcesses as item (item.key)}
        {@const rowBusy = busyKey === `proc:${item.name.toLowerCase()}`}
        {@const isTipActive = activeTooltipKey === item.key}
        <li
          class="ui-row-hover px-4 py-3 flex flex-col sm:flex-row sm:items-center justify-between gap-3"
          onpointerenter={(e) => {
            const infoAnchor =
              (e.currentTarget.querySelector('[data-tip-anchor]') as HTMLElement | null) ??
              e.currentTarget;
            scheduleOpenTooltip(item, infoAnchor);
          }}
          onpointerleave={scheduleCloseTooltip}
        >
          <div data-tip-anchor class="min-w-0 flex-1 space-y-0.5">
            <div class="flex flex-wrap items-center gap-2">
              <span
                class="w-2 h-2 rounded-full shrink-0 {safetyDotClass(item.safetyLevel)}"
                aria-hidden="true"
              ></span>

              <span class="text-sm font-semibold text-[var(--text-primary)] break-words">
                {item.displayName}
              </span>

              <code
                translate="no"
                class="font-mono text-xs px-1.5 py-0.5 rounded-md bg-[var(--bg-elevated)] text-[var(--text-secondary)] select-text"
              >
                {item.name}.exe
              </code>

              {#if item.isRunning}
                <span
                  class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[0.68rem] font-medium border tabular-nums bg-[var(--status-active-soft)] text-[var(--status-active-text)] border-[var(--status-active-border)]"
                >
                  <span>Работает · {formatMem(item.totalMemoryMb)}</span>
                  {#if item.instanceCount > 1}
                    <span class="opacity-80">×{item.instanceCount}</span>
                  {/if}
                </span>
              {:else}
                <span
                  class="inline-flex items-center rounded-full px-2 py-0.5 text-[0.68rem] font-medium border bg-[var(--bg-elevated)] text-[var(--text-muted)] border-[var(--border-subtle)]"
                >
                  Не запущен
                </span>
              {/if}

              {#if item.inStartup}
                <span
                  class="inline-flex items-center rounded-full px-2 py-0.5 text-[0.68rem] font-medium border bg-[var(--accent-soft)] text-[var(--accent-text)] border-[var(--accent-border)]"
                >
                  Автозагрузка
                </span>
              {/if}

              <button
                type="button"
                aria-label={`Описание процесса ${item.displayName}`}
                aria-expanded={isTipActive}
                aria-describedby={isTipActive ? 'processes-item-tooltip' : undefined}
                onpointerdown={() => {
                  suppressFocusOpen = true;
                  requestAnimationFrame(() => {
                    suppressFocusOpen = false;
                  });
                }}
                onfocus={(e) => {
                  if (suppressFocusOpen) {
                    suppressFocusOpen = false;
                    return;
                  }
                  scheduleOpenTooltip(item, e.currentTarget, true);
                }}
                onblur={() => {
                  suppressFocusOpen = false;
                  if (pinnedTooltipKey !== item.key) {
                    scheduleCloseTooltip();
                  }
                }}
                onclick={(e) => {
                  e.stopPropagation();
                  togglePinnedTooltip(item, e.currentTarget);
                }}
                class="inline-flex items-center justify-center w-6 h-6 rounded-md text-[var(--text-muted)] hover:text-[var(--accent-text)] hover:bg-[var(--bg-hover)] focus-visible:text-[var(--accent-text)] cursor-pointer transition-colors"
              >
                <Info size={13} strokeWidth={1.9} aria-hidden="true" />
              </button>
            </div>

            {#if item.summaryRu}
              <p class="text-xs text-[var(--text-muted)] truncate pl-4">
                {item.summaryRu}
              </p>
            {/if}
          </div>

          <!-- 2-choice Mode Control or Protection Lock -->
          <div class="flex items-center shrink-0 self-start sm:self-center">
            {#if item.isProtected}
              <span
                class="inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-medium bg-[var(--bg-elevated)] text-[var(--text-secondary)] border border-[var(--border-subtle)]"
              >
                <Lock size={12} strokeWidth={2} aria-hidden="true" />
                <span>{protectionLabel(item.protectionKind)}</span>
              </span>
            {:else}
              <div
                class="inline-flex items-center gap-1 p-0.5 rounded-xl bg-[var(--bg-elevated)] border border-[var(--border-subtle)]"
                role="group"
                aria-label={`Режим работы процесса ${item.name}`}
              >
                <button
                  type="button"
                  disabled={rowBusy || busyKey !== null}
                  aria-pressed={!item.disableInGaming}
                  onclick={() => {
                    if (item.disableInGaming) {
                      dismissTooltip();
                      void onSetProcessMode(item.name, false, item.safetyLevel);
                    }
                  }}
                  class="rounded-lg px-2.5 py-1.5 min-h-8 text-xs font-medium border transition-colors inline-flex items-center gap-1.5 disabled:opacity-55 cursor-pointer {!item.disableInGaming
                    ? 'bg-[var(--bg-surface)] text-[var(--text-primary)] border-[var(--border-strong)] font-semibold shadow-xs'
                    : 'bg-transparent text-[var(--text-muted)] border-transparent hover:text-[var(--text-primary)]'}"
                >
                  {#if rowBusy && item.disableInGaming}
                    <Loader2 size={12} strokeWidth={2} class="ui-spin" aria-hidden="true" />
                  {/if}
                  <span>Без утилки</span>
                </button>

                <button
                  type="button"
                  disabled={rowBusy || busyKey !== null}
                  aria-pressed={item.disableInGaming}
                  onclick={() => {
                    if (!item.disableInGaming) {
                      dismissTooltip();
                      void onSetProcessMode(item.name, true, item.safetyLevel);
                    }
                  }}
                  class="rounded-lg px-2.5 py-1.5 min-h-8 text-xs font-medium border transition-colors inline-flex items-center gap-1.5 disabled:opacity-55 cursor-pointer {item.disableInGaming
                    ? 'bg-[var(--status-warn-soft)] text-[var(--status-warn-text)] border-[var(--status-warn-border)] font-semibold'
                    : 'bg-transparent text-[var(--text-muted)] border-transparent hover:text-[var(--text-primary)]'}"
                >
                  {#if rowBusy && !item.disableInGaming}
                    <Loader2 size={12} strokeWidth={2} class="ui-spin" aria-hidden="true" />
                  {/if}
                  <span>Выкл. в Gaming Mode</span>
                </button>
              </div>
            {/if}
          </div>
        </li>
      {/each}
    </ul>

    {#if filteredProcesses.length > visibleProcesses.length}
      <div class="flex justify-center pt-1">
        <button
          type="button"
          onclick={() => (visibleLimit += 60)}
          class="ui-btn-secondary ui-pressable rounded-xl px-4 py-2 min-h-9 text-[0.8125rem] font-medium cursor-pointer"
        >
          Показать ещё ({Math.min(60, filteredProcesses.length - visibleProcesses.length)} из {filteredProcesses.length - visibleProcesses.length} оставшихся)
        </button>
      </div>
    {/if}
  {/if}
</div>

<ItemTooltip
  tooltipId="processes-item-tooltip"
  payload={activeTooltip}
  anchorEl={activeAnchorEl}
  onTooltipEnter={cancelCloseTooltip}
  onTooltipLeave={scheduleCloseTooltip}
  onDismiss={dismissTooltip}
/>
