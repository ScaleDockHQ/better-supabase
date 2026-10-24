import type { BlockMode } from "../config/blocks.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlIdType,
} from "./context.ts";
import type { EntityTable } from "./entity-clashes.ts";
import type { BlockSqlFile, BlockSqlLayout, BlockSql } from "./module-types.ts";

import { tenantNameOf } from "../config/blocks.ts";
import { CONFIG_DEFAULTS } from "../config/defaults.ts";
import { instancePrefix } from "../config/instances.ts";
import { sqlString } from "../core/template.ts";
import { applyActorWriteGuards } from "./actor-guard.ts";
import { apiWrappers } from "./api-schema.ts";
import { withColumnTypeFunction } from "./column-type.ts";
import { entityTableClash, tenantNameClashes } from "./entity-clashes.ts";
import { eventTriggersOf } from "./event-triggers.ts";
import {
  instanceRenames,
  renameIdentifiers,
  renamedInstances,
  rendersOwnInstance,
} from "./instance-names.ts";
import { moduleExtensions } from "./introspect.ts";
import { entitiesMarker, withBlockHash } from "./markers.ts";
import { moduleContext } from "./module-context.ts";
import { blockSqlVersion } from "./module-types.ts";
import { appTablesFiles } from "./modules/app-tables.ts";
import { ownerSearchTriggers } from "./modules/search.ts";
import { moduleDataPath, modulePath } from "./paths.ts";
import { checkModules, resolveBlocks, SQL_MODULES } from "./registry.ts";
import { withSubjectMergeFunction } from "./subject-merge-sql.ts";
import { deprecationWrappers } from "./upgrade.ts";

/**
 * `sql` with the parameter qualifiers of renamed functions renamed too:
 * PL/pgSQL and SQL functions name a parameter `fn.param`, so
 * `create_organization.name` follows `create_organization` to
 * `create_workspace.name`.
 */
function renameQualifiers(sql: string, ctx: BlockSqlContext): string {
  let out = sql;

  for (const [from, to] of ctx.functionRenames()) {
    out = out.replaceAll(
      new RegExp(`(?<![\\w."$])${from}\\.(?=[a-z_])`, "g"),
      `${to}.`,
    );
  }

  return out;
}

function moduleSql(
  module: BlockSql,
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
) {
  return withSubjectMergeFunction(
    withColumnTypeFunction(
      applyActorWriteGuards(module.build(ctx, layout), layout),
    ),
  );
}

/** A module's SQL for `layout`, without header; `undefined` in custom mode. */
export function moduleBody(
  name: string,
  layout: BlockSqlLayout = {},
): string | undefined {
  checkModules(layout.modules);
  const modules = resolveBlocks([name], layout);
  const module = modules.find((entry) => entry.name === name)!;

  const ctx = moduleContext(
    name,
    layout,
    modules.map((entry) => entry.name),
  );

  return ctx.mode === "custom"
    ? undefined
    : renameQualifiers(moduleSql(module, ctx, layout), ctx);
}

/** The table `moduleRow` writes to, created by every schema module's file. */
const BLOCKS_TABLE = `
create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;
`;

/**
 * Records the module in `better_supabase.blocks`, which `upgrade` and doctor
 * read. An instance that installs it under another name records its block too.
 */
function moduleRow(
  module: BlockSql,
  mode: BlockMode,
  instance: string,
): string {
  const version = String(blockSqlVersion(module));

  return instance === module.name
    ? `insert into better_supabase.blocks (name, version, mode)
values (${sqlString(module.name)}, ${version}, ${sqlString(mode)})
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();`
    : `alter table better_supabase.blocks add column if not exists block text;
insert into better_supabase.blocks (name, block, version, mode)
values (${sqlString(instance)}, ${sqlString(module.name)}, ${version}, ${sqlString(mode)})
on conflict (name) do update
  set block = excluded.block, version = excluded.version, mode = excluded.mode, updated_at = now();`;
}

/**
 * The files `add` writes for these modules. Modules in `custom` mode write
 * nothing: the app implements their contract. A schema module's rows, role
 * settings and other statements a schema diff can't capture go to a second file
 * in `better-supabase-data/` (`kind: 'data'`), which `add --adopt` writes into
 * a migration. An instance that installs a module under another name renders
 * its own files after the module's.
 */
