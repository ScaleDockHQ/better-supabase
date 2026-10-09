import type { AnyEntry, Contributions } from "@supabase/middleware";

import { around, bufferInPlace, toResponse, type Validated } from "./shared.ts";

/** The part of an H3 2 event the bridge reads and writes. */
export interface H3Event<Context extends object> {
  readonly req: Request;
  readonly context: Context & {
    /** Nitro's Cloudflare presets put the bindings here. */
    readonly cloudflare?: { readonly env?: unknown } | undefined;
  };
  /** The status and headers a handler set with `event.res`, kept on a plain return value. */
  readonly res?:
    | {
        readonly status?: number | undefined;
        readonly statusText?: string | undefined;
        readonly headers?: Headers | undefined;
      }
    | undefined;
}

export interface ToH3Options<Context extends object> {
  /** The host's env object for `getEnv`; defaults to `event.context.cloudflare.env`. */
  readonly env?: (event: H3Event<Context>) => unknown;
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
  options: ToH3Options<Partial<Contributions<Entries>>> = {},
): H3Middleware<Partial<Contributions<Entries>>> {
  const run = around(entries);
  return (event, next) => {
    bufferInPlace(event.req);
    const env = options.env
      ? options.env(event)
      : event.context.cloudflare?.env;
    return run(event.req, env, async (contributions) => {
      Object.assign(event.context, contributions);
      const value = await next();
      return toResponse(value, {
        status: event.res?.status,
        statusText: event.res?.statusText,
        headers: event.res?.headers,
      });
    });
  };
}
