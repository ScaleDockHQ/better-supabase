import type { DbError } from "../../core/errors.ts";
import type { QueueMessageBody } from "./backends.ts";
import type {
  JobHandler,
  PayloadOut,
  Queue,
  QueueSchemas,
  RunJobOptions,
} from "./types.ts";
import type { VercelQueueMetadata } from "./vercel-queue.ts";

/** What a `retry` callback of `@vercel/queue` returns. */
export type VercelRetryDirective =
  | { readonly afterSeconds: number }
  | { readonly acknowledge: true };

type CallbackHandler = (
  message: unknown,
  metadata: VercelQueueMetadata & { readonly topicName: string },
) => Promise<void>;

interface CallbackOptions {
  readonly visibilityTimeoutSeconds?: number;
  readonly retry?: (
    error: unknown,
    metadata: VercelQueueMetadata,
  ) => VercelRetryDirective | undefined;
}

/**
 * The part of `@vercel/queue`'s `QueueClient` the route uses, typed
 * structurally so the package stays an optional peer. Pass `new QueueClient()`
 * or the module itself (`import * as queue from "@vercel/queue"`).
 */
export interface VercelQueueCallbackClient {
  handleCallback(
    handler: CallbackHandler,
    options?: CallbackOptions,
  ): (request: Request) => Promise<Response>;
}

/** A Connect-style request, with the body already parsed. */
export interface VercelNodeRequest {
  readonly method?: string;
  readonly headers: Record<string, string | string[] | undefined>;
  readonly body?: unknown;
}

/** A Connect-style response. */
export interface VercelNodeResponse {
  status(code: number): { json(data: unknown): void; end(): void };
  end(): void;
}

/** The `handleNodeCallback` of `QueueClient`, for `(req, res)` frameworks. */
export interface VercelQueueNodeCallbackClient {
  handleNodeCallback(
    handler: CallbackHandler,
    options?: CallbackOptions,
  ): (
    request: VercelNodeRequest,
    response: VercelNodeResponse,
  ) => Promise<void>;
}

export interface VercelQueueRouteOptions<
  Q extends QueueSchemas,
  C = VercelQueueCallbackClient,
> extends RunJobOptions {
  /** A handler per queue; the topic of a delivery names its queue. */
  readonly handlers: {
    readonly [N in Extract<keyof Q, string>]?: JobHandler<PayloadOut<Q, N>>;
  };
  readonly client: C;
  /**
   * Seconds before a failed delivery comes back, or a function of the attempt.
   * Default 30.
   */
  readonly retryAfter?: number | ((attempt: number) => number);
  /** The lock on each message while its handler runs. Default 300. */
  readonly visibilityTimeoutSeconds?: number;
  /**
   * Gets every handler error, with `dead: true` once the delivery was the last
   * attempt and the message is acknowledged without running again.
   */
  readonly onError?: (
    error: DbError,
    delivery: {
      readonly queue: string;
      readonly messageId: string;
      readonly attempt: number;
      readonly dead: boolean;
    },
  ) => void;
}

/**
 * A route handler for Vercel Queues push delivery: Vercel calls the route for
 * each message on the topics its `experimentalTriggers` name, and the route
 * runs the queue's handler through `jobs.runJob` (the schema check and tenant
 * context of `drain`). A failed delivery comes back after `retryAfter`; the
 * last of `maxAttempts` is acknowledged, since Vercel Queues keeps no dead
 * letters. Messages are the `{ payload, max_attempts }` bodies
 * `vercelQueueProvider` sends.
 */
export function vercelQueueRoute<Q extends QueueSchemas>(
  jobs: Queue<Q>,
  options: VercelQueueRouteOptions<Q>,
): (request: Request) => Promise<Response> {
  const consumer = consumerOf(jobs, options);

  return options.client.handleCallback(consumer.handler, consumer.options);
}

/**
 * `vercelQueueRoute` for frameworks with `(req, res)` handlers and a parsed
 * body (Express, the Next.js Pages Router), over `handleNodeCallback`.
 */
export function vercelQueueNodeRoute<Q extends QueueSchemas>(
  jobs: Queue<Q>,
  options: VercelQueueRouteOptions<Q, VercelQueueNodeCallbackClient>,
): (request: VercelNodeRequest, response: VercelNodeResponse) => Promise<void> {
  const consumer = consumerOf(jobs, options);

  return options.client.handleNodeCallback(consumer.handler, consumer.options);
}

function consumerOf<Q extends QueueSchemas, C>(
  jobs: Queue<Q>,
  options: VercelQueueRouteOptions<Q, C>,
): { readonly handler: CallbackHandler; readonly options: CallbackOptions } {
  const exhausted = new Set<string>();
  let deliveries = 0;

  const delayOf = (attempt: number): number => {
    const retryAfter = options.retryAfter ?? 30;

    return typeof retryAfter === "number" ? retryAfter : retryAfter(attempt);
  };

  const handler: CallbackHandler = async (message, metadata) => {
    const queue = metadata.topicName;
    // SAFETY: an unknown topic reads undefined, which the next line rejects.
    const run = options.handlers[queue as Extract<keyof Q, string>];

    if (run === undefined) {
      throw new TypeError(`No handler for the Vercel Queues topic "${queue}"`);
    }

    // SAFETY: vercelQueueProvider sends { payload, max_attempts } on every topic it writes.
    const body = (message ?? {}) as QueueMessageBody;
    const maxAttempts = body.max_attempts ?? 5;

    deliveries += 1;

    const result = await jobs.runJob({
      // SAFETY: the route registered `queue` from the `Q` keys.
      queue: queue as Extract<keyof Q, string>,
      delivery: {
        id: deliveries,
        attempts: metadata.deliveryCount,
        enqueuedAt: metadata.createdAt,
        message: body,
      },
      handler: run,
      ...options,
    });

    if (result.ok) {
      return;
    }

    const dead = metadata.deliveryCount >= maxAttempts;

    options.onError?.(result.error, {
      queue,
      messageId: metadata.messageId,
      attempt: metadata.deliveryCount,
      dead,
    });

    if (dead) {
      exhausted.add(metadata.messageId);
    }

    throw new Error(result.error.message, { cause: result.error });
  };

  return {
    handler,
    options: {
      visibilityTimeoutSeconds: options.visibilityTimeoutSeconds ?? 300,
      retry: (_error, metadata) => {
        if (exhausted.delete(metadata.messageId)) {
          return { acknowledge: true };
        }

        return { afterSeconds: delayOf(metadata.deliveryCount) };
      },
    },
  };
}
