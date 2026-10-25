import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/**
 * A custom context's source: the table and column that hold a tenant's value,
 * and the column with the tenant id (`id` by default).
 */
export interface FlagContextColumn {
  readonly table: string;
  readonly column: string;
  readonly tenant?: string;
}

/** `blocks['flags'].options`. */
export type FlagsSqlOptions = {
  /**
   * Custom contexts by name, e.g. `{ brand: { table: "public.organizations",
   * column: "brand_id" } }`.
   */
  readonly contexts?: Readonly<Record<string, FlagContextColumn>>;
  readonly extraColumns?: ExtraColumns;
};

export const flagsSqlOptions: BlockOptionsSchema<FlagsSqlOptions> =
  blockOptions<FlagsSqlOptions>({
    contexts: option.unknown(),
    extraColumns: option.extraColumns(),
  });
