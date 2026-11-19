<script lang="ts">
  import {
    AlertCircle,
    AlertTriangle,
    Bluetooth,
    Camera,
    Check,
    FilterX,
    Gamepad2,
    Globe,
    ListFilter,
    Loader2,
    Lock,
    MoreHorizontal,
    Plus,
    Printer,
    RefreshCw,
    Search,
    Server,
    Shield,
    ShieldAlert,
    ShieldCheck,
    Wifi,
    X
  } from '@lucide/svelte';
  import type {
    BlacklistServiceItem,
    InstalledServiceItem,
    ListMutationOperation,
    ServiceCategory,
    ServiceControlOperation,
    ServiceDescriptionEntry,
    ServiceFeaturePack,
    ServiceListType,
    WhitelistServiceItem
  } from '../types';

  export type ServiceViewMode = 'disable' | 'keep' | 'all';
  export type ServiceCategoryFilter = 'all' | ServiceCategory;

  interface Props {
    blacklist: BlacklistServiceItem[];
    whitelist: string[];
    whitelistDescriptions?: Record<string, ServiceDescriptionEntry>;
    whitelistItems?: WhitelistServiceItem[];
    allInstalledServices?: InstalledServiceItem[];
    wifiActive?: boolean;
    featurePacks?: ServiceFeaturePack[];
    busyFeaturePack?: string | null;
    viewMode: ServiceViewMode;
    searchQuery: string;
    selectedCategory: ServiceCategoryFilter;
    isLoading: boolean;
    busyService: string | null;
    loadError: string | null;
    onViewModeChange: (mode: ServiceViewMode) => void;
    onSearchChange: (value: string) => void;
    onCategoryChange: (category: ServiceCategoryFilter) => void;
    onRetry: () => void;
    onApplyFeaturePack?: (packId: string, keepEnabledInGame: boolean) => Promise<void> | void;
    onMoveToDisableList?: (serviceName: string) => Promise<void> | void;
    onControlService: (serviceName: string, operation: ServiceControlOperation) => Promise<void> | void;
    onUpdateServiceList: (params: {
      listType: ServiceListType;
      serviceName: string;
      displayName?: string;
      category?: ServiceCategory;
      reason?: string;
      operation: ListMutationOperation;
    }) => Promise<void> | void;
  }

  let {
    blacklist,
    whitelist,
    whitelistDescriptions = {},
    whitelistItems = [],
    allInstalledServices = [],
    wifiActive = false,
    featurePacks = [],
    busyFeaturePack = null,
    viewMode,
    searchQuery,
    selectedCategory,
    isLoading,
    busyService,
    loadError,
    onViewModeChange,
    onSearchChange,
    onCategoryChange,
    onRetry,
    onApplyFeaturePack,
    onMoveToDisableList,
    onControlService,
    onUpdateServiceList
  }: Props = $props();

  let newServiceName = $state('');
  let newServiceReason = $state('');
  let newServiceCategory = $state<ServiceCategory>('System');
  let showNotInstalled = $state(false);
  let openMenuService = $state<string | null>(null);
  let visibleDisableLimit = $state(60);
  let visibleKeepLimit = $state(60);
  let visibleAllLimit = $state(60);

  const CATEGORY_LABELS: Record<ServiceCategoryFilter, string> = {
    all: 'Все',
    Telemetry: 'Телеметрия',
    Updates: 'Обновления',
    Xbox: 'Xbox и игры',
    Print: 'Печать',
    Devices: 'Устройства',
    Network: 'Сеть и VPN',
    Remote: 'Удалённый доступ',
    System: 'Система'
  };

  const CATEGORIES: ServiceCategoryFilter[] = [
    'all',
    'Telemetry',
    'Updates',
    'Xbox',
    'Print',
    'Devices',
    'Network',
    'Remote',
    'System'
  ];

  const ADD_CATEGORIES: ServiceCategory[] = [
    'System',
    'Telemetry',
    'Updates',
    'Xbox',
    'Print',
    'Devices',
    'Network',
    'Remote'
  ];

  function statusLabel(status?: string): string {
    if (status === 'Running') return 'Работает';
    if (status === 'Stopped') return 'Остановлена';
    if (status === 'StartPending') return 'Запуск…';
    if (status === 'StopPending') return 'Остановка…';
    if (status === 'Paused') return 'Пауза';
    if (status === 'NotInstalled') return 'Не установлена';
    return '';
  }

  function startTypeLabel(startType?: string): string {
    if (startType === 'Automatic') return 'Авто';
    if (startType === 'Manual') return 'Вручную';
    if (startType === 'Disabled') return 'Откл.';
    return '';
  }

  function isConditionalCautionHint(hint?: string): boolean {
    if (!hint) return false;
    const h = hint.toLowerCase();
    return (
      h.includes('только если') ||
      h.includes('отключайте, только') ||
      h.includes('наруш') ||
      h.includes('перестан') ||
      h.includes('не запуск') ||
      h.includes('если пользу') ||
      h.includes('если играете') ||
      h.includes('если не используете') ||
      h.includes('перенесите')
    );
  }

  let debouncedQuery = $state('');
  let searchDebounceHandle: ReturnType<typeof setTimeout> | undefined;

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

  const wifiPack = $derived(featurePacks.find((p) => p.id === 'wifi'));
  const showWifiWarningBanner = $derived(
    Boolean(wifiActive && wifiPack && !wifiPack.keepEnabledInGame)
  );

  const notInstalledBlacklistCount = $derived(
    blacklist.filter((item) => item.Status === 'NotInstalled').length
  );

  const sortedAndFilteredDisable = $derived.by(() => {
    const filtered = blacklist.filter((item) => {
      if (!showNotInstalled && item.Status === 'NotInstalled') return false;
      if (selectedCategory !== 'all' && item.Category !== selectedCategory) return false;
      if (!normalizedQuery) return true;
      const catLabel = (CATEGORY_LABELS[item.Category] ?? item.Category).toLowerCase();
      return (
        item.Name.toLowerCase().includes(normalizedQuery) ||
        item.DisplayName.toLowerCase().includes(normalizedQuery) ||
        item.Reason.toLowerCase().includes(normalizedQuery) ||
        (item.SummaryRu ?? '').toLowerCase().includes(normalizedQuery) ||
        catLabel.includes(normalizedQuery)
      );
    });

    const rank = (st?: string) => {
      if (st === 'Running') return 0;
      if (st === 'NotInstalled') return 2;
      return 1;
    };

    return filtered.slice().sort((a, b) => {
      const ra = rank(a.Status);
      const rb = rank(b.Status);
      if (ra !== rb) return ra - rb;
      return (a.DisplayName || a.Name)
        .toLowerCase()
        .localeCompare((b.DisplayName || b.Name).toLowerCase());
    });
  });

  const effectiveWhitelistItems = $derived.by((): WhitelistServiceItem[] => {
    if (whitelistItems.length > 0) return whitelistItems;
    return whitelist.map((name) => {
      const d = whitelistDescriptions[name];
      return {
        Name: name,
        DisplayName: name,
        Status: '',
        isCoreLocked: false,
        SummaryRu: d?.summaryRu ?? 'Защищённая служба Windows.',
        CanDisableHint: d?.canDisableRu ?? ''
      };
    });
  });

  const filteredKeepItems = $derived.by(() => {
    if (!normalizedQuery) return effectiveWhitelistItems;
    return effectiveWhitelistItems.filter(
      (w) =>
        w.Name.toLowerCase().includes(normalizedQuery) ||
        w.DisplayName.toLowerCase().includes(normalizedQuery) ||
        (w.SummaryRu ?? '').toLowerCase().includes(normalizedQuery)
    );
  });

  const userKeepItems = $derived(filteredKeepItems.filter((w) => !w.isCoreLocked));
  const coreKeepItems = $derived(filteredKeepItems.filter((w) => w.isCoreLocked));

  const filteredAllInstalled = $derived.by(() => {
    if (!normalizedQuery) return allInstalledServices;
    return allInstalledServices.filter(
      (s) =>
        s.Name.toLowerCase().includes(normalizedQuery) ||
        s.DisplayName.toLowerCase().includes(normalizedQuery) ||
        (s.SummaryRu ?? '').toLowerCase().includes(normalizedQuery)
    );
  });

  $effect(() => {
    void normalizedQuery;
    void selectedCategory;
    void viewMode;
    void showNotInstalled;
    visibleDisableLimit = 60;
    visibleKeepLimit = 60;
    visibleAllLimit = 60;
    openMenuService = null;
  });

  const visibleDisable = $derived(sortedAndFilteredDisable.slice(0, visibleDisableLimit));
  const visibleCoreKeep = $derived(coreKeepItems.slice(0, visibleKeepLimit));
  const visibleAll = $derived(filteredAllInstalled.slice(0, visibleAllLimit));

  const hasActiveFilters = $derived(
    searchQuery.trim().length > 0 || (viewMode === 'disable' && selectedCategory !== 'all')
  );

  function resetFilters() {
    onSearchChange('');
    onCategoryChange('all');
  }

  async function handleAddServiceSubmit(e: SubmitEvent) {
    e.preventDefault();
    const cleanedName = newServiceName.trim();
    if (!cleanedName) return;

    await onUpdateServiceList({
      listType: viewMode === 'keep' ? 'whitelist' : 'blacklist',
      serviceName: cleanedName,
      category: viewMode === 'keep' ? undefined : newServiceCategory,
      reason: viewMode === 'keep' ? undefined : (newServiceReason.trim() || 'Добавлено пользователем'),
      operation: 'add'
    });

    newServiceName = '';
    newServiceReason = '';
  }

  async function handleMoveKeepToDisable(svcName: string) {
    if (onMoveToDisableList) {
      await onMoveToDisableList(svcName);
    } else {
      await onUpdateServiceList({
        listType: 'whitelist',
        serviceName: svcName,
        operation: 'remove'
      });
    }
  }
