import {
  reenqueueActiveRuns,
  type MessageId,
  type QueueBatchResult,
  type QueueOptions,
  type QueuePayload,
  type QueuePrefix,
  type ValidQueueName,
  type World,
} from "@workflow/world";
import { createWorld as createPostgresWorld } from "@workflow/world-postgres";
import { Pool } from "pg";

import { dbError } from "../../core/errors.ts";
import { memoized } from "../../core/optional-peer.ts";
import { problemResponse } from "../../core/problem.ts";
import { sqlIdent } from "../../core/template.ts";
import { watchPoolErrors } from "../../postgres/pool-errors.ts";
import {
  WORKFLOW_DELIVERY_QUEUE,
  WORKFLOW_VAULT_SECRETS,
} from "../../sql/modules/workflow-sdk-world.ts";
import { createAnalytics } from "./analytics.ts";
import {
  deriveRunKey,
  parseMasterKey,
  signDelivery,
  unsignedAllowed,
  verifyDelivery,
} from "./crypto.ts";
import { env, resolveFlowUrl, worldOptionsFromEnv } from "./env.ts";
import {
  JOB_HEADER,
  MAX_DELIVERIES,
  SIGNATURE_HEADER,
  type ClaimedJob,
  type StoredMessage,
  type SupabaseWorldOptions,
} from "./types.ts";

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

/** The World plus the delivery helpers the tests and routes use. */
export type SupabaseWorld = World & {
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
 * stream tables of `@workflow/world-postgres` (installed by the
 * `workflow-sdk-world` SQL module), with messages in the jobs module's queue
 * instead of graphile-worker.
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

  watchPoolErrors(pool, {
    ...(options.events ? { events: options.events } : {}),
    ...(options.logger ? { logger: options.logger } : {}),
  });

  const base = createPostgresWorld({
    pool,
    ...(options.namespace === undefined
      ? {}
      : { namespace: options.namespace }),
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

  const queueBatch = (
    name: ValidQueueName,
    messages: readonly { message: QueuePayload; opts?: QueueOptions }[],
  ): Promise<QueueBatchResult[]> =>
    Promise.all(
      messages.map(({ message, opts }) =>
        queue(name, message, opts).then(
          ({ messageId }): QueueBatchResult => ({ messageId }),
          (cause: unknown): QueueBatchResult => ({
            messageId: null,
            error: cause instanceof Error ? cause.message : String(cause),
            retryable: true,
          }),
        ),
      ),
    );

  const complete = (id: string, attempts: number): Promise<unknown> =>
    call("complete_job", [queueName, id, attempts]);

  const fail = (
    id: string,
    attempts: number,
    error: string,
    attempt: number,
  ): Promise<unknown> =>
    call("fail_job", [
      queueName,
      id,
      attempts,
      error.slice(0, 2000),
      backoffSeconds(attempt),
    ]);

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
  ): Headers => {
    const headers = new Headers(message.headers);
    headers.set("content-type", "application/json");
    headers.set("x-vqs-queue-name", message.queueName);
    headers.set("x-vqs-message-id", message.messageId);
    headers.set("x-vqs-message-attempt", String(attempt));
    headers.delete(JOB_HEADER);
    headers.delete(SIGNATURE_HEADER);

    return headers;
  };

  const flowUrl = (): string => resolveFlowUrl(options.flowUrl);

  const deliver = async (job: ClaimedJob): Promise<void> => {
    const payload = job.message.payload;

    if (!isStoredMessage(payload)) {
      await fail(job.id, job.attempts, "Not a workflow message", 99);

      return;
    }

    const attempt = payload.attempt + job.attempts - 1;
    const body = Buffer.from(payload.body, "base64");
    const headers = deliveryHeaders(payload, attempt);
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

      const response = await fetch(flowUrl(), {
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
            headers: deliveryHeaders(payload, attempt),
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
    queue,
    queueBatch,
    createQueueHandler,
    getEncryptionKeyForRun,
    deliverOnce,
    async start() {
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
 * `WORKFLOW_POSTGRES_MAX_CONNECTIONS`,
 * `WORKFLOW_POSTGRES_CONNECTION_TIMEOUT_MS`,
 * `WORKFLOW_POSTGRES_IDLE_TIMEOUT_MS`, `WORKFLOW_POSTGRES_STATEMENT_TIMEOUT_MS`
 * and `WORKFLOW_POSTGRES_IDLE_IN_TRANSACTION_TIMEOUT_MS`.
 */
export function createWorld(): SupabaseWorld {
  return createSupabaseWorld(worldOptionsFromEnv());
}
