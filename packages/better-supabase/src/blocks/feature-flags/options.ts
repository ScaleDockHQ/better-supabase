import type { BlockOptionsSchema } from "../options.ts";

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

/** `blocks['feature-flags'].options`. */
export type FeatureFlagsSqlOptions = {
  /**
   * Custom contexts by name, e.g. `{ brand: { table: "public.organizations",
   * column: "brand_id" } }`.
   */
  readonly contexts?: Readonly<Record<string, FlagContextColumn>>;
  readonly extraColumns?: unknown;
};

export const featureFlagsSqlOptions: BlockOptionsSchema<FeatureFlagsSqlOptions> =
  blockOptions<FeatureFlagsSqlOptions>({
    contexts: option.unknown(),
    extraColumns: option.unknown(),
  });
