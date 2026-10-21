import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.announcements.options`. */
export type AnnouncementsSqlOptions = {
  readonly topic?: string;
  readonly event?: string;
  readonly extraColumns?: unknown;
};

export const announcementsSqlOptions: BlockOptionsSchema<AnnouncementsSqlOptions> =
  blockOptions<AnnouncementsSqlOptions>({
    topic: option.string({ default: "announcements", client: true }),
    event: option.string({ default: "announcement_changed" }),
    extraColumns: option.unknown(),
  });
