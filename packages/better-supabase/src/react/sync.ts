import { useContext, useSyncExternalStore } from "react";

import type { DataSyncState } from "../bindings/data-engine.ts";
import type { RejectedChange } from "../powersync/connector.ts";

import { ClientContext } from "./context.ts";

const NO_CHANGES: readonly RejectedChange[] = [];

const none = (): readonly RejectedChange[] => NO_CHANGES;

const noSubscription = (): (() => void) => () => undefined;

const noState = (): undefined => undefined;

function useSync() {
  return useContext(ClientContext)?.client.engine?.sync;
}

/**
 * The local database's connection and sync progress, for a status badge or a
 * "syncing" banner. `undefined` when the provider's engine syncs nothing (the
 * hooks read the server). Re-renders only when a field changes.
 */
export function useSyncStatus(): DataSyncState | undefined {
  const sync = useSync();

  return useSyncExternalStore(
    sync?.subscribe ?? noSubscription,
    sync?.current ?? noState,
    sync?.current ?? noState,
  );
}

export interface Conflicts {
  /** Changes the server refused, oldest first. */
  readonly changes: readonly RejectedChange[];
  /** Forgets one change after the UI handled it, or all of them. */
  readonly dismiss: (change?: RejectedChange) => void;
}

const ignore = (): void => undefined;

/**
 * The changes the engine's upload connector could not upload: conflicts with a
 * newer server row and changes the server refused. Show them next to the row,
 * then `dismiss` them.
 */
export function useConflicts(): Conflicts {
  const conflicts = useSync()?.conflicts;

  const changes = useSyncExternalStore(
    conflicts?.subscribe ?? noSubscription,
    conflicts?.current ?? none,
    conflicts?.current ?? none,
  );

  return { changes, dismiss: conflicts?.dismiss ?? ignore };
}
