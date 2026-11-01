import type { GuardrailEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `ai-guardrails` block: type to data. */
export type AiGuardrailsEvents = {
  readonly "guardrail.blocked": GuardrailEventData;
};

/** The `ai-guardrails` block's event types, for its manifest and `onBlockEvent`. */
export const aiGuardrailsEvents: Events<AiGuardrailsEvents> = defineEvents({
  "guardrail.blocked": event<GuardrailEventData>(),
});
