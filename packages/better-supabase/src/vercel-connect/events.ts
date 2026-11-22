import type { Outbox } from "../blocks/outbox/outbox.ts";
import type { DbError } from "../core/errors.ts";
import type { BlockProblemOptions } from "../core/problem.ts";
import type { SqlClient } from "../postgres/executor.ts";

import { isRecord } from "../core/block-helpers.ts";
import { dbError, dbErrorOf } from "../core/errors.ts";
import { methodNotAllowed, problemResponse } from "../core/problem.ts";
import { AsyncResult, err, ok } from "../core/result.ts";
import { temporal } from "../core/temporal-required.ts";

/** Where Connect stands on a subscription, as `@vercel/connect/mcp` names it. */
export type ConnectEventStatus =
  | "pending"
  | "active"
  | "needs_auth"
  | "stopped"
  | "expired"
  | "failed";

/** The statuses whose deliveries the route accepts. */
const LIVE: ReadonlySet<ConnectEventStatus> = new Set(["pending", "active"]);

/**
 * A delivery from Vercel Connect, as `experimental_verifyMcpEvent` returns it:
 * one event of a subscription, or a control message about the stream.
 */
export interface ConnectEventDelivery {
  readonly version: 1;
  readonly deliveryId: string;
  readonly subscriptionId: string;
  readonly source: { readonly type: "mcp"; readonly connectorId: string };
  readonly context: Readonly<Record<string, unknown>>;
  readonly event?: {
    readonly eventId: string;
    readonly name: string;
    readonly timestamp: string;
    readonly data: Readonly<Record<string, unknown>>;
    readonly cursor: string | null;
    readonly _meta?: Readonly<Record<string, unknown>>;
  };
  readonly control?:
    | {
        readonly type: "gap";
        readonly cursor: string | null;
        readonly truncated?: true;
      }
    | {
        readonly type: "terminated";
        readonly error: {
          readonly code: number;
          readonly message: string;
          readonly data?: unknown;
        };
      };
}

/** What the route tells `verifyMcpEvent` about itself. */
export interface ConnectEventVerifyOptions {
  /**
   * The path the subscription's destination names, such as
   * `/api/connect/events`.
   */
  readonly path: string;
  readonly ownerId?: string;
  readonly audience?: string;
  readonly issuer?: string;
  readonly projectId?: string;
  readonly environment?: string;
  readonly customEnvironmentId?: string;
  readonly branch?: string;
}

/**
 * `experimental_verifyMcpEvent` from `@vercel/connect/mcp`: checks Connect's
 * OIDC token and the envelope, and throws when either is wrong.
 */
export type ConnectEventVerifier = (
  request: Request,
  options: ConnectEventVerifyOptions,
) => Promise<ConnectEventDelivery>;

/** One watch a tenant has with a connector. */
export interface ConnectEventSubscription {
  /** Connect's subscription id. */
  readonly id: string;
  /** The organization the events belong to. */
  readonly tenantId: string;
  readonly connectorId: string;
  /** The user the watch runs as; it becomes the event's `subject`. */
  readonly userId?: string;
  /** The event name the subscription asked for. */
  readonly name: string;
  readonly status: ConnectEventStatus;
  readonly statusReason?: string;
  readonly expiresAt?: Temporal.Instant;
  readonly createdAt?: Temporal.Instant;
}

/** The per-tenant table of subscriptions. */
export interface ConnectEventSubscriptions {
  get(id: string): AsyncResult<ConnectEventSubscription | null>;
  /** Inserts the subscription, or replaces the one with the same id. */
  save(subscription: ConnectEventSubscription): AsyncResult<void>;
  setStatus(
    id: string,
    status: ConnectEventStatus,
    reason?: string,
  ): AsyncResult<boolean>;
  listByTenant(
    tenantId: string,
    options?: { readonly status?: ConnectEventStatus },
  ): AsyncResult<readonly ConnectEventSubscription[]>;
  remove(id: string): AsyncResult<boolean>;
}

