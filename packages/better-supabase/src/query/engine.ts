import type { QueryClient } from "@tanstack/query-core";

import { QueryObserver } from "@tanstack/query-core";

import type {
  DataEngine,
  DataEngineOptions,
  DataEntry,
  DataKey,
} from "../bindings/data-engine.ts";

import { liveEngine, loadError } from "../bindings/data-engine.ts";

const IDLE: DataEntry = { status: "idle", data: undefined, error: undefined };

/**
 * The data hooks' engine on TanStack Query: their reads live in `queryClient`
 * under `["bsb", <instance or table>, ...]`, so devtools, `staleTime` and
 * `invalidateQueries` see them. `live` reads followed sources again when their
 * tables change elsewhere.
 *
 * ```ts
 * export const bsb = createClient(betterSupabase, {
 *   engine: queryEngine(queryClient),
 * });
 * ```
 */
export function queryEngine(
  queryClient: QueryClient,
  options: DataEngineOptions = {},
): DataEngine {
  const entries = new Map<string, DataEntry>();

  queryClient.getQueryCache().subscribe((event) => {
    if (event.type === "removed") {
      entries.delete(event.query.queryHash);
    }
  });

  const entryOf = (key: DataKey): DataEntry => {
    const query = queryClient
      .getQueryCache()
      .find({ queryKey: key, exact: true });

    if (query === undefined) {
      return IDLE;
    }

    const { status, fetchStatus, data, error } = query.state;

    const next: DataEntry = {
      status:
        fetchStatus === "fetching"
          ? "loading"
          : status === "pending"
            ? "idle"
            : status,
      data,
      error: error === null ? undefined : loadError(error),
    };

    const held = entries.get(query.queryHash);

    if (
      held !== undefined &&
      held.status === next.status &&
      Object.is(held.data, next.data) &&
      Object.is(held.error?.message, next.error?.message)
    ) {
      return held;
    }

    entries.set(query.queryHash, next);

    return next;
  };

  const engine: DataEngine = {
    apiVersion: 1,
    watch: (key, load, listener) => {
      const observer = new QueryObserver(queryClient, {
        queryKey: key,
        queryFn: load,
        retry: false,
      });

      return observer.subscribe(() => {
        listener();
      });
    },
    entry: entryOf,
    refetch: (key) => {
      void queryClient.refetchQueries({ queryKey: key, exact: true });
    },
    rewrite: (prefix, update) => {
      const previous = queryClient.getQueriesData({ queryKey: prefix });

      for (const [key, data] of previous) {
        if (data !== undefined) {
          queryClient.setQueryData(key, update(data));
        }
      }

      return () => {
        for (const [key, data] of previous) {
          queryClient.setQueryData(key, data);
        }
      };
    },
    invalidate: (prefix) => {
      void queryClient.invalidateQueries({ queryKey: prefix });
    },
  };

  return liveEngine(engine, options.live, options);
}
