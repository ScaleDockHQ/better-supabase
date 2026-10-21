import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.domains.options`. */
export type DomainsSqlOptions = {
  /**
   * The app's own domain: one label below it is a subdomain verified when
   * added.
   */
  readonly platformDomain?: string;
  /** The TXT record name's first label: `<txtPrefix>.<hostname>`. */
  readonly txtPrefix?: string;
};

export const domainsSqlOptions: BlockOptionsSchema<DomainsSqlOptions> =
  blockOptions<DomainsSqlOptions>({
    platformDomain: option.string(),
    txtPrefix: option.string({ default: "_better-supabase" }),
  });
