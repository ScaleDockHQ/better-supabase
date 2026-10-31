import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `dam_rendition.recorded`. */
export interface DamRenditionEventData {
  readonly organizationId: string;
  readonly id: string;
  /** The drive file the rendition belongs to. */
  readonly nodeId: string;
  readonly kind: string;
  /** `pending`, `ready` or `failed`. */
  readonly status: string;
}

/** What every `dam_usage_right.*` event carries. */
export interface DamUsageRightEventData {
  readonly organizationId: string;
  readonly id: string;
  readonly nodeId: string;
  readonly licensee: string;
  /** The last day of the right, `null` when it never expires. */
  readonly expiresOn: string | null;
}

/** The events of the `dam` block: type to data. */
export type DamEvents = {
  readonly "dam_rendition.recorded": DamRenditionEventData;
  readonly "dam_usage_right.granted": DamUsageRightEventData;
  readonly "dam_usage_right.revoked": DamUsageRightEventData;
  readonly "dam_usage_right.expiry_notified": DamUsageRightEventData;
};

/** The `dam` block's event types, for its manifest and `onBlockEvent`. */
export const damEvents: Events<DamEvents> = defineEvents({
  "dam_rendition.recorded": event<DamRenditionEventData>(),
  "dam_usage_right.granted": event<DamUsageRightEventData>(),
  "dam_usage_right.revoked": event<DamUsageRightEventData>(),
  "dam_usage_right.expiry_notified": event<DamUsageRightEventData>(),
});
