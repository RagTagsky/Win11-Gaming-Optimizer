<script lang="ts">
  import { ChevronDown, ChevronUp, Copy, Terminal, Trash2 } from '@lucide/svelte';
  import type { LogEntry } from '../types';

  interface Props {
    logs: LogEntry[];
    isOpen: boolean;
    onToggle: () => void;
    onClear: () => void;
  }

  let { logs = [], isOpen = false, onToggle, onClear }: Props = $props();

  let copied = $state(false);

  function copyLogs() {
    const text = logs
      .map((l) => `[${l.timestamp}] [${l.level.toUpperCase()}] ${l.message}`)
      .join('\n');
    navigator.clipboard.writeText(text);
    copied = true;
    setTimeout(() => (copied = false), 2000);
  }
</script>

<div
  class="rounded-xl border overflow-hidden transition-all"
  style="background-color: var(--bg-surface); border-color: var(--border-subtle);"
>
  <div
    class="flex items-center justify-between px-4 py-2.5 border-b"
    style="background-color: var(--bg-elevated); border-color: var(--border-subtle);"
  >
    <button
      type="button"
      onclick={onToggle}
      class="flex items-center gap-2 text-xs font-semibold transition-colors cursor-pointer select-none"
      style="color: var(--text-primary);"
    >
      <Terminal class="w-3.5 h-3.5" style="color: var(--text-secondary);" />
      <span>Журнал событий</span>
      <span class="text-[11px] font-mono" style="color: var(--text-muted);">
        ({logs.length})
      </span>
      {#if isOpen}
        <ChevronDown class="w-3.5 h-3.5" style="color: var(--text-muted);" />
      {:else}
        <ChevronUp class="w-3.5 h-3.5" style="color: var(--text-muted);" />
      {/if}
    </button>

    {#if isOpen}
      <div class="flex items-center gap-2">
        <button
          type="button"
          onclick={copyLogs}
          class="flex items-center gap-1.5 text-[11px] font-medium px-2.5 py-1 rounded-md border transition-colors cursor-pointer"
          style="background-color: var(--bg-surface); border-color: var(--border-subtle); color: var(--text-secondary);"
          title="Скопировать журнал"
        >
          <Copy class="w-3 h-3" />
          <span>{copied ? 'Скопировано' : 'Копировать'}</span>
        </button>
        <button
          type="button"
          onclick={onClear}
          class="flex items-center gap-1.5 text-[11px] font-medium px-2.5 py-1 rounded-md border transition-colors cursor-pointer"
          style="background-color: var(--bg-surface); border-color: var(--border-subtle); color: var(--text-secondary);"
          title="Очистить журнал"
        >
          <Trash2 class="w-3 h-3" />
          <span>Очистить</span>
        </button>
      </div>
    {/if}
  </div>

  {#if isOpen}
    <div
      class="p-3.5 max-h-[170px] overflow-y-auto font-mono text-[11px] space-y-1.5 select-text"
      style="background-color: var(--bg-app);"
    >
      {#each logs as log}
        <div class="flex items-start gap-2.5 leading-relaxed">
          <span class="shrink-0 select-none" style="color: var(--text-muted);">
            {log.timestamp}
          </span>
          {#if log.level === 'success'}
            <span class="shrink-0 font-semibold" style="color: var(--active-primary);">Готово</span>
          {:else if log.level === 'warn'}
            <span class="shrink-0 font-semibold" style="color: var(--warn-primary);">Внимание</span>
          {:else if log.level === 'error'}
            <span class="shrink-0 font-semibold" style="color: var(--danger-primary);">Ошибка</span>
          {:else}
            <span class="shrink-0" style="color: var(--accent-primary);">Инфо</span>
          {/if}
          <span class="break-all" style="color: var(--text-primary);">{log.message}</span>
        </div>
      {:else}
        <div class="text-center py-4 text-xs font-sans" style="color: var(--text-muted);">
          Журнал событий пуст
        </div>
      {/each}
    </div>
  {/if}
</div>