</script>

<svelte:window
  onclick={() => {
    openMenuService = null;
  }}
  onkeydown={(e) => {
    if (e.key === 'Escape') {
      openMenuService = null;
    }
  }}
/>

<div class="space-y-4">
  <!-- Header Card -->
  <section class="ui-card rounded-2xl p-5 space-y-4">
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
      <div class="space-y-1">
        <h1 class="text-base font-semibold text-[var(--text-primary)]">
          Службы Windows в игровом режиме
        </h1>
        <p class="text-sm text-[var(--text-secondary)]">
          Настройте, какие службы временно отключаются перед игрой (и автоматически восстанавливаются при выходе).
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
              Служба Wi-Fi сейчас настроена на отключение в игровом режиме — если вы играете по Wi-Fi (а не по кабелю), оставьте её включённой.
            </p>
          </div>
        </div>

        <button
          type="button"
          disabled={busyFeaturePack !== null}
          onclick={() => onApplyFeaturePack?.('wifi', true)}
          class="ui-btn-warn ui-pressable rounded-lg px-3.5 py-2 min-h-9 text-xs font-semibold shrink-0 disabled:opacity-55 cursor-pointer"
        >
          Оставить Wi-Fi включённым
        </button>
      </div>
    {/if}

    <!-- Feature Packs Quick Toggles -->
    {#if featurePacks.length > 0}
      <div class="space-y-2.5 pt-1">
        <div class="space-y-0.5">
          <h2 class="text-[0.8125rem] font-semibold text-[var(--text-primary)]">
            Что вам нужно во время игры?
          </h2>
          <p class="text-xs text-[var(--text-muted)]">
            Быстрые переключатели защищают или разрешают отключение целой группы связанных служб Windows в 1 клик.
          </p>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
          {#each featurePacks as pack (pack.id)}
            {@const isPackBusy = busyFeaturePack === pack.id}
            <button
              type="button"
              disabled={busyFeaturePack !== null || busyService !== null}
              aria-pressed={pack.keepEnabledInGame}
              onclick={() => onApplyFeaturePack?.(pack.id, !pack.keepEnabledInGame)}
              class="{pack.keepEnabledInGame
                ? 'ui-card-selected'
                : 'ui-card-interactive'} rounded-xl px-3.5 py-2.5 text-start flex items-start justify-between gap-2.5 disabled:opacity-55 cursor-pointer"
            >
              <div class="flex items-start gap-2.5 min-w-0">
                <span
                  class="w-7 h-7 rounded-lg flex items-center justify-center shrink-0 mt-0.5 {pack.keepEnabledInGame
                    ? 'bg-[var(--status-active-soft)] text-[var(--status-active-text)]'
                    : 'bg-[var(--bg-elevated)] text-[var(--text-muted)]'}"
                >
                  {#if isPackBusy}
                    <Loader2 size={14} strokeWidth={2} class="ui-spin" aria-hidden="true" />
                  {:else if pack.id === 'wifi'}
                    <Wifi size={14} strokeWidth={1.85} aria-hidden="true" />
                  {:else if pack.id === 'bluetooth'}
                    <Bluetooth size={14} strokeWidth={1.85} aria-hidden="true" />
                  {:else if pack.id === 'faceit'}
                    <Shield size={14} strokeWidth={1.85} aria-hidden="true" />
                  {:else if pack.id === 'camera'}
                    <Camera size={14} strokeWidth={1.85} aria-hidden="true" />
                  {:else if pack.id === 'xbox'}
                    <Gamepad2 size={14} strokeWidth={1.85} aria-hidden="true" />
                  {:else if pack.id === 'vpn'}
                    <Globe size={14} strokeWidth={1.85} aria-hidden="true" />
                  {:else}
                    <Printer size={14} strokeWidth={1.85} aria-hidden="true" />
                  {/if}
                </span>

                <div class="min-w-0 space-y-0.5">
                  <div class="text-[0.8125rem] font-semibold text-[var(--text-primary)] leading-snug">
                    {pack.title}
                  </div>
                  <p class="text-xs text-[var(--text-muted)] leading-snug">
                    {pack.description}
                  </p>
                </div>
              </div>

              <span
                class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[0.7rem] font-semibold border shrink-0 {pack.keepEnabledInGame
                  ? 'bg-[var(--status-active-soft)] text-[var(--status-active-text)] border-[var(--status-active-border)]'
                  : 'bg-[var(--bg-elevated)] text-[var(--text-muted)] border-[var(--border-subtle)]'}"
              >
                {#if pack.keepEnabledInGame}
                  <Check size={10} strokeWidth={2.5} aria-hidden="true" />
                  <span>Вкл</span>
                {:else}
                  <span>Откл.</span>
                {/if}
              </span>
            </button>
          {/each}
        </div>
      </div>
    {/if}

    <!-- Segmented View Toggle + Search -->
    <div class="flex flex-col lg:flex-row lg:items-center gap-3 pt-1">
      <div
        class="inline-flex flex-wrap gap-1.5 p-1 rounded-xl bg-[var(--bg-elevated)] border border-[var(--border-subtle)]"
        role="group"
        aria-label="Режим просмотра служб"
      >
        <button
          type="button"
          onclick={() => onViewModeChange('disable')}
          aria-pressed={viewMode === 'disable'}
          class="{viewMode === 'disable'
            ? 'ui-btn-primary'
            : 'ui-btn-ghost'} ui-pressable rounded-lg px-3 py-2 min-h-9 text-[0.8125rem] font-medium flex items-center gap-2 cursor-pointer"
        >
          <ShieldAlert size={15} strokeWidth={1.75} aria-hidden="true" />
          <span>Отключаются в игре</span>
          <span class="tabular-nums opacity-90">({blacklist.length})</span>
        </button>

        <button
          type="button"
          onclick={() => onViewModeChange('keep')}
          aria-pressed={viewMode === 'keep'}
          class="{viewMode === 'keep'
            ? 'ui-btn-primary'
            : 'ui-btn-ghost'} ui-pressable rounded-lg px-3 py-2 min-h-9 text-[0.8125rem] font-medium flex items-center gap-2 cursor-pointer"
        >
          <ShieldCheck size={15} strokeWidth={1.75} aria-hidden="true" />
          <span>Всегда включены</span>
          <span class="tabular-nums opacity-90">({whitelist.length})</span>
        </button>

        <button
          type="button"
          onclick={() => onViewModeChange('all')}
          aria-pressed={viewMode === 'all'}
          class="{viewMode === 'all'
            ? 'ui-btn-primary'
            : 'ui-btn-ghost'} ui-pressable rounded-lg px-3 py-2 min-h-9 text-[0.8125rem] font-medium flex items-center gap-2 cursor-pointer"
        >
          <Server size={15} strokeWidth={1.75} aria-hidden="true" />
          <span>Все службы ПК</span>
          {#if allInstalledServices.length > 0}
            <span class="tabular-nums opacity-90">({allInstalledServices.length})</span>
          {/if}
        </button>
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
          placeholder="Найти по названию, имени службы или описанию…"
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

    {#if viewMode === 'disable'}
      <div class="space-y-2.5 pt-1">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <div class="flex flex-wrap items-center gap-1.5" role="group" aria-label="Категории служб">
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
                  : 'bg-[var(--bg-elevated)] text-[var(--text-secondary)] border-[var(--border-input)] hover:bg-[var(--bg-hover)]'} ui-pressable rounded-lg border px-2.5 py-1 min-h-8 text-xs font-medium cursor-pointer"
              >
                {CATEGORY_LABELS[cat]}
              </button>
            {/each}
          </div>
        </div>

        <div class="flex flex-wrap items-center justify-between gap-2">
          <label class="inline-flex items-center gap-2 text-xs font-medium text-[var(--text-secondary)] cursor-pointer select-none">
            <input
              type="checkbox"
              bind:checked={showNotInstalled}
              class="w-4 h-4 rounded accent-[var(--accent-solid)] cursor-pointer"
            />
            <span>Показать не установленные на этом ПК ({notInstalledBlacklistCount})</span>
          </label>

          <p class="text-[0.8125rem] text-[var(--text-muted)] tabular-nums" aria-live="polite">
            Показано {visibleDisable.length} из {sortedAndFilteredDisable.length}
          </p>
        </div>
      </div>
    {:else if viewMode === 'keep'}
      <form onsubmit={handleAddServiceSubmit} class="flex flex-col sm:flex-row gap-2 pt-1">
        <label for="new-service-keep" class="sr-only">Системное имя службы для защиты</label>
        <input
          id="new-service-keep"
          type="text"
          autocomplete="off"
          spellcheck={false}
          bind:value={newServiceName}
          placeholder="Имя службы, которую всегда нужно оставлять включённой…"
          class="ui-input flex-1 rounded-xl px-3.5 py-2 min-h-10 text-sm"
        />
        <button
          type="submit"
          disabled={!newServiceName.trim() || busyService !== null}
          class="ui-btn-primary ui-pressable rounded-xl px-4 py-2 min-h-10 text-[0.8125rem] font-medium inline-flex items-center justify-center gap-1.5 shrink-0 disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer"
        >
          <Plus size={15} strokeWidth={2} aria-hidden="true" />
          <span>Защитить службу</span>
        </button>
      </form>
    {:else}
      <p class="text-[0.8125rem] text-[var(--text-muted)] tabular-nums" aria-live="polite">
        Найдено {filteredAllInstalled.length} установленных служб Windows (показано {visibleAll.length})
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
      <span>Загружаю службы Windows…</span>
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
  {:else if viewMode === 'disable'}
    {#if sortedAndFilteredDisable.length === 0}
      <div class="ui-card rounded-2xl p-8 text-center space-y-3">
        <p class="text-sm font-semibold text-[var(--text-primary)]">
          Службы не найдены
        </p>
        <p class="text-sm text-[var(--text-secondary)]">
          Попробуйте изменить поиск или включить показ неустановленных служб.
        </p>
        <div class="flex flex-wrap justify-center gap-2">
          {#if !showNotInstalled && notInstalledBlacklistCount > 0}
            <button
              type="button"
              onclick={() => (showNotInstalled = true)}
              class="ui-btn-secondary ui-pressable rounded-lg px-4 py-2 min-h-9 text-[0.8125rem] font-medium cursor-pointer"
            >
              Показать не установленные ({notInstalledBlacklistCount})
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
      <ul class="ui-card rounded-2xl divide-y divide-[var(--border-subtle)]">
        {#each visibleDisable as svc (svc.Name)}
          {@const showDisplay =
            svc.DisplayName.trim().length > 0 && svc.DisplayName.trim() !== svc.Name.trim()}
          {@const sLabel = statusLabel(svc.Status)}
          {@const stLabel = startTypeLabel(svc.StartType)}
          {@const summary = svc.SummaryRu?.trim() || svc.Reason}
          {@const hint = svc.CanDisableHint?.trim()}
          {@const caution = isConditionalCautionHint(hint)}
          {@const isMenuOpen = openMenuService === svc.Name}
          <li class="relative first:rounded-t-2xl last:rounded-b-2xl p-4 flex flex-col sm:flex-row sm:items-start justify-between gap-3">
            <div class="min-w-0 flex-1 space-y-1.5">
              <div class="flex flex-wrap items-center gap-2">
                <span class="text-sm font-semibold text-[var(--text-primary)] break-words">
                  {showDisplay ? svc.DisplayName : svc.Reason}
                </span>
                <code
                  translate="no"
                  class="font-mono text-xs px-2 py-0.5 rounded-md bg-[var(--bg-elevated)] text-[var(--text-secondary)] select-text"
                >
                  {svc.Name}
                </code>
                <span class="inline-flex items-center rounded-full px-2 py-0.5 text-[0.7rem] font-medium bg-[var(--bg-elevated)] text-[var(--text-secondary)] border border-[var(--border-subtle)]">
                  {CATEGORY_LABELS[svc.Category] ?? svc.Category}
                </span>
                {#if sLabel}
                  <span
                    class="inline-flex items-center rounded-full px-2 py-0.5 text-[0.7rem] font-medium border {svc.Status === 'Running'
                      ? 'bg-[var(--status-active-soft)] text-[var(--status-active-text)] border-[var(--status-active-border)]'
                      : 'bg-[var(--bg-elevated)] text-[var(--text-muted)] border-[var(--border-subtle)]'}"
                  >
                    {sLabel}{stLabel ? ` · ${stLabel}` : ''}
                  </span>
                {/if}
              </div>

              <p class="text-[0.8125rem] leading-relaxed text-[var(--text-secondary)] break-words">
                {summary}
              </p>

              {#if hint}
                <p
                  class="text-xs leading-relaxed flex items-start gap-1.5 {caution
                    ? 'text-[var(--status-warn-text)]'
                    : 'text-[var(--text-muted)]'}"
                >
                  {#if caution}
                    <AlertTriangle size={13} strokeWidth={1.85} class="shrink-0 mt-0.5" aria-hidden="true" />
                  {/if}
                  <span>{hint}</span>
                </p>
              {/if}
            </div>

            <div class="flex items-center gap-3 shrink-0 pt-0.5">
              <div class="flex items-center gap-2">
                <span
                  id="svc-disable-lbl-{svc.Name}"
                  class="text-xs font-medium text-[var(--status-warn-text)]"
                >
                  Отключать в игре
                </span>
                <button
                  type="button"
                  role="switch"
                  aria-checked={true}
                  aria-labelledby="svc-disable-lbl-{svc.Name}"
                  disabled={busyService !== null}
                  title="Выключите, чтобы служба всегда оставалась включённой в игре"
                  onclick={() =>
                    onUpdateServiceList({
                      listType: 'whitelist',
                      serviceName: svc.Name,
                      operation: 'add'
                    })}
                  class="ui-switch relative inline-flex items-center w-10 h-5 rounded-full shrink-0 disabled:opacity-50 cursor-pointer"
                >
                  <span class="ui-switch-thumb pointer-events-none block w-3.5 h-3.5 rounded-full translate-x-[21px]"></span>
                </button>
              </div>

              <div class="relative">
                <button
                  type="button"
                  aria-label={`Дополнительные действия для службы ${svc.Name}`}
                  aria-expanded={isMenuOpen}
                  disabled={busyService !== null}
                  onclick={(e) => {
                    e.stopPropagation();
                    openMenuService = isMenuOpen ? null : svc.Name;
                  }}
                  class="ui-btn-ghost w-8 h-8 rounded-lg flex items-center justify-center border border-[var(--border-subtle)] cursor-pointer disabled:opacity-50"
                >
                  <MoreHorizontal size={15} strokeWidth={1.75} aria-hidden="true" />
                </button>

                {#if isMenuOpen}
                  <div
                    role="menu"
                    tabindex="-1"
                    onclick={(e) => e.stopPropagation()}
                    onkeydown={(e) => {
                      if (e.key === 'Escape') openMenuService = null;
                    }}
                    class="absolute right-0 top-full mt-1.5 z-40 w-52 rounded-xl p-1.5 bg-[var(--bg-surface)] border border-[var(--border-strong)] shadow-[var(--shadow-dialog)] text-xs space-y-0.5"
                  >
                    {#if svc.Status && svc.Status !== 'NotInstalled'}
                      <button
                        type="button"
                        role="menuitem"
                        onclick={() => {
                          openMenuService = null;
                          onControlService(
                            svc.Name,
                            svc.Status === 'Running' ? 'Stop' : 'Start'
                          );
                        }}
                        class="w-full text-start px-3 py-2 rounded-lg hover:bg-[var(--bg-hover)] text-[var(--text-primary)] font-medium cursor-pointer"
                      >
                        {svc.Status === 'Running' ? 'Остановить сейчас' : 'Запустить сейчас'}
                      </button>
                      <button
                        type="button"
                        role="menuitem"
                        onclick={() => {
                          openMenuService = null;
                          onControlService(svc.Name, 'Automatic');
                        }}
                        class="w-full text-start px-3 py-1.5 rounded-lg hover:bg-[var(--bg-hover)] text-[var(--text-secondary)] cursor-pointer"
                      >
                        Тип запуска: Авто
                      </button>
                      <button
                        type="button"
                        role="menuitem"
                        onclick={() => {
                          openMenuService = null;
                          onControlService(svc.Name, 'Manual');
                        }}
                        class="w-full text-start px-3 py-1.5 rounded-lg hover:bg-[var(--bg-hover)] text-[var(--text-secondary)] cursor-pointer"
                      >
                        Тип запуска: Вручную
                      </button>
                      <button
                        type="button"
                        role="menuitem"
                        onclick={() => {
                          openMenuService = null;
                          onControlService(svc.Name, 'Disabled');
                        }}
                        class="w-full text-start px-3 py-1.5 rounded-lg hover:bg-[var(--bg-hover)] text-[var(--text-secondary)] cursor-pointer"
                      >
                        Тип запуска: Отключена
                      </button>
                      <div class="my-1 border-t border-[var(--border-subtle)]"></div>
                    {/if}

                    <button
                      type="button"
                      role="menuitem"
                      onclick={() => {
                        openMenuService = null;
                        onUpdateServiceList({
                          listType: 'blacklist',
                          serviceName: svc.Name,
                          operation: 'remove'
                        });
                      }}
                      class="w-full text-start px-3 py-2 rounded-lg hover:bg-[var(--status-danger-soft)] text-[var(--status-danger-text)] cursor-pointer"
                    >
                      Убрать из списков
                    </button>
                  </div>
                {/if}
              </div>
            </div>
          </li>
        {/each}
      </ul>
      {#if sortedAndFilteredDisable.length > visibleDisable.length}
        <div class="flex justify-center pt-1">
          <button
            type="button"
            onclick={() => (visibleDisableLimit += 60)}
            class="ui-btn-secondary ui-pressable rounded-xl px-4 py-2 min-h-9 text-[0.8125rem] font-medium cursor-pointer"
          >
            Показать ещё ({Math.min(60, sortedAndFilteredDisable.length - visibleDisable.length)} из {sortedAndFilteredDisable.length - visibleDisable.length} оставшихся)
          </button>
        </div>
      {/if}
    {/if}
  {:else if viewMode === 'keep'}
    <div class="space-y-4">
      <section class="ui-card rounded-2xl p-4 sm:p-5 space-y-3">
        <div class="space-y-0.5">
          <h2 class="text-sm font-semibold text-[var(--text-primary)]">
            Ваши исключения и нужные функции ({userKeepItems.length})
          </h2>
          <p class="text-[0.8125rem] text-[var(--text-secondary)]">
            Эти службы защищены от отключения в игре (включая FACEIT AC по умолчанию). Вы можете перенести любую из них в список отключаемых.
          </p>
        </div>

        {#if userKeepItems.length === 0}
          <p class="text-sm text-[var(--text-muted)] py-3 text-center">
            Пользовательские исключения не найдены.
          </p>
        {:else}
          <ul class="divide-y divide-[var(--border-subtle)] rounded-xl border border-[var(--border-subtle)] overflow-hidden">
            {#each userKeepItems as svc (svc.Name)}
              {@const showDisplay =
                svc.DisplayName.trim().length > 0 && svc.DisplayName.trim() !== svc.Name.trim()}
              {@const sLabel = statusLabel(svc.Status)}
              <li class="p-3.5 bg-[var(--bg-surface)] flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                <div class="min-w-0 flex-1 space-y-1">
                  <div class="flex flex-wrap items-center gap-2">
                    <ShieldCheck size={15} strokeWidth={1.85} class="text-[var(--status-active-text)] shrink-0" aria-hidden="true" />
                    <span class="text-sm font-medium text-[var(--text-primary)] break-words">
                      {showDisplay ? svc.DisplayName : svc.Name}
                    </span>
                    <code translate="no" class="font-mono text-xs px-2 py-0.5 rounded-md bg-[var(--bg-elevated)] text-[var(--text-secondary)]">
                      {svc.Name}
                    </code>
                    {#if sLabel}
                      <span class="inline-flex items-center rounded-full px-2 py-0.5 text-[0.7rem] font-medium bg-[var(--bg-elevated)] text-[var(--text-muted)] border border-[var(--border-subtle)]">
                        {sLabel}
                      </span>
                    {/if}
                  </div>
                  {#if svc.SummaryRu}
                    <p class="text-[0.8125rem] text-[var(--text-secondary)]">{svc.SummaryRu}</p>
                  {/if}
                </div>

                <div class="flex flex-wrap items-center gap-2 shrink-0">
                  <button
                    type="button"
                    disabled={busyService !== null}
                    onclick={() => handleMoveKeepToDisable(svc.Name)}
                    class="ui-btn-secondary ui-pressable rounded-lg px-3 py-1.5 min-h-8 text-xs font-medium disabled:opacity-50 cursor-pointer"
                  >
                    Отключать в игре
                  </button>
                  <button
                    type="button"
                    disabled={busyService !== null}
                    onclick={() =>
                      onUpdateServiceList({
                        listType: 'whitelist',
                        serviceName: svc.Name,
                        operation: 'remove'
                      })}
                    class="ui-btn-ghost rounded-lg px-2.5 py-1.5 min-h-8 text-xs font-medium text-[var(--text-muted)] hover:text-[var(--status-danger-text)] disabled:opacity-50 cursor-pointer"
                  >
                    Убрать
                  </button>
                </div>
              </li>
            {/each}
          </ul>
        {/if}
      </section>

      <section class="ui-card rounded-2xl p-4 sm:p-5 space-y-3">
        <div class="flex items-center gap-2">
          <Lock size={15} strokeWidth={1.85} class="text-[var(--text-muted)]" aria-hidden="true" />
          <h2 class="text-sm font-semibold text-[var(--text-primary)]">
            Ядро Windows ({coreKeepItems.length})
          </h2>
        </div>
        <p class="text-[0.8125rem] text-[var(--text-secondary)]">
          Критически важные компоненты звука, сети, RPC и ввода. Блокированы от отключения для стабильности ПК.
        </p>

        {#if coreKeepItems.length === 0}
          <p class="text-sm text-[var(--text-muted)] py-3 text-center">Совпадений не найдено.</p>
        {:else}
          <ul class="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
            {#each visibleCoreKeep as svc (svc.Name)}
              {@const showDisplay =
                svc.DisplayName.trim().length > 0 && svc.DisplayName.trim() !== svc.Name.trim()}
              <li class="rounded-xl p-3.5 bg-[var(--bg-elevated)] border border-[var(--border-subtle)] space-y-1 min-w-0">
                <div class="flex items-center justify-between gap-2">
                  <div class="flex flex-wrap items-center gap-2 min-w-0">
                    <span class="text-[0.8125rem] font-semibold text-[var(--text-primary)] break-words">
                      {showDisplay ? svc.DisplayName : svc.Name}
                    </span>
                    <code translate="no" class="font-mono text-xs text-[var(--text-muted)]">
                      {svc.Name}
                    </code>
                  </div>
                  <Lock size={13} strokeWidth={1.75} class="text-[var(--text-muted)] shrink-0" aria-hidden="true" />
                </div>
                {#if svc.SummaryRu}
                  <p class="text-xs text-[var(--text-secondary)] leading-relaxed">{svc.SummaryRu}</p>
                {/if}
              </li>
            {/each}
          </ul>
          {#if coreKeepItems.length > visibleCoreKeep.length}
            <div class="flex justify-center pt-1">
              <button
                type="button"
                onclick={() => (visibleKeepLimit += 60)}
                class="ui-btn-secondary ui-pressable rounded-xl px-4 py-2 min-h-9 text-[0.8125rem] font-medium cursor-pointer"
              >
                Показать ещё ({Math.min(60, coreKeepItems.length - visibleCoreKeep.length)} из {coreKeepItems.length - visibleCoreKeep.length} оставшихся)
              </button>
            </div>
          {/if}
        {/if}
      </section>
    </div>
  {:else}
    <!-- All Installed Services View -->
    {#if filteredAllInstalled.length === 0}
      <div class="ui-card rounded-2xl p-8 text-center space-y-3">
        <p class="text-sm font-semibold text-[var(--text-primary)]">
          Службы на этом ПК не найдены
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
      <ul class="ui-card rounded-2xl divide-y divide-[var(--border-subtle)] overflow-hidden">
        {#each visibleAll as svc (svc.Name)}
          {@const sLabel = statusLabel(svc.Status)}
          {@const stLabel = startTypeLabel(svc.StartType)}
          <li class="p-3.5 sm:px-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
            <div class="min-w-0 flex-1 space-y-1">
              <div class="flex flex-wrap items-center gap-2">
                <span class="text-sm font-medium text-[var(--text-primary)] break-words">
                  {svc.DisplayName || svc.Name}
                </span>
                <code translate="no" class="font-mono text-xs px-2 py-0.5 rounded-md bg-[var(--bg-elevated)] text-[var(--text-secondary)] select-text">
                  {svc.Name}
                </code>
                {#if sLabel}
                  <span
                    class="inline-flex items-center rounded-full px-2 py-0.5 text-[0.7rem] font-medium border {svc.Status === 'Running'
                      ? 'bg-[var(--status-active-soft)] text-[var(--status-active-text)] border-[var(--status-active-border)]'
                      : 'bg-[var(--bg-elevated)] text-[var(--text-muted)] border-[var(--border-subtle)]'}"
                  >
                    {sLabel}{stLabel ? ` · ${stLabel}` : ''}
                  </span>
                {/if}
                {#if svc.membership === 'core'}
                  <span class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[0.7rem] font-medium bg-[var(--bg-elevated)] text-[var(--text-secondary)] border border-[var(--border-subtle)]">
                    <Lock size={10} strokeWidth={2} aria-hidden="true" />
                    <span>Ядро Windows</span>
                  </span>
                {:else if svc.membership === 'whitelist'}
                  <span class="inline-flex items-center rounded-full px-2 py-0.5 text-[0.7rem] font-medium bg-[var(--status-active-soft)] text-[var(--status-active-text)] border border-[var(--status-active-border)]">
                    Всегда включена
                  </span>
                {:else if svc.membership === 'blacklist'}
                  <span class="inline-flex items-center rounded-full px-2 py-0.5 text-[0.7rem] font-medium bg-[var(--status-warn-soft)] text-[var(--status-warn-text)] border border-[var(--status-warn-border)]">
                    Отключается в игре
                  </span>
                {/if}
              </div>

              {#if svc.SummaryRu}
                <p class="text-xs text-[var(--text-secondary)] leading-relaxed">{svc.SummaryRu}</p>
              {/if}
            </div>

            <div class="flex flex-wrap items-center gap-1.5 shrink-0">
              {#if !svc.isCoreLocked}
                {#if svc.membership !== 'blacklist'}
                  <button
                    type="button"
                    disabled={busyService !== null}
                    onclick={() =>
                      svc.membership === 'whitelist'
                        ? handleMoveKeepToDisable(svc.Name)
                        : onUpdateServiceList({
                            listType: 'blacklist',
                            serviceName: svc.Name,
                            displayName: svc.DisplayName,
                            category: svc.Category,
                            reason: svc.SummaryRu || svc.DisplayName || 'Добавлено пользователем',
                            operation: 'add'
                          })}
                    class="ui-btn-secondary ui-pressable rounded-lg px-2.5 py-1.5 min-h-8 text-xs font-medium disabled:opacity-50 cursor-pointer"
                  >
                    Отключать в игре
                  </button>
                {/if}

                {#if svc.membership !== 'whitelist'}
                  <button
                    type="button"
                    disabled={busyService !== null}
                    onclick={() =>
                      onUpdateServiceList({
                        listType: 'whitelist',
                        serviceName: svc.Name,
                        operation: 'add'
                      })}
                    class="ui-btn-secondary ui-pressable rounded-lg px-2.5 py-1.5 min-h-8 text-xs font-medium disabled:opacity-50 cursor-pointer"
                  >
                    Всегда включена
                  </button>
                {/if}
              {:else}
                <span class="text-xs text-[var(--text-muted)] px-2">Защищено ОС</span>
              {/if}
            </div>
          </li>
        {/each}
      </ul>
      {#if filteredAllInstalled.length > visibleAll.length}
        <div class="flex justify-center pt-1">
          <button
            type="button"
            onclick={() => (visibleAllLimit += 60)}
            class="ui-btn-secondary ui-pressable rounded-xl px-4 py-2 min-h-9 text-[0.8125rem] font-medium cursor-pointer"
          >
            Показать ещё ({Math.min(60, filteredAllInstalled.length - visibleAll.length)} из {filteredAllInstalled.length - visibleAll.length} оставшихся)
          </button>
        </div>
      {/if}
    {/if}
  {/if}
</div>
