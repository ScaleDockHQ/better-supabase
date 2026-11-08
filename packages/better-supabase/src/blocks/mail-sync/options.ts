import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.mail-sync.options`. */
export type MailSyncSqlOptions = {
  /** The activity type shared threads are logged as. Default `email`. */
  readonly activityType?: string;
  /** Also links a thread to companies by the domain of its addresses. */
  readonly matchDomains?: boolean;
};

export const mailSyncSqlOptions: BlockOptionsSchema<MailSyncSqlOptions> =
  blockOptions<MailSyncSqlOptions>({
    activityType: option.string(),
    matchDomains: option.boolean(),
  });
