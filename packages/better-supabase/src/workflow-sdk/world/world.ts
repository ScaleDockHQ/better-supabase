import type {
  MessageId,
  QueueBatchResult,
  QueueOptions,
  QueuePayload,
  QueuePrefix,
  ValidQueueName,
  World,
} from "@workflow/world";

import {
  getQueueTopicPrefix,
  mintedSpecVersion,
  parseQueueRoute,
  reenqueueActiveRuns,
} from "@workflow/world";
import { createWorld as createPostgresWorld } from "@workflow/world-postgres";
import { Pool } from "pg";

import type { EveSessionStore } from "../../eve/store.ts";
import type { WorkflowMaintenance } from "../run-keys.ts";
import type {
  ClaimedJob,
  DeadLetter,
  StoredMessage,
  SupabaseWorldOptions,
  WorldConnection,
} from "./types.ts";

import { consoleLogger } from "../../core/logger.ts";
import { memoized } from "../../core/optional-peer.ts";
import { sqlIdent } from "../../core/template.ts";
import { createEveSessionStore } from "../../eve/store.ts";
import { watchPoolErrors } from "../../postgres/pool-errors.ts";
import { usesTransactionPooler } from "../../postgres/pooler.ts";
import {
  WORKFLOW_DELIVERY_QUEUE,
  WORKFLOW_GRAPHILE_SCHEMA as GRAPHILE_SHIM_SCHEMA,
  WORKFLOW_VAULT_SECRETS,
} from "../../sql/modules/workflow-sdk.ts";
import { createAnalytics } from "./analytics.ts";
import {
  deriveRunKey,
  parseKeyRing,
  parseMasterKey,
  ringKeyFor,
  signDelivery,
  unsignedAllowed,
  verifyDelivery,
} from "./crypto.ts";
import { assertWorldMigrations } from "./drift.ts";
import {
  env,
  isServerless,
  parseHeaders,
  resolveFlowUrl,
  routeUrl,
  worldOptionsFromEnv,
} from "./env.ts";
import { createMaintenance } from "./maintenance.ts";
import {
  backoffSeconds,
  byPrefix,
  deliveryProblem,
  isStoredMessage,
  runIdOf,
  serialize,
  transactionStorage,
  worldRegistry,
} from "./messages.ts";
import { pollingStreamReader } from "./polling.ts";
import { clearOwedWake, sweepOwedWakes } from "./recovery.ts";
import {
  DEFAULT_STREAM_FLUSH_MS,
  JOB_HEADER,
  KEY_ID_ATTRIBUTE,
  MAX_DELIVERIES,
  SIGNATURE_HEADER,
} from "./types.ts";
import { createVercelDelivery, timeoutOf } from "./vercel-delivery.ts";
import { loadVercelQueue } from "./vercel-queue.ts";

