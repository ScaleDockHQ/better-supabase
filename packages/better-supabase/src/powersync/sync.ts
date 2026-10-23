import type { DataSync, DataSyncState } from "../bindings/data-engine.ts";
import type { RejectedStore } from "./connector.ts";

/** The part of PowerSync's `SyncStatus` the engine reads. */
export interface SyncStatusLike {
  readonly connected: boolean;
  readonly connecting?: boolean;
  readonly hasSynced?: boolean | undefined;
  readonly dataFlowStatus?: {
    readonly uploading: boolean;
    readonly downloading: boolean;
    readonly uploadError?: Error | undefined;
    readonly downloadError?: Error | undefined;
  };
}

/** The part of a PowerSync database the engine's sync status follows. */
export interface SyncStatusSource {
  readonly currentStatus: SyncStatusLike;
  registerListener(listener: {
    statusChanged?: (status: SyncStatusLike) => void;
  }): () => void;
}

function stateOf(status: SyncStatusLike): DataSyncState {
  const flow = status.dataFlowStatus;

  return {
    connected: status.connected,
    connecting: status.connecting ?? false,
    hasSynced: status.hasSynced ?? false,
    uploading: flow?.uploading ?? false,
    downloading: flow?.downloading ?? false,
    error: flow?.uploadError ?? flow?.downloadError,
  };
}

function sameState(a: DataSyncState, b: DataSyncState): boolean {
  return (
    a.connected === b.connected &&
    a.connecting === b.connecting &&
    a.hasSynced === b.hasSynced &&
    a.uploading === b.uploading &&
    a.downloading === b.downloading &&
    a.error === b.error
  );
}

/**
 * The engine's sync status over PowerSync's: the same snapshot while its fields
 * stay equal, as `useSyncExternalStore` needs.
 */
export function powersyncSync(
  database: SyncStatusSource,
  conflicts?: RejectedStore,
): DataSync {
  let snapshot = stateOf(database.currentStatus);

  return {
    current: () => {
      const next = stateOf(database.currentStatus);

      if (!sameState(snapshot, next)) {
        snapshot = next;
      }

      return snapshot;
    },
    subscribe: (listener) =>
      database.registerListener({ statusChanged: listener }),
    ...(conflicts === undefined ? {} : { conflicts }),
  };
}