export interface ConnectEventSubscriptionsOptions {
  /** Defaults to `connect_event_subscriptions`. */
  readonly table?: string;
  /** Defaults to `public`. */
  readonly schema?: string;
}

const IDENTIFIER = /^[a-z_][a-z0-9_]*$/i;

function quoted(name: string, option: string): string {
  if (!IDENTIFIER.test(name)) {
    throw new TypeError(`${option}: "${name}" is not a SQL identifier`);
  }

  return `"${name}"`;
}

const STATUSES: ReadonlySet<string> = new Set([
  "pending",
  "active",
  "needs_auth",
  "stopped",
  "expired",
  "failed",
]);

const isStatus = (value: unknown): value is ConnectEventStatus =>
  typeof value === "string" && STATUSES.has(value);

const instantOf = (value: unknown): Temporal.Instant | undefined => {
  if (value instanceof Date) {
    return temporal().Instant.fromEpochMilliseconds(value.getTime());
  }

  return typeof value === "string"
    ? temporal().Instant.from(new Date(value).toISOString())
    : undefined;
};

function rowOf(row: Record<string, unknown>): ConnectEventSubscription {
  const status = row["status"];
  const expiresAt = instantOf(row["expires_at"]);
  const createdAt = instantOf(row["created_at"]);
  const userId = row["user_id"];
  const reason = row["status_reason"];

  return {
    id: String(row["id"]),
    tenantId: String(row["tenant_id"]),
    connectorId: String(row["connector_id"]),
    name: String(row["name"]),
    status: isStatus(status) ? status : "failed",
    ...(typeof userId === "string" ? { userId } : {}),
    ...(typeof reason === "string" ? { statusReason: reason } : {}),
    ...(expiresAt === undefined ? {} : { expiresAt }),
    ...(createdAt === undefined ? {} : { createdAt }),
  };
}

/**
 * The subscriptions in a table you create (the docs page has the SQL), over a
 * service connection (`postgres.admin`). The table has row level security on
 * and no policy, so only the service connection reads it.
 */
export function postgresConnectEventSubscriptions(
  sql: SqlClient,
  options: ConnectEventSubscriptionsOptions = {},
): ConnectEventSubscriptions {
  const table = `${quoted(options.schema ?? "public", "schema")}.${quoted(options.table ?? "connect_event_subscriptions", "table")}`;

  const run = <T>(
    text: string,
    params: unknown[],
    map: (rows: Record<string, unknown>[]) => T,
  ): AsyncResult<T> =>
    AsyncResult.from(async () => {
      try {
        return ok(map(await sql.queryRaw(text, params)));
      } catch (cause) {
        return err(
          dbErrorOf(cause) ??
            dbError("network", "The subscription table could not be reached.", {
              hint: "CONNECT_EVENTS_STORE_UNAVAILABLE",
            }),
        );
      }
    });

  return {
    get: (id) =>
      run(`select * from ${table} where id = $1`, [id], ([row]) =>
        row === undefined ? null : rowOf(row),
      ),
    save: (s) =>
      run(
        `insert into ${table}
           (id, tenant_id, connector_id, user_id, name, status, status_reason, expires_at)
         values ($1, $2, $3, $4, $5, $6, $7, $8)
         on conflict (id) do update set
           tenant_id = excluded.tenant_id,
           connector_id = excluded.connector_id,
           user_id = excluded.user_id,
           name = excluded.name,
           status = excluded.status,
           status_reason = excluded.status_reason,
           expires_at = excluded.expires_at,
           updated_at = now()`,
        [
          s.id,
          s.tenantId,
          s.connectorId,
          s.userId ?? null,
          s.name,
          s.status,
          s.statusReason ?? null,
          s.expiresAt === undefined
            ? null
            : new Date(s.expiresAt.epochMilliseconds),
        ],
        () => undefined,
      ),
    setStatus: (id, status, reason) =>
      run(
        `update ${table} set status = $2, status_reason = $3, updated_at = now()
         where id = $1 returning id`,
        [id, status, reason ?? null],
        (rows) => rows.length > 0,
      ),
    listByTenant: (tenantId, listOptions = {}) =>
      run(
        `select * from ${table} where tenant_id = $1
           and ($2::text is null or status = $2) order by created_at, id`,
        [tenantId, listOptions.status ?? null],
        (rows) => rows.map(rowOf),
      ),
    remove: (id) =>
      run(
        `delete from ${table} where id = $1 returning id`,
        [id],
        (rows) => rows.length > 0,
      ),
  };
}

