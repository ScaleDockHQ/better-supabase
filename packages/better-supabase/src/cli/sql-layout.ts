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
  appColumnsOf,
  declaredPolicies,
  moduleLayout,
  resolveExposeColumns,
  resolveBlocks,
  sameTenantLayout,
  mappingTagsOf,
  sameTenantTagsOf,
  withMappingTags,
} from "../sql/index.ts";
import { apiUsedNames } from "./api-used.ts";
import { parseSnapshot } from "./commands/snapshot.ts";
import { toCatalog } from "./introspect/catalog.ts";
import { TypegenMissingError } from "./introspect/typegen.ts";
import {
  declaredForeignKeys as appForeignKeys,
  declaredIndexes,
  declaredTableColumns,
  declaredColumnTypes,
  declaredTables,
  declaredViews,
  declaredUpdatedAtTriggers,
  extensionSchema,
  policyGrants,
  primeSchemaFacts,
  rlsTables,
} from "./sql-facts.ts";
import {
  configFileInDir,
  declarativeSchemasDir,
  pgFunctionHooks,
  readSupabaseConfig,
  schemaPaths,
  sqlWorkflow,
} from "./supabase-config.ts";

/** The folder the module data files sit next to, for the project's workflow. */
export async function schemasDirOf(config: ResolvedConfig): Promise<string> {
  const toml = await readSupabaseConfig(config.root);

  return declarativeSchemasDir(toml, sqlWorkflow(config, toml));
}

/**
 * Reads kept for the length of one `withLayoutSession`. A probe renders the
 * blocks hundreds of times over the same files; without the session each render
 * reads and scans every schema file and the snapshot again.
 */
let session: Map<string, Promise<unknown>> | undefined;

/** Runs `run` with the layout's file reads and scans shared between calls. */
export async function withLayoutSession<T>(run: () => Promise<T>): Promise<T> {
  const outer = session;
  session ??= new Map();

  try {
    return await run();
  } finally {
    session = outer;
  }
}

function shared<T>(
  key: string,
  root: string,
  read: () => Promise<T>,
): Promise<T> {
  if (session === undefined) {
    return read();
  }

  const id = `${key}\0${root}`;
  // SAFETY: each key is only ever filled by the read of that name.
  const hit = session.get(id) as Promise<T> | undefined;

  if (hit !== undefined) {
    return hit;
  }

  const made = read();
  session.set(id, made);

  return made;
}

const schemaTexts = (
  config: ResolvedConfig,
): ReturnType<typeof readSchemaTexts> =>
  shared("schemaTexts", config.root, () => readSchemaTexts(config));

const declarativeTexts = (
  config: ResolvedConfig,
): ReturnType<typeof readDeclarativeTexts> =>
  shared("declarativeTexts", config.root, () => readDeclarativeTexts(config));

const snapshotCatalog = (
  config: ResolvedConfig,
): ReturnType<typeof readSnapshotCatalog> =>
  shared("snapshotCatalog", config.root, () => readSnapshotCatalog(config));

const databaseTables = (
  config: ResolvedConfig,
): ReturnType<typeof readDatabaseTables> =>
  shared("databaseTables", config.root, () => readDatabaseTables(config));

const auditedTables = (
  config: ResolvedConfig,
): ReturnType<typeof readAuditedTables> =>
  shared("auditedTables", config.root, () => readAuditedTables(config));

/**
 * The migrations oldest first, then the declarative schema files, so a schema
 * file, which holds the final state, wins over an older migration.
 */
async function readSchemaTexts(
  config: ResolvedConfig,
): Promise<{ readonly path: string; readonly text: string }[]> {
  const toml = await readSupabaseConfig(config.root);
  const migrations = resolve(config.root, migrationsDir(config));

  const paths = [
    ...(existsSync(migrations)
      ? (await readdir(migrations))
          .filter((name) => name.endsWith(".sql"))
          .toSorted()
          .map((name) => join(migrations, name))
      : []),
    ...(await schemaPaths(config.root, toml, sqlWorkflow(config, toml))).files,
  ];

  const texts = await Promise.all(
    paths.map(async (path) => ({
      path,
      text: await readFile(resolve(config.root, path), "utf-8"),
    })),
  );

  await primeSchemaFacts(texts, config.root);

  return texts;
}

