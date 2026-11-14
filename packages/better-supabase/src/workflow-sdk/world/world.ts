import type {
  MessageId,
  QueueBatchResult,
  QueueOptions,
  QueuePayload,
  QueuePrefix,
  ValidQueueName,
  World,
} from "@workflow/world";

import { parseQueueRoute, reenqueueActiveRuns } from "@workflow/world";
import { createWorld as createPostgresWorld } from "@workflow/world-postgres";
import { Pool } from "pg";

import type { WorkflowMaintenance } from "../run-keys.ts";
import type {
  ClaimedJob,
  DeadLetter,
  StoredMessage,
  SupabaseWorldOptions,
} from "./types.ts";

import { dbError } from "../../core/errors.ts";
import { consoleLogger } from "../../core/logger.ts";
import { memoized } from "../../core/optional-peer.ts";
import { problemResponse } from "../../core/problem.ts";
import { sqlIdent } from "../../core/template.ts";
import { watchPoolErrors } from "../../postgres/pool-errors.ts";
import { usesTransactionPooler } from "../../postgres/pooler.ts";
import {
  WORKFLOW_DELIVERY_QUEUE,
  WORKFLOW_VAULT_SECRETS,
} from "../../sql/modules/workflow-sdk.ts";
import { createAnalytics } from "./analytics.ts";
import {
  deriveRunKey,
  parseMasterKey,
  signDelivery,
  unsignedAllowed,
  verifyDelivery,
} from "./crypto.ts";
import { assertWorldMigrations } from "./drift.ts";
import { env, resolveFlowUrl, worldOptionsFromEnv } from "./env.ts";
import { createMaintenance } from "./maintenance.ts";
import { JOB_HEADER, MAX_DELIVERIES, SIGNATURE_HEADER } from "./types.ts";

/**
 * JSON with Uint8Array values as `{ __type: "Uint8Array", data: <base64> }`, as
 * world-postgres sends them.
 */
function serialize(value: unknown): Buffer {
  return Buffer.from(
    JSON.stringify(value, (_key, inner: unknown) =>
      inner instanceof Uint8Array
        ? { __type: "Uint8Array", data: Buffer.from(inner).toString("base64") }
        : inner,
    ),
  );
}

function isStoredMessage(value: unknown): value is StoredMessage {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const record: Record<string, unknown> = { ...value };

  return (
    typeof record["queueName"] === "string" &&
    typeof record["messageId"] === "string" &&
    typeof record["attempt"] === "number" &&
    typeof record["body"] === "string"
  );
}

/** The run a flow message belongs to, when its body names one. */
function runIdOf(message: StoredMessage): string | undefined {
  try {
    const body: unknown = JSON.parse(
      Buffer.from(message.body, "base64").toString("utf-8"),
    );

    if (typeof body === "object" && body !== null && "runId" in body) {
      return typeof body.runId === "string" ? body.runId : undefined;
    }
  } catch {
    return undefined;
  }

  return undefined;
}

function deliveryProblem(
  kind: "invalid_request" | "unauthorized" | "network",
  detail: string,
): Response {
  return problemResponse(
    dbError(kind, detail, { code: "WORKFLOW_DELIVERY_REJECTED" }),
    { expose: true },
  );
}

/**
 * Retry delay after a failed delivery, as world-postgres (exp(min(attempt, 10))
 * seconds).
 */
const backoffSeconds = (attempt: number): number =>
  Math.ceil(Math.exp(Math.min(attempt, 10)));

const REGISTRY: unique symbol = Symbol.for("better-supabase.workflow.worlds");

/**
 * The Worlds `createWorld()` made, on `globalThis`: the Workflow SDK imports
 * the factory once per bundle, and each copy must share one pool and poller.
 */
function worldRegistry(): Map<string, SupabaseWorld> {
  // SAFETY: only this function writes the symbol, always a Map of Worlds.
  const holder = globalThis as { [REGISTRY]?: Map<string, SupabaseWorld> };
  holder[REGISTRY] ??= new Map<string, SupabaseWorld>();

  return holder[REGISTRY];
}

/** The World plus the delivery helpers the tests and routes use. */
export type SupabaseWorld = World &
  WorkflowMaintenance & {
    start(): Promise<void>;
    close(): Promise<void>;
    /**
     * Claims and delivers the due messages once (poll mode); resolves with how
     * many it delivered.
     */
    deliverOnce(): Promise<number>;
  };

