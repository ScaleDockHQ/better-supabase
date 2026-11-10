import type { NextRequest } from "next/server.js";

import type { BetterSupabase } from "../../core/define.ts";
import type { AnyFunctions, AnyModels } from "../../schema/types.ts";
import type { NextOptions, ProxyOptions } from "../types.ts";

import { createServer } from "../../server/server.ts";
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
 * refreshed cookies. Pass the same options as `createNext`, or `server` to
 * share its `createServer`.
 *
 * ```ts
 * const proxy = createProxy(betterSupabase, { protect });
 * export default proxy;
 * ```
 */
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
  options: NextOptions & ProxyOptions<C, P> = {},
): (request: NextRequest) => Promise<Response> {
  const base = createServer(betterSupabase, options);

  const { collector, statsHeader, statsRoute, flushAfter } = proxyRuntime(
    betterSupabase,
    options,
  );

  const handle = proxyHandler<C, P>({
    base,
    logger: betterSupabase.events.logger,
    collector,
    statsHeader,
    statsRoute,
    flushAfter,
  });

  return (request) => handle(request, options);
}
