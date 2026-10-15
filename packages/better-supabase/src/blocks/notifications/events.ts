import type {
  NotificationDeliveryEventData,
  NotificationEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `notifications` block: type to data. */
export type NotificationsEvents = {
  readonly "notification.created": NotificationEventData;
  readonly "notification.delivered": NotificationDeliveryEventData;
  readonly "notification.failed": NotificationDeliveryEventData;
  readonly "notification.opened": NotificationDeliveryEventData;
  readonly "notification.clicked": NotificationDeliveryEventData;
  readonly "notification.bounced": NotificationDeliveryEventData;
  readonly "notification.complained": NotificationDeliveryEventData;
  readonly "notification.delayed": NotificationDeliveryEventData;
};

/** The `notifications` block's event types, for its manifest and `onBlockEvent`. */
export const notificationsEvents: Events<NotificationsEvents> = defineEvents({
  "notification.created": event<NotificationEventData>(),
  "notification.delivered": event<NotificationDeliveryEventData>(),
  "notification.failed": event<NotificationDeliveryEventData>(),
  "notification.opened": event<NotificationDeliveryEventData>(),
  "notification.clicked": event<NotificationDeliveryEventData>(),
  "notification.bounced": event<NotificationDeliveryEventData>(),
  "notification.complained": event<NotificationDeliveryEventData>(),
  "notification.delayed": event<NotificationDeliveryEventData>(),
});
