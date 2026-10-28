import type { CookieOptions } from "@supabase/ssr";

import { clearAuthCookiesAtScopes, createServerClient } from "@supabase/ssr";

import type {
  CookieRecord,
  CookieWrite,
  SessionEncoding,
  StoredSession,
} from "./session.ts";

/**
 * Why a refresh failed: Auth refused the token, another request used it, or
 * Auth was unreachable.
 */
export type RefreshFailure =
  | {
      readonly ok: false;
      readonly reason: "rejected" | "raced";
      readonly status?: number;
      readonly code?: string;
    }
  | {
      readonly ok: false;
      readonly reason: "network";
      readonly cause: "timeout" | "network" | "status";
      readonly status?: number;
    };

export type RefreshOutcome =
  | {
      readonly ok: true;
      readonly session: StoredSession;
      /** The token request was shared with another request. */
      readonly shared: boolean;
    }
  | RefreshFailure;

export interface CookieRefresh {
  readonly outcome: RefreshOutcome;
  /**
   * The cookie writes `@supabase/ssr` made: the new session, or the cleared
   * one.
   */
  readonly writes: readonly CookieWrite[];
  /** The cache headers `@supabase/ssr` sent with the writes, lowercased. */
  readonly headers: Readonly<Record<string, string>>;
}

export interface CookieRefreshOptions {
  readonly url: string;
  readonly publishableKey: string;
  readonly cookieName: string;
  readonly cookieOptions?: CookieOptions;
  readonly encode?: SessionEncoding;
  readonly cookies: readonly CookieRecord[];
  /** The refresh token the session cookie holds. */
  readonly refreshToken: string;
  /**
   * Sends `Sb-Forwarded-For` with the secret key as `apikey`, so Auth's per-IP
   * rate limit counts the user, not the server.
   */
  readonly forwardedFor?: { readonly ip: string; readonly secretKey: string };
  readonly fetch?: typeof fetch;
  /** Milliseconds before the token request counts as unreachable. Defaults to 5000. */
  readonly timeoutMs?: number;
  /** Epoch milliseconds. */
  readonly now?: () => number;
}

/** Auth's code for a refresh token another request already rotated. */
const RACED_CODE = "refresh_token_already_used";

/** How long a token response answers later requests with the same refresh token. */
const REUSE_MS = 10_000;

const RECENT_MAX = 1000;

/** The body the coalescing fetch answers with when Auth is unreachable. */
const UNREACHABLE_CODE = "bsb_auth_unreachable";

interface Settled {
  readonly status: number;
  readonly statusText: string;
  readonly headers: readonly (readonly [string, string])[];
  readonly body: string;
  readonly at: number;
  readonly outage?: {
    readonly cause: "timeout" | "network" | "status";
    readonly status?: number;
  };
}

interface RefreshRegistry {
  readonly inflight: Map<string, Promise<Settled>>;
  readonly recent: Map<string, Settled>;
}

const REGISTRY = Symbol.for("better-supabase.refresh");

/**
 * Shared on `globalThis`, so the proxy and route handlers in other module
 * graphs answer a refresh token with one Auth call.
 */
function registry(): RefreshRegistry {
  // SAFETY: REGISTRY is a module symbol, so nothing else writes to that global slot.
  const scope = globalThis as { [REGISTRY]?: RefreshRegistry };
  const shared = scope[REGISTRY] ?? { inflight: new Map(), recent: new Map() };
  scope[REGISTRY] = shared;

  return shared;
}

/** Forgets every shared token response. For tests. */
export function clearRefreshes(): void {
  const shared = registry();
  shared.inflight.clear();
  shared.recent.clear();
}

interface Trace {
  shared: boolean;
  outage?: Settled["outage"];
  status?: number;
  code?: string;
}

function urlOf(input: string | URL | { readonly url: string }): string {
  if (typeof input === "string") {
    return input;
  }

  return input instanceof URL ? input.href : input.url;
}

function refreshTokenOf(body: RequestInit["body"]): string | undefined {
  if (typeof body !== "string") {
    return undefined;
  }

  try {
    const parsed: unknown = JSON.parse(body);

    return typeof parsed === "object" &&
      parsed !== null &&
      "refresh_token" in parsed &&
      typeof parsed.refresh_token === "string"
      ? parsed.refresh_token
      : undefined;
  } catch {
    return undefined;
  }
}

