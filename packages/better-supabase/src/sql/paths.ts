import type { BlockSqlLayout, BlockSql } from "./module-types.ts";

import { CONFIG_DEFAULTS } from "../config/defaults.ts";
import { instancePrefix } from "../config/instances.ts";
import { renamedInstances, rendersOwnInstance } from "./instance-names.ts";
import { moduleContext } from "./module-context.ts";
import { ORDER, checkModules, resolveBlocks } from "./registry.ts";

/**
 * The file a module renders to; with `instance`, the file of that instance,
 * numbered with its module.
 */
export function modulePath(
  module: BlockSql,
  layout: BlockSqlLayout,
  instance: string = module.name,
): string {
  const dir = (layout.dir ?? CONFIG_DEFAULTS.sql.dir).replace(/\/$/, "");
  const prefix = layout.prefix ?? CONFIG_DEFAULTS.sql.prefix;

  const testsDir = (layout.testsDir ?? CONFIG_DEFAULTS.sql.testsDir).replace(
    /\/$/,
    "",
  );

  const slug = instancePrefix(instance);

  const position =
    module.before === undefined
      ? ORDER.indexOf(module.name) + 1
      : ORDER.indexOf(module.before);

  return module.target === "test"
    ? `${testsDir}/000_better_supabase_${slug}.test.sql`
    : `${dir}/${prefix}_${String(position).padStart(2, "0")}_${slug}.sql`;
}

/**
 * The schema or test file `renderBlocks` writes for each of `names` and the
 * modules they pull in, without rendering: modules in custom mode have none.
 */
export function moduleFilePaths(
  names: readonly string[],
  layout: BlockSqlLayout = {},
): ReadonlyMap<string, string> {
  checkModules(layout.modules);
  const modules = resolveBlocks(names, layout);
  const installed = modules.map((module) => module.name);

  return new Map(
    modules.flatMap((module) => [
      ...(rendersOwnInstance(module.name, layout) &&
      moduleContext(module.name, layout, installed).mode !== "custom"
        ? [[module.name, modulePath(module, layout)] as const]
        : []),
      ...renamedInstances(module.name, layout)
        .filter(
          (instance) =>
            moduleContext(module.name, layout, installed, instance.name)
              .mode !== "custom",
        )
        .map(
          (instance) =>
            [instance.name, modulePath(module, layout, instance.name)] as const,
        ),
    ]),
  );
}

/**
 * Where a module's data statements go: `better-supabase-data/` next to the
 * declarative schema folder, or next to `dir` when `dir` is outside it.
 * pg-delta loads every file under the schema folder, nested folders included,
 * and rejects a managed table that has rows afterwards.
 */
export function moduleDataPath(
  module: BlockSql,
  layout: BlockSqlLayout,
  instance: string = module.name,
): string {
  const path = modulePath(module, layout, instance);
  const file = path.slice(path.lastIndexOf("/"));
  const dir = path.slice(0, path.lastIndexOf("/"));
  const bare = (value: string) => value.replace(/^\.\//, "").replace(/\/$/, "");
  const schemas = bare(layout.schemasDir ?? CONFIG_DEFAULTS.sql.dir);
  const inside = bare(dir) === schemas || bare(dir).startsWith(`${schemas}/`);
  const base = inside ? `${dir.startsWith("./") ? "./" : ""}${schemas}` : dir;
  const parent = base.lastIndexOf("/");

  return `${parent === -1 ? "" : base.slice(0, parent + 1)}better-supabase-data${file}`;
}
