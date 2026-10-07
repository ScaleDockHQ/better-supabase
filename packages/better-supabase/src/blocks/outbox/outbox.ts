import type { BlockTransport } from "../../core/block-transport.ts";
import type { CloudEvent, EventSink } from "../../events/index.ts";
import type { SqlClient } from "../../postgres/executor.ts";

import { type DbError, dbError } from "../../core/errors.ts";
import {
  type BlockProblemOptions,
  problemResponse,
} from "../../core/problem.ts";
import { type AsyncResult, toDbError } from "../../core/result.ts";
import { sqlIdent } from "../../core/template.ts";
import {
  asDbError,
  run,
  toInstant,
  workerId,
  type BlockTemporalOptions,
  applyTemporal,
} from "../shared.ts";
import { verifySharedSecret } from "../webhooks/verify.ts";

// ---------------------------------------------------------------------------
// Outbox (SQL module `outbox`)

/** One row of the outbox, as `outbox_claim` and `outbox_history` return it. */
export interface OutboxEvent {
  /** The cursor value: increases with every event. */
  readonly position: number;
  readonly id: string;
  readonly type: string;
  readonly payload: unknown;
  /** The module or function that wrote it, e.g. `better-supabase/blocks/organizations`. */
  readonly source: string | null;
  readonly subject: string | null;
  readonly tenant: string | null;
  readonly key: string | null;
  readonly actorId: string | null;
  readonly createdAt: Temporal.Instant;
}

export interface EmitOptions {
  readonly subject?: string;
  readonly tenant?: string;
  /** With a key, emitting again (per tenant) returns the first event. */
  readonly key?: string;
  readonly source?: string;
}

export interface OutboxOptions extends BlockTemporalOptions {
  /** The schema of the `outbox` module. Defaults to `better_supabase`. */
  readonly schema?: string;
  /** CloudEvents `source` of the relayed events, e.g. `https://crm.example.com`. */
  readonly source: string;
  /** Prepended to each type with a dot when relaying, e.g. `com.example`. Defaults to `dev.better-supabase`. */
  readonly typePrefix?: string;
}

export interface RegisterOptions {
  /** Type patterns such as `organization.*` or `invoice.paid`. Defaults to every event. */
  readonly types?: readonly string[];
  /** Start at the first kept event instead of after the latest one. */
  readonly fromStart?: boolean;
}

export interface RelayOptions {
  /** Events per claim and per `sink.send`. Defaults to 100. */
  readonly batch?: number;
  /** How long a claim holds the consumer. Defaults to `1 minute`. */
  readonly lease?: string;
  /** Stops claiming after this many milliseconds. */
  readonly budgetMs?: number;
  /** Identifies this worker in the lease. Defaults to a random id. */
  readonly owner?: string;
}

export interface RelayResult {
  readonly delivered: number;
  /** Set when the sink threw: the batch stays unacknowledged for the next run. */
  readonly error?: DbError;
}

/**
 * Takes a batch of outbox rows, with the actor and tenant that CloudEvents
 * leave out. Throwing leaves the batch for the next run.
 */
export type OutboxHandler = (events: readonly OutboxEvent[]) => unknown;

export interface OutboxRouteOptions
  extends Omit<RelayOptions, "owner">, BlockProblemOptions {
  /** The bearer secret, such as `process.env.CRON_SECRET`. */
  readonly secret: string | undefined;
  /** Consumer name to the sink its events go to, or a handler that takes the rows. */
  readonly consumers: Readonly<Record<string, EventSink | OutboxHandler>>;
  readonly onError?: (error: DbError, consumer: string) => void;
}

export interface OutboxRouteResult {
  readonly consumers: Readonly<Record<string, RelayResult>>;
  readonly budgetExhausted: boolean;
}

export interface HistoryFilter {
  readonly subject?: string;
  readonly type?: string;
  /** Only events after this position. */
  readonly after?: number;
  readonly limit?: number;
}

