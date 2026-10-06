import type { AnyEntry, Contributions } from "@supabase/middleware";

import { around, bufferInPlace, type Validated } from "./shared.ts";

/** The part of SvelteKit's `RequestEvent` the bridge reads and writes. */
export interface SvelteKitEvent<Locals extends object> {
  readonly request: Request;
  readonly locals: Locals;
  readonly platform?: { readonly env?: unknown } | undefined;
}

/** SvelteKit's `Handle`, typed structurally so the package does not import `@sveltejs/kit`. */
export type SvelteKitHandle<Locals extends object> = (input: {
  readonly event: SvelteKitEvent<Locals>;
  readonly resolve: (
    event: SvelteKitEvent<Locals>,
  ) => Response | Promise<Response>;
}) => Promise<Response>;

/**
 * Runs an entry array as a SvelteKit `handle` hook. Every contributed key
 * lands on `event.locals`, so loads, actions and endpoints read
 * `locals.db`; `event.platform.env` (Cloudflare) seeds `getEnv`. Declare
 * the keys in `App.Locals` with `BetterSupabaseContributions`.
 *
 * ```ts title="src/hooks.server.ts"
 * export const handle = toSvelteKit([withBetterSupabase(server)])
 * ```
 *
 * Compose it with other hooks through SvelteKit's `sequence`.
 */
export function toSvelteKit<const Entries extends readonly AnyEntry[]>(
  entries: Entries & Validated<Entries>,
): SvelteKitHandle<Partial<Contributions<Entries>>> {
  const run = around(entries);
  return ({ event, resolve }) => {
    bufferInPlace(event.request);
    return run(event.request, event.platform?.env, async (contributions) => {
      Object.assign(event.locals, contributions);
      return resolve(event);
    });
  };
}
