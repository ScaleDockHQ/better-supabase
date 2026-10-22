import type {
  SegmentEventData,
  SegmentMemberEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `segments` block: type to data. */
export type SegmentsEvents = {
  readonly "segment.saved": SegmentEventData;
  readonly "segment.removed": SegmentEventData;
  readonly "segment.entered": SegmentMemberEventData;
  readonly "segment.left": SegmentMemberEventData;
};

/** The `segments` block's event types, for its manifest and `onBlockEvent`. */
export const segmentsEvents: Events<SegmentsEvents> = defineEvents({
  "segment.saved": event<SegmentEventData>(),
  "segment.removed": event<SegmentEventData>(),
  "segment.entered": event<SegmentMemberEventData>(),
  "segment.left": event<SegmentMemberEventData>(),
});
