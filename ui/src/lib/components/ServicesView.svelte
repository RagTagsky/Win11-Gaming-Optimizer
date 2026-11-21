<script lang="ts">
  import { onDestroy } from 'svelte';
  import {
    AlertCircle,
    Bluetooth,
    Camera,
    FilterX,
    Gamepad2,
    Globe,
    Info,
    Loader2,
    Lock,
    Printer,
    RefreshCw,
    Search,
    Shield,
    Wifi,
    X
  } from '@lucide/svelte';
  import ItemTooltip, { type TooltipPayload } from './ItemTooltip.svelte';
  import type {
    InstalledServiceItem,
    SafetyLevel,
    ServiceFeaturePack
  } from '../types';

  export type ServiceFilterMode = 'all' | 'disable' | 'normal';

  interface Props {
    active?: boolean;
    allInstalledServices: InstalledServiceItem[];
    wifiActive?: boolean;
    featurePacks?: ServiceFeaturePack[];
    busyFeaturePack?: string | null;
    filterMode: ServiceFilterMode;
    searchQuery: string;
    isLoading: boolean;
    busyService: string | null;
    loadError: string | null;
    onFilterModeChange: (mode: ServiceFilterMode) => void;
    onSearchChange: (value: string) => void;
    onRetry: () => void;
    onApplyFeaturePack?: (packId: string, keepEnabledInGame: boolean) => Promise<void> | void;
    onSetServiceMode: (
      serviceName: string,
      disableInGaming: boolean,
      safetyLevel?: SafetyLevel
    ) => Promise<void> | void;
  }

  let {
    active = true,
    allInstalledServices = [],
    wifiActive = false,
    featurePacks = [],
    busyFeaturePack = null,
    filterMode,
    searchQuery,
    isLoading,
    busyService,
    loadError,
    onFilterModeChange,
    onSearchChange,
    onRetry,
    onApplyFeaturePack,
    onSetServiceMode
  }: Props = $props();

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

  function effectiveSafety(svc: InstalledServiceItem): SafetyLevel {
    if (svc.isCoreLocked) return 'protected';
    if (svc.safetyLevel === 'safe' || svc.safetyLevel === 'optional' || svc.safetyLevel === 'protected') {
      return svc.safetyLevel;
    }
    return 'optional';
  }

  function isDisabledInGaming(svc: InstalledServiceItem): boolean {
    if (svc.isCoreLocked) return false;
    if (typeof svc.disableInGaming === 'boolean') return svc.disableInGaming;
    return svc.membership === 'blacklist';
  }

  function statusLabel(status?: string): string {
    if (status === 'Running') return 'Работает';
    if (status === 'Stopped') return 'Остановлена';
    if (status === 'StartPending') return 'Запуск…';
    if (status === 'StopPending') return 'Остановка…';
    if (status === 'Paused') return 'Пауза';
    return '';
  }

  function startTypeLabel(startType?: string): string {
    if (startType === 'Automatic') return 'Авто';
    if (startType === 'Manual') return 'Вручную';
    if (startType === 'Disabled') return 'Откл.';
    return '';
  }

  function safetyDotClass(level: SafetyLevel): string {
    if (level === 'safe') return 'bg-[var(--status-active-text)]';
    if (level === 'protected') return 'bg-[var(--status-danger-text)]';
    return 'bg-[var(--status-warn-text)]';
  }

  function buildServiceTooltip(svc: InstalledServiceItem): TooltipPayload {
    const level = effectiveSafety(svc);
    const disabled = isDisabledInGaming(svc);
    const st = statusLabel(svc.Status);
    const startType = startTypeLabel(svc.StartType);
    const statusPart = [st, startType].filter(Boolean).join(' · ');
    const modePart = svc.isCoreLocked
      ? 'Защищено ОС (не отключается)'
      : disabled
        ? 'Выкл. в Gaming Mode'
        : 'Без утилки';

    return {
      id: svc.Name,
      title: svc.DisplayName?.trim() || svc.Name,
      subtitle: svc.Name,
      safetyLevel: level,
      summary:
        svc.SummaryRu?.trim() || `Служба Windows или стороннего ПО («${svc.DisplayName || svc.Name}»).`,
      impact:
        svc.CanDisableHint?.trim() ||
        (svc.isCoreLocked
          ? 'Критическая служба ядра Windows — отключать нельзя.'
          : 'Отключайте в Gaming Mode, только если уверены, что служба не нужна во время игры.'),
      metaNote: statusPart ? `${statusPart} · Режим: ${modePart}` : `Режим: ${modePart}`
    };
  }

  function scheduleOpenTooltip(svc: InstalledServiceItem, anchor: HTMLElement, immediate = false) {
    if (pinnedTooltipKey !== null && !immediate) {
      return;
    }
    if (closeTimer) {
      clearTimeout(closeTimer);
      closeTimer = undefined;
    }
    const show = () => {
      activeAnchorEl = anchor;
      activeTooltipKey = svc.Name;
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

  function togglePinnedTooltip(svc: InstalledServiceItem, anchor: HTMLElement) {
    suppressFocusOpen = false;
    clearTooltipTimers();
    if (pinnedTooltipKey === svc.Name) {
      dismissTooltip();
    } else {
      pinnedTooltipKey = svc.Name;
      activeTooltipKey = svc.Name;
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

  const wifiPack = $derived(featurePacks.find((p) => p.id === 'wifi'));
  const wlanService = $derived(
    allInstalledServices.find((s) => s.Name.toLowerCase() === 'wlansvc')
  );
  const showWifiWarningBanner = $derived(
    Boolean(
      wifiActive &&
        (wlanService ? isDisabledInGaming(wlanService) : wifiPack && !wifiPack.keepEnabledInGame)
    )
  );

  const totalCount = $derived(allInstalledServices.length);
  const disabledCount = $derived(
    allInstalledServices.filter((s) => isDisabledInGaming(s)).length
  );
  const normalCount = $derived(totalCount - disabledCount);
  const runningCount = $derived(
    allInstalledServices.filter((s) => s.Status === 'Running').length
  );

  const filteredServices = $derived.by(() => {
    return allInstalledServices.filter((svc) => {
      const disabled = isDisabledInGaming(svc);
      if (filterMode === 'disable' && !disabled) return false;
      if (filterMode === 'normal' && disabled) return false;
      if (!normalizedQuery) return true;
      return (
        svc.Name.toLowerCase().includes(normalizedQuery) ||
        svc.DisplayName.toLowerCase().includes(normalizedQuery) ||
        (svc.SummaryRu ?? '').toLowerCase().includes(normalizedQuery) ||
        (svc.CanDisableHint ?? '').toLowerCase().includes(normalizedQuery)
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
    visibleLimit = 60;
    dismissTooltip();
  });

  const visibleServices = $derived(filteredServices.slice(0, visibleLimit));
  const activeTooltip = $derived.by((): TooltipPayload | null => {
    if (!activeTooltipKey) return null;
    const svc = visibleServices.find((s) => s.Name === activeTooltipKey);
    return svc ? buildServiceTooltip(svc) : null;
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

  function packShortTitle(pack: ServiceFeaturePack): string {
    switch (pack.id) {
      case 'wifi':
        return 'Wi-Fi';
      case 'bluetooth':
        return 'Bluetooth';
      case 'faceit':
        return 'FACEIT AC';
      case 'camera':
        return 'Камера';
      case 'xbox':
        return 'Xbox / Store';
      case 'vpn':
        return 'VPN / PPPoE';
      case 'printer':
        return 'Принтер';
      default:
        return pack.title;
    }
  }
</script>

<div class="space-y-4">
  <!-- Header Card -->
  <section class="ui-card rounded-2xl p-5 space-y-4">
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
      <div class="space-y-1">
        <h1 class="text-base font-semibold text-[var(--text-primary)]">
          Службы Windows
        </h1>
        <p class="text-sm text-[var(--text-secondary)]">
          Выберите для каждой службы: работает <strong class="font-medium text-[var(--text-primary)]">без утилки</strong> или временно <strong class="font-medium text-[var(--text-primary)]">выключается в Gaming Mode</strong>. Наведите на любую строку, чтобы узнать описание.
        </p>
      </div>

      <button
        type="button"
        onclick={onRetry}
        disabled={isLoading}
        class="ui-btn-secondary ui-pressable rounded-lg px-3.5 py-2 min-h-9 text-[0.8125rem] font-medium flex items-center gap-1.5 shrink-0 self-start sm:self-center disabled:opacity-55 disabled:cursor-not-allowed cursor-pointer"
      >
        <RefreshCw size={14} strokeWidth={1.75} class={isLoading ? 'ui-spin' : ''} aria-hidden="true" />
        <span>Обновить</span>
      </button>
    </div>

    {#if showWifiWarningBanner}
      <div
        role="status"
        class="rounded-xl p-3.5 bg-[var(--status-warn-soft)] border border-[var(--status-warn-border)] flex flex-col sm:flex-row sm:items-center justify-between gap-3"
      >
        <div class="flex items-start gap-2.5 min-w-0">
          <Wifi size={18} strokeWidth={1.85} class="text-[var(--status-warn-text)] shrink-0 mt-0.5" aria-hidden="true" />
          <div class="space-y-0.5 text-[0.8125rem] min-w-0">
            <p class="font-semibold text-[var(--status-warn-text)]">
              Сейчас ПК подключён по Wi-Fi
            </p>
            <p class="text-[var(--text-secondary)]">
              Служба Wi-Fi сейчас отмечена как «Выкл. в Gaming Mode» — если играете по Wi-Fi, переведите её в режим «Без утилки».
            </p>
          </div>
        </div>

        <button
          type="button"
          disabled={busyFeaturePack !== null}
          onclick={() => {
            dismissTooltip();
            void onApplyFeaturePack?.('wifi', true);
          }}
          class="ui-btn-warn ui-pressable rounded-lg px-3.5 py-2 min-h-9 text-xs font-semibold shrink-0 disabled:opacity-55 cursor-pointer"
        >
          Оставить Wi-Fi включённым
        </button>
      </div>
    {/if}

    <!-- Compact Quick Presets Bar -->
    {#if featurePacks.length > 0}
      <div class="flex flex-wrap items-center gap-1.5 pt-0.5" role="group" aria-label="Быстрые пресеты служб">
        <span class="text-xs font-medium text-[var(--text-muted)] mr-1">
          Быстрые пресеты:
        </span>
        {#each featurePacks as pack (pack.id)}
          {@const isPackBusy = busyFeaturePack === pack.id}
          <button
            type="button"
            disabled={busyFeaturePack !== null || busyService !== null}
            aria-pressed={pack.keepEnabledInGame}
            title={`${pack.title}: ${pack.description}. Нажмите, чтобы переключить всю группу (${pack.keepEnabledInGame ? 'сейчас: Без утилки' : 'сейчас: Выкл. в Gaming Mode'}).`}
            onclick={() => {
              dismissTooltip();
              void onApplyFeaturePack?.(pack.id, !pack.keepEnabledInGame);
            }}
            class="ui-pressable inline-flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 min-h-8 text-xs font-medium border disabled:opacity-55 cursor-pointer {pack.keepEnabledInGame
              ? 'bg-[var(--status-active-soft)] text-[var(--status-active-text)] border-[var(--status-active-border)]'
              : 'bg-[var(--bg-elevated)] text-[var(--text-secondary)] border-[var(--border-subtle)] hover:bg-[var(--bg-hover)]'}"
          >
            {#if isPackBusy}
              <Loader2 size={12} strokeWidth={2} class="ui-spin" aria-hidden="true" />
            {:else if pack.id === 'wifi'}
              <Wifi size={12} strokeWidth={1.85} aria-hidden="true" />
            {:else if pack.id === 'bluetooth'}
              <Bluetooth size={12} strokeWidth={1.85} aria-hidden="true" />
            {:else if pack.id === 'faceit'}
              <Shield size={12} strokeWidth={1.85} aria-hidden="true" />
            {:else if pack.id === 'camera'}
              <Camera size={12} strokeWidth={1.85} aria-hidden="true" />
            {:else if pack.id === 'xbox'}
              <Gamepad2 size={12} strokeWidth={1.85} aria-hidden="true" />
            {:else if pack.id === 'vpn'}
              <Globe size={12} strokeWidth={1.85} aria-hidden="true" />
            {:else}
              <Printer size={12} strokeWidth={1.85} aria-hidden="true" />
            {/if}
            <span>{packShortTitle(pack)}</span>
            <span class="opacity-75 text-[0.68rem]">
              · {pack.keepEnabledInGame ? 'Без утилки' : 'Выкл. в игре'}
            </span>
          </button>
        {/each}
      </div>
    {/if}

    <!-- Filter Pills + Search -->
    <div class="flex flex-col lg:flex-row lg:items-center gap-3 pt-1">
      <div
        class="inline-flex flex-wrap gap-1 p-1 rounded-xl bg-[var(--bg-elevated)] border border-[var(--border-subtle)]"
        role="group"
        aria-label="Фильтр служб по режиму"
      >
        {#each [
          { id: 'all', label: 'Все', count: totalCount },
          { id: 'disable', label: 'Выкл. в Gaming Mode', count: disabledCount },
          { id: 'normal', label: 'Без утилки', count: normalCount }
        ] as item (item.id)}
          {@const active = filterMode === item.id}
          <button
            type="button"
            onclick={() => onFilterModeChange(item.id as ServiceFilterMode)}
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
        <label for="services-search" class="sr-only">
          Поиск служб по названию, системному имени или описанию
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
          placeholder="Найти службу по названию, имени или описанию…"
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

    <!-- Legend + Counters -->
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

      <p class="tabular-nums" aria-live="polite">
        Показано {visibleServices.length} из {filteredServices.length} · работает в фоне: {runningCount}
      </p>
    </div>
  </section>

  <!-- Unified Installed Services List -->
  {#if isLoading && allInstalledServices.length === 0}
    <div
      class="ui-card rounded-2xl p-8 flex items-center justify-center gap-3 text-sm text-[var(--text-secondary)]"
      role="status"
    >
      <Loader2 size={18} strokeWidth={2} class="ui-spin text-[var(--accent-text)]" aria-hidden="true" />
      <span>Загружаю установленные службы Windows…</span>
    </div>
  {:else if loadError && allInstalledServices.length === 0}
    <div
      class="ui-card rounded-2xl p-6 border border-[var(--status-danger-border)] bg-[var(--status-danger-soft)] flex flex-col sm:flex-row sm:items-center justify-between gap-4"
      role="alert"
    >
      <div class="flex items-start gap-3 min-w-0">
        <AlertCircle size={20} strokeWidth={1.75} class="text-[var(--status-danger-text)] shrink-0 mt-0.5" aria-hidden="true" />
        <div class="space-y-1 min-w-0">
          <p class="text-sm font-semibold text-[var(--status-danger-text)]">
            Не удалось загрузить службы
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
  {:else if filteredServices.length === 0}
    <div class="ui-card rounded-2xl p-8 text-center space-y-3">
      <p class="text-sm font-semibold text-[var(--text-primary)]">
        Службы не найдены
      </p>
      <p class="text-sm text-[var(--text-secondary)]">
        Попробуйте изменить поисковый запрос или переключить фильтр.
      </p>
      {#if hasActiveFilters}
        <div class="flex justify-center">
          <button
            type="button"
            onclick={resetFilters}
            class="ui-btn-secondary ui-pressable rounded-lg px-4 py-2 min-h-9 text-[0.8125rem] font-medium inline-flex items-center gap-1.5 cursor-pointer"
          >
            <FilterX size={15} strokeWidth={1.75} aria-hidden="true" />
            <span>Сбросить фильтры</span>
          </button>
        </div>
      {/if}
    </div>
  {:else}
    <ul class="ui-card rounded-2xl divide-y divide-[var(--border-subtle)] overflow-hidden">
      {#each visibleServices as svc (svc.Name)}
        {@const safety = effectiveSafety(svc)}
        {@const disabledInGaming = isDisabledInGaming(svc)}
        {@const sLabel = statusLabel(svc.Status)}
        {@const rowBusy = busyService === svc.Name}
        {@const isTipActive = activeTooltipKey === svc.Name}
        {@const showDisplay =
          svc.DisplayName.trim().length > 0 &&
          svc.DisplayName.trim().toLowerCase() !== svc.Name.trim().toLowerCase()}
        <li
          class="ui-row-hover px-4 py-3 flex flex-col sm:flex-row sm:items-center justify-between gap-3"
          onpointerenter={(e) => {
            const infoAnchor =
              (e.currentTarget.querySelector('[data-tip-anchor]') as HTMLElement | null) ??
              e.currentTarget;
            scheduleOpenTooltip(svc, infoAnchor);
          }}
          onpointerleave={scheduleCloseTooltip}
        >
          <div data-tip-anchor class="min-w-0 flex-1 space-y-0.5">
            <div class="flex flex-wrap items-center gap-2">
              <span
                class="w-2 h-2 rounded-full shrink-0 {safetyDotClass(safety)}"
                aria-hidden="true"
              ></span>

              <span class="text-sm font-semibold text-[var(--text-primary)] break-words">
                {showDisplay ? svc.DisplayName : svc.Name}
              </span>

              <code
                translate="no"
                class="font-mono text-xs px-1.5 py-0.5 rounded-md bg-[var(--bg-elevated)] text-[var(--text-secondary)] select-text"
              >
                {svc.Name}
              </code>

              {#if sLabel}
                <span
                  class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[0.68rem] font-medium border {svc.Status === 'Running'
                    ? 'bg-[var(--status-active-soft)] text-[var(--status-active-text)] border-[var(--status-active-border)]'
                    : 'bg-[var(--bg-elevated)] text-[var(--text-muted)] border-[var(--border-subtle)]'}"
                >
                  {sLabel}
                </span>
              {/if}

              <button
                type="button"
                aria-label={`Описание службы ${svc.DisplayName || svc.Name}`}
                aria-expanded={isTipActive}
                aria-describedby={isTipActive ? 'services-item-tooltip' : undefined}
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
                  scheduleOpenTooltip(svc, e.currentTarget, true);
                }}
                onblur={() => {
                  suppressFocusOpen = false;
                  if (pinnedTooltipKey !== svc.Name) {
                    scheduleCloseTooltip();
                  }
                }}
                onclick={(e) => {
                  e.stopPropagation();
                  togglePinnedTooltip(svc, e.currentTarget);
                }}
                class="inline-flex items-center justify-center w-6 h-6 rounded-md text-[var(--text-muted)] hover:text-[var(--accent-text)] hover:bg-[var(--bg-hover)] focus-visible:text-[var(--accent-text)] cursor-pointer transition-colors"
              >
                <Info size={13} strokeWidth={1.9} aria-hidden="true" />
              </button>
            </div>

            {#if svc.SummaryRu?.trim()}
              <p class="text-xs text-[var(--text-muted)] truncate pl-4">
                {svc.SummaryRu}
              </p>
            {/if}
          </div>

          <!-- 2-choice Mode Control or OS Core Lock -->
          <div class="flex items-center shrink-0 self-start sm:self-center">
            {#if svc.isCoreLocked}
              <span
                class="inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-medium bg-[var(--bg-elevated)] text-[var(--text-secondary)] border border-[var(--border-subtle)]"
              >
                <Lock size={12} strokeWidth={2} aria-hidden="true" />
                <span>Защищено ОС</span>
              </span>
            {:else}
              <div
                class="inline-flex items-center gap-1 p-0.5 rounded-xl bg-[var(--bg-elevated)] border border-[var(--border-subtle)]"
                role="group"
                aria-label={`Режим работы службы ${svc.Name}`}
              >
                <button
                  type="button"
                  disabled={rowBusy || busyService !== null || busyFeaturePack !== null}
                  aria-pressed={!disabledInGaming}
                  onclick={() => {
                    if (disabledInGaming) {
                      dismissTooltip();
                      void onSetServiceMode(svc.Name, false, safety);
                    }
                  }}
                  class="rounded-lg px-2.5 py-1.5 min-h-8 text-xs font-medium border transition-colors inline-flex items-center gap-1.5 disabled:opacity-55 cursor-pointer {!disabledInGaming
                    ? 'bg-[var(--bg-surface)] text-[var(--text-primary)] border-[var(--border-strong)] font-semibold shadow-xs'
                    : 'bg-transparent text-[var(--text-muted)] border-transparent hover:text-[var(--text-primary)]'}"
                >
                  {#if rowBusy && disabledInGaming}
                    <Loader2 size={12} strokeWidth={2} class="ui-spin" aria-hidden="true" />
                  {/if}
                  <span>Без утилки</span>
                </button>

                <button
                  type="button"
                  disabled={rowBusy || busyService !== null || busyFeaturePack !== null}
                  aria-pressed={disabledInGaming}
                  onclick={() => {
                    if (!disabledInGaming) {
                      dismissTooltip();
                      void onSetServiceMode(svc.Name, true, safety);
                    }
                  }}
                  class="rounded-lg px-2.5 py-1.5 min-h-8 text-xs font-medium border transition-colors inline-flex items-center gap-1.5 disabled:opacity-55 cursor-pointer {disabledInGaming
                    ? 'bg-[var(--status-warn-soft)] text-[var(--status-warn-text)] border-[var(--status-warn-border)] font-semibold'
                    : 'bg-transparent text-[var(--text-muted)] border-transparent hover:text-[var(--text-primary)]'}"
                >
                  {#if rowBusy && !disabledInGaming}
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

    {#if filteredServices.length > visibleServices.length}
      <div class="flex justify-center pt-1">
        <button
          type="button"
          onclick={() => (visibleLimit += 60)}
          class="ui-btn-secondary ui-pressable rounded-xl px-4 py-2 min-h-9 text-[0.8125rem] font-medium cursor-pointer"
        >
          Показать ещё ({Math.min(60, filteredServices.length - visibleServices.length)} из {filteredServices.length - visibleServices.length} оставшихся)
        </button>
      </div>
    {/if}
  {/if}
</div>

<ItemTooltip
  tooltipId="services-item-tooltip"
  payload={activeTooltip}
  anchorEl={activeAnchorEl}
  onTooltipEnter={cancelCloseTooltip}
  onTooltipLeave={scheduleCloseTooltip}
  onDismiss={dismissTooltip}
/>