export function renderBlocks(
  names: readonly string[],
  layout: BlockSqlLayout = {},
): BlockSqlFile[] {
  checkModules(layout.modules);
  const modules = resolveBlocks(names, layout);
  checkTenantName(modules, layout);
  const installed = modules.map((module) => module.name);
  checkEntityTables(modules, layout, installed);

  const files = modules.flatMap((module): BlockSqlFile[] => [
    ...(rendersOwnInstance(module.name, layout)
      ? moduleFiles(module, layout, installed)
      : []),
    ...renamedInstances(module.name, layout).flatMap((instance) =>
      moduleFiles(module, layout, installed, instance.name),
    ),
  ]);

  return [...files, ...appTablesFiles(layout, installed)].map((file) => ({
    ...file,
    contents: withBlockHash(file.contents),
  }));
}

function moduleFiles(
  module: BlockSql,
  layout: BlockSqlLayout,
  installed: readonly string[],
  instance?: string,
): BlockSqlFile[] {
  const ctx = moduleContext(module.name, layout, installed, instance);

  if (ctx.mode === "custom") {
    return [];
  }

  const own = ctx.instance === module.name;

  // The names this instance's SQL shares with the module's own instance,
  // which its context leaves alone: the indexes, constraints and types a
  // module writes by hand. The helpers the render adds around a module are
  // shared by every module, so only what the module builds counts.
  const renames = own
    ? new Map<string, string>()
    : instanceRenames(
        [
          module.build(ctx, layout),
          module.extras?.(ctx, layout) ?? "",
          module.data?.(ctx, layout) ?? "",
        ].join("\n"),
        module.build(moduleContext(module.name, layout, installed), layout),
        instancePrefix(ctx.instance),
      );

  const scoped = (sql: string): string =>
    renameIdentifiers(renameQualifiers(sql, ctx), renames);

  const title = `-- better-supabase module: ${ctx.instance}`;

  const managed = [
    "-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.",
    "-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.",
  ];

  const entities = entitiesMarker(
    ctx.instance,
    Object.values(ctx.resolved.entities)
      .filter(
        (entity) =>
          !entity.global &&
          (entity.to.singular !== entity.from.singular ||
            entity.to.plural !== entity.from.plural),
      )
      .map((entity) => ({ key: entity.key, ...entity.to })),
  );

  const header = [
    title,
    `-- @bsb-block ${ctx.instance}@${String(blockSqlVersion(module))} ${ctx.mode}${own ? "" : ` ${module.name}`}`,
    ...(entities === undefined ? [] : [entities]),
    `-- ${module.description}`,
    ...managed,
  ].join("\n");

  const searchAt = installed.indexOf("search");

  const searchTriggers =
    searchAt !== -1 && installed.indexOf(module.name) > searchAt
      ? ownerSearchTriggers(moduleContext("search", layout, installed), ctx)
      : "";

  const extra = `${scoped(module.extras?.(ctx, layout) ?? "")}${searchTriggers === "" ? "" : `\n${searchTriggers}\n`}`;
  const wrappers = renameIdentifiers(deprecationWrappers(module, ctx), renames);
  const body = scoped(moduleSql(module, ctx, layout).trim());
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

  const file = (
    kind: BlockSqlFile["kind"],
    path: string,
    contents: string,
  ): BlockSqlFile => ({
    module: module.name,
    ...(own ? {} : { instance: ctx.instance }),
    kind,
    path,
    contents,
  });

  if (module.target === "test") {
    checkFunctionRenames(ctx);

    return [
      file(
        "test",
        modulePath(module, layout, ctx.instance),
        `${header}\n\n${body}\n${extra}${wrappers}`,
      ),
    ];
  }

  const data = [
    moduleExtensions(body),
    eventTriggersOf(body)
      .map((trigger) => trigger.statement)
      .join("\n"),
    scoped(module.data?.(ctx, layout).trim() ?? ""),
    moduleRow(module, ctx.mode, ctx.instance),
  ]
    .filter((part) => part !== "")
    .join("\n\n");

  const dataHeader = [
    title,
    `-- @bsb-block-data ${ctx.instance}`,
    "-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`",
    "-- after the schema migration to put them in a migration.",
    ...managed,
  ].join("\n");

  const testsDir = (layout.testsDir ?? CONFIG_DEFAULTS.sql.testsDir).replace(
    /\/$/,
    "",
  );

  const slug = instancePrefix(ctx.instance);

  const testHeader = [
    title,
    `-- @bsb-block-test ${ctx.instance}`,
    ...managed,
  ].join("\n");

  const tests = module.tests?.(ctx, layout) ?? [];
  checkFunctionRenames(ctx);

  return [
    file(
      "schema",
      modulePath(module, layout, ctx.instance),
      `${header}\n\n${body}\n${extra}${wrappers}${api}${BLOCKS_TABLE}`,
    ),
    file(
      "data",
      moduleDataPath(module, layout, ctx.instance),
      `${dataHeader}\n\n${data}\n`,
    ),
    ...tests.map((test) =>
      file(
        "test",
        `${testsDir}/900_better_supabase_${slug}_${test.name}.test.sql`,
        `${testHeader}\n\n${scoped(test.sql.trim())}\n`,
      ),
    ),
  ];
}

