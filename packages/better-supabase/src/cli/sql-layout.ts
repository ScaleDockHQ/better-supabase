import { existsSync } from "node:fs";
import { readdir, readFile } from "node:fs/promises";
import { dirname, join, relative, resolve, sep } from "node:path";

import type { ResolvedConfig } from "../config/index.ts";
import type {
  BlockSqlAccessProvider,
  BlockSqlEntitlementsProvider,
  BlockSqlLayout,
  AuditedTable,
  OwnIndex,
  OwnView,
} from "../sql/index.ts";
import type { FilePlan } from "./core/files.ts";
import type { CatalogPolicy } from "./introspect/types.ts";

import {
  adoptedColumnProblems,
  auditRegistrations,
  declaredIndexes,
  declaredTableColumns,
  declaredTables,
  declaredViews,
  declaredPolicies,
  declaredUpdatedAtTriggers,
  extensionSchema,
  moduleLayout,
  policyGrants,
  resolveExposeColumns,
  resolveBlocks,
  sameTenantLayout,
  rlsTables,
} from "../sql/index.ts";
import { parseSnapshot } from "./commands/snapshot.ts";
import { toCatalog } from "./introspect/catalog.ts";
import { TypegenMissingError } from "./introspect/typegen.ts";
import {
  declarativeSchemasDir,
  readSupabaseToml,
  schemaPaths,
  sqlWorkflow,
} from "./supabase-toml.ts";

/** The folder the module data files sit next to, for the project's workflow. */
export async function schemasDirOf(config: ResolvedConfig): Promise<string> {
  const toml = await readSupabaseToml(config.root);

  return declarativeSchemasDir(toml, sqlWorkflow(config, toml));
}

/** The declarative schema files, then the migrations oldest first. */
async function schemaTexts(
  config: ResolvedConfig,
): Promise<{ readonly path: string; readonly text: string }[]> {
  const toml = await readSupabaseToml(config.root);
  const migrations = resolve(config.root, migrationsDir(config));

  const paths = [
    ...(await schemaPaths(config.root, toml, sqlWorkflow(config, toml))).files,
    ...(existsSync(migrations)
      ? (await readdir(migrations))
          .filter((name) => name.endsWith(".sql"))
          .toSorted()
          .map((name) => join(migrations, name))
      : []),
  ];

  return Promise.all(
    paths.map(async (path) => ({
      path,
      text: await readFile(resolve(config.root, path), "utf-8"),
    })),
  );
}

async function declarativeTexts(
  config: ResolvedConfig,
): Promise<{ readonly path: string; readonly text: string }[]> {
  const toml = await readSupabaseToml(config.root);

  const { files } = await schemaPaths(
    config.root,
    toml,
    sqlWorkflow(config, toml),
  );

  if (files.length === 0) {
    return schemaTexts(config);
  }

  return Promise.all(
    files.map(async (path) => ({
      path,
      text: await readFile(resolve(config.root, path), "utf-8"),
    })),
  );
}

/**
 * The `better_supabase.audit(...)` calls in the declarative schemas, then the
 * migrations oldest first, so a later call or `unaudit` wins.
 */
async function auditedTables(config: ResolvedConfig): Promise<AuditedTable[]> {
  return auditRegistrations(await schemaTexts(config));
}

/**
 * What differs between the callers of `moduleLayoutFor`: the providers and the
 * compiled read sets.
 */
export interface LayoutInput {
  readonly names: readonly string[];
  readonly testsDir?: string | undefined;
  readonly readSets?: BlockSqlLayout["readSets"] | undefined;
  readonly entitlementsProvider?: BlockSqlEntitlementsProvider | undefined;
  readonly accessProvider?: BlockSqlAccessProvider | undefined;
  readonly permissionCatalog?: readonly string[] | undefined;
}

/**
 * The layout `upgrade` and doctor render the module files with, so both see the
 * same grants, session policies, audit triggers and vector schema.
 */
