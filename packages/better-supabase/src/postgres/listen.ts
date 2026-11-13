import type { Logger } from "../core/logger.ts";

import { kicker } from "../core/kick.ts";
import { consoleLogger } from "../core/logger.ts";
import { WORK_CHANNEL } from "../sql/modules/work-notify.ts";
import { usesTransactionPooler } from "./pooler.ts";

/** The notification `pg` hands a listening client. */
export interface PgNotification {
  readonly channel: string;
  readonly payload?: string | undefined;
}

/** The part of a `pg` pooled client `listenForWork` uses. */
export interface PgListenClient {
  query(text: string, values?: unknown[]): Promise<{ rows: unknown[] }>;
  on(
    event: "notification",
    listener: (message: PgNotification) => void,
  ): unknown;
  on(event: "error", listener: (error: Error) => void): unknown;
  on(event: "end", listener: () => void): unknown;
  removeAllListeners(event?: string): unknown;
  /** `true` closes the connection instead of returning it to the pool. */
  release(destroy?: boolean): void;
}

/** The part of a `pg.Pool` `listenForWork` uses. */
export interface PgListenPool {
  connect(): Promise<PgListenClient>;
  readonly options?: {
    readonly connectionString?: string | undefined;
    readonly port?: number | undefined;
  };
}

export interface ListenForWorkOptions {
  /** Processes the webhook inbox: `() => inbox.process({ handler })`. */
  readonly inbox?: () => PromiseLike<unknown>;
  /** Relays the outbox: `() => outbox.relay({ consumer, sink })`. */
  readonly outbox?: () => PromiseLike<unknown>;
  /**
   * Drains each queue by name: `{ emails: () => queue.drain({ queue: "emails",
   * handler }) }`. Notifications for other queues are ignored.
   */
  readonly queues?: Readonly<Record<string, () => PromiseLike<unknown>>>;
  /** How long to gather notifications before a pass starts. Defaults to 25. */
  readonly debounceMs?: number;
  /**
   * The first wait before reconnecting after the connection drops; it doubles
   * up to 30 seconds. Defaults to 1000.
   */
  readonly reconnectMs?: number;
  /** Receives connection errors and failing passes. Default: `console`. */
  readonly logger?: Logger;
}

export interface WorkListener {
  /** Stops listening, releases the connection and waits for running passes. */
  close(): Promise<void>;
}

const MAX_RECONNECT_MS = 30_000;

type WorkKey = "inbox" | "outbox" | `queue:${string}`;

function field(value: unknown, name: string): unknown {
  if (typeof value !== "object" || value === null) {
    return undefined;
  }

  const record: Record<string, unknown> = { ...value };

  return record[name];
}

function keyOf(payload: string | undefined): WorkKey | undefined {
  try {
    const message: unknown = JSON.parse(payload ?? "");
    const kind = field(message, "kind");
    const queue = field(message, "queue");

    if (kind === "inbox" || kind === "outbox") {
      return kind;
    }

    return kind === "queue" && typeof queue === "string"
      ? `queue:${queue}`
      : undefined;
  } catch {
    return undefined;
  }
}

/**
 * Runs the inbox, outbox and queue passes as soon as a write commits, on a
 * long-lived Node process. It holds one connection of `pool` with `LISTEN
 * better_supabase_work`, which the job modules' statement triggers notify, so a
 * row inserted from SQL is handled too. After each (re)connect it asks the
 * `*_has_work` probes, so work written while it was away still runs. Keep the
 * cron or drain route as the fallback for hosts without such a process.
 *
 * Needs a session connection: the transaction pooler (port 6543) drops
 * `LISTEN`, so it throws for one.
 */
