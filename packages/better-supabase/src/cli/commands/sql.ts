import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs } from "../command.ts";
import type { CommandResult } from "../io.ts";

import {
  type KitLayout,
  type KitPermdock,
  kitLayout,
  renderKit,
  resolveModules,
  sameKitFile,
  SQL_MODULES,
} from "../../sql/index.ts";
import { defineCliCommand } from "../command.ts";
import { fileDiff } from "../diff.ts";
import { display, writeIfChanged } from "../io.ts";
import { entitlementsMode, permdockSource, readPermdock } from "../permdock.ts";
import { compiledReadSets } from "../read-sets.ts";
import { type Paint, painter, plain } from "../style.ts";
import {
  migrationCommand,
  readSupabaseToml,
  schemaPaths,
} from "../supabase-toml.ts";

const SQL_ARGS = {
  action: {
    type: "positional",
    required: false,
    description:
      "list (modules and whether they are installed), add <module...>, sync or print <module>",
  },
  check: {
    type: "boolean",
    description: "With sync: fail when a file is stale",
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

async function layout(
  config: ResolvedConfig,
  args: SqlArgs,
  names?: readonly string[],
): Promise<KitLayout> {
  return kitLayout(
    config,
    args["tests-dir"],
    [],
    await permdockFor(config, names),
  );
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
  return kitLayout(
    config,
    args["tests-dir"],
    needsReadSets ? await compiledReadSets(config) : [],
    permdock,
  );
}

async function write(
  config: ResolvedConfig,
  args: SqlArgs,
  names: readonly string[],
  kit: KitLayout,
): Promise<string[]> {
  const lines: string[] = [];
  const dryRun = args["dry-run"] === true;
  for (const file of renderKit(names, kit)) {
    const path = resolve(config.root, file.path);
    const shown = display(config.root, file.path);
    if (dryRun) {
      lines.push(`Would write ${shown} (${file.module})`);
      continue;
    }
    const wrote = await writeIfChanged(path, file.contents);
    lines.push(`${wrote ? "Wrote" : "Unchanged"} ${shown} (${file.module})`);
  }
  return lines;
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

export async function runSql(
  config: ResolvedConfig,
  args: SqlArgs,
  paint: Paint = plain,
): Promise<CommandResult> {
  const [action, ...names] = args._;
  switch (action) {
    case "list": {
      const kit = await layout(config, args);
      const files = new Map(
        renderKit(Object.keys(SQL_MODULES), kit).map((file) => [
          file.module,
          file.path,
        ]),
      );
      const lines = Object.values(SQL_MODULES).map((module) => {
        const path = files.get(module.name)!;
        const installed = existsSync(resolve(config.root, path));
        const tracked = config.sql.kit.includes(module.name);
        const mark = installed ? (tracked ? "●" : "○") : " ";
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
        output: `${lines.join("\n")}\n\n● installed and in sql.kit   ○ installed, not in sql.kit`,
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
    case "print": {
      const [name] = names;
      const module = name ? SQL_MODULES[name] : undefined;
      if (!module) {
        return {
          code: 2,
          error: `Name one module: ${Object.keys(SQL_MODULES).join(", ")}`,
        };
      }
      return {
        code: 0,
        output: module.render
          ? module.render(
              config.claims,
              await layout(config, args, [module.name]),
            )
          : module.sql,
      };
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
    description: "Lists, adds, syncs and prints SQL kit modules",
  },
  args: SQL_ARGS,
  run: (args, { config, io }) => runSql(config, args, painter(io.color)),
});