export interface Outbox {
  /** Writes an event in the current transaction and returns its id. */
  emit(
    type: string,
    payload?: unknown,
    options?: EmitOptions,
  ): AsyncResult<string>;
  /** Creates the consumer, or changes its types. Returns its cursor position. */
  register(consumer: string, options?: RegisterOptions): AsyncResult<number>;
  /** Removes the consumer, so purges stop waiting for it. */
  unregister(consumer: string): AsyncResult<boolean>;
  /**
   * Claims the consumer's next events, sends them to `sink` as CloudEvents and
   * moves the cursor, until none are left or the budget runs out. A sink that
   * throws leaves the batch for the next run, so delivery is at least once.
   */
  relay(
    consumer: string,
    sink: EventSink,
    options?: RelayOptions,
  ): Promise<RelayResult>;
  /**
   * Like `relay`, but hands `handler` the outbox rows themselves, with
   * `actorId`, `tenant` and `key`, for consumers inside the app (search
   * indexing, notifications) that need the actor.
   */
  consume(
    consumer: string,
    handler: OutboxHandler,
    options?: RelayOptions,
  ): Promise<RelayResult>;
  /** A `GET`/`POST` handler for a cron that relays every consumer at once, within one budget. */
  relayRoute(
    options: OutboxRouteOptions,
  ): (request: Request) => Promise<Response>;
  history(filter?: HistoryFilter): AsyncResult<readonly OutboxEvent[]>;
  /**
   * Deletes up to `batch` events (default 10,000) older than `olderThan` that
   * every consumer has passed. Call it again while it returns `batch`.
   */
  purge(olderThan?: string, batch?: number): AsyncResult<number>;
}

interface OutboxRow {
  readonly position: number;
  readonly id: string | number;
  readonly type: string;
  readonly payload: unknown;
  readonly source?: string | null;
  readonly subject?: string | null;
  readonly tenant?: string | number | null;
  readonly key?: string | null;
  readonly actor_id?: string | null;
  readonly created_at: string;
}

function isOutboxRow(value: unknown): value is OutboxRow {
  return (
    typeof value === "object" &&
    value !== null &&
    "position" in value &&
    "type" in value &&
    "created_at" in value
  );
}

function toEvent(row: OutboxRow): OutboxEvent {
  return {
    position: row.position,
    id: String(row.id),
    type: row.type,
    payload: row.payload,
    source: row.source ?? null,
    subject: row.subject ?? null,
    tenant:
      row.tenant === undefined || row.tenant === null
        ? null
        : String(row.tenant),
    key: row.key ?? null,
    actorId: row.actor_id ?? null,
    createdAt: toInstant(row.created_at),
  };
}

function toEvents(value: unknown): readonly OutboxEvent[] {
  if (!Array.isArray(value)) return [];
  return value.filter(isOutboxRow).map(toEvent);
}

/**
 * The CloudEvent for an outbox row: the row id as `id` (stable, so receivers
 * can deduplicate), the payload as `data`, the tenant as `partitionkey` and
 * the writing module as `producer`. The actor stays out of the context
 * attributes, which must not carry personal data.
 */
export function outboxCloudEvent(
  event: OutboxEvent,
  options: Pick<OutboxOptions, "source" | "typePrefix">,
): CloudEvent {
  return {
    specversion: "1.0",
    id: event.id,
    source: options.source,
    type: `${options.typePrefix ?? "dev.better-supabase"}.${event.type}`,
    ...(event.subject ? { subject: event.subject } : {}),
    time: event.createdAt.toString(),
    datacontenttype: "application/json",
    data: event.payload,
    ...(event.tenant ? { partitionkey: event.tenant } : {}),
    ...(event.source ? { producer: event.source } : {}),
  };
}

/** The outbox functions' argument names, for calls through a `BlockTransport`. */
const PARAMS: Readonly<Record<string, readonly string[]>> = {
  emit_event: ["event_type", "payload", "subject", "tenant", "key", "source"],
  outbox_register: ["consumer", "types", "from_start"],
  outbox_unregister: ["consumer"],
  outbox_claim: ["consumer", "owner", "max_events", "lease"],
  outbox_ack: ["consumer", "owner", "upto"],
  outbox_history: ["subject", "event_type", "after", "max_events"],
  purge_outbox: ["older_than", "batch"],
};

const isTransport = (
  source: SqlClient | BlockTransport,
): source is BlockTransport => "call" in source;

/**
 * The outbox over a server connection (`SqlClient`), or over a
 * `BlockTransport` such as `rpcTransport(serviceClient, { schema: "api" })`
 * for apps that reach the database only through the Data API. Over a
 * transport, `emit` writes in its own transaction.
 */
