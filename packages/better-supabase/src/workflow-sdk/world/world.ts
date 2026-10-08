import type {
  MessageId,
  QueueOptions,
  QueueBatchResult,
  QueuePayload,
  QueuePrefix,
  ValidQueueName,
  World,
} from "@workflow/world";

import { reenqueueActiveRuns } from "@workflow/world";
import { createWorld as createPostgresWorld } from "@workflow/world-postgres";
import { Pool } from "pg";

import { sqlIdent } from "../../core/template.ts";
import { WORLD_POSTGRES_VERSION } from "../../sql/modules/workflow-sdk-world-ddl.generated.ts";
import {
  WORKFLOW_DELIVERY_QUEUE,
  WORKFLOW_VAULT_SECRETS,
  type WorkflowDeliveryMode,
} from "../../sql/modules/workflow-sdk-world.ts";
import { createAnalytics } from "./analytics.ts";

/**
 * The `@workflow/world` protocol this World speaks: the package version its
 * types and queue format come from. Its tables come from
 * `@workflow/world-postgres` at `WORLD_POSTGRES_VERSION`.
 */
export const WORKFLOW_WORLD_PROTOCOL = "5.0.2";
export { WORLD_POSTGRES_VERSION };

export type { WorkflowDeliveryMode };

export interface SupabaseWorldOptions {
  /** A Postgres connection string with access to the `workflow` schema and the jobs functions. */
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
  /** The flow route the poller posts to. Defaults to `WORKFLOW_FLOW_URL`, then `WORKFLOW_LOCAL_BASE_URL` or `http://localhost:$PORT` plus `/.well-known/workflow/v1/flow`. */
  readonly flowUrl?: string;
  /**
   * The secret deliveries are signed with. Required to accept `pg_net`
   * deliveries; read from the Vault secret `workflow_delivery_secret` when
   * unset. A poller with a secret signs too, and the route then refuses
   * unsigned requests.
   */
  readonly deliverySecret?: string;
  /**
   * A 32-byte master key (base64 or hex) that each run's AES-256 key is
   * derived from (HKDF-SHA256). Read from the Vault secret
   * `workflow_encryption_key` when unset; without one, run data is stored
   * unencrypted.
   */
  readonly encryptionKey?: string;
  /** The jobs queue the messages wait in (`sql.modules.workflow-sdk-world.options.queue`). */
  readonly queue?: string;
  /** The schema of the jobs functions, default `better_supabase`. */
  readonly schema?: string;
  /** Deliveries in flight at once in poll mode (default 50). */
  readonly concurrency?: number;
  /** Milliseconds between polls of an empty queue (default 250). */
  readonly pollInterval?: number;
  /** Seconds a claimed message stays leased; the delivery extends it while it runs (default 60). */
  readonly lease?: number;
  /** The queue namespace, as `WORKFLOW_QUEUE_NAMESPACE`. */
  readonly namespace?: string;
}

/** The deliveries one message may take; matches world-postgres (49 plus 24 retries of the terminal write). */
const MAX_DELIVERIES = 73;
const SIGNATURE_TOLERANCE_SECONDS = 300;
const JOB_HEADER = "x-bs-job";
const SIGNATURE_HEADER = "x-bs-signature";
const FLOW_PATH = "/.well-known/workflow/v1/flow";
const HKDF_SALT = "better-supabase/workflow";

interface StoredMessage {
  readonly queueName: string;
  readonly messageId: string;
  readonly attempt: number;
  /** The serialized message, base64: jsonb can't hold the NUL bytes payloads may contain. */
  readonly body: string;
  readonly headers?: Readonly<Record<string, string>>;
  readonly idempotencyKey?: string;
}

interface ClaimedJob {
  readonly id: string;
  readonly attempts: number;
  readonly message: { readonly payload?: unknown };
}

const encoder = new TextEncoder();

/** JSON with Uint8Array values as `{ __type: "Uint8Array", data: <base64> }`, as world-postgres sends them. */
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
  if (typeof value !== "object" || value === null) return false;
  const record: Record<string, unknown> = { ...value };
  return (
    typeof record["queueName"] === "string" &&
    typeof record["messageId"] === "string" &&
    typeof record["attempt"] === "number" &&
    typeof record["body"] === "string"
  );
}

function env(name: string): string | undefined {
  const value = process.env[name];
  return value === undefined || value === "" ? undefined : value;
}

function positiveInt(value: string | undefined): number | undefined {
  const parsed = Math.trunc(Number(value ?? ""));
  return Number.isFinite(parsed) && parsed > 0 ? parsed : undefined;
}

