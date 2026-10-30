import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/**
 * `automation.created`, `automation.updated`, `automation.enabled`,
 * `automation.disabled` and `automation.deleted`.
 */
export interface RuleEventData {
  readonly organizationId: string;
  readonly ruleId: string;
  readonly name: string;
  readonly subjectType: string;
  readonly trigger: string;
  readonly version: number;
}

/** `automation.matched`: a live evaluation matched a subject. */
export interface RuleMatchedEventData {
  readonly organizationId: string;
  readonly ruleId: string;
  readonly version: number;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly trigger: string;
}

/** The events of the `rules` block: type to data. */
export type AutomationsEvents = {
  readonly "automation.created": RuleEventData;
  readonly "automation.updated": RuleEventData;
  readonly "automation.enabled": RuleEventData;
  readonly "automation.disabled": RuleEventData;
  readonly "automation.deleted": RuleEventData;
  readonly "automation.matched": RuleMatchedEventData;
};

/** The `rules` block's event types, for its manifest and `onBlockEvent`. */
export const automationsEvents: Events<AutomationsEvents> = defineEvents({
  "automation.created": event<RuleEventData>(),
  "automation.updated": event<RuleEventData>(),
  "automation.enabled": event<RuleEventData>(),
  "automation.disabled": event<RuleEventData>(),
  "automation.deleted": event<RuleEventData>(),
  "automation.matched": event<RuleMatchedEventData>(),
});
