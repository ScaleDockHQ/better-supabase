import type {
  QueueProvider,
  QueueMessageBody,
  QueueMessageRow,
} from "./backends.ts";
import type { Job } from "./types.ts";

import { DbException, dbError } from "../../core/errors.ts";
import { sqlOnly } from "./backends.ts";

/** What the backend reads of `@vercel/queue`'s message metadata. */
export interface VercelQueueMetadata {
  readonly messageId: string;
  readonly deliveryCount: number;
  readonly createdAt: Date;
  readonly expiresAt: Date;
  readonly topicName?: string;
  readonly consumerGroup?: string;
  readonly region?: string;
}

/**
 * The part of a `PollingQueueClient` from `@vercel/queue` the backend uses,
 * typed structurally so the package stays an optional peer. A `QueueClient` has
 * no `receive`: it sends, and `vercelQueueRoute` runs the pushed jobs.
 */
export interface VercelQueueClient {
  send(
    topic: string,
    payload: unknown,
    options?: {
      readonly idempotencyKey?: string;
      readonly delaySeconds?: number;
      readonly retentionSeconds?: number;
      readonly headers?: Readonly<Record<string, string>>;
    },
  ): PromiseLike<{ readonly messageId: string | null }>;
  receive?(
    topic: string,
    consumerGroup: string,
    handler: (
      message: unknown,
      metadata: VercelQueueMetadata,
    ) => PromiseLike<void> | void,
    options?: {
      readonly limit?: number;
      readonly visibilityTimeoutSeconds?: number;
      readonly retry?: (
        error: unknown,
        metadata: VercelQueueMetadata,
      ) =>
        | { readonly afterSeconds: number }
        | { readonly acknowledge: true }
        | undefined;
    },
  ): PromiseLike<VercelReceiveResult>;
}

/** What `receive` answers: `ok`, or why nothing was processed. */
export type VercelReceiveResult =
  | { readonly ok: true }
  | {
      readonly ok: false;
      readonly reason?:
        | "empty"
        | "not_found"
        | "not_available"
        | "already_processed";
    };

export interface VercelQueueProviderOptions {
  /**
   * The consumer group that reads the topics, or one per queue. Default
   * `better-supabase`.
   */
  readonly consumerGroup?: string | ((queue: string) => string);
  /**
   * Seconds a message is kept, clamped to 60 through 604800 (7 days). A delayed
   * message keeps at least its delay plus an hour. Default: the topic's 24
   * hours.
   */
  readonly retention?: number;
  /** Headers sent with every message, for consumers that route on them. */
  readonly headers?: Readonly<Record<string, string>>;
  /**
   * Seconds a failed message waits before redelivery when `fail` gives no
   * delay. Default 30.
   */
  readonly retryAfter?: number;
  /**
   * Milliseconds `read` waits for the rest of a batch after the first message.
   * Default 25.
   */
  readonly settle?: number;
  /**
   * Called after each `receive` with its result, so a drain can count empty
   * polls apart from messages another consumer holds.
   */
  readonly onReceive?: (queue: string, result: VercelReceiveResult) => void;
}

const TOPIC = /^[A-Za-z0-9_-]+$/;

const DAY = 86_400;
const MAX_RETENTION = 7 * DAY;

/**
 * The retention a message delayed by `delay` seconds needs: the default day, or
 * an hour past the delay, at most the 7-day cap. `undefined` without a delay,
 * so the topic's default applies.
 */
export function vercelRetentionSeconds(delay: number): number | undefined {
  if (delay <= 0) {
    return undefined;
  }

  if (delay > MAX_RETENTION) {
    throw new RangeError(
      `Vercel Queues delays messages at most ${String(MAX_RETENTION)} seconds (7 days), got ${String(delay)}`,
    );
  }

  return Math.min(Math.max(DAY, delay + 3600), MAX_RETENTION);
}

const MIN_RETENTION = 60;
const MAX_KEY = 256;

/**
 * The topic of a queue: `.` and `:` become `-`, so `billing.invoice` and
 * `tenant:sync` are valid topic names. Throws for any other character a topic
 * can't hold.
 */
