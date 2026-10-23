import type {
  DataChanges,
  DataEngine,
  LiveEngineOptions,
  LocalTablesOption,
} from "../bindings/data-engine.ts";
import type { Executor } from "../core/executor.ts";
import type { RejectedStore } from "./connector.ts";
import type {
  PowerSyncDatabaseLike,
  PowerSyncExecutorOptions,
} from "./executor.ts";

import { localEngine } from "../bindings/data-engine.ts";
import { powersyncExecutor } from "./executor.ts";
import { powersyncSync } from "./sync.ts";

export interface PowerSyncEngineOptions
  extends
    Omit<PowerSyncExecutorOptions, "fallback">,
    LiveEngineOptions,
    LocalTablesOption {
  /**
   * Where reads are kept: `queryEngine(queryClient)` to share them with
   * TanStack Query. Default one in memory.
   */
  readonly cache?: DataEngine;
  /**
   * `createUploadConnector(...)`: `useConflicts()` reads the changes it could
   * not upload.
   */
  readonly connector?: { readonly rejected: RejectedStore };
  /** The least time between two reads after local changes. Default 30 ms. */
  readonly throttleMs?: number;
  /**
   * Reads that SQLite can't run and `db.$rpc` go to the server: the client's
   * PostgREST executor unless `fallback` names another. `false` keeps every
   * call local.
   */
  readonly fallback?: Executor | false;
}

/**
 * The data hooks and `db` on PowerSync's local SQLite database: reads and
 * writes run offline, synced rows and local writes refresh every hook that
 * follows their table, and `useSyncStatus()` and `useConflicts()` follow the
 * sync. Reads SQLite can't run go to the server, and are read again when
 * PowerSync connects again.
 *
 * ```ts
 * export const bsb = createNativeClient(betterSupabase, supabase, {
 *   engine: powersyncEngine(powersync, { connector }),
 * });
 * ```
 */
export function powersyncEngine(
  database: PowerSyncDatabaseLike,
  options: PowerSyncEngineOptions = {},
): DataEngine {
  const { cache, connector, throttleMs, tables, local, fallback, ...executor } =
    options;

  const changes: DataChanges | undefined =
    database.onChange === undefined
      ? undefined
      : {
          subscribe: (onChange) => {
            const unsubscribe = database.onChange?.(
              {
                onChange: (event) => {
                  onChange(event.changedTables);
                },
              },
              throttleMs === undefined ? {} : { throttleMs },
            );

            const unlisten = onReconnect(database, () => {
              engine.invalidate(["bsb"]);
            });

            return () => {
              unsubscribe?.();
              unlisten();
            };
          },
        };

  const { currentStatus } = database;
  const listens = database.registerListener !== undefined;

  const engine = localEngine({
    cache,
    changes,
    ...(tables === undefined ? {} : { tables }),
    ...(local === undefined ? {} : { local }),
    connect: (server) =>
      powersyncExecutor(database, {
        ...executor,
        ...(fallback === false ? {} : { fallback: fallback ?? server }),
      }),
    sync:
      currentStatus === undefined || !listens
        ? undefined
        : powersyncSync(
            {
              get currentStatus() {
                return database.currentStatus ?? currentStatus;
              },
              registerListener: (listener) =>
                database.registerListener?.(listener) ?? (() => undefined),
            },
            connector?.rejected,
          ),
  });

  return engine;
}

/** Calls `listener` each time PowerSync connects after it was offline. */
function onReconnect(
  database: PowerSyncDatabaseLike,
  listener: () => void,
): () => void {
  if (database.registerListener === undefined) {
    return () => undefined;
  }

  let connected = database.currentStatus?.connected ?? false;

  return database.registerListener({
    statusChanged: (status) => {
      if (status.connected && !connected) {
        listener();
      }

      connected = status.connected;
    },
  });
}
