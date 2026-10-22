import type {
  MailAccountEventData,
  MailMessageEventData,
  MailTrackingEventData,
} from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The events of the `mail-sync` block: type to data. */
export type MailSyncEvents = {
  readonly "mail_account.connected": MailAccountEventData;
  readonly "mail_account.disconnected": MailAccountEventData;
  readonly "mail_message.received": MailMessageEventData;
  readonly "mail_message.sent": MailMessageEventData;
  readonly "mail_message.opened": MailTrackingEventData;
  readonly "mail_message.clicked": MailTrackingEventData;
};

/** The `mail-sync` block's event types, for its manifest and `onBlockEvent`. */
export const mailSyncEvents: Events<MailSyncEvents> = defineEvents({
  "mail_account.connected": event<MailAccountEventData>(),
  "mail_account.disconnected": event<MailAccountEventData>(),
  "mail_message.received": event<MailMessageEventData>(),
  "mail_message.sent": event<MailMessageEventData>(),
  "mail_message.opened": event<MailTrackingEventData>(),
  "mail_message.clicked": event<MailTrackingEventData>(),
});