export function createOutbox(
  source: SqlClient | BlockTransport,
  options: OutboxOptions,
): Outbox {
  applyTemporal(options);
  const name = options.schema ?? "better_supabase";
  const schema = sqlIdent(name);
  const transport = isTransport(source) ? source : undefined;
  const call = async (fn: string, args: unknown[]): Promise<unknown> => {
    if (isTransport(source)) {
      const names = PARAMS[fn] ?? [];
      const value = await source.call(
        name,
        fn,
        Object.fromEntries(names.map((param, index) => [param, args[index]])),
      );
      return value ?? null;
    }
    const sql = source;
    const params = args.map((_, index) => `$${String(index + 1)}`).join(", ");
    const [row] = await sql.queryRaw<{ value: unknown }>(
      `select ${schema}.${sqlIdent(fn)}(${params}) as value`,
      args,
    );
    return row?.value ?? null;
  };

  const toSink =
    (sink: EventSink): OutboxHandler =>
    (events) =>
      sink.send(events.map((event) => outboxCloudEvent(event, options)));

  async function relay(
    consumer: string,
    handler: OutboxHandler,
    relayOptions: RelayOptions = {},
    deadline?: number,
  ): Promise<RelayResult> {
    const owner = relayOptions.owner ?? workerId();
    const batch = relayOptions.batch ?? 100;
    const lease = relayOptions.lease ?? "1 minute";
    const until =
      deadline ??
      (relayOptions.budgetMs === undefined
        ? Number.POSITIVE_INFINITY
        : Date.now() + relayOptions.budgetMs);
    let delivered = 0;
    while (Date.now() < until) {
      let events: readonly OutboxEvent[];
      try {
        events = toEvents(
          await call("outbox_claim", [consumer, owner, batch, lease]),
        );
      } catch (cause) {
        return { delivered, error: asDbError(cause) };
      }
      const last = events.at(-1);
      if (last === undefined) {
        await call("outbox_ack", [consumer, owner, null]).catch(() => null);
        break;
      }
      try {
        await handler(events);
      } catch (cause) {
        await call("outbox_ack", [consumer, owner, null]).catch(() => null);
        return { delivered, error: toDbError(cause) };
      }
      try {
        await call("outbox_ack", [consumer, owner, last.position]);
      } catch (cause) {
        return { delivered, error: asDbError(cause) };
      }
      delivered += events.length;
      if (events.length < batch) break;
    }
    return { delivered };
  }

  return {
    emit: (type, payload = {}, emitOptions = {}) =>
      run(async () =>
        String(
          await call("emit_event", [
            type,
            transport ? payload : JSON.stringify(payload),
            emitOptions.subject ?? null,
            emitOptions.tenant ?? null,
            emitOptions.key ?? null,
            emitOptions.source ?? null,
          ]),
        ),
      ),
    register: (consumer, registerOptions = {}) =>
      run(async () =>
        Number(
          await call("outbox_register", [
            consumer,
            registerOptions.types ?? null,
            registerOptions.fromStart ?? false,
          ]),
        ),
      ),
    unregister: (consumer) =>
      run(async () => (await call("outbox_unregister", [consumer])) === true),
    relay: (consumer, sink, relayOptions) =>
      relay(consumer, toSink(sink), relayOptions),
    consume: (consumer, handler, relayOptions) =>
      relay(consumer, handler, relayOptions),
    relayRoute(routeOptions) {
      const secret = routeOptions.secret;
      if (!secret) {
        throw new TypeError(
          "relayRoute needs a secret, such as process.env.CRON_SECRET",
        );
      }
      return async (request) => {
        const instance = new URL(request.url).pathname;
        if (request.method !== "GET" && request.method !== "POST") {
          return new Response(null, {
            status: 405,
            headers: { allow: "GET, POST" },
          });
        }
        if (!verifySharedSecret(request, secret)) {
          return problemResponse(
            dbError("unauthorized", "The relay route needs its bearer secret"),
            { instance, format: routeOptions.problem },
          );
        }
        const deadline = Date.now() + (routeOptions.budgetMs ?? 50_000);
        // Each consumer has its own cursor and lease, so they relay side by
        // side within the one budget.
        const entries = Object.entries(routeOptions.consumers);
        const relayed = await Promise.all(
          entries.map(async ([consumer, sink]) => {
            const result = await relay(
              consumer,
              typeof sink === "function" ? sink : toSink(sink),
              routeOptions,
              deadline,
            );
            if (result.error) routeOptions.onError?.(result.error, consumer);
            return result;
          }),
        );
        const results: Record<string, RelayResult> = {};
        entries.forEach(([consumer], index) => {
          results[consumer] = relayed[index]!;
        });
        const result: OutboxRouteResult = {
          consumers: results,
          budgetExhausted: Date.now() >= deadline,
        };
        return Response.json(result);
      };
    },
    history: (filter = {}) =>
      run(async () =>
        toEvents(
          await call("outbox_history", [
            filter.subject ?? null,
            filter.type ?? null,
            filter.after ?? 0,
            filter.limit ?? 100,
          ]),
        ),
      ),
    purge: (olderThan, batch) =>
      run(async () =>
        Number(await call("purge_outbox", [olderThan ?? null, batch ?? null])),
      ),
  };
}
