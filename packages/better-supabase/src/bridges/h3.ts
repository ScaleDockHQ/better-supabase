import type { AnyEntry, Contributions } from "@supabase/middleware";

import { around, bufferInPlace, toResponse, type Validated } from "./shared.ts";

/** The part of an H3 2 event the bridge reads and writes. */
export interface H3Event<Context extends object> {
  readonly req: Request;
  readonly context: Context;
}

/** H3 2 middleware, typed structurally so the package does not import `h3`. */
export type H3Middleware<Context extends object> = (
  event: H3Event<Context>,
  next: () => unknown,
) => Promise<Response>;

/**
 * Runs an entry array as H3 2 middleware (`app.use(...)`, Nitro and Nuxt
 * server middleware). Every contributed key lands on `event.context`, and
 * the handler's value comes back as a `Response` (JSON for plain values)
 * so response-phase entries can add headers and cookies.
 *
 * ```ts
 * app.use(toH3([withBetterSupabase(server)]))
 * app.get('/notes', (event) => event.context.db.notes.findMany().orThrow())
 * ```
 */
export function toH3<const Entries extends readonly AnyEntry[]>(
  entries: Entries & Validated<Entries>,
): H3Middleware<Partial<Contributions<Entries>>> {
  const run = around(entries);
  return (event, next) => {
    bufferInPlace(event.req);
    return run(event.req, undefined, async (contributions) => {
      Object.assign(event.context, contributions);
      return toResponse(await next());
    });
  };
}
