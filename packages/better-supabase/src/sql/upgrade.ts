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
import {
  SQL_MODULES,
  checkMigrationOptions,
  checkModules,
} from "./registry.ts";
import { nameMigrationSql } from "./rename-sql.ts";
import { freesTableName } from "./table-renames.ts";

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
 * custom mode belong to the app and are skipped. A module whose table move
 * frees a name another module's move takes comes first.
 */
export function upgradePlan(
  installed: readonly InstalledBlock[],
  layout: BlockSqlLayout = {},
  modules: Readonly<Record<string, BlockSql>> = SQL_MODULES,
): BlockSqlUpgradePlan[] {
  checkModules(layout.modules, modules);
  checkMigrationOptions(layout.modules, layout.ownTables);

  const names = [
    ...new Set(installed.map((entry) => entry.block ?? entry.module)),
  ];

  const defaults = withProviderDefaults(layout);

  const ordered = installed.toSorted(
    (a, b) =>
      Number(freesTableName(b.block ?? b.module)) -
      Number(freesTableName(a.block ?? a.module)),
  );

  return ordered.flatMap((entry): BlockSqlUpgradePlan[] => {
    const block = entry.block ?? entry.module;
    const module = modules[block];

    if (!module) {
      return [];
    }

    const to = blockSqlVersion(module);

    if (entry.version >= to) {
      return [];
    }

    const options = {
      ...(defaults ? { modules: defaults } : {}),
      ...(layout.claims ? { claims: layout.claims } : {}),
      ...(layout.instances ? { instances: layout.instances } : {}),
      ...(entry.module === block ? {} : { instance: entry.module }),
      installed: names,
      ...(layout.ownTables ? { ownTables: layout.ownTables } : {}),
      ...(layout.ownViews ? { ownViews: layout.ownViews } : {}),
      ...providerIdType(layout),
      ...providerGuests(layout),
    };

    const ctx = createModuleContext(
      block,
      (name) => modules[name]?.names,
      options,
    );

    if (ctx.mode === "custom") {
      return [];
    }

    const migrations = module.names?.migrations ?? [];

    // A step that runs before a table move reads the table by its old name.
    const contextAt = (from: number): BlockSqlContext => {
      const pending = migrations.filter((move) => move.from > from);

      if (pending.length === 0 || !module.names) {
        return ctx;
      }

      const tables = { ...module.names.tables };

      for (const move of pending) {
        const table = tables[move.table];

        if (table && move.was) {
          tables[move.table] = { ...table, name: move.was };
        }
      }

      const before = { ...module.names, tables };

      return createModuleContext(
        block,
        (name) => (name === block ? before : modules[name]?.names),
        options,
      );
    };

    const moves = migrations.map((migration) => ({
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
        sql: step.sql(moves.includes(step) ? ctx : contextAt(step.from)).trim(),
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
