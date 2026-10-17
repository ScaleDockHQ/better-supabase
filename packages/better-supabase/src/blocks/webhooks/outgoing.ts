import type { SubscriberEvent } from "../../core/contracts/authorization-hooks.ts";
import type { DbErrorKind } from "../../core/errors.ts";
import type { Result } from "../../core/result.ts";
import type { CredentialRef } from "../../credentials/provider.ts";
import type { CloudEvent } from "../../events/index.ts";
import type { WebhookEncoder } from "./encoders.ts";
import type { WebhooksEvents } from "./events.ts";
import type {
  DeliverWebhooksOptions,
  DeliverWebhooksResult,
  Outcome,
  WebhookDelivery,
  Webhooks,
  WebhooksOptions,
  WebhookSubscriber,
} from "./outgoing-types.ts";

import { blockEmitter } from "../../core/block-events.ts";
import {
  blockCall,
  budget,
  seconds,
  toBlockError,
} from "../../core/block-helpers.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { cronRoute } from "../../core/cron-route.ts";
import { dbError } from "../../core/errors.ts";
import { problemResponse } from "../../core/problem.ts";
import { AsyncResult, err, ok, toDbError } from "../../core/result.ts";
import { subjectReaders } from "../../core/subject-readers.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  credentialRefInTenant,
  foreignCredentialRef,
} from "../../credentials/provider.ts";
import { stripTypePrefix } from "../../events/cloud-event.ts";
import {
  DEFAULT_BLOCK_SCHEMA,
  applyTemporal,
  errorText,
  isRecord,
} from "../shared.ts";
import { encoderRegistry } from "./encoders.ts";
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

const textsOf = (value: unknown): readonly string[] | null =>
  Array.isArray(value) ? value.map(String) : null;

const credentialRefOf = (value: unknown): CredentialRef | null =>
  isRecord(value) && typeof value["provider"] === "string"
    ? { ...value, provider: value["provider"] }
    : null;

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
    subject: textOf(row["subject"]),
    owner: textOf(row["owner"]),
    principal: textOf(row["principal"]),
    permissions: textsOf(row["permissions"]),
    batch: row["batch"] === true,
    signing: row["signing"] === "v1a" ? "v1a" : "v1",
    format: typeof row["format"] === "string" ? row["format"] : "cloudevents",
    credentialRef: credentialRefOf(row["credential_ref"]),
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

/** Token errors a retry can't fix. */
const PERMANENT_CREDENTIAL_ERRORS: ReadonlySet<DbErrorKind> = new Set([
  "invalid_input",
  "not_found",
  "forbidden",
  "unauthorized",
]);

const defaultRetryable = (status: number): boolean =>
  status === 408 || status === 429 || status >= 500;

/** W3C Trace Context, version 00 and the forward-compatible later versions. */
const TRACEPARENT =
  /^(?!ff)[0-9a-f]{2}-(?!0{32})[0-9a-f]{32}-(?!0{16})[0-9a-f]{16}-[0-9a-f]{2}$/;

function absoluteUri(where: string, value: string): string {
  if (!URL.canParse(value))
    throw new TypeError(`${where} must be an absolute URI, not "${value}"`);
  return value;
}

/** The CloudEvents `source`: the `source` option, else `/webhooks` on `appUrl`. */
function sourceOf(options: WebhooksOptions): string {
  if (options.source !== undefined)
    return absoluteUri("createWebhooks: source", options.source);
  if (options.appUrl !== undefined)
    return new URL(
      "/webhooks",
      absoluteUri("createWebhooks: appUrl", options.appUrl),
    ).href;
  return "urn:better-supabase:webhooks";
}

/** The `actorId` a block event or the outbox put in the payload, if any. */
function actorOf(payload: unknown): string | null {
  if (!isRecord(payload)) return null;
  const actor = payload["actorId"];
  return typeof actor === "string" ? actor : null;
}

/** A stable `webhook-id` for a batch: the same deliveries give the same id. */
async function batchId(
  deliveries: readonly WebhookDelivery[],
): Promise<string> {
  const ids = deliveries.map((delivery) => delivery.id).toSorted();
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(ids.join("\n")),
  );
  const hex = Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
  return `batch_${hex.slice(0, 32)}`;
}

/** What one attempt came to; `failed` retries or dead-letters per delivery. */
interface Attempt {
  readonly outcome: Outcome | "failed";
  readonly response?: WebhookResponse;
  readonly durationMs?: number;
  readonly error?: string;
}

