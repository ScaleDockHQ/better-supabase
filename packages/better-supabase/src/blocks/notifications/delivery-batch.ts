import type { NotificationDeliveryEventData } from "../../core/block-events.ts";
import type { SubscriberEvent } from "../../core/contracts/authorization-hooks.ts";
import type { NotificationTypes, NotificationsOptions } from "./api-types.ts";
import type { NotificationChannel, NotificationMessage } from "./channel.ts";
import type { NotificationItem } from "./types.ts";

import { emailChannel } from "./email.ts";

/**
 * The data of `notification.delivered` and `notification.failed` for one
 * delivery.
 */
export const deliveryData = (
  message: NotificationMessage,
  channel: string,
): NotificationDeliveryEventData => {
  const notification = message.notification;

  return {
    notificationId: notification.eventId,
    organizationId: notification.tenant,
    type: notification.type,
    channel,
    deliveryId: message.deliveryId,
    subjectType: notification.subject?.type ?? "notification",
    subjectId: notification.subject?.id ?? notification.eventId,
  };
};

/** `hydrate`'s result for one locale's deliveries, or what it threw. */
export type Hydration<H> =
  | { readonly ok: true; readonly value: H | undefined }
  | { readonly ok: false; readonly cause: unknown };

export interface Claimed {
  readonly message: NotificationMessage;
  /** The suppression's reason when the address is suppressed on the channel. */
  readonly suppressed: string | null;
}

export function deliveryChannels(
  options: Pick<NotificationsOptions<NotificationTypes>, "channels" | "email">,
): readonly NotificationChannel[] {
  const channels = options.channels ?? [];

  if (options.email === undefined) {
    return channels;
  }

  if (channels.some((channel) => channel.name === "email")) {
    throw new TypeError(
      'createNotifications: `email` adds the "email" channel; remove the channel named "email" from `channels`',
    );
  }

  return [...channels, emailChannel(options.email)];
}

/**
 * The event a delivery's audience check sees: the notification, as its
 * recipients read it.
 */
export const subscriberEventOf = (
  notification: NotificationItem,
): SubscriberEvent => ({
  type: notification.type,
  tenant: notification.tenant,
  actorId: notification.actorId,
  payload: notification.data,
  subject: notification.subject
    ? `${notification.subject.type}/${notification.subject.id}`
    : null,
});

/** Messages grouped by the recipient's locale, in claim order. */
export const byLocale = (
  messages: readonly NotificationMessage[],
): Map<string | null, NotificationMessage[]> => {
  const groups = new Map<string | null, NotificationMessage[]>();

  for (const message of messages) {
    const group = groups.get(message.locale) ?? [];
    group.push(message);
    groups.set(message.locale, group);
  }

  return groups;
};
