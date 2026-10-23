import type { DbError } from "../core/errors.ts";

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
 * Where the data hooks keep their reads. `memoryEngine()` is the default;
 * `queryEngine(queryClient)` from `better-supabase/query` keeps them in
 * TanStack Query. Every engine passes the same contract suite.
 */
export interface DataEngine {
  readonly apiVersion: 1;
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

/**
 * The data hooks' default engine: an in-memory cache per client. Reads are
 * shared by key and dropped once nothing follows them.
 */
export function memoryEngine(): DataEngine {
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

    load().then(
      (data) => {
        if (run === record.run) {
          set(record, { status: "success", data, error: undefined });
        }
      },
      (cause: unknown) => {
        if (run === record.run) {
          set(record, { status: "error", error: loadError(cause) });
        }
      },
    );
  };

  return {
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
