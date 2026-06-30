import AsyncStorage from '@react-native-async-storage/async-storage';
import React, { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import {
  auth as authApi,
  clearToken,
  loadToken,
  LoginResult,
  setToken,
  setUnauthorizedHandler,
  SessionUser,
} from '../lib/api';
import { loadServerUrl } from '../lib/server';

const USER_KEY = 'ts_user';

type AuthState = {
  ready: boolean; // finished restoring any stored session
  user: SessionUser | null;
  /** Returns 'ok' or an MFA challenge the caller must complete. */
  signIn: (
    email: string,
    password: string,
  ) => Promise<{ kind: 'ok' } | { kind: 'mfa'; method: string; challengeToken: string }>;
  completeMfa: (
    challengeToken: string,
    code: string,
  ) => Promise<{ usedBackupCode?: boolean; backupCodesRemaining?: number }>;
  signOut: () => Promise<void>;
  /** Merge changes into the cached session user (e.g. an edited display name). */
  updateUser: (patch: Partial<SessionUser>) => Promise<void>;
  has: (permission: string) => boolean;
  /** Holds the permission directly OR in approval mode — use to show actions
   * that fall back to creating an approval request. */
  canActOrRequest: (permission: string) => boolean;
};

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [ready, setReady] = useState(false);
  const [user, setUser] = useState<SessionUser | null>(null);

  const persist = useCallback(async (token: string, u: SessionUser) => {
    await setToken(token);
    await AsyncStorage.setItem(USER_KEY, JSON.stringify(u));
    setUser(u);
  }, []);

  const signOut = useCallback(async () => {
    await clearToken();
    await AsyncStorage.removeItem(USER_KEY);
    setUser(null);
  }, []);

  const updateUser = useCallback(async (patch: Partial<SessionUser>) => {
    setUser((prev) => {
      if (!prev) return prev;
      const next = { ...prev, ...patch };
      AsyncStorage.setItem(USER_KEY, JSON.stringify(next)).catch(() => undefined);
      return next;
    });
  }, []);

  // Restore the previous session on launch (token + cached user, like the web's
  // ts_token cookie + ts_user localStorage). A stale token simply 401s on the
  // first request, which bounces back to login via the handler below.
  useEffect(() => {
    (async () => {
      // Restore the saved server address first so the first request hits the
      // right host (rather than the build-time default).
      await loadServerUrl();
      const token = await loadToken();
      const raw = await AsyncStorage.getItem(USER_KEY);
      if (token && raw) {
        try {
          setUser(JSON.parse(raw) as SessionUser);
        } catch {
          await signOut();
        }
      }
      setReady(true);
    })();
  }, [signOut]);

  // A 401 anywhere drops the session back to the login screen.
  useEffect(() => {
    setUnauthorizedHandler(() => {
      AsyncStorage.removeItem(USER_KEY).catch(() => undefined);
      setUser(null);
    });
    return () => setUnauthorizedHandler(null);
  }, []);

  const signIn = useCallback(
    async (email: string, password: string) => {
      const res: LoginResult = await authApi.login(email, password);
      if (res.mfaRequired) {
        return { kind: 'mfa' as const, method: res.method, challengeToken: res.challengeToken };
      }
      await persist(res.accessToken, res.user);
      return { kind: 'ok' as const };
    },
    [persist],
  );

  const completeMfa = useCallback(
    async (challengeToken: string, code: string) => {
      const res = await authApi.verifyMfa(challengeToken, code);
      await persist(res.accessToken, res.user);
      return { usedBackupCode: res.usedBackupCode, backupCodesRemaining: res.backupCodesRemaining };
    },
    [persist],
  );

  const has = useCallback(
    (permission: string) => !!user && (user.isAdmin || user.permissions.includes(permission)),
    [user],
  );

  const canActOrRequest = useCallback(
    (permission: string) =>
      !!user &&
      (user.isAdmin ||
        user.permissions.includes(permission) ||
        (user.approvalPermissions ?? []).includes(permission)),
    [user],
  );

  const value = useMemo<AuthState>(
    () => ({ ready, user, signIn, completeMfa, signOut, updateUser, has, canActOrRequest }),
    [ready, user, signIn, completeMfa, signOut, updateUser, has, canActOrRequest],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthState {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}
