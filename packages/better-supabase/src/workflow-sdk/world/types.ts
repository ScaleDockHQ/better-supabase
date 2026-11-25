import type { Pool } from "pg";

import type { EventHub } from "../../core/events.ts";
import type { Logger } from "../../core/logger.ts";
import type { WorkflowDeliveryMode } from "../../sql/modules/workflow-sdk.ts";
import type { VercelQueueSdk } from "./vercel-queue.ts";

/**
 * The `@workflow/world` protocol this World speaks: the package version its
 * types and queue format come from, which a test keeps equal to the installed
 * one. Its tables come from `@workflow/world-postgres` at
 * `WORLD_POSTGRES_VERSION`.
 */
export const WORKFLOW_WORLD_PROTOCOL = "5.4.0";

export type { WorkflowDeliveryMode };

/**
 * How the World's connection behaves. `session` supports `LISTEN`, which stream
 * readers, run status waits and live run event feeds use. `transaction` is a
 * transaction pooler (Supabase port 6543), which has none: the World then polls
 * the stream rows and leaves `events.subscribe` and
 * `runs.waitForTerminalStatus` out, so the runtime polls instead.
 */
export type WorldConnection = "session" | "transaction";

/** Milliseconds core waits to batch stream writes when no option sets it. */
export const DEFAULT_STREAM_FLUSH_MS = 20;

/**
 * The run attribute that names the key ring entry a run's data is encrypted
 * with.
 */
export const KEY_ID_ATTRIBUTE = "$bsb.key_id";

/** A message the queue gave up on after `MAX_DELIVERIES` failed deliveries. */
export interface DeadLetter {
  readonly queueName: string;
  readonly jobId: string;
  readonly messageId?: string;
  /** The run the message belongs to, when its body names one. */
  readonly runId?: string | undefined;
  /** Deliveries of this message, the last one included. */
  readonly attempts: number;
  /** The last error. */
  readonly error: string;
}