function errorCodeOf(body: string): string | undefined {
  try {
    const parsed: unknown = JSON.parse(body);

    if (typeof parsed !== "object" || parsed === null) {
      return undefined;
    }

    const code =
      "error_code" in parsed
        ? parsed.error_code
        : "code" in parsed
          ? parsed.code
          : undefined;

    return typeof code === "string" ? code : undefined;
  } catch {
    return undefined;
  }
}

function responseOf(settled: Settled): Response {
  return new Response(settled.body, {
    status: settled.status,
    statusText: settled.statusText,
    headers: settled.headers.map(([name, value]): [string, string] => [
      name,
      value,
    ]),
  });
}

function unreachable(
  outage: NonNullable<Settled["outage"]>,
  now: number,
): Settled {
  // auth-js retries 5xx and thrown fetches with backoff for up to 30 seconds;
  // a 400 returns at once. Its session removal is discarded on an outage.
  return {
    status: 400,
    statusText: "Auth unreachable",
    headers: [["content-type", "application/json"]],
    body: JSON.stringify({
      error_code: UNREACHABLE_CODE,
      msg: "The Auth server could not be reached",
    }),
    at: now,
    outage,
  };
}

/**
 * A `fetch` for auth-js that sends one `grant_type=refresh_token` request per
 * refresh token, however many requests ask at once, and answers repeats of the
 * same token from that response for 10 seconds. Single-use refresh tokens then
 * never race between parallel requests (prefetches, islands, a burst of
 * navigations). Every other request passes through.
 */
function coalescingFetch(
  options: CookieRefreshOptions,
  trace: Trace,
): typeof fetch {
  const base = options.fetch ?? fetch;
  const now = options.now ?? Date.now;

  return async (input, init) => {
    const url = urlOf(input);

    const method = (
      init?.method ?? (input instanceof Request ? input.method : "GET")
    ).toUpperCase();

    const token =
      method === "POST" && url.includes("grant_type=refresh_token")
        ? refreshTokenOf(init?.body)
        : undefined;

    if (token === undefined) {
      return base(input, init);
    }

    const shared = registry();
    const key = `${url}\n${token}`;
    const recent = shared.recent.get(key);

    const settle = (settled: Settled): Response => {
      trace.status = settled.status;

      if (settled.outage) {
        trace.outage = settled.outage;
      } else if (settled.status >= 400) {
        const code = errorCodeOf(settled.body);

        if (code !== undefined) {
          trace.code = code;
        }
      }

      return responseOf(settled);
    };

    if (recent && now() - recent.at < REUSE_MS) {
      trace.shared = true;

      return settle(recent);
    }

    const running = shared.inflight.get(key);

    if (running) {
      trace.shared = true;

      return settle(await running);
    }

    const headers = new Headers(init?.headers);

    if (options.forwardedFor) {
      headers.set("apikey", options.forwardedFor.secretKey);
      headers.set("sb-forwarded-for", options.forwardedFor.ip);
      headers.delete("authorization");
    }

    const timeout = AbortSignal.timeout(options.timeoutMs ?? 5000);

    const signal = init?.signal
      ? AbortSignal.any([init.signal, timeout])
      : timeout;

    const request = (async (): Promise<Settled> => {
      try {
        const response = await base(url, {
          ...init,
          method: "POST",
          headers,
          signal,
        });

        if (response.status >= 500 || response.status === 429) {
          return unreachable(
            { cause: "status", status: response.status },
            now(),
          );
        }

        return {
          status: response.status,
          statusText: response.statusText,
          headers: [...response.headers],
          body: await response.text(),
          at: now(),
        };
      } catch {
        return unreachable(
          { cause: timeout.aborted ? "timeout" : "network" },
          now(),
        );
      }
    })();

    shared.inflight.set(key, request);

    try {
      const settled = await request;

      if (!settled.outage) {
        shared.recent.set(key, settled);

        if (shared.recent.size > RECENT_MAX) {
          shared.recent.delete(shared.recent.keys().next().value!);
        }
      }

      return settle(settled);
    } finally {
      shared.inflight.delete(key);
    }
  };
}

interface Captured {
  readonly writes: CookieWrite[];
  readonly headers: Record<string, string>;
}

