import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.messaging.options`. */
export type MessagingSqlOptions = {
  /** The Realtime topic prefix: pings go to `<topic>:<conversation id>`. */
  readonly topic?: string;
  /** `1` keeps threads one level deep; `unlimited` nests replies. */
  readonly threadDepth?: 1 | "unlimited";
  readonly maxBodyLength?: number;
  /** Seconds an author may edit a message; `0` for always. */
  readonly editWindow?: number;
  /** The jobs queue that sends scheduled messages. */
  readonly scheduleQueue?: string;
  readonly extraColumns?: ExtraColumns;
  /**
   * `false` sends no `message.mentioned`, `message.direct` or `message.replied`
   * notification.
   */
  readonly notify?: boolean;
};

export const messagingSqlOptions: BlockOptionsSchema<MessagingSqlOptions> =
  blockOptions<MessagingSqlOptions>({
    topic: option.string({ default: "messages", client: true }),
    threadDepth: option.unknown(),
    maxBodyLength: option.number({ default: 40_000 }),
    editWindow: option.number({ default: 0 }),
    scheduleQueue: option.string({ default: "messaging" }),
    extraColumns: option.extraColumns(),
    notify: option.boolean({ default: true }),
  });
