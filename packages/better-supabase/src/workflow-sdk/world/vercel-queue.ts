import { isRecord } from "../../core/guards.ts";
import { importOptionalPeer } from "../../core/optional-peer.ts";

/** What a delivery's `metadata` holds of `@vercel/queue`'s message metadata. */
export interface VercelDeliveryMetadata {
  readonly messageId: string;
  readonly deliveryCount: number;
  readonly createdAt?: Date;
}

/** What `retry` of `handleCallback` answers. */
export type VercelRetryDirective =
  | { readonly afterSeconds: number }
  | { readonly acknowledge: true };

export interface VercelSendOptions {
  readonly delaySeconds?: number;
  readonly retentionSeconds?: number;
  readonly idempotencyKey?: string;
  readonly headers?: Readonly<Record<string, string>>;
}

/** One message's outcome in a `sendBatch`, in the order sent. */
export type VercelBatchResult =
  | { readonly status: "sent"; readonly messageId: string }
  | { readonly status: "deferred"; readonly messageId: null }
  | {
      readonly status: "failed";
      readonly statusCode: number;
      readonly error: string;
      /** Absent in `@vercel/queue` releases before it reported this. */
      readonly retryable?: boolean;
    };

/**
 * The part of `@vercel/queue`'s `QueueClient` the World uses, typed
 * structurally so the package stays an optional peer. Pass `new QueueClient()`
 * as `vercelQueue` to configure the client yourself.
 */
export interface VercelQueueSdk {
  send(
    topic: string,
    payload: unknown,
    options?: VercelSendOptions,
  ): PromiseLike<{ readonly messageId: string | null }>;
  sendBatch?(
    topic: string,
    messages: readonly ({ readonly payload: unknown } & VercelSendOptions)[],
  ): PromiseLike<readonly VercelBatchResult[]>;
  handleCallback(
    handler: (
      message: unknown,
      metadata: VercelDeliveryMetadata,
    ) => Promise<void>,
    options?: {
      readonly visibilityTimeoutSeconds?: number;
      readonly retry?: (
        error: unknown,
        metadata: VercelDeliveryMetadata,
      ) => VercelRetryDirective | undefined;
    },
  ): (request: Request) => Promise<Response>;
}

/** Vercel Queues delays a message at most 23 hours. */
export const VERCEL_MAX_DELAY_SECONDS: number = 23 * 3600;

/** Vercel Queues redelivers a failed message after 5 through 900 seconds. */
const VERCEL_MIN_RETRY_SECONDS: number = 5;

const VERCEL_MAX_RETRY_SECONDS: number = 900;

const MAX_RETENTION_SECONDS = 7 * 86_400;

/**
 * The topic of a queue name: characters Vercel Queues rejects become `-`, as
 * `@workflow/world-vercel` does, so the `__wkf_workflow_*` triggers the
 * Workflow SDK's builders write match.
 */
export function vercelTopicOf(queueName: string): string {
  return queueName.replaceAll(/[^A-Za-z0-9_-]/g, "-");
}

/**
 * The first hop of a delay: Vercel Queues delays at most 23 hours, so a longer
 * delay is sent as that, and `remaining` is what the receiving hop sends on.
 */
export function chainDelay(delaySeconds: number): {
  readonly delaySeconds: number;
  readonly remaining: number;
} {
  const total = Math.max(0, Math.ceil(delaySeconds));
  const hop = Math.min(total, VERCEL_MAX_DELAY_SECONDS);

  return { delaySeconds: hop, remaining: total - hop };
}

/**
 * The retention a message needs: the delay plus an hour, clamped to the 7 day
 * cap, so a delayed message does not expire before it is due. `undefined`
 * without a delay lets the topic's default apply.
 */
export function retentionFor(delaySeconds: number): number | undefined {
  return delaySeconds <= 0
    ? undefined
    : Math.min(Math.max(86_400, delaySeconds + 3600), MAX_RETENTION_SECONDS);
}

/** The seconds a failed delivery waits: `backoff` clamped to Vercel's range. */
export function retryAfterSeconds(backoff: number): number {
  return Math.min(
    VERCEL_MAX_RETRY_SECONDS,
    Math.max(VERCEL_MIN_RETRY_SECONDS, Math.ceil(backoff)),
  );
}

/**
 * An idempotency key Vercel Queues accepts: keys of at most 256 characters pass
 * through, longer ones become their SHA-256 hex digest.
 */
export async function vercelIdempotencyKey(key: string): Promise<string> {
  if (key.length <= 256) {
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

function isQueueSdk(value: unknown): value is VercelQueueSdk {
  return (
    isRecord(value) &&
    typeof value["send"] === "function" &&
    typeof value["handleCallback"] === "function"
  );
}

/**
 * `new QueueClient()` from `@vercel/queue`, which reads the deployment's
 * credentials from the environment. The import is lazy so apps that deliver
 * with `poll` or `pg_net` never need the package; without it the call rejects
 * with an install message.
 */
export async function loadVercelQueue(): Promise<VercelQueueSdk> {
  const loaded = await importOptionalPeer("@vercel/queue");

  if (isRecord(loaded) && typeof loaded["QueueClient"] === "function") {
    const client: unknown = Reflect.construct(loaded["QueueClient"], []);

    if (isQueueSdk(client)) {
      return client;
    }
  }

  throw new Error(
    'delivery: "vercel-queue" needs the optional peer @vercel/queue (0.11 or later): install it, or pass a client as vercelQueue',
  );
}
