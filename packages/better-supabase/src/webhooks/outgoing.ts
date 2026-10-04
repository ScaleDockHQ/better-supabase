import type { ErrorMapper } from "../core/errors.ts";
import type { EventHub } from "../core/events.ts";
import type { KitTransport } from "../core/kit-transport.ts";
import type { RequestContext } from "../core/plugin.ts";
import type { CloudEvent, EventSink } from "../events/index.ts";
import type { WebhookResponse, WebhookTransport } from "./http.ts";
import type { RotateSecretOptions, WebhookSecretStore } from "./secrets.ts";
import type { WebhookSigner } from "./signers.ts";
import type { AllowUrl } from "./url-policy.ts";

import { dbError, mapDbError } from "../core/errors.ts";
import { emitKitEvent } from "../core/kit-events.ts";
import { rawError } from "../core/kit-transport.ts";
import { problemResponse } from "../core/problem.ts";
import { AsyncResult, err, ok, toDbError } from "../core/result.ts";
import { temporal } from "../core/temporal-required.ts";
import { fetchTransport, WebhookPolicyError } from "./http.ts";
import { sqlSecretStore } from "./secrets.ts";
import { standardWebhooks } from "./signers.ts";
import { publicUrl } from "./url-policy.ts";
import { verifySharedSecret } from "./verify.ts";

/** One claimed delivery, as `shouldDeliver`, `transform` and `headers` see it. */
export interface WebhookDelivery {
  readonly id: string;
  readonly destinationId: string;
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
   * minutes, 2 hours, 5 hours, then 10 hours, each with full jitter. A
   * receiver's `Retry-After` wins when it asks for longer, up to a day.
   */
  readonly backoff?: (attempt: number) => number;
  /** Statuses worth retrying. Defaults to 408, 429 and 5xx; network errors always retry. */
  readonly retryable?: (status: number) => boolean;
}

export interface WebhooksOptions {
  /** `sqlTransport(postgres.admin)` for the worker, or the user's connection to manage. */
  readonly transport: KitTransport;
  /** `kits.webhooks-out.schema`. Defaults to `better_supabase`. */
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
  /** `betterSupabase.events`, for `webhook.*` kit events. */
  readonly events?: EventHub;
  readonly context?: RequestContext;
  readonly errorMappers?: readonly ErrorMapper[];
}

export interface PublishInput {
  readonly type: string;
  readonly data: unknown;
  readonly tenant?: string;
  /** With an id, publishing it again never queues a second delivery. */
  readonly id?: string;
}

export interface DispatchInput {
  readonly destinationId: string;
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
  readonly completed: number;
  /** Failed attempts that will retry. */
  readonly failed: number;
  readonly deadLettered: number;
  readonly canceled: number;
  /** Destinations disabled after failing for `disableAfter`. */
  readonly disabled: number;
}

export interface WebhooksRouteOptions extends DeliverWebhooksOptions {
  readonly secret: string | undefined;
  readonly onError?: (error: unknown) => void;
}

export interface Webhooks {
  /** Queues the event for each subscribed destination; returns how many. */
  publish(event: PublishInput): AsyncResult<number>;
  /** Sends to one destination outside its subscriptions; returns the delivery id. */
  dispatch(input: DispatchInput): AsyncResult<string>;
  /** Queues a finished delivery again. */
  redeliver(deliveryId: string): AsyncResult<string>;
  /** A new signing secret, returned once. */
  rotateSecret(
    destinationId: string,
    options?: RotateSecretOptions,
  ): AsyncResult<string>;
  /** Sends due deliveries. Run it from a cron route or a job. */
  deliver(options?: DeliverWebhooksOptions): Promise<DeliverWebhooksResult>;
  /** A `GET`/`POST` handler for Vercel Cron that runs `deliver` behind a bearer secret. */
  deliverRoute(
    options: WebhooksRouteOptions,
  ): (request: Request) => Promise<Response>;
  /** An `EventSink` that publishes CloudEvents, e.g. from the outbox relay. */
  sink(): EventSink;
}

const DEFAULT_SCHEMA = "better_supabase";

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const textOf = (value: unknown): string | null =>
  value === null || value === undefined ? null : String(value);

function toDelivery(row: Record<string, unknown>): WebhookDelivery {
  return {
    id: String(row["id"]),
    destinationId: String(row["destination_id"]),
    url: String(row["url"]),
    type: String(row["type"]),
    payload: row["payload"] ?? {},
    attempt: Number(row["attempt"] ?? 1),
    tenant: textOf(row["tenant"]),
    eventId: textOf(row["event_id"]),
    runId: textOf(row["run_id"]),
    createdAt:
      typeof row["created_at"] === "string"
        ? temporal().Instant.from(row["created_at"])
        : temporal().Now.instant(),
  };
}

const SCHEDULE = [5, 300, 1800, 7200, 18_000, 36_000] as const;

const defaultBackoff = (attempt: number): number =>
  Math.round(
    Math.random() *
      SCHEDULE[Math.min(Math.max(attempt, 1), SCHEDULE.length) - 1]!,
  );

