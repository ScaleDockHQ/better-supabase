import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `field_key.dropped`: whose data key was deleted, never key material. */
export interface FieldKeyEventData {
  /** `tenant:<id>`, `user:<id>` or `app`. */
  readonly owner: string;
}

/** `field_key.rotated`: whose data key was replaced, never key material. */
export interface FieldKeyRotatedEventData extends FieldKeyEventData {
  /** How many stored values were encrypted again under the new key. */
  readonly values: number;
}

/** The events of the `field-encryption` block: type to data. */
export type FieldEncryptionEvents = {
  readonly "field_key.dropped": FieldKeyEventData;
  readonly "field_key.rotated": FieldKeyRotatedEventData;
};

/**
 * The `field-encryption` block's event types, for its manifest and
 * `onBlockEvent`.
 */
export const fieldEncryptionEvents: Events<FieldEncryptionEvents> =
  defineEvents({
    "field_key.dropped": event<FieldKeyEventData>(),
    "field_key.rotated": event<FieldKeyRotatedEventData>(),
  });
