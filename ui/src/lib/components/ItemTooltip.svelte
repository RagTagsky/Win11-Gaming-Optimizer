<script lang="ts">
  import { tick } from 'svelte';
  import { AlertTriangle, CheckCircle2, ShieldAlert } from '@lucide/svelte';
  import type { SafetyLevel } from '../types';

  export interface TooltipPayload {
    id: string;
    title: string;
    subtitle?: string;
    safetyLevel: SafetyLevel;
    summary: string;
    impact: string;
    metaNote?: string;
  }

  interface Props {
    tooltipId?: string;
    payload: TooltipPayload | null;
    anchorEl: HTMLElement | null;
    onTooltipEnter?: () => void;
    onTooltipLeave?: () => void;
    onDismiss?: () => void;
  }

  let {
    tooltipId = 'ugm-item-tooltip',
    payload,
    anchorEl,
    onTooltipEnter,
    onTooltipLeave,
    onDismiss
  }: Props = $props();

  let popoverEl = $state<HTMLDivElement | null>(null);
  let posLeft = $state(12);
  let posTop = $state(12);
  let isPositioned = $state(false);
  let usingNativePopover = $state(false);

  const verdict = $derived.by(() => {
    const lvl = payload?.safetyLevel ?? 'optional';
    if (lvl === 'safe') {
      return {
        label: 'Можно выключить',
        pillClass:
          'bg-[var(--status-active-soft)] text-[var(--status-active-text)] border-[var(--status-active-border)]',
        dotClass: 'bg-[var(--status-active-text)]'
      };
    }
    if (lvl === 'protected') {
      return {
        label: 'Нельзя выключать',
        pillClass:
          'bg-[var(--status-danger-soft)] text-[var(--status-danger-text)] border-[var(--status-danger-border)]',
        dotClass: 'bg-[var(--status-danger-text)]'
      };
    }
    return {
      label: 'По желанию',
      pillClass:
        'bg-[var(--status-warn-soft)] text-[var(--status-warn-text)] border-[var(--status-warn-border)]',
      dotClass: 'bg-[var(--status-warn-text)]'
    };
  });

  function updateCoordinates() {
    if (!popoverEl || !anchorEl || !payload) return;
    if (!anchorEl.isConnected) {
      onDismiss?.();
      return;
    }
    const anchorRect = anchorEl.getBoundingClientRect();
    if (anchorRect.width === 0 && anchorRect.height === 0) {
      onDismiss?.();
      return;
    }
    const tipRect = popoverEl.getBoundingClientRect();
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    const sideMargin = 12;
    const topMargin = 52; // Reserve clearance below the 44px fixed TitleBar
    const bottomMargin = 12;
    const gap = 8;

    const tipW = tipRect.width || 340;
    const tipH = tipRect.height || 140;

    let left = anchorRect.left;
    if (left + tipW > vw - sideMargin) {
      left = Math.max(sideMargin, vw - tipW - sideMargin);
    }
    if (left < sideMargin) {
      left = sideMargin;
    }

    const spaceBelow = vh - anchorRect.bottom - bottomMargin;
    const spaceAbove = anchorRect.top - topMargin;
    let top: number;
    if (spaceBelow >= tipH + gap || spaceBelow >= spaceAbove) {
      top = Math.min(vh - tipH - bottomMargin, anchorRect.bottom + gap);
    } else {
      top = Math.max(topMargin, anchorRect.top - tipH - gap);
    }
    if (top < topMargin) {
      top = topMargin;
    }

    posLeft = Math.round(left);
    posTop = Math.round(top);
    isPositioned = true;
  }

  $effect(() => {
    const activePayload = payload;
    const activeAnchor = anchorEl;
    const el = popoverEl;
    if (!el) return;

    let cancelled = false;

    if (activePayload && activeAnchor) {
      const supportsPopover = typeof el.showPopover === 'function';
      usingNativePopover = supportsPopover;
      if (supportsPopover) {
        try {
          if (!el.matches(':popover-open')) {
            el.showPopover();
          }
        } catch {
          usingNativePopover = false;
        }
      }
      void tick().then(() => {
        if (cancelled) return;
        updateCoordinates();
        requestAnimationFrame(() => {
          if (!cancelled) updateCoordinates();
        });
      });
    } else {
      isPositioned = false;
      if (typeof el.hidePopover === 'function') {
        try {
          if (el.matches(':popover-open')) {
            el.hidePopover();
          }
        } catch {
          // ignore if already closed or disconnected
        }
      }
    }

    return () => {
      cancelled = true;
    };
  });

  $effect(() => {
    if (!payload) return;

    function handleKeyDown(e: KeyboardEvent) {
      if (e.key === 'Escape') {
        onDismiss?.();
      }
    }

    function handleScroll(e: Event) {
      if (popoverEl && e.target instanceof Node && popoverEl.contains(e.target)) {
        return;
      }
      onDismiss?.();
    }

    function handleResize() {
      onDismiss?.();
    }

    function handlePointerDown(e: PointerEvent) {
      const target = e.target;
      if (!(target instanceof Node)) return;
      if (popoverEl?.contains(target) || anchorEl?.contains(target)) return;
      onDismiss?.();
    }

    window.addEventListener('keydown', handleKeyDown);
    window.addEventListener('scroll', handleScroll, true);
    window.addEventListener('resize', handleResize);
    window.addEventListener('pointerdown', handlePointerDown, true);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
      window.removeEventListener('scroll', handleScroll, true);
      window.removeEventListener('resize', handleResize);
      window.removeEventListener('pointerdown', handlePointerDown, true);
    };
  });
