import type { DbError, DbErrorKind } from "../core/errors.ts";
import type { Result } from "../core/result.ts";

import { dbError } from "../core/errors.ts";
import { err } from "../core/result.ts";

/** A queued local change: PowerSync's `CrudEntry`. */
export interface CrudEntryLike {
  /** `PUT`, `PATCH` or `DELETE` (PowerSync's `UpdateType`). */
  readonly op: string;
  readonly table: string;
  readonly id: string;
  readonly opData?: Readonly<Record<string, unknown>> | undefined;
}

/** The part of a PowerSync database the connector reads the queue from. */
export interface CrudQueueLike {
  getCrudBatch(limit?: number): Promise<{
    readonly crud: readonly CrudEntryLike[];
    complete(): Promise<void>;
  } | null>;
}

/**
 * A repository a table's changes replay through (`bs.db.customers`), so
 * RLS, plugins and validation run as they do online.
 */
export interface UploadRepository {
  upsert(data: never): PromiseLike<Result<unknown>>;
  update(id: never, patch: never): PromiseLike<Result<unknown>>;
  delete(id: never): PromiseLike<Result<unknown>>;
}

/** A table's route: its repository, or a function for custom replay. */
export type UploadRoute =
  | UploadRepository
  | ((entry: CrudEntryLike) => PromiseLike<Result<unknown>>);

/** What an upload error means for the queued change. */
export type UploadOutcome = "retry" | "conflict" | "discard";

/** A change the server refused, kept for the UI. */
export interface RejectedChange {
  readonly entry: CrudEntryLike;
  readonly error: DbError;
  readonly outcome: "conflict" | "discard";
}

/** A `useSyncExternalStore`-compatible list of refused changes. */
export interface RejectedStore {
  readonly current: () => readonly RejectedChange[];
  readonly subscribe: (listener: () => void) => () => void;
  /** Forgets one change, or all of them. */
  readonly dismiss: (change?: RejectedChange) => void;
}

interface SessionClient {
  readonly auth: {
    getSession(): Promise<{
      readonly data: {
        readonly session: {
          readonly access_token: string;
          readonly expires_at?: number | undefined;
        } | null;
      };
    }>;
  };
}

export interface UploadConnectorOptions {
  /** The PowerSync service URL. */
  readonly endpoint: string;
  /** The supabase-js client whose session authenticates sync and uploads. */
  readonly supabase: SessionClient;
  /** Every synced table that takes local writes, by its SQLite name. */
  readonly tables: Readonly<Record<string, UploadRoute>>;
  /** Changes per upload batch. Defaults to 100. */
  readonly batchSize?: number;
  /** Overrides `uploadOutcome` for some errors. */
  readonly classify?: (
    error: DbError,
    entry: CrudEntryLike,
  ) => UploadOutcome | undefined;
  readonly onConflict?: (change: RejectedChange) => void;
  readonly onDiscard?: (change: RejectedChange) => void;
}

/** PowerSync's `PowerSyncBackendConnector`. */
export interface UploadConnector {
  fetchCredentials(): Promise<{
    readonly endpoint: string;
    readonly token: string;
    readonly expiresAt?: Date;
  } | null>;
  uploadData(database: CrudQueueLike): Promise<void>;
  /** Changes the server refused since the app started. */
  readonly rejected: RejectedStore;
}

const OUTCOMES: { readonly [K in DbErrorKind]: UploadOutcome } = {
  network: "retry",
  timeout: "retry",
  aborted: "retry",
  rate_limited: "retry",
  quota_exceeded: "retry",
  serialization: "retry",
  unauthorized: "retry",
  unexpected: "retry",
  conflict: "conflict",
  stale: "conflict",
  foreign_key: "conflict",
  not_found: "discard",
  forbidden: "discard",
  check: "discard",
  not_null: "discard",
  exclusion: "discard",
  invalid_input: "discard",
  invalid_value: "discard",
  raised: "discard",
  invalid_request: "discard",
  max_affected: "discard",
  validation: "discard",
  multiple_rows: "discard",
  unsupported: "discard",
};

/**
 * The default for a failed upload: transient errors retry, a newer server
 * row is a conflict, and a change the server will never accept is
 * discarded so it doesn't block the queue.
 */
