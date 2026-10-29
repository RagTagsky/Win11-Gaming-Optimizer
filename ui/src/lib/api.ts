import type { HardwareInfo, LogEntry, ModeState, OptimizationProfile, ServiceItem, TweakSetting } from './types';

// Check if running inside Tauri webview
export const isTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

export async function fetchSystemStatus(): Promise<{
  mode: ModeState;
  profile: OptimizationProfile;
  hardware: HardwareInfo;
  activeSince?: string;
}> {
  if (isTauri) {
    try {
      const { invoke } = await import('@tauri-apps/api/core');
      return await invoke('get_system_status');
    } catch (e) {
      console.warn('Tauri invoke failed, falling back to mock:', e);
    }
  }

  // Fallback mock representation for dev preview
  return {
    mode: 'Normal',
    profile: 'competitive',
    hardware: {
      cpu: 'AMD Ryzen 5 5600X (6C / 12T @ 4.65 GHz)',
      gpu: 'AMD Radeon RX 6600 (8 GB GDDR6)',
      ram: '32 GB DDR4-3600 CL16',
      display: '1920x1080 @ 180Hz (FreeSync / MPO Protected)',
      dpcLatency: '34 µs (Sub-millisecond Realtime)',
      mpoStatus: 'Protected (Overlay Flickering Suppressed)',
    },
  };
}

export async function executeModeAction(action: 'Enable' | 'Restore', profile: OptimizationProfile = 'competitive'): Promise<boolean> {
  if (isTauri) {
    const { invoke } = await import('@tauri-apps/api/core');
    return await invoke('execute_mode_action', { action, profile });
  }

  console.log(`[DevMode] Action executed: ${action} with profile: ${profile}`);
  return true;
}

export async function executeEmergencyRepair(repairType: 'display' | 'services' | 'shaders' | 'verify'): Promise<{ success: boolean; message: string }> {
  if (isTauri) {
    const { invoke } = await import('@tauri-apps/api/core');
    return await invoke('execute_emergency_repair', { repairType });
  }

  console.log(`[DevMode] Emergency repair executed: ${repairType}`);
  return { success: true, message: `Ремонт [${repairType}] успешно выполнен.` };
}
