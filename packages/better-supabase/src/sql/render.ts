import type { BlockSqlContractFunction, BlockSqlIdType } from "./context.ts";
import type { BlockSqlFile, BlockSqlLayout, BlockSql } from "./module-types.ts";

import { CONFIG_DEFAULTS } from "../config/defaults.ts";
import { instancePrefix } from "../config/instances.ts";
import { apiWrappers } from "./api-schema.ts";
import { clientFunctions } from "./client-functions.ts";
import { eventTriggersOf } from "./event-triggers.ts";
import {
  applyIndexSkips,
  indexSkipOf,
  withoutSkippedIndexes,
} from "./index-skip.ts";
import {
  instanceRenames,
  renameIdentifiers,
  renamedInstances,
  rendersOwnInstance,
} from "./instance-names.ts";
import { moduleExtensions } from "./introspect.ts";
import { withBlockHash } from "./markers.ts";
import { moduleContext, viewColumnsOf } from "./module-context.ts";
import { blockSqlVersion } from "./module-types.ts";
import { appTablesFiles } from "./modules/app-tables.ts";
import { ownerSearchTriggers } from "./modules/search.ts";
import { overAppTables } from "./over-app-tables.ts";
import { moduleDataPath, modulePath } from "./paths.ts";
import {
  dataFileHeader,
  moduleHeader,
  moduleRow,
  testFileHeader,
} from "./pipeline/assemble.ts";
import {
  checkEntityTables,
  checkFunctionRenames,
  checkTenantName,
} from "./pipeline/checks.ts";
import { renderModuleCached } from "./pipeline/module-cache.ts";
import { preludeFile } from "./pipeline/prelude.ts";
import {
  guardBelowHeader,
  moduleSql,
  overApp,
  renameQualifiers,
} from "./pipeline/prepare.ts";
import { appTableSet, ownTablesCreatedBy } from "./pipeline/resolve.ts";
import { rerunnableDdl, staticDdl } from "./pipeline/static.ts";
import { withUnscopedFile } from "./pipeline/unscoped.ts";
import { withoutCoveredPolicies } from "./policy-cover.ts";
import { bsbNames } from "./policy-names.ts";
import {
  checkMigrationOptions,
  checkModules,
  resolveBlocks,
} from "./registry.ts";
import { rowAuditData } from "./row-audit.ts";
import { rowRealtimeData } from "./row-realtime.ts";
import { deprecationWrappers } from "./upgrade.ts";
import { assertViewColumns } from "./view-columns.ts";

