import { defineMiddleware, type SingleKeyEntry } from "@supabase/middleware";

import type { AuthResolution } from "../../auth/resolve.ts";
import type { AnyFunctions, AnyModels } from "../../schema/types.ts";

import {
  clearSessionAtScopes,
  type CookieScope,
  parseCookies,
  type SessionEncoding,
  serializeCookie,
} from "../../auth/session.ts";
import { callOf, type ServerCore } from "./core.ts";

export interface SessionEntryConfig {
  /**
   * Refresh an expired cookie session and send the new cookies on the
   * response. Only where cookies can be written once per request (a proxy, a
   * framework middleware); never in Server Components. Defaults to false.
   */
  readonly refresh?: boolean;
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
}

/** Appends `Max-Age=0` writes for the session cookie at the old scopes. */
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
        const refresh = call ? (call.refresh ?? false) : config.refresh;
        const cookies = call ? call.cookies : config.cookies;
        const session = await core.resolve(request, {
          ...(refresh === undefined ? {} : { refresh }),
          ...(cookies === undefined ? {} : { cookies }),
          ...(config.encode === undefined ? {} : { encode: config.encode }),
        });
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
