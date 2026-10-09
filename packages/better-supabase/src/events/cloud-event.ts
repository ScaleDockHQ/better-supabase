import type { BlockEvent, BlockEventPattern } from "../core/block-events.ts";
import type { EventHub } from "../core/events.ts";

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

/**
 * A block event as a CloudEvent: `dev.better-supabase.support.started` with
 * the event data and the actor (`actorId`) as `data` and the tenant as
 * `partitionkey`.
 */
export function blockCloudEvent(
  event: BlockEvent,
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
    data: event.actorId
      ? { ...event.data, actorId: event.actorId }
      : event.data,
    ...(event.tenant ? { partitionkey: event.tenant } : {}),
  };
}

export interface ForwardBlockOptions extends CloudEventOptions {
  /** Only forward events that match, e.g. `support.*`. Defaults to all. */
  readonly types?: readonly BlockEventPattern[];
  /** Sink failures never fail the block call. Defaults to the `Logger`. */
  readonly onError?: (error: unknown, events: readonly CloudEvent[]) => void;
}

/**
 * Sends a CloudEvent for every block event (`support.*`, `organization.*`, ...) to
 * `sink`. Returns a function that stops forwarding. Like
 * `forwardMutations`, sends are tracked on `betterSupabase.events`.
 */
export function forwardBlockEvents(
  betterSupabase: { readonly events: EventHub },
  sink: EventSink,
  options: ForwardBlockOptions,
): () => void {
  const types = options.types;
  return betterSupabase.events.on("block", (event) => {
    if (
      types &&
      !types.some((pattern) =>
        pattern.endsWith(".*")
          ? event.type.startsWith(pattern.slice(0, -1))
          : pattern === event.type,
      )
    )
      return;
    const events = [blockCloudEvent(event, options)];
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
