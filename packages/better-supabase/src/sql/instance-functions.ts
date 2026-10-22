import type { BlockSqlLayout } from "./module-types.ts";

import { moduleContext } from "./module-context.ts";
import { moduleNameSet } from "./name-sets.ts";
import { SQL_MODULES } from "./registry.ts";

/**
 * Each function of `instance`'s block to the name the instance's SQL writes it
 * under, for the functions it writes under another name: the instance's prefix,
 * its entity renames and `blocks.<instance>.functions`. `gen` writes it to the
 * instance's `names.functions`, so the block's client calls the instance's own
 * functions.
 */
export function instanceFunctions(
  layout: BlockSqlLayout,
  installed: readonly string[],
  instance: string,
): Readonly<Record<string, string>> {
  const block = layout.instances?.[instance]?.block;
  const module = block === undefined ? undefined : SQL_MODULES[block];

  if (block === undefined || module === undefined || block === instance) {
    return {};
  }

  const ctx = moduleContext(block, layout, installed, instance);

  return Object.fromEntries(
    moduleNameSet(module).functions.flatMap((name) => {
      const written = ctx.fnName(name);

      return written === name ? [] : [[name, written]];
    }),
  );
}
