<script lang="ts">
  import { Minus, X, Zap } from '@lucide/svelte';
  import { isTauri } from '../api';

  interface Props {
    title?: string;
  }

  let { title = 'Ultra Gaming Mode v3.0' }: Props = $props();

  async function minimizeWindow() {
    if (isTauri) {
      const { getCurrentWindow } = await import('@tauri-apps/api/window');
      await getCurrentWindow().minimize();
    }
  }

  async function closeWindow() {
    if (isTauri) {
      const { getCurrentWindow } = await import('@tauri-apps/api/window');
      await getCurrentWindow().close();
    }
  }
</script>

<div
  data-tauri-drag-region
  class="h-10 w-full flex items-center justify-between px-3 bg-[#111215]/90 backdrop-blur-md border-b border-[#22242a] select-none z-50 fixed top-0 left-0 right-0"
>
  <!-- Window Title & Icon -->
  <div class="flex items-center gap-2 pointer-events-none">
    <div class="w-5 h-5 rounded flex items-center justify-center bg-[#181a20] border border-[#2b2d35]">
      <Zap class="w-3.5 h-3.5 text-emerald-400" />
    </div>
    <span class="text-xs font-medium tracking-wide text-zinc-300">
      {title}
    </span>
  </div>

  <!-- Window Controls -->
  <div class="flex items-center -mr-2">
    <button
      onclick={minimizeWindow}
      class="w-10 h-10 flex items-center justify-center text-zinc-400 hover:text-zinc-100 hover:bg-[#1a1c23] transition-colors"
      title="Свернуть"
      aria-label="Свернуть"
    >
      <Minus class="w-3.5 h-3.5" />
    </button>
    <button
      onclick={closeWindow}
      class="w-10 h-10 flex items-center justify-center text-zinc-400 hover:text-white hover:bg-rose-600/80 transition-colors"
      title="Закрыть"
      aria-label="Закрыть"
    >
      <X class="w-4 h-4" />
    </button>
  </div>
</div>
