import type { DbError } from "../core/errors.ts";
import type { Executor } from "../core/executor.ts";
import type { Operation } from "../ir/types.ts";
import type { RejectedStore } from "../powersync/connector.ts";

import { DbException } from "../core/db-exception.ts";
import { dbError, dbErrorOf } from "../core/errors.ts";

/** One cached read: the last data stays while it loads again. */
export interface DataEntry {
  readonly status: "idle" | "loading" | "success" | "error";
  readonly data: unknown;
  readonly error: DbError | undefined;
}

/** A cache key: `["bsb", source, verb, ...args]`. */
export type DataKey = readonly unknown[];

/**
 * Tells an engine which tables changed outside the hooks' own writes:
 * `realtimeChanges()` from `better-supabase/realtime` for Supabase Realtime, or
 * a local database's change events. The engine reads again every followed
 * source whose name matches a changed table.
 */
export interface DataChanges {
  /**
   * Calls `onChange` with the changed tables (`customers`, `client_notes`).
   * Returns the function that stops.
   */
  subscribe(onChange: (tables: readonly string[]) => void): () => void;
}

/** A local database's connection and sync progress. */
export interface DataSyncState {
  readonly connected: boolean;
  readonly connecting: boolean;
  /** The first full sync finished; before it, local reads may be empty. */
  readonly hasSynced: boolean;
  readonly uploading: boolean;
  readonly downloading: boolean;
  readonly error: Error | undefined;
}

/** What `useSyncStatus()` and `useConflicts()` read from an engine. */
export interface DataSync {
  /** The same object until a field changes. */
  readonly current: () => DataSyncState;
  readonly subscribe: (listener: () => void) => () => void;
  /** Changes the server refused, from `createUploadConnector`. */
  readonly conflicts?: RejectedStore;
}

/** What every engine takes. */
export interface DataEngineOptions extends LiveEngineOptions {
  /** Reads followed sources again when their tables change elsewhere. */
  readonly live?: DataChanges;
}

/**
 * Where the data hooks keep their reads. `memoryEngine()` is the default;
 * `queryEngine(queryClient)` from `better-supabase/query` keeps them in
 * TanStack Query; `powersyncEngine`, `sqliteEngine` and `tanstackDbEngine` read
 * a local database. Every engine passes the same contract suite.
 */
export interface DataEngine {
  readonly apiVersion: 1;
  /**
   * Runs the client's `db` on a local database. `server` is the PostgREST
   * executor for what the local one can't run. Without it, `db` runs on the
   * server.
   */
  readonly connect?: (server: Executor) => Executor;
  /** Connection and sync progress, for engines over a synced database. */
  readonly sync?: DataSync;
  /**
   * Follows `key`, loading it with `load` when it has no data yet. `load`
   * rejects with a `DbException`. Returns the function that stops following.
   */
  watch(
    key: DataKey,
    load: () => Promise<unknown>,
    listener: () => void,
  ): () => void;
  /** The entry under `key`, the same object until it changes. */
  entry(key: DataKey): DataEntry;
  /** Loads `key` again. */
  refetch(key: DataKey): void;
  /**
   * Rewrites the data of every loaded entry whose key starts with `prefix`.
   * Returns the function that puts the old data back.
   */
  rewrite(prefix: DataKey, update: (data: unknown) => unknown): () => void;
  /** Marks every entry under `prefix` stale and loads the followed ones again. */
  invalidate(prefix: DataKey): void;
}

const IDLE: DataEntry = { status: "idle", data: undefined, error: undefined };

/** A stable string for a key; a `bigint` becomes its digits. */
export function dataKeyHash(key: DataKey): string {
  return JSON.stringify(key, (_key, value: unknown) =>
    typeof value === "bigint" ? `${value.toString()}n` : value,
  );
}

function startsWith(key: DataKey, prefix: DataKey): boolean {
  return prefix.every(
    (part, index) => dataKeyHash([part]) === dataKeyHash([key[index]]),
  );
}

/** The `DbError` a rejected load carries. */
export function loadError(cause: unknown): DbError {
  return (
    dbErrorOf(cause) ??
    dbError(
      "unexpected",
      cause instanceof Error ? cause.message : String(cause),
    )
  );
}

interface MemoryRecord {
  readonly key: DataKey;
  entry: DataEntry;
  load: (() => Promise<unknown>) | undefined;
  run: number;
  readonly listeners: Set<() => void>;
}

/** What `liveEngine` takes besides the changes. */
export interface LiveEngineOptions {
  /**
   * The tables each source reads, by source name, when they differ from its
   * name: `{ tickets: ["tasks"] }`. A source matches a table whose name equals
   * its own, ignoring case, `_` and `-`.
   */
  readonly tables?: Readonly<Record<string, readonly string[]>>;
}

const normalName = (name: string): string =>
  name.replaceAll(/[_-]/g, "").toLowerCase();

/**
 * `engine`, reading followed sources again when `changes` reports one of their
 * tables. It subscribes while a hook follows a read, and stops after the last
 * one.
 */
