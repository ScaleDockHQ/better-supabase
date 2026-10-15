import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.inbox.options`. */
export type InboxSqlOptions = {
  readonly topic?: string;
  readonly bucket?: string;
  readonly maxBodyLength?: number;
  readonly botQueue?: unknown;
  readonly outboundQueue?: unknown;
  readonly notify?: boolean;
};

export const inboxSqlOptions: BlockOptionsSchema<InboxSqlOptions> =
  blockOptions<InboxSqlOptions>({
    topic: option.string({ default: "inbox", client: true }),
    bucket: option.string({ default: "inbox-files" }),
    maxBodyLength: option.number({ default: 20_000 }),
    botQueue: option.unknown(),
    outboundQueue: option.unknown(),
    notify: option.boolean({ default: true }),
  });
