import type { BlockSql } from "./module-types.ts";

import { tenantNames } from "../core/entity-naming.ts";

const isDefault = (name: string): boolean => name.includes("organization");

function defaultNames(module: BlockSql): readonly string[] {
  return Object.values(module.names?.tables ?? {}).flatMap((table) => [
    table.name,
    ...Object.values(table.columns),
  ]);
}

/**
 * The names `module` already uses that `blocks.memberships.names.organization:
 * tenant` would also give a renamed table or column, such as `team_id` and
 * `teams` for `team`. Such a module can't run under that tenant name: its
 * tables would collide, and the clients couldn't tell the two apart in a
 * result.
 */
export function tenantNameClashes(
  module: BlockSql,
  tenant: string,
  modules: Readonly<Record<string, BlockSql>>,
): readonly string[] {
  const names = tenantNames(tenant);

  if (!names.renamed) {
    return [];
  }

  const renamed = new Set(
    Object.values(modules)
      .flatMap(defaultNames)
      .filter(isDefault)
      .map((name) => names.rename(name)),
  );

  return [
    ...new Set(
      defaultNames(module).filter(
        (name) => !isDefault(name) && renamed.has(name),
      ),
    ),
  ];
}

/** A managed table a module writes under its default or entity-renamed name. */
export interface EntityTable {
  readonly module: string;
  readonly logical: string;
  readonly schema: string;
  readonly name: string;
  /** Whether `blocks.<module>.entities` gave the table its name. */
  readonly renamed: boolean;
}

/**
 * The first entity rename that gives a table a name another module's table
 * already has in the same schema, as an error message, or undefined.
 */
export function entityTableClash(
  tables: readonly EntityTable[],
): string | undefined {
  const byName = new Map<string, EntityTable>();

  for (const table of tables) {
    const key = `${table.schema}.${table.name}`;
    const other = byName.get(key);

    if (other === undefined) {
      byName.set(key, table);
      continue;
    }

    const [renamed, kept] = table.renamed ? [table, other] : [other, table];

    if (renamed.renamed && renamed.module !== kept.module) {
      return `blocks.${renamed.module}.entities: the ${renamed.module} block's ${renamed.logical} table would be named ${renamed.name}, which the ${kept.module} block already uses. Choose another name.`;
    }
  }

  return undefined;
}
