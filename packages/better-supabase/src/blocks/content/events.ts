import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The `content_entry.*` events. */
export interface ContentEntryEventData {
  readonly organizationId: string;
  /** The entry. */
  readonly id: string;
  readonly type: string;
  readonly locale: string;
  readonly slug: string;
  /** Draft, scheduled, published or archived, after the change. */
  readonly status: string;
  readonly translationGroupId: string;
}

/** The events of the `content` block: type to data. */
export type ContentEvents = {
  readonly "content_entry.created": ContentEntryEventData;
  readonly "content_entry.updated": ContentEntryEventData;
  readonly "content_entry.publish_requested": ContentEntryEventData;
  readonly "content_entry.scheduled": ContentEntryEventData;
  readonly "content_entry.unscheduled": ContentEntryEventData;
  readonly "content_entry.published": ContentEntryEventData;
  readonly "content_entry.archived": ContentEntryEventData;
};

/** The `content` block's event types, for its manifest and `onBlockEvent`. */
export const contentEvents: Events<ContentEvents> = defineEvents({
  "content_entry.created": event<ContentEntryEventData>(),
  "content_entry.updated": event<ContentEntryEventData>(),
  "content_entry.publish_requested": event<ContentEntryEventData>(),
  "content_entry.scheduled": event<ContentEntryEventData>(),
  "content_entry.unscheduled": event<ContentEntryEventData>(),
  "content_entry.published": event<ContentEntryEventData>(),
  "content_entry.archived": event<ContentEntryEventData>(),
});
