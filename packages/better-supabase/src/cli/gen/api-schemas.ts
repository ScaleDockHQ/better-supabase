import type { ResolvedConfig } from "../../config/index.ts";

import { resolveBlock } from "../../sql/index.ts";

/**
 * The block API schemas (`blocks.<module>.api`, which `sql.api` fills in) that
 * `config.schemas` doesn't list, sorted. Introspection and typegen read them
 * too, so `database.types.ts` types `client.schema("api").rpc(...)`.
 * `gen.api.types: false` returns none.
 */
export function apiTypeSchemas(
  config: Pick<ResolvedConfig, "blocks" | "gen" | "schemas">,
): readonly string[] {
  if (config.gen.api?.types === false) {
    return [];
  }

  const found = new Set<string>();

  for (const block of Object.values(config.blocks)) {
    const { api } = resolveBlock(block);

    if (api !== undefined) {
      found.add(api.schema);
    }
  }

  return [...found]
    .filter((schema) => !config.schemas.includes(schema))
    .toSorted();
}
