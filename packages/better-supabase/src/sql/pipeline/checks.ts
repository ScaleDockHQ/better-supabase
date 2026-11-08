import type { BlockSqlContext } from "../context.ts";
import type { EntityTable } from "../entity-clashes.ts";
import type { BlockSqlLayout, BlockSql } from "../module-types.ts";

import { tenantNameOf } from "../../config/blocks.ts";
import {
  entityTableClash,
  sharedTableClash,
  tenantNameClashes,
} from "../entity-clashes.ts";
import { renamedInstances, rendersOwnInstance } from "../instance-names.ts";
import { moduleContext } from "../module-context.ts";
import { SQL_MODULES } from "../registry.ts";

/**
 * Throws when `blocks.memberships.names.organization` gives a renamed table or
 * column a name a module already uses.
 */
export function checkTenantName(
  modules: readonly BlockSql[],
  layout: BlockSqlLayout,
): void {
  const tenant = tenantNameOf(layout.modules);

  if (tenant === undefined) {
    return;
  }

  for (const module of modules) {
    const clashes = tenantNameClashes(module, tenant, SQL_MODULES);

    if (clashes.length === 0) {
      continue;
    }

    throw new TypeError(
      `blocks.memberships.names.organization: "${tenant}" renames the tenant tables and columns to names the ${module.name} module already uses (${clashes.join(", ")}). Choose another name.`,
    );
  }
}

/**
 * Throws when two installed blocks would create the same table: a
 * `blocks.<name>.tables` entry or a `blocks.<name>.entities` rename that gives
 * a block's table the name another block's table already has.
 */
export function checkEntityTables(
  modules: readonly BlockSql[],
  layout: BlockSqlLayout,
  installed: readonly string[],
): void {
  const tables = modules.flatMap((module): EntityTable[] =>
    [
      ...(rendersOwnInstance(module.name, layout) ? [module.name] : []),
      ...renamedInstances(module.name, layout).map(({ name }) => name),
    ].flatMap((instance) => {
      const ctx = moduleContext(
        module.name,
        layout,
        installed,
        instance === module.name ? undefined : instance,
      );

      if (!ctx.manages) {
        return [];
      }

      return Object.entries(module.names?.tables ?? {})
        .filter(
          ([logical]) =>
            ctx.config.tables[logical] !== null && ctx.owns(logical),
        )
        .map(([logical, spec]) => {
          const { schema, name } = ctx.tableName(logical);

          return {
            module: instance,
            logical,
            schema,
            name,
            renamed: ctx.resolved.entityNaming.rename(spec.name) !== spec.name,
            mapped: ctx.config.tables[logical] !== undefined,
          };
        });
    }),
  );

  const clash = entityTableClash(tables) ?? sharedTableClash(tables);

  if (clash !== undefined) {
    throw new TypeError(clash);
  }
}

/** Throws on a `blocks.<name>.functions` key the module writes no function for. */
export function checkFunctionRenames(ctx: BlockSqlContext): void {
  const unknown = ctx.unusedFunctions();

  if (unknown.length === 0) {
    return;
  }

  throw new TypeError(
    `blocks.${ctx.module}.functions: the ${ctx.module} module writes no function ${unknown.map((name) => `"${name}"`).join(", ")}`,
  );
}
