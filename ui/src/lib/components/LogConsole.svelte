<script lang="ts">
  import { onMount } from 'svelte';
  import { Check, ChevronDown, ChevronUp, Copy, Terminal, Trash2 } from '@lucide/svelte';
  import type { LogEntry } from '../types';

  interface Props {
    logs: LogEntry[];
    expanded: boolean;
    onToggleExpand: () => void;
    onRequestClear: () => void;
    onCopyError: (detail: string) => void;
  }

  let { logs, expanded, onToggleExpand, onRequestClear, onCopyError }: Props = $props();

  let copied = $state(false);
  let copyTimer: ReturnType<typeof setTimeout> | null = null;
  let listEl = $state<HTMLUListElement | null>(null);

  $effect(() => {
    const _len = logs.length;
    if (expanded && listEl && _len > 0) {
      listEl.scrollTop = listEl.scrollHeight;
    }
  });

  onMount(() => {
    return () => {
      if (copyTimer) clearTimeout(copyTimer);
    };
  });

  async function copyLogs() {
    if (logs.length === 0) return;
    const text = logs
      .map((entry) => `[${entry.timestamp}] [${entry.level.toUpperCase()}] ${entry.message}`)
      .join('\n');
    try {
      await navigator.clipboard.writeText(text);
      copied = true;
      if (copyTimer) clearTimeout(copyTimer);
      copyTimer = setTimeout(() => {
        copied = false;
      }, 2000);
    } catch (err) {
      onCopyError(
        err instanceof Error && err.message
          ? err.message
          : 'Буфер обмена недоступен в текущем окне.'
      );
    }
  }

  function levelClasses(level: LogEntry['level']): string {
    switch (level) {
      case 'success':
        return 'text-[var(--status-active-text)]';
      case 'warn':
        return 'text-[var(--status-warn-text)]';
      case 'error':
        return 'text-[var(--status-danger-text)]';
      default:
        return 'text-[var(--text-secondary)]';
    }
  }

  function levelLabel(level: LogEntry['level']): string {
    switch (level) {
      case 'success':
        return 'OK';
      case 'warn':
        return 'WARN';
      case 'error':
        return 'ERR';
      default:
        return 'INFO';
    }
  }
</script>

<section
  aria-label="Журнал операций"
  class="ui-card rounded-2xl overflow-hidden"
>
  <div class="px-3.5 py-2 flex flex-wrap items-center justify-between gap-2 bg-[var(--bg-elevated)]">
    <button
      type="button"
      onclick={onToggleExpand}
      aria-expanded={expanded}
      aria-controls="event-log-panel"
      class="ui-btn-ghost ui-pressable rounded-lg px-2.5 py-1.5 min-h-9 flex items-center gap-2 text-[0.8125rem] font-medium text-[var(--text-primary)] cursor-pointer"
    >
      <Terminal size={15} strokeWidth={1.75} class="text-[var(--accent-text)]" aria-hidden="true" />
      <span>Журнал событий</span>
      <span
        class="rounded-full px-2 py-0.5 text-xs font-semibold tabular-nums bg-[var(--bg-surface)] text-[var(--text-secondary)] border border-[var(--border-subtle)]"
      >
        {logs.length}
      </span>
      {#if expanded}
        <ChevronUp size={15} strokeWidth={1.75} class="text-[var(--text-muted)]" aria-hidden="true" />
      {:else}
        <ChevronDown size={15} strokeWidth={1.75} class="text-[var(--text-muted)]" aria-hidden="true" />
      {/if}
    </button>

    <div class="flex items-center gap-1.5">
      <button
        type="button"
        onclick={copyLogs}
        disabled={logs.length === 0}
        class="ui-btn-ghost ui-pressable rounded-lg px-2.5 py-1.5 min-h-9 text-xs font-medium flex items-center gap-1.5 disabled:opacity-45 disabled:cursor-not-allowed cursor-pointer"
        aria-live="polite"
      >
        {#if copied}
          <Check size={14} strokeWidth={2} class="text-[var(--status-active-text)]" aria-hidden="true" />
          <span class="text-[var(--status-active-text)]">Скопировано</span>
        {:else}
          <Copy size={14} strokeWidth={1.75} aria-hidden="true" />
          <span>Копировать</span>
        {/if}
      </button>

      <button
        type="button"
        onclick={onRequestClear}
        disabled={logs.length === 0}
        class="ui-btn-ghost ui-pressable rounded-lg px-2.5 py-1.5 min-h-9 text-xs font-medium flex items-center gap-1.5 disabled:opacity-45 disabled:cursor-not-allowed cursor-pointer"
      >
        <Trash2 size={14} strokeWidth={1.75} aria-hidden="true" />
        <span>Очистить</span>
      </button>
    </div>
  </div>

  {#if expanded}
    <div id="event-log-panel" class="border-t border-[var(--border-subtle)]">
      {#if logs.length === 0}
        <p class="p-4 text-[0.8125rem] text-[var(--text-muted)]">
          Журнал пуст. События переключения режимов и диагностики появятся здесь.
        </p>
      {:else}
        <ul
          bind:this={listEl}
          class="max-h-52 overflow-y-auto px-4 py-3 space-y-1.5 font-mono text-xs select-text"
        >
          {#each logs as entry (entry.id)}
            <li class="flex items-baseline gap-2.5 leading-relaxed">
              <span class="text-[var(--text-muted)] tabular-nums shrink-0">
                [{entry.timestamp}]
              </span>
              <span class="font-semibold shrink-0 w-10 {levelClasses(entry.level)}" translate="no">
                {levelLabel(entry.level)}
              </span>
              <span class="text-[var(--text-primary)] break-words min-w-0">
                {entry.message}
              </span>
            </li>
          {/each}
        </ul>
      {/if}
    </div>
  {/if}
</section>