export async function moduleLayoutFor(
  config: ResolvedConfig,
  input: LayoutInput,
): Promise<BlockSqlLayout> {
  const resolved = new Set(
    resolveBlocks(
      input.names,
      input.entitlementsProvider
        ? { entitlementsProvider: input.entitlementsProvider }
        : {},
    ).map((module) => module.name),
  );

  const own = await ownLayout(config);

  const adopted = adoptedColumnProblems(
    config.blocks,
    await declarativeTexts(config),
    config.schemas,
    own.ownTables,
    config.subjects,
  );

  if (adopted.length > 0) {
    throw new TypeError(adopted.join("\n"));
  }

  const fromPolicies =
    resolved.has("grants") &&
    config.blocks["grants"]?.options?.["fromPolicies"] === true;

  const sessionPolicies =
    resolved.has("sessions") &&
    config.blocks["sessions"]?.options?.["policies"] === true;

  const sameTenant = config.blocks["memberships"]?.options?.["sameTenant"];

  const autoSameTenant =
    resolved.has("memberships") &&
    typeof sameTenant === "object" &&
    sameTenant !== null &&
    "auto" in sameTenant &&
    sameTenant.auto === true;

  const base = moduleLayout(
    config,
    input.testsDir,
    input.readSets ?? [],
    input.entitlementsProvider,
    input.accessProvider,
    input.permissionCatalog,
  );

  const grants =
    base.grants === undefined
      ? undefined
      : resolveExposeColumns(
          base.grants,
          await declarativeTexts(config),
          config.schemas,
        );

  return {
    ...base,
    ...(grants === undefined ? {} : { grants }),
    schemasDir: await schemasDirOf(config),
    ...(resolved.has("audit")
      ? { auditedTables: await auditedTables(config) }
      : {}),
    ...(resolved.has("vector-search")
      ? vectorSchemaOf(await schemaTexts(config))
      : {}),
    ...(fromPolicies
      ? {
          policyGrants: policyGrants(
            await declarativeTexts(config),
            config.schemas,
          ),
        }
      : {}),
    ...(fromPolicies
      ? { rlsTables: rlsTables(await declarativeTexts(config), config.schemas) }
      : {}),
    ...(autoSameTenant
      ? sameTenantLayout(await declarativeTexts(config), config.schemas)
      : {}),
    ...(fromPolicies || sessionPolicies
      ? {
          declaredTables: declaredTables(
            await declarativeTexts(config),
            config.schemas,
          ),
        }
      : {}),
    ...own,
  };
}

/**
 * `ownTables`, `ownViews`, `ownColumns`, `ownUpdatedAtTriggers` and
 * `ownPolicies`: the database's tables and views, then the app's files.
 */
async function ownLayout(
  config: ResolvedConfig,
): Promise<
  Pick<
    BlockSqlLayout,
    | "ownTables"
    | "ownViews"
    | "ownColumns"
    | "ownUpdatedAtTriggers"
    | "ownPolicies"
    | "ownIndexes"
  >
> {
  const database = await databaseTables(config);

  const own = (await declarativeTexts(config)).filter(
    (source) => !writtenByBlocks(source),
  );

  const columns = Object.fromEntries(
    [...declaredTableColumns(own, config.schemas)].map(([table, names]) => [
      table,
      [...names],
    ]),
  );

  const views = ownDeclaredViews(own, config.schemas);

  return {
    ownTables: {
      ...database.tables,
      ...ownDeclaredTables(own, config.schemas),
      ...views.tables,
    },
    ownViews: { ...database.views, ...views.views },
    ownColumns: { ...database.columns, ...columns, ...views.columns },
    ownUpdatedAtTriggers: {
      ...database.updatedAtTriggers,
      ...declaredUpdatedAtTriggers(own, config.schemas),
    },
    ownPolicies: {
      ...database.policies,
      ...declaredPolicies(own, config.schemas),
    },
    ownIndexes: mergeIndexes(
      database.indexes,
      declaredIndexes(own, config.schemas),
    ),
  };
}

