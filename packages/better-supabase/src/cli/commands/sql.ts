import { existsSync } from "node:fs";
import { readdir, readFile, rm } from "node:fs/promises";
import { dirname, join, relative, resolve, sep } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs } from "../command.ts";
import type { CommandResult } from "../io.ts";

import {
  type AuditedTable,
  auditRegistrations,
  contractSignature,
  customContracts,
  type InstalledModule,
  type ModuleAccessPermdock,
  type ModuleExtension,
  type ModuleFile,
  moduleFileVersion,
  type ModuleLayout,
  type ModulePermdock,
  moduleFilePaths,
  moduleLayout,
  modulePermissionKeys,
  moduleBody,
  moduleSchemaExtensions,
  declaredTables,
  policyGrants,
  renderModules,
  resolveModules,
  sameModuleFile,
  SQL_MODULES,
  upgradePlan,
} from "../../sql/index.ts";
import { defineCliCommand } from "../command.ts";
import { fileDiff } from "../diff.ts";
import { display, writeIfChanged } from "../io.ts";
import {
  accessPermdockMode,
  entitlementsMode,
  moduleKeyProblems,
  permdockSource,
  readPermdock,
  readPermissionCatalogKeys,
} from "../permdock.ts";
import { compiledReadSets } from "../read-sets.ts";
import { type Paint, painter, plain } from "../style.ts";
import {
  declarativeSchemasDir,
  migrationCommand,
  readSupabaseToml,
  schemaPaths,
} from "../supabase-toml.ts";
import { topicPolicyFile } from "../topic-policies.ts";

const SQL_ARGS = {
  action: {
    type: "positional",
    required: false,
    description:
      "list (modules and whether they are installed), add <module...>, sync, upgrade, data (a migration with the rows a schema diff skips) or print <module>",
  },
  check: {
    type: "boolean",
    description:
      "With sync: fail when a file is stale. With upgrade: fail when a module is behind",
  },
  "tests-dir": {
    type: "string",
    description: "Where the pgtap module goes. Defaults to sql.testsDir",
    valueHint: "dir",
  },
  "dry-run": { type: "boolean", description: "Show what would be written" },
  force: {
    type: "boolean",
    description: "Write tenant even though a permdock.config.ts is present",
  },
} as const;

export type SqlArgs = CliArgs<typeof SQL_ARGS>;

const USAGE = "Run `better-supabase sql --help` for the actions.";

/** Modules that fill a claim PermDock's hook also writes (`memberships`). */
const PERMDOCK_OWNED: ReadonlySet<string> = new Set(["tenant"]);

/**
 * PermDock's helpers for the `entitlements` module. When `names` resolve to
 * that module, an invalid PermDock mode (no manifest, a scope it lacks, an
 * unknown id type) throws instead of falling back to the tenant module.
 * Without `names` (`sql list`) it only describes the modules, so it doesn't.
 */
async function permdockFor(
  config: ResolvedConfig,
  names?: readonly string[],
): Promise<ModulePermdock | undefined> {
  const mode = entitlementsMode(
    config,
    await readPermdock(config.root, config.permdock),
  );
  switch (mode.kind) {
    case "tenant":
      return undefined;
    case "permdock":
      return mode.permdock;
    case "invalid":
      if (
        names === undefined ||
        !resolveModules(names, {}).some(
          (module) => module.name === "entitlements",
        )
      )
        return undefined;
      throw new TypeError(mode.problem);
    default: {
      const unreachable: never = mode;
      return unreachable;
    }
  }
}

/**
 * PermDock's helpers for the `access` module's `permdock` model, read from
 * the manifest whatever `entitlements` says. When `names` resolve to
 * `access`, an invalid mode throws, and so does a module permission key the
 * catalog doesn't mark `rowConditions: false`. `sql list` (no `names`)
 * doesn't render, so it doesn't throw.
 */