/**
 * Throws when `blocks.memberships.names.organization` gives a renamed table or
 * column a name a module already uses.
 */
function checkTenantName(
  modules: readonly BlockSql[],
  layout: BlockSqlLayout,
): void {
  const tenant = tenantNameOf(layout.modules);

  if (tenant === undefined) {
    return;
  }

  for (const module of modules) {
    const clashes = tenantNameClashes(module, tenant, SQL_MODULES);

    if (clashes.length === 0) {
      continue;
    }

    throw new TypeError(
      `blocks.memberships.names.organization: "${tenant}" renames the tenant tables and columns to names the ${module.name} module already uses (${clashes.join(", ")}). Choose another name.`,
    );
  }
}

/**
 * Throws when `blocks.<name>.entities` gives a managed table a name another
 * installed block's table already has.
 */
function checkEntityTables(
  modules: readonly BlockSql[],
  layout: BlockSqlLayout,
  installed: readonly string[],
): void {
  if (
    !modules.some(
      (module) =>
        layout.modules?.[module.name]?.entities !== undefined ||
        renamedInstances(module.name, layout).length > 0,
    )
  ) {
    return;
  }

  const tables = modules.flatMap((module): EntityTable[] =>
    [
      ...(rendersOwnInstance(module.name, layout) ? [module.name] : []),
      ...renamedInstances(module.name, layout).map(({ name }) => name),
    ].flatMap((instance) => {
      const ctx = moduleContext(
        module.name,
        layout,
        installed,
        instance === module.name ? undefined : instance,
      );

      if (!ctx.manages) {
        return [];
      }

      return Object.entries(module.names?.tables ?? {})
        .filter(([logical]) => ctx.config.tables[logical] === undefined)
        .map(([logical, spec]) => {
          const { schema, name } = ctx.tableName(logical);

          return {
            module: instance,
            logical,
            schema,
            name,
            renamed: ctx.resolved.entityNaming.rename(spec.name) !== spec.name,
          };
        });
    }),
  );

  const clash = entityTableClash(tables);

  if (clash !== undefined) {
    throw new TypeError(clash);
  }
}

/** Throws on a `blocks.<name>.functions` key the module writes no function for. */
function checkFunctionRenames(ctx: BlockSqlContext): void {
  const unknown = ctx.unusedFunctions();

  if (unknown.length === 0) {
    return;
  }

  throw new TypeError(
    `blocks.${ctx.module}.functions: the ${ctx.module} module writes no function ${unknown.map((name) => `"${name}"`).join(", ")}`,
  );
}

export interface BlockSqlTopic {
  readonly module: string;
  readonly topic: string;
}

export function moduleTopics(
  names: readonly string[],
  layout: BlockSqlLayout = {},
): BlockSqlTopic[] {
  const modules = resolveBlocks(names, layout);
  const installed = modules.map((module) => module.name);

  return modules.flatMap((module) => {
    if (module.topics === undefined) {
      return [];
    }

    const ctx = moduleContext(module.name, layout, installed);

    if (ctx.mode === "custom") {
      return [];
    }

    return module.topics(ctx).map((topic) => ({ module: module.name, topic }));
  });
}

/** The contract functions of the modules in `custom` mode, for doctor. */
export function customContracts(
  names: readonly string[],
  layout: BlockSqlLayout = {},
): {
  readonly module: string;
  readonly schema: string;
  readonly idType: BlockSqlIdType;
  readonly functions: readonly BlockSqlContractFunction[];
}[] {
  const modules = resolveBlocks(names, layout);
  const installed = modules.map((module) => module.name);

  return modules.flatMap((module) => {
    const ctx = moduleContext(module.name, layout, installed);

    if (ctx.mode !== "custom" || !module.contract) {
      return [];
    }

    return [
      {
        module: module.name,
        schema: ctx.schemaName,
        idType: ctx.idType,
        functions: module
          .contract(ctx)
          .map((fn) => ({ ...fn, name: ctx.fnName(fn.name) })),
      },
    ];
  });
}
