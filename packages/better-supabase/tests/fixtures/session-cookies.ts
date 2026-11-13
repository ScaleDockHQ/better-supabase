import {
  createChunks,
  DEFAULT_COOKIE_OPTIONS,
  isChunkLike,
  stringToBase64URL,
} from "@supabase/ssr";

import type {
  CookieOptions,
  CookieRecord,
  CookieWrite,
  SessionEncoding,
  StoredSession,
} from "../../src/auth/session.ts";

/**
 * The cookie writes `@supabase/ssr` makes to store `session` under `name`, and
 * the expiries of the chunks the new value no longer uses: a stored session for
 * tests to send.
 */
export function writeSession(
  existing: readonly CookieRecord[],
  name: string,
  session: StoredSession | null,
  options: CookieOptions = {},
  { encode = "user-and-tokens" }: { readonly encode?: SessionEncoding } = {},
): CookieWrite[] {
  const base: CookieOptions = { ...DEFAULT_COOKIE_OPTIONS, ...options };
  const { user: _user, ...tokens } = session ?? {};
  const value = encode === "tokens-only" ? tokens : session;

  const chunks = session
    ? createChunks(name, `base64-${stringToBase64URL(JSON.stringify(value))}`)
    : [];

  const kept = new Set(chunks.map((chunk) => chunk.name));

  return [
    ...existing
      .filter(
        (cookie) => isChunkLike(cookie.name, name) && !kept.has(cookie.name),
      )
      .map((cookie) => ({
        name: cookie.name,
        value: "",
        options: { ...base, maxAge: 0 },
      })),
    ...chunks.map((chunk) => ({
      name: chunk.name,
      value: chunk.value,
      options: base,
    })),
  ];
}
