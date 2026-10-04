import type { MutationNotice } from "../core/events.ts";
import type { EventHub } from "../core/events.ts";
import type { KitEvent, KitEventPattern } from "../core/kit-events.ts";
import type { MutationIntent } from "../core/plugin.ts";
import type { SchemaMeta } from "../schema/types.ts";

import { nowInstant } from "../core/temporal.ts";

/** A CloudEvents 1.0 event. Extension attributes are lowercase alphanumerics. */
export interface CloudEvent<T = unknown> {
  readonly specversion: "1.0";
  readonly id: string;
  readonly source: string;
  readonly type: string;
  readonly subject?: string;
  readonly time?: string;
  readonly datacontenttype?: string;
  readonly dataschema?: string;
  readonly data?: T;
  readonly [extension: string]: unknown;
}

export const ROW_EVENT_TYPES: { readonly [K in MutationIntent]: string } = {
  insert: "dev.better-supabase.row.created",
  upsert: "dev.better-supabase.row.upserted",
  update: "dev.better-supabase.row.updated",
  delete: "dev.better-supabase.row.deleted",
  softDelete: "dev.better-supabase.row.softdeleted",
};

export interface RowEventData {
  readonly table: string;
  readonly row: Readonly<Record<string, unknown>>;
}

export interface CloudEventOptions {
  /** URI-reference of the producer, e.g. `https://crm.example.com` or `/crm`. */
  readonly source: string;
  /** Replaces the `dev.better-supabase` type prefix. */
  readonly typePrefix?: string;
  readonly id?: () => string;
  readonly now?: () => Temporal.Instant;
}

/** Sends events somewhere: a queue, a bus, an outbox table, an HTTP endpoint. */
export interface EventSink {
  send(events: readonly CloudEvent[]): void | Promise<void>;
}

function subjectOf(
  meta: SchemaMeta | undefined,
  table: string,
  row: Readonly<Record<string, unknown>>,
): string | undefined {
  const key = meta?.tables[table]?.primaryKey;
  if (!key || key.length === 0) return undefined;
  const values = key.map((column) => row[column]);
  if (values.some((value) => value === undefined || value === null))
    return undefined;
  return `${table}/${values.map((value) => encodeURIComponent(String(value))).join(",")}`;
}

/**
 * One CloudEvent per mutated row: `dev.better-supabase.row.created` with the
 * app-cased row as `data`, the primary key as `subject`, the tenant as
 * `partitionkey` and the actor as `actorid`. Writes that return no rows (soft
 * deletes, `returning: false`) send one event per known primary key, with the
 * key as `row`.
 */
export function toCloudEvents(
  notice: MutationNotice,
  options: CloudEventOptions & { readonly meta?: SchemaMeta },
): CloudEvent<RowEventData>[] {
  const intent = notice.intent ?? notice.kind;
  const type = options.typePrefix
    ? `${options.typePrefix}.row.${ROW_EVENT_TYPES[intent].split(".").at(-1)!}`
    : ROW_EVENT_TYPES[intent];
  const time = (options.now ?? nowInstant)().toString();
  const tenant = notice.tenant ?? notice.context.tenant;
  const rows = notice.rows.length > 0 ? notice.rows : (notice.keys ?? []);
  return rows.map((row) => {
    const subject = subjectOf(options.meta, notice.table, row);
    return {
      specversion: "1.0",
      id: options.id?.() ?? crypto.randomUUID(),
      source: options.source,
      type,
      ...(subject ? { subject } : {}),
      time,
      datacontenttype: "application/json",
      data: { table: notice.table, row },
      ...(tenant ? { partitionkey: tenant } : {}),
      ...(notice.context.actor?.id ? { actorid: notice.context.actor.id } : {}),
    };
  });
}

export interface ForwardOptions extends CloudEventOptions {
  /** Only forward these tables or kinds. */
  readonly filter?: (notice: MutationNotice) => boolean;
  /** Sink failures never fail the mutation. Defaults to the `Logger`. */
  readonly onError?: (error: unknown, events: readonly CloudEvent[]) => void;
}

