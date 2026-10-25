import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { BlockProblemOptions } from "../../core/problem.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { SqlClient } from "../../postgres/executor.ts";
import type { BlockTemporalOptions } from "../shared.ts";

/** How a delivery proves it came from the sender. */
export type IncomingVerify =
  | "none"
  | "standard-webhooks"
  | "hmac-sha256"
  | "shared-secret";

export interface IncomingWebhooksOptions
  extends BlockProblemOptions, BlockTemporalOptions {
  /**
   * A service SQL connection (`postgres.admin`): `receive` looks endpoints up
   * by token, counts the rate limit and stores deliveries with it.
   */
  readonly sql: SqlClient;
  /**
   * The caller's transport for `create`, `list`, `update` and the other
   * management calls, so `webhooks.manage` is checked for them. Defaults to
   * `sqlTransport(sql)`.
   */
  readonly transport?: BlockTransport;
  readonly mappers?: readonly ErrorMapper[];
  /** `withBlockHooks` hooks around the management methods. */
  readonly hooks?: BlockHooks<IncomingWebhooks>;
  /** Receives the errors `after` hooks throw. */
  readonly logger?: Logger;
  /** The schema of the `webhooks-in` module. Defaults to `better_supabase`. */
  readonly schema?: string;
  /**
   * The webhook inbox source deliveries are stored under. Defaults to
   * `webhook-in`.
   */
  readonly source?: string;
  /**
   * Deliveries per endpoint and period, counted with the `rate-limit` module's
   * `hit_rate_limit`. Unset: no limit.
   */
  readonly rateLimit?: {
    readonly max: number;
    /** Seconds, or a Postgres interval such as `1 minute`. */
    readonly period: number | string;
  };
  /** Request headers stored with each delivery. Defaults to none. */
  readonly keepHeaders?: readonly string[];
  /**
   * Where verified deliveries go. Defaults to `inboxDestination(sql, { source
   * })`, the webhook inbox; `jobsDestination(jobs, { queue })` sends them to a
   * jobs queue. A destination can route on the endpoint's metadata.
   */
  readonly destination?: IncomingDestination;
}

/** A verified delivery, handed to the destination. */
export interface IncomingDelivery {
  readonly endpoint: {
    readonly id: string;
    readonly tenant: string;
    readonly metadata: Readonly<Record<string, unknown>>;
  };
  /** `options.source`. */
  readonly source: string;
  /**
   * Unique per endpoint and delivery: the signed `webhook-id`, the HMAC, the
   * `webhook-id` header or a random id. A repeated delivery repeats it.
   */
  readonly messageId: string;
  /** The payload's `type` when it is a string. */
  readonly type: string | null;
  /** The parsed JSON body, or `{ body }` when it isn't JSON. */
  readonly payload: unknown;
  /** `options.keepHeaders` and the endpoint id header, lowercased. */
  readonly headers: Readonly<Record<string, string>>;
}

export interface IncomingDestinationResult {
  readonly id: string | number;
  /** True when the destination had the delivery already; `receive` answers 200. */
  readonly duplicate: boolean;
}

/**
 * Stores or forwards verified deliveries. It must detect a repeated
 * `endpoint.id` and `messageId` and report it as a duplicate. Versioned:
 * `apiVersion: 1`.
 */
export interface IncomingDestination {
  readonly apiVersion: 1;
  readonly name: string;
  deliver(delivery: IncomingDelivery): Promise<IncomingDestinationResult>;
}

export interface CreateIncomingWebhookInput {
  readonly tenant: string;
  readonly name: string;
  /** Defaults to `none`: the token in the URL is the only credential. */
  readonly verify?: IncomingVerify;
  readonly metadata?: Readonly<Record<string, unknown>>;
  /**
   * The header that carries the HMAC for `hmac-sha256`. Defaults to
   * `x-signature`.
   */
  readonly signatureHeader?: string;
  /** The record the endpoint belongs to, a type from `on`. */
  readonly subject?: { readonly type: string; readonly id: string };
}

