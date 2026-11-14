import type { DbError } from "../../core/errors.ts";
import type { QueueMessageBody } from "./backends.ts";
import type {
  JobHandler,
  PayloadOut,
  Queue,
  QueueSchemas,
  RunJobOptions,
  ScheduledRun,
} from "./types.ts";
import type { VercelQueueMetadata } from "./vercel-queue.ts";
import type {
  VercelScheduleQueueMessage,
  VercelScheduleRun,
} from "./vercel-schedules.ts";

import { isRecord } from "../../core/guards.ts";
import { BLOCK_SCHEDULE_PREFIX, BLOCK_TICKS_QUEUE } from "./block-schedules.ts";
import {
  isVercelScheduleMessage,
  vercelScheduleNameFrom,
  vercelScheduleRunOf,
} from "./vercel-schedules.ts";

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
    // oxlint-disable-next-line typescript/no-unsafe-enum-assignment -- false positive: the key type is a string, not an enum (ADR 0634: 9 findings, tsgolint 7.0.2006 treats the mapped-type key as an enum)
    const run = options.handlers[queue as Extract<keyof Q, string>];

    if (run === undefined) {
      throw new TypeError(`No handler for the Vercel Queues topic "${queue}"`);
    }

    const scheduled = isVercelScheduleMessage(message)
      ? scheduledMessageOf(message)
      : undefined;

    // vercelQueueProvider sends { payload, max_attempts } on every topic it writes.
    const body: QueueMessageBody =
      scheduled === undefined ? (message ?? {}) : scheduled.body;

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
        ...(scheduled === undefined ? {} : { schedule: scheduled.run }),
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

/** What a Vercel schedule message carries for the job it runs. */
interface ScheduledMessage {
  /** The queue the run goes to; unset when the message doesn't say. */
  readonly queue: string | undefined;
  readonly body: QueueMessageBody;
  readonly probe: string | undefined;
  readonly run: ScheduledRun & VercelScheduleRun;
}

/**
 * A block timer's tick from its schedule name, `block:<block>.<timer>`. Block
 * names have no dots, so the first one ends the block.
 */
function blockTickOf(
  name: string,
): { readonly block: string; readonly name: string } | undefined {
  if (!name.startsWith(BLOCK_SCHEDULE_PREFIX)) {
    return undefined;
  }

  const rest = name.slice(BLOCK_SCHEDULE_PREFIX.length);
  const dot = rest.indexOf(".");

  return dot <= 0
    ? undefined
    : { block: rest.slice(0, dot), name: rest.slice(dot + 1) };
}

/**
 * Reads a schedule message: the job body `vercelScheduler` stored as the
 * payload, or, for a static schedule without one, a block timer's tick named by
 * the schedule (`block:<block>.<timer>`, encoded) or an empty payload.
 */
function scheduledMessageOf(
  message: VercelScheduleQueueMessage,
): ScheduledMessage {
  const run = vercelScheduleRunOf(message);

  if (run === null) {
    throw new TypeError(
      `The Vercel schedule run ${message.executionId} has an invalid scheduledAt "${message.scheduledAt}"`,
    );
  }

  const stored = message.payload;

  if (isRecord(stored) && Object.hasOwn(stored, "payload")) {
    const name =
      typeof stored["name"] === "string"
        ? stored["name"]
        : (vercelScheduleNameFrom(message.name) ?? message.name);

    return {
      queue: typeof stored["queue"] === "string" ? stored["queue"] : undefined,
      // SAFETY: vercelScheduler stores { payload, max_attempts, name, queue, probe? }.
      body: stored,
      probe: typeof stored["probe"] === "string" ? stored["probe"] : undefined,
      run: { ...run, name },
    };
  }

  const name = vercelScheduleNameFrom(message.name) ?? message.name;
  const tick = blockTickOf(name);

  return {
    queue: tick === undefined ? undefined : BLOCK_TICKS_QUEUE,
    body: { payload: tick ?? stored ?? {}, max_attempts: 5 },
    probe: undefined,
    run: { ...run, name },
  };
}

export interface VercelScheduleBridgeRouteOptions {
  /** `new QueueClient()` from `@vercel/queue`, or the module itself. */
  readonly client: VercelQueueCallbackClient;
  /** Seconds before a failed enqueue comes back. Default 30. */
  readonly retryAfter?: number;
  /** The lock on each message while the run is enqueued. Default 60. */
  readonly visibilityTimeoutSeconds?: number;
  /** Gets every error; the message then comes back after `retryAfter`. */
  readonly onError?: (error: DbError, run: VercelScheduleRun) => void;
  /** Gets each run whose probe reported no work, which is skipped. */
  readonly onSkip?: (run: VercelScheduleRun) => void;
}

/**
 * The route on the bridge topic of `vercelScheduler(Schedules, { bridge })`,
 * for Vercel Schedules with a Supabase queue: for each run it checks the
 * schedule's probe with `schedule_has_work`, then enqueues the run with
 * `jobs.enqueueScheduledRun`, once per `executionId`. A false probe skips that
 * run only; the next run asks again. A static schedule on the topic runs a
 * block timer, named `block:<block>.<timer>`, on `block_ticks`.
 */
export function vercelScheduleBridgeRoute<Q extends QueueSchemas>(
  jobs: Queue<Q>,
  options: VercelScheduleBridgeRouteOptions,
): (request: Request) => Promise<Response> {
  const handler: CallbackHandler = async (message) => {
    if (!isVercelScheduleMessage(message)) {
      throw new TypeError(
        "The bridge topic carries Vercel schedule runs; this message is not one",
      );
    }

    const scheduled = scheduledMessageOf(message);

    if (scheduled.queue === undefined) {
      throw new TypeError(
        `The Vercel schedule "${message.name}" names no queue: write it with jobs.schedule, or name a block timer`,
      );
    }

    const result = await jobs.enqueueScheduledRun({
      name: scheduled.run.name,
      queue: scheduled.queue,
      payload: scheduled.body.payload,
      executionId: scheduled.run.executionId,
      maxAttempts: scheduled.body.max_attempts ?? 5,
      ...(scheduled.probe === undefined ? {} : { probe: scheduled.probe }),
    });

    if (!result.ok) {
      options.onError?.(result.error, scheduled.run);

      throw new Error(result.error.message, { cause: result.error });
    }

    if (result.data === null) {
      options.onSkip?.(scheduled.run);
    }
  };

  return options.client.handleCallback(handler, {
    visibilityTimeoutSeconds: options.visibilityTimeoutSeconds ?? 60,
    retry: () => ({ afterSeconds: options.retryAfter ?? 30 }),
  });
}
