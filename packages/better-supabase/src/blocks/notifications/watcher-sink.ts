import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { SubjectEventData } from "../../core/block-events.ts";
import type { CloudEvent, EventSink } from "../../events/cloud-event.ts";
import type {
  NotificationTypes,
  Notifications,
  TypeName,
} from "./api-types.ts";

import { isRecord, optionalText } from "../shared.ts";

/** A subject-bound event's data, with its tenant. */
export type WatchedEventData = SubjectEventData & {
  readonly organizationId: string;
} & Readonly<Record<string, unknown>>;

/** How one event type reaches a subject's watchers. */
export interface WatcherRule<
  K extends NotificationTypes,
  N extends TypeName<K> = TypeName<K>,
> {
  /** The notification type to send. */
  readonly type: N;
  /** `all` (the default) reaches only `all` watchers; `participating` reaches both levels. */
  readonly activity?: "participating" | "all";
  /** Users to notify besides the watchers, such as a reminder's owner. */
  readonly recipients?: (data: WatchedEventData) => readonly string[];
  /** The notification data. Defaults to the event data. */
  readonly data?: (
    event: CloudEvent,
    data: WatchedEventData,
  ) => StandardSchemaV1.InferInput<K[N]>;
  readonly summary?: (data: WatchedEventData) => string;
}

export interface WatcherSinkOptions<K extends NotificationTypes> {
  /**
   * Event type (without `typePrefix`) to the notification type, or a rule.
   * Only subject-bound events (`SubjectEventType`) reach watchers; others
   * are skipped.
   */
  readonly types: Readonly<
    Record<string, TypeName<K> | WatcherRule<K> | undefined>
  >;
  /** Stripped from each event type. Defaults to `dev.better-supabase.`. */
  readonly typePrefix?: string;
}

function subjectData(event: CloudEvent): WatchedEventData | undefined {
  const data = isRecord(event.data) ? event.data : undefined;
  if (data === undefined) return undefined;
  const subjectType = optionalText(data["subjectType"]);
  const subjectId = optionalText(data["subjectId"]);
  const organizationId =
    optionalText(data["organizationId"]) ?? optionalText(event["partitionkey"]);
  if (
    subjectType === undefined ||
    subjectId === undefined ||
    organizationId === undefined
  ) {
    return undefined;
  }
  return { ...data, organizationId, subjectType, subjectId };
}

/**
 * An outbox sink that notifies the watchers of the subject an event is
 * about: `outbox.relay('watchers', watcherSink(notifications, { types }))`.
 * It reads `SubjectEventData` (tenant, subject type and id) from any block's
 * event, leaves out the actor (`actorId` or `authorId`), and keys each
 * notification by the event id, so a replayed event sends nothing new.
 * Build `notifications` with a service transport.
 */
export function watcherSink<K extends NotificationTypes>(
  notifications: Pick<Notifications<K>, "sink">,
  options: WatcherSinkOptions<K>,
): EventSink {
  return notifications.sink({
    ...(options.typePrefix === undefined
      ? {}
      : { typePrefix: options.typePrefix }),
    map(event) {
      const entry = options.types[event.type];
      if (entry === undefined) return null;
      const data = subjectData(event);
      if (data === undefined) return null;
      const rule: WatcherRule<K> =
        typeof entry === "string" ? { type: entry } : entry;
      const actorId =
        optionalText(data["actorId"]) ?? optionalText(data["authorId"]);
      const summary = rule.summary?.(data);
      return {
        type: rule.type,
        tenant: data.organizationId,
        subject: { type: data.subjectType, id: data.subjectId },
        recipients: rule.recipients?.(data) ?? [],
        activity: rule.activity ?? "all",
        key: `watch:${event.id}`,
        data: rule.data === undefined ? data : rule.data(event, data),
        ...(actorId === undefined ? {} : { actorId }),
        ...(summary === undefined ? {} : { summary }),
      };
    },
  });
}
