import type { CloudEvent } from "../../events/index.ts";
import type {
  DeliverWebhooksOptions,
  DeliverWebhooksResult,
  Outcome,
  WebhookDelivery,
  Webhooks,
  WebhooksOptions,
} from "./outgoing-types.ts";

import { blockEmitter } from "../../core/block-events.ts";
import { budget, seconds, toBlockError } from "../../core/block-helpers.ts";
import { cronRoute } from "../../core/cron-route.ts";
import { dbError } from "../../core/errors.ts";
import { problemResponse } from "../../core/problem.ts";
import { AsyncResult, err, ok, toDbError } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import { stripTypePrefix } from "../../events/cloud-event.ts";
import {
  DEFAULT_BLOCK_SCHEMA,
  applyTemporal,
  errorText,
  isRecord,
} from "../shared.ts";
import {
  WebhookPolicyError,
  fetchTransport,
  type WebhookResponse,
  type WebhookTransport,
} from "./http.ts";
import { sqlSecretStore } from "./secrets.ts";
import { standardWebhooks } from "./signers.ts";
import { publicUrl } from "./url-policy.ts";

const textOf = (value: unknown): string | null =>
  value === null || value === undefined ? null : String(value);

function toDelivery(row: Record<string, unknown>): WebhookDelivery {
  return {
    id: String(row["id"]),
    endpointId: String(row["endpoint_id"]),
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

/** Equal jitter: at least half the step, and never under a second. */
const defaultBackoff = (attempt: number): number => {
  const step = SCHEDULE[Math.min(Math.max(attempt, 1), SCHEDULE.length) - 1]!;
  return Math.max(1, Math.round(step / 2 + (Math.random() * step) / 2));
};

const MAX_RETRY_AFTER = 86_400;

const defaultRetryable = (status: number): boolean =>
  status === 408 || status === 429 || status >= 500;

export function createWebhooks(options: WebhooksOptions): Webhooks {
  applyTemporal(options);
  const { transport } = options;
  const schema = options.schema ?? DEFAULT_BLOCK_SCHEMA;
  const mappers = options.mappers ?? [];
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
        return err(toBlockError(cause, mappers));
      }
    });
  }

  const emitEvent = blockEmitter(options);

  function emit(
    type: "webhook.delivered" | "webhook.failed" | "webhook.disabled",
    delivery: WebhookDelivery,
    extra: { readonly status?: number; readonly error?: string } = {},
  ): void {
    emitEvent(
      type,
      {
        endpointId: delivery.endpointId,
        deliveryId: delivery.id,
        eventType: delivery.type,
        attempt: delivery.attempt,
        ...extra,
      },
      `webhooks/${delivery.endpointId}`,
      delivery.tenant,
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
      status === "retrying"
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
    delivery.attempt >= maxAttempts ? "dead" : "retrying";

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
      const secrets = await store.secrets(delivery.endpointId);
      if (secrets.length === 0)
        return {
          outcome: "dead",
          error: "The endpoint has no signing secret",
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
        return { outcome: "succeeded", response, durationMs };
      return {
        outcome: retryable(response.status) ? failure(delivery) : "dead",
        response,
        durationMs,
        error: `HTTP ${String(response.status)}`,
      };
    } catch (cause) {
      return {
        outcome:
          cause instanceof WebhookPolicyError ? "dead" : failure(delivery),
        durationMs: Date.now() - started,
        error: errorText(cause),
      };
    }
  }

  async function deliver(
    deliverOptions: DeliverWebhooksOptions = {},
  ): Promise<DeliverWebhooksResult> {
    const counts = {
      succeeded: 0,
      retrying: 0,
      dead: 0,
      canceled: 0,
      disabled: 0,
    };
    const spent = budget(deliverOptions.budgetMs);
    const batch = deliverOptions.batch ?? 25;
    const concurrency = Math.max(1, deliverOptions.concurrency ?? 10);

    async function handle(delivery: WebhookDelivery): Promise<void> {
      const result = await attempt(delivery);
      const state = await complete(delivery, result.outcome, result);
      if (state === "stale") return;
      switch (result.outcome) {
        case "succeeded":
          counts.succeeded += 1;
          emit("webhook.delivered", delivery, {
            status: result.response?.status ?? 200,
          });
          break;
        case "retrying":
        case "dead":
          if (result.outcome === "retrying") counts.retrying += 1;
          else counts.dead += 1;
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

    while (!spent.expired()) {
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

  const purge: Webhooks["purge"] = (purgeOptions = {}) =>
    run(
      () =>
        call("purge_webhook_deliveries", {
          older_than:
            purgeOptions.olderThan === undefined
              ? undefined
              : seconds(purgeOptions.olderThan),
          include_dead: purgeOptions.includeDead,
          batch: purgeOptions.batch,
        }),
      (value) => Number(value ?? 0),
    );

  return {
    purge,
    purgeJob: (jobOptions) => async () => purge(jobOptions).orThrow(),
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
            endpoint: input.endpointId,
            event_type: input.type,
            payload: input.data ?? {},
            run_id: input.runId ?? null,
            event_id: input.eventId ?? null,
          }),
        String,
      ),
    redeliver: (deliveryId) =>
      run(() => call("redeliver_webhook", { delivery: deliveryId }), String),
    rotateSecret(endpointId, rotateOptions) {
      if (!store.rotate) {
        return AsyncResult.err(
          dbError("unexpected", "The secret store can't rotate secrets"),
        );
      }
      const rotate = store.rotate.bind(store);
      return run(() => rotate(endpointId, rotateOptions), String);
    },
    deliver,
    deliverRoute(routeOptions) {
      return cronRoute(
        {
          name: "deliver",
          secret: routeOptions.secret,
          problem: routeOptions.problem,
        },
        async (_request, instance) => {
          try {
            return Response.json(
              await deliver({ budgetMs: 50_000, ...routeOptions }),
            );
          } catch (cause) {
            routeOptions.onError?.(cause);
            return problemResponse(toDbError(cause), {
              instance,
              format: routeOptions.problem,
            });
          }
        },
      );
    },
    sink: (sinkOptions = {}) => {
      return {
        async send(events: readonly CloudEvent[]) {
          for (const event of events) {
            const tenant = event["partitionkey"];
            await call("publish_webhook_event", {
              event_type: stripTypePrefix(event.type, sinkOptions.typePrefix),
              payload: event.data ?? {},
              tenant: typeof tenant === "string" ? tenant : null,
              event_id: event.id,
            });
          }
        },
      };
    },
  };
}
