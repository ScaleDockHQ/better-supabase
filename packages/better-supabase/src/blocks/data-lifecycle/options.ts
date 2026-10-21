import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.data-lifecycle.options`. */
export type DataLifecycleSqlOptions = {
  readonly bucket?: string;
  readonly grace?: string;
  readonly exportTtl?: string;
  readonly tables?: unknown;
  readonly autoTables?: unknown;
  readonly tenantRow?: unknown;
  readonly anonymize?: unknown;
  readonly omitPattern?: unknown;
};

export const dataLifecycleSqlOptions: BlockOptionsSchema<DataLifecycleSqlOptions> =
  blockOptions<DataLifecycleSqlOptions>({
    bucket: option.string({ default: "data-exports" }),
    grace: option.string({ default: "30 days" }),
    exportTtl: option.string({ default: "7 days" }),
    tables: option.unknown(),
    autoTables: option.unknown(),
    tenantRow: option.unknown(),
    anonymize: option.unknown(),
    omitPattern: option.unknown(),
  });
