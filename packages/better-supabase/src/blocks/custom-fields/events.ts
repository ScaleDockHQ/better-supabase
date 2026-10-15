import type {
  Events,
  SaasEventData,
  SaasSubjectEventData,
} from "../../core/block-events.ts";

import { defineEvents, event } from "../../core/block-events.ts";

/** The events of the `custom-fields` block: type to data. */
export type CustomFieldsEvents = {
  readonly "custom_field.saved": SaasEventData;
  readonly "custom_field.deleted": SaasEventData;
  readonly "field_value.set": SaasSubjectEventData;
};

/** The `custom-fields` block's event types, for its manifest and `onBlockEvent`. */
export const customFieldsEvents: Events<CustomFieldsEvents> = defineEvents({
  "custom_field.saved": event<SaasEventData>(),
  "custom_field.deleted": event<SaasEventData>(),
  "field_value.set": event<SaasSubjectEventData>(),
});
