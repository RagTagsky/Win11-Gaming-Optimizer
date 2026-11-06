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
    const text = logs.map((l) => `[${l.timestamp}] [${l.level.toUpperCase()}] ${l.message}`).join('\n');
    navigator.clipboard.writeText(text);
    copied = true;
    setTimeout(() => (copied = false), 2000);
  }
</script>

<div class="rounded-xl border border-[#20222a] bg-[#111216] overflow-hidden transition-all shadow-sm">
  <!-- Bar Header -->
  <div class="flex items-center justify-between px-4 py-2.5 bg-[#14151a] border-b border-[#1f2027]">
    <button
      type="button"
      onclick={onToggle}
      class="flex items-center gap-2 text-xs font-semibold text-zinc-300 hover:text-white transition-colors cursor-pointer select-none"
    >
      <Terminal class="w-3.5 h-3.5 text-zinc-400" />
      <span>Консоль выполнения и журнал событий</span>
      <span class="text-[10px] text-zinc-500 font-mono">({logs.length})</span>
      {#if isOpen}
        <ChevronDown class="w-3.5 h-3.5 text-zinc-500" />
      {:else}
        <ChevronUp class="w-3.5 h-3.5 text-zinc-500" />
      {/if}
    </button>

    {#if isOpen}
      <div class="flex items-center gap-2">
        <button
          type="button"
          onclick={copyLogs}
          class="flex items-center gap-1.5 text-[11px] font-medium text-zinc-400 hover:text-zinc-200 px-2.5 py-1 rounded-lg hover:bg-[#1f2027] transition-colors cursor-pointer"
          title="Скопировать журнал"
        >
          <Copy class="w-3 h-3" />
          <span>{copied ? 'Скопировано!' : 'Копировать'}</span>
        </button>
        <button
          type="button"
          onclick={onClear}
          class="flex items-center gap-1.5 text-[11px] font-medium text-zinc-400 hover:text-rose-400 px-2.5 py-1 rounded-lg hover:bg-[#1f2027] transition-colors cursor-pointer"
          title="Очистить"
        >
          <Trash2 class="w-3 h-3" />
          <span>Очистить</span>
        </button>
      </div>
    {/if}
  </div>

  <!-- Collapsible Log Body -->
  {#if isOpen}
    <div class="p-3.5 max-h-[170px] overflow-y-auto font-mono text-[11px] space-y-1 select-text bg-[#0c0d10]">
      {#each logs as log}
        <div class="flex items-start gap-2.5 leading-relaxed">
          <span class="text-zinc-600 shrink-0 select-none">[{log.timestamp}]</span>
          {#if log.level === 'success'}
            <span class="text-emerald-400 shrink-0 font-bold">[OK]</span>
          {:else if log.level === 'warn'}
            <span class="text-amber-400 shrink-0 font-bold">[WARN]</span>
          {:else if log.level === 'error'}
            <span class="text-rose-400 shrink-0 font-bold">[ERR]</span>
          {:else}
            <span class="text-zinc-500 shrink-0">[INFO]</span>
          {/if}
          <span class="text-zinc-300 break-all">{log.message}</span>
        </div>
      {:else}
        <div class="text-zinc-600 text-center py-4 text-xs font-sans">Журнал событий пуст</div>
      {/each}
    </div>
  {/if}
</div>
