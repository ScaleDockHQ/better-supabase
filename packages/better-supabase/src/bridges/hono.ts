import type { Context, MiddlewareHandler, Next } from "hono";

import {
  type AnyEntry,
  bufferRequest,
  type Contributions,
  pipeline,
  seedContext,
  type ValidateEntries,
} from "@supabase/middleware";

import { handoffOf } from "./shared.ts";

/**
 * The Hono middleware type when the entries compose, or the engine's error
 * string when they don't, which surfaces at the `app.use` call.
 */
export type HonoBridge<Entries extends readonly AnyEntry[]> = [
  ValidateEntries<Entries>,
] extends [true]
  ? MiddlewareHandler<{ Variables: Contributions<Entries> }>
  : ValidateEntries<Entries>;

const HANDOFF = Symbol("toHono.handoff");

interface Handoff {
  readonly c: Context;
  readonly next: Next;
  readonly publish: (c: Context, ctx: object) => void;
}

/** Copies every contributed key onto `c.var`. */
function publishAll(c: Context, ctx: object): void {
  for (const [key, value] of Object.entries(ctx)) {
    // SAFETY: Hono's `set` is keyed by the app's Variables; the bridge's type
    // publishes exactly the contributed keys, so every key here is one of them.
    c.set(key as never, value);
  }
}

/**
 * The Hono middleware for `entries`. `publish` decides what lands on
 * `c.var`; `createHono` adds `auth` from `ctx.bs`.
 */
export function honoMiddleware(
  entries: readonly AnyEntry[],
  publish: (c: Context, ctx: object) => void = publishAll,
): MiddlewareHandler {
  const run = pipeline(entries, async (_request, ctx) => {
    const handoff = handoffOf<Handoff>(ctx, HANDOFF);
    handoff.publish(handoff.c, ctx);
    await handoff.next();
    return handoff.c.res;
  });
  return async (c, next) => {
    // A bridge that seeds the context buffers the body itself, and puts the
    // buffered request on Hono's so an entry and the route read one cache.
    if (c.req.raw.body) c.req.raw = bufferRequest(c.req.raw);
    // `c.env` holds the bindings on Workers, which is how `getEnv` reads them there.
    const response = await run(c.req.raw, {
      ...seedContext(c.env),
      [HANDOFF]: { c, next, publish } satisfies Handoff,
    });
    if (response !== c.res) {
      // Hono's `res` setter merges the previous response's headers into the
      // new one, which would undo headers the response phase rewrote.
      c.res = undefined;
      c.res = response;
    }
  };
}

/**
 * Runs an entry array in Hono's middleware slot. The pipeline folds once,
 * so entries keep their state across requests; each request publishes every
 * contributed key on `c.var`, runs the rest of the Hono chain, and returns
 * Hono's response back up through the entries, so response-phase entries
 * (refreshed cookies, `withCors`) see it.
 *
 * ```ts
 * const app = new Hono().use(toHono([withBetterSupabase(server)])).get('/notes', (c) => ...)
 * ```
 *
 * Chain `.use()` into the routes it gates: Hono carries the contributed
 * keys through the chained call's type.
 */
export function toHono<const Entries extends readonly AnyEntry[]>(
  entries: Entries,
): HonoBridge<Entries> {
  // SAFETY: HonoBridge is the middleware type exactly when the entries
  // validate; otherwise it is the error string the caller has to fix first.
  return honoMiddleware(entries) as HonoBridge<Entries>;
}