export function vercelTopicOf(queue: string): string {
  const topic = queue.replaceAll(/[.:]/g, "-");

  if (!TOPIC.test(topic)) {
    throw new TypeError(
      `Vercel Queues topic names match ${TOPIC.source}, got "${queue}"`,
    );
  }

  return topic;
}

/**
 * An idempotency key Vercel Queues accepts: keys of at most 256 characters pass
 * through, longer ones become their SHA-256 hex digest.
 */
export async function vercelIdempotencyKey(key: string): Promise<string> {
  if (key.length <= MAX_KEY) {
    return key;
  }

  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(key),
  );

  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

/** What `send` passes to `@vercel/queue`. */
export interface VercelSendOptions {
  readonly delaySeconds: number;
  readonly retentionSeconds?: number;
  readonly idempotencyKey?: string;
  readonly headers?: Readonly<Record<string, string>>;
}

/**
 * The send options for a message delayed by `delay` seconds: the retention
 * clamped to 60 through 604800 and raised to cover the delay, the hashed
 * idempotency key and the headers. Throws a `RangeError` naming the limit for a
 * delay past 7 days.
 */
export async function vercelSendOptionsOf(
  delay: number,
  dedupeKey: string | undefined,
  options: Pick<VercelQueueProviderOptions, "retention" | "headers"> = {},
): Promise<VercelSendOptions> {
  const needed = vercelRetentionSeconds(delay);

  const configured =
    options.retention === undefined
      ? undefined
      : Math.min(Math.max(options.retention, MIN_RETENTION), MAX_RETENTION);

  const retentionSeconds =
    configured === undefined
      ? needed
      : Math.max(configured, needed === undefined ? 0 : delay + 3600);

  return {
    delaySeconds: delay,
    ...(retentionSeconds === undefined
      ? {}
      : { retentionSeconds: Math.min(retentionSeconds, MAX_RETENTION) }),
    ...(dedupeKey === undefined
      ? {}
      : { idempotencyKey: await vercelIdempotencyKey(dedupeKey) }),
    ...(options.headers === undefined ? {} : { headers: options.headers }),
  };
}

/** One Vercel Queues trigger of a route in `vercel.json`. */
export interface VercelQueueTrigger {
  readonly type: "queue/v2beta";
  readonly topic: string;
  readonly maxDeliveries?: number;
}

/**
 * The `functions` fragment of `vercel.json` that points the topics of `queues`
 * at `route`, so a push route receives them. `maxAttempts` caps deliveries, for
 * every queue or per queue.
 */
export function vercelQueueTriggers(
  route: string,
  queues: readonly string[],
  options: {
    readonly maxAttempts?: number | Readonly<Record<string, number>>;
  } = {},
): {
  readonly [route: string]: {
    readonly experimentalTriggers: readonly VercelQueueTrigger[];
  };
} {
  const triggers = queues.map((queue): VercelQueueTrigger => {
    const max =
      typeof options.maxAttempts === "number"
        ? options.maxAttempts
        : options.maxAttempts?.[queue];

    return {
      type: "queue/v2beta",
      topic: vercelTopicOf(queue),
      ...(max === undefined ? {} : { maxDeliveries: max }),
    };
  });

  return { [route]: { experimentalTriggers: triggers } };
}

interface Held {
  readonly metadata: VercelQueueMetadata;
  readonly done: () => void;
  readonly fail: (error: Error) => void;
}

/**
 * Stores jobs on Vercel Queues through a `PollingQueueClient`. Queue names are
 * topic names. `read` holds each message open inside the client's `receive`
 * handler (the client keeps the visibility timeout alive), `complete`
 * acknowledges it and `fail` throws so the topic redelivers it after the retry
 * delay. Vercel Queues has no dead letters, schedules or ids that fit a number,
 * so ids are local handles, a message past `maxAttempts` is acknowledged and
 * dropped, and schedules need the SQL backend.
 */
