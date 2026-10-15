import type { SqlModule } from "./module-types.ts";

import { tenantNames } from "../core/tenant-naming.ts";

const isDefault = (name: string): boolean => name.includes("organization");

function defaultNames(module: SqlModule): readonly string[] {
  return Object.values(module.names?.tables ?? {}).flatMap((table) => [
    table.name,
    ...Object.values(table.columns),
  ]);
}

/**
 * The names `module` already uses that `sql.naming.tenant: tenant` would
 * also give a renamed table or column, such as `team_id` and `teams` for
 * `team`. Such a module can't run under that tenant name: its tables would
 * collide, and the clients couldn't tell the two apart in a result.
 */
export function tenantNameClashes(
  module: SqlModule,
  tenant: string,
  modules: Readonly<Record<string, SqlModule>>,
): readonly string[] {
  const names = tenantNames(tenant);
  if (!names.renamed) return [];
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
