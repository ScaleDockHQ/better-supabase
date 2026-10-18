import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type {
  AuthorizationHooks,
  SubscriberPolicy,
} from "../../core/contracts/authorization-hooks.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { EventHub } from "../../core/events.ts";
import type { RequestContext } from "../../core/plugin.ts";
import type { BlockProblemOptions } from "../../core/problem.ts";
import type { AsyncResult } from "../../core/result.ts";
import type {
  CredentialProvider,
  CredentialRef,
} from "../../credentials/provider.ts";
import type { EventSink } from "../../events/index.ts";
import type { JobHandler } from "../jobs/types.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type { WebhookEncoder } from "./encoders.ts";
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
  /** The CloudEvents `subject`, such as `invoices/123`, when the event has one. */
  readonly subject: string | null;
  /** The user who owns the endpoint, or `null` for a service principal's endpoint. */
  readonly owner: string | null;
  /**
   * The tenant's default service principal, which an endpoint without an
   * owner runs as, when the service-principals module is installed.
   */
  readonly principal: string | null;
  /** The permissions a service principal's endpoint declares. */
  readonly permissions: readonly string[] | null;
  /** The endpoint takes CloudEvents batches. */
  readonly batch: boolean;
  /** `v1` signs with the endpoint's secrets, `v1a` with `asymmetricSigner`. */
  readonly signing: "v1" | "v1a";
  /** The encoder that writes the request body, such as `cloudevents` or `otlp-logs`. */
  readonly format: string;
  /** The credential whose token authenticates the request, if any. */
  readonly credentialRef: CredentialRef | null;
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

/** The subscription a `subscribers` policy sees for one claimed delivery. */
export interface WebhookSubscriber {
  /**
   * The endpoint owner's user id; for an endpoint without an owner, the
   * tenant's default service principal, or the endpoint id without one.
   */
  readonly principal: string;
  readonly kind: "user" | "service";
  readonly delivery: WebhookDelivery;
}

export interface WebhooksOptions extends BlockTemporalOptions {
  /** `sqlTransport(postgres.admin)` for the worker, or the user's connection to manage. */
  readonly transport: BlockTransport;
  /** The module schema, or its API schema: `defineBlocks` passes it from `blocks.generated.ts`. Default `better_supabase`. */
  readonly schema?: string;
  /** Defaults to `fetchTransport({ allowUrl })`. */
  readonly http?: WebhookTransport;
  /** Used by the default `http`. Defaults to `publicUrl()`. */
  readonly allowUrl?: AllowUrl;
  /** Signs deliveries to `v1` endpoints. Defaults to `standardWebhooks()`. */
  readonly signer?: WebhookSigner;
  /**
   * Signs deliveries to endpoints with `signing = 'v1a'`, usually
   * `standardWebhooksAsymmetric({ signer })`. Without it those deliveries
   * are dead-lettered.
   */
  readonly asymmetricSigner?: WebhookSigner;
  /** Defaults to `sqlSecretStore(transport)`. */
  readonly secrets?: WebhookSecretStore;
  /**
   * Encoders for endpoint `format`s beyond, or replacing, the built-in
   * `cloudevents`, `standard`, `otlp-logs`, `splunk-hec` and `set`. A
   * delivery to a format without an encoder is dead-lettered.
   */
  readonly encoders?: readonly WebhookEncoder[];
  /**
   * The format of an endpoint whose row has none, such as an adopted table
   * that doesn't map `format` or holds `null`.
   * `blocks.webhooks-out.options.defaultFormat`, which `defineBlocks` passes,
   * and the column default. Defaults to `cloudevents`.
   */
  readonly defaultFormat?: string;
  /**
   * Resolves an endpoint's `credential_ref` to the token that
   * authenticates its requests. Without it, such deliveries are
   * dead-lettered.
   */
  readonly credentials?: CredentialProvider;
  readonly retry?: RetryPolicy;
  /** Return `false` (or throw) to cancel a delivery instead of sending it. */
  readonly shouldDeliver?: (
    delivery: WebhookDelivery,
  ) => boolean | Promise<boolean>;
  /** The CloudEvent's `data`. Defaults to the published payload. */
  readonly transform?: (delivery: WebhookDelivery) => unknown;
  /**
   * The CloudEvents `source`, an absolute URI. Defaults to `/webhooks` on
   * `appUrl`, or `urn:better-supabase:webhooks` without one.
   */
  readonly source?: string;
  /** The app's public URL, such as `https://app.example.com`. */
  readonly appUrl?: string;
  /** Prepended to each type with a dot, such as `com.example`. Defaults to none. */
  readonly typePrefix?: string;
  /**
   * The CloudEvents `dataschema`: an absolute URI, or a function that picks
   * one per delivery or leaves it out with `undefined`.
   */
  readonly dataschema?:
    | string
    | ((delivery: WebhookDelivery) => string | undefined);
  /**
   * The W3C `traceparent` of the delivery, sent as the CloudEvents
   * `traceparent` extension. A value that is not a valid trace context is
   * left out.
   */
  readonly traceparent?: (delivery: WebhookDelivery) => string | undefined;
  /**
   * Narrows each event's claimed deliveries to the endpoints whose owner
   * may read it. A delivery it leaves out is canceled; a throw retries every
   * delivery of the event. Each delivery is checked against its own stored
   * `subject`. Defaults to `authorization.delivery.subscribers`; with
   * `authorization` but no such policy, to `subjectReaders(transport)`, so
   * an event about a `config.subjects` record only reaches endpoints whose
   * owner (or service principal) may read that record.
   */
  readonly subscribers?: SubscriberPolicy;
  /** `server.authorization`, for its `delivery.subscribers` policy. */
  readonly authorization?: Pick<AuthorizationHooks, "delivery">;
  /** Extra headers, e.g. an `idempotency-key`. */
  readonly headers?: (
    delivery: WebhookDelivery,
  ) => Readonly<Record<string, string>>;
  /** Characters of the response body kept in the log. Defaults to 2000. */
  readonly responseBodyLimit?: number;
  /** `betterSupabase.events`, for `webhook.*` block events. */
  readonly events?: EventHub;
  /** `withBlockHooks` hooks around the client's methods, such as a check before `publish`. */
  readonly hooks?: BlockHooks<Webhooks>;
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
  /** What the event is about, such as `invoices/123`: the CloudEvents `subject`. */
  readonly subject?: string;
  /**
   * The permission an endpoint owner needs in the tenant to receive the
   * event, such as `invoices.read`. Defaults to the module's view
   * permission (`webhooks.read`).
   */
  readonly readPermission?: string;
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
