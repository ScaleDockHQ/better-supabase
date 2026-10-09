import type { AnyEntry, Contributions } from "@supabase/middleware";

import type { Validated } from "../../bridges/shared.ts";
import type { RouteGuardOptions } from "../../server/refusal.ts";

import { beforeRoute } from "../../bridges/before-route.ts";
import {
  applyWebHeaders,
  headRequest,
  type NodeHeaderTarget,
  type NodeRequestHead,
} from "../../bridges/node-headers.ts";
import {
  errorResponse,
  guardedLocals,
  routeRefusal,
} from "../../server/refusal.ts";

export type { RouteGuardOptions } from "../../server/refusal.ts";

/** The part of an H3 1 event (Nitro 2, Nuxt 3 and 4) the bridge reads and writes. */
export interface H3V1Event<Context extends object = Record<string, unknown>> {
  readonly node: {
    readonly req: NodeRequestHead;
    readonly res: NodeHeaderTarget;
  };
  readonly context: Context & {
    /** Nitro's Cloudflare presets put the bindings here. */
    readonly cloudflare?: { readonly env?: unknown } | undefined;
  };
}

export interface ToH3V1Options<Context extends object> {
  /** The host's env object for `getEnv`; defaults to `event.context.cloudflare.env`. */
  readonly env?: (event: H3V1Event<Context>) => unknown;
  /** Read the protocol and host from `x-forwarded-*`. Defaults to false. */
  readonly trustProxy?: boolean;
}

/**
 * An H3 1 handler, typed structurally so the package does not import `h3`.
 * It returns a `Response` to end the request or `undefined` to continue.
 */
export type H3V1Handler<Context extends object> = (
  event: H3V1Event<Context>,
) => Promise<Response | undefined>;

/**
 * Runs an entry array as Nitro 2 server middleware. A short circuit (a 401,
 * a CORS preflight) ends the request; otherwise the entries' cookies and
 * headers go on the response and every contribution lands on
 * `event.context`. Response-phase entries (`withDbStats`) see an empty
 * response under H3 1.
 *
 * ```ts title="server/middleware/supabase.ts"
 * export default defineEventHandler(toH3V1([withBetterSupabase(server)]))
 * ```
 */
export function toH3V1<const Entries extends readonly AnyEntry[]>(
  entries: Entries & Validated<Entries>,
  options: ToH3V1Options<Partial<Contributions<Entries>>> = {},
): H3V1Handler<Partial<Contributions<Entries>>> {
  const run = beforeRoute(entries);
  return async (event) => {
    const env = options.env
      ? options.env(event)
      : event.context.cloudflare?.env;
    const outcome = await run(
      headRequest(event.node.req, options.trustProxy),
      env,
    );
    if (!outcome.reached) return outcome.response;
    applyWebHeaders(event.node.res, outcome.headers);
    Object.assign(event.context, outcome.contributions);
    return;
  };
}

/**
 * Refuses callers outside `options`: Problem Details, or a redirect to
 * `signIn` or `mfa`. Returns `undefined` for callers it lets through, so a
 * route handler can return its result.
 *
 * ```ts title="server/api/admin.get.ts"
 * const admins = guard({ roles: ['admin'] })
 * export default defineEventHandler(async (event) =>
 *   (await admins(event)) ?? event.context.db.members.findMany().orThrow())
 * ```
 */
export function guard(
  options: RouteGuardOptions = {},
): (event: H3V1Event<object>) => Promise<Response | undefined> {
  return (event) =>
    routeRefusal(
      guardedLocals(event.context),
      headRequest(event.node.req),
      options,
    );
}

/**
 * Answers thrown `DbException`s (from `.orThrow()`) with Problem Details
 * and returns `undefined` for every other error, for a Nitro `error` hook
 * or a handler's `catch`.
 */
export function problemOnError(
  options: { readonly expose?: boolean } = {},
): (error: unknown, event: H3V1Event<object>) => Response | undefined {
  return (error, event) =>
    errorResponse(error, headRequest(event.node.req), options);
}