/**
 * A Workflow SDK World on Supabase Postgres: the run, step, event, hook and
 * stream tables of `@workflow/world-postgres` (installed by the `workflow-sdk`
 * SQL module), with messages in the queue block's queue instead of
 * graphile-worker.
 *
 * ```ts
 * // workflow.config or WORKFLOW_TARGET_WORLD=better-supabase/workflow-sdk/world
 * export default createSupabaseWorld({ delivery: "pg_net" });
 * ```
 */
export function createSupabaseWorld(
  options: SupabaseWorldOptions = {},
): SupabaseWorld {
  const delivery = options.delivery ?? "poll";
  const queueName = options.queue ?? WORKFLOW_DELIVERY_QUEUE;
  const schema = sqlIdent(options.schema ?? "better_supabase");
  const concurrency = Math.max(1, options.concurrency ?? 50);
  const pollInterval = Math.max(10, options.pollInterval ?? 250);
  const lease = Math.max(5, options.lease ?? 60);
  const deliveryTimeout = Math.max(lease, options.deliveryTimeout ?? 300);

  const pool =
    options.pool ??
    new Pool({
      connectionString:
        options.connectionString ??
        env("WORKFLOW_POSTGRES_URL") ??
        env("SUPABASE_DB_URL") ??
        env("DATABASE_URL"),
      max: Math.max(1, options.maxConnections ?? 10),
      connectionTimeoutMillis: options.connectionTimeout ?? 30_000,
      idleTimeoutMillis: options.idleTimeout ?? 10_000,
      statement_timeout: options.statementTimeout ?? 30_000,
      idle_in_transaction_session_timeout:
        options.idleInTransactionTimeout ?? 15_000,
    });

  const logger = options.logger ?? consoleLogger;

  if (
    options.pool === undefined &&
    usesTransactionPooler(
      options.connectionString ??
        env("WORKFLOW_POSTGRES_URL") ??
        env("SUPABASE_DB_URL") ??
        env("DATABASE_URL"),
    )
  ) {
    logger.warn(
      "The workflow World connects through the transaction pooler (port 6543). world-postgres needs LISTEN/NOTIFY, which only a session connection (port 5432 or the session pooler) supports.",
    );
  }

  watchPoolErrors(pool, {
    ...(options.events ? { events: options.events } : {}),
    ...(options.logger ? { logger: options.logger } : {}),
  });

  const base = createPostgresWorld({
    pool,
    ...(options.namespace === undefined
      ? {}
      : { namespace: options.namespace }),
    ...(options.enableInvoke === undefined
      ? {}
      : { enableInvoke: options.enableInvoke }),
    ...(options.streamFlushIntervalMs === undefined
      ? {}
      : { streamFlushIntervalMs: options.streamFlushIntervalMs }),
  });

  /**
   * The Vault secret, `undefined` when no row has the name; a failed read
   * rejects.
   */
  const vault = async (name: string): Promise<string | undefined> => {
    const result = await pool.query<{ secret: string | null }>(
      "select decrypted_secret as secret from vault.decrypted_secrets where name = $1",
      [name],
    );

    return result.rows[0]?.secret ?? undefined;
  };

  const deliverySecret = memoized(
    async () =>
      options.deliverySecret ?? vault(WORKFLOW_VAULT_SECRETS.deliverySecret),
  );

  const masterKey = memoized(async () => {
    const text =
      options.encryptionKey ??
      (await vault(WORKFLOW_VAULT_SECRETS.encryptionKey));

    return text === undefined ? undefined : parseMasterKey(text);
  });

  const allowUnsigned = unsignedAllowed();

  const call = async <T>(
    fn: string,
    args: readonly unknown[],
  ): Promise<T[]> => {
    const list = args.map((_, index) => `$${String(index + 1)}`).join(", ");

    const result = await pool.query(
      `select * from ${schema}.${sqlIdent(fn)}(${list})`,
      [...args],
    );

    // SAFETY: each caller names the row shape its function returns.
    return result.rows as T[];
  };

  const store = async (
    message: StoredMessage,
    delaySeconds: number | undefined,
  ): Promise<void> => {
    await call("enqueue_job", [
      queueName,
      JSON.stringify(message),
      Math.max(0, Math.ceil(delaySeconds ?? 0)),
      MAX_DELIVERIES,
      message.idempotencyKey ?? message.messageId,
      false,
    ]);
  };

  const queue = async (
    name: ValidQueueName,
    message: QueuePayload,
    opts?: QueueOptions,
  ): Promise<{ messageId: MessageId }> => {
    // SAFETY: MessageId is a branded string; any id the queue mints is valid.
    const messageId = `msg_${crypto.randomUUID()}` as MessageId;
    await store(
      {
        queueName: name,
        messageId,
        attempt: 1,
        createdAt: new Date().toISOString(),
        body: serialize(message).toString("base64"),
        ...(opts?.headers === undefined ? {} : { headers: opts.headers }),
        ...(opts?.idempotencyKey === undefined
          ? {}
          : { idempotencyKey: opts.idempotencyKey }),
      },
      opts?.delaySeconds,
    );
    // The runtime never calls start(), so the process that queues also polls.
    startPolling();

    return { messageId };
  };

  const queueBatch = async (
    name: ValidQueueName,
    messages: readonly { message: QueuePayload; opts?: QueueOptions }[],
  ): Promise<QueueBatchResult[]> => {
    if (messages.length === 0) {
      return [];
    }

    const createdAt = new Date().toISOString();

    const prepared = messages.map(({ message, opts }) => {
      // SAFETY: MessageId is a branded string; any id the queue mints is valid.
      const messageId = `msg_${crypto.randomUUID()}` as MessageId;

      const stored: StoredMessage = {
        queueName: name,
        messageId,
        attempt: 1,
        createdAt,
        body: serialize(message).toString("base64"),
        ...(opts?.headers === undefined ? {} : { headers: opts.headers }),
        ...(opts?.idempotencyKey === undefined
          ? {}
          : { idempotencyKey: opts.idempotencyKey }),
      };

      return {
        messageId,
        stored,
        delay: Math.max(0, Math.ceil(opts?.delaySeconds ?? 0)),
      };
    });

    try {
      // One statement, so the batch is enqueued together or not at all.
      await pool.query(
        `select ${schema}.enqueue_job($1, m.payload, m.delay, $2, m.dedupe, false)
         from unnest($3::jsonb[], $4::integer[], $5::text[]) as m(payload, delay, dedupe)`,
        [
          queueName,
          MAX_DELIVERIES,
          prepared.map(({ stored }) => JSON.stringify(stored)),
          prepared.map(({ delay }) => delay),
          prepared.map(
            ({ stored }) => stored.idempotencyKey ?? stored.messageId,
          ),
        ],
      );
    } catch (cause) {
      const error = cause instanceof Error ? cause.message : String(cause);

      return prepared.map((): QueueBatchResult => ({
        messageId: null,
        error,
        retryable: true,
      }));
    }

    startPolling();

    return prepared.map(({ messageId }): QueueBatchResult => ({ messageId }));
  };

  const complete = (id: string, attempts: number): Promise<unknown> =>
    call("complete_job", [queueName, id, attempts]);

  const fail = async (
    id: string,
    attempts: number,
    error: string,
    attempt: number,
    message?: StoredMessage,
  ): Promise<void> => {
    const [row] = await call<{ fail_job: string | null }>("fail_job", [
      queueName,
      id,
      attempts,
      error.slice(0, 2000),
      backoffSeconds(attempt),
    ]);

    if (row?.fail_job === "dead") {
      await deadLetter({
        jobId: id,
        attempts,
        error,
        queueName: message?.queueName ?? queueName,
        ...(message === undefined
          ? {}
          : { messageId: message.messageId, runId: runIdOf(message) }),
      });
    }
  };

  /**
   * Tells `onDeadLetter` that a message gave up; the hook can't fail a
   * delivery.
   */
  const deadLetter = async (info: DeadLetter): Promise<void> => {
    logger.error("A workflow message was dead-lettered", { ...info });

    try {
      await options.onDeadLetter?.(info);
    } catch (cause) {
      logger.error("onDeadLetter threw", { error: cause });
    }
  };

  const heartbeat = (id: string, attempts: number): (() => void) => {
    const timer = setInterval(
      () => {
        void call("extend_job_lease", [queueName, id, attempts, lease]).catch(
          () => undefined,
        );
      },
      Math.max(1000, (lease * 1000) / 2),
    );

    return () => {
      clearInterval(timer);
    };
  };

  /** Settles a delivered job from the flow route's response. */
  const settle = async (
    job: { readonly id: string; readonly attempts: number },
    message: StoredMessage,
    attempt: number,
    status: number,
    text: string,
  ): Promise<void> => {
    if (status < 200 || status >= 300) {
      await fail(
        job.id,
        job.attempts,
        `Flow route answered ${String(status)}: ${text}`,
        attempt,
        message,
      );

      return;
    }

    let timeoutSeconds: number | undefined;

    try {
      const parsed: unknown = JSON.parse(text);

      if (
        typeof parsed === "object" &&
        parsed !== null &&
        "timeoutSeconds" in parsed
      ) {
        const value = Number(parsed.timeoutSeconds);

        if (Number.isFinite(value) && value >= 0) {
          timeoutSeconds = value;
        }
      }
    } catch {
      timeoutSeconds = undefined;
    }

    if (timeoutSeconds !== undefined) {
      await store({ ...message, attempt: attempt + 1 }, timeoutSeconds);
    }

    await complete(job.id, job.attempts);
  };

  const deliveryHeaders = (
    message: StoredMessage,
    attempt: number,
    deliveryCount: number,
  ): Headers => {
    const headers = new Headers(message.headers);
    headers.set("content-type", "application/json");
    headers.set("x-vqs-queue-name", message.queueName);
    headers.set("x-vqs-message-id", message.messageId);
    headers.set("x-vqs-message-attempt", String(attempt));
    headers.set("x-vqs-message-delivery-count", String(deliveryCount));

    if (message.createdAt === undefined) {
      headers.delete("x-vqs-message-created-at");
    } else {
      headers.set("x-vqs-message-created-at", message.createdAt);
    }

    headers.delete(JOB_HEADER);
    headers.delete(SIGNATURE_HEADER);

    return headers;
  };

  const flowUrl = (): string => resolveFlowUrl(options.flowUrl);

  type RouteHandler = (req: Request) => Promise<Response>;

  const handlers = new Map<QueuePrefix, RouteHandler>();
  const routes = new Map<QueuePrefix, string>();

  /** The entry of the longest prefix `queueName` starts with. */
  const byPrefix = <T>(
    entries: ReadonlyMap<QueuePrefix, T>,
    queueName: string,
  ): T | undefined => {
    let found: T | undefined;
    let length = -1;

    for (const [prefix, value] of entries) {
      if (queueName.startsWith(prefix) && prefix.length > length) {
        found = value;
        length = prefix.length;
      }
    }

    return found;
  };

  /**
   * Sends a message to the handler registered for its prefix in this process,
   * else to its registered route, else to the flow route.
   */
  const post = (
    queueName: string,
    init: RequestInit & { readonly signal: AbortSignal },
  ): Promise<Response> => {
    const handler = byPrefix(handlers, queueName);

    if (handler !== undefined) {
      return handler(new Request(flowUrl(), init));
    }

    const route = byPrefix(routes, queueName);

    return fetch(
      route === undefined ? flowUrl() : new URL(route, flowUrl()),
      init,
    );
  };

  const deliver = async (job: ClaimedJob): Promise<void> => {
    const payload = job.message.payload;

    if (!isStoredMessage(payload)) {
      await fail(job.id, job.attempts, "Not a workflow message", 99);

      return;
    }

    const attempt = payload.attempt + job.attempts - 1;
    const body = Buffer.from(payload.body, "base64");
    const headers = deliveryHeaders(payload, attempt, job.attempts);
    const beat = heartbeat(job.id, job.attempts);
    const controller = new AbortController();

    const timer = setTimeout(() => {
      controller.abort(
        new Error(
          `The flow route did not answer within ${String(deliveryTimeout)} seconds`,
        ),
      );
    }, deliveryTimeout * 1000);

    const stop = (): void => {
      clearTimeout(timer);
      beat();
    };

    controller.signal.addEventListener("abort", stop, { once: true });

    try {
      const secret = await deliverySecret();

      if (secret !== undefined) {
        headers.set(
          SIGNATURE_HEADER,
          await signDelivery(secret, "", body.toString("utf-8")),
        );
      }

      const response = await post(payload.queueName, {
        method: "POST",
        headers,
        body,
        signal: controller.signal,
      });

      const text = await response.text();
      stop();
      await settle(job, payload, attempt, response.status, text);
    } catch (cause) {
      stop();
      await fail(
        job.id,
        job.attempts,
        cause instanceof Error ? cause.message : String(cause),
        attempt,
        payload,
      );
    }
  };

  const claim = (batch: number): Promise<ClaimedJob[]> =>
    call<Omit<ClaimedJob, "id"> & { readonly id: string | number }>(
      "claim_jobs",
      [queueName, lease, batch],
    ).then((rows) => rows.map((row) => ({ ...row, id: String(row.id) })));

  let running = false;
  let closed = false;
  let loop: Promise<void> | undefined;
  const inflight = new Set<Promise<void>>();
  let wake: (() => void) | undefined;

  const deliverOnce = async (): Promise<number> => {
    const jobs = await claim(concurrency);
    await Promise.all(jobs.map((job) => deliver(job)));

    return jobs.length;
  };

  const track = (job: ClaimedJob): void => {
    const task: Promise<void> = deliver(job)
      .catch(() => undefined)
      .finally(() => {
        inflight.delete(task);
        wake?.();
      });

    inflight.add(task);
  };

  /** Waits `pollInterval`, or until a delivery finishes and frees a slot. */
  const idle = (): Promise<void> =>
    new Promise<void>((resolve) => {
      const timer = setTimeout(done, pollInterval);

      function done(): void {
        clearTimeout(timer);
        wake = undefined;
        resolve();
      }

      wake = done;
    });

  const claimInto = async (room: number): Promise<number> => {
    try {
      const jobs = await claim(room);

      for (const job of jobs) {
        track(job);
      }

      return jobs.length;
    } catch {
      return 0;
    }
  };

  const isRunning = (): boolean => running;

  const poll = async (): Promise<void> => {
    while (isRunning()) {
      const room = concurrency - inflight.size;
      const claimed = room > 0 ? await claimInto(room) : 0;

      if (claimed === 0 || room <= claimed) {
        await idle();
      }
    }
  };

  function startPolling(): void {
    if (delivery !== "poll" || running || closed) {
      return;
    }

    running = true;
    loop = poll();
  }

  const createQueueHandler = (
    prefix: QueuePrefix,
    handler: Parameters<World["createQueueHandler"]>[1],
  ): ((req: Request) => Promise<Response>) => {
    const inner = base.createQueueHandler(prefix, handler);

    return async (req) => {
      const job = req.headers.get(JOB_HEADER);
      let secret: string | undefined;

      try {
        secret = await deliverySecret();
      } catch {
        return deliveryProblem(
          "network",
          "The workflow delivery secret could not be read from Vault",
        );
      }

      if (job === null) {
        if (secret === undefined && delivery === "poll") {
          if (allowUnsigned) {
            return inner(req);
          }

          return deliveryProblem(
            "unauthorized",
            "Unsigned workflow delivery: set WORKFLOW_DELIVERY_SECRET or the Vault secret workflow_delivery_secret",
          );
        }

        const text = await req.text();

        if (
          secret === undefined ||
          !(await verifyDelivery(
            secret,
            req.headers.get(SIGNATURE_HEADER),
            "",
            text,
          ))
        ) {
          return deliveryProblem("unauthorized", "Unsigned workflow delivery");
        }

        return inner(
          new Request(req.url, {
            method: "POST",
            headers: req.headers,
            body: text,
          }),
        );
      }

      const text = await req.text();

      if (
        secret === undefined ||
        !(await verifyDelivery(
          secret,
          req.headers.get(SIGNATURE_HEADER),
          job,
          text,
        ))
      ) {
        return deliveryProblem(
          "unauthorized",
          "Bad workflow delivery signature",
        );
      }

      const [jobQueue, id, readCount] = job.split(":");
      const attempts = Number(readCount);
      let payload: unknown;

      try {
        payload = JSON.parse(text);
      } catch {
        payload = undefined;
      }

      if (
        jobQueue !== queueName ||
        id === undefined ||
        !/^\d+$/.test(id) ||
        !Number.isInteger(attempts) ||
        !isStoredMessage(payload)
      ) {
        return deliveryProblem(
          "invalid_request",
          "Malformed workflow delivery",
        );
      }

      const claimed = { id, attempts };
      const attempt = payload.attempt + attempts - 1;
      const stop = heartbeat(id, attempts);

      try {
        const response = await inner(
          new Request(req.url, {
            method: "POST",
            headers: deliveryHeaders(payload, attempt, attempts),
            body: Buffer.from(payload.body, "base64"),
          }),
        );

        const answer = await response.text();
        await settle(claimed, payload, attempt, response.status, answer);

        return new Response(answer, {
          status: response.status,
          headers: response.headers,
        });
      } catch (cause) {
        await fail(
          id,
          attempts,
          cause instanceof Error ? cause.message : String(cause),
          attempt,
          payload,
        ).catch(() => undefined);
        throw cause;
      } finally {
        stop();
      }
    };
  };

  async function getEncryptionKeyForRun(
    run: string | { readonly runId: string },
  ): Promise<Uint8Array | undefined> {
    const master = await masterKey();

    if (master === undefined) {
      return undefined;
    }

    return deriveRunKey(master, typeof run === "string" ? run : run.runId);
  }

  return {
    ...base,
    analytics: createAnalytics(pool),
    // Every delivery carries the HMAC that createQueueHandler checks before the
    // runtime sees it, so the runtime's loopback key check has nothing to add.
    queueAuthMode: "skip",
    queue,
    queueBatch,
    createQueueHandler,
    // The base World's versions register with its graphile queue, which never
    // runs; poll delivery reads these instead. `pg_net` delivery posts every
    // message to the flow route.
    registerHandler(prefix, handler) {
      handlers.set(prefix, handler);
    },
    registerRoute(prefix, path) {
      routes.set(prefix, parseQueueRoute(path));
    },
    getEncryptionKeyForRun,
    deliverOnce,
    ...createMaintenance(call, (runId) => getEncryptionKeyForRun(runId)),
    async start() {
      await assertWorldMigrations();
      startPolling();
      await reenqueueActiveRuns(
        base.runs,
        queue,
        "better-supabase",
        options.namespace,
      );
    },
    async close() {
      closed = true;
      running = false;
      wake?.();
      await loop;
      await Promise.all(inflight);
      await base.close?.();

      if (options.pool === undefined) {
        await pool.end();
      }
    },
  };
}

