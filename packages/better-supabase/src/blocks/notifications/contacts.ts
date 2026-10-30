import type {
  ContactDelivery,
  NotificationsOptions,
  NotificationTypes,
} from "./api-types.ts";
import type {
  ContactMessage,
  ContactRecipient,
  NotificationChannel,
} from "./channel.ts";
import type { NotificationItem } from "./types.ts";

import { errorText } from "../shared.ts";
import { toItem } from "./rows.ts";

/** One send: `send_notification`'s argument and the contacts it leaves out. */
export interface Prepared {
  readonly args: Readonly<Record<string, unknown>>;
  readonly contacts: readonly ContactRecipient[];
}

export interface SplitRecipients {
  readonly users: readonly string[];
  readonly contacts: readonly ContactRecipient[];
  /** The index of each contact without a usable address. */
  readonly invalid: readonly number[];
}

/** User ids go to `send_notification`; contacts stay in TypeScript. */
export function splitRecipients(
  recipients: readonly (string | ContactRecipient)[],
): SplitRecipients {
  const users: string[] = [];
  const contacts: ContactRecipient[] = [];
  const invalid: number[] = [];

  for (const [index, recipient] of recipients.entries()) {
    if (typeof recipient === "string") {
      users.push(recipient);
    } else if (/^[^\s@<>]+@[^\s@<>]+$/.test(recipient.email)) {
      contacts.push(recipient);
    } else {
      invalid.push(index);
    }
  }

  return { users, contacts, invalid };
}

/**
 * The notification as a contact sees it, from `send_notification`'s argument:
 * there is no recipient row, so `id` is the event id.
 */
export function contactItem(
  eventId: string,
  notification: Readonly<Record<string, unknown>>,
): NotificationItem {
  return toItem({
    id: eventId,
    event_id: eventId,
    type: notification["type"],
    data: notification["data"],
    tenant: notification["tenant"],
    actor_id: notification["actor"],
    subject_type: notification["subject_type"],
    subject_id: notification["subject_id"],
    subject_label: notification["subject_label"],
    summary: notification["summary"],
    action_path: notification["action_path"],
    actions: notification["actions"],
    priority: notification["priority"],
    fields: notification["fields"],
  });
}

/**
 * Hands each contact to each channel with `sendToContact`, among `wanted` when
 * the send names its channels. A throw fails that one delivery.
 */
export async function deliverToContacts<H>(
  channels: readonly NotificationChannel[],
  wanted: readonly string[] | undefined,
  contacts: readonly ContactRecipient[],
  item: NotificationItem,
  options: Pick<
    NotificationsOptions<NotificationTypes, H>,
    "hydrate" | "render"
  >,
): Promise<readonly ContactDelivery[]> {
  const senders = channels.filter(
    (channel) =>
      channel.sendToContact !== undefined &&
      (wanted === undefined || wanted.includes(channel.name)),
  );

  if (contacts.length === 0 || senders.length === 0) {
    return [];
  }

  let hydrated: H | undefined;
  let text: ContactMessage["text"];

  try {
    hydrated = await options.hydrate?.([item], {});
    text = options.render?.(item, {
      ...(hydrated === undefined ? {} : { hydrated }),
    });
  } catch (cause) {
    const error = errorText(cause);

    return senders.flatMap((channel) =>
      contacts.map((contact): ContactDelivery => ({
        email: contact.email,
        channel: channel.name,
        status: "failed",
        error,
      })),
    );
  }

  const deliveries: ContactDelivery[] = [];

  for (const channel of senders) {
    for (const contact of contacts) {
      const message: ContactMessage = {
        channel: channel.name,
        key: `${item.eventId}:${channel.name}:${contact.email.toLowerCase()}`,
        contact,
        notification: item,
        ...(text === undefined ? {} : { text }),
        ...(hydrated === undefined ? {} : { hydrated }),
      };

      try {
        const result = await channel.sendToContact?.(message);

        deliveries.push({
          email: contact.email,
          channel: channel.name,
          status: result?.status ?? "sent",
          ...(result?.providerMessageId === undefined
            ? {}
            : { providerMessageId: result.providerMessageId }),
        });
      } catch (cause) {
        deliveries.push({
          email: contact.email,
          channel: channel.name,
          status: "failed",
          error: errorText(cause),
        });
      }
    }
  }

  return deliveries;
}
