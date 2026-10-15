import type { Events, SupportEventData } from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `support-sessions` block: type to data. */
export type SupportSessionsEvents = {
  readonly "support.started": SupportEventData;
  readonly "support.ended": SupportEventData;
  readonly "support.denied": SupportEventData;
};

/** The `support-sessions` block's event types, for its manifest and `onBlockEvent`. */
export const supportSessionsEvents: Events<SupportSessionsEvents> =
  defineEvents({
    "support.started": event<SupportEventData>(),
    "support.ended": event<SupportEventData>(),
    "support.denied": event<SupportEventData>(),
  });
