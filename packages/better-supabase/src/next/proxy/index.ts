import type { NextRequest } from "next/server.js";

import type { BetterSupabase } from "../../core/define.ts";
import type { AnyFunctions, AnyModels } from "../../schema/types.ts";
import type { SessionsHost } from "../../server/sessions-runtime.ts";
import type { NextOptions, ProxyOptions } from "../types.ts";

import { EventHub } from "../../core/events.ts";
import { sessionsRuntime } from "../../server/sessions-runtime.ts";
import { serverSessions } from "../../server/sessions.ts";
import { proxyHandler } from "../proxy-handler.ts";
import { proxyRuntime } from "../proxy-runtime.ts";

export {
  isRedirect,
  mutableResponse,
  overrideRequestHeaders,
  serverTimingValue,
  syncMiddlewareSetCookie,
} from "../proxy.ts";

export { permissionsOf, toSession } from "../../auth/view.ts";

export { postAuthPath } from "../sign-in.ts";

export type { NextOptions, ProxyOptions } from "../types.ts";

/**
 * The `proxy.ts` handler without the Server Component side of `createNext`: it
 * refreshes the session, answers the cookie-only redirect and forwards the
 * refreshed cookies. Pass the options alone and `proxy.ts` imports nothing of
 * your app definition (no schema, repositories or blocks), which keeps its
 * bundle small; pass the definition first only to read its claims schema. The
 * options are those of `createNext`, or `server` to share its `createServer`.
 *
 * ```ts
 * export default createProxy({ protect });
 * ```
 */
export function createProxy<C = unknown, P = unknown>(
  options?: NextOptions & ProxyOptions<C, P>,
): (request: NextRequest) => Promise<Response>;
export function createProxy<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  B = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P, B>,
  options?: NextOptions & ProxyOptions<C, P>,
): (request: NextRequest) => Promise<Response>;
export function createProxy<C = unknown, P = unknown>(
  first: SessionsHost<C, P> | (NextOptions & ProxyOptions<C, P>) = {},
  second: NextOptions & ProxyOptions<C, P> = {},
): (request: NextRequest) => Promise<Response> {
  const hosted = "events" in first && first.events instanceof EventHub;

  // SAFETY: `hosted` tells the two overloads apart; a definition has an EventHub.
  const betterSupabase: SessionsHost<C, P> = hosted
    ? first
    : { events: new EventHub() };

  // SAFETY: the options are the first argument when no definition was passed.
  const options = hosted ? second : (first as NextOptions & ProxyOptions<C, P>);

  const runtime = sessionsRuntime(betterSupabase, options);

  const { sessions } = serverSessions({
    resolve: runtime.resolve,
    memo: runtime.verifiedTokens,
    versions: undefined,
    contextFor: () => {
      throw new Error("The proxy has no request context");
    },
  });

  const base = { resolve: runtime.resolve, sessions };

  const { collector, statsHeader, statsValue, statsRoute, flushAfter } =
    proxyRuntime(betterSupabase, options);

  const handle = proxyHandler<C, P>({
    base,
    logger: betterSupabase.events.logger,
    collector,
    statsHeader,
    statsValue,
    statsRoute,
    flushAfter,
  });

  return (request) => handle(request, options);
}
