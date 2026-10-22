import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `field_key.dropped`: whose data key was deleted, never key material. */
export interface FieldKeyEventData {
  /** `tenant:<id>`, `user:<id>` or `app`. */
  readonly owner: string;
}

/** The events of the `field-encryption` block: type to data. */
export type FieldEncryptionEvents = {
  readonly "field_key.dropped": FieldKeyEventData;
};

/**
 * The `field-encryption` block's event types, for its manifest and
 * `onBlockEvent`.
 */
export const fieldEncryptionEvents: Events<FieldEncryptionEvents> =
  defineEvents({ "field_key.dropped": event<FieldKeyEventData>() });
