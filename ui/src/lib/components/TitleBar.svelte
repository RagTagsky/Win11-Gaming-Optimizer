<script lang="ts">
  import { onMount } from 'svelte';
  import { invoke } from '@tauri-apps/api/core';
  import { getCurrentWindow } from '@tauri-apps/api/window';
  import { Copy, Minus, Moon, Square, Sun, X, Zap } from '@lucide/svelte';
  import { isTauri } from '../api';
  import type { ThemeMode } from '../types';

  interface Props {
    theme: ThemeMode;
    onToggleTheme: () => void;
  }

  let { theme, onToggleTheme }: Props = $props();
  let isMaximized = $state(false);

  onMount(() => {
    if (!isTauri) return;

    let disposed = false;
    let unlisten: (() => void) | null = null;
    const appWindow = getCurrentWindow();

    void appWindow
      .isMaximized()
      .then((max) => {
        if (!disposed) isMaximized = max;
      })
      .catch(() => {});

    void appWindow
      .onResized(async () => {
        try {
          const max = await appWindow.isMaximized();
          if (!disposed) isMaximized = max;
        } catch {
          // ignore transient window query errors
        }
      })
      .then((fn) => {
        if (disposed) {
          fn();
        } else {
          unlisten = fn;
        }
      })
      .catch(() => {});

    return () => {
      disposed = true;
      unlisten?.();
    };
  });

  function startDragIfHeader(e: MouseEvent) {
    if (!isTauri || e.button !== 0) return;
    const target = e.target as HTMLElement | null;
    if (target?.closest('button, a, input, [role="button"]')) return;
    void getCurrentWindow().startDragging().catch(() => {});
  }

  async function handleMinimize() {
    if (!isTauri) return;
    try {
      await invoke('minimize_window');
    } catch {
      void getCurrentWindow().minimize().catch(() => {});
    }
  }

  async function handleToggleMaximize() {
    if (!isTauri) return;
    try {
      isMaximized = await invoke<boolean>('toggle_maximize_window');
    } catch {
      try {
        const win = getCurrentWindow();
        await win.toggleMaximize();
        isMaximized = await win.isMaximized();
      } catch {
        // ignore window control error
      }
    }
  }

  async function handleClose() {
    if (!isTauri) return;
    try {
      await invoke('close_window');
    } catch {
      void getCurrentWindow().close().catch(() => {});
    }
  }
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<header
  onmousedown={startDragIfHeader}
  ondblclick={(e) => {
    const target = e.target as HTMLElement | null;
    if (!target?.closest('button, a, input, [role="button"]')) {
      void handleToggleMaximize();
    }
  }}
  data-tauri-drag-region
  class="fixed top-0 left-0 right-0 z-40 h-11 flex items-center justify-between gap-2 pl-3 pr-0 border-b border-[var(--border-subtle)] bg-[var(--bg-titlebar)] backdrop-blur-md select-none"
>
  <div class="flex items-center gap-2.5 min-w-0" data-tauri-drag-region>
    <div
      class="w-7 h-7 rounded-lg bg-[var(--accent-solid)] text-white flex items-center justify-center shrink-0"
      data-tauri-drag-region
    >
      <Zap size={16} strokeWidth={2} aria-hidden="true" />
    </div>
    <span
      class="text-sm font-semibold tracking-tight text-[var(--text-primary)] truncate"
      data-tauri-drag-region
    >
      Ultra Gaming Mode
    </span>
    <span
      class="max-[440px]:hidden shrink-0 rounded-md px-2 py-0.5 text-xs font-semibold tabular-nums bg-[var(--accent-soft)] text-[var(--accent-text)] border border-[var(--accent-border)]"
      data-tauri-drag-region
    >
      v3.2.0
    </span>
  </div>

  <div class="flex items-center h-full shrink-0">
    <button
      type="button"
      onclick={onToggleTheme}
      class="ui-btn-ghost ui-pressable h-9 px-2.5 sm:px-3 mr-1 rounded-lg flex items-center gap-1.5 text-[0.8125rem] font-medium cursor-pointer"
      aria-label={theme === 'dark'
        ? 'Светлая тема — переключить оформление на светлое'
        : 'Тёмная тема — переключить оформление на тёмное'}
      title={theme === 'dark' ? 'Переключить на светлую тему' : 'Переключить на тёмную тему'}
    >
      {#if theme === 'dark'}
        <Sun size={15} strokeWidth={1.75} aria-hidden="true" />
        <span class="max-[360px]:hidden">Светлая</span>
      {:else}
        <Moon size={15} strokeWidth={1.75} aria-hidden="true" />
        <span class="max-[360px]:hidden">Тёмная</span>
      {/if}
    </button>

    {#if isTauri}
      <div class="flex items-center h-full border-l border-[var(--border-subtle)]">
        <button
          type="button"
          onclick={handleMinimize}
          class="ui-btn-ghost w-11 h-11 flex items-center justify-center cursor-pointer"
          aria-label="Свернуть окно"
          title="Свернуть"
        >
          <Minus size={16} strokeWidth={1.75} aria-hidden="true" />
        </button>

        <button
          type="button"
          onclick={handleToggleMaximize}
          class="ui-btn-ghost w-11 h-11 flex items-center justify-center cursor-pointer"
          aria-label={isMaximized ? 'Восстановить размер окна' : 'Развернуть окно'}
          title={isMaximized ? 'Восстановить' : 'Развернуть'}
        >
          {#if isMaximized}
            <Copy size={13} strokeWidth={1.75} class="scale-x-[-1]" aria-hidden="true" />
          {:else}
            <Square size={13} strokeWidth={1.75} aria-hidden="true" />
          {/if}
        </button>

        <button
          type="button"
          onclick={handleClose}
          class="ui-btn-ghost ui-btn-close w-11 h-11 flex items-center justify-center cursor-pointer"
          aria-label="Закрыть приложение"
          title="Закрыть"
        >
          <X size={16} strokeWidth={1.75} aria-hidden="true" />
        </button>
      </div>
    {/if}
  </div>
</header>