export interface SupabaseWorldOptions {
  /**
   * Called once when a message is dead-lettered. A throw is logged and ignored;
   * the message stays in the queue's archive with `dead = true`.
   */
  readonly onDeadLetter?: (info: DeadLetter) => void | Promise<void>;
  /**
   * Turns on world-postgres's experimental `invoke()` delivery (one Graphile
   * execution queue per run). Off by default.
   */
  readonly enableInvoke?: boolean;
  /**
   * Milliseconds core waits before it flushes buffered stream writes into the
   * World (default 20; core's own default is 0, one insert per chunk).
   * `WORKFLOW_STREAM_FLUSH_INTERVAL_MS` overrides this option.
   */
  readonly streamFlushIntervalMs?: number;
  /**
   * `session` or `transaction`; detected from the connection string (port 6543
   * is a transaction pooler) when unset, and read from
   * `WORKFLOW_POSTGRES_CONNECTION`.
   */
  readonly connection?: WorldConnection;
  /**
   * Milliseconds between reads of an open stream in `transaction` mode (default
   * 100).
   */
  readonly streamPollInterval?: number;
  /**
   * A Postgres connection string with access to the `workflow` schema and the
   * jobs functions.
   */
  readonly connectionString?: string;
  /** An existing pool instead of `connectionString`; `close()` leaves it open. */
  readonly pool?: Pool;
  /**
   * How messages reach the flow route. `poll` (default) claims them in this
   * process and posts to the route; `pg_net` leaves delivery to
   * `dispatch_workflow_deliveries()` on a pg_cron schedule, for serverless
   * hosts with no long-running process; `vercel-queue` sends each message
   * through Vercel Queues (an optional peer, `@vercel/queue`) and Vercel calls
   * the flow route, which suits a function deployed on Vercel.
   */
  readonly delivery?: WorkflowDeliveryMode;
  /**
   * The flow route the poller posts to. Defaults to `WORKFLOW_FLOW_URL`, then
   * `WORKFLOW_LOCAL_BASE_URL` or `http://localhost:$PORT` plus
   * `/.well-known/workflow/v1/flow`.
   */
  readonly flowUrl?: string;
  /**
   * Headers the poller adds to every post to the flow route (a deployment
   * protection bypass, for one). `WORKFLOW_DELIVERY_HEADERS` (a JSON object)
   * and, for `pg_net`, the Vault secret `workflow_delivery_headers` set the
   * same. The World's own headers win over these.
   */
  readonly deliveryHeaders?: Readonly<Record<string, string>>;
  /**
   * The `@vercel/queue` client `delivery: "vercel-queue"` sends and receives
   * with (`new QueueClient({ ... })`); default `new QueueClient()` from the
   * installed package.
   */
  readonly vercelQueue?: VercelQueueSdk;
  /**
   * Seconds a run's wake-up may stay owed before `deliverOnce()` and `start()`
   * send it again (default 300). A wake-up is owed from the event that wakes
   * the run until a delivery of it completes.
   */
  readonly recoverAfter?: number;
  /**
   * The secret deliveries are signed with. Required to accept `pg_net`
   * deliveries; read from the Vault secret `workflow_delivery_secret` when
   * unset. A poller with a secret signs too, and the route then refuses
   * unsigned requests.
   */
  readonly deliverySecret?: string;
  /**
   * A 32-byte master key (base64 or hex) that each run's AES-256 key is derived
   * from (HKDF-SHA256). Read from the Vault secret `workflow_encryption_key`
   * when unset; without one, run data is stored unencrypted.
   */
  readonly encryptionKey?: string;
  /**
   * A key ring as JSON (`[{ "id", "key", "from" }]`), read from the Vault
   * secret `workflow_encryption_keys` when unset. A run uses the latest key
   * that started before it was created, so appending a key rotates without
   * changing any run's key. It replaces `encryptionKey`.
   */
  readonly encryptionKeys?: string;
  /**
   * The jobs queue the messages wait in
   * (`blocks["workflow-sdk"].options.queue`).
   */
  readonly queue?: string;
  /** The schema of the jobs functions, default `better_supabase`. */
  readonly schema?: string;
  /** Deliveries in flight at once in poll mode (default 50). */
  readonly concurrency?: number;
  /**
   * Starts, resumes, cancels and reads runs without delivering any message: the
   * process never polls the queue, and `start()` skips the owed wake-up sweep
   * and the re-enqueue of active runs. For a web tier next to separate workers,
   * as world-postgres's own `skipWorkers`. Read from
   * `WORKFLOW_POSTGRES_SKIP_WORKERS=1`.
   */
  readonly skipWorkers?: boolean;
  /**
   * Milliseconds between polls of an empty queue (default 250; world-postgres
   * polls graphile-worker on its own schedule).
   */
  readonly pollInterval?: number;
  /**
   * Seconds a claimed message stays leased; the delivery extends it while it
   * runs (default 60).
   */
  readonly lease?: number;
  /**
   * Seconds a poll delivery may wait for the flow route before it is aborted,
   * failed and retried; the lease stops being extended then (default 300, at
   * least `lease`).
   */
  readonly deliveryTimeout?: number;
  /** The queue namespace, as `WORKFLOW_QUEUE_NAMESPACE`. */
  readonly namespace?: string;
  /**
   * Connections the World's own pool opens (default 10, or 2 on serverless
   * hosts, where every instance holds its own pool). Each delivery holds one
   * only for its short claim, settle and heartbeat statements, so more
   * deliveries than connections wait for one instead of failing.
   */
  readonly maxConnections?: number;
  /**
   * Milliseconds a statement waits for a free connection before it fails
   * (default 30000).
   */
  readonly connectionTimeout?: number;
  /** Milliseconds an unused connection stays open (default 10000). */
  readonly idleTimeout?: number;
  /**
   * `statement_timeout` of the World's connections, in milliseconds (default
   * 30000).
   */
  readonly statementTimeout?: number;
  /**
   * `idle_in_transaction_session_timeout` of the World's connections, in
   * milliseconds (default 15000).
   */
  readonly idleInTransactionTimeout?: number;
  /**
   * `betterSupabase.events`: errors on idle pooled connections arrive as
   * `error` events.
   */
  readonly events?: EventHub;
  /**
   * Where idle-connection errors go without `error` handlers. Defaults to the
   * console.
   */
  readonly logger?: Logger;
}

/**
 * The deliveries one message may take; matches world-postgres (49 plus 24
 * retries of the terminal write).
 */
export const MAX_DELIVERIES = 73;

export const SIGNATURE_TOLERANCE_SECONDS = 300;

export const JOB_HEADER = "x-bsb-job";

export const SIGNATURE_HEADER = "x-bsb-signature";

export const FLOW_PATH = "/.well-known/workflow/v1/flow";

export const HKDF_SALT = "better-supabase/workflow";

export interface StoredMessage {
  readonly queueName: string;
  readonly messageId: string;
  readonly attempt: number;
  /**
   * When the message was first queued (ISO 8601), sent as
   * `x-vqs-message-created-at`.
   */
  readonly createdAt?: string;
  /**
   * The serialized message, base64: jsonb can't hold the NUL bytes payloads may
   * contain.
   */
  readonly body: string;
  readonly headers?: Readonly<Record<string, string>>;
  readonly idempotencyKey?: string;
  /**
   * Seconds still to wait when the message was delayed past what Vercel Queues
   * allows (23 hours): each hop sends the message on until none remain.
   */
  readonly remainingDelay?: number;
}

export interface ClaimedJob {
  readonly id: string;
  readonly attempts: number;
  readonly message: { readonly payload?: unknown };
}
