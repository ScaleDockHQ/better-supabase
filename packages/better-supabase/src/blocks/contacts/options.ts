import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.contacts.options`. */
export type ContactsSqlOptions = {
  readonly companyLifecycles?: unknown;
  readonly personLifecycles?: unknown;
  /**
   * The roles a company or person can have, lowercase. Default `customer`,
   * `supplier`, `funder`, `partner`.
   */
  readonly roles?: readonly string[];
  readonly extraColumns?: ExtraColumns;
  /**
   * Adds a stored `search_tsv` column and a GIN index to companies and people,
   * so queries match with `search_tsv @@ websearch_to_tsquery('simple', ...)`.
   * Default `false`.
   */
  readonly searchColumn?: boolean;
};

export const contactsSqlOptions: BlockOptionsSchema<ContactsSqlOptions> =
  blockOptions<ContactsSqlOptions>({
    companyLifecycles: option.unknown(),
    personLifecycles: option.unknown(),
    roles: option.strings(),
    extraColumns: option.extraColumns(),
    searchColumn: option.boolean({ default: false }),
  });
