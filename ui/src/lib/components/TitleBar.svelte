<script lang="ts">
  import { Copy, Minus, Square, X, Zap } from '@lucide/svelte';
  import { invoke } from '@tauri-apps/api/core';
  import { getCurrentWindow } from '@tauri-apps/api/window';

  interface Props {
    title?: string;
  }

  let { title = 'Ultra Gaming Mode v3.0' }: Props = $props();

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
  class="h-10 w-full flex items-center justify-between pl-3 pr-0 bg-[#0d0f13]/95 backdrop-blur-md border-b border-[#1f2027] select-none z-50 fixed top-0 left-0 right-0 cursor-default"
>
  <!-- Window Title & Branding (Draggable) -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    onmousedown={handleMouseDown}
    class="flex items-center gap-2.5 h-full cursor-default select-none pr-3"
  >
    <div class="w-5 h-5 rounded flex items-center justify-center bg-emerald-950/80 border border-emerald-800/60 shadow-sm shadow-emerald-950/40 pointer-events-none">
      <Zap class="w-3.5 h-3.5 text-emerald-400 fill-emerald-400" />
    </div>
    <span class="text-xs font-semibold tracking-wide text-zinc-200 pointer-events-none">
      {title}
    </span>
    <span class="text-[10px] uppercase font-mono px-1.5 py-0.2 rounded bg-zinc-800/80 text-zinc-400 border border-zinc-700/60 pointer-events-none">
      v3.0
    </span>
  </div>

  <!-- Draggable Center Spacer -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    onmousedown={handleMouseDown}
    class="flex-1 h-full cursor-default"
  ></div>

  <!-- Windows 11 Native Controls (Strictly No-Drag) -->
  <div
    class="flex items-center h-full relative z-50 pointer-events-auto"
    style="-webkit-app-region: no-drag; app-region: no-drag;"
  >
    <!-- Minimize -->
    <button
      type="button"
      onmousedown={(e) => e.stopPropagation()}
      onclick={handleMinimize}
      style="-webkit-app-region: no-drag; app-region: no-drag;"
      class="w-11 h-10 flex items-center justify-center text-zinc-400 hover:text-zinc-100 hover:bg-[#1f222b] transition-colors cursor-pointer select-none"
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
      style="-webkit-app-region: no-drag; app-region: no-drag;"
      class="w-11 h-10 flex items-center justify-center text-zinc-400 hover:text-zinc-100 hover:bg-[#1f222b] transition-colors cursor-pointer select-none"
      title={isMaximized ? 'Восстановить' : 'Развернуть'}
      aria-label={isMaximized ? 'Восстановить' : 'Развернуть'}
    >
      {#if isMaximized}
        <Copy class="w-3 h-3 pointer-events-none" />
      {:else}
        <Square class="w-3 h-3 pointer-events-none" />
      {/if}
    </button>

    <!-- Close (Windows 11 red hover) -->
    <button
      type="button"
      onmousedown={(e) => e.stopPropagation()}
      onclick={handleClose}
      style="-webkit-app-region: no-drag; app-region: no-drag;"
      class="w-11 h-10 flex items-center justify-center text-zinc-400 hover:text-white hover:bg-[#c42b1c] active:bg-[#b02619] transition-colors cursor-pointer select-none"
      title="Закрыть"
      aria-label="Закрыть"
    >
      <X class="w-4 h-4 pointer-events-none" />
    </button>
  </div>
</div>
