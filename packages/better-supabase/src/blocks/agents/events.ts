import type { AgentEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `agents` block: type to data. */
export type AgentsEvents = {
  readonly "agent.saved": AgentEventData;
  readonly "agent.published": AgentEventData;
  readonly "agent.deleted": AgentEventData;
  readonly "agent.installed": AgentEventData;
  readonly "agent.uninstalled": AgentEventData;
};

/** The `agents` block's event types, for its manifest and `onBlockEvent`. */
export const agentsEvents: Events<AgentsEvents> = defineEvents({
  "agent.saved": event<AgentEventData>(),
  "agent.published": event<AgentEventData>(),
  "agent.deleted": event<AgentEventData>(),
  "agent.installed": event<AgentEventData>(),
  "agent.uninstalled": event<AgentEventData>(),
});