/** What `onDelivery` is told about each delivery the route handled. */
export interface ConnectEventOutcome {
  readonly deliveryId: string;
  readonly subscriptionId: string;
  /**
   * `accepted`: written to the outbox. `ignored`: unknown or stopped
   * subscription.
   */
  readonly status: "accepted" | "ignored";
  readonly tenantId?: string;
  readonly type?: string;
}

export interface ConnectEventRouteOptions extends BlockProblemOptions {
  /** `experimental_verifyMcpEvent` from `@vercel/connect/mcp`. */
  readonly verify: ConnectEventVerifier;
  /** The path the subscriptions' `destination` names. */
  readonly path: string;
  /**
   * Overrides for the trusted receiver; the project and environment default to
   * Vercel's env.
   */
  readonly receiver?: Omit<ConnectEventVerifyOptions, "path">;
  /** The outbox, written with the service role. */
  readonly outbox: Pick<Outbox, "emit">;
  readonly subscriptions: Pick<ConnectEventSubscriptions, "get" | "setStatus">;
  /** Prefix of the event types. Default `connect.`. */
  readonly typePrefix?: string;
  /**
   * Sees every accepted or ignored delivery, for logs and metrics. It runs
   * after the delivery is stored and can't change the response; an error it
   * throws is dropped.
   */
  readonly onDelivery?: (outcome: ConnectEventOutcome) => void | Promise<void>;
}

function verificationFailure(cause: unknown): DbError {
  const code =
    isRecord(cause) && cause["name"] === "McpEventVerificationError"
      ? cause["code"]
      : undefined;

  if (code === "invalid_delivery" || code === undefined) {
    return dbError("unauthorized", "The delivery could not be verified.", {
      code: "INVALID_DELIVERY",
    });
  }

  if (code === "verification_unavailable") {
    return dbError("network", "Delivery verification is temporarily down.", {
      code: "VERIFICATION_UNAVAILABLE",
    });
  }

  return dbError("unexpected", "The event receiver is not configured.", {
    code: "CONNECT_EVENTS_CONFIGURATION",
  });
}

const REASON_LIMIT = 500;

/**
 * A route for the events Vercel Connect delivers to a subscription. It checks
 * the delivery's OIDC token, looks the subscription up in the per-tenant table
 * and writes the event to the outbox under the tenant, keyed by the delivery
 * id, so a redelivery adds nothing. It answers 200 only after the outbox holds
 * the event and 503 when it could not write, so Connect retries.
 *
 * A delivery for a subscription that is unknown or no longer active is
 * acknowledged and dropped. A `gap` control message becomes a `<prefix>gap`
 * event, so a consumer can resync; a `terminated` one becomes
 * `<prefix>terminated` and marks the subscription `failed`.
 */
