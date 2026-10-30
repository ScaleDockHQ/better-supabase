import type { SupportEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `impersonation` block: type to data. */
export type ImpersonationEvents = {
  readonly "support_session.started": SupportEventData;
  readonly "support_session.ended": SupportEventData;
  readonly "support_session.denied": SupportEventData;
};

/** The `impersonation` block's event types, for its manifest and `onBlockEvent`. */
export const impersonationEvents: Events<ImpersonationEvents> = defineEvents({
  "support_session.started": event<SupportEventData>(),
  "support_session.ended": event<SupportEventData>(),
  "support_session.denied": event<SupportEventData>(),
});
