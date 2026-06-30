/**
 * Hardcoded API server address. The app always talks to the warehouse server;
 * there is no in-app way to change it (the address-editor UI was removed). To
 * point a build at a different host, change SERVER_URL below and rebuild.
 */

/** The one and only server the app talks to (no trailing slash). */
export const SERVER_URL = 'https://awstire.tail263731.ts.net';

/** Current address — always the hardcoded {@link SERVER_URL}. */
export function getServerUrl(): string {
  return SERVER_URL;
}

/** Kept for the launch sequence (state/auth) — now a no-op that resolves to the
 * hardcoded address; there's nothing to restore from storage anymore. */
export async function loadServerUrl(): Promise<string> {
  return SERVER_URL;
}