/**
 * Sends a CloudEvent for every mutation to `sink`. Returns a function that
 * stops forwarding. Sends in flight are tracked on `betterSupabase.events`
 * (`settled()`), which the Next adapter hands to `after()` and the edge
 * entry to `waitUntil`. Use an outbox (SQL kit) when events must not be lost.
 */
export function forwardMutations(
  betterSupabase: { readonly events: EventHub; readonly meta: SchemaMeta },
  sink: EventSink,
  options: ForwardOptions,
): () => void {
  return betterSupabase.events.on("mutation", (notice) => {
    if (options.filter && !options.filter(notice)) return;
    const events = toCloudEvents(notice, {
      ...options,
      meta: betterSupabase.meta,
    });
    if (events.length === 0) return;
    const report = (error: unknown) => {
      (
        options.onError ??
        ((cause) => {
          betterSupabase.events.logger.error("event sink failed", { cause });
        })
      )(error, events);
    };
    try {
      betterSupabase.events.track(
        Promise.resolve(sink.send(events)).catch(report),
      );
    } catch (error) {
      report(error);
    }
  });
}

/**
 * A kit event as a CloudEvent: `dev.better-supabase.support.started` with
 * the event data as `data`, the tenant as `partitionkey` and the actor as
 * `actorid`.
 */
export function kitCloudEvent(
  event: KitEvent,
  options: CloudEventOptions,
): CloudEvent {
  return {
    specversion: "1.0",
    id: options.id?.() ?? crypto.randomUUID(),
    source: options.source,
    type: `${options.typePrefix ?? "dev.better-supabase"}.${event.type}`,
    ...(event.subject ? { subject: event.subject } : {}),
    time: (options.now?.() ?? event.time).toString(),
    datacontenttype: "application/json",
    data: event.data,
    ...(event.tenant ? { partitionkey: event.tenant } : {}),
    ...(event.actorId ? { actorid: event.actorId } : {}),
  };
}

export interface ForwardKitOptions extends CloudEventOptions {
  /** Only forward events that match, e.g. `support.*`. Defaults to all. */
  readonly types?: readonly KitEventPattern[];
  /** Sink failures never fail the kit call. Defaults to the `Logger`. */
  readonly onError?: (error: unknown, events: readonly CloudEvent[]) => void;
}

/**
 * Sends a CloudEvent for every kit event (`support.*`, `org.*`, ...) to
 * `sink`. Returns a function that stops forwarding. Like
 * `forwardMutations`, sends are tracked on `betterSupabase.events`.
 */
export function forwardKitEvents(
  betterSupabase: { readonly events: EventHub },
  sink: EventSink,
  options: ForwardKitOptions,
): () => void {
  const types = options.types;
  return betterSupabase.events.on("kit", (event) => {
    if (
      types &&
      !types.some((pattern) =>
        pattern.endsWith(".*")
          ? event.type.startsWith(pattern.slice(0, -1))
          : pattern === event.type,
      )
    )
      return;
    const events = [kitCloudEvent(event, options)];
    const report = (error: unknown) => {
      (
        options.onError ??
        ((cause) => {
          betterSupabase.events.logger.error("event sink failed", { cause });
        })
      )(error, events);
    };
    try {
      betterSupabase.events.track(
        Promise.resolve(sink.send(events)).catch(report),
      );
    } catch (error) {
      report(error);
    }
  });
}

export type HttpMode = "structured" | "binary" | "batch";

const STRUCTURED = "application/cloudevents+json";
const BATCH = "application/cloudevents-batch+json";

