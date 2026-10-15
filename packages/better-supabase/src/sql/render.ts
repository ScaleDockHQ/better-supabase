import type { BlockMode } from "../config/blocks.ts";
import type { ModuleFile, ModuleLayout } from "./module-types.ts";
import type { SqlModule } from "./module-types.ts";

import { CONFIG_DEFAULTS } from "../config/defaults.ts";
import { DEFAULT_CLAIMS } from "../core/claims.ts";
import { sqlString } from "../core/template.ts";
import { applyActorWriteGuards } from "./actor-guard.ts";
import { apiWrappers } from "./api-schema.ts";
import {
  type ModuleContext,
  type ModuleContractFunction,
  type ModuleIdType,
} from "./context.ts";
import { eventTriggersOf } from "./event-triggers.ts";
import { moduleExtensions } from "./introspect.ts";
import { moduleContext } from "./module-context.ts";
import { moduleVersion } from "./module-types.ts";
import { moduleDataPath, modulePath } from "./paths.ts";
import { checkModules, resolveModules } from "./registry.ts";
import { deprecationWrappers } from "./upgrade.ts";

function moduleSql(
  module: SqlModule,
  ctx: ModuleContext,
  layout: ModuleLayout,
) {
  if (module.build)
    return applyActorWriteGuards(module.build(ctx, layout), layout);
  if (
    module.render &&
    (layout.claims ||
      layout.entitlementsProvider ||
      layout.tenantColumn ||
      (layout.entitlements?.source ?? "stripe-sync") !== "stripe-sync")
  )
    return applyActorWriteGuards(
      module.render(layout.claims ?? DEFAULT_CLAIMS, layout),
      layout,
    );
  return applyActorWriteGuards(module.sql, layout);
}

/** A module's SQL for `layout`, without header; `undefined` in custom mode. */
export function moduleBody(
  name: string,
  layout: ModuleLayout = {},
): string | undefined {
  checkModules(layout.modules);
  const modules = resolveModules([name], layout);
  const module = modules.find((entry) => entry.name === name)!;
  const ctx = moduleContext(
    name,
    layout,
    modules.map((entry) => entry.name),
  );
  return ctx.mode === "custom" ? undefined : moduleSql(module, ctx, layout);
}

/** The table `moduleRow` writes to, created by every schema module's file. */
const MODULE_MODULES_TABLE = `
create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;
`;

/** Records the module in `better_supabase.modules`, which `sql upgrade` and doctor read. */
function moduleRow(module: SqlModule, mode: BlockMode): string {
  return `insert into better_supabase.modules (name, version, mode)
values (${sqlString(module.name)}, ${String(moduleVersion(module))}, ${sqlString(mode)})
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();`;
}

/**
 * The files `sql add` writes for these modules. Modules in `custom` mode
 * write nothing: the app implements their contract. A schema module's rows,
 * role settings and other statements a schema diff can't capture go to a
 * second file in `better-supabase-data/` (`kind: 'data'`), which
 * `sql data` writes into a migration.
 */
