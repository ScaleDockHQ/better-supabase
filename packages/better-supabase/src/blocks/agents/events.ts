import type { AgentEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `agents` block: type to data. */
export type AgentsEvents = {
  readonly "agent.created": AgentEventData;
  readonly "agent.updated": AgentEventData;
  readonly "agent.published": AgentEventData;
  readonly "agent.deleted": AgentEventData;
  readonly "agent.installed": AgentEventData;
  readonly "agent.uninstalled": AgentEventData;
};

/** The `agents` block's event types, for its manifest and `onBlockEvent`. */
export const agentsEvents: Events<AgentsEvents> = defineEvents({
  "agent.created": event<AgentEventData>(),
  "agent.updated": event<AgentEventData>(),
  "agent.published": event<AgentEventData>(),
  "agent.deleted": event<AgentEventData>(),
  "agent.installed": event<AgentEventData>(),
  "agent.uninstalled": event<AgentEventData>(),
});
