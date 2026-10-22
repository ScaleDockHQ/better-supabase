import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.relations.options`. */
export type RelationsSqlOptions = {
  readonly kinds?: unknown;
  readonly extraColumns?: unknown;
};

export const relationsSqlOptions: BlockOptionsSchema<RelationsSqlOptions> =
  blockOptions<RelationsSqlOptions>({
    kinds: option.unknown(),
    extraColumns: option.unknown(),
  });