export function createWebhooks(options: WebhooksOptions): Webhooks {
  applyTemporal(options);
  const { transport } = options;
  const schema = options.schema ?? DEFAULT_BLOCK_SCHEMA;
  const mappers = options.mappers ?? [];
  const store = options.secrets ?? sqlSecretStore(transport, { schema });
  const signer = options.signer ?? standardWebhooks();
  const encoders = encoderRegistry(options.encoders);
  const maxAttempts = options.retry?.maxAttempts ?? 8;
  const backoff = options.retry?.backoff ?? defaultBackoff;
  const retryable = options.retry?.retryable ?? defaultRetryable;
  const bodyLimit = options.responseBodyLimit ?? 2000;
  const source = sourceOf(options);
  const dataschema =
    typeof options.dataschema === "string"
      ? absoluteUri("createWebhooks: dataschema", options.dataschema)
      : options.dataschema;
  const subscribers =
    options.subscribers ??
    options.authorization?.delivery?.subscribers ??
    (options.authorization === undefined
      ? undefined
      : subjectReaders(transport, { schema }));
  let http = options.http;
  const httpTransport = (): WebhookTransport =>
    (http ??= fetchTransport({ allowUrl: options.allowUrl ?? publicUrl() }));

  const db = blockCall(transport, schema, mappers);
  /** A call the worker needs to go on: it throws the mapped `DbError`. */
  const call = (
    fn: string,
    args: Readonly<Record<string, unknown>>,
  ): Promise<unknown> => db(fn, args, (value) => value).orThrow();

  const emitEvent = blockEmitter<WebhooksEvents>(options);

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

  async function cloudEvent(delivery: WebhookDelivery): Promise<CloudEvent> {
    const schema =
      typeof dataschema === "function" ? dataschema(delivery) : dataschema;
    const traceparent = options.traceparent?.(delivery);
    return {
      specversion: "1.0",
      id: delivery.id,
      source,
      type: options.typePrefix
        ? `${options.typePrefix.replace(/\.$/, "")}.${delivery.type}`
        : delivery.type,
      ...(delivery.subject ? { subject: delivery.subject } : {}),
      time: delivery.createdAt.toString(),
      datacontenttype: "application/json",
      ...(schema === undefined
        ? {}
        : { dataschema: absoluteUri("createWebhooks: dataschema", schema) }),
      data: options.transform
        ? await options.transform(delivery)
        : delivery.payload,
      ...(traceparent !== undefined && TRACEPARENT.test(traceparent)
        ? { traceparent }
        : {}),
    };
  }

  type Headers = Readonly<Record<string, string>>;

  /** The headers the endpoint's `credential_ref` token becomes. */
  async function authorization(
    delivery: WebhookDelivery,
    encoder: WebhookEncoder,
  ): Promise<Result<Headers, Attempt>> {
    const ref = delivery.credentialRef;
    if (ref === null) return ok({});
    if (!credentialRefInTenant(ref, delivery.tenant ?? undefined))
      return err({
        outcome: "dead",
        error: foreignCredentialRef(delivery.tenant ?? undefined).message,
      });
    if (options.credentials === undefined)
      return err({
        outcome: "dead",
        error:
          "The endpoint has a credential_ref, but no credentials provider is set",
      });
    const token = await options.credentials.getToken(ref, {
      subject: { type: "app" },
    });
    if (!token.ok)
      return err({
        outcome: PERMANENT_CREDENTIAL_ERRORS.has(token.error.kind)
          ? "dead"
          : "failed",
        error: token.error.message,
      });
    return ok(encoder.authorize?.(token.data) ?? token.data.headers);
  }

  /** The Standard Webhooks headers, from the endpoint's secrets or `asymmetricSigner`. */
  async function signatureHeaders(
    deliveries: readonly WebhookDelivery[],
    body: string,
  ): Promise<Result<Headers, Attempt>> {
    const first = deliveries[0]!;
    const sign = first.signing === "v1a" ? options.asymmetricSigner : signer;
    if (sign === undefined)
      return err({
        outcome: "dead",
        error: "The endpoint signs with v1a, but no asymmetricSigner is set",
      });
    const secrets = await store.secrets(first.endpointId);
    if (secrets.length === 0 && first.signing === "v1")
      return err({
        outcome: "dead",
        error: "The endpoint has no signing secret",
      });
    return ok(
      await sign.sign({
        id: first.batch ? await batchId(deliveries) : first.id,
        body,
        timestamp: temporal().Now.instant(),
        secrets,
      }),
    );
  }

  /** Sends one delivery, or one batch for an endpoint that takes batches. */
  async function attempt(
    deliveries: readonly WebhookDelivery[],
  ): Promise<Attempt> {
    const first = deliveries[0]!;
    const encoder = encoders.get(first.format);
    if (encoder === undefined)
      return {
        outcome: "dead",
        error: `No encoder for the endpoint format "${first.format}"`,
      };
    let body: string;
    let headers: Record<string, string>;
    try {
      const auth = await authorization(first, encoder);
      if (!auth.ok) return auth.error;
      const events = await Promise.all(deliveries.map(cloudEvent));
      const message = await encoder.encode(events, {
        url: first.url,
        batch: first.batch,
        tenant: first.tenant,
      });
      body = message.body;
      const signature = encoder.signed
        ? await signatureHeaders(deliveries, body)
        : ok({});
      if (!signature.ok) return signature.error;
      headers = {
        ...message.headers,
        "user-agent": "better-supabase-webhooks",
        ...options.headers?.(first),
        ...auth.data,
        ...signature.data,
      };
    } catch (cause) {
      return { outcome: "failed", error: errorText(cause) };
    }
    const started = Date.now();
    try {
      const response = await httpTransport().send({
        url: first.url,
        headers,
        body,
      });
      const durationMs = Date.now() - started;
      const verdict = encoder.classify?.(response);
      if (verdict !== undefined)
        return {
          outcome: verdict.outcome === "retry" ? "failed" : verdict.outcome,
          response,
          durationMs,
          ...(verdict.error === undefined ? {} : { error: verdict.error }),
        };
      if (response.status >= 200 && response.status < 300)
        return { outcome: "succeeded", response, durationMs };
      return {
        outcome: retryable(response.status) ? "failed" : "dead",
        response,
        durationMs,
        error: `HTTP ${String(response.status)}`,
      };
    } catch (cause) {
      return {
        outcome: cause instanceof WebhookPolicyError ? "dead" : "failed",
        durationMs: Date.now() - started,
        error: errorText(cause),
      };
    }
  }

  /** `false` (or a throw) from `shouldDeliver` cancels the delivery. */
  async function vetoed(
    delivery: WebhookDelivery,
  ): Promise<Attempt | undefined> {
    if (!options.shouldDeliver) return undefined;
    try {
      if (await options.shouldDeliver(delivery)) return undefined;
    } catch (cause) {
      return { outcome: "canceled", error: errorText(cause) };
    }
    return { outcome: "canceled", error: "Canceled by shouldDeliver" };
  }

  /**
   * Runs `subscribers` once per event and stored subject over its claimed
   * deliveries. A delivery it leaves out is canceled; a throw fails every
   * delivery of the event, which then retries.
   */
  async function screen(
    queue: readonly WebhookDelivery[],
  ): Promise<Map<WebhookDelivery, Attempt>> {
    const refused = new Map<WebhookDelivery, Attempt>();
    if (!subscribers) return refused;
    const byEvent = Map.groupBy(
      queue,
      (delivery) =>
        `${delivery.eventId ?? `delivery:${delivery.id}`}\u0000${delivery.subject ?? ""}`,
    );
    await Promise.all(
      [...byEvent.values()].map(async (deliveries) => {
        const first = deliveries[0]!;
        const event: SubscriberEvent = {
          type: first.type,
          tenant: first.tenant,
          actorId: actorOf(first.payload),
          payload: first.payload,
          subject: first.subject,
        };
        const candidates = deliveries.map((delivery): WebhookSubscriber => ({
          principal:
            delivery.owner ?? delivery.principal ?? delivery.endpointId,
          kind: delivery.owner ? "user" : "service",
          delivery,
        }));
        let kept: ReadonlySet<WebhookSubscriber>;
        try {
          kept = new Set(await subscribers(event, candidates));
        } catch (cause) {
          for (const delivery of deliveries)
            refused.set(delivery, {
              outcome: "failed",
              error: `Subscriber policy failed: ${errorText(cause)}`,
            });
          return;
        }
        for (const candidate of candidates)
          if (!kept.has(candidate))
            refused.set(candidate.delivery, {
              outcome: "canceled",
              error: "Refused by the subscriber policy",
            });
      }),
    );
    return refused;
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

    async function finish(
      delivery: WebhookDelivery,
      result: Attempt,
    ): Promise<void> {
      const outcome =
        result.outcome === "failed" ? failure(delivery) : result.outcome;
      const state = await complete(delivery, outcome, result);
      if (state === "stale") return;
      switch (outcome) {
        case "succeeded":
          counts.succeeded += 1;
          emit("webhook.delivered", delivery, {
            status: result.response?.status ?? 200,
          });
          break;
        case "retrying":
        case "dead":
          if (outcome === "retrying") counts.retrying += 1;
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
          const unknown: never = outcome;
          throw new TypeError(`Unknown outcome ${String(unknown)}`);
        }
      }
      if (state === "disabled") {
        counts.disabled += 1;
        emit("webhook.disabled", delivery);
      }
    }

    async function handle(
      deliveries: readonly WebhookDelivery[],
    ): Promise<void> {
      const send: WebhookDelivery[] = [];
      for (const delivery of deliveries) {
        const veto = await vetoed(delivery);
        if (veto) await finish(delivery, veto);
        else send.push(delivery);
      }
      if (send.length === 0) return;
      const result = await attempt(send);
      for (const delivery of send) await finish(delivery, result);
    }

    while (!spent.expired()) {
      const claimed = await call("claim_webhook_deliveries", {
        max_items: batch,
        lease: deliverOptions.lease ?? "2 minutes",
        max_attempts: maxAttempts,
      });
      const deliveries = (Array.isArray(claimed) ? claimed : [])
        .filter(isRecord)
        .map(toDelivery);
      const size = deliveries.length;
      const refused = await screen(deliveries);
      for (const [delivery, result] of refused) await finish(delivery, result);
      const allowed = deliveries.filter((delivery) => !refused.has(delivery));
      const batched = Map.groupBy(
        allowed.filter((delivery) => delivery.batch),
        (delivery) => delivery.endpointId,
      );
      const queue: (readonly WebhookDelivery[])[] = [
        ...allowed
          .filter((delivery) => !delivery.batch)
          .map((delivery) => [delivery]),
        ...batched.values(),
      ];
      await Promise.all(
        Array.from(
          { length: Math.min(concurrency, queue.length) },
          async () => {
            for (let next = queue.shift(); next; next = queue.shift())
              await handle(next);
          },
        ),
      );
      if (size < batch) break;
    }
    return counts;
  }

  const purge: Webhooks["purge"] = (purgeOptions = {}) =>
    db(
      "purge_webhook_deliveries",
      {
        older_than:
          purgeOptions.olderThan === undefined
            ? undefined
            : seconds(purgeOptions.olderThan),
        include_dead: purgeOptions.includeDead,
        batch: purgeOptions.batch,
      },
      (value) => Number(value ?? 0),
    );

  const client: Webhooks = {
    purge,
    purgeJob: (jobOptions) => async () => purge(jobOptions).orThrow(),
    publish: (event) =>
      db(
        "publish_webhook_event",
        {
          event_type: event.type,
          payload: event.data ?? {},
          tenant: event.tenant ?? null,
          event_id: event.id ?? null,
          ...(event.subject === undefined ? {} : { subject: event.subject }),
          ...(event.readPermission === undefined
            ? {}
            : { read_permission: event.readPermission }),
        },
        Number,
      ),
    dispatch: (input) =>
      db(
        "dispatch_webhook",
        {
          endpoint: input.endpointId,
          event_type: input.type,
          payload: input.data ?? {},
          run_id: input.runId ?? null,
          event_id: input.eventId ?? null,
        },
        String,
      ),
    redeliver: (deliveryId) =>
      db("redeliver_webhook", { delivery: deliveryId }, String),
    rotateSecret(endpointId, rotateOptions) {
      if (!store.rotate) {
        return AsyncResult.err(
          dbError("unexpected", "The secret store can't rotate secrets"),
        );
      }
      const rotate = store.rotate.bind(store);
      return AsyncResult.from(async () => {
        try {
          return ok(await rotate(endpointId, rotateOptions));
        } catch (cause) {
          return err(toBlockError(cause, mappers));
        }
      });
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
    sink: (sinkOptions = {}) => ({
      async send(events: readonly CloudEvent[]) {
        for (const event of events) {
          const tenant = event["partitionkey"];
          await call("publish_webhook_event", {
            event_type: stripTypePrefix(event.type, sinkOptions.typePrefix),
            payload: event.data ?? {},
            tenant: typeof tenant === "string" ? tenant : null,
            event_id: event.id,
            ...(event.subject === undefined ? {} : { subject: event.subject }),
          });
        }
      },
    }),
  };
  return withBlockHooks(client, options.hooks, {
    block: "webhooks",
    ...(options.events ? { logger: options.events.logger } : {}),
  });
}
