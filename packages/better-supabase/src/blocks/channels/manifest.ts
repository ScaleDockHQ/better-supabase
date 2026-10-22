import type { BlockOf } from "../define-block.ts";
import type { ChannelsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { createChannels } from "./channels.ts";
import { channelsEvents } from "./events.ts";
import { channelChangeSchema, channelInputSchema } from "./schemas.ts";

/** The `channels` block's manifest (ADR 0029, ADR 0062). */
export const channelsBlock: BlockOf<
  "channels",
  typeof createChannels,
  ChannelsEvents
> = defineBlock({
  name: "channels",
  sql: ["channels"],
  events: channelsEvents,
  schemas: {
    channel: { input: channelInputSchema, change: channelChangeSchema },
  },
  create: createChannels,
  category: "collaboration",
  recipes: ["channel-sidebar", "message-list", "thread-panel"],
});
