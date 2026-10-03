import {
  type CookieOptions,
  createChunks,
  DEFAULT_COOKIE_OPTIONS,
  isChunkLike,
  parseCookieHeader,
  serializeCookieHeader,
  stringFromBase64URL,
  stringToBase64URL,
} from "@supabase/ssr";

export type { CookieOptions };

/** The session object auth-js persists (`sb-<ref>-auth-token`). */
export interface StoredSession {
  readonly access_token: string;
  readonly refresh_token: string;
  readonly expires_at?: number;
  readonly expires_in?: number;
  readonly token_type?: string;
  readonly user?: unknown;
  readonly [key: string]: unknown;
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

const BASE64_PREFIX = "base64-";

/** Headers that keep responses carrying session cookies out of shared caches. */
export const AUTH_CACHE_HEADERS: Readonly<Record<string, string>> = {
  "Cache-Control": "private, no-cache, no-store, must-revalidate, max-age=0",
  Expires: "0",
  Pragma: "no-cache",
};

/** `sb-<first label of the hostname>-auth-token`, the supabase-js default. */
export function sessionCookieName(url: string): string {
  let name = cookieNames.get(url);
  if (name === undefined) {
    name = `sb-${new URL(url).hostname.split(".")[0] ?? ""}-auth-token`;
    if (cookieNames.size < 16) cookieNames.set(url, name);
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

function combine(
  cookies: readonly CookieRecord[],
  name: string,
): string | undefined {
  const byName = new Map(cookies.map((cookie) => [cookie.name, cookie.value]));
  const whole = byName.get(name);
  if (whole) return whole;
  const parts: string[] = [];
  for (let index = 0; ; index++) {
    const part = byName.get(`${name}.${index}`);
    if (!part) break;
    parts.push(part);
  }
  return parts.length > 0 ? parts.join("") : undefined;
}

function isStoredSession(value: unknown): value is StoredSession {
  if (typeof value !== "object" || value === null) return false;
  // SAFETY: value is a non-null object here, and every field is checked below.
  const session = value as Record<string, unknown>;
  return (
    typeof session["access_token"] === "string" &&
    typeof session["refresh_token"] === "string"
  );
}

/**
 * Reads the session written by `@supabase/ssr` (plain or `base64-`, whole or
 * chunked). Mismatched chunks from a partial write read as no session.
 */
export function readSession(
  cookies: readonly CookieRecord[],
  name: string,
): StoredSession | null {
  const raw = combine(cookies, name);
  if (!raw) return null;
  try {
    const json = raw.startsWith(BASE64_PREFIX)
      ? stringFromBase64URL(raw.slice(BASE64_PREFIX.length))
      : raw;
    const parsed: unknown = JSON.parse(json);
    return isStoredSession(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

/**
 * Cookie writes that store `session` (or clear it with `null`) exactly like
 * `@supabase/ssr`, and expire chunks the new value no longer uses.
 */
export function writeSession(
  existing: readonly CookieRecord[],
  name: string,
  session: StoredSession | null,
  options: CookieOptions = {},
): CookieWrite[] {
  const base: CookieOptions = { ...DEFAULT_COOKIE_OPTIONS, ...options };
  const chunks = session
    ? createChunks(
        name,
        BASE64_PREFIX + stringToBase64URL(JSON.stringify(session)),
      )
    : [];
  const kept = new Set(chunks.map((chunk) => chunk.name));
  const removals = existing
    .filter(
      (cookie) => isChunkLike(cookie.name, name) && !kept.has(cookie.name),
    )
    .map((cookie) => ({
      name: cookie.name,
      value: "",
      options: { ...base, maxAge: 0 },
    }));
  return [
    ...removals,
    ...chunks.map((chunk) => ({
      name: chunk.name,
      value: chunk.value,
      options: base,
    })),
  ];
}

/** Applies cookie writes to a cookie list, as the next request would see it. */
export function applyCookieWrites(
  cookies: readonly CookieRecord[],
  writes: readonly CookieWrite[],
): CookieRecord[] {
  const next = new Map(cookies.map((cookie) => [cookie.name, cookie.value]));
  for (const write of writes) {
    if (write.options.maxAge === 0) next.delete(write.name);
    else next.set(write.name, write.value);
  }
  return [...next].map(([name, value]) => ({ name, value }));
}
