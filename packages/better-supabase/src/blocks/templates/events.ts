import type {
  TemplateApplicationEventData,
  TemplateEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `templates` block: type to data. */
export type TemplatesEvents = {
  readonly "template.published": TemplateEventData;
  readonly "template.applied": TemplateApplicationEventData;
};

/** The `templates` block's event types, for its manifest and `onBlockEvent`. */
export const templatesEvents: Events<TemplatesEvents> = defineEvents({
  "template.published": event<TemplateEventData>(),
  "template.applied": event<TemplateApplicationEventData>(),
});
