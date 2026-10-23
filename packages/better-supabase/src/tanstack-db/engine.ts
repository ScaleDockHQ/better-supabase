import type { DataChanges, DataEngine } from "../bindings/data-engine.ts";

import { liveEngine, memoryEngine } from "../bindings/data-engine.ts";

/**
 * The part of a TanStack DB collection the engine uses. Typed by shape, so
 * better-supabase doesn't depend on TanStack DB.
 */
export interface CollectionLike {
  subscribeChanges(callback: (changes: readonly unknown[]) => void): {
    unsubscribe(): void;
  };
  /** A query collection's `utils`: the engine refetches it after writes. */
  readonly utils?: { readonly refetch?: () => unknown };
}

type Collections = Readonly<Record<string, CollectionLike>>;

export interface TanstackDbEngineOptions {
  /**
   * The collections that hold each source's rows, by source name: `{ customers:
   * customersCollection }`. Pass a function when the collections are built on
   * the client this engine goes into; the engine calls it when a hook first
   * follows a read.
   */
  readonly collections: Collections | (() => Collections);
  /**
   * Where reads are kept: `queryEngine(queryClient)` to share them with
   * TanStack Query. Default one in memory.
   */
  readonly cache?: DataEngine;
}

/**
 * The data hooks next to TanStack DB collections: a change to a collection (an
 * optimistic write, a sync, another client's row) reads every hook that follows
 * the same source again, and a hook's write refetches the source's query
 * collection, so live queries and hooks show the same rows.
 *
 * ```ts
 * export const bsb = createClient(betterSupabase, {
 *   engine: tanstackDbEngine({ collections: { customers } }),
 * });
 * ```
 */
export function tanstackDbEngine(options: TanstackDbEngineOptions): DataEngine {
  const collections = (): Collections =>
    typeof options.collections === "function"
      ? options.collections()
      : options.collections;

  const changes: DataChanges = {
    subscribe: (onChange) => {
      const subscriptions = Object.entries(collections()).map(
        ([name, collection]) =>
          collection.subscribeChanges((messages) => {
            if (messages.length > 0) {
              onChange([name]);
            }
          }),
      );

      return () => {
        for (const subscription of subscriptions) {
          subscription.unsubscribe();
        }
      };
    },
  };

  const engine = liveEngine(options.cache ?? memoryEngine(), changes);

  const refetch = (name: string): void => {
    void collections()[name]?.utils?.refetch?.();
  };

  return {
    ...engine,
    invalidate: (prefix) => {
      engine.invalidate(prefix);
      const name = prefix[1];

      if (typeof name === "string") {
        refetch(name);

        return;
      }

      if (prefix.length <= 1) {
        for (const key of Object.keys(collections())) {
          refetch(key);
        }
      }
    },
  };
}