export function renderModules(
  names: readonly string[],
  layout: ModuleLayout = {},
): ModuleFile[] {
  checkModules(layout.modules);
  const modules = resolveModules(names, layout);
  const installed = modules.map((module) => module.name);
  return modules.flatMap((module): ModuleFile[] => {
    const ctx = moduleContext(module.name, layout, installed);
    if (ctx.mode === "custom") return [];
    const title = `-- better-supabase module: ${module.name}${layout.version ? ` (${layout.version})` : ""}`;
    const managed = [
      "-- Managed by `better-supabase sql add`; re-running it overwrites this file.",
      "-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.",
    ];
    const header = [
      title,
      `-- @bs-module ${module.name}@${String(moduleVersion(module))} ${ctx.mode}`,
      `-- ${module.description}`,
      ...managed,
    ].join("\n");
    const extra = module.extras?.(ctx, layout) ?? "";
    const wrappers = deprecationWrappers(module, ctx);
    const body = moduleSql(module, ctx, layout).trim();
    module.contract?.(ctx);
    const api = ctx.config.api
      ? apiWrappers(
          body,
          ctx.schemaName,
          ctx.config.api,
          module.name,
          module.internal,
        )
      : "";
    if (module.target === "test") {
      checkFunctionRenames(ctx);
      return [
        {
          module: module.name,
          kind: "test",
          path: modulePath(module, layout),
          contents: `${header}\n\n${body}\n${extra}${wrappers}`,
        },
      ];
    }
    const data = [
      moduleExtensions(body),
      eventTriggersOf(body)
        .map((trigger) => trigger.statement)
        .join("\n"),
      module.data?.(ctx, layout).trim() ?? "",
      moduleRow(module, ctx.mode),
    ]
      .filter((part) => part !== "")
      .join("\n\n");
    const dataHeader = [
      title,
      `-- @bs-module-data ${module.name}`,
      "-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`",
      "-- after the schema migration to put them in a migration.",
      ...managed,
    ].join("\n");
    const testsDir = (layout.testsDir ?? CONFIG_DEFAULTS.sql.testsDir).replace(
      /\/$/,
      "",
    );
    const slug = module.name.replaceAll("-", "_");
    const testHeader = [
      title,
      `-- @bs-module-test ${module.name}`,
      ...managed,
    ].join("\n");
    const tests = module.tests?.(ctx, layout) ?? [];
    checkFunctionRenames(ctx);
    return [
      {
        module: module.name,
        kind: "schema",
        path: modulePath(module, layout),
        contents: `${header}\n\n${body}\n${extra}${wrappers}${api}${MODULE_MODULES_TABLE}`,
      },
      {
        module: module.name,
        kind: "data",
        path: moduleDataPath(module, layout),
        contents: `${dataHeader}\n\n${data}\n`,
      },
      ...tests.map((test): ModuleFile => ({
        module: module.name,
        kind: "test",
        path: `${testsDir}/900_better_supabase_${slug}_${test.name}.test.sql`,
        contents: `${testHeader}\n\n${test.sql.trim()}\n`,
      })),
    ];
  });
}

/** Throws on a `blocks.<name>.functions` key the module writes no function for. */
function checkFunctionRenames(ctx: ModuleContext): void {
  const unknown = ctx.unusedFunctions();
  if (unknown.length === 0) return;
  throw new TypeError(
    `blocks.${ctx.module}.functions: the ${ctx.module} module writes no function ${unknown.map((name) => `"${name}"`).join(", ")}`,
  );
}

export interface ModuleTopic {
  readonly module: string;
  readonly topic: string;
}

export function moduleTopics(
  names: readonly string[],
  layout: ModuleLayout = {},
): ModuleTopic[] {
  const modules = resolveModules(names, layout);
  const installed = modules.map((module) => module.name);
  return modules.flatMap((module) => {
    if (module.topics === undefined) return [];
    const ctx = moduleContext(module.name, layout, installed);
    if (ctx.mode === "custom") return [];
    return module.topics(ctx).map((topic) => ({ module: module.name, topic }));
  });
}

/** The contract functions of the modules in `custom` mode, for doctor. */
export function customContracts(
  names: readonly string[],
  layout: ModuleLayout = {},
): {
  readonly module: string;
  readonly schema: string;
  readonly idType: ModuleIdType;
  readonly functions: readonly ModuleContractFunction[];
}[] {
  const modules = resolveModules(names, layout);
  const installed = modules.map((module) => module.name);
  return modules.flatMap((module) => {
    const ctx = moduleContext(module.name, layout, installed);
    if (ctx.mode !== "custom" || !module.contract) return [];
    return [
      {
        module: module.name,
        schema: ctx.schemaName,
        idType: ctx.idType,
        functions: module.contract(ctx).map((fn) => ({
          ...fn,
          name: ctx.fnName(fn.name),
        })),
      },
    ];
  });
}
