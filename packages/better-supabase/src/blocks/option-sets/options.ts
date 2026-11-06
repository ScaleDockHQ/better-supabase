import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/**
 * Where a tenant's brand lives: the table and column that hold it, and the
 * column with the tenant id (`id` by default).
 */
export interface OptionSetBrandColumn {
  readonly table: string;
  readonly column: string;
  readonly tenant?: string;
}

/** `blocks.option-sets.options`. */
export type OptionSetsSqlOptions = {
  /**
   * Turns on per-brand item templates, e.g. `{ table: "public.organizations",
   * column: "brand" }`: a field's `brands.<brand>` template seeds the sets of
   * every tenant whose column holds that brand.
   */
  readonly brand?: OptionSetBrandColumn;
};

export const optionSetsSqlOptions: BlockOptionsSchema<OptionSetsSqlOptions> =
  blockOptions<OptionSetsSqlOptions>({ brand: option.unknown() });
