import type {
  QueueProvider,
  QueueMessageBody,
  QueueMessageRow,
} from "./backends.ts";
import type { Job } from "./types.ts";

import { sqlOnly } from "./backends.ts";

/** What the backend reads of `@vercel/queue`'s message metadata. */
export interface VercelQueueMetadata {
  readonly messageId: string;
  readonly deliveryCount: number;
  readonly createdAt: Date;
  readonly expiresAt: Date;
}

/**
 * The part of a `PollingQueueClient` from `@vercel/queue` the backend uses,
 * typed structurally so the package stays an optional peer.
 */
export interface VercelQueueClient {
  send(
    topic: string,
    payload: unknown,
    options?: {
      readonly idempotencyKey?: string;
      readonly delaySeconds?: number;
    },
  ): PromiseLike<{ readonly messageId: string | null }>;
  receive(
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
  ): PromiseLike<{ readonly ok: boolean }>;
}

export interface VercelQueueProviderOptions {
  /** The consumer group that reads the topics. Default `better-supabase`. */
  readonly consumerGroup?: string;
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
}

const TOPIC = /^[A-Za-z0-9_-]+$/;

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
  const group = options.consumerGroup ?? "better-supabase";
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

  const topicOf = (queue: string): string => {
    if (!TOPIC.test(queue)) {
      throw new TypeError(
        `Vercel Queues topic names match ${TOPIC.source}, got "${queue}"`,
      );
    }

    return queue;
  };

  const key = (job: Job): string => `${job.queue}:${job.id}`;

  return {
    apiVersion: 1,
    name: "vercel-queues",
    leases: false,
    async send(queue, payload, delay, maxAttempts, dedupeKey) {
      const sent = await client.send(
        topicOf(queue),
        { payload: payload ?? {}, max_attempts: maxAttempts },
        {
          delaySeconds: delay,
          ...(dedupeKey === undefined ? {} : { idempotencyKey: dedupeKey }),
        },
      );

      return handleOf(sent.messageId);
    },
    read(queue, lease, batch) {
      const rows: QueueMessageRow[] = [];

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

        client
          .receive(topicOf(queue), group, handler, {
            limit: Math.min(Math.max(batch, 1), 10),
            visibilityTimeoutSeconds: Math.min(Math.max(lease, 30), 3600),
            retry: (_error, metadata) => {
              const afterSeconds = delays.get(metadata.messageId) ?? retryAfter;

              delays.delete(metadata.messageId);

              return { afterSeconds };
            },
          })
          .then(() => {
            if (timer !== undefined) {
              clearTimeout(timer);
            }

            finish();
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
    schedule: () => sqlOnly("schedule"),
    unschedule: () => sqlOnly("unschedule"),
  };
}
