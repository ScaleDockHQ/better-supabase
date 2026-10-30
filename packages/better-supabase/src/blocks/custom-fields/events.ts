import type {
  SaasEventData,
  SaasSubjectEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `custom-fields` block: type to data. */
export type CustomFieldsEvents = {
  readonly "field_definition.created": SaasEventData;
  readonly "field_definition.updated": SaasEventData;
  readonly "field_definition.deleted": SaasEventData;
  readonly "field_value.set": SaasSubjectEventData;
  /** A value was removed (`delete_field_value`, keyed layout). */
  readonly "field_value.deleted": SaasSubjectEventData;
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
  "field_definition.created": event<SaasEventData>(),
  "field_definition.updated": event<SaasEventData>(),
  "field_definition.deleted": event<SaasEventData>(),
  "field_value.set": event<SaasSubjectEventData>(),
  "field_value.deleted": event<SaasSubjectEventData>(),
  "field_value.viewed": event<FieldValueReadEventData>(),
});
