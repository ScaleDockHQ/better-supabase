import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.notifications.options`. */
export type NotificationsSqlOptions = {
  readonly channelDefaults?: unknown;
  readonly channels?: readonly string[];
  readonly createdEvent?: string;
  /**
   * Lets `send_notification` name people who are not members: `external` takes
   * `{ address }` or `{ contact }` entries, and the email channel reaches them.
   * A contact is resolved through `resolveAddress`, with the contact id in the
   * `user` argument.
   */
  readonly externalRecipients?: boolean;
  readonly maxRecipients?: number;
  readonly partitioned?: boolean;
  readonly priorities?: readonly string[];
  readonly realtime?: string;
  /**
   * An app function `schema.name(user uuid, channel text) returns text` that
   * says where a member is reached on a channel, such as a work email in your
   * own profile table. Deliveries, digests and bounce suppression use it, and a
   * null answer falls back to the member's sign-in email.
   */
  readonly resolveAddress?: string;
  readonly topic?: string;
  readonly updatedEvent?: string;
};

export const notificationsSqlOptions: BlockOptionsSchema<NotificationsSqlOptions> =
  blockOptions<NotificationsSqlOptions>({
    channelDefaults: option.unknown(),
    channels: option.strings({ default: ["in_app"] }),
    createdEvent: option.string(),
    externalRecipients: option.boolean({ default: false }),
    maxRecipients: option.number({ default: 1000 }),
    partitioned: option.boolean({ default: false }),
    priorities: option.strings({
      default: ["low", "normal", "high", "urgent"],
    }),
    realtime: option.string(),
    resolveAddress: option.string(),
    topic: option.string({ default: "notifications:{userId}", client: true }),
    updatedEvent: option.string(),
  });
