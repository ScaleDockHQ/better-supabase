"use client";

import {
  useEffect,
  useMemo,
  useRef,
  useState,
  useSyncExternalStore,
} from "react";

import type { DbError } from "../../core/errors.ts";
import type { Result } from "../../core/result.ts";
import type { RejectedChange, RejectedStore } from "../connector.ts";
import type { PowerSyncDatabaseLike } from "../executor.ts";

import { watch } from "../watch.ts";

export type { RejectedChange, RejectedStore } from "../connector.ts";

export interface UseWatchOptions<T> {
  readonly db: PowerSyncDatabaseLike;
  /** The repository call, e.g. `() => list.run(local, query)`. */
  readonly query: () => PromiseLike<Result<T>>;
  /** SQLite tables whose changes rerun the query (`sqliteTables()`). */
  readonly tables: readonly string[];
  /** Values the query reads; a change restarts the watch. */
  readonly deps?: readonly unknown[];
  readonly throttleMs?: number;
  /** False pauses the watch and keeps the last result. Defaults to true. */
  readonly enabled?: boolean;
}

export interface WatchState<T> {
  readonly result: Result<T> | undefined;
  readonly data: T | undefined;
  readonly error: DbError | undefined;
  /** No result yet for the current `deps`. */
  readonly loading: boolean;
}

/**
 * A live repository call over PowerSync's SQLite database: reruns when
 * one of `tables` changes, keeps unchanged rows' identity, and restarts
 * when `deps` change.
 *
 * ```tsx
 * const { data, loading } = useWatch({
 *   db: powersync,
 *   query: () => customerList.run(local, { ...customerList.defaults, search }),
 *   tables,
 *   deps: [search],
 * });
 * ```
 */
export function useWatch<T>(options: UseWatchOptions<T>): WatchState<T> {
  const { db, tables, throttleMs } = options;
  const enabled = options.enabled ?? true;
  const key = JSON.stringify([tables, options.deps ?? []]);
  const [state, setState] = useState<{
    readonly key: string;
    readonly result: Result<T> | undefined;
  }>({ key, result: undefined });
  const latest = useRef({ query: options.query, tables });
  // oxlint-disable-next-line react/refs -- latest-ref pattern; the react peer range predates useEffectEvent.
  latest.current = { query: options.query, tables };

  useEffect(() => {
    if (!enabled) return;
    // `key` covers the tables, so the ones read here match it.
    return watch(db, () => latest.current.query(), {
      tables: latest.current.tables,
      onResult: (result) => {
        setState({ key, result });
      },
      ...(throttleMs === undefined ? {} : { throttleMs }),
    });
  }, [db, key, enabled, throttleMs]);

  const result = state.result;
  return {
    result,
    data: result?.ok ? result.data : undefined,
    error: result && !result.ok ? result.error : undefined,
    loading: state.key !== key || result === undefined,
  };
}

/** The part of PowerSync's `SyncStatus` `useSyncStatus` reads. */
export interface SyncStatusLike {
  readonly connected: boolean;
  readonly connecting?: boolean;
  readonly hasSynced?: boolean | undefined;
  readonly dataFlowStatus: {
    readonly uploading: boolean;
    readonly downloading: boolean;
    readonly uploadError?: Error | undefined;
    readonly downloadError?: Error | undefined;
  };
}

/** The part of a PowerSync database `useSyncStatus` subscribes to. */
export interface SyncStatusSource {
  readonly currentStatus: SyncStatusLike;
  registerListener(listener: {
    statusChanged?: (status: SyncStatusLike) => void;
  }): () => void;
}

export interface SyncState {
  readonly connected: boolean;
  readonly connecting: boolean;
  /** The first full sync finished; before it, local reads may be empty. */
  readonly hasSynced: boolean;
  readonly uploading: boolean;
  readonly downloading: boolean;
  readonly error: Error | undefined;
}

function stateOf(status: SyncStatusLike): SyncState {
  const flow = status.dataFlowStatus;
  return {
    connected: status.connected,
    connecting: status.connecting ?? false,
    hasSynced: status.hasSynced ?? false,
    uploading: flow.uploading,
    downloading: flow.downloading,
    error: flow.uploadError ?? flow.downloadError,
  };
}

function sameState(a: SyncState, b: SyncState): boolean {
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
 * PowerSync's connection and sync progress, for a status badge or a
 * "syncing" banner. Re-renders only when one of the fields changes.
 */
export function useSyncStatus(db: SyncStatusSource): SyncState {
  const store = useMemo(() => statusStore(db), [db]);
  return useSyncExternalStore(store.subscribe, store.read, store.read);
}

/** Keeps the last snapshot while its fields stay equal, as `useSyncExternalStore` needs. */
function statusStore(db: SyncStatusSource) {
  let snapshot = stateOf(db.currentStatus);
  return {
    read: (): SyncState => {
      const next = stateOf(db.currentStatus);
      if (!sameState(snapshot, next)) snapshot = next;
      return snapshot;
    },
    subscribe: (listener: () => void) =>
      db.registerListener({ statusChanged: listener }),
  };
}

export interface Conflicts {
  /** Changes the server refused, oldest first. */
  readonly changes: readonly RejectedChange[];
  /** Forgets one change after the UI handled it, or all of them. */
  readonly dismiss: (change?: RejectedChange) => void;
}

/**
 * The changes `createUploadConnector` could not upload: conflicts with a
 * newer server row and changes the server refused. Show them next to the
 * row, then `dismiss` them.
 */
export function useConflicts(connector: {
  readonly rejected: RejectedStore;
}): Conflicts {
  const { rejected } = connector;
  const changes = useSyncExternalStore(
    rejected.subscribe,
    rejected.current,
    rejected.current,
  );
  return { changes, dismiss: rejected.dismiss };
}
