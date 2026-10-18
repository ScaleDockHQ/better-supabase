import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.notifications.options`. */
export type NotificationsSqlOptions = {
  readonly channelDefaults?: unknown;
  readonly channels?: readonly string[];
  readonly createdEvent?: string;
  readonly maxRecipients?: number;
  readonly partitioned?: boolean;
  readonly priorities?: readonly string[];
  readonly realtime?: string;
  readonly topic?: string;
  readonly updatedEvent?: string;
  readonly extraColumns?: unknown;
};

export const notificationsSqlOptions: BlockOptionsSchema<NotificationsSqlOptions> =
  blockOptions<NotificationsSqlOptions>({
    channelDefaults: option.unknown(),
    channels: option.strings({ default: ["in_app"] }),
    createdEvent: option.string({ default: "notification_created" }),
    maxRecipients: option.number({ default: 1000 }),
    partitioned: option.boolean({ default: false }),
    priorities: option.strings({
      default: ["low", "normal", "high", "urgent"],
    }),
    realtime: option.string({ default: "broadcast" }),
    topic: option.string({ default: "notifications:{userId}", client: true }),
    updatedEvent: option.string({ default: "notification_updated" }),
    extraColumns: option.unknown(),
  });