/**
 * The World from the environment, the factory the Workflow SDK calls for
 * `WORKFLOW_TARGET_WORLD=better-supabase/workflow-sdk/world`: the connection
 * from `WORKFLOW_POSTGRES_URL`, `SUPABASE_DB_URL` or `DATABASE_URL`, and
 * `WORKFLOW_DELIVERY`, `WORKFLOW_FLOW_URL`, `WORKFLOW_DELIVERY_SECRET`,
 * `WORKFLOW_ENCRYPTION_KEY`, `WORKFLOW_DELIVERY_QUEUE`,
 * `WORKFLOW_QUEUE_NAMESPACE`, `WORKFLOW_POSTGRES_WORKER_CONCURRENCY`,
 * `WORKFLOW_POSTGRES_POLL_INTERVAL_MS`, and the pool settings
 * `WORKFLOW_POSTGRES_MAX_POOL_SIZE` (or `WORKFLOW_POSTGRES_MAX_CONNECTIONS`),
 * `WORKFLOW_POSTGRES_CONNECTION_TIMEOUT_MS`,
 * `WORKFLOW_POSTGRES_IDLE_TIMEOUT_MS`, `WORKFLOW_POSTGRES_STATEMENT_TIMEOUT_MS`
 * and `WORKFLOW_POSTGRES_IDLE_IN_TRANSACTION_TIMEOUT_MS`.
 */
export function createWorld(): SupabaseWorld {
  const options = worldOptionsFromEnv();
  const registry = worldRegistry();

  const key = JSON.stringify([
    options.connectionString ?? null,
    options.namespace ?? null,
    options.queue ?? null,
  ]);

  const existing = registry.get(key);

  if (existing !== undefined) {
    return existing;
  }

  const world = createSupabaseWorld(options);
  const close = world.close.bind(world);

  const shared: SupabaseWorld = {
    ...world,
    async close() {
      registry.delete(key);
      await close();
    },
  };

  registry.set(key, shared);

  return shared;
}