const MAX_RETRY_AFTER = 86_400;

const defaultRetryable = (status: number): boolean =>
  status === 408 || status === 429 || status >= 500;

const errorText = (cause: unknown): string =>
  cause instanceof Error ? cause.message : String(cause);

type Outcome = "completed" | "failed" | "dead_lettered" | "canceled";

export function createWebhooks(options: WebhooksOptions): Webhooks {
  const { transport } = options;
  const schema = options.schema ?? DEFAULT_SCHEMA;
  const mappers = options.errorMappers ?? [];
  const store = options.secrets ?? sqlSecretStore(transport, { schema });
  const signer = options.signer ?? standardWebhooks();
  const maxAttempts = options.retry?.maxAttempts ?? 8;
  const backoff = options.retry?.backoff ?? defaultBackoff;
  const retryable = options.retry?.retryable ?? defaultRetryable;
  const bodyLimit = options.responseBodyLimit ?? 2000;
  let http = options.http;
  const httpTransport = (): WebhookTransport =>
    (http ??= fetchTransport({ allowUrl: options.allowUrl ?? publicUrl() }));

  const call = (fn: string, args: Readonly<Record<string, unknown>>) =>
    transport.call(schema, fn, args);

  function run<T>(
    fn: () => Promise<unknown>,
    then: (value: unknown) => T,
  ): AsyncResult<T> {
    return AsyncResult.from(async () => {
      try {
        return ok(then(await fn()));
      } catch (cause) {
        const raw = rawError(cause);
        return err(raw ? mapDbError(raw, mappers) : toDbError(cause));
      }
    });
  }

  function emit(
    type: "webhook.delivered" | "webhook.failed" | "webhook.disabled",
    delivery: WebhookDelivery,
    extra: { readonly status?: number; readonly error?: string } = {},
  ): void {
    if (!options.events) return;
    emitKitEvent(
      options.events,
      type,
      {
        endpointId: delivery.destinationId,
        deliveryId: delivery.id,
        eventType: delivery.type,
        attempt: delivery.attempt,
        ...extra,
      },
      {
        subject: `webhooks/${delivery.destinationId}`,
        ...(delivery.tenant ? { tenant: delivery.tenant } : {}),
        ...(options.context ? { context: options.context } : {}),
      },
    );
  }

  async function complete(
    delivery: WebhookDelivery,
    status: Outcome,
    detail: {
      readonly response?: WebhookResponse;
      readonly durationMs?: number;
      readonly error?: string;
    },
  ): Promise<unknown> {
    const retryAfter = Math.min(
      detail.response?.retryAfter ?? 0,
      MAX_RETRY_AFTER,
    );
    const retryAt =
      status === "failed"
        ? temporal()
            .Now.instant()
            .add({
              seconds: Math.max(backoff(delivery.attempt), retryAfter),
            })
            .toString()
        : undefined;
    return call("complete_webhook_delivery", {
      delivery: delivery.id,
      outcome: {
        status,
        attempt: delivery.attempt,
        ...(retryAt ? { retry_at: retryAt } : {}),
        ...(detail.response
          ? {
              response_status: detail.response.status,
              response_body: detail.response.body.slice(0, bodyLimit),
            }
          : {}),
        ...(detail.durationMs === undefined
          ? {}
          : { duration_ms: detail.durationMs }),
        ...(detail.error === undefined
          ? {}
          : { error: detail.error.slice(0, bodyLimit) }),
      },
    });
  }

  const failure = (delivery: WebhookDelivery): Outcome =>
    delivery.attempt >= maxAttempts ? "dead_lettered" : "failed";

  async function attempt(delivery: WebhookDelivery): Promise<{
    readonly outcome: Outcome;
    readonly response?: WebhookResponse;
    readonly durationMs?: number;
    readonly error?: string;
  }> {
    if (options.shouldDeliver) {
      let send: boolean;
      try {
        send = await options.shouldDeliver(delivery);
      } catch (cause) {
        return { outcome: "canceled", error: errorText(cause) };
      }
      if (!send)
        return { outcome: "canceled", error: "Canceled by shouldDeliver" };
    }
    let body: string;
    let headers: Record<string, string>;
    try {
      const secrets = await store.secrets(delivery.destinationId);
      if (secrets.length === 0)
        return {
          outcome: "dead_lettered",
          error: "The destination has no signing secret",
        };
      body = JSON.stringify(
        options.transform
          ? await options.transform(delivery)
          : {
              type: delivery.type,
              timestamp: delivery.createdAt.toString(),
              data: delivery.payload,
            },
      );
      headers = {
        "content-type": "application/json",
        "user-agent": "better-supabase-webhooks",
        ...options.headers?.(delivery),
        ...(await signer.sign({
          id: delivery.id,
          body,
          timestamp: temporal().Now.instant(),
          secrets,
        })),
      };
    } catch (cause) {
      return { outcome: failure(delivery), error: errorText(cause) };
    }
    const started = Date.now();
    try {
      const response = await httpTransport().send({
        url: delivery.url,
        headers,
        body,
      });
      const durationMs = Date.now() - started;
      if (response.status >= 200 && response.status < 300)
        return { outcome: "completed", response, durationMs };
      return {
        outcome: retryable(response.status)
          ? failure(delivery)
          : "dead_lettered",
        response,
        durationMs,
        error: `HTTP ${String(response.status)}`,
      };
    } catch (cause) {
      return {
        outcome:
          cause instanceof WebhookPolicyError
            ? "dead_lettered"
            : failure(delivery),
        durationMs: Date.now() - started,
        error: errorText(cause),
      };
    }
  }

  async function deliver(
    deliverOptions: DeliverWebhooksOptions = {},
  ): Promise<DeliverWebhooksResult> {
    const counts = {
      completed: 0,
      failed: 0,
      deadLettered: 0,
      canceled: 0,
      disabled: 0,
    };
    const deadline =
      deliverOptions.budgetMs === undefined
        ? Number.POSITIVE_INFINITY
        : Date.now() + deliverOptions.budgetMs;
    const batch = deliverOptions.batch ?? 25;
    const concurrency = Math.max(1, deliverOptions.concurrency ?? 10);

    async function handle(delivery: WebhookDelivery): Promise<void> {
      const result = await attempt(delivery);
      const state = await complete(delivery, result.outcome, result);
      if (state === "stale") return;
      switch (result.outcome) {
        case "completed":
          counts.completed += 1;
          emit("webhook.delivered", delivery, {
            status: result.response?.status ?? 200,
          });
          break;
        case "failed":
        case "dead_lettered":
          if (result.outcome === "failed") counts.failed += 1;
          else counts.deadLettered += 1;
          emit("webhook.failed", delivery, {
            ...(result.response ? { status: result.response.status } : {}),
            ...(result.error ? { error: result.error } : {}),
          });
          break;
        case "canceled":
          counts.canceled += 1;
          break;
        default: {
          const unknown: never = result.outcome;
          throw new TypeError(`Unknown outcome ${String(unknown)}`);
        }
      }
      if (state === "disabled") {
        counts.disabled += 1;
        emit("webhook.disabled", delivery);
      }
    }

    while (Date.now() < deadline) {
      const claimed = await call("claim_webhook_deliveries", {
        max_items: batch,
        lease: deliverOptions.lease ?? "2 minutes",
        max_attempts: maxAttempts,
      });
      const queue = (Array.isArray(claimed) ? claimed : [])
        .filter(isRecord)
        .map(toDelivery);
      const size = queue.length;
      await Promise.all(
        Array.from({ length: Math.min(concurrency, size) }, async () => {
          for (let next = queue.shift(); next; next = queue.shift())
            await handle(next);
        }),
      );
      if (size < batch) break;
    }
    return counts;
  }

  return {
    publish: (event) =>
      run(
        () =>
          call("publish_webhook_event", {
            event_type: event.type,
            payload: event.data ?? {},
            tenant: event.tenant ?? null,
            event_id: event.id ?? null,
          }),
        Number,
      ),
    dispatch: (input) =>
      run(
        () =>
          call("dispatch_webhook", {
            destination: input.destinationId,
            event_type: input.type,
            payload: input.data ?? {},
            run_id: input.runId ?? null,
            event_id: input.eventId ?? null,
          }),
        String,
      ),
    redeliver: (deliveryId) =>
      run(() => call("redeliver_webhook", { delivery: deliveryId }), String),
    rotateSecret(destinationId, rotateOptions) {
      if (!store.rotate) {
        return AsyncResult.err(
          dbError("unexpected", "The secret store can't rotate secrets"),
        );
      }
      const rotate = store.rotate.bind(store);
      return run(() => rotate(destinationId, rotateOptions), String);
    },
    deliver,
    deliverRoute(routeOptions) {
      const secret = routeOptions.secret;
      if (!secret)
        throw new TypeError(
          "deliverRoute needs a secret, such as process.env.CRON_SECRET",
        );
      return async (request) => {
        const instance = new URL(request.url).pathname;
        if (request.method !== "GET" && request.method !== "POST")
          return new Response(null, {
            status: 405,
            headers: { allow: "GET, POST" },
          });
        if (!verifySharedSecret(request, secret))
          return problemResponse(
            dbError(
              "unauthorized",
              "The deliver route needs its bearer secret",
            ),
            { instance },
          );
        try {
          return Response.json(
            await deliver({ budgetMs: 50_000, ...routeOptions }),
          );
        } catch (cause) {
          routeOptions.onError?.(cause);
          return problemResponse(toDbError(cause), { instance });
        }
      };
    },
    sink: () => ({
      async send(events: readonly CloudEvent[]) {
        for (const event of events) {
          const tenant = event["partitionkey"];
          await call("publish_webhook_event", {
            event_type: event.type,
            payload: event.data ?? {},
            tenant: typeof tenant === "string" ? tenant : null,
            event_id: event.id,
          });
        }
      },
    }),
  };
}
