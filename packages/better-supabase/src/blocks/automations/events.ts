import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `rule.saved`, `rule.enabled`, `rule.disabled` and `rule.removed`. */
export interface RuleEventData {
  readonly organizationId: string;
  readonly ruleId: string;
  readonly name: string;
  readonly subjectType: string;
  readonly trigger: string;
  readonly version: number;
}

/** `rule.matched`: a live evaluation matched a subject. */
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
  readonly "rule.saved": RuleEventData;
  readonly "rule.enabled": RuleEventData;
  readonly "rule.disabled": RuleEventData;
  readonly "rule.removed": RuleEventData;
  readonly "rule.matched": RuleMatchedEventData;
};

/** The `rules` block's event types, for its manifest and `onBlockEvent`. */
export const automationsEvents: Events<AutomationsEvents> = defineEvents({
  "rule.saved": event<RuleEventData>(),
  "rule.enabled": event<RuleEventData>(),
  "rule.disabled": event<RuleEventData>(),
  "rule.removed": event<RuleEventData>(),
  "rule.matched": event<RuleMatchedEventData>(),
});