async function accessPermdockFor(
  config: ResolvedConfig,
  names?: readonly string[],
): Promise<ModuleAccessPermdock | undefined> {
  const project = await readPermdock(config.root, config.permdock);
  const mode = accessPermdockMode(config, project);
  const renders =
    names !== undefined &&
    resolveModules(names, {}).some((module) => module.name === "access");
  switch (mode.kind) {
    case "off":
      return undefined;
    case "permdock": {
      if (!renders || !project) return mode.access;
      const problems = moduleKeyProblems(
        project,
        modulePermissionKeys(config.sql.modules, names),
        mode.access,
      );
      if (problems.length > 0) {
        throw new TypeError(
          problems.map((problem) => problem.message).join("\n"),
        );
      }
      return mode.access;
    }
    case "invalid":
      if (!renders) return undefined;
      throw new TypeError(mode.problem);
    default: {
      const unreachable: never = mode;
      return unreachable;
    }
  }
}

/** The keys of PermDock's permission catalog, for `api-keys` scopes. */
function permissionCatalogFor(
  config: ResolvedConfig,
): Promise<readonly string[] | undefined> {
  return readPermissionCatalogKeys(config.root, config.permdock.catalog);
}

async function layout(
  config: ResolvedConfig,
  args: SqlArgs,
  names?: readonly string[],
): Promise<ModuleLayout> {
  return {
    ...moduleLayout(
      config,
      args["tests-dir"],
      [],
      await permdockFor(config, names),
      await accessPermdockFor(config, names),
      await permissionCatalogFor(config),
    ),
    schemasDir: declarativeSchemasDir(await readSupabaseToml(config.root)),
  };
}