function mergeIndexes(
  database: Readonly<Record<string, readonly OwnIndex[]>>,
  declared: ReadonlyMap<string, readonly OwnIndex[]>,
): Readonly<Record<string, readonly OwnIndex[]>> {
  const merged: Record<string, readonly OwnIndex[]> = { ...database };

  for (const [table, indexes] of declared) {
    merged[table] = [...(merged[table] ?? []), ...indexes];
  }

  return merged;
}

/** A trigger function named like one that keeps `updated_at` current. */
const UPDATED_AT_FUNCTION = /updated_at|moddatetime|touch/i;

const BLOCK_MARKER = /^-- @(?:bsb-block|bsb-tables|bs-module|bs-app-tables)\b/m;

const BLOCK_MIGRATION = /_better_supabase_[a-z_]+\.sql$/;

/**
 * The `schema.table`s that the files better-supabase wrote create, among
 * `sources`; a table an app table entry enriches is not one of them.
 */
export function blockDeclaredTables(
  sources: readonly { readonly path: string; readonly text: string }[],
  schemas: readonly string[],
): ReadonlySet<string> {
  return new Set(declaredTables(sources.filter(writtenByBlocks), schemas));
}

/** A file better-supabase wrote: a block file or a module migration. */
export function writtenByBlocks(source: {
  readonly path: string;
  readonly text: string;
}): boolean {
  return BLOCK_MARKER.test(source.text) || BLOCK_MIGRATION.test(source.path);
}

/**
 * The tables in the saved snapshot (`source.snapshot`) that no block file or
 * module migration created, mapped to `database`. Without a snapshot, the app's
 * schema files and migrations stand in for it.
 */
async function databaseTables(
  config: ResolvedConfig,
): Promise<{
  readonly tables: Readonly<Record<string, string>>;
  readonly views: Readonly<Record<string, OwnView>>;
  readonly columns: Readonly<Record<string, readonly string[]>>;
  readonly updatedAtTriggers: Readonly<Record<string, string>>;
  readonly policies: Readonly<Record<string, readonly CatalogPolicy[]>>;
  readonly indexes: Readonly<Record<string, readonly OwnIndex[]>>;
}> {
  const none = {
    tables: {},
    views: {},
    columns: {},
    updatedAtTriggers: {},
    policies: {},
    indexes: {},
  };

  const path = config.source.snapshot;

  if (path === undefined || !existsSync(resolve(config.root, path))) {
    return none;
  }

  let snapshot;

  try {
    snapshot = await parseSnapshot(
      JSON.parse(await readFile(resolve(config.root, path), "utf-8")),
      path,
    );
  } catch (cause) {
    // Reading a snapshot's metadata needs the optional typegen peer; without
    // it, the migrations still name the app's tables.
    if (cause instanceof TypegenMissingError) {
      return none;
    }

    throw cause;
  }

  const created = blockDeclaredTables(
    await schemaTexts(config),
    config.schemas,
  );

  const blockIndexes = new Set(
    [
      ...declaredIndexes(
        (await schemaTexts(config)).filter(writtenByBlocks),
        config.schemas,
      ).values(),
    ].flatMap((list) => list.map((index) => index.name)),
  );

  const tables: Record<string, string> = {};
  const views: Record<string, OwnView> = {};
  const columns: Record<string, readonly string[]> = {};
  const updatedAtTriggers: Record<string, string> = {};
  const policies: Record<string, readonly CatalogPolicy[]> = {};
  const indexes: Record<string, readonly OwnIndex[]> = {};

  for (const table of toCatalog(snapshot).tables) {
    const name = `${table.schema}.${table.name}`;

    if (config.schemas.includes(table.schema) && !created.has(name)) {
      tables[name] = "database";
      columns[name] = table.columns.map((column) => column.name);

      if (table.kind === "view") {
        views[name] = { updatable: table.insertable && table.updatable };
      }

      const kept = table.triggers.find(
        (trigger) =>
          !trigger.name.startsWith("bsb_") &&
          trigger.events.includes("update") &&
          UPDATED_AT_FUNCTION.test(trigger.function),
      );

      if (kept !== undefined) {
        updatedAtTriggers[name] = kept.name;
      }

      policies[name] = table.policies.filter(
        (policy) => !policy.name.startsWith("bsb_"),
      );

      indexes[name] = table.indexes
        .filter(
          (index) =>
            !index.partial &&
            [undefined, "btree"].includes(index.method) &&
            !blockIndexes.has(index.name),
        )
        .map((index) => ({ name: index.name, columns: index.columns }));
    }
  }

  return { tables, views, columns, updatedAtTriggers, policies, indexes };
}

