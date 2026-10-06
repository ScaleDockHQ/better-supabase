import type { AnyEntry, Contributions } from "@supabase/middleware";

import { around, bufferInPlace, type Validated } from "./shared.ts";

/** The part of React Router's `RouterContextProvider` the bridge writes. */
export interface ReactRouterContext<Key, Value> {
  set(key: Key, value: Value): void;
}

/** React Router's server middleware, typed structurally so the package does not import `react-router`. */
export type ReactRouterMiddleware<Key, Value> = (
  args: {
    readonly request: Request;
    readonly context: ReactRouterContext<Key, Value>;
  },
  next: () => Promise<Response>,
) => Promise<Response>;

/**
 * Runs an entry array as React Router server middleware. The contributions
 * are set under `key` (a `createContext()` key), so loaders and actions
 * read `context.get(key).db`.
 *
 * ```ts title="app/root.tsx"
 * export const supabase = createContext<BetterSupabaseContributions<...>>()
 * export const middleware = [toReactRouter([withBetterSupabase(server)], supabase)]
 * ```
 */
export function toReactRouter<const Entries extends readonly AnyEntry[], Key>(
  entries: Entries & Validated<Entries>,
  key: Key,
): ReactRouterMiddleware<Key, Contributions<Entries>> {
  const run = around(entries);
  return ({ request, context }, next) => {
    bufferInPlace(request);
    return run(request, undefined, async (contributions) => {
      // SAFETY: around() hands over exactly the entries' contributions.
      context.set(key, contributions as Contributions<Entries>);
      return next();
    });
  };
}
