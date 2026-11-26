import type { BlockTransport } from "./block-transport.ts";

import { encodeArguments } from "../ir/wire.ts";
import { isRecord } from "./guards.ts";

/** The most calls one `read_batch` runs; a longer batch goes in several. */
export const READ_BATCH_LIMIT = 50;

/** The codes PostgREST and Postgres answer with for a function that is missing. */
const MISSING_FUNCTION = new Set(["PGRST202", "42883"]);

interface Queued {
  readonly schema: string;
  readonly fn: string;
  readonly args: Readonly<Record<string, unknown>>;
  readonly resolve: (value: unknown) => void;
  readonly reject: (cause: unknown) => void;
}

/**
 * What `batchReads` learned about the database, shared by the batches that pass
 * the same memory: the schemas without `read_batch`, and the functions it
 * skipped (a `volatile` read, for one), which then go direct from the start
 * instead of costing a second round trip.
 */
export interface ReadBatchMemory {
  readonly missing: Set<string>;
  readonly skipped: Set<string>;
}

/** An empty `ReadBatchMemory`. */
export function createBatchMemory(): ReadBatchMemory {
  return { missing: new Set(), skipped: new Set() };
}

/** A transport that batches the calls of concurrent work, and how to join it. */
export interface ReadBatch {
  /** Queues each call and sends the queue once every active participant waits. */
  readonly transport: BlockTransport;
  /**
   * Runs `fn` as a participant: the batch waits for its calls before it
   * flushes.
   */
  readonly run: <T>(fn: () => Promise<T>) => Promise<T>;
}

/**
 * Batches the reads of concurrent participants into one `read_batch` call per
 * schema (the read-sets module). A call made while no participant is active
 * goes straight to `inner`. The batch flushes once every active participant
 * waits on a call, so a participant's second, dependent call goes in the next
 * flush. Entries the database skips, and every call when `read_batch` fails as
 * a whole, run on their own through `inner`.
 */
export function batchReads(
  inner: BlockTransport,
  memory: ReadBatchMemory = createBatchMemory(),
): ReadBatch {
  let active = 0;
  let inFlight = 0;
  let queue: Queued[] = [];
  let scheduled = false;

  const flush = (): void => {
    const pending = queue;

    queue = [];

    const bySchema = new Map<string, Queued[]>();

    for (const call of pending) {
      const group = bySchema.get(call.schema) ?? [];

      group.push(call);
      bySchema.set(call.schema, group);
    }

    for (const [schema, group] of bySchema) {
      for (let start = 0; start < group.length; start += READ_BATCH_LIMIT) {
        void send(schema, group.slice(start, start + READ_BATCH_LIMIT));
      }
    }
  };

  // Checked in a microtask, so participants started in the same tick all count
  // before the first of their calls could flush alone.
  const settle = (): void => {
    if (scheduled) {
      return;
    }

    scheduled = true;
    queueMicrotask(() => {
      scheduled = false;

      if (queue.length > 0 && queue.length + inFlight >= active) {
        flush();
      }
    });
  };

  // A participant waiting on a direct call counts as waiting, so the others'
  // queued calls don't wait for it to come back.
  const direct = (call: Queued, waits: boolean): void => {
    if (waits) {
      inFlight += 1;
      settle();
    }

    const release = (): void => {
      if (waits) {
        inFlight -= 1;
      }
    };

    inner.call(call.schema, call.fn, call.args).then(
      (value) => {
        release();
        call.resolve(value);
      },
      (cause: unknown) => {
        release();
        call.reject(cause);
      },
    );
  };

  const send = async (
    schema: string,
    calls: readonly Queued[],
  ): Promise<void> => {
    if (calls.length === 1 || memory.missing.has(schema)) {
      for (const call of calls) {
        direct(call, true);
      }

      return;
    }

    let entries: unknown;

    inFlight += calls.length;

    try {
      entries = await inner.call(schema, "read_batch", {
        calls: calls.map((call) => ({
          fn: call.fn,
          args: encodeArguments(call.args),
        })),
      });
    } catch (error) {
      const code = isRecord(error) ? error["code"] : undefined;

      if (typeof code === "string" && MISSING_FUNCTION.has(code)) {
        memory.missing.add(schema);
      }

      entries = undefined;
    } finally {
      inFlight -= calls.length;
    }

    if (!Array.isArray(entries) || entries.length !== calls.length) {
      for (const call of calls) {
        direct(call, true);
      }

      return;
    }

    for (const [index, call] of calls.entries()) {
      const entry: unknown = entries[index];

      if (isRecord(entry) && "data" in entry) {
        call.resolve(entry["data"]);
      } else if (isRecord(entry) && isRecord(entry["error"])) {
        const error = entry["error"];

        const message =
          typeof error["message"] === "string"
            ? error["message"]
            : "read_batch call failed";

        call.reject(Object.assign(new Error(message), error));
      } else {
        memory.skipped.add(`${schema}.${call.fn}`);
        direct(call, true);
      }
    }
  };

  return {
    transport: {
      call(schema, fn, args) {
        return new Promise((resolve, reject) => {
          const call: Queued = { schema, fn, args, resolve, reject };

          if (active === 0) {
            direct(call, false);

            return;
          }

          if (
            memory.missing.has(schema) ||
            memory.skipped.has(`${schema}.${fn}`)
          ) {
            direct(call, true);

            return;
          }

          queue.push(call);
          settle();
        });
      },
    },
    async run(fn) {
      active += 1;

      try {
        return await fn();
      } finally {
        active -= 1;
        settle();
      }
    },
  };
}
