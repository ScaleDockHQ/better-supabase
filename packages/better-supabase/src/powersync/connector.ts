import type { DbError, DbErrorKind } from "../core/errors.ts";
import type { Result } from "../core/result.ts";

import { dbError } from "../core/errors.ts";
import { err, ok } from "../core/result.ts";

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
  getCrudBatch(
    limit?: number,
  ): Promise<{
    readonly crud: readonly CrudEntryLike[];
    complete(): Promise<void>;
  } | null>;
}

/**
 * A repository a table's changes replay through (`bsb.db.customers`), so RLS,
 * plugins and validation run as they do online. `I` is the table's insert type
 * and `K` its primary key; every generated repository fits.
 */
export interface UploadRepository<I = Record<string, unknown>, K = string> {
  upsert(data: I): PromiseLike<Result<unknown>>;
  update(id: K, patch: Partial<I>): PromiseLike<Result<unknown>>;
  delete(id: K): PromiseLike<Result<unknown>>;
}

/**
 * A repository for a table whose rows are written once (attachments, events): a
 * `PUT` inserts with `create`, and a `DELETE` calls `delete`.
 */
export interface CreateUploadRepository<
  I = Record<string, unknown>,
  K = string,
> {
  create(data: I): PromiseLike<Result<unknown>>;
  delete(id: K): PromiseLike<Result<unknown>>;
}

/** Replays one queued change. */
export type UploadFunction = (
  entry: CrudEntryLike,
) => PromiseLike<Result<unknown>>;

/** A table's route: its repository, or a function for custom replay. */
export type UploadRoute<I = Record<string, unknown>, K = string> =
  | UploadRepository<I, K>
  | UploadFunction;

export interface UploadRouteOptions<P extends "upsert" | "create"> {
  /**
   * What a `PUT` calls. `upsert` (the default) inserts or replaces the row.
   * `create` inserts it and counts a `conflict` as applied, since the row is
   * already on the server (an earlier upload of the same change); a `PATCH`
   * then fails with `unsupported` and is discarded.
   */
  readonly put?: P;
}

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
      readonly error?: {
        readonly name?: string;
        readonly message: string;
      } | null;
    }>;
  };
}

/** Where the connector met an error it reports to `onError`. */
export interface UploadErrorContext {
  /**
   * `credentials`: reading the Supabase session failed, so sync and uploads
   * wait for PowerSync's next try. `upload`: a change failed with an error that
   * keeps the batch queued for a retry.
   */
  readonly phase: "credentials" | "upload";
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
  /**
   * Called when reading the session fails (kind `unauthorized`, or `network`
   * when the Auth server is unreachable) and when an upload error keeps the
   * batch queued. PowerSync retries both on its own; this is for logging. A
   * signed-out session is not an error.
   */
  readonly onError?: (error: DbError, context: UploadErrorContext) => void;
}

/** PowerSync's `PowerSyncBackendConnector`. */
export interface UploadConnector {
  /**
   * Reads the current session on every call. PowerSync calls it on connect and
   * near `expiresAt`; it has no way to drop credentials early, so
   * `syncWithAuth` reconnects when the claims change to make it read the new
   * token.
   */
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
 * The default for a failed upload: transient errors retry, a newer server row
 * is a conflict, and a change the server will never accept is discarded so it
 * doesn't block the queue.
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

