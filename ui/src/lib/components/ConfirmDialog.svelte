<script lang="ts">
  import { AlertTriangle, HelpCircle, OctagonAlert } from '@lucide/svelte';
  import type { ConfirmDialogRequest } from '../types';

  interface Props {
    request: ConfirmDialogRequest | null;
    onResolve: (confirmed: boolean) => void;
  }

  let { request, onResolve }: Props = $props();

  let dialogEl = $state<HTMLDialogElement | null>(null);
  let pointerStartedOutside = false;

  const titleId = 'confirm-dialog-title';
  const descId = 'confirm-dialog-description';

  $effect(() => {
    if (!dialogEl) return;
    if (request && !dialogEl.open) {
      dialogEl.returnValue = '';
      dialogEl.showModal();
    } else if (!request && dialogEl.open) {
      dialogEl.close('');
    }
  });

  function isOutsideRect(e: PointerEvent, el: HTMLDialogElement): boolean {
    const rect = el.getBoundingClientRect();
    return (
      e.clientX < rect.left ||
      e.clientX > rect.right ||
      e.clientY < rect.top ||
      e.clientY > rect.bottom
    );
  }

  function handlePointerDown(e: PointerEvent) {
    if (!dialogEl || e.target !== dialogEl) {
      pointerStartedOutside = false;
      return;
    }
    pointerStartedOutside = isOutsideRect(e, dialogEl);
  }

  function handlePointerUp(e: PointerEvent) {
    if (!dialogEl || 'closedBy' in HTMLDialogElement.prototype) return;
    if (pointerStartedOutside && e.target === dialogEl && isOutsideRect(e, dialogEl)) {
      dialogEl.close('');
    }
    pointerStartedOutside = false;
  }

  function handleClose() {
    if (!dialogEl) return;
    const confirmed = dialogEl.returnValue === 'confirm';
    dialogEl.returnValue = '';
    onResolve(confirmed);
  }

  function confirmButtonClass(tone: ConfirmDialogRequest['tone']): string {
    if (tone === 'danger') return 'ui-btn-danger';
    if (tone === 'warn') return 'ui-btn-warn';
    return 'ui-btn-primary';
  }
</script>

<dialog
  bind:this={dialogEl}
  class="ui-dialog"
  aria-labelledby={titleId}
  aria-describedby={descId}
  onpointerdown={handlePointerDown}
  onpointerup={handlePointerUp}
  onclose={handleClose}
  {...({ closedby: 'any' } as Record<string, string>)}
>
  {#if request}
    <div class="p-6 space-y-5">
      <div class="flex items-start gap-3.5">
        <div
          class="w-10 h-10 rounded-xl flex items-center justify-center shrink-0 border {request.tone === 'danger'
            ? 'bg-[var(--status-danger-soft)] text-[var(--status-danger-text)] border-[var(--status-danger-border)]'
            : request.tone === 'warn'
              ? 'bg-[var(--status-warn-soft)] text-[var(--status-warn-text)] border-[var(--status-warn-border)]'
              : 'bg-[var(--accent-soft)] text-[var(--accent-text)] border-[var(--accent-border)]'}"
        >
          {#if request.tone === 'danger'}
            <OctagonAlert size={20} strokeWidth={1.75} aria-hidden="true" />
          {:else if request.tone === 'warn'}
            <AlertTriangle size={20} strokeWidth={1.75} aria-hidden="true" />
          {:else}
            <HelpCircle size={20} strokeWidth={1.75} aria-hidden="true" />
          {/if}
        </div>

        <div class="min-w-0 space-y-1.5">
          <h2 id={titleId} class="text-base font-semibold leading-snug text-[var(--text-primary)]">
            {request.title}
          </h2>
          <p id={descId} class="text-sm leading-relaxed text-[var(--text-secondary)]">
            {request.description}
          </p>
          {#if request.details}
            <p class="text-[0.8125rem] leading-relaxed text-[var(--text-muted)] pt-0.5">
              {request.details}
            </p>
          {/if}
        </div>
      </div>

      <form method="dialog" class="flex flex-wrap items-center justify-end gap-2.5 pt-1">
        <!-- svelte-ignore a11y_autofocus -->
        <button
          type="submit"
          value="cancel"
          autofocus
          class="ui-btn-secondary ui-pressable rounded-lg px-4 py-2 min-h-9 text-sm font-medium cursor-pointer"
        >
          {request.cancelLabel ?? 'Отмена'}
        </button>

        <button
          type="submit"
          value="confirm"
          class="{confirmButtonClass(request.tone)} ui-pressable rounded-lg px-4 py-2 min-h-9 text-sm font-semibold cursor-pointer"
        >
          {request.confirmLabel}
        </button>
      </form>
    </div>
  {/if}
</dialog>
