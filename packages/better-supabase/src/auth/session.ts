import type { CookieOptions } from "@supabase/ssr";

import {
  combineChunks,
  parseCookieHeader,
  serializeCookieHeader,
  stringFromBase64URL,
} from "@supabase/ssr";

export type { CookieOptions };

/**
 * The session object auth-js persists (`sb-<ref>-auth-token`). A `tokens-only`
 * cookie has no `user`: auth-js keeps it in `auth.userStorage`.
 */
export interface StoredSession {
  readonly access_token: string;
  readonly refresh_token: string;
  readonly expires_at?: number;
  readonly expires_in?: number;
  readonly token_type?: string;
  readonly user?: unknown;
  readonly [key: string]: unknown;
}

/**
 * `cookies.encode` in `@supabase/ssr`: `user-and-tokens` stores the user object
 * in the cookie, `tokens-only` stores the access and refresh tokens alone. The
 * server and the browser client must use the same value.
 */
export type SessionEncoding = "user-and-tokens" | "tokens-only";

/** A cookie scope an earlier deploy wrote the session at. */
export interface CookieScope {
  readonly domain?: string;
  readonly path?: string;
}

export interface CookieRecord {
  readonly name: string;
  readonly value: string;
}

export interface CookieWrite {
  readonly name: string;
  readonly value: string;
  readonly options: CookieOptions;
}

/** `sb-<first label of the hostname>-auth-token`, the supabase-js default. */
export function sessionCookieName(url: string): string {
  let name = cookieNames.get(url);

  if (name === undefined) {
    name = `sb-${new URL(url).hostname.split(".")[0] ?? ""}-auth-token`;

    if (cookieNames.size < 16) {
      cookieNames.set(url, name);
    }
  }

  return name;
}

/** Project URLs come from configuration, so a handful of entries suffice. */
const cookieNames = new Map<string, string>();

export function parseCookies(
  header: string | null | undefined,
): CookieRecord[] {
  return header ? parseCookieHeader(header) : [];
}

export function serializeCookie(write: CookieWrite): string {
  return serializeCookieHeader(write.name, write.value, write.options);
}

/**
 * Sessions read per parsed cookie list: one request reads its session more than
 * once.
 */
const sessions = new WeakMap<
  readonly CookieRecord[],
  Map<string, Promise<StoredSession | null>>
>();

async function readStored(
  cookies: readonly CookieRecord[],
  name: string,
): Promise<StoredSession | null> {
  const value = await combineChunks(
    name,
    (chunk) => cookies.find((cookie) => cookie.name === chunk)?.value,
  );

  if (!value) {
    return null;
  }

  try {
    const stored: unknown = JSON.parse(
      value.startsWith("base64-")
        ? stringFromBase64URL(value.slice("base64-".length))
        : value,
    );

    return isStoredSession(stored) ? stored : null;
  } catch {
    return null;
  }
}

function isStoredSession(value: unknown): value is StoredSession {
  return (
    typeof value === "object" &&
    value !== null &&
    "access_token" in value &&
    typeof value.access_token === "string" &&
    "refresh_token" in value &&
    typeof value.refresh_token === "string"
  );
}

/**
 * The session `@supabase/ssr` stored in the `cookieName` cookies, decoded the
 * way its cookie storage does (plain or `base64-`, whole or chunked, either
 * `encode`). An expired session is returned too: the proxy refreshes it. It
 * never calls Auth: verify the access token before you trust it.
 */
export function ssrSession(
  cookies: readonly CookieRecord[],
  cookieName: string,
): Promise<StoredSession | null> {
  let memo = sessions.get(cookies);
  const known = memo?.get(cookieName);

  if (known) {
    return known;
  }

  const read = readStored(cookies, cookieName);

  if (!memo) {
    memo = new Map();
    sessions.set(cookies, memo);
  }

  memo.set(cookieName, read);

  return read;
}

/** Applies cookie writes to a cookie list, as the next request would see it. */
export function applyCookieWrites(
  cookies: readonly CookieRecord[],
  writes: readonly CookieWrite[],
): CookieRecord[] {
  const next = new Map(cookies.map((cookie) => [cookie.name, cookie.value]));

  for (const write of writes) {
    if (write.options.maxAge === 0) {
      next.delete(write.name);
    } else {
      next.set(write.name, write.value);
    }
  }

  return [...next].map(([name, value]) => ({ name, value }));
}