/** An endpoint as members see it: everything but the token and secret. */
export interface IncomingWebhook {
  readonly id: string;
  readonly tenant: string;
  readonly name: string;
  readonly verify: IncomingVerify;
  readonly signatureHeader: string | null;
  readonly enabled: boolean;
  readonly maxBodyBytes: number;
  readonly receiveCount: number;
  readonly lastReceivedAt: Temporal.Instant | null;
  readonly lastStatus: number | null;
  readonly metadata: Readonly<Record<string, unknown>>;
  readonly subject: { readonly type: string; readonly id: string } | null;
  readonly createdBy: string | null;
  readonly createdAt: Temporal.Instant;
}

/** A new endpoint: its token (for the URL) and secret are shown once. */
export interface CreatedIncomingWebhook {
  readonly id: string;
  readonly tenant: string;
  readonly name: string;
  readonly verify: IncomingVerify;
  readonly token: string;
  readonly secret: string | null;
  readonly signatureHeader: string | null;
  readonly subject: { readonly type: string; readonly id: string } | null;
}

export interface UpdateIncomingWebhookInput {
  readonly name?: string;
  readonly metadata?: Readonly<Record<string, unknown>>;
  readonly verify?: IncomingVerify;
  readonly signatureHeader?: string;
}

export interface UpdatedIncomingWebhook {
  readonly id: string;
  readonly tenant: string;
  readonly name: string;
  readonly verify: IncomingVerify;
  readonly secret: string | null;
  readonly signatureHeader: string | null;
  readonly metadata: Readonly<Record<string, unknown>>;
}

export interface RotatedIncomingSecret {
  readonly secret: string;
  readonly previousSecretExpiresAt: Temporal.Instant | null;
}

export interface IncomingWebhooks {
  /**
   * The route for `/hooks/<token>`: finds the endpoint, checks the body size,
   * the rate limit and the signature, stores the delivery in the webhook inbox
   * with the endpoint's tenant and answers 202 (200 for a repeated delivery). A
   * delivery repeats when its signed `webhook-id` does (`standard-webhooks`),
   * when its body does (`hmac-sha256`, whose signature covers only the body),
   * or when its `webhook-id` header does (`none`). Needs a service connection.
   */
  receive(request: Request, token: string): Promise<Response>;
  /** Creates an endpoint for a tenant; the caller needs `webhooks.manage`. */
  create(
    input: CreateIncomingWebhookInput,
  ): AsyncResult<CreatedIncomingWebhook>;
  /** A new token, and with `rotateSecret` a new secret. */
  rotate(
    id: string,
    options?: { readonly rotateSecret?: boolean },
  ): AsyncResult<{ readonly token: string; readonly secret: string | null }>;
  rotateSecret(
    id: string,
    options?: { readonly grace?: Temporal.Duration | string },
  ): AsyncResult<RotatedIncomingSecret>;
  update(
    id: string,
    input: UpdateIncomingWebhookInput,
  ): AsyncResult<UpdatedIncomingWebhook>;
  setEnabled(id: string, enabled: boolean): AsyncResult<boolean>;
  remove(id: string): AsyncResult<boolean>;
  /**
   * A tenant's endpoints, or one subject's, as the caller sees them (the read
   * policy hides endpoints whose subject they can't read).
   */
  list(
    tenant: string,
    subject?: { readonly type: string; readonly id?: string },
  ): AsyncResult<readonly IncomingWebhook[]>;
}

export interface EndpointRow {
  readonly id: string;
  readonly tenant: string;
  readonly enabled: boolean;
  readonly verify: IncomingVerify;
  readonly secret: string | null;
  readonly signature_header: string | null;
  readonly max_body_bytes: number;
  readonly previous_secret?: string | null;
  readonly metadata?: Readonly<Record<string, unknown>> | null;
}
