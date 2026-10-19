import { existsSync } from "node:fs";
import { readdir, readFile } from "node:fs/promises";
import { dirname, join, relative, resolve, sep } from "node:path";

import type { ResolvedConfig } from "../config/index.ts";
import type { FilePlan } from "./core/files.ts";

import {
  type ModuleAccessProvider,
  type ModuleEntitlementsProvider,
  type ModuleLayout,
  type AuditedTable,
  adoptedColumnProblems,
  auditRegistrations,
  declaredTables,
  extensionSchema,
  moduleLayout,
  policyGrants,
  resolveExposeColumns,
  resolveModules,
  sameTenantLayout,
  rlsTables,
} from "../sql/index.ts";
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
): Promise<{ readonly text: string }[]> {
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
      text: await readFile(resolve(config.root, path), "utf-8"),
    })),
  );
}

async function declarativeTexts(
  config: ResolvedConfig,
): Promise<{ readonly text: string }[]> {
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
      text: await readFile(resolve(config.root, path), "utf-8"),
    })),
  );
}

/**
 * The `better_supabase.audit(...)` calls in the declarative schemas, then
 * the migrations oldest first, so a later call or `unaudit` wins.
 */
async function auditedTables(config: ResolvedConfig): Promise<AuditedTable[]> {
  return auditRegistrations(await schemaTexts(config));
}

/** What differs between the callers of `moduleLayoutFor`: the providers and the compiled read sets. */
export interface LayoutInput {
  readonly names: readonly string[];
  readonly testsDir?: string | undefined;
  readonly readSets?: ModuleLayout["readSets"] | undefined;
  readonly entitlementsProvider?: ModuleEntitlementsProvider | undefined;
  readonly accessProvider?: ModuleAccessProvider | undefined;
  readonly permissionCatalog?: readonly string[] | undefined;
}

/**
 * The layout `sql sync` and doctor render the module files with, so both
 * see the same grants, session policies, audit triggers and vector schema.
 */
export async function moduleLayoutFor(
  config: ResolvedConfig,
  input: LayoutInput,
): Promise<ModuleLayout> {
  const resolved = new Set(
    resolveModules(input.names, {
      ...(input.entitlementsProvider
        ? { entitlementsProvider: input.entitlementsProvider }
        : {}),
    }).map((module) => module.name),
  );

  const adopted = adoptedColumnProblems(
    config.blocks,
    await declarativeTexts(config),
    config.schemas,
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

  const sameTenant = config.blocks["tenant"]?.options?.["sameTenant"];

  const autoSameTenant =
    resolved.has("tenant") &&
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
      ? {
          rlsTables: rlsTables(await declarativeTexts(config), config.schemas),
        }
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
  };
}

function vectorSchemaOf(sources: readonly { readonly text: string }[]): {
  vectorSchema?: string;
} {
  const schema = extensionSchema(sources, "vector");

  return schema === undefined ? {} : { vectorSchema: schema };
}

/**
 * The folder that holds both the project root and `sql.dir`: the root, or
 * an ancestor when `sql.dir` points at a shared stack. The `sql` commands
 * write SQL files only inside it.
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
 * A plan for files under the project root or `sql.dir`, with paths relative
 * to the project root.
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
      ? { remove: plan.remove.map((path) => resolve(config.root, path)) }
      : {}),
  };
}

/**
 * The migrations folder next to the `config.toml` found walking up from
 * `sql.dir`, relative to the root; `supabase/migrations` without one. The
 * walk stops where `sql.dir` and the root meet, so a `sql.dir` outside the
 * project (a shared stack in a monorepo) finds that stack's folder.
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
