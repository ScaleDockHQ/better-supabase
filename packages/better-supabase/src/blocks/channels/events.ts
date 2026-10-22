import type { ChannelEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `channels` block: type to data. */
export type ChannelsEvents = {
  readonly "channel.created": ChannelEventData;
  readonly "channel.updated": ChannelEventData;
};

/** The `channels` block's event types, for its manifest and `onBlockEvent`. */
export const channelsEvents: Events<ChannelsEvents> = defineEvents({
  "channel.created": event<ChannelEventData>(),
  "channel.updated": event<ChannelEventData>(),
});
