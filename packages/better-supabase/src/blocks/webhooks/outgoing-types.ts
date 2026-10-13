import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { EventHub } from "../../core/events.ts";
import type { RequestContext } from "../../core/plugin.ts";
import type { BlockProblemOptions } from "../../core/problem.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { EventSink } from "../../events/index.ts";
import type { JobHandler } from "../jobs/types.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type { WebhookTransport } from "./http.ts";
import type { RotateSecretOptions, WebhookSecretStore } from "./secrets.ts";
import type { WebhookSigner } from "./signers.ts";
import type { AllowUrl } from "./url-policy.ts";

/** One claimed delivery, as `shouldDeliver`, `transform` and `headers` see it. */
export interface WebhookDelivery {
  readonly id: string;
  readonly endpointId: string;
  readonly url: string;
  readonly type: string;
  readonly payload: unknown;
  /** 1 on the first try. Counted when the delivery is claimed. */
  readonly attempt: number;
  readonly tenant: string | null;
  readonly eventId: string | null;
  readonly runId: string | null;
  readonly createdAt: Temporal.Instant;
}

export interface RetryPolicy {
  /** Attempts before a delivery is dead-lettered. Defaults to 8. */
  readonly maxAttempts?: number;
  /**
   * Seconds before the next attempt. Defaults to 5 seconds, 5 minutes, 30
   * minutes, 2 hours, 5 hours, then 10 hours. Each wait is at least half
   * its step and at least a second, plus a random share of the rest. A
   * receiver's `Retry-After` wins when it asks for longer, up to a day.
   */
  readonly backoff?: (attempt: number) => number;
  /** Statuses worth retrying. Defaults to 408, 429 and 5xx; network errors always retry. */
  readonly retryable?: (status: number) => boolean;
}

export interface WebhooksOptions extends BlockTemporalOptions {
  /** `sqlTransport(postgres.admin)` for the worker, or the user's connection to manage. */
  readonly transport: BlockTransport;
  /** `sql.modules.webhooks-out.schema`. Defaults to `better_supabase`. */
  readonly schema?: string;
  /** Defaults to `fetchTransport({ allowUrl })`. */
  readonly http?: WebhookTransport;
  /** Used by the default `http`. Defaults to `publicUrl()`. */
  readonly allowUrl?: AllowUrl;
  /** Defaults to `standardWebhooks()`. */
  readonly signer?: WebhookSigner;
  /** Defaults to `sqlSecretStore(transport)`. */
  readonly secrets?: WebhookSecretStore;
  readonly retry?: RetryPolicy;
  /** Return `false` (or throw) to cancel a delivery instead of sending it. */
  readonly shouldDeliver?: (
    delivery: WebhookDelivery,
  ) => boolean | Promise<boolean>;
  /**
   * The JSON body. Defaults to the Standard Webhooks envelope,
   * `{ type, timestamp, data }`.
   */
  readonly transform?: (delivery: WebhookDelivery) => unknown;
  /** Extra headers, e.g. an `idempotency-key`. */
  readonly headers?: (
    delivery: WebhookDelivery,
  ) => Readonly<Record<string, string>>;
  /** Characters of the response body kept in the log. Defaults to 2000. */
  readonly responseBodyLimit?: number;
  /** `betterSupabase.events`, for `webhook.*` block events. */
  readonly events?: EventHub;
  readonly context?: RequestContext;
  /** Error mappers that run before the built-in ones, as in `betterSupabase.mapError()`. */
  readonly mappers?: readonly ErrorMapper[];
}

export interface PublishInput {
  readonly type: string;
  readonly data: unknown;
  readonly tenant?: string;
  /** With an id, publishing it again never queues a second delivery. */
  readonly id?: string;
}

export interface DispatchInput {
  readonly endpointId: string;
  readonly type: string;
  readonly data: unknown;
  /** An external run id stored with the delivery, e.g. a workflow run. */
  readonly runId?: string;
  readonly eventId?: string;
}

export interface DeliverWebhooksOptions {
  /** Deliveries per claim. Defaults to 25. */
  readonly batch?: number;
  /**
   * Requests in flight at once. Defaults to 10, so a batch of 25 at the
   * 10-second timeout finishes well inside the lease.
   */
  readonly concurrency?: number;
  /** How long a claim holds a delivery. Defaults to `'2 minutes'`. */
  readonly lease?: string;
  readonly budgetMs?: number;
}

export interface DeliverWebhooksResult {
  readonly succeeded: number;
  /** Failed attempts that will retry. */
  readonly retrying: number;
  /** Deliveries that ran out of attempts or can't succeed. */
  readonly dead: number;
  readonly canceled: number;
  /** Endpoints disabled after failing for `disableAfter`. */
  readonly disabled: number;
}

export interface WebhooksRouteOptions
  extends DeliverWebhooksOptions, BlockProblemOptions {
  readonly secret: string | undefined;
  readonly onError?: (error: unknown) => void;
}

export interface Webhooks {
  /** Queues the event for each subscribed endpoint; returns how many. */
  publish(event: PublishInput): AsyncResult<number>;
  /** Sends to one endpoint outside its subscriptions; returns the delivery id. */
  dispatch(input: DispatchInput): AsyncResult<string>;
  /** Queues a finished delivery again. */
  redeliver(deliveryId: string): AsyncResult<string>;
  /** A new signing secret, returned once. */
  rotateSecret(
    endpointId: string,
    options?: RotateSecretOptions,
  ): AsyncResult<string>;
  /** Sends due deliveries. Run it from a cron route or a job. */
  deliver(options?: DeliverWebhooksOptions): Promise<DeliverWebhooksResult>;
  /** A `GET`/`POST` handler for Vercel Cron that runs `deliver` behind a bearer secret. */
  deliverRoute(
    options: WebhooksRouteOptions,
  ): (request: Request) => Promise<Response>;
  /**
   * An `EventSink` that publishes CloudEvents, e.g. from the outbox relay.
   * Endpoints subscribe to unprefixed types, so it removes `typePrefix`
   * (`dev.better-supabase` by default, the relay's default) and the dot.
   */
  sink(options?: WebhookSinkOptions): EventSink;
  /**
   * Deletes up to `batch` finished deliveries created before `olderThan`
   * (`purge_webhook_deliveries`); returns how many. Keep `olderThan` above
   * the window you republish in: a purged event id can be queued again.
   */
  purge(options?: PurgeWebhookDeliveriesOptions): AsyncResult<number>;
  /** A job handler that runs `purge`; schedule it nightly. */
  purgeJob(options?: PurgeWebhookDeliveriesOptions): JobHandler<unknown>;
}

export interface PurgeWebhookDeliveriesOptions {
  /** Seconds, or an interval such as `"30 days"`. Defaults to 30 days. */
  readonly olderThan?: number | string;
  /** Also delete dead deliveries. Defaults to false. */
  readonly includeDead?: boolean;
  /** Defaults to 10000. */
  readonly batch?: number;
}

export interface WebhookSinkOptions {
  /** The relay's `typePrefix`. */
  readonly typePrefix?: string;
}

export type Outcome = "succeeded" | "retrying" | "dead" | "canceled";