/** The HTTP protocol binding: headers and body for one event (or a batch). */
export function toHttp(
  events: CloudEvent | readonly CloudEvent[],
  mode: HttpMode = "structured",
): { headers: Record<string, string>; body: string }[] {
  // SAFETY: events is one CloudEvent or a list of them, and Array.isArray ruled
  // out the list.
  const list: readonly CloudEvent[] = Array.isArray(events)
    ? events
    : [events as CloudEvent];
  switch (mode) {
    case "batch":
      return [
        { headers: { "content-type": BATCH }, body: JSON.stringify(list) },
      ];
    case "structured":
      return list.map((event) => ({
        headers: { "content-type": STRUCTURED },
        body: JSON.stringify(event),
      }));
    case "binary":
      return list.map((event) => {
        const headers: Record<string, string> = {};
        for (const [key, value] of Object.entries(event)) {
          if (
            key === "data" ||
            key === "datacontenttype" ||
            value === undefined
          )
            continue;
          headers[`ce-${key}`] = encodeURIComponent(String(value)).replaceAll(
            "%20",
            " ",
          );
        }
        headers["content-type"] = event.datacontenttype ?? "application/json";
        return {
          headers,
          body: event.data === undefined ? "" : JSON.stringify(event.data),
        };
      });
    default: {
      const unknown: never = mode;
      throw new TypeError(`Unknown CloudEvents mode ${String(unknown)}`);
    }
  }
}

export function isCloudEvent(value: unknown): value is CloudEvent {
  if (typeof value !== "object" || value === null) return false;
  // SAFETY: value is a non-null object here, and every field is checked below.
  const event = value as Record<string, unknown>;
  return (
    event["specversion"] === "1.0" &&
    typeof event["id"] === "string" &&
    typeof event["source"] === "string" &&
    typeof event["type"] === "string"
  );
}

/** Reads CloudEvents from a request in any of the three HTTP modes. */
export async function fromHttp(request: Request): Promise<CloudEvent[]> {
  const contentType = request.headers.get("content-type") ?? "";
  const text = await request.text();
  if (contentType.startsWith(BATCH)) {
    const parsed: unknown = JSON.parse(text);
    if (!Array.isArray(parsed) || !parsed.every(isCloudEvent))
      throw new TypeError("Invalid CloudEvents batch");
    return parsed;
  }
  if (contentType.startsWith(STRUCTURED)) {
    const parsed: unknown = JSON.parse(text);
    if (!isCloudEvent(parsed)) throw new TypeError("Invalid CloudEvent");
    return [parsed];
  }
  const event: Record<string, unknown> = {};
  for (const [key, value] of request.headers) {
    if (key.startsWith("ce-")) event[key.slice(3)] = decodeURIComponent(value);
  }
  if (contentType) event["datacontenttype"] = contentType;
  if (text)
    // SAFETY: JSON.parse returns any; this keeps the event data unknown.
    event["data"] = contentType.includes("json")
      ? (JSON.parse(text) as unknown)
      : text;
  if (!isCloudEvent(event)) throw new TypeError("Request is not a CloudEvent");
  return [event];
}

export interface HttpSinkOptions {
  readonly mode?: HttpMode;
  readonly headers?: Readonly<Record<string, string>>;
  readonly fetch?: typeof fetch;
}

/** POSTs events to `url`. Non-2xx responses reject. */
export function httpSink(
  url: string | URL,
  options: HttpSinkOptions = {},
): EventSink {
  const send = options.fetch ?? fetch;
  return {
    async send(events) {
      for (const message of toHttp(events, options.mode ?? "batch")) {
        const response = await send(url, {
          method: "POST",
          headers: { ...options.headers, ...message.headers },
          body: message.body,
        });
        if (!response.ok)
          throw new Error(`Event sink responded ${String(response.status)}`);
      }
    },
  };
}

export {
  KIT_ATTRIBUTES,
  kitEventAttributes,
  onKitEvent,
} from "../core/kit-events.ts";
export type {
  InvitationEventData,
  KitEvent,
  KitEventMap,
  KitEventMeta,
  KitEventPattern,
  KitEventsMatching,
  KitEventType,
  NotificationEventData,
  OrgEventData,
  SupportEventData,
  WebhookEventData,
} from "../core/kit-events.ts";
