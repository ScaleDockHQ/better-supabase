import type { BlockSqlContext } from "./context.ts";
import type {
  BlockSqlLayout,
  BlockSqlDeprecation,
  BlockSql,
} from "./module-types.ts";

import { createModuleContext } from "./context.ts";
import {
  providerGuests,
  providerIdType,
  withProviderDefaults,
} from "./module-context.ts";
import { blockSqlVersion } from "./module-types.ts";
import { SQL_MODULES, checkModules } from "./registry.ts";
import { nameMigrationSql } from "./rename-sql.ts";

/**
 * The compatibility wrappers of a module's deprecated symbols that are not
 * removed yet.
 */
export function deprecationWrappers(
  module: BlockSql,
  ctx: BlockSqlContext,
): string {
  return (module.deprecated ?? [])
    .flatMap((entry) =>
      entry.removed === undefined && entry.wrapper
        ? [
            `\n-- Deprecated since ${entry.since}: use ${entry.use}.\n${entry.wrapper(ctx).trim()}\n`,
          ]
        : [],
    )
    .join("");
}

/**
 * An installed module, from its file's `@bsb-block` line or the
 * `better_supabase.blocks` table.
 */
export interface InstalledBlock {
  /** The instance: the module's name, or the key of a renamed instance. */
  readonly module: string;
  /** The module, when the instance installs it under another name. */
  readonly block?: string;
  readonly version: number;
}

/** What `upgrade` runs for one instance behind the current version. */
export interface BlockSqlUpgradePlan {
  /** The instance. */
  readonly module: string;
  readonly from: number;
  readonly to: number;
  readonly steps: readonly {
    readonly from: number;
    readonly description: string;
    readonly sql: string;
  }[];
}

/**
 * The upgrade steps for modules installed at an older version. A version
 * without a step needs none: the module file upgrades in place. Modules in
 * custom mode belong to the app and are skipped.
 */
export function upgradePlan(
  installed: readonly InstalledBlock[],
  layout: BlockSqlLayout = {},
  modules: Readonly<Record<string, BlockSql>> = SQL_MODULES,
): BlockSqlUpgradePlan[] {
  checkModules(layout.modules, modules);

  const names = [
    ...new Set(installed.map((entry) => entry.block ?? entry.module)),
  ];

  const defaults = withProviderDefaults(layout);

  return installed.flatMap((entry): BlockSqlUpgradePlan[] => {
    const block = entry.block ?? entry.module;
    const module = modules[block];

    if (!module) {
      return [];
    }

    const to = blockSqlVersion(module);

    if (entry.version >= to) {
      return [];
    }

    const ctx = createModuleContext(block, (name) => modules[name]?.names, {
      ...(defaults ? { modules: defaults } : {}),
      ...(layout.claims ? { claims: layout.claims } : {}),
      ...(layout.instances ? { instances: layout.instances } : {}),
      ...(entry.module === block ? {} : { instance: entry.module }),
      installed: names,
      ...providerIdType(layout),
      ...providerGuests(layout),
    });

    if (ctx.mode === "custom") {
      return [];
    }

    const moves = (module.names?.migrations ?? []).map((migration) => ({
      from: migration.from,
      description: migration.description,
      sql: (each: BlockSqlContext) => nameMigrationSql(each, migration),
    }));

    const steps = [...moves, ...(module.upgrades ?? [])]
      .filter((step) => step.from >= entry.version && step.from < to)
      .toSorted((a, b) => a.from - b.from)
      .map((step) => ({
        from: step.from,
        description: step.description,
        sql: step.sql(ctx).trim(),
      }));

    return [{ module: entry.module, from: entry.version, to, steps }];
  });
}

/** Every deprecated or removed module symbol, with its module. */
export function moduleDeprecations(
  modules: Readonly<Record<string, BlockSql>> = SQL_MODULES,
): readonly (BlockSqlDeprecation & { readonly module: string })[] {
  return Object.values(modules).flatMap((module) =>
    (module.deprecated ?? []).map((entry) => ({
      ...entry,
      module: module.name,
    })),
  );
}
