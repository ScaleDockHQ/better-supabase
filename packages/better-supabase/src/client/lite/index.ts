import { AuthClient } from "@supabase/auth-js";
import { RealtimeClient } from "@supabase/realtime-js";

/**
 * A browser client with Auth and Realtime, and no PostgREST, storage or
 * functions client.
 */
export interface LiteBrowserClient {
  readonly auth: InstanceType<typeof AuthClient>;
  readonly realtime: RealtimeClient;
  channel(topic: string): ReturnType<RealtimeClient["channel"]>;
}

export interface LiteBrowserClientOptions {
  /** Cookie or local storage key. Defaults to `sb-<project>-auth-token`. */
  readonly storageKey?: string;
  /** `localStorage` in the browser. Tests pass a map. */
  readonly storage?: {
    getItem(key: string): string | null;
    setItem(key: string, value: string): void;
    removeItem(key: string): void;
  };
}

/**
 * Auth and Realtime for a route that does not query Postgres from the browser.
 * Cookie sessions stay on `better-supabase/client`, which uses
 * `@supabase/ssr`.
 */
export function createLiteBrowserClient(
  url: string,
  key: string,
  options: LiteBrowserClientOptions = {},
): LiteBrowserClient {
  const storageKey =
    options.storageKey ??
    `sb-${new URL(url).hostname.split(".")[0]}-auth-token`;

  const auth = new AuthClient({
    url: new URL("/auth/v1", url).href,
    headers: { apikey: key },
    storageKey,
    ...(options.storage === undefined ? {} : { storage: options.storage }),
    autoRefreshToken: true,
    persistSession: true,
  });

  const realtime = new RealtimeClient(new URL("/realtime/v1", url).href, {
    params: { apikey: key },
  });

  return { auth, realtime, channel: (topic) => realtime.channel(topic) };
}