/** The flow route: `flowUrl`, `WORKFLOW_FLOW_URL`, or the local server. */
export function resolveFlowUrl(flowUrl?: string): string {
  const explicit = flowUrl ?? env("WORKFLOW_FLOW_URL");
  if (explicit !== undefined) return explicit;
  const base =
    env("WORKFLOW_LOCAL_BASE_URL") ??
    `http://localhost:${env("PORT") ?? "3000"}`;
  const url = new URL(base);
  url.pathname = `${url.pathname.replace(/\/+$/, "")}${FLOW_PATH}`;
  url.search = "";
  url.hash = "";
  return url.toString();
}

/** A 32-byte key from base64 or hex. */
export function parseMasterKey(value: string): Uint8Array {
  const text = value.trim();
  const bytes = /^[0-9a-f]{64,}$/i.test(text)
    ? Buffer.from(text, "hex")
    : Buffer.from(text, "base64");
  if (bytes.byteLength < 32) {
    throw new TypeError(
      "better-supabase: the workflow encryption key must be at least 32 bytes, base64 or hex",
    );
  }
  return new Uint8Array(bytes);
}

/** The run's AES-256 key: HKDF-SHA256 of the master key with info `run:<runId>`. */
export async function deriveRunKey(
  master: Uint8Array,
  runId: string,
): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "raw",
    Uint8Array.from(master),
    "HKDF",
    false,
    ["deriveBits"],
  );
  const bits = await crypto.subtle.deriveBits(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: encoder.encode(HKDF_SALT),
      info: encoder.encode(`run:${runId}`),
    },
    key,
    256,
  );
  return new Uint8Array(bits);
}

async function hmacHex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(message),
  );
  return Buffer.from(signature).toString("hex");
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let index = 0; index < a.length; index += 1) {
    diff |= (a.codePointAt(index) ?? 0) ^ (b.codePointAt(index) ?? 0);
  }
  return diff === 0;
}

/** `t=<unix>,v1=<hex>` over `<t>.<job>.<body>`. */
export async function signDelivery(
  secret: string,
  job: string,
  body: string,
  now: number = Date.now(),
): Promise<string> {
  const t = String(Math.floor(now / 1000));
  return `t=${t},v1=${await hmacHex(secret, `${t}.${job}.${body}`)}`;
}

/** Whether `header` signs `job` and `body` with `secret` within five minutes of `now`. */
export async function verifyDelivery(
  secret: string,
  header: string | null,
  job: string,
  body: string,
  now: number = Date.now(),
): Promise<boolean> {
  if (header === null) return false;
  const parts = new Map(
    header.split(",").map((part) => {
      const index = part.indexOf("=");
      return [part.slice(0, index).trim(), part.slice(index + 1).trim()];
    }),
  );
  const t = parts.get("t");
  const v1 = parts.get("v1");
  if (t === undefined || v1 === undefined || !/^\d+$/.test(t)) return false;
  if (Math.abs(now / 1000 - Number(t)) > SIGNATURE_TOLERANCE_SECONDS) {
    return false;
  }
  return constantTimeEqual(await hmacHex(secret, `${t}.${job}.${body}`), v1);
}

/** Retry delay after a failed delivery, as world-postgres (exp(min(attempt, 10)) seconds). */
const backoffSeconds = (attempt: number): number =>
  Math.ceil(Math.exp(Math.min(attempt, 10)));

/** The World plus the delivery helpers the tests and routes use. */
export type SupabaseWorld = World & {
  start(): Promise<void>;
  close(): Promise<void>;
  /** Claims and delivers the due messages once (poll mode); resolves with how many it delivered. */
  deliverOnce(): Promise<number>;
};