export async function listenForWork(
  pool: PgListenPool,
  options: ListenForWorkOptions,
): Promise<WorkListener> {
  const { connectionString, port } = pool.options ?? {};

  if (port === 6543 || usesTransactionPooler(connectionString)) {
    throw new TypeError(
      "listenForWork needs a session connection (port 5432 or the session pooler); the transaction pooler (port 6543) drops LISTEN",
    );
  }

  const logger = options.logger ?? consoleLogger;
  const debounceMs = options.debounceMs ?? 25;
  const queues = options.queues ?? {};
  const running = new Set<Promise<unknown>>();

  const run = (key: WorkKey): PromiseLike<unknown> | undefined => {
    if (key === "inbox") {
      return options.inbox?.();
    }

    if (key === "outbox") {
      return options.outbox?.();
    }

    return Object.hasOwn(queues, key.slice(6))
      ? queues[key.slice(6)]?.()
      : undefined;
  };

  const fire = kicker<WorkKey>(
    {
      waitUntil: (work) => {
        running.add(work);
        void work.finally(() => {
          running.delete(work);
        });
      },
      run: async (key) => run(key),
    },
    logger,
    "listenForWork",
  );

  const pending = new Set<WorkKey>();
  let timer: ReturnType<typeof setTimeout> | undefined;

  const schedule = (key: WorkKey): void => {
    pending.add(key);
    timer ??= setTimeout(() => {
      timer = undefined;

      for (const next of pending) {
        fire(next);
      }

      pending.clear();
    }, debounceMs);
  };

  /** Schedules each configured pass whose probe says there is work. */
  const probe = async (client: PgListenClient): Promise<void> => {
    const checks: [WorkKey, string, unknown[]][] = [];

    if (options.inbox) {
      checks.push([
        "inbox",
        "select better_supabase.webhook_inbox_has_work() as ready",
        [],
      ]);
    }

    if (options.outbox) {
      checks.push([
        "outbox",
        "select better_supabase.outbox_has_work() as ready",
        [],
      ]);
    }

    for (const [key, text, values] of checks) {
      try {
        const { rows } = await client.query(text, values);

        if (field(rows[0], "ready") === true) {
          schedule(key);
        }
      } catch (cause) {
        logger.warn(`listenForWork: the ${key} probe failed`, { cause });
      }
    }

    const names = Object.keys(queues);

    if (names.length > 0) {
      try {
        const { rows } = await client.query(
          "select queue from better_supabase.ready_job_queues($1::text[])",
          [names],
        );

        for (const row of rows) {
          const queue = field(row, "queue");

          if (typeof queue === "string") {
            schedule(`queue:${queue}`);
          }
        }
      } catch (cause) {
        logger.warn("listenForWork: the queue probe failed", { cause });
      }
    }
  };

  let closed = false;
  let client: PgListenClient | undefined;
  let retry: ReturnType<typeof setTimeout> | undefined;
  let wait = options.reconnectMs ?? 1000;

  const connect = async (): Promise<void> => {
    const next = await pool.connect();
    let dropped = false;

    const drop = (cause?: Error): void => {
      if (dropped) {
        return;
      }

      dropped = true;
      next.removeAllListeners();
      next.release(true);

      // A connection that never listened is retried by whoever called connect.
      if (client !== next) {
        return;
      }

      client = undefined;

      if (closed) {
        return;
      }

      logger.warn("listenForWork lost its connection; reconnecting", {
        ...(cause ? { cause } : {}),
      });
      reconnect();
    };

    next.on("notification", (message) => {
      if (message.channel !== WORK_CHANNEL) {
        return;
      }

      const key = keyOf(message.payload);

      if (key !== undefined) {
        schedule(key);
      }
    });
    next.on("error", drop);
    next.on("end", () => {
      drop();
    });

    try {
      await next.query(`listen ${WORK_CHANNEL}`);
    } catch (cause) {
      drop(cause instanceof Error ? cause : undefined);
      throw cause;
    }

    client = next;
    wait = options.reconnectMs ?? 1000;
    await probe(next);
  };

  const reconnect = (): void => {
    if (closed || retry !== undefined) {
      return;
    }

    retry = setTimeout(() => {
      retry = undefined;
      connect().catch((cause: unknown) => {
        logger.warn("listenForWork could not reconnect", { cause });
        wait = Math.min(wait * 2, MAX_RECONNECT_MS);
        reconnect();
      });
    }, wait);
  };

  await connect();

  return {
    async close() {
      closed = true;
      clearTimeout(retry);
      clearTimeout(timer);

      const current = client;
      client = undefined;

      if (current) {
        current.removeAllListeners();

        try {
          await current.query(`unlisten ${WORK_CHANNEL}`);
        } catch {
          // The connection is closed below either way.
        }

        current.release(true);
      }

      await Promise.allSettled(running);
    },
  };
}
