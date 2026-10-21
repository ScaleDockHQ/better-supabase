import type {
  ModuleLayout,
  ModuleDeprecation,
  SqlModule,
} from "./module-types.ts";

import { createModuleContext, type ModuleContext } from "./context.ts";
import { providerIdType, withProviderDefaults } from "./module-context.ts";
import { moduleVersion } from "./module-types.ts";
import { SQL_MODULES, checkModules } from "./registry.ts";

/**
 * The compatibility wrappers of a module's deprecated symbols that are not
 * removed yet.
 */
export function deprecationWrappers(
  module: SqlModule,
  ctx: ModuleContext,
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

/** An installed module, from its file's `@bs-module` line or `modules`. */
export interface InstalledModule {
  readonly module: string;
  readonly version: number;
}

/** What `sql upgrade` runs for one module behind the current version. */
export interface ModuleUpgradePlan {
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
  installed: readonly InstalledModule[],
  layout: ModuleLayout = {},
  modules: Readonly<Record<string, SqlModule>> = SQL_MODULES,
): ModuleUpgradePlan[] {
  checkModules(layout.modules, modules);
  const names = installed.map((entry) => entry.module);
  const defaults = withProviderDefaults(layout);

  return installed.flatMap((entry): ModuleUpgradePlan[] => {
    const module = modules[entry.module];

    if (!module) {
      return [];
    }

    const to = moduleVersion(module);

    if (entry.version >= to) {
      return [];
    }

    const ctx = createModuleContext(
      entry.module,
      (name) => modules[name]?.names,
      {
        ...(defaults ? { modules: defaults } : {}),
        ...(layout.claims ? { claims: layout.claims } : {}),
        installed: names,
        ...providerIdType(layout),
      },
    );

    if (ctx.mode === "custom") {
      return [];
    }

    const steps = (module.upgrades ?? [])
      .filter((step) => step.from >= entry.version && step.from < to)
      .toSorted((a, b) => a.from - b.from)
      .map((step) => ({
        from: step.from,
        description: step.description,
        sql: step.sql(ctx).trim(),
      }));

    return [{ module: module.name, from: entry.version, to, steps }];
  });
}

/** Every deprecated or removed module symbol, with its module. */
export function moduleDeprecations(
  modules: Readonly<Record<string, SqlModule>> = SQL_MODULES,
): readonly (ModuleDeprecation & { readonly module: string })[] {
  return Object.values(modules).flatMap((module) =>
    (module.deprecated ?? []).map((entry) => ({
      ...entry,
      module: module.name,
    })),
  );
}