/**
 * A Workflow SDK World on Supabase Postgres: the run, step, event, hook and
 * stream tables of `@workflow/world-postgres` (installed by the
 * `workflow-sdk-world` SQL module), with messages in the jobs module's
 * queue instead of graphile-worker.
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
  const pool =
    options.pool ??
    new Pool({
      connectionString:
        options.connectionString ??
        env("WORKFLOW_POSTGRES_URL") ??
        env("SUPABASE_DB_URL") ??
        env("DATABASE_URL"),
    });
  const base = createPostgresWorld({
    pool,
    ...(options.namespace === undefined
      ? {}
      : { namespace: options.namespace }),
  });

  const vault = async (name: string): Promise<string | undefined> => {
    const result = await pool.query<{ secret: string | null }>(
      "select decrypted_secret as secret from vault.decrypted_secrets where name = $1",
      [name],
    );
    return result.rows[0]?.secret ?? undefined;
  };
  let secretPromise: Promise<string | undefined> | undefined;
  const deliverySecret = (): Promise<string | undefined> =>
    (secretPromise ??=
      options.deliverySecret === undefined
        ? vault(WORKFLOW_VAULT_SECRETS.deliverySecret).catch(() => undefined)
        : Promise.resolve(options.deliverySecret));
  let masterPromise: Promise<Uint8Array | undefined> | undefined;
  const masterKey = (): Promise<Uint8Array | undefined> =>
    (masterPromise ??= (async () => {
      const text =
        options.encryptionKey ??
        (await vault(WORKFLOW_VAULT_SECRETS.encryptionKey).catch(
          () => undefined,
        ));
      return text === undefined ? undefined : parseMasterKey(text);
    })());

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
        if (Number.isFinite(value) && value >= 0) timeoutSeconds = value;
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
    const secret = await deliverySecret();
    if (secret !== undefined) {
      headers.set(
        SIGNATURE_HEADER,
        await signDelivery(secret, "", body.toString("utf8")),
      );
    }
    const stop = heartbeat(job.id, job.attempts);
    try {
      const response = await fetch(flowUrl(), {
        method: "POST",
        headers,
        body,
      });
      await settle(
        job,
        payload,
        attempt,
        response.status,
        await response.text(),
      );
    } catch (cause) {
      await fail(
        job.id,
        job.attempts,
        cause instanceof Error ? cause.message : String(cause),
        attempt,
      );
    } finally {
      stop();
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
      jobs.forEach(track);
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
      if (claimed === 0 || room <= claimed) await idle();
    }
  };

  function startPolling(): void {
    if (delivery !== "poll" || running || closed) return;
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
      const secret = await deliverySecret();
      if (job === null) {
        if (secret === undefined && delivery === "poll") return inner(req);
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
          return new Response("Unsigned workflow delivery", { status: 401 });
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
        return new Response("Bad workflow delivery signature", {
          status: 401,
        });
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
        return new Response("Malformed workflow delivery", { status: 400 });
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
    if (master === undefined) return undefined;
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
      if (options.pool === undefined) await pool.end();
    },
  };
}

/** The options `createWorld()` reads from the environment. */
export function worldOptionsFromEnv(
  source: Readonly<Record<string, string | undefined>> = process.env,
): SupabaseWorldOptions {
  const read = (name: string): string | undefined => {
    const value = source[name];
    return value === undefined || value === "" ? undefined : value;
  };
  const delivery = read("WORKFLOW_DELIVERY");
  if (delivery !== undefined && delivery !== "poll" && delivery !== "pg_net") {
    throw new TypeError(
      `better-supabase: WORKFLOW_DELIVERY must be "poll" or "pg_net", got "${delivery}"`,
    );
  }
  const connectionString =
    read("WORKFLOW_POSTGRES_URL") ??
    read("SUPABASE_DB_URL") ??
    read("DATABASE_URL");
  const flowUrl = read("WORKFLOW_FLOW_URL");
  const deliverySecret = read("WORKFLOW_DELIVERY_SECRET");
  const encryptionKey = read("WORKFLOW_ENCRYPTION_KEY");
  const queue = read("WORKFLOW_DELIVERY_QUEUE");
  const namespace = read("WORKFLOW_QUEUE_NAMESPACE");
  const concurrency = positiveInt(read("WORKFLOW_POSTGRES_WORKER_CONCURRENCY"));
  const pollInterval = positiveInt(read("WORKFLOW_POSTGRES_POLL_INTERVAL_MS"));
  return {
    ...(connectionString === undefined ? {} : { connectionString }),
    ...(delivery === undefined ? {} : { delivery }),
    ...(flowUrl === undefined ? {} : { flowUrl }),
    ...(deliverySecret === undefined ? {} : { deliverySecret }),
    ...(encryptionKey === undefined ? {} : { encryptionKey }),
    ...(queue === undefined ? {} : { queue }),
    ...(namespace === undefined ? {} : { namespace }),
    ...(concurrency === undefined ? {} : { concurrency }),
    ...(pollInterval === undefined ? {} : { pollInterval }),
  };
}

/**
 * The World from the environment, the factory the Workflow SDK calls for
 * `WORKFLOW_TARGET_WORLD=better-supabase/workflow-sdk/world`: the connection
 * from `WORKFLOW_POSTGRES_URL`, `SUPABASE_DB_URL` or `DATABASE_URL`, and
 * `WORKFLOW_DELIVERY`, `WORKFLOW_FLOW_URL`, `WORKFLOW_DELIVERY_SECRET`,
 * `WORKFLOW_ENCRYPTION_KEY`, `WORKFLOW_DELIVERY_QUEUE`,
 * `WORKFLOW_QUEUE_NAMESPACE`, `WORKFLOW_POSTGRES_WORKER_CONCURRENCY` and
 * `WORKFLOW_POSTGRES_POLL_INTERVAL_MS`.
 */
export function createWorld(): SupabaseWorld {
  return createSupabaseWorld(worldOptionsFromEnv());
}
