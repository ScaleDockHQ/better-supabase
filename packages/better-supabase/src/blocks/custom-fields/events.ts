import type {
  SaasEventData,
  SaasSubjectEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `custom-fields` block: type to data. */
export type CustomFieldsEvents = {
  readonly "custom_field.saved": SaasEventData;
  readonly "custom_field.deleted": SaasEventData;
  readonly "field_value.set": SaasSubjectEventData;
  /**
   * Protected values were read; audit only, with
   * `blocks.custom-fields.options.auditReads`.
   */
  readonly "field_value.viewed": FieldValueReadEventData;
};

/** The values of one subject that a `read_field_values` call returned. */
export interface FieldValueReadEventData extends SaasSubjectEventData {
  /** The ids of the encrypted or sensitive values it returned. */
  readonly ids: readonly string[];
}

/** The `custom-fields` block's event types, for its manifest and `onBlockEvent`. */
export const customFieldsEvents: Events<CustomFieldsEvents> = defineEvents({
  "custom_field.saved": event<SaasEventData>(),
  "custom_field.deleted": event<SaasEventData>(),
  "field_value.set": event<SaasSubjectEventData>(),
  "field_value.viewed": event<FieldValueReadEventData>(),
});
