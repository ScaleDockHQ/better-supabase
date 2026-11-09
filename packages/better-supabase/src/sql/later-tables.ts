import type { BlockSqlContext } from "./context.ts";
import type { BlockSqlLayout } from "./module-types.ts";

import { renamedInstances, rendersOwnInstance } from "./instance-names.ts";
import { moduleContext } from "./module-context.ts";

/** The quoted tables of a block instance's context. */
export function tablesOf(ctx: BlockSqlContext): ReadonlySet<string> {
  return new Set(
    Object.keys(ctx.names.tables)
      .filter((key) => ctx.hasTable(key))
      .map((key) => ctx.table(key)),
  );
}

/**
 * The tables of the blocks that render after `module`. They don't exist when
 * that module's file runs, so a policy or trigger that names one belongs in the
 * later block's own file, or calls a plpgsql function that binds late.
 */
export function laterTables(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
  module: string,
): ReadonlySet<string> {
  const installed = ctx.installedModules;
  const later = installed.slice(installed.indexOf(module) + 1);

  return new Set(
    later
      .flatMap((block) => [
        ...(rendersOwnInstance(block, layout)
          ? [moduleContext(block, layout, installed)]
          : []),
        ...renamedInstances(block, layout).map((instance) =>
          moduleContext(block, layout, installed, instance.name),
        ),
      ])
      .filter((owner) => owner.mode !== "custom")
      .flatMap((owner) => [...tablesOf(owner)]),
  );
}