async function readDeclarativeTexts(
  config: ResolvedConfig,
): Promise<{ readonly path: string; readonly text: string }[]> {
  const toml = await readSupabaseConfig(config.root);
  const workflow = sqlWorkflow(config, toml);
  const { files } = await schemaPaths(config.root, toml, workflow);

  // Only pg-delta treats the schema files as the whole schema. Under migra the
  // app's tables stay in the migrations, so reading the schema files alone
  // would lose them once the modules' own files sit in that folder.
  if (files.length === 0 || workflow !== "pg-delta") {
    return schemaTexts(config);
  }

  const texts = await Promise.all(
    files.map(async (path) => ({
      path,
      text: await readFile(resolve(config.root, path), "utf-8"),
    })),
  );

  await primeSchemaFacts(texts, config.root);

  return texts;
}

/**
 * The `better_supabase.audit(...)` calls in the migrations oldest first, then
 * the declarative schemas, so a later call or `unaudit` wins and the schema
 * files, which hold the final state, win over a migration.
 */
async function readAuditedTables(
  config: ResolvedConfig,
): Promise<AuditedTable[]> {
  return auditRegistrations(await schemaTexts(config));
}

/** The custom access token hook of config.toml, for the pgTAP helpers. */
async function accessTokenHookOf(
  config: ResolvedConfig,
): Promise<{ customAccessTokenHook?: string }> {
  const toml = await readSupabaseConfig(config.root);

  const hook = toml
    ? pgFunctionHooks(toml.document).find(
        (entry) => entry.hook === "custom_access_token",
      )
    : undefined;

  return hook ? { customAccessTokenHook: `${hook.schema}.${hook.name}` } : {};
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
    input.accessProvider,
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
    sameTenant !== false &&
    !(
      typeof sameTenant === "object" &&
      sameTenant !== null &&
      !Array.isArray(sameTenant) &&
      "auto" in sameTenant &&
      sameTenant.auto === false
    );

  const base = moduleLayout(
    config,
    input.testsDir,
    input.readSets ?? [],
    input.entitlementsProvider,
    input.accessProvider,
    input.permissionCatalog,
  );

  const mapped = withMappingTags(
    base.modules ?? {},
    base.instances ?? {},
    mappingTagsOf(
      (await appSchemaTexts(config)).map((file) => file.text),
      config.schemas,
    ),
  );

  const grants =
    base.grants === undefined
      ? undefined
      : resolveExposeColumns(
          base.grants,
          await declarativeTexts(config),
          config.schemas,
        );

  const apiUsed = await apiUsedNames(config);

  const rerunnable =
    sqlWorkflow(config, await readSupabaseConfig(config.root)) === "migrations";

  return {
    ...base,
    modules: mapped.modules,
    instances: mapped.instances,
    ...(rerunnable ? { rerunnable } : {}),
    ...(grants === undefined ? {} : { grants }),
    ...(apiUsed === undefined ? {} : { apiUsed }),
    schemasDir: await schemasDirOf(config),
    ...appScans(await appSchemaTexts(config), config.schemas),
    ...(resolved.has("imports")
      ? { appFunctions: appFunctionsOf(await appSchemaTexts(config)) }
      : {}),
    ...(resolved.has("pgtap") ? await accessTokenHookOf(config) : {}),
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

type AppScans = Pick<
  BlockSqlLayout,
  "uuidColumns" | "idTypes" | "foreignKeys" | "sameTenantTags"
>;

/**
 * The last scan by its input. Doctor asks for the layout once per rule, and
 * these scans of a large schema folder cost seconds each, so the same files are
 * scanned once.
 */
let lastScans: { key: string; scans: AppScans } | undefined;

function appScans(
  files: readonly { readonly path: string; readonly text: string }[],
  schemas: readonly string[],
): AppScans {
  const key = `${schemas.join(",")}\0${files.map((file) => file.text).join("\0")}`;

  if (lastScans?.key !== key) {
    const foreignKeys = appForeignKeys(files, schemas);

    lastScans = {
      key,
      scans: {
        uuidColumns: uuidColumnsOf(files, schemas),
        idTypes: idTypesOf(files, schemas),
        foreignKeys,
        sameTenantTags: sameTenantTagsOf(
          files.map((file) => file.text),
          schemas,
          foreignKeys,
        ),
      },
    };
  }

  return lastScans.scans;
}

const FUNCTION_DECLARATION =
  /\bcreate\s+(?:or\s+replace\s+)?function\s+(?:"?([a-z_][a-z0-9_]*)"?\s*\.\s*)?"?([a-z_][a-z0-9_]*)"?\s*\(/giu;

/**
 * The functions the app's files create, as `schema.name` (`public`
 * unqualified).
 */
function appFunctionsOf(
  files: readonly { readonly text: string }[],
): readonly string[] {
  return [
    ...new Set(
      files.flatMap((file) =>
        [...file.text.matchAll(FUNCTION_DECLARATION)].map((match) =>
          `${match[1] ?? "public"}.${match[2] ?? ""}`.toLowerCase(),
        ),
      ),
    ),
  ];
}

/** The columns the app's files declare as `uuid`, by `schema.table`. */
function uuidColumnsOf(
  files: readonly { readonly text: string }[],
  schemas: readonly string[],
): Readonly<Record<string, readonly string[]>> {
  return Object.fromEntries(
    [...declaredColumnTypes(files, schemas)]
      .map(
        ([table, columns]) =>
          [
            table,
            [...columns].flatMap(([name, type]) =>
              type === "uuid" ? [name] : [],
            ),
          ] as const,
      )
      .filter(([, columns]) => columns.length > 0),
  );
}

/** The schema files the app wrote, not the ones blocks did. */
export async function appSchemaTexts(
  config: ResolvedConfig,
): Promise<Awaited<ReturnType<typeof declarativeTexts>>> {
  return (await declarativeTexts(config)).filter(
    (source) => !writtenByBlocks(source),
  );
}

/** The columns the app's schema files add to block tables, by table. */
export async function appColumnsFor(
  config: ResolvedConfig,
): Promise<ReturnType<typeof appColumnsOf>> {
  return appColumnsOf(
    (await declarativeTexts(config)).filter(
      (source) => !writtenByBlocks(source),
    ),
  );
}

/**
 * `ownTables`, `ownViews`, `ownColumns`, `ownUpdatedAtTriggers` and
 * `ownPolicies`: the database's tables and views, then the app's files.
 */
export async function ownLayout(
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
    | "appColumns"
  >
> {
  const database = await databaseTables(config);

  const own = (await declarativeTexts(config)).filter(
    (source) => !writtenByBlocks(source),
  );

  const columns: Record<string, string[]> = Object.fromEntries(
    [...declaredTableColumns(own, config.schemas)].map(([table, names]) => [
      table,
      [...names],
    ]),
  );

  const views = ownDeclaredViews(own, config.schemas);
  const added = appColumnsOf(own);

  // A column the app's files add with `alter table` is declared as well (ADR 0580).
  for (const [table, list] of Object.entries(added)) {
    if (table in columns) {
      columns[table] = [
        ...new Set([...columns[table]!, ...list.map((column) => column.name)]),
      ];
    }
  }

  return {
    appColumns: added,
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
/** The config's snapshot as a catalog, or `undefined` without one. */
async function readSnapshotCatalog(
  config: ResolvedConfig,
): Promise<ReturnType<typeof toCatalog> | undefined> {
  const path = config.source.snapshot;

  if (path === undefined || !existsSync(resolve(config.root, path))) {
    return undefined;
  }

  try {
    return toCatalog(
      await parseSnapshot(
        JSON.parse(await readFile(resolve(config.root, path), "utf-8")),
        path,
      ),
    );
  } catch (cause) {
    // Reading a snapshot's metadata needs the optional typegen peer; without
    // it, the migrations still name the app's tables.
    if (cause instanceof TypegenMissingError) {
      return undefined;
    }

    throw cause;
  }
}

/**
 * The column types of `tables` (`schema.table`) in the config's snapshot, by
 * table and column: `uuid`, `int4`, `text[]`. A table the snapshot lacks is
 * left out.
 */
export async function snapshotColumnTypes(
  config: ResolvedConfig,
  tables: readonly string[],
): Promise<ReadonlyMap<string, ReadonlyMap<string, string>>> {
  const wanted = new Set(tables);
  const found = new Map<string, ReadonlyMap<string, string>>();

  if (wanted.size === 0) {
    return found;
  }

  for (const table of (await snapshotCatalog(config))?.tables ?? []) {
    const name = `${table.schema}.${table.name}`;

    if (wanted.has(name)) {
      found.set(
        name,
        new Map(
          table.columns.map((column) => [
            column.name,
            column.isArray ? `${column.udt}[]` : column.udt,
          ]),
        ),
      );
    }
  }

  return found;
}

async function readDatabaseTables(
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

  const catalog = await snapshotCatalog(config);

  if (catalog === undefined) {
    return none;
  }

  const created = blockDeclaredTables(
    await schemaTexts(config),
    config.schemas,
  );

  const blockIndexes = new Map(
    [
      ...declaredIndexes(
        (await schemaTexts(config)).filter(writtenByBlocks),
        config.schemas,
      ).values(),
    ].flatMap((list) =>
      list.map((index) => [index.name, index.columns.join(",")] as const),
    ),
  );

  const tables: Record<string, string> = {};
  const views: Record<string, OwnView> = {};
  const columns: Record<string, readonly string[]> = {};
  const updatedAtTriggers: Record<string, string> = {};
  const policies: Record<string, readonly CatalogPolicy[]> = {};
  const indexes: Record<string, readonly OwnIndex[]> = {};

  for (const table of catalog.tables) {
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
        .filter((index) => {
          const btree = index.method === undefined || index.method === "btree";

          if (
            index.keys !== undefined ||
            blockIndexes.get(index.name) === index.columns.join(",")
          ) {
            return false;
          }

          return (
            !index.partial ||
            (btree &&
              index.unique &&
              notNullKeyPredicate(index.predicate ?? undefined, index.columns))
          );
        })
        .map((index) => ({
          name: index.name,
          columns: index.columns,
          ...(index.method === undefined || index.method === "btree"
            ? {}
            : { method: index.method }),
          ...(index.unique ? { unique: true } : {}),
          plain: index.columns.every((column) =>
            /^[A-Za-z_][\w$]*$/.test(column),
          ),
        }));
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
 * Whether `predicate` is exactly `<column> is not null` for a column of
 * `columns`. The CLI keeps its own copy: it reaches the library only through
 * entry files, and this check is not part of that surface.
 */
function notNullKeyPredicate(
  predicate: string | undefined,
  columns: readonly string[],
): boolean {
  if (predicate === undefined) {
    return false;
  }

  const text = predicate
    .trim()
    .replace(/^where\s+/i, "")
    .replace(/^\(+/, "")
    .replace(/\)+$/, "")
    .trim();

  const match = /^(?:"([^"]+)"|([A-Za-z_][\w$]*))\s+is\s+not\s+null$/i.exec(
    text,
  );

  const column = match?.[1] ?? match?.[2];

  return column !== undefined && columns.includes(column);
}

/**
 * The migrations folder next to the config file found walking up from
 * `sql.dir`, relative to the root; `supabase/migrations` without one. The walk
 * stops where `sql.dir` and the root meet, so a `sql.dir` outside the project
 * (a shared stack in a monorepo) finds that stack's folder.
 */
export function migrationsDir(config: ResolvedConfig): string {
  const root = resolve(config.root);
  let dir = resolve(root, config.sql.dir);
  const stop = sqlRoot(config);

  for (;;) {
    if (configFileInDir(dir) !== undefined) {
      return relative(root, join(dir, "migrations")).replaceAll("\\", "/");
    }

    if (dir === stop || dirname(dir) === dir) {
      break;
    }

    dir = dirname(dir);
  }

  return "supabase/migrations";
}

const ID_TYPES = new Set(["uuid", "text", "bigint", "integer", "smallint"]);

/** The columns the app's files declare with an id-like type, by `schema.table`. */
function idTypesOf(
  files: readonly { readonly text: string }[],
  schemas: readonly string[],
): Readonly<Record<string, Readonly<Record<string, string>>>> {
  return Object.fromEntries(
    [...declaredColumnTypes(files, schemas)]
      .map(
        ([table, columns]) =>
          [
            table,
            Object.fromEntries(
              [...columns].filter(([, type]) => ID_TYPES.has(type)),
            ),
          ] as const,
      )
      .filter(([, columns]) => Object.keys(columns).length > 0),
  );
}
