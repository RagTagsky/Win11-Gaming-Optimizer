<script lang="ts">
  import {
    AlertCircle,
    CheckCircle2,
    FileCheck2,
    History,
    Loader2,
    MemoryStick,
    Monitor,
    RotateCcw,
    Sparkles,
    Trash2,
    Wrench,
    X
  } from '@lucide/svelte';
  import type { ConfirmDialogRequest, RepairType } from '../types';

  export interface RepairStatusMessage {
    type: 'success' | 'error';
    text: string;
  }

  interface Props {
    runningRepair: RepairType | null;
    statusMessage: RepairStatusMessage | null;
    onRunRepair: (type: RepairType, title: string, confirm?: ConfirmDialogRequest) => void;
    onDismissStatus: () => void;
  }

  let { runningRepair, statusMessage, onRunRepair, onDismissStatus }: Props = $props();

  interface RepairActionItem {
    id: RepairType;
    title: string;
    description: string;
    buttonLabel: string;
    confirm?: ConfirmDialogRequest;
    tone?: 'default' | 'warn' | 'danger';
  }

  const SAFE_ACTIONS: RepairActionItem[] = [
    {
      id: 'memory',
      title: 'Очистить кэш ОЗУ',
      description:
        'Освобождает резервную память (Standby List) в Windows, помогая убрать подтормаживания при длительных сессиях.',
      buttonLabel: 'Очистить кэш ОЗУ'
    },
    {
      id: 'verify',
      title: 'Проверить целостность конфигурации',
      description:
        'Диагностирует JSON-файлы профилей и настройки драйвера ввода без изменения системных параметров.',
      buttonLabel: 'Проверить конфиги'
    },
    {
      id: 'services',
      title: 'Восстановить службы Windows',
      description:
        'Возвращает исходные типы запуска всем службам из резервного снимка после аварийного завершения игры.',
      buttonLabel: 'Восстановить службы'
    }
  ];

  const CRITICAL_ACTIONS: RepairActionItem[] = [
    {
      id: 'shaders',
      title: 'Очистить кэш шейдеров GPU',
      description:
        'Удаляет накопленные скомпилированные шейдеры DirectX и драйвера видеокарты для устранения графических артефактов.',
      buttonLabel: 'Очистить шейдеры',
      tone: 'warn',
      confirm: {
        title: 'Очистить кэш шейдеров GPU?',
        description:
          'Будут удалены временные файлы кэша DirectX, NVIDIA и AMD. При первом запуске игр возможна повторная компиляция шейдеров.',
        confirmLabel: 'Очистить кэш шейдеров',
        cancelLabel: 'Отмена',
        tone: 'warn'
      }
    },
    {
      id: 'display',
      title: 'Сбросить графический стек (DWM)',
      description:
        'Перезапускает композитор рабочего стола и переинициализирует вывод дисплея при зависании картинки.',
      buttonLabel: 'Сбросить дисплей',
      tone: 'warn',
      confirm: {
        title: 'Сбросить графическую подсистему Windows?',
        description:
          'Экран кратковременно погаснет на 1–2 секунды во время перезапуска DWM. Активные полноэкранные игры могут свернуться.',
        confirmLabel: 'Сбросить дисплей',
        cancelLabel: 'Отмена',
        tone: 'warn'
      }
    },
    {
      id: 'debloat',
      title: 'Оптимизация Windows 11 (Debloat)',
      description:
        'Отключает избыточную телеметрию, Copilot и фоновые виджеты Windows 11 для снижения системного шума.',
      buttonLabel: 'Применить Win11 Debloat',
      tone: 'danger',
      confirm: {
        title: 'Применить Win11 Debloat?',
        description:
          'Внесёт изменения в политику телеметрии, фоновые компоненты Windows 11 и планировщик задач. Исходные значения сохраняются для отката.',
        details: 'Вернуть стандартное поведение можно в любое время кнопкой «Откатить Win11 Debloat».',
        confirmLabel: 'Применить Debloat',
        cancelLabel: 'Отмена',
        tone: 'danger'
      }
    },
    {
      id: 'restore_debloat',
      title: 'Откат Win11 Debloat',
      description:
        'Возвращает стандартные настройки Windows 11 для телеметрии, виджетов и вспомогательных компонентов.',
      buttonLabel: 'Откатить Win11 Debloat',
      tone: 'warn',
      confirm: {
        title: 'Вернуть стандартные параметры Windows 11?',
        description:
          'Отменит применённые ранее твики Win11 Debloat и восстановит системные компоненты ОС по умолчанию.',
        confirmLabel: 'Вернуть параметры ОС',
        cancelLabel: 'Отмена',
        tone: 'warn'
      }
    }
  ];

  const isAnyRunning = $derived(runningRepair !== null);
