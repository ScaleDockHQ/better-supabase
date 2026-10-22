import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.mail-sync.options`. */
export type MailSyncSqlOptions = {
  /** The engagement type shared threads are logged as. Default `email`. */
  readonly engagementType?: string;
  /** Also links a thread to companies by the domain of its addresses. */
  readonly matchDomains?: boolean;
};

export const mailSyncSqlOptions: BlockOptionsSchema<MailSyncSqlOptions> =
  blockOptions<MailSyncSqlOptions>({
    engagementType: option.string(),
    matchDomains: option.boolean(),
  });