function capture(): Captured & {
  setAll(
    cookies: readonly { name: string; value: string; options: CookieOptions }[],
    headers?: Record<string, string>,
  ): void;
} {
  const writes: CookieWrite[] = [];
  const headers: Record<string, string> = {};

  return {
    writes,
    headers,
    setAll(cookies, sent = {}) {
      // auth-js saves a refreshed session more than once; the last write of a
      // cookie at a scope wins.
      for (const cookie of cookies) {
        const at = writes.findIndex(
          (write) =>
            write.name === cookie.name &&
            write.options.path === cookie.options.path &&
            write.options.domain === cookie.options.domain,
        );

        if (at !== -1) {
          writes.splice(at, 1);
        }

        writes.push({
          name: cookie.name,
          value: cookie.value,
          options: cookie.options,
        });
      }

      for (const [name, value] of Object.entries(sent)) {
        headers[name.toLowerCase()] = value;
      }
    },
  };
}

function plainCookies(
  cookies: readonly CookieRecord[],
): { name: string; value: string }[] {
  return cookies.map((cookie) => ({ name: cookie.name, value: cookie.value }));
}

/**
 * Refreshes the cookie session with a `@supabase/ssr` server client made for
 * this request alone, so it delivers the cache headers with its writes. auth-js
 * rotates the token and writes the cookies; the token request goes through a
 * coalescing `fetch`.
 */
export async function refreshCookieSession(
  options: CookieRefreshOptions,
): Promise<CookieRefresh> {
  const trace: Trace = { shared: false };
  const captured = capture();

  const client = createServerClient(options.url, options.publishableKey, {
    cookieOptions: { ...options.cookieOptions, name: options.cookieName },
    cookies: {
      getAll: () => plainCookies(options.cookies),
      setAll: (cookies, headers) => {
        captured.setAll(cookies, headers);
      },
      ...(options.encode === undefined ? {} : { encode: options.encode }),
    },
    global: { fetch: coalescingFetch(options, trace) },
  });

  // An explicit token always refreshes, also for a token that hasn't expired
  // but no longer verifies; a repeat of the token is answered from the shared
  // response, so this never rotates twice.
  const { data, error } = await client.auth.refreshSession({
    refresh_token: options.refreshToken,
  });

  const outcome = ((): RefreshOutcome => {
    if (trace.outage) {
      return {
        ok: false,
        reason: "network",
        cause: trace.outage.cause,
        ...(trace.outage.status === undefined
          ? {}
          : { status: trace.outage.status }),
      };
    }

    if (error || !data.session) {
      const code = trace.code ?? error?.code;

      return {
        ok: false,
        reason:
          code === RACED_CODE || error?.name === "AuthRefreshDiscardedError"
            ? "raced"
            : "rejected",
        ...(trace.status === undefined ? {} : { status: trace.status }),
        ...(code === undefined ? {} : { code }),
      };
    }

    return {
      ok: true,
      session: {
        access_token: data.session.access_token,
        refresh_token: data.session.refresh_token,
        ...(data.session.expires_at === undefined
          ? {}
          : { expires_at: data.session.expires_at }),
      },
      shared: trace.shared,
    };
  })();

  return { outcome, writes: captured.writes, headers: captured.headers };
}

/**
 * The writes that clear the session cookie and its chunks at the current scope
 * and at every scope in `scopes` (an old `domain` or `path`), with the cache
 * headers `@supabase/ssr` sends with them.
 */
export async function clearCookieSession(options: {
  readonly cookieName: string;
  readonly cookies: readonly CookieRecord[];
  readonly cookieOptions?: CookieOptions;
  readonly scopes?: readonly Partial<CookieOptions>[];
  /** Clear the current scope too. Defaults to true. */
  readonly current?: boolean;
}): Promise<{
  readonly writes: readonly CookieWrite[];
  readonly headers: Readonly<Record<string, string>>;
}> {
  const captured = capture();

  await clearAuthCookiesAtScopes({
    getAll: () => plainCookies(options.cookies),
    setAll: (cookies, headers) => {
      captured.setAll(cookies, headers);
    },
    storageKey: options.cookieName,
    scopes: [
      ...(options.current === false ? [] : [{ ...options.cookieOptions }]),
      ...(options.scopes ?? []),
    ],
  });

  return {
    writes: captured.writes,
    headers: captured.writes.length > 0 ? NO_STORE : {},
  };
}

/**
 * The headers `@supabase/ssr` sends with session writes. Its scope-clearing
 * helper sends none, and a response that clears a session must not be cached
 * either.
 */
export const NO_STORE: Readonly<Record<string, string>> = Object.freeze({
  "cache-control": "private, no-cache, no-store, must-revalidate, max-age=0",
  expires: "0",
  pragma: "no-cache",
});
