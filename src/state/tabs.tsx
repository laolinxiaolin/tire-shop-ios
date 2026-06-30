import AsyncStorage from '@react-native-async-storage/async-storage';
import React, { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import { DEFAULT_PINNED, destByKey, MAX_PINNED } from '../navigation/destinations';

const STORAGE_KEY = 'ts_tabs';

type TabsState = {
  /** Finished restoring the saved choice (avoids a flash of defaults). */
  ready: boolean;
  /** Ordered destination keys pinned as bottom tabs (excludes the More tab). */
  pinned: string[];
  /** Replace the pinned set; drops unknown keys and caps at MAX_PINNED. */
  setPinned: (keys: string[]) => void;
};

const TabsContext = createContext<TabsState | null>(null);

/** Keep only real destinations and respect the tab cap. */
function sanitize(keys: string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const k of keys) {
    if (destByKey(k) && !seen.has(k)) {
      seen.add(k);
      out.push(k);
    }
  }
  return out.slice(0, MAX_PINNED);
}

export function TabsProvider({ children }: { children: React.ReactNode }) {
  const [ready, setReady] = useState(false);
  const [pinned, setPinnedState] = useState<string[]>(DEFAULT_PINNED);

  useEffect(() => {
    (async () => {
      try {
        const raw = await AsyncStorage.getItem(STORAGE_KEY);
        if (raw) {
          const parsed = sanitize(JSON.parse(raw) as string[]);
          if (parsed.length) setPinnedState(parsed);
        }
      } catch {
        // fall back to defaults
      }
      setReady(true);
    })();
  }, []);

  const setPinned = useCallback((keys: string[]) => {
    const next = sanitize(keys);
    setPinnedState(next);
    AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(next)).catch(() => undefined);
  }, []);

  const value = useMemo<TabsState>(
    () => ({ ready, pinned, setPinned }),
    [ready, pinned, setPinned],
  );
  return <TabsContext.Provider value={value}>{children}</TabsContext.Provider>;
}

export function useTabs(): TabsState {
  const ctx = useContext(TabsContext);
  if (!ctx) throw new Error('useTabs must be used within TabsProvider');
  return ctx;
}
