import type { AnyBlocksConfig } from "../../src/config/blocks.ts";

import { moduleContext } from "../../src/sql/module-context.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";

/** Says every table is the app's, so a context resolves names under any config. */
const EVERY_TABLE: Readonly<Record<string, string>> = new Proxy(
  {},
  { get: (_target, key) => (typeof key === "string" ? "app.sql" : undefined) },
);

/**
 * `ownTables` with every table of `blocks` (all of `modules` by default) that
 * the app's table can stand in for, as the CLI finds them in the app's schema
 * files. Tables mapped to `null`, and `onlyWhenMapped` tables left unmapped,
 * stay the block's.
 */
export function ownTablesOf(
  modules: AnyBlocksConfig,
  blocks: readonly string[] = Object.keys(modules),
): Record<string, string> {
  const own: Record<string, string> = {};

  for (const name of blocks) {
    const ctx = moduleContext(
      name,
      { modules, ownTables: EVERY_TABLE },
      Object.keys(modules),
    );

    const mapped = modules[name]?.tables ?? {};

    for (const [logical, spec] of Object.entries(
      SQL_MODULES[name]?.names?.tables ?? {},
    )) {
      if (
        spec.app === undefined ||
        mapped[logical] === null ||
        (spec.app.onlyWhenMapped === true && mapped[logical] === undefined)
      ) {
        continue;
      }

      const { schema, name: table } = ctx.tableName(logical);
      own[`${schema}.${table}`] = "app.sql";
    }
  }

  return own;
}