</script>

<div
  bind:this={popoverEl}
  id={tooltipId}
  role="tooltip"
  popover="manual"
  onpointerenter={() => onTooltipEnter?.()}
  onpointerleave={() => onTooltipLeave?.()}
  class="ui-tooltip-popover"
  style="left: {posLeft}px; top: {posTop}px; {payload && anchorEl
    ? `opacity: ${isPositioned ? 1 : 0};${usingNativePopover ? '' : ' display: block;'}`
    : usingNativePopover
      ? ''
      : 'display: none;'}"
>
  {#if payload}
    <div class="ui-tooltip-card rounded-xl p-3.5 w-[22rem] max-w-[calc(100vw-1.5rem)] space-y-2.5 text-left">
      <div class="flex items-start justify-between gap-2">
        <div class="min-w-0 space-y-0.5">
          <div class="text-[0.8125rem] font-semibold text-[var(--text-primary)] leading-snug break-words">
            {payload.title}
          </div>
          {#if payload.subtitle && payload.subtitle.toLowerCase() !== payload.title.toLowerCase()}
            <code
              translate="no"
              class="inline-block font-mono text-[0.7rem] text-[var(--text-muted)] break-all"
            >
              {payload.subtitle}
            </code>
          {/if}
        </div>

        <span
          class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[0.7rem] font-semibold border shrink-0 {verdict.pillClass}"
        >
          {#if payload.safetyLevel === 'safe'}
            <CheckCircle2 size={11} strokeWidth={2.25} aria-hidden="true" />
          {:else if payload.safetyLevel === 'protected'}
            <ShieldAlert size={11} strokeWidth={2.25} aria-hidden="true" />
          {:else}
            <AlertTriangle size={11} strokeWidth={2.25} aria-hidden="true" />
          {/if}
          <span>{verdict.label}</span>
        </span>
      </div>

      <div class="space-y-1.5 text-xs leading-relaxed">
        <p class="text-[var(--text-secondary)] break-words">
          {payload.summary}
        </p>

        {#if payload.impact}
          <div class="rounded-lg px-2.5 py-2 bg-[var(--bg-elevated)] border border-[var(--border-subtle)] text-[var(--text-secondary)] break-words">
            <span class="font-semibold text-[var(--text-primary)]">Отключение: </span>
            <span>{payload.impact}</span>
          </div>
        {/if}
      </div>

      {#if payload.metaNote}
        <p class="text-[0.7rem] text-[var(--text-muted)] pt-0.5 border-t border-[var(--border-subtle)]">
          {payload.metaNote}
        </p>
      {/if}
    </div>
  {/if}
</div>
