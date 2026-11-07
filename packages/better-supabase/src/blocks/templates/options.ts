import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/**
 * Where a tenant's brand lives: the table and column that hold it, and the
 * column with the tenant id (`id` by default).
 */
export interface TemplateBrandColumn {
  readonly table: string;
  readonly column: string;
  readonly tenant?: string;
}

/** `blocks.templates.options`. */
export type TemplatesSqlOptions = {
  /**
   * Turns on brand-scoped starters, e.g. `{ table: "public.organizations",
   * column: "brand" }`: a starter `sync` saves with a `brand` reaches every
   * tenant whose column holds that brand.
   */
  readonly brand?: TemplateBrandColumn;
  /**
   * Template types this app registers. A block can contribute its own. An empty
   * registry keeps free-form types. ADR 0244.
   */
  readonly types?: Readonly<Record<string, unknown>>;
};

export const templatesSqlOptions: BlockOptionsSchema<TemplatesSqlOptions> =
  blockOptions<TemplatesSqlOptions>({
    brand: option.unknown(),
    types: option.unknown(),
  });
