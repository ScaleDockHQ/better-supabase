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

/**
 * The session object auth-js persists (`sb-<ref>-auth-token`). A
 * `tokens-only` cookie has no `user`: auth-js keeps it in `auth.userStorage`.
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
 * `cookies.encode` in `@supabase/ssr`: `user-and-tokens` stores the user
 * object in the cookie, `tokens-only` stores the access and refresh tokens
 * alone. The server and the browser client must use the same value.
 */
export type SessionEncoding = "user-and-tokens" | "tokens-only";

export const DEFAULT_SESSION_ENCODING: SessionEncoding = "user-and-tokens";

export interface WriteSessionOptions {
  /** Defaults to `user-and-tokens`, the `@supabase/ssr` default. */
  readonly encode?: SessionEncoding;
}

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

/** Cookie values by name, per parsed cookie list: one request reads its session more than once. */
const cookieMaps = new WeakMap<
  readonly CookieRecord[],
  ReadonlyMap<string, string>
>();

function combine(
  cookies: readonly CookieRecord[],
  name: string,
): string | undefined {
  let byName = cookieMaps.get(cookies);
  if (!byName) {
    byName = new Map(cookies.map((cookie) => [cookie.name, cookie.value]));
    cookieMaps.set(cookies, byName);
  }
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
 * chunked, `user-and-tokens` or `tokens-only`). Mismatched chunks from a
 * partial write read as no session.
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

/** The encoding a stored session was written with: `tokens-only` without a `user`. */
export function sessionEncoding(session: StoredSession): SessionEncoding {
  return session.user === undefined || session.user === null
    ? "tokens-only"
    : "user-and-tokens";
}

function encoded(session: StoredSession, encode: SessionEncoding): string {
  switch (encode) {
    case "user-and-tokens":
      return JSON.stringify(session);
    case "tokens-only": {
      const { user: _user, ...tokens } = session;
      return JSON.stringify(tokens);
    }
    default: {
      const unhandled: never = encode;
      return unhandled;
    }
  }
}

/**
 * Cookie writes that store `session` (or clear it with `null`) exactly like
 * `@supabase/ssr` with the same `encode`, and expire chunks the new value no
 * longer uses.
 */
export function writeSession(
  existing: readonly CookieRecord[],
  name: string,
  session: StoredSession | null,
  options: CookieOptions = {},
  { encode = DEFAULT_SESSION_ENCODING }: WriteSessionOptions = {},
): CookieWrite[] {
  const base: CookieOptions = { ...DEFAULT_COOKIE_OPTIONS, ...options };
  const chunks = session
    ? createChunks(
        name,
        BASE64_PREFIX + stringToBase64URL(encoded(session, encode)),
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

/**
 * `Max-Age=0` writes for every chunk of the session cookie at each of
 * `scopes`, like `clearAuthCookiesAtScopes` from `@supabase/ssr`. Use it once
 * the cookie `domain` or `path` changed, for the scopes earlier deploys
 * wrote: browsers ignore writes for scopes the host doesn't own, but a scope
 * equal to the current one clears the live session.
 */
export function clearSessionAtScopes(
  existing: readonly CookieRecord[],
  name: string,
  scopes: readonly CookieScope[],
): CookieWrite[] {
  if (scopes.length === 0) return [];
  const chunks = existing
    .map((cookie) => cookie.name)
    .filter((cookie) => isChunkLike(cookie, name));
  return scopes.flatMap((scope) => {
    const options: CookieOptions = {
      ...DEFAULT_COOKIE_OPTIONS,
      ...(scope.domain === undefined ? {} : { domain: scope.domain }),
      ...(scope.path === undefined ? {} : { path: scope.path }),
      maxAge: 0,
    };
    return chunks.map((chunk) => ({ name: chunk, value: "", options }));
  });
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