export function vercelQueueProvider(
  client: VercelQueueClient,
  options: VercelQueueProviderOptions = {},
): QueueProvider {
  const groupOf = (queue: string): string =>
    typeof options.consumerGroup === "function"
      ? options.consumerGroup(queue)
      : (options.consumerGroup ?? "better-supabase");

  const retryAfter = options.retryAfter ?? 30;
  const settle = options.settle ?? 25;
  const held = new Map<string, Held>();
  const delays = new Map<string, number>();
  const handles = new Map<string, number>();
  let next = 0;

  // Numbers are local handles for Vercel's string message ids, stable within a process.
  const handleOf = (messageId: string | null): number => {
    const known = messageId === null ? undefined : handles.get(messageId);

    if (known !== undefined) {
      return known;
    }

    next += 1;

    if (messageId !== null) {
      handles.set(messageId, next);
    }

    return next;
  };

  const key = (job: Job): string => `${job.queue}:${job.id}`;

  return {
    apiVersion: 1,
    name: "vercel-queues",
    leases: false,
    async send(queue, payload, delay, maxAttempts, dedupeKey) {
      const sent = await client.send(
        vercelTopicOf(queue),
        { payload: payload ?? {}, max_attempts: maxAttempts },
        await vercelSendOptionsOf(delay, dedupeKey, options),
      );

      return handleOf(sent.messageId);
    },
    read(queue, lease, batch) {
      const rows: QueueMessageRow[] = [];
      const receive = client.receive?.bind(client);

      if (receive === undefined) {
        return Promise.reject(
          new TypeError(
            "This Vercel Queues client only sends; push delivery runs jobs through vercelQueueRoute, or pass a PollingQueueClient to poll",
          ),
        );
      }

      return new Promise((resolve, reject) => {
        let timer: ReturnType<typeof setTimeout> | undefined;

        const finish = (): void => {
          resolve([...rows]);
        };

        const handler = (
          message: unknown,
          metadata: VercelQueueMetadata,
        ): Promise<void> => {
          const id = handleOf(metadata.messageId);

          rows.push({
            id,
            attempts: metadata.deliveryCount,
            enqueued_at: metadata.createdAt,
            visible_until: new Date(Date.now() + lease * 1000),
            // SAFETY: send() wrote this body, so a topic of this backend holds { payload, max_attempts }.
            message: message as QueueMessageBody,
          });

          return new Promise<void>((done, failed) => {
            held.set(`${queue}:${id}`, {
              metadata,
              done: () => {
                done();
              },
              fail: (error) => {
                failed(error);
              },
            });
            timer ??= setTimeout(finish, settle);
          });
        };

        void receive(vercelTopicOf(queue), groupOf(queue), handler, {
          limit: Math.min(Math.max(batch, 1), 10),
          visibilityTimeoutSeconds: Math.min(Math.max(lease, 30), 3600),
          retry: (_error, metadata) => {
            const afterSeconds = delays.get(metadata.messageId) ?? retryAfter;

            delays.delete(metadata.messageId);

            return { afterSeconds };
          },
        }).then((result) => {
          if (timer !== undefined) {
            clearTimeout(timer);
          }

          options.onReceive?.(queue, result);
          finish();

          return result;
        }, reject);
      });
    },
    complete(job) {
      const entry = held.get(key(job));

      if (!entry) {
        return Promise.resolve(false);
      }

      held.delete(key(job));
      entry.done();

      return Promise.resolve(true);
    },
    fail(job, error, retryIn) {
      const entry = held.get(key(job));

      if (!entry) {
        return Promise.resolve(null);
      }

      held.delete(key(job));

      if (job.attempts >= job.maxAttempts) {
        entry.done();

        return Promise.resolve("dead");
      }

      if (retryIn !== undefined) {
        delays.set(entry.metadata.messageId, retryIn);
      }

      entry.fail(new Error(error));

      return Promise.resolve("queued");
    },
    extend: () => Promise.resolve(false),
    stats: () =>
      Promise.reject(
        new DbException(
          dbError(
            "invalid_request",
            "Vercel Queues returns no queue counts through its API; read them in the Vercel dashboard under Observability, Queues",
          ),
        ),
      ),
    schedule: () => sqlOnly("schedule"),
    unschedule: () => sqlOnly("unschedule"),
  };
}