export function liveEngine(
  engine: DataEngine,
  changes: DataChanges | undefined,
  options: LiveEngineOptions = {},
): DataEngine {
  if (changes === undefined) {
    return engine;
  }

  const watched = new Map<string, number>();
  let stop: (() => void) | undefined;

  const onChange = (tables: readonly string[]): void => {
    const changed = new Set(tables.map(normalName));

    for (const name of watched.keys()) {
      const own = options.tables?.[name] ?? [name];

      if (own.some((table) => changed.has(normalName(table)))) {
        engine.invalidate(["bsb", name]);
      }
    }
  };

  return {
    ...engine,
    watch: (key, load, listener) => {
      const unwatch = engine.watch(key, load, listener);
      const name = key[1];

      if (typeof name !== "string") {
        return unwatch;
      }

      watched.set(name, (watched.get(name) ?? 0) + 1);
      stop ??= changes.subscribe(onChange);
      let done = false;

      return () => {
        if (done) {
          return;
        }

        done = true;
        unwatch();
        const left = (watched.get(name) ?? 1) - 1;

        if (left === 0) {
          watched.delete(name);
        } else {
          watched.set(name, left);
        }

        if (watched.size === 0 && stop !== undefined) {
          const unsubscribe = stop;
          stop = undefined;
          unsubscribe();
        }
      };
    },
  };
}

/** What an engine over a local database is made of. */
export interface LocalTablesOption {
  /**
   * The table keys the local database holds. `db` reads and writes every other
   * table on the server. Default: every table runs locally.
   */
  readonly local?: readonly string[] | undefined;
}

export interface LocalEngineParts extends LiveEngineOptions, LocalTablesOption {
  /** Where reads are kept; default `memoryEngine()`. */
  readonly cache?: DataEngine | undefined;
  /** The local database's change events. */
  readonly changes?: DataChanges | undefined;
  readonly connect: (server: Executor) => Executor;
  readonly sync?: DataSync | undefined;
}

/** Runs the `local` tables on `executor` and the rest on `server`. */
function routeTables(
  executor: Executor,
  server: Executor,
  local: readonly string[],
): Executor {
  const keys = new Set(local);
  const onDevice = (op: Operation): boolean => keys.has(op.table.key);

  return {
    ...executor,
    execute: (op, context) =>
      (onDevice(op) ? executor : server).execute(op, context),
    batch: async (ops, context) =>
      executor.batch !== undefined && ops.every(onDevice)
        ? executor.batch(ops, context)
        : Promise.all(
            ops.map((op) =>
              (onDevice(op) ? executor : server).execute(op, context),
            ),
          ),
  };
}

/**
 * An engine whose `db` runs on a local database: `cache` keeps the reads, and
 * the database's changes read followed sources again.
 */
export function localEngine(parts: LocalEngineParts): DataEngine {
  const cache = parts.cache ?? memoryEngine();

  const live = liveEngine(
    cache,
    parts.changes,
    parts.tables === undefined ? {} : { tables: parts.tables },
  );

  const { connect, local } = parts;

  return {
    ...live,
    connect:
      local === undefined
        ? connect
        : (server) => routeTables(connect(server), server, local),
    ...(parts.sync === undefined ? {} : { sync: parts.sync }),
  };
}

/**
 * The data hooks' default engine: an in-memory cache per client. Reads are
 * shared by key and dropped once nothing follows them. `live` reads followed
 * sources again when their tables change elsewhere.
 */
export function memoryEngine(options: DataEngineOptions = {}): DataEngine {
  const records = new Map<string, MemoryRecord>();

  const recordOf = (key: DataKey): MemoryRecord => {
    const hash = dataKeyHash(key);
    let record = records.get(hash);

    if (record === undefined) {
      record = {
        key,
        entry: IDLE,
        load: undefined,
        run: 0,
        listeners: new Set(),
      };
      records.set(hash, record);
    }

    return record;
  };

  const set = (record: MemoryRecord, entry: Partial<DataEntry>): void => {
    record.entry = { ...record.entry, ...entry };

    for (const listener of [...record.listeners]) {
      listener();
    }
  };

  const fetch = (record: MemoryRecord): void => {
    const load = record.load;

    if (load === undefined) {
      return;
    }

    record.run += 1;
    const run = record.run;
    set(record, { status: "loading" });

    void load().then(
      (data) => {
        if (run === record.run) {
          set(record, { status: "success", data, error: undefined });
        }

        return data;
      },
      (cause: unknown) => {
        if (run === record.run) {
          set(record, { status: "error", error: loadError(cause) });
        }

        return cause;
      },
    );
  };

  const engine: DataEngine = {
    apiVersion: 1,
    watch: (key, load, listener) => {
      const record = recordOf(key);
      record.load = load;
      record.listeners.add(listener);

      if (record.entry.status === "idle") {
        fetch(record);
      }

      return () => {
        record.listeners.delete(listener);

        if (record.listeners.size === 0) {
          record.run += 1;
          records.delete(dataKeyHash(key));
        }
      };
    },
    entry: (key) => records.get(dataKeyHash(key))?.entry ?? IDLE,
    refetch: (key) => {
      const record = records.get(dataKeyHash(key));

      if (record !== undefined) {
        fetch(record);
      }
    },
    rewrite: (prefix, update) => {
      const previous: [MemoryRecord, unknown][] = [];

      for (const record of records.values()) {
        if (
          record.entry.data === undefined ||
          !startsWith(record.key, prefix)
        ) {
          continue;
        }

        previous.push([record, record.entry.data]);
        set(record, { data: update(record.entry.data) });
      }

      return () => {
        for (const [record, data] of previous) {
          set(record, { data });
        }
      };
    },
    invalidate: (prefix) => {
      for (const record of records.values()) {
        if (startsWith(record.key, prefix)) {
          fetch(record);
        }
      }
    },
  };

  return liveEngine(engine, options.live, options);
}

/** `result.data`, or a rejection with the `DbException` of `result.error`. */
export async function unwrap<T>(
  result: PromiseLike<
    | { readonly ok: true; readonly data: T }
    | { readonly ok: false; readonly error: DbError }
  >,
): Promise<T> {
  const settled = await result;

  if (!settled.ok) {
    throw new DbException(settled.error);
  }

  return settled.data;
}