/** A module's SQL for `layout`, without header; `undefined` in custom mode. */
export function moduleBody(
  name: string,
  layout: BlockSqlLayout = {},
): string | undefined {
  checkModules(layout.modules);
  checkMigrationOptions(layout.modules, layout.ownTables);
  assertViewColumns(viewColumnsOf(layout).missing);
  const modules = resolveBlocks([name], layout);
  const module = modules.find((entry) => entry.name === name)!;

  const ctx = moduleContext(
    name,
    layout,
    modules.map((entry) => entry.name),
  );

  if (ctx.mode === "custom") {
    return undefined;
  }

  const body = withoutCoveredPolicies(
    overApp(renameQualifiers(moduleSql(module, ctx, layout), ctx), ctx, layout),
    layout.ownPolicies,
  );

  const named = bsbNames(
    layout.rerunnable === true
      ? rerunnableDdl(body)
      : staticDdl(body, appTableSet(ctx)),
  );

  const skip = indexSkipOf(layout.modules?.[name], `blocks.${name}.indexes`);

  if (skip.length === 0) {
    return named;
  }

  const stripped = withoutSkippedIndexes(named, new Set(skip));
  const left = skip.filter((index) => !stripped.removed.includes(index));

  if (left.length > 0) {
    throw new TypeError(
      `blocks.${name}.indexes.skip names ${left.join(", ")}, which this module does not create. Indexes: ${stripped.created.toSorted().join(", ")}`,
    );
  }

  return stripped.sql;
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
  checkMigrationOptions(layout.modules, layout.ownTables);
  assertViewColumns(viewColumnsOf(layout).missing);
  const modules = resolveBlocks(names, layout);
  checkTenantName(modules, layout);
  const installed = modules.map((module) => module.name);
  checkEntityTables(modules, layout, installed);

  const cachedFiles = (module: BlockSql, instance?: string): BlockSqlFile[] =>
    renderModuleCached(
      `${module.name}\u0000${instance ?? ""}`,
      layout,
      installed,
      (tracked, trackedInstalled) =>
        moduleFiles(module, tracked, trackedInstalled, instance),
    );

  const files = modules.flatMap((module): BlockSqlFile[] => [
    ...(rendersOwnInstance(module.name, layout) ? cachedFiles(module) : []),
    ...renamedInstances(module.name, layout).flatMap((instance) =>
      cachedFiles(module, instance.name),
    ),
  ]);

  // App table policies take the read-only check like every block policy, so a
  // read-only support or agent session can't write through them either.
  const appFiles = appTablesFiles(layout, installed).map((file) =>
    file.kind === "schema"
      ? {
          ...file,
          contents:
            layout.rerunnable === true
              ? rerunnableDdl(guardBelowHeader(file.contents, layout))
              : staticDdl(guardBelowHeader(file.contents, layout), new Set(), {
                  keepIfNotExists: true,
                }),
        }
      : file,
  );

  const prelude = preludeFile(
    layout,
    installed,
    [...files, ...appFiles].filter((file) => file.kind === "schema"),
  );

  const covered = withUnscopedFile(
    [...(prelude === undefined ? [] : [prelude]), ...files, ...appFiles],
    layout,
  ).map((file) =>
    file.kind === "schema"
      ? {
          ...file,
          contents: withoutCoveredPolicies(file.contents, layout.ownPolicies),
        }
      : file,
  );

  return applyIndexSkips(covered, (instance) =>
    indexSkipOf(layout.modules?.[instance], `blocks.${instance}.indexes`),
  ).map((file) => ({ ...file, contents: withBlockHash(file.contents) }));
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

  const collisions = ownTablesCreatedBy(module, ctx, layout);

  const scoped = (sql: string): string => {
    const renamed = renameIdentifiers(renameQualifiers(sql, ctx), renames);

    const collision = [...collisions].find(
      (table) => overAppTables(renamed, new Set([table])) !== renamed,
    );

    if (collision !== undefined) {
      const file = layout.ownTables?.[collision];
      const where = file === "database" ? "the database" : file;

      throw new Error(
        `blocks.${ctx.instance} creates ${collision}, which is already in ${where}. This module can't run over a table the app has: rename yours, or map the block's table to another name in blocks.${ctx.instance}.tables.`,
      );
    }

    return overApp(renamed, ctx, layout);
  };

  const header = moduleHeader({
    instance: ctx.instance,
    version: blockSqlVersion(module),
    mode: ctx.mode,
    description: module.description,
    block: own ? undefined : module.name,
    entities: Object.values(ctx.resolved.entities)
      .filter(
        (entity) =>
          !entity.global &&
          (entity.to.singular !== entity.from.singular ||
            entity.to.plural !== entity.from.plural),
      )
      .map((entity) => ({ key: entity.key, ...entity.to })),
  });

  const searchAt = installed.indexOf("search");

  const searchTriggers =
    searchAt !== -1 && installed.indexOf(module.name) > searchAt
      ? ownerSearchTriggers(moduleContext("search", layout, installed), ctx)
      : "";

  // The row audit registration belongs in the schema file, so a schema diff
  // keeps the triggers instead of dropping them; a module installed before
  // `audit` has no `audit()` to call yet and registers from its data file.
  const auditAt = installed.indexOf("audit");

  // A static trigger needs no function at apply time under a declarative
  // diff; only the migrations workflow applies the statements in file order.
  const rowAuditBeforeSchema =
    auditAt === -1 ||
    (layout.rerunnable === true && installed.indexOf(module.name) < auditAt);

  const rowAuditSchema = rowAuditBeforeSchema
    ? ""
    : rowAuditData(ctx, layout, installed, true);

  // The same holds for the realtime triggers, which need `broadcast_changes`.
  const realtimeAt = installed.indexOf("realtime-tables");

  const rowRealtimeBeforeSchema =
    realtimeAt === -1 ||
    (layout.rerunnable === true && installed.indexOf(module.name) < realtimeAt);

  const rowRealtimeSchema = rowRealtimeBeforeSchema
    ? ""
    : rowRealtimeData(ctx, installed, true);

  const extra = `${scoped(module.extras?.(ctx, layout) ?? "")}${searchTriggers === "" ? "" : `\n${searchTriggers}\n`}${rowAuditSchema === "" ? "" : `\n${rowAuditSchema}\n`}${rowRealtimeSchema === "" ? "" : `\n${rowRealtimeSchema}\n`}`;
  const wrappers = renameIdentifiers(deprecationWrappers(module, ctx), renames);
  const body = scoped(moduleSql(module, ctx, layout).trim());
  module.contract?.(ctx);

  const api = ctx.config.api
    ? apiWrappers(
        body,
        ctx.schemaName,
        layout.apiUsed === undefined
          ? ctx.config.api
          : { ...ctx.config.api, used: layout.apiUsed },
        module.name,
        module.internal,
        clientFunctions(module.name).map((name) => renames.get(name) ?? name),
      )
    : "";

  // The migrations workflow repeats every statement in each migration; the
  // others read the files as declarative DDL.
  // A rerun renames first, so the drop before each re-created policy and
  // constraint names the object the statement creates.
  const settled = (sql: string): string =>
    layout.rerunnable === true
      ? rerunnableDdl(bsbNames(sql))
      : bsbNames(staticDdl(sql, appTableSet(ctx)));

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
    rowAuditBeforeSchema ? rowAuditData(ctx, layout, installed) : "",
    rowRealtimeBeforeSchema ? rowRealtimeData(ctx, installed) : "",
    moduleRow(module, ctx.mode, ctx.instance),
  ]
    .filter((part) => part !== "")
    .join("\n\n");

  const dataHeader = dataFileHeader(ctx.instance);

  const testsDir = (layout.testsDir ?? CONFIG_DEFAULTS.sql.testsDir).replace(
    /\/$/,
    "",
  );

  const slug = instancePrefix(ctx.instance);

  const testHeader = testFileHeader(ctx.instance);

  const tests = module.tests?.(ctx, layout) ?? [];
  checkFunctionRenames(ctx);

  return [
    file(
      "schema",
      modulePath(module, layout, ctx.instance),
      settled(`${header}\n\n${body}\n${extra}${wrappers}${api}`),
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