/** The declarative schema files, then the migrations oldest first. */
async function schemaTexts(
  config: ResolvedConfig,
): Promise<{ readonly text: string }[]> {
  const toml = await readSupabaseToml(config.root);
  const migrations = resolve(config.root, migrationsDir(config));
  const paths = [
    ...(await schemaPaths(config.root, toml)).files,
    ...(existsSync(migrations)
      ? (await readdir(migrations))
          .filter((name) => name.endsWith(".sql"))
          .toSorted()
          .map((name) => join(migrations, name))
      : []),
  ];
  return Promise.all(
    paths.map(async (path) => ({
      text: await readFile(resolve(config.root, path), "utf8"),
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

/**
 * The layout, with `config.readSets` compiled when `names` includes
 * `read-sets` and the audited tables when it includes `audit`.
 */
async function layoutFor(
  config: ResolvedConfig,
  args: SqlArgs,
  names: readonly string[],
): Promise<ModuleLayout> {
  const permdock = await permdockFor(config, names);
  const resolved = new Set(
    resolveModules(names, {
      ...(permdock ? { permdock } : {}),
    }).map((module) => module.name),
  );
  return {
    ...moduleLayout(
      config,
      args["tests-dir"],
      resolved.has("read-sets") ? await compiledReadSets(config) : [],
      permdock,
      await accessPermdockFor(config, names),
      await permissionCatalogFor(config),
    ),
    schemasDir: declarativeSchemasDir(await readSupabaseToml(config.root)),
    ...(resolved.has("audit")
      ? { auditedTables: await auditedTables(config) }
      : {}),
    ...(resolved.has("grants") &&
    config.sql.modules["grants"]?.options?.["fromPolicies"] === true
      ? {
          policyGrants: policyGrants(await schemaTexts(config), config.schemas),
        }
      : {}),
    ...(resolved.has("sessions") &&
    config.sql.modules["sessions"]?.options?.["policies"] === true
      ? {
          declaredTables: declaredTables(
            await schemaTexts(config),
            config.schemas,
          ),
        }
      : {}),
  };
}

const MODULE_TEST_MARKER = /^-- @bs-module-test ([a-z0-9-]+)$/m;

/**
 * Test files a SQL module wrote for an earlier layout (a table that is no
 * longer audited), for the modules in `names`.
 */
async function staleModuleTests(
  config: ResolvedConfig,
  names: readonly string[],
  sqlLayout: ModuleLayout,
  files: readonly ModuleFile[],
): Promise<string[]> {
  const dir = (sqlLayout.testsDir ?? "supabase/tests").replace(/\/$/, "");
  const entries: string[] = await readdir(resolve(config.root, dir)).catch(
    () => [],
  );
  const current = new Set(files.map((file) => file.path));
  const modules = new Set(
    resolveModules(names, sqlLayout).map((module) => module.name),
  );
  const stale: string[] = [];
  for (const name of entries.toSorted()) {
    const path = `${dir}/${name}`;
    if (!name.endsWith(".test.sql") || current.has(path)) continue;
    const text = await readFile(resolve(config.root, path), "utf8");
    const module = MODULE_TEST_MARKER.exec(text)?.[1];
    if (module !== undefined && modules.has(module)) stale.push(path);
  }
  return stale;
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
  let stop = root;
  while (dir !== stop && !dir.startsWith(stop + sep) && dirname(stop) !== stop)
    stop = dirname(stop);
  for (;;) {
    if (existsSync(join(dir, "config.toml"))) {
      return relative(root, join(dir, "migrations")).replaceAll("\\", "/");
    }
    if (dir === stop || dirname(dir) === dir) break;
    dir = dirname(dir);
  }
  return "supabase/migrations";
}

/** `YYYYMMDDHHMMSS` in UTC, the Supabase CLI's migration prefix. */
const migrationStamp = (now: Date): string =>
  now.toISOString().replaceAll(/[-:T]/g, "").slice(0, 14);

/**
 * A stamp for `now`, or one second after the newest migration when that one
 * has the same stamp or a later one: the Supabase CLI keys migrations by
 * stamp, and the data has to run after the schema.
 */
function stampAfter(migrations: readonly string[], now: Date): string {
  // Every name that starts with 14 digits counts, whatever follows them
  // (another tool's `<stamp>-seeds.sql` or `<stamp>.sql`), so the data
  // migration never shares a timestamp with one.
  const newest = migrations
    .map((name) =>
      /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(?!\d)/.exec(name),
    )
    .filter((match) => match !== null)
    .map((match) =>
      Date.UTC(
        Number(match[1]),
        Number(match[2]) - 1,
        Number(match[3]),
        Number(match[4]),
        Number(match[5]),
        Number(match[6]),
      ),
    )
    .reduce((max, time) => Math.max(max, time), Number.NEGATIVE_INFINITY);
  const at = Math.floor(now.getTime() / 1000) * 1000;
  return migrationStamp(new Date(Math.max(at, newest + 1000)));
}

async function write(
  config: ResolvedConfig,
  args: SqlArgs,
  names: readonly string[],
  sqlLayout: ModuleLayout,
  only?: readonly string[],
): Promise<string[]> {
  const lines: string[] = [];
  const dryRun = args["dry-run"] === true;
  let data = false;
  const files = renderModules(names, sqlLayout).filter(
    (file) => only === undefined || only.includes(file.module),
  );
  for (const path of await staleModuleTests(
    config,
    only ?? names,
    sqlLayout,
    files,
  )) {
    const shown = display(config.root, path);
    if (dryRun) {
      lines.push(`Would remove ${shown}`);
      continue;
    }
    await rm(resolve(config.root, path));
    lines.push(`Removed ${shown}`);
  }
  for (const file of files) {
    const path = resolve(config.root, file.path);
    const shown = display(config.root, file.path);
    if (dryRun) {
      lines.push(`Would write ${shown} (${file.module})`);
      continue;
    }
    const wrote = await writeIfChanged(path, file.contents);
    if (wrote && file.kind === "data") data = true;
    lines.push(`${wrote ? "Wrote" : "Unchanged"} ${shown} (${file.module})`);
  }
  lines.push(...(await writeExtensionsMigration(config, files, dryRun)));
  if (data) lines.push("", DATA_NEXT);
  return lines;
}

const EXTENSIONS_SUFFIX = "_better_supabase_extensions.sql";

const MIGRATION_EXTENSION =
  /^\s*create\s+extension\s+(?:if\s+not\s+exists\s+)?"?([a-z_][a-z0-9_]*)"?/gim;

async function unmigratedExtensions(
  config: ResolvedConfig,
  files: readonly ModuleFile[],
): Promise<{
  dir: string;
  existing: string[];
  missing: ModuleExtension[];
}> {
  const dir = migrationsDir(config);
  const existing: string[] = await readdir(resolve(config.root, dir)).catch(
    () => [],
  );
  const created = new Set<string>();
  for (const name of existing) {
    if (!name.endsWith(".sql") || name.endsWith(DATA_SUFFIX)) continue;
    const text = await readFile(resolve(config.root, dir, name), "utf8");
    for (const match of text.matchAll(MIGRATION_EXTENSION))
      created.add(match[1]!.toLowerCase());
  }
  return {
    dir,
    existing,
    missing: moduleSchemaExtensions(files).filter(
      (extension) => !created.has(extension.name),
    ),
  };
}

async function writeExtensionsMigration(
  config: ResolvedConfig,
  files: readonly ModuleFile[],
  dryRun: boolean,
): Promise<string[]> {
  const { dir, existing, missing } = await unmigratedExtensions(config, files);
  if (missing.length === 0) return [];
  const path = `${dir}/${stampAfter(existing, new Date(Date.now() - 1000))}${EXTENSIONS_SUFFIX}`;
  if (dryRun) return [`Would write ${path}`];
  await writeIfChanged(
    resolve(config.root, path),
    `-- better-supabase sql: the extensions of ${missing.map((extension) => extension.name).join(", ")}, created before the schema migration that needs them.\n\n${missing.map((extension) => extension.statement).join("\n")}\n`,
  );
  return [
    `Wrote ${path}`,
    "It creates the extensions the module schemas need, so create the schema migration after it.",
  ];
}

const DATA_NEXT =
  "The better-supabase-data files hold rows and settings a schema diff skips: after the schema migration, run `better-supabase sql data`.";
const DATA_SUFFIX = "_better_supabase_module_data.sql";

/**
 * Writes the data files of `sql.modules` into one migration, meant to run after
 * the schema migration that creates their tables. Every statement is
 * idempotent, so the migration carries all of them, not only the changes.
 */
async function dataMigration(
  config: ResolvedConfig,
  args: SqlArgs,
): Promise<CommandResult> {
  if (config.sql.moduleNames.length === 0) {
    return { code: 0, output: "sql.modules is empty; nothing to write." };
  }
  const rendered = renderModules(
    config.sql.moduleNames,
    await layoutFor(config, args, config.sql.moduleNames),
  );
  const { missing } = await unmigratedExtensions(config, rendered);
  if (missing.length > 0) {
    return {
      code: 1,
      error: [
        `No migration before the data migration creates ${missing.map((extension) => extension.name).join(", ")}, and the schema migration needs ${missing.length === 1 ? "it" : "them"} while it applies.`,
        "Run `better-supabase sql sync` to write the extensions migration, then create the schema migration again after it.",
      ].join("\n"),
    };
  }
  const files = rendered.filter((file) => file.kind === "data");
  const contents = `-- better-supabase sql data: the rows and settings of ${files.map((file) => file.module).join(", ")}, which a schema diff skips.\n\n${files.map((file) => file.contents.trim()).join("\n\n")}\n`;
  const dir = migrationsDir(config);
  const existing: string[] = await readdir(resolve(config.root, dir)).catch(
    () => [],
  );
  const latest = existing
    .toSorted()
    .findLast((name) => name.endsWith(DATA_SUFFIX));
  if (
    latest !== undefined &&
    (await readFile(resolve(config.root, dir, latest), "utf8")) === contents
  ) {
    return {
      code: 0,
      output: `${dir}/${latest} already has these rows; nothing to write.`,
    };
  }
  const path = `${dir}/${stampAfter(existing, new Date())}${DATA_SUFFIX}`;
  if (args["dry-run"] === true) {
    return { code: 0, output: `Would write ${path}` };
  }
  await writeIfChanged(resolve(config.root, path), contents);
  return { code: 0, output: `Wrote ${path}` };
}

/** A note when migra's `schema_paths` is set and misses module files, which `supabase db diff` would then skip. */
async function unlistedModuleFiles(
  config: ResolvedConfig,
  names: readonly string[],
  sqlLayout: ModuleLayout,
): Promise<string[]> {
  const toml = await readSupabaseToml(config.root);
  const order = await schemaPaths(config.root, toml);
  if (!order.configured) return [];
  const supabase = `${toml?.dir ?? "supabase"}/`;
  const unlisted = new Set(order.unlisted);
  const listed = new Set(order.files.filter((path) => !unlisted.has(path)));
  const dir = `${config.sql.dir.replace(/\/$/, "")}/`;
  const missing = renderModules(names, sqlLayout)
    .filter((file) => file.kind !== "data")
    .map((file) => file.path)
    .filter((path) => path.startsWith(dir) && !listed.has(path));
  if (missing.length === 0) return [];
  return [
    "",
    `${toml?.path ?? "supabase/config.toml"} sets [db.migrations] schema_paths, and no entry matches these files, so \`supabase db diff\` skips them.`,
    "Add them before the schemas that call their functions:",
    ...missing.map(
      (path) =>
        `  "./${path.startsWith(supabase) ? path.slice(supabase.length) : path}",`,
    ),
    "Or switch to pg-delta, which orders the files by dependency: add [experimental.pgdelta] with enabled = true and remove schema_paths (doctor BS316).",
  ];
}

/**
 * Rewrites the module files of modules behind the current version, and writes
 * their upgrade steps (renames, backfills) as a migration that runs before
 * the one the schema diff creates.
 */
async function upgrade(
  config: ResolvedConfig,
  args: SqlArgs,
  paint: Paint,
): Promise<CommandResult> {
  if (config.sql.moduleNames.length === 0) {
    return { code: 0, output: "sql.modules is empty; nothing to upgrade." };
  }
  const sqlLayout = await layoutFor(config, args, config.sql.moduleNames);
  const files = renderModules(config.sql.moduleNames, sqlLayout);
  const installed: InstalledModule[] = [];
  const stale: ModuleFile[] = [];
  const diffs: string[] = [];
  for (const file of files) {
    if (file.kind === "data") continue;
    const current = await readFile(
      resolve(config.root, file.path),
      "utf8",
    ).catch(() => undefined);
    if (current === undefined) continue;
    installed.push({
      module: file.module,
      version: moduleFileVersion(current)?.version ?? 1,
    });
    if (!sameModuleFile(current, file.contents)) {
      stale.push(file);
      diffs.push(
        fileDiff(
          display(config.root, file.path),
          current,
          file.contents,
          paint,
        ),
      );
    }
  }
  const plan = upgradePlan(installed, sqlLayout);
  const behind = plan.map(
    (entry) =>
      `${entry.module} is at version ${String(entry.from)}; the current version is ${String(entry.to)}`,
  );
  if (args.check === true) {
    if (plan.length === 0 && stale.length === 0) {
      return {
        code: 0,
        output: "SQL modules are at their current versions.",
      };
    }
    return {
      code: 1,
      output: diffs.join("\n\n"),
      error: [
        ...behind,
        ...(stale.length > 0
          ? [
              `Out of date: ${stale.map((file) => display(config.root, file.path)).join(", ")}.`,
            ]
          : []),
        "Run `better-supabase sql upgrade`.",
      ].join("\n"),
    };
  }
  if (plan.length === 0 && stale.length === 0) {
    return {
      code: 0,
      output: "SQL modules are at their current versions.",
    };
  }
  const lines: string[] = [];
  const steps = plan.flatMap((entry) =>
    entry.steps
      .filter((step) => step.sql !== "")
      .map(
        (step) =>
          `-- ${entry.module}: version ${String(step.from)} to ${String(step.from + 1)}. ${step.description}\n${step.sql}`,
      ),
  );
  const dryRun = args["dry-run"] === true;
  if (steps.length > 0) {
    const path = `${migrationsDir(config)}/${migrationStamp(new Date())}_better_supabase_block_upgrade.sql`;
    const contents = `-- better-supabase sql upgrade: steps that run before the schema diff.\n\n${steps.join("\n\n")}\n`;
    if (dryRun) {
      lines.push(`Would write ${path}`);
    } else {
      await writeIfChanged(resolve(config.root, path), contents);
      lines.push(`Wrote ${path}`);
    }
  }
  for (const entry of plan) {
    lines.push(
      `${entry.module}: version ${String(entry.from)} to ${String(entry.to)}`,
      ...entry.steps.map((step) => `  ${step.description}`),
    );
  }
  lines.push(
    ...(await write(config, args, config.sql.moduleNames, sqlLayout)),
    "",
    `Then create a migration: ${migrationCommand(await readSupabaseToml(config.root), "better_supabase_module")}`,
  );
  return { code: 0, output: lines.join("\n") };
}

export async function runSql(
  config: ResolvedConfig,
  args: SqlArgs,
  paint: Paint = plain,
): Promise<CommandResult> {
  const [action, ...names] = args._;
  switch (action) {
    case "list": {
      const sqlLayout = await layout(config, args);
      const files = moduleFilePaths(Object.keys(SQL_MODULES), sqlLayout);
      const lines = Object.values(SQL_MODULES).map((module) => {
        const path = files.get(module.name);
        const installed =
          path !== undefined && existsSync(resolve(config.root, path));
        const tracked = config.sql.moduleNames.includes(module.name);
        const mark =
          path === undefined ? "◇" : installed ? (tracked ? "●" : "○") : " ";
        const requires =
          sqlLayout.permdock && module.permdockRequires
            ? module.permdockRequires
            : module.requires;
        const needs =
          requires.length > 0 ? ` (needs ${requires.join(", ")})` : "";
        return `${mark} ${module.name.padEnd(15)} ${module.description}${needs}`;
      });
      return {
        code: 0,
        output: `${lines.join("\n")}\n\n● installed and in sql.modules   ○ installed, not in sql.modules   ◇ custom mode (the app implements it)`,
      };
    }
    case "add": {
      if (names.length === 0) {
        return { code: 2, error: `Name at least one module.\n${USAGE}` };
      }
      const unknown = names.filter((name) => !(name in SQL_MODULES));
      if (unknown.length > 0) {
        return {
          code: 2,
          error: `Unknown module ${unknown.join(", ")}. Available: ${Object.keys(SQL_MODULES).join(", ")}`,
        };
      }
      const project = await readPermdock(config.root, config.permdock);
      const permdock = project ? permdockSource(project) : undefined;
      const hookModules = names.filter((name) => PERMDOCK_OWNED.has(name));
      if (permdock && hookModules.length > 0 && args.force !== true) {
        return {
          code: 1,
          error: [
            `${permdock} is present, so PermDock owns the access token hook and the memberships claim.`,
            `${hookModules.join(" and ")} would add a second source for them. Use \`permdock supabase hook generate\` instead,`,
            "or pass --force to write the modules anyway.",
          ].join("\n"),
        };
      }
      // Render with the modules sql.modules already lists, so the new ones
      // see them (a foreign key to the organizations table, plan quotas
      // over entitlements), but write only the named ones and what they need.
      const listed = [
        ...config.sql.moduleNames,
        ...names.filter((name) => !config.sql.moduleNames.includes(name)),
      ];
      const sqlLayout = await layoutFor(config, args, listed);
      const added = resolveModules(names, sqlLayout).map(
        (module) => module.name,
      );
      const lines = await write(config, args, listed, sqlLayout, added);
      const pulledIn = resolveModules(names, sqlLayout)
        .map((module) => module.name)
        .filter((name) => PERMDOCK_OWNED.has(name) && !names.includes(name));
      if (permdock && pulledIn.length > 0) {
        lines.push(
          "",
          `${pulledIn.join(" and ")} came along as a dependency: its memberships table backs has_organization_role() and has_entitlement().`,
          `PermDock's hook still owns the memberships claim, so don't call better_supabase.membership_claims from a hook.`,
          "List better_supabase.memberships as a PermDock membership source if both should agree.",
        );
      }
      const untracked = resolveModules(names, sqlLayout)
        .map((module) => module.name)
        .filter((name) => !config.sql.moduleNames.includes(name));
      if (untracked.length > 0) {
        lines.push(
          "",
          `Add them to your config so \`sql sync --check\` keeps them current:`,
          `  sql: { modules: [${[...config.sql.moduleNames, ...untracked].map((name) => `'${name}'`).join(", ")}] }`,
        );
      }
      if (args["dry-run"] !== true)
        lines.push(...(await unlistedModuleFiles(config, names, sqlLayout)));
      lines.push(
        "",
        `Then create a migration: ${migrationCommand(await readSupabaseToml(config.root), "better_supabase_module")}`,
      );
      return { code: 0, output: lines.join("\n") };
    }
    case "sync": {
      const topics = await topicPolicyFile(config);
      if (config.sql.moduleNames.length === 0 && topics === undefined) {
        return { code: 0, output: "sql.modules is empty; nothing to sync." };
      }
      if (args.check !== true) {
        const lines =
          config.sql.moduleNames.length === 0
            ? []
            : await write(
                config,
                args,
                config.sql.moduleNames,
                await layoutFor(config, args, config.sql.moduleNames),
              );
        if (topics !== undefined) {
          const shown = display(config.root, topics.path);
          if (args["dry-run"] === true)
            lines.push(`Would write ${shown} (topics)`);
          else {
            const wrote = await writeIfChanged(
              resolve(config.root, topics.path),
              topics.contents,
            );
            lines.push(`${wrote ? "Wrote" : "Unchanged"} ${shown} (topics)`);
          }
        }
        return { code: 0, output: lines.join("\n") };
      }
      const sqlLayout = await layoutFor(config, args, config.sql.moduleNames);
      const files: { path: string; contents: string; topics?: true }[] = [
        ...renderModules(config.sql.moduleNames, sqlLayout),
        ...(topics === undefined ? [] : [{ ...topics, topics: true as const }]),
      ];
      const stale: string[] = (
        await staleModuleTests(
          config,
          config.sql.moduleNames,
          sqlLayout,
          renderModules(config.sql.moduleNames, sqlLayout),
        )
      ).map((path) => display(config.root, path));
      const diffs: string[] = stale.map(
        (path) => `${path} is no longer written; \`sql sync\` removes it.`,
      );
      for (const file of files) {
        const current = await readFile(
          resolve(config.root, file.path),
          "utf8",
        ).catch(() => undefined);
        if (
          file.topics
            ? current !== file.contents
            : !sameModuleFile(current, file.contents)
        ) {
          const shown = display(config.root, file.path);
          stale.push(shown);
          diffs.push(fileDiff(shown, current, file.contents, paint));
        }
      }
      return stale.length === 0
        ? { code: 0, output: "SQL module files are up to date." }
        : {
            code: 1,
            output: diffs.join("\n\n"),
            error: `Out of date: ${stale.join(", ")}. Run \`better-supabase sql sync\`.`,
          };
    }
    case "upgrade":
      return upgrade(config, args, paint);
    case "data":
      return dataMigration(config, args);
    case "print": {
      const [name] = names;
      const module = name ? SQL_MODULES[name] : undefined;
      if (!module) {
        return {
          code: 2,
          error: `Name one module: ${Object.keys(SQL_MODULES).join(", ")}`,
        };
      }
      const body = moduleBody(
        module.name,
        await layout(config, args, [module.name]),
      );
      if (body === undefined) {
        return {
          code: 0,
          output: `-- sql.modules.${module.name} is in custom mode: the app writes these functions.\n${customContracts(
            [module.name],
            await layout(config, args, [module.name]),
          )
            .flatMap((contract) =>
              contract.functions.map(
                (fn) =>
                  `-- ${contract.schema}.${fn.name}(${contractSignature(fn, contract.idType)}) returns ${fn.returns.replaceAll("{id}", contract.idType)}`,
              ),
            )
            .join("\n")}`,
        };
      }
      return { code: 0, output: body };
    }
    case undefined:
      return { code: 2, error: `Name an action.\n${USAGE}` };
    default:
      return {
        code: 2,
        error: `Unknown sql action "${action}".\n${USAGE}`,
      };
  }
}

export const sqlCommand: AnyCommand = defineCliCommand({
  meta: {
    name: "sql",
    description:
      "Lists, adds, syncs, upgrades and prints SQL modules, and writes their data migration",
  },
  args: SQL_ARGS,
  run: (args, { config, io }) => runSql(config, args, painter(io.color)),
});
