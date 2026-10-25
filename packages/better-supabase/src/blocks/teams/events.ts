import type { SaasEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `teams` block: type to data. */
export type TeamsEvents = {
  readonly "team.created": SaasEventData;
  readonly "team.updated": SaasEventData;
  readonly "team.archived": SaasEventData;
  readonly "team.restored": SaasEventData;
  readonly "team.deleted": SaasEventData;
  readonly "team_member.added": SaasEventData;
  readonly "team_member.removed": SaasEventData;
};

/** The `teams` block's event types, for its manifest and `onBlockEvent`. */
export const teamsEvents: Events<TeamsEvents> = defineEvents({
  "team.created": event<SaasEventData>(),
  "team.updated": event<SaasEventData>(),
  "team.archived": event<SaasEventData>(),
  "team.restored": event<SaasEventData>(),
  "team.deleted": event<SaasEventData>(),
  "team_member.added": event<SaasEventData>(),
  "team_member.removed": event<SaasEventData>(),
});
