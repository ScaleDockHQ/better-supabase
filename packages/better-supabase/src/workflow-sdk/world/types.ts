import type { Pool } from "pg";

import type { EventHub } from "../../core/events.ts";
import type { Logger } from "../../core/logger.ts";
import type { WorkflowDeliveryMode } from "../../sql/modules/workflow-sdk-world.ts";

/**
 * The `@workflow/world` protocol this World speaks: the package version its
 * types and queue format come from. Its tables come from
 * `@workflow/world-postgres` at `WORLD_POSTGRES_VERSION`.
 */
export const WORKFLOW_WORLD_PROTOCOL = "5.0.2";

export type { WorkflowDeliveryMode };

export interface SupabaseWorldOptions {
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
   * hosts with no long-running process.
   */
  readonly delivery?: WorkflowDeliveryMode;
  /**
   * The flow route the poller posts to. Defaults to `WORKFLOW_FLOW_URL`, then
   * `WORKFLOW_LOCAL_BASE_URL` or `http://localhost:$PORT` plus
   * `/.well-known/workflow/v1/flow`.
   */
  readonly flowUrl?: string;
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
   * The jobs queue the messages wait in
   * (`blocks.workflow-sdk-world.options.queue`).
   */
  readonly queue?: string;
  /** The schema of the jobs functions, default `better_supabase`. */
  readonly schema?: string;
  /** Deliveries in flight at once in poll mode (default 50). */
  readonly concurrency?: number;
  /** Milliseconds between polls of an empty queue (default 250). */
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
   * Connections the World's own pool opens (default 10). Each delivery holds
   * one only for its short claim, settle and heartbeat statements, so more
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

export const JOB_HEADER = "x-bs-job";

export const SIGNATURE_HEADER = "x-bs-signature";

export const FLOW_PATH = "/.well-known/workflow/v1/flow";

export const HKDF_SALT = "better-supabase/workflow";

export interface StoredMessage {
  readonly queueName: string;
  readonly messageId: string;
  readonly attempt: number;
  /**
   * The serialized message, base64: jsonb can't hold the NUL bytes payloads may
   * contain.
   */
  readonly body: string;
  readonly headers?: Readonly<Record<string, string>>;
  readonly idempotencyKey?: string;
}

export interface ClaimedJob {
  readonly id: string;
  readonly attempts: number;
  readonly message: { readonly payload?: unknown };
}