/**
 * `schema.table` to the app's own schema file that creates it: every
 * declarative file, or migration, that better-supabase didn't write.
 */
function ownDeclaredTables(
  sources: readonly { readonly path: string; readonly text: string }[],
  schemas: readonly string[],
): Readonly<Record<string, string>> {
  const ownTables: Record<string, string> = {};

  for (const source of sources) {
    for (const table of declaredTables([source], schemas)) {
      ownTables[table] ??= source.path;
    }
  }

  return ownTables;
}

/**
 * The views and materialized views the app's own files create, as `ownTables`
 * entries, with their columns where the files name them.
 */
function ownDeclaredViews(
  sources: readonly { readonly path: string; readonly text: string }[],
  schemas: readonly string[],
): {
  readonly tables: Readonly<Record<string, string>>;
  readonly views: Readonly<Record<string, OwnView>>;
  readonly columns: Readonly<Record<string, readonly string[]>>;
} {
  const tables: Record<string, string> = {};
  const views: Record<string, OwnView> = {};
  const columns: Record<string, readonly string[]> = {};

  for (const source of sources) {
    for (const [view, declared] of declaredViews([source], schemas)) {
      tables[view] ??= source.path;
      views[view] = { updatable: declared.updatable };

      if (declared.columns !== undefined) {
        columns[view] = declared.columns;
      }
    }
  }

  return { tables, views, columns };
}

function vectorSchemaOf(sources: readonly { readonly text: string }[]): {
  vectorSchema?: string;
} {
  const schema = extensionSchema(sources, "vector");

  return schema === undefined ? {} : { vectorSchema: schema };
}

/**
 * The folder that holds both the project root and `sql.dir`: the root, or an
 * ancestor when `sql.dir` points at a shared stack. The `sql` commands write
 * SQL files only inside it.
 */
function sqlRoot(config: ResolvedConfig): string {
  const dir = resolve(config.root, config.sql.dir);
  let stop = resolve(config.root);

  while (
    dir !== stop &&
    !dir.startsWith(stop + sep) &&
    dirname(stop) !== stop
  ) {
    stop = dirname(stop);
  }

  return stop;
}

/**
 * A plan for files under the project root or `sql.dir`, with paths relative to
 * the project root.
 */
export function sqlPlan(
  config: ResolvedConfig,
  plan: Omit<FilePlan, "root" | "base">,
): FilePlan {
  return {
    ...plan,
    root: sqlRoot(config),
    base: config.root,
    files: plan.files.map((file) => ({
      ...file,
      path: resolve(config.root, file.path),
    })),
    ...(plan.remove
      ? {
          remove: plan.remove.map((entry) => {
            const path = resolve(
              config.root,
              typeof entry === "string" ? entry : entry.path,
            );

            return typeof entry === "string" ? path : { ...entry, path };
          }),
        }
      : {}),
  };
}

/**
 * The migrations folder next to the `config.toml` found walking up from
 * `sql.dir`, relative to the root; `supabase/migrations` without one. The walk
 * stops where `sql.dir` and the root meet, so a `sql.dir` outside the project
 * (a shared stack in a monorepo) finds that stack's folder.
 */
export function migrationsDir(config: ResolvedConfig): string {
  const root = resolve(config.root);
  let dir = resolve(root, config.sql.dir);
  const stop = sqlRoot(config);

  for (;;) {
    if (existsSync(join(dir, "config.toml"))) {
      return relative(root, join(dir, "migrations")).replaceAll("\\", "/");
    }

    if (dir === stop || dirname(dir) === dir) {
      break;
    }

    dir = dirname(dir);
  }

  return "supabase/migrations";
}
