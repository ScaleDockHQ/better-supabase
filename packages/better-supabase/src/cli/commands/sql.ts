import { existsSync } from "node:fs";
import { readdir, readFile } from "node:fs/promises";
import { dirname, join, relative, resolve, sep } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs } from "../command.ts";
import type { CommandResult } from "../io.ts";

import {
  contractSignature,
  customContracts,
  type InstalledKitModule,
  type KitAccessPermdock,
  type KitFile,
  kitFileVersion,
  type KitLayout,
  type KitPermdock,
  kitFilePaths,
  kitLayout,
  kitPermissionKeys,
  moduleBody,
  renderKit,
  resolveModules,
  sameKitFile,
  SQL_MODULES,
  upgradePlan,
} from "../../sql/index.ts";
import { defineCliCommand } from "../command.ts";
import { fileDiff } from "../diff.ts";
import { display, writeIfChanged } from "../io.ts";
import {
  accessPermdockMode,
  entitlementsMode,
  kitKeyProblems,
  permdockSource,
  readPermdock,
} from "../permdock.ts";
import { compiledReadSets } from "../read-sets.ts";
import { type Paint, painter, plain } from "../style.ts";
import {
  declarativeSchemasDir,
  migrationCommand,
  readSupabaseToml,
  schemaPaths,
} from "../supabase-toml.ts";

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
): Promise<KitPermdock | undefined> {
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
 * `access`, an invalid mode throws, and so does a kit permission key the
 * catalog doesn't mark `rowConditions: false`. `sql list` (no `names`)
 * doesn't render, so it doesn't throw.
 */
async function accessPermdockFor(
  config: ResolvedConfig,
  names?: readonly string[],
): Promise<KitAccessPermdock | undefined> {
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
      const problems = kitKeyProblems(
        project,
        kitPermissionKeys(config.kits, names),
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

async function layout(
  config: ResolvedConfig,
  args: SqlArgs,
  names?: readonly string[],
): Promise<KitLayout> {
  return {
    ...kitLayout(
      config,
      args["tests-dir"],
      [],
      await permdockFor(config, names),
      await accessPermdockFor(config, names),
    ),
    schemasDir: declarativeSchemasDir(await readSupabaseToml(config.root)),
  };
}

/** The layout, with `config.readSets` compiled when `names` includes `read-sets`. */
async function layoutFor(
  config: ResolvedConfig,
  args: SqlArgs,
  names: readonly string[],
): Promise<KitLayout> {
  const permdock = await permdockFor(config, names);
  const needsReadSets = resolveModules(names, {
    ...(permdock ? { permdock } : {}),
  }).some((module) => module.name === "read-sets");
  return {
    ...kitLayout(
      config,
      args["tests-dir"],
      needsReadSets ? await compiledReadSets(config) : [],
      permdock,
      await accessPermdockFor(config, names),
    ),
    schemasDir: declarativeSchemasDir(await readSupabaseToml(config.root)),
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
  const newest = migrations
    .map((name) => /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})_/.exec(name))
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
  kit: KitLayout,
): Promise<string[]> {
  const lines: string[] = [];
  const dryRun = args["dry-run"] === true;
  let data = false;
  for (const file of renderKit(names, kit)) {
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
  if (data) lines.push("", DATA_NEXT);
  return lines;
}

const DATA_NEXT =
  "The better-supabase-data files hold rows and settings a schema diff skips: after the schema migration, run `better-supabase sql data`.";
const DATA_SUFFIX = "_better_supabase_kit_data.sql";

/**
 * Writes the data files of `sql.kit` into one migration, meant to run after
 * the schema migration that creates their tables. Every statement is
 * idempotent, so the migration carries all of them, not only the changes.
 */
async function dataMigration(
  config: ResolvedConfig,
  args: SqlArgs,
): Promise<CommandResult> {
  if (config.sql.kit.length === 0) {
    return { code: 0, output: "sql.kit is empty; nothing to write." };
  }
  const files = renderKit(
    config.sql.kit,
    await layoutFor(config, args, config.sql.kit),
  ).filter((file) => file.kind === "data");
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

/** A note when migra's `schema_paths` is set and misses kit files, which `supabase db diff` would then skip. */
async function unlistedKitFiles(
  config: ResolvedConfig,
  names: readonly string[],
  kit: KitLayout,
): Promise<string[]> {
  const order = await schemaPaths(
    config.root,
    await readSupabaseToml(config.root),
  );
  if (!order.configured) return [];
  const unlisted = new Set(order.unlisted);
  const listed = new Set(order.files.filter((path) => !unlisted.has(path)));
  const dir = `${config.sql.dir.replace(/\/$/, "")}/`;
  const missing = renderKit(names, kit)
    .filter((file) => file.kind !== "data")
    .map((file) => file.path)
    .filter((path) => path.startsWith(dir) && !listed.has(path));
  if (missing.length === 0) return [];
  return [
    "",
    "supabase/config.toml sets [db.migrations] schema_paths, and no entry matches these files, so `supabase db diff` skips them.",
    "Add them before the schemas that call their functions:",
    ...missing.map(
      (path) =>
        `  "./${path.startsWith("supabase/") ? path.slice("supabase/".length) : path}",`,
    ),
  ];
}

/**
 * Rewrites the kit files of modules behind the current version, and writes
 * their upgrade steps (renames, backfills) as a migration that runs before
 * the one the schema diff creates.
 */
async function upgrade(
  config: ResolvedConfig,
  args: SqlArgs,
  paint: Paint,
): Promise<CommandResult> {
  if (config.sql.kit.length === 0) {
    return { code: 0, output: "sql.kit is empty; nothing to upgrade." };
  }
  const kit = await layoutFor(config, args, config.sql.kit);
  const files = renderKit(config.sql.kit, kit);
  const installed: InstalledKitModule[] = [];
  const stale: KitFile[] = [];
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
      version: kitFileVersion(current)?.version ?? 1,
    });
    if (!sameKitFile(current, file.contents)) {
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
  const plan = upgradePlan(installed, kit);
  const behind = plan.map(
    (entry) =>
      `${entry.module} is at version ${String(entry.from)}; the current version is ${String(entry.to)}`,
  );
  if (args.check === true) {
    if (plan.length === 0 && stale.length === 0) {
      return {
        code: 0,
        output: "SQL kit modules are at their current versions.",
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
      output: "SQL kit modules are at their current versions.",
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
    const path = `${migrationsDir(config)}/${migrationStamp(new Date())}_better_supabase_kit_upgrade.sql`;
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
    ...(await write(config, args, config.sql.kit, kit)),
    "",
    `Then create a migration: ${migrationCommand(await readSupabaseToml(config.root), "better_supabase_kit")}`,
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
      const kit = await layout(config, args);
      const files = kitFilePaths(Object.keys(SQL_MODULES), kit);
      const lines = Object.values(SQL_MODULES).map((module) => {
        const path = files.get(module.name);
        const installed =
          path !== undefined && existsSync(resolve(config.root, path));
        const tracked = config.sql.kit.includes(module.name);
        const mark =
          path === undefined ? "◇" : installed ? (tracked ? "●" : "○") : " ";
        const requires =
          kit.permdock && module.permdockRequires
            ? module.permdockRequires
            : module.requires;
        const needs =
          requires.length > 0 ? ` (needs ${requires.join(", ")})` : "";
        return `${mark} ${module.name.padEnd(15)} ${module.description}${needs}`;
      });
      return {
        code: 0,
        output: `${lines.join("\n")}\n\n● installed and in sql.kit   ○ installed, not in sql.kit   ◇ custom mode (the app implements it)`,
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
      const kit = await layoutFor(config, args, names);
      const lines = await write(config, args, names, kit);
      const pulledIn = resolveModules(names, kit)
        .map((module) => module.name)
        .filter((name) => PERMDOCK_OWNED.has(name) && !names.includes(name));
      if (permdock && pulledIn.length > 0) {
        lines.push(
          "",
          `${pulledIn.join(" and ")} came along as a dependency: its memberships table backs has_org_role() and has_entitlement().`,
          `PermDock's hook still owns the memberships claim, so don't call better_supabase.membership_claims from a hook.`,
          "List better_supabase.memberships as a PermDock membership source if both should agree.",
        );
      }
      const untracked = resolveModules(names, kit)
        .map((module) => module.name)
        .filter((name) => !config.sql.kit.includes(name));
      if (untracked.length > 0) {
        lines.push(
          "",
          `Add them to your config so \`sql sync --check\` keeps them current:`,
          `  sql: { kit: [${[...config.sql.kit, ...untracked].map((name) => `'${name}'`).join(", ")}] }`,
        );
      }
      if (args["dry-run"] !== true)
        lines.push(...(await unlistedKitFiles(config, names, kit)));
      lines.push(
        "",
        `Then create a migration: ${migrationCommand(await readSupabaseToml(config.root), "better_supabase_kit")}`,
      );
      return { code: 0, output: lines.join("\n") };
    }
    case "sync": {
      if (config.sql.kit.length === 0) {
        return { code: 0, output: "sql.kit is empty; nothing to sync." };
      }
      if (args.check !== true) {
        return {
          code: 0,
          output: (
            await write(
              config,
              args,
              config.sql.kit,
              await layoutFor(config, args, config.sql.kit),
            )
          ).join("\n"),
        };
      }
      const stale: string[] = [];
      const diffs: string[] = [];
      for (const file of renderKit(
        config.sql.kit,
        await layoutFor(config, args, config.sql.kit),
      )) {
        const current = await readFile(
          resolve(config.root, file.path),
          "utf8",
        ).catch(() => undefined);
        if (!sameKitFile(current, file.contents)) {
          const shown = display(config.root, file.path);
          stale.push(shown);
          diffs.push(fileDiff(shown, current, file.contents, paint));
        }
      }
      return stale.length === 0
        ? { code: 0, output: "SQL kit files are up to date." }
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
          output: `-- kits.${module.name} is in custom mode: the app writes these functions.\n${customContracts(
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
      "Lists, adds, syncs, upgrades and prints SQL kit modules, and writes their data migration",
  },
  args: SQL_ARGS,
  run: (args, { config, io }) => runSql(config, args, painter(io.color)),
});
