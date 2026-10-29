import { extractCredentials } from "@supabase/server/core";

import type { CookieOptions } from "./session.ts";

import { decodeJwtPayload } from "../core/base64.ts";
import {
  parseCookies,
  readSession,
  serializeCookie,
  sessionCookieName,
} from "./session.ts";
import { clearCookieSession } from "./ssr-client.ts";

/** `banned`: Auth rejected the token with `error_code: "user_banned"`. */
export type SessionStatus = "active" | "ended" | "banned" | "unknown";

export interface SessionStatusOptions {
  readonly url: string;
  readonly publishableKey: string;
  readonly cookieName?: string;
  readonly fetch?: typeof fetch;
  readonly timeoutMs?: number;
  readonly now?: () => number;
}

export interface ClearSessionCookiesOptions {
  readonly url: string;
  readonly cookieName?: string;
  readonly cookie?: CookieOptions;
}

const DEFAULT_TIMEOUT_MS = 5000;

function accessTokenOf(
  request: Request,
  options: SessionStatusOptions,
): string | undefined {
  const bearer = extractCredentials(request).token;

  if (bearer) {
    return bearer;
  }

  const session = readSession(
    parseCookies(request.headers.get("cookie")),
    options.cookieName ?? sessionCookieName(options.url),
  );

  return session?.access_token;
}

export async function sessionStatus(
  input: Request | string,
  options: SessionStatusOptions,
): Promise<SessionStatus> {
  const token =
    typeof input === "string" ? input : accessTokenOf(input, options);

  if (!token) {
    return "unknown";
  }

  const exp = decodeJwtPayload(token)?.["exp"];

  if (typeof exp === "number" && exp * 1000 <= (options.now ?? Date.now)()) {
    return "unknown";
  }

  const doFetch = options.fetch ?? fetch;

  try {
    const response = await doFetch(`${options.url}/auth/v1/user`, {
      headers: {
        apikey: options.publishableKey,
        authorization: `Bearer ${token}`,
      },
      signal: AbortSignal.timeout(options.timeoutMs ?? DEFAULT_TIMEOUT_MS),
    });

    if (response.status === 401 || response.status === 403) {
      // SAFETY: the Auth server responds with a JSON object, and the field is checked before use.
      const body = (await response.json().catch(() => null)) as Record<
        string,
        unknown
      > | null;

      return body?.["error_code"] === "user_banned" ? "banned" : "ended";
    }

    await response.body?.cancel();

    return response.ok ? "active" : "unknown";
  } catch {
    return "unknown";
  }
}

/**
 * Clears the session cookie and its chunks on `response`, with the no-store
 * headers, through `@supabase/ssr`. Resolves to `response` unchanged when the
 * request carries no session cookie.
 */
export async function clearSessionCookies<R extends Response>(
  request: Request,
  response: R,
  options: ClearSessionCookiesOptions,
): Promise<R> {
  const { writes, headers } = await clearCookieSession({
    cookieName: options.cookieName ?? sessionCookieName(options.url),
    cookies: parseCookies(request.headers.get("cookie")),
    ...(options.cookie ? { cookieOptions: options.cookie } : {}),
  });

  if (writes.length === 0) {
    return response;
  }

  for (const write of writes) {
    response.headers.append("set-cookie", serializeCookie(write));
  }

  for (const [key, value] of Object.entries(headers)) {
    response.headers.set(key, value);
  }

  return response;
}

const ENDED = Symbol.for("better-supabase.ended-tokens");
const ENDED_LIMIT = 1000;

/** Access tokens a database check found ended, until each token's `exp`. */
type EndedTokens = Map<string, { status: "ended" | "banned"; exp: number }>;

/**
 * Shared on `globalThis`, so the proxy sees what a render in another module
 * graph recorded.
 */
function endedTokens(): EndedTokens {
  // SAFETY: ENDED is a module symbol, so nothing else writes to that global slot.
  const scope = globalThis as { [ENDED]?: EndedTokens };

  scope[ENDED] ??= new Map();

  return scope[ENDED];
}

/**
 * Records that the session behind `token` ended, as `bsb.bootstrap()` learns
 * from `session_active()`, so the proxy clears its cookies on the next request
 * this process serves. A token past its `exp` is not kept.
 */
export function markSessionEnded(
  token: string,
  status: "ended" | "banned",
  now: () => number = Date.now,
): void {
  const exp = decodeJwtPayload(token)?.["exp"];

  if (typeof exp !== "number" || exp * 1000 <= now()) {
    return;
  }

  const tokens = endedTokens();

  for (const [key, entry] of tokens) {
    if (entry.exp * 1000 <= now()) {
      tokens.delete(key);
    }
  }

  if (tokens.size >= ENDED_LIMIT) {
    const oldest = tokens.keys().next();

    if (!oldest.done) {
      tokens.delete(oldest.value);
    }
  }

  tokens.set(token, { status, exp });
}

/** How the session behind `token` ended, if `markSessionEnded` recorded it. */
export function endedSessionOf(
  token: string,
  now: () => number = Date.now,
): "ended" | "banned" | undefined {
  const entry = endedTokens().get(token);

  if (entry === undefined) {
    return undefined;
  }

  if (entry.exp * 1000 <= now()) {
    endedTokens().delete(token);

    return undefined;
  }

  return entry.status;
}