export function connectEventRoute(
  options: ConnectEventRouteOptions,
): (request: Request) => Promise<Response> {
  const prefix = options.typePrefix ?? "connect.";
  const format = { format: options.problem };

  const respond = (status: ConnectEventOutcome["status"], id?: string) =>
    Response.json({ status, ...(id === undefined ? {} : { id }) });

  const notify = async (outcome: ConnectEventOutcome): Promise<void> => {
    try {
      await options.onDelivery?.(outcome);
    } catch {
      // An observer can't change what Connect is told.
    }
  };

  return async (request) => {
    if (request.method !== "POST") {
      return methodNotAllowed(["POST"]);
    }

    let delivery: ConnectEventDelivery;

    try {
      delivery = await options.verify(request, {
        ...options.receiver,
        path: options.path,
      });
    } catch (cause) {
      return problemResponse(verificationFailure(cause), format);
    }

    const found = await options.subscriptions.get(delivery.subscriptionId);

    if (!found.ok) {
      return problemResponse(found.error, format);
    }

    const subscription = found.data;

    const base = {
      deliveryId: delivery.deliveryId,
      subscriptionId: delivery.subscriptionId,
    };

    if (subscription === null || !LIVE.has(subscription.status)) {
      await notify({ ...base, status: "ignored" });

      return respond("ignored");
    }

    const { event, control } = delivery;

    const written = await (event === undefined
      ? emitControl(options, prefix, subscription, delivery, control)
      : emitEvent(options, prefix, subscription, delivery, event));

    if (!written.ok) {
      return problemResponse(written.error, format);
    }

    await notify({
      ...base,
      status: "accepted",
      tenantId: subscription.tenantId,
      type: written.data.type,
    });

    return respond("accepted", written.data.id);
  };
}

interface Written {
  readonly id: string;
  readonly type: string;
}

function emitEvent(
  options: ConnectEventRouteOptions,
  prefix: string,
  subscription: ConnectEventSubscription,
  delivery: ConnectEventDelivery,
  event: NonNullable<ConnectEventDelivery["event"]>,
): AsyncResult<Written> {
  const type = `${prefix}${event.name}`;

  return write(options, subscription, delivery, type, {
    connectorId: delivery.source.connectorId,
    subscriptionId: delivery.subscriptionId,
    deliveryId: delivery.deliveryId,
    eventId: event.eventId,
    name: event.name,
    timestamp: event.timestamp,
    cursor: event.cursor,
    data: event.data,
    context: delivery.context,
  });
}

function emitControl(
  options: ConnectEventRouteOptions,
  prefix: string,
  subscription: ConnectEventSubscription,
  delivery: ConnectEventDelivery,
  control: ConnectEventDelivery["control"],
): AsyncResult<Written> {
  const common = {
    connectorId: delivery.source.connectorId,
    subscriptionId: delivery.subscriptionId,
    deliveryId: delivery.deliveryId,
  };

  if (control === undefined) {
    return AsyncResult.err(
      dbError("unauthorized", "The delivery carries no event.", {
        code: "INVALID_DELIVERY",
      }),
    );
  }

  switch (control.type) {
    case "gap": {
      return write(options, subscription, delivery, `${prefix}gap`, {
        ...common,
        cursor: control.cursor,
        truncated: control.truncated === true,
      });
    }

    case "terminated": {
      const reason = control.error.message.slice(0, REASON_LIMIT);

      return write(
        options,
        subscription,
        delivery,
        `${prefix}terminated`,
        { ...common, code: control.error.code, message: reason },
        () =>
          options.subscriptions.setStatus(subscription.id, "failed", reason),
      );
    }

    default: {
      const unreachable: never = control;

      return unreachable;
    }
  }
}

function write(
  options: ConnectEventRouteOptions,
  subscription: ConnectEventSubscription,
  delivery: ConnectEventDelivery,
  type: string,
  payload: Record<string, unknown>,
  after?: () => AsyncResult<boolean>,
): AsyncResult<Written> {
  return options.outbox
    .emit({
      type,
      payload,
      tenant: subscription.tenantId,
      key: `connect:${delivery.deliveryId}`,
      source: "vercel-connect",
      ...(subscription.userId === undefined
        ? {}
        : { subject: subscription.userId }),
    })
    .andThen(async (id) => {
      // The event is stored; a failed status update must not fail the delivery,
      // since the redelivery would add nothing and the status stays as it was.
      await after?.();

      return ok({ id, type });
    });
}
