import { defineMiddleware, type SingleKeyEntry } from "@supabase/middleware";

import type { AuthResolution } from "../../auth/resolve.ts";
import type { AuthOutageEvent } from "../../core/events.ts";
import type { Logger } from "../../core/logger.ts";
import type { AnyFunctions, AnyModels } from "../../schema/types.ts";

import {
  AUTH_CACHE_HEADERS,
  clearSessionAtScopes,
  type CookieScope,
  parseCookies,
  type SessionEncoding,
  serializeCookie,
} from "../../auth/session.ts";
import {
  refreshFor,
  type RefreshPolicy,
  shouldCheckSession,
} from "../refresh.ts";
import { callOf, type ServerCore } from "./core.ts";

function checkFor(
  policy: SessionEntryConfig["checkSession"],
  request: Request,
): boolean {
  if (policy === undefined || typeof policy === "boolean")
    return policy ?? false;
  return policy === "navigation"
    ? shouldCheckSession(request)
    : policy(request);
}

export interface SessionEntryConfig {
  /**
   * Refresh an expired cookie session and send the new cookies on the
   * response. Only where cookies can be written once per request (a proxy, a
   * framework middleware); never in Server Components. `'navigation'`
   * refreshes page loads, navigations and form posts (`shouldRefresh`), so
   * parallel `fetch` calls never race on the refresh token. Defaults to false.
   */
  readonly refresh?: RefreshPolicy;
  /**
   * Ask the Auth server whether the session still exists, so a session
   * ended elsewhere (sign-out on another device, an admin revoke) is anon
   * here too. One Auth call per matching request: `true` checks every
   * request, `'navigation'` full page loads (`shouldCheckSession`). Off by
   * default, because a valid token otherwise never calls the Auth server.
   */
  readonly checkSession?:
    | boolean
    | "navigation"
    | ((request: Request) => boolean);
  /** Read the session cookie. Defaults to true; `false` resolves bearer tokens only. */
  readonly cookies?: boolean;
  /**
   * Keeps the invocation alive for event sink sends the handler started:
   * `EdgeRuntime.waitUntil`, the Workers `ctx.waitUntil` or Next's `after`.
   */
  readonly waitUntil?: (promise: Promise<unknown>) => void;
  /**
   * The shape refreshed sessions are written in, `cookies.encode` in
   * `@supabase/ssr`. Use the browser client's value. Defaults to the
   * server's `auth.cookie.encode`, then `user-and-tokens`.
   */
  readonly encode?: SessionEncoding;
  /**
   * Cookie scopes (`domain`, `path`) earlier deploys wrote the session at.
   * Each response to a request that carries the session cookie expires it
   * at these scopes, like `clearAuthCookiesAtScopes` in `@supabase/ssr`, so
   * moving the cookie to a new domain or path is one config change. Never
   * list the current scope: that clears the live session.
   */
  readonly cookieScopes?: readonly CookieScope[];
  /**
   * Called when a refresh failed because the Auth server was unreachable,
   * timed out or answered 5xx or 429. When the access token couldn't be
   * kept (`event.kept` is false), a returned `Response` answers the request
   * instead of the handler, such as a 503 with `Retry-After`. A throw is
   * logged and ignored.
   */
  readonly onAuthOutage?: AuthOutageHook;
}

/** `onAuthOutage` on the session entry and the Next.js proxy. */
export type AuthOutageHook = (
  event: AuthOutageEvent,
  request: Request,
) => Response | undefined | void | Promise<Response | undefined | void>;

/**
 * Runs `hook` for a resolution with an outage and returns its response when
 * the session couldn't be kept.
 */
export async function outageResponse(
  hook: AuthOutageHook | undefined,
  resolution: AuthResolution,
  request: Request,
  logger: Logger,
): Promise<Response | undefined> {
  const outage = resolution.outage;
  if (!hook || !outage) return;
  try {
    const response = await hook(outage, request);
    return outage.kept || !(response instanceof Response)
      ? undefined
      : response;
  } catch (cause) {
    logger.warn("onAuthOutage threw", { cause });
    return;
  }
}

/** Appends `Max-Age=0` writes for the session cookie at the old scopes, and the no-store headers. */
function clearOldScopes(
  response: Response,
  request: Request,
  name: string,
  scopes: readonly CookieScope[],
): Response {
  const writes = clearSessionAtScopes(
    parseCookies(request.headers.get("cookie")),
    name,
    scopes,
  );
  if (writes.length === 0) return response;
  const headers = new Headers(response.headers);
  for (const write of writes)
    headers.append("set-cookie", serializeCookie(write));
  for (const [key, value] of Object.entries(AUTH_CACHE_HEADERS))
    headers.set(key, value);
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

/**
 * Entry contributing `ctx.session`, the request's `AuthResolution`: a bearer
 * token first, the session cookie second. It is the only entry with a
 * response seam for cookies: on the way out it adds the refreshed session
 * cookies and the no-store headers, and hands pending event sends to
 * `waitUntil`.
 */
export function withSession<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
>(
  core: ServerCore<M, F, E, C, P>,
  config: SessionEntryConfig = {},
): SingleKeyEntry<"session", Record<never, never>, AuthResolution<C, P>> {
  return defineMiddleware<
    "session",
    undefined,
    Record<never, never>,
    AuthResolution<C, P>
  >({
    key: "session",
    run: () =>
      async function* (request, ctx) {
        const call = callOf(ctx)?.options;
        const refresh = call
          ? (call.refresh ?? false)
          : refreshFor(config.refresh, request);
        const cookies = call ? call.cookies : config.cookies;
        const checkSession = !call && checkFor(config.checkSession, request);
        const session = await core.resolve(request, {
          ...(refresh === undefined ? {} : { refresh }),
          ...(cookies === undefined ? {} : { cookies }),
          ...(checkSession ? { checkSession } : {}),
          ...(config.encode === undefined ? {} : { encode: config.encode }),
        });
        const outage = await outageResponse(
          config.onAuthOutage,
          session,
          request,
          core.events.logger,
        );
        if (outage) return session.apply(outage);
        try {
          const response = yield { session };
          const applied = session.apply(response);
          return config.cookieScopes?.length
            ? clearOldScopes(
                applied,
                request,
                core.sessionCookie(),
                config.cookieScopes,
              )
            : applied;
        } finally {
          if (config.waitUntil && core.events.pending) {
            config.waitUntil(core.events.settled());
          }
        }
      },
  })();
}