/** The World plus the delivery helpers the tests and routes use. */
export type SupabaseWorld = World &
  WorkflowMaintenance & {
    /** The eve projection's lease and cursor functions, for `syncSession`. */
    readonly eveSessions: EveSessionStore;
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

  const connectionString =
    options.connectionString ??
    env("WORKFLOW_POSTGRES_URL") ??
    env("SUPABASE_DB_URL") ??
    env("DATABASE_URL");

  const pooled = usesTransactionPooler(connectionString);

  const connection: WorldConnection =
    options.connection ?? (pooled ? "transaction" : "session");

  const pool =
    options.pool ??
    new Pool({
      connectionString,
      max: Math.max(1, options.maxConnections ?? (isServerless() ? 2 : 10)),
      connectionTimeoutMillis: options.connectionTimeout ?? 30_000,
      idleTimeoutMillis: options.idleTimeout ?? 10_000,
      statement_timeout: options.statementTimeout ?? 30_000,
      idle_in_transaction_session_timeout:
        options.idleInTransactionTimeout ?? 15_000,
    });

  const logger = options.logger ?? consoleLogger;
  const recoverAfter = Math.max(5, options.recoverAfter ?? 300);
  const skipWorkers = options.skipWorkers === true;

  // world-postgres reads it at call time for the add_job of a zero-retention
  // run's purge backstop; the SQL module defines that add_job in workflow.
  const graphileSchema = env("GRAPHILE_WORKER_SCHEMA");

  if (graphileSchema === undefined) {
    process.env["GRAPHILE_WORKER_SCHEMA"] = GRAPHILE_SHIM_SCHEMA;
  } else if (graphileSchema !== GRAPHILE_SHIM_SCHEMA) {
    logger.warn(
      `GRAPHILE_WORKER_SCHEMA is "${graphileSchema}": the workflow World sends the purge backstops of zero-retention runs to that schema's add_job, where no runner of this World claims them. Unset it or set it to "${GRAPHILE_SHIM_SCHEMA}".`,
    );
  }

  if (delivery === "poll" && env("VERCEL") !== undefined) {
    logger.warn(
      'The workflow World delivers with "poll" on Vercel, where messages are only claimed while a function instance runs. Set delivery: "vercel-queue" (or "pg_net" with a flow URL Supabase can reach).',
    );
  }

  if (options.pool === undefined && pooled && connection === "session") {
    logger.warn(
      'The workflow World connects through the transaction pooler (port 6543) with connection: "session". Streams, run status waits and run event feeds need LISTEN, which only a session connection (port 5432 or the session pooler) supports; use connection: "transaction" or a session URL.',
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
    streamFlushIntervalMs:
      options.streamFlushIntervalMs ?? DEFAULT_STREAM_FLUSH_MS,
    ...(skipWorkers ? { skipWorkers } : {}),
  });

  const poller =
    connection === "transaction"
      ? pollingStreamReader(pool, options.streamPollInterval)
      : undefined;

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

  /** Headers added to each post to the flow route; ours win over these. */
  const extraHeaders = memoized(
    async (): Promise<Readonly<Record<string, string>>> => {
      if (options.deliveryHeaders !== undefined) {
        return options.deliveryHeaders;
      }

      try {
        return (
          parseHeaders(await vault(WORKFLOW_VAULT_SECRETS.deliveryHeaders)) ??
          {}
        );
      } catch {
        return {};
      }
    },
  );

  const vercelSdk = memoized(
    async () => options.vercelQueue ?? loadVercelQueue(),
  );

  const keyRing = memoized(async () => {
    const ring =
      options.encryptionKeys ??
      (options.encryptionKey === undefined
        ? await vault(WORKFLOW_VAULT_SECRETS.encryptionKeys)
        : undefined);

    if (ring !== undefined) {
      return parseKeyRing(ring);
    }

    const text =
      options.encryptionKey ??
      (await vault(WORKFLOW_VAULT_SECRETS.encryptionKey));

    return text === undefined
      ? undefined
      : [{ id: "default", key: parseMasterKey(text), from: 0 }];
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

  const vercel = createVercelDelivery({
    sdk: vercelSdk,
    logger,
    queueName,
    deadLetter: (info) => deadLetter(info),
    clearWake: (message) => clearWake(message),
    headers: (message, attempt, count) =>
      deliveryHeaders(message, attempt, count),
    flowUrl: () => flowUrl(),
    isStoredMessage,
    runIdOf,
    backoffSeconds,
  });

  const enqueueStored = (
    message: StoredMessage,
    delaySeconds: number | undefined,
  ): Promise<void> =>
    delivery === "vercel-queue"
      ? vercel.send(message, delaySeconds)
      : store(message, delaySeconds);

  let dispatching = false;

  /**
   * Gets due messages moving at once: wakes the poller, or asks pg_net to
   * dispatch now instead of at the next cron tick. A failed dispatch is left to
   * the cron job.
   */
  const kick = async (delaySeconds: number): Promise<void> => {
    // The runtime never calls start(), so the process that queues also polls.
    startPolling();

    if (delaySeconds > 0) {
      return;
    }

    if (delivery === "poll") {
      wake?.();

      return;
    }

    if (delivery === "pg_net" && !dispatching) {
      dispatching = true;

      try {
        await call("dispatch_workflow_deliveries", []);
      } catch {
        // The cron schedule dispatches it.
      } finally {
        dispatching = false;
      }
    }
  };

  const queue = async (
    name: ValidQueueName,
    message: QueuePayload,
    opts?: QueueOptions,
  ): Promise<{ messageId: MessageId }> => {
    // SAFETY: MessageId is a branded string; any id the queue mints is valid.
    const messageId = `msg_${crypto.randomUUID()}` as MessageId;
    await enqueueStored(
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
    await kick(opts?.delaySeconds ?? 0);

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

    if (delivery === "vercel-queue") {
      return vercel.sendBatch(prepared);
    }

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

    await kick(Math.min(...prepared.map(({ delay }) => delay)));

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

  const orchestratorPrefix = getQueueTopicPrefix(
    "workflow",
    options.namespace ?? env("WORKFLOW_QUEUE_NAMESPACE"),
  );

  const clearWake = (message: StoredMessage): Promise<void> =>
    clearOwedWake(pool, orchestratorPrefix, message);

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

    const timeoutSeconds = timeoutOf(text);

    if (timeoutSeconds !== undefined) {
      // A continuation starts `attempt` over, as world-postgres does for
      // everything but a spec 9 orchestrator message: core fails a run past
      // 48 deliveries of one message, and a long run hops far more often.
      await store({ ...message, attempt: 1 }, timeoutSeconds);
    }

    await complete(job.id, job.attempts);

    if (timeoutSeconds === undefined) {
      await clearWake(message);
    }
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
      route === undefined ? flowUrl() : routeUrl(route, flowUrl()),
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

    for (const [name, value] of Object.entries(await extraHeaders())) {
      if (!headers.has(name)) {
        headers.set(name, value);
      }
    }

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

  const sweepOwed = (): Promise<number> =>
    sweepOwedWakes({
      pool,
      queue,
      logger,
      recoverAfter,
      prefix: orchestratorPrefix,
    });

  const maintenance = createMaintenance(call, (runId) =>
    getEncryptionKeyForRun(runId),
  );

  const deliverOnce = async (): Promise<number> => {
    await sweepOwed().catch(() => 0);
    await maintenance.purgeBackstops().catch(() => 0);

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
    running
      ? new Promise<void>((resolve) => {
          const timer = setTimeout(done, pollInterval);

          function done(): void {
            clearTimeout(timer);
            wake = undefined;
            resolve();
          }

          wake = done;
        })
      : Promise.resolve();

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

  let lastSweep = 0;

  const poll = async (): Promise<void> => {
    while (isRunning()) {
      if (Date.now() - lastSweep >= Math.max(30_000, recoverAfter * 500)) {
        lastSweep = Date.now();
        await sweepOwed().catch(() => 0);
        await maintenance.purgeBackstops().catch(() => 0);
      }

      const room = concurrency - inflight.size;
      const claimed = room > 0 ? await claimInto(room) : 0;

      if (claimed === 0 || room <= claimed) {
        await idle();
      }
    }
  };

  function startPolling(): void {
    if (delivery !== "poll" || skipWorkers || running || closed) {
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

    if (delivery === "vercel-queue") {
      return vercel.handler(inner);
    }

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

  /**
   * Run data is plain text without a key; say so once at startup unless the
   * process runs in development or test.
   */
  async function warnWithoutKey(): Promise<void> {
    const mode = env("NODE_ENV");

    if (mode === "development" || mode === "test") {
      return;
    }

    try {
      if ((await keyRing()) === undefined) {
        logger.warn(
          "The workflow World has no encryption key, so run inputs, outputs and stream data are stored unencrypted. Set WORKFLOW_ENCRYPTION_KEYS (or the Vault secret workflow_encryption_keys).",
        );
      }
    } catch (cause) {
      logger.error("The workflow encryption key could not be read", {
        error: cause,
      });
    }
  }

  async function getEncryptionKeyForRun(
    run: string | { readonly runId: string },
  ): Promise<Uint8Array | undefined> {
    const ring = await keyRing();

    if (ring === undefined) {
      return undefined;
    }

    const runId = typeof run === "string" ? run : run.runId;
    const stored = ring.length > 1 ? await storedKeyId(runId) : undefined;
    const entry = ring.find((candidate) => candidate.id === stored);

    return deriveRunKey((entry ?? ringKeyFor(ring, runId)).key, runId);
  }

  /**
   * Run ids to the id of the ring key stamped on them; a run keeps its key
   * through a rotation.
   */
  const stampedKeys = new Map<string, string | undefined>();

  async function storedKeyId(runId: string): Promise<string | undefined> {
    if (stampedKeys.has(runId)) {
      return stampedKeys.get(runId);
    }

    const result = await pool.query<{ id: string | null }>(
      `select attributes->>$2 as id from workflow.workflow_runs where id = $1`,
      [runId, KEY_ID_ATTRIBUTE],
    );

    const id = result.rows[0]?.id ?? undefined;

    if (id !== undefined) {
      if (stampedKeys.size >= 1000) {
        stampedKeys.clear();
      }

      stampedKeys.set(runId, id);
    }

    return id;
  }

  /**
   * Writes the id of the ring key a new run uses into its attributes. The key
   * is derived from the run's creation time, so without the stamp, editing the
   * ring's `from` dates would change the key of runs that already exist.
   */
  async function stampKeyId(runId: string): Promise<void> {
    const ring = await keyRing();

    if (ring === undefined) {
      return;
    }

    const id = ringKeyFor(ring, runId).id;
    stampedKeys.set(runId, id);
    await pool.query(
      `update workflow.workflow_runs
       set attributes = coalesce(attributes, '{}'::jsonb) || jsonb_build_object($2::text, $3::text)
       where id = $1 and not coalesce(attributes ? $2::text, false)`,
      [runId, KEY_ID_ATTRIBUTE, id],
    );
  }

  // SAFETY: `create` is overloaded over its event types; this view keeps one loose signature,
  // and the call below forwards every argument unchanged.
  const looseEvents = base.events as {
    readonly create: (...rest: unknown[]) => Promise<unknown>;
  };

  const forwardCreate = (...args: unknown[]): Promise<unknown> =>
    looseEvents.create(...args);

  const wrapped = async (...args: unknown[]): Promise<unknown> => {
    const result = await forwardCreate(...args);
    const data = args[1];

    const created =
      typeof data === "object" &&
      data !== null &&
      "eventType" in data &&
      data.eventType === "run_created";

    if (
      created &&
      typeof result === "object" &&
      result !== null &&
      "run" in result
    ) {
      const run: unknown = result.run;

      if (
        typeof run === "object" &&
        run !== null &&
        "runId" in run &&
        typeof run.runId === "string"
      ) {
        await stampKeyId(run.runId).catch((cause: unknown) => {
          logger.error("The run's encryption key id could not be stored", {
            error: cause,
          });
        });
      }
    }

    return result;
  };

  // SAFETY: `create` is overloaded over its event types; the wrapper forwards every argument and
  // returns the base World's result unchanged.
  const createEvent = wrapped as typeof base.events.create;

  return {
    ...base,
    ...(poller === undefined ? {} : transactionStorage(base, poller)),
    events: {
      ...(poller === undefined
        ? base.events
        : transactionStorage(base, poller).events),
      create: createEvent,
    },
    analytics: createAnalytics(pool),
    // The queue is a pgmq table that runs any number of a run's messages at
    // once and takes no run delivery lease, so the World declares neither
    // `maxConcurrency` nor `inBandFence` and mints spec 8 runs whatever
    // `WORKFLOW_SPEC_VERSION` says (ADR 1106).
    capabilities: {
      ...base.capabilities,
      maxConcurrency: false,
      inBandFence: false,
    },
    specVersion: mintedSpecVersion(),
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
    ...maintenance,
    eveSessions: createEveSessionStore(call),
    async start() {
      await assertWorldMigrations();
      await warnWithoutKey();

      if (skipWorkers) {
        return;
      }

      startPolling();
      await sweepOwed().catch(() => 0);
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
      poller?.close();
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
