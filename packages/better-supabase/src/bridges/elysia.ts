import {
  type AnyEntry,
  bufferRequest,
  type Contributions,
} from "@supabase/middleware";

import { around, type Validated } from "./shared.ts";

export interface ElysiaBridge<Entries extends readonly AnyEntry[]> {
  /**
   * Runs the entries around the app's fetch (`app.handle`), so short
   * circuits answer before Elysia routes and the route's response passes
   * back through the entries.
   */
  wrap(
    handle: (request: Request) => Promise<Response>,
  ): (request: Request) => Promise<Response>;
  /**
   * The contributions for a request `wrap` is serving. Throws for any other
   * request, so a route reached without the entries fails closed.
   * Expose it with `.derive(({ request }) => bridge.context(request))`.
   */
  context(request: Request): Contributions<Entries>;
}

/**
 * Runs an entry array around an Elysia app. Elysia has no middleware slot
 * that sees the response it produces, so the bridge wraps the app's fetch
 * and hands the contributions to routes through `context(request)`.
 *
 * ```ts
 * const bridge = toElysia([withBetterSupabase(server)])
 * const app = new Elysia().derive(({ request }) => bridge.context(request)).get('/notes', ({ db }) => ...)
 * export default { fetch: bridge.wrap((request) => app.handle(request)) }
 * ```
 */
export function toElysia<const Entries extends readonly AnyEntry[]>(
  entries: Entries & Validated<Entries>,
): ElysiaBridge<Entries> {
  const run = around(entries);
  const contexts = new WeakMap<Request, Contributions<Entries>>();
  return {
    wrap: (handle) => (incoming) => {
      const request = incoming.body ? bufferRequest(incoming) : incoming;
      return run(request, undefined, (contributions) => {
        // SAFETY: around() hands over exactly the entries' contributions.
        contexts.set(request, contributions as Contributions<Entries>);
        return handle(request);
      });
    },
    context(request) {
      const contributions = contexts.get(request);
      if (!contributions) {
        throw new Error(
          "better-supabase: this request did not pass through toElysia().wrap(); serve the app with the wrapped fetch",
        );
      }
      return contributions;
    },
  };
}
