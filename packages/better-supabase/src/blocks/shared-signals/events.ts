import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `ssf_stream.*`: the stream and the receiver that manages it. */
export interface SsfStreamEventData {
  readonly streamId: string;
  readonly receiver: string;
  readonly tenant: string | null;
}

/** `ssf_stream.created` also carries the delivery method URN. */
export interface SsfStreamCreatedEventData extends SsfStreamEventData {
  readonly method: string;
}

/** `ssf_stream.status_changed` carries the new status and its reason. */
export interface SsfStreamStatusEventData extends SsfStreamEventData {
  readonly status: "enabled" | "paused" | "disabled";
  readonly reason: string | null;
}

/** The events of the `shared-signals` block: type to data. */
export type SharedSignalsEvents = {
  readonly "ssf_stream.created": SsfStreamCreatedEventData;
  readonly "ssf_stream.status_changed": SsfStreamStatusEventData;
  readonly "ssf_stream.deleted": SsfStreamEventData;
};

/**
 * The `shared-signals` block's event types, for its manifest and
 * `onBlockEvent`.
 */
export const sharedSignalsEvents: Events<SharedSignalsEvents> = defineEvents({
  "ssf_stream.created": event<SsfStreamCreatedEventData>(),
  "ssf_stream.status_changed": event<SsfStreamStatusEventData>(),
  "ssf_stream.deleted": event<SsfStreamEventData>(),
});
