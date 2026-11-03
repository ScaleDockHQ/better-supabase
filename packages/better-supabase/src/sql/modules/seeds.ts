import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlDefinition, BlockSqlLayout } from "../module-types.ts";

import { moduleContext, registeredModule } from "../module-context.ts";
import { renderSeedUmbrella, seedFunctionName } from "../seeds.ts";
import { schemaPreamble } from "../shared.ts";

function build(ctx: BlockSqlContext, layout: BlockSqlLayout): string {
  const functions = ctx.installedModules.flatMap((name) => {
    const module = registeredModule(name);
    const other = moduleContext(name, layout, ctx.installedModules);
    const tables = module?.seeds?.defaults?.(other) ?? [];

    // A module whose defaults render no rows writes no function to call.
    return tables.length === 0
      ? []
      : [{ module: name, fn: other.fn(seedFunctionName(name)) }];
  });

  return `${schemaPreamble(ctx)}
${renderSeedUmbrella(ctx.schema, ctx.idType, functions, layout.seedDefaults)}`;
}

export const SEEDS: BlockSqlDefinition = {
  name: "seeds",
  version: 1,
  names: { tables: {} },
  title: "Seeds",
  description:
    "seed_tenant_defaults(tenant, variants, locale) applies the defaults every installed block declares, in install order. The organizations block calls it when an organization is created.",
  requires: [],
  target: "schema",
  build,
};