export function uploadOutcome(kind: DbErrorKind): UploadOutcome {
  return OUTCOMES[kind];
}

function rejectedStore(): RejectedStore & {
  add(change: RejectedChange): void;
} {
  let changes: readonly RejectedChange[] = [];
  const listeners = new Set<() => void>();
  const set = (next: readonly RejectedChange[]) => {
    changes = next;
    for (const listener of [...listeners]) listener();
  };
  return {
    current: () => changes,
    subscribe: (listener) => {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    dismiss: (change) => {
      set(change ? changes.filter((each) => each !== change) : []);
    },
    add: (change) => {
      set([...changes, change]);
    },
  };
}

function replay(
  route: UploadRoute,
  entry: CrudEntryLike,
): PromiseLike<Result<unknown>> {
  if (typeof route === "function") return route(entry);
  const data = entry.opData ?? {};
  switch (entry.op) {
    case "PUT":
      // SAFETY: PowerSync recorded these columns from a write to the local
      // table, whose columns mirror the repository's table.
      return route.upsert({ ...data, id: entry.id } as never);
    case "PATCH":
      // SAFETY: as above; the id is the row's text primary key.
      return route.update(entry.id as never, data as never);
    case "DELETE":
      // SAFETY: as above.
      return route.delete(entry.id as never);
    default:
      return Promise.resolve(
        err(
          dbError(
            "unsupported",
            `better-supabase: unknown PowerSync op ${entry.op}`,
          ),
        ),
      );
  }
}

/**
 * A PowerSync connector that authenticates with the Supabase session and
 * replays queued changes through repositories. Changes upload in batches;
 * a transient error keeps the batch queued for PowerSync's retry, and
 * refused changes land in `rejected` instead of blocking the queue. A table
 * without a route stops the upload with an error, so no change is dropped
 * silently. When the session is gone (the refresh token was revoked), the
 * upload stops until the user signs in again.
 *
 * ```ts
 * const connector = createUploadConnector({
 *   endpoint: process.env.EXPO_PUBLIC_POWERSYNC_URL,
 *   supabase,
 *   tables: { customers: bs.db.customers },
 * });
 * await powersync.connect(connector);
 * ```
 */
export function createUploadConnector(
  options: UploadConnectorOptions,
): UploadConnector {
  const rejected = rejectedStore();
  const batchSize = options.batchSize ?? 100;
  const signedIn = async (): Promise<boolean> => {
    const { data } = await options.supabase.auth.getSession();
    return data.session !== null;
  };
  return {
    rejected,
    async fetchCredentials() {
      const { data } = await options.supabase.auth.getSession();
      const session = data.session;
      if (!session) return null;
      return {
        endpoint: options.endpoint,
        token: session.access_token,
        ...(session.expires_at === undefined
          ? {}
          : { expiresAt: new Date(session.expires_at * 1000) }),
      };
    },
    async uploadData(database) {
      const batch = await database.getCrudBatch(batchSize);
      if (!batch) return;
      for (const entry of batch.crud) {
        const route = options.tables[entry.table];
        if (!route) {
          throw new Error(
            `better-supabase: no upload route for PowerSync table "${entry.table}"; add it to createUploadConnector({ tables })`,
          );
        }
        const result = await replay(route, entry);
        if (result.ok) continue;
        const { error } = result;
        const outcome =
          options.classify?.(error, entry) ?? uploadOutcome(error.kind);
        switch (outcome) {
          case "retry":
            if (error.kind === "unauthorized" && !(await signedIn())) return;
            // PowerSync keeps the batch queued and calls uploadData again.
            throw new Error(error.message);
          case "conflict": {
            const change: RejectedChange = { entry, error, outcome };
            rejected.add(change);
            options.onConflict?.(change);
            break;
          }
          case "discard": {
            const change: RejectedChange = { entry, error, outcome };
            rejected.add(change);
            options.onDiscard?.(change);
            break;
          }
          default: {
            const unhandled: never = outcome;
            throw new TypeError(
              `Unhandled upload outcome ${String(unhandled)}`,
            );
          }
        }
      }
      await batch.complete();
    },
  };
}