    for (const listener of [...listeners]) {
      listener();
    }
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

function sessionError(cause: unknown): DbError {
  const failure = typeof cause === "object" && cause !== null ? cause : {};
  const name = "name" in failure ? failure.name : undefined;

  const message =
    "message" in failure && typeof failure.message === "string"
      ? failure.message
      : String(cause);

  // supabase-js raises AuthRetryableFetchError, and fetch a TypeError, when
  // the Auth server is unreachable.
  return cause instanceof TypeError || name === "AuthRetryableFetchError"
    ? dbError("network", message)
    : dbError("unauthorized", message);
}

function unsupportedOp(entry: CrudEntryLike, route: string): Result<never> {
  return err(
    dbError(
      "unsupported",
      `better-supabase: a ${route} upload route can't replay PowerSync op ${entry.op}`,
    ),
  );
}

/**
 * Turns a repository into a function route. By default a `PUT` upserts, a
 * `PATCH` updates and a `DELETE` deletes, as a bare repository in `tables`
 * does. With `put: "create"`, a `PUT` inserts and a `conflict` counts as
 * applied, for tables whose rows are written once.
 *
 * ```ts
 * tables: {
 *   customers: bsb.db.customers,
 *   attachments: uploadRoute(bsb.db.attachments, { put: "create" }),
 * }
 * ```
 */
export function uploadRoute(
  repository: CreateUploadRepository<never, never>,
  options: UploadRouteOptions<"create"> & { readonly put: "create" },
): UploadFunction;
export function uploadRoute(
  repository: UploadRepository<never, never>,
  options?: UploadRouteOptions<"upsert">,
): UploadFunction;
export function uploadRoute(
  repository: UploadRepository | CreateUploadRepository,
  options: UploadRouteOptions<"upsert" | "create"> = {},
): UploadFunction {
  const put = options.put ?? "upsert";

  return async (entry) => {
    // PowerSync recorded these columns from a write to the local table, whose
    // columns mirror the repository's table, and the id is its primary key.
    const row = { ...entry.opData, id: entry.id };
    const id = entry.id;

    switch (entry.op) {
      case "PUT": {
        if (put === "create" && "create" in repository) {
          const result = await repository.create(row);

          return !result.ok && result.error.kind === "conflict"
            ? ok(undefined)
            : result;
        }

        return "upsert" in repository
          ? repository.upsert(row)
          : unsupportedOp(entry, put);
      }

      case "PATCH": {
        return put === "upsert" && "update" in repository
          ? repository.update(id, entry.opData ?? {})
          : unsupportedOp(entry, put);
      }

      case "DELETE": {
        return repository.delete(id);
      }

      default: {
        return err(
          dbError(
            "unsupported",
            `better-supabase: unknown PowerSync op ${entry.op}`,
          ),
        );
      }
    }
  };
}

function replay(
  route: UploadRoute,
  entry: CrudEntryLike,
): PromiseLike<Result<unknown>> {
  return typeof route === "function" ? route(entry) : uploadRoute(route)(entry);
}

/**
 * A PowerSync connector that authenticates with the Supabase session and
 * replays queued changes through repositories. Changes upload in batches; a
 * transient error keeps the batch queued for PowerSync's retry, and refused
 * changes land in `rejected` instead of blocking the queue. A table without a
 * route stops the upload with an error, so no change is dropped silently. When
 * the session is gone (the refresh token was revoked), the upload stops until
 * the user signs in again.
 *
 * ```ts
 * const connector = createUploadConnector({
 *   endpoint: process.env.EXPO_PUBLIC_POWERSYNC_URL,
 *   supabase,
 *   tables: { customers: bsb.db.customers },
 * });
 * await powersync.connect(connector);
 * ```
 */
export function createUploadConnector(
  options: UploadConnectorOptions,
): UploadConnector {
  const rejected = rejectedStore();
  const batchSize = options.batchSize ?? 100;

  // undefined when reading the session failed; the failure went to onError.
  const currentSession = async () => {
    try {
      const { data, error } = await options.supabase.auth.getSession();

      if (error) {
        options.onError?.(sessionError(error), { phase: "credentials" });

        return;
      }

      return data.session;
    } catch (cause) {
      options.onError?.(sessionError(cause), { phase: "credentials" });

      return;
    }
  };

  const signedIn = async (): Promise<boolean> =>
    (await currentSession()) !== null;

  return {
    rejected,
    async fetchCredentials() {
      const session = await currentSession();

      if (!session) {
        return null;
      }

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

      if (!batch) {
        return;
      }

      for (const entry of batch.crud) {
        const route = options.tables[entry.table];

        if (!route) {
          throw new Error(
            `better-supabase: no upload route for PowerSync table "${entry.table}"; add it to createUploadConnector({ tables })`,
          );
        }

        const result = await replay(route, entry);

        if (result.ok) {
          continue;
        }

        const { error } = result;

        const outcome =
          options.classify?.(error, entry) ?? uploadOutcome(error.kind);

        switch (outcome) {
          case "retry": {
            if (error.kind === "unauthorized" && !(await signedIn())) {
              return;
            }

            options.onError?.(error, { phase: "upload" });

            // PowerSync keeps the batch queued and calls uploadData again.
            throw new Error(error.message);
          }

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
