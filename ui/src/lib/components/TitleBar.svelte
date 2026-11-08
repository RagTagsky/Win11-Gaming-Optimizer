<script lang="ts">
  import { Copy, Minus, Moon, Square, Sun, X, Zap } from '@lucide/svelte';
  import { invoke } from '@tauri-apps/api/core';
  import { getCurrentWindow } from '@tauri-apps/api/window';
  import type { ThemeMode } from '../types';

  interface Props {
    title?: string;
    theme: ThemeMode;
    onToggleTheme: () => void;
  }

  let { title = 'Ultra Gaming Mode', theme = 'dark', onToggleTheme }: Props = $props();

  let isMaximized = $state(false);

  function handleMouseDown(e: MouseEvent) {
    if (e.button !== 0) return;
    if (e.detail === 2) {
      handleToggleMaximize(e);
      return;
    }
    invoke('start_dragging').catch(() => {
      getCurrentWindow().startDragging().catch(() => {});
    });
  }

  function handleMinimize(e?: Event) {
    e?.preventDefault();
    e?.stopPropagation();
    invoke('minimize_window').catch(() => {
      getCurrentWindow().minimize().catch(() => {});
    });
  }

  function handleToggleMaximize(e?: Event) {
    e?.preventDefault();
    e?.stopPropagation();
    invoke('toggle_maximize_window')
      .then(() => {
        isMaximized = !isMaximized;
      })
      .catch(async () => {
        try {
          const win = getCurrentWindow();
          await win.toggleMaximize();
          isMaximized = await win.isMaximized();
        } catch {}
      });
  }

  function handleClose(e?: Event) {
    e?.preventDefault();
    e?.stopPropagation();
    invoke('close_window').catch(() => {
      getCurrentWindow()
        .destroy()
        .catch(() => {
          window.close();
        });
    });
  }
</script>

<div
  class="h-10 w-full flex items-center justify-between pl-3.5 pr-0 backdrop-blur-md border-b select-none z-50 fixed top-0 left-0 right-0 cursor-default transition-colors"
  style="background-color: var(--bg-titlebar); border-color: var(--border-subtle);"
>
  <!-- Window Title & Branding (Draggable) -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    onmousedown={handleMouseDown}
    class="flex items-center gap-2.5 h-full cursor-default select-none pr-3"
  >
    <div
      class="w-5 h-5 rounded-md flex items-center justify-center border pointer-events-none"
      style="background-color: var(--accent-soft); border-color: var(--accent-border);"
    >
      <Zap class="w-3.5 h-3.5" style="color: var(--accent-primary);" />
    </div>
    <span
      class="text-xs font-semibold tracking-tight pointer-events-none"
      style="color: var(--text-primary);"
    >
      {title}
    </span>
    <span
      class="text-[11px] font-medium px-1.5 py-0.5 rounded border pointer-events-none"
      style="background-color: var(--bg-elevated); color: var(--text-secondary); border-color: var(--border-subtle);"
    >
      v3.0
    </span>
  </div>

  <!-- Draggable Center Spacer -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    onmousedown={handleMouseDown}
    class="flex-1 h-full cursor-default"
  ></div>

  <!-- Theme Switcher & Native Window Controls -->
  <div
    class="flex items-center h-full relative z-50 pointer-events-auto"
    style="-webkit-app-region: no-drag; app-region: no-drag;"
  >
    <!-- Dark / Light Mode Toggle -->
    <button
      type="button"
      onmousedown={(e) => e.stopPropagation()}
      onclick={onToggleTheme}
      style="-webkit-app-region: no-drag; app-region: no-drag; background-color: var(--bg-elevated); border-color: var(--border-subtle); color: var(--text-secondary);"
      class="flex items-center gap-1.5 px-2.5 py-1 mr-2 rounded-md border text-[11px] font-medium hover:opacity-90 transition-all cursor-pointer select-none"
      title={theme === 'dark' ? 'Переключить на светлую тему' : 'Переключить на тёмную тему'}
      aria-label="Переключить тему оформления"
    >
      {#if theme === 'dark'}
        <Sun class="w-3.5 h-3.5 pointer-events-none" style="color: var(--warn-primary);" />
        <span style="color: var(--text-primary);">Светлая</span>
      {:else}
        <Moon class="w-3.5 h-3.5 pointer-events-none" style="color: var(--accent-primary);" />
        <span style="color: var(--text-primary);">Тёмная</span>
      {/if}
    </button>

    <!-- Minimize -->
    <button
      type="button"
      onmousedown={(e) => e.stopPropagation()}
      onclick={handleMinimize}
      style="-webkit-app-region: no-drag; app-region: no-drag; color: var(--text-secondary);"
      class="w-11 h-10 flex items-center justify-center hover:opacity-100 transition-colors cursor-pointer select-none"
      title="Свернуть"
      aria-label="Свернуть"
    >
      <Minus class="w-3.5 h-3.5 pointer-events-none" />
    </button>

    <!-- Maximize / Restore -->
    <button
      type="button"
      onmousedown={(e) => e.stopPropagation()}
      onclick={handleToggleMaximize}
      style="-webkit-app-region: no-drag; app-region: no-drag; color: var(--text-secondary);"
      class="w-11 h-10 flex items-center justify-center hover:opacity-100 transition-colors cursor-pointer select-none"
      title={isMaximized ? 'Восстановить' : 'Развернуть'}
      aria-label={isMaximized ? 'Восстановить' : 'Развернуть'}
    >
      {#if isMaximized}
        <Copy class="w-3 h-3 pointer-events-none" />
      {:else}
        <Square class="w-3 h-3 pointer-events-none" />
      {/if}
    </button>

    <!-- Close -->
    <button
      type="button"
      onmousedown={(e) => e.stopPropagation()}
      onclick={handleClose}
      style="-webkit-app-region: no-drag; app-region: no-drag; color: var(--text-secondary);"
      class="w-11 h-10 flex items-center justify-center hover:text-white hover:bg-[#c42b1c] active:bg-[#b02619] transition-colors cursor-pointer select-none"
      title="Закрыть"
      aria-label="Закрыть"
    >
      <X class="w-4 h-4 pointer-events-none" />
    </button>
  </div>
</div>