</script>

<div class="space-y-4">
  <!-- Intro Card -->
  <section class="ui-card rounded-2xl p-5 space-y-1">
    <h1 class="text-base font-semibold text-[var(--text-primary)]">
      Обслуживание и аварийное восстановление
    </h1>
    <p class="text-sm text-[var(--text-secondary)]">
      Инструменты очистки памяти, диагностики целостности и безопасного сброса системных подсистем Windows.
    </p>
  </section>

  <!-- Persistent Status Banner -->
  {#if statusMessage}
    <div
      role={statusMessage.type === 'error' ? 'alert' : 'status'}
      class="ui-card rounded-2xl p-4 border flex items-start justify-between gap-3 {statusMessage.type ===
      'error'
        ? 'bg-[var(--status-danger-soft)] border-[var(--status-danger-border)]'
        : 'bg-[var(--status-active-soft)] border-[var(--status-active-border)]'}"
    >
      <div class="flex items-start gap-3 min-w-0">
        {#if statusMessage.type === 'error'}
          <AlertCircle
            size={18}
            strokeWidth={1.75}
            class="text-[var(--status-danger-text)] shrink-0 mt-0.5"
            aria-hidden="true"
          />
        {:else}
          <CheckCircle2
            size={18}
            strokeWidth={1.75}
            class="text-[var(--status-active-text)] shrink-0 mt-0.5"
            aria-hidden="true"
          />
        {/if}

        <p
          class="text-sm font-medium leading-relaxed break-words {statusMessage.type ===
          'error'
            ? 'text-[var(--status-danger-text)]'
            : 'text-[var(--status-active-text)]'}"
        >
          {statusMessage.text}
        </p>
      </div>

      <button
        type="button"
        onclick={onDismissStatus}
        aria-label="Скрыть результат операции"
        class="ui-btn-ghost w-8 h-8 rounded-lg flex items-center justify-center shrink-0 cursor-pointer"
      >
        <X size={16} strokeWidth={1.75} aria-hidden="true" />
      </button>
    </div>
  {/if}

  <!-- Everyday Maintenance -->
  <section aria-labelledby="repair-safe-heading" class="space-y-3">
    <h2 id="repair-safe-heading" class="text-sm font-semibold text-[var(--text-primary)] px-0.5">
      Быстрое обслуживание и диагностика
    </h2>

    <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
      {#each SAFE_ACTIONS as item (item.id)}
        {@const active = runningRepair === item.id}
        <article class="ui-card rounded-2xl p-4 flex flex-col justify-between gap-4">
          <div class="space-y-2.5">
            <div class="w-9 h-9 rounded-xl bg-[var(--accent-soft)] text-[var(--accent-text)] flex items-center justify-center">
              {#if item.id === 'memory'}
                <MemoryStick size={18} strokeWidth={1.75} aria-hidden="true" />
              {:else if item.id === 'verify'}
                <FileCheck2 size={18} strokeWidth={1.75} aria-hidden="true" />
              {:else}
                <Wrench size={18} strokeWidth={1.75} aria-hidden="true" />
              {/if}
            </div>

            <div class="space-y-1">
              <h3 class="text-sm font-semibold text-[var(--text-primary)]">
                {item.title}
              </h3>
              <p class="text-[0.8125rem] leading-relaxed text-[var(--text-secondary)]">
                {item.description}
              </p>
            </div>
          </div>

          <button
            type="button"
            onclick={() => onRunRepair(item.id, item.title)}
            disabled={isAnyRunning}
            class="ui-btn-secondary ui-pressable w-full rounded-xl px-3.5 py-2 min-h-10 text-sm font-medium flex items-center justify-center gap-2 disabled:opacity-55 disabled:cursor-not-allowed cursor-pointer"
          >
            {#if active}
              <Loader2 size={15} strokeWidth={2} class="ui-spin" aria-hidden="true" />
              <span>Выполняется…</span>
            {:else}
              <span>{item.buttonLabel}</span>
            {/if}
          </button>
        </article>
      {/each}
    </div>
  </section>

  <!-- Disruptive / System Tweaks -->
  <section aria-labelledby="repair-critical-heading" class="space-y-3">
    <div class="space-y-0.5 px-0.5">
      <h2 id="repair-critical-heading" class="text-sm font-semibold text-[var(--text-primary)]">
        Глубокий сброс и компоненты Windows 11
      </h2>
      <p class="text-[0.8125rem] text-[var(--text-secondary)]">
        Перед выполнением появится окно подтверждения с описанием последствий.
      </p>
    </div>

    <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
      {#each CRITICAL_ACTIONS as item (item.id)}
        {@const active = runningRepair === item.id}
        <article class="ui-card rounded-2xl p-4 sm:p-5 flex flex-col justify-between gap-4">
          <div class="flex items-start gap-3.5">
            <div
              class="w-9 h-9 rounded-xl flex items-center justify-center shrink-0 mt-0.5 {item.tone ===
              'danger'
                ? 'bg-[var(--status-danger-soft)] text-[var(--status-danger-text)]'
                : 'bg-[var(--status-warn-soft)] text-[var(--status-warn-text)]'}"
            >
              {#if item.id === 'shaders'}
                <Trash2 size={18} strokeWidth={1.75} aria-hidden="true" />
              {:else if item.id === 'display'}
                <Monitor size={18} strokeWidth={1.75} aria-hidden="true" />
              {:else if item.id === 'debloat'}
                <Sparkles size={18} strokeWidth={1.75} aria-hidden="true" />
              {:else}
                <History size={18} strokeWidth={1.75} aria-hidden="true" />
              {/if}
            </div>

            <div class="space-y-1 min-w-0">
              <h3 class="text-sm font-semibold text-[var(--text-primary)]">
                {item.title}
              </h3>
              <p class="text-[0.8125rem] leading-relaxed text-[var(--text-secondary)]">
                {item.description}
              </p>
            </div>
          </div>

          <div class="flex justify-end">
            <button
              type="button"
              onclick={() => onRunRepair(item.id, item.title, item.confirm)}
              disabled={isAnyRunning}
              class="{item.tone === 'danger'
                ? 'ui-btn-danger'
                : 'ui-btn-warn'} ui-pressable w-full sm:w-auto rounded-xl px-4 py-2 min-h-10 text-sm font-semibold flex items-center justify-center gap-2 disabled:opacity-55 disabled:cursor-not-allowed cursor-pointer"
            >
              {#if active}
                <Loader2 size={15} strokeWidth={2} class="ui-spin" aria-hidden="true" />
                <span>Выполняется…</span>
              {:else}
                {#if item.id === 'restore_debloat'}
                  <RotateCcw size={15} strokeWidth={1.75} aria-hidden="true" />
                {/if}
                <span>{item.buttonLabel}</span>
              {/if}
            </button>
          </div>
        </article>
      {/each}
    </div>
  </section>
</div>
