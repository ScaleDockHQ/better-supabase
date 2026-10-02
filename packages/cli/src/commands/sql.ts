import type { ResolvedConfig } from "better-supabase/config";

import {
  type KitLayout,
  type KitPermdock,
  kitLayout,
  renderKit,
  resolveModules,
  sameKitFile,
  SQL_MODULES,
} from "better-supabase/sql";
import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ParsedArgs } from "../args.ts";
import type { CommandResult } from "../io.ts";

import { flagBool, flagString } from "../args.ts";
import { display, writeIfChanged } from "../io.ts";
import { entitlementsMode, permdockConfig, readPermdock } from "../permdock.ts";
import { compiledReadSets } from "../read-sets.ts";
import { readSupabaseToml, schemaPaths } from "../supabase-toml.ts";

export const SQL_HELP = `Usage: better-supabase sql <list|add|sync|print> [modules...]

  list                 Modules and whether they are installed
  add <module...>      Write the modules (and what they need) to sql.dir
  sync [--check]       Rewrite the modules in sql.kit; --check fails when a file is stale
  print <module>       Print a module's SQL, e.g. to paste into a migration

Options
  --tests-dir <dir>    Where the pgtap module goes. Defaults to sql.testsDir.
  --dry-run            Show what would be written
  --force              Write tenant even though a permdock.config.ts is present`;

/** Modules that fill a claim PermDock's hook also writes (`memberships`). */
const PERMDOCK_OWNED: ReadonlySet<string> = new Set(["tenant"]);

/** PermDock's helpers for the `entitlements` module; throws for a scope the manifest lacks. */
async function permdockFor(
  config: ResolvedConfig,
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
      throw new TypeError(mode.problem);
    default: {
      const unreachable: never = mode;
      return unreachable;
    }
  }
}

async function layout(
  config: ResolvedConfig,
  args: ParsedArgs,
): Promise<KitLayout> {
  return kitLayout(
    config,
    flagString(args.flags, "tests-dir"),
    [],
    await permdockFor(config),
  );
}

/** The layout, with `config.readSets` compiled when `names` includes `read-sets`. */
async function layoutFor(
  config: ResolvedConfig,
  args: ParsedArgs,
  names: readonly string[],
): Promise<KitLayout> {
  const permdock = await permdockFor(config);
  const needsReadSets = resolveModules(names, {
    ...(permdock ? { permdock } : {}),
  }).some((module) => module.name === "read-sets");
  return kitLayout(
    config,
    flagString(args.flags, "tests-dir"),
    needsReadSets ? await compiledReadSets(config) : [],
    permdock,
  );
}

async function write(
  config: ResolvedConfig,
  args: ParsedArgs,
  names: readonly string[],
  kit: KitLayout,
): Promise<string[]> {
  const lines: string[] = [];
  const dryRun = flagBool(args.flags, "dry-run");
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

/** A note when `schema_paths` is set and misses kit files, which `supabase db diff` would then skip. */
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
  args: ParsedArgs,
): Promise<CommandResult> {
  const [action, ...names] = args.rest;
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
        return { code: 2, error: `Name at least one module.\n\n${SQL_HELP}` };
      }
      const unknown = names.filter((name) => !(name in SQL_MODULES));
      if (unknown.length > 0) {
        return {
          code: 2,
          error: `Unknown module ${unknown.join(", ")}. Available: ${Object.keys(SQL_MODULES).join(", ")}`,
        };
      }
      const permdock = permdockConfig(config.root);
      const hookModules = names.filter((name) => PERMDOCK_OWNED.has(name));
      if (
        permdock &&
        hookModules.length > 0 &&
        !flagBool(args.flags, "force")
      ) {
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
      if (!flagBool(args.flags, "dry-run"))
        lines.push(...(await unlistedKitFiles(config, names, kit)));
      lines.push(
        "",
        "Then create a migration: supabase db diff -f better_supabase_kit",
      );
      return { code: 0, output: lines.join("\n") };
    }
    case "sync": {
      if (config.sql.kit.length === 0) {
        return { code: 0, output: "sql.kit is empty; nothing to sync." };
      }
      if (!flagBool(args.flags, "check")) {
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
      for (const file of renderKit(
        config.sql.kit,
        await layoutFor(config, args, config.sql.kit),
      )) {
        const current = await readFile(
          resolve(config.root, file.path),
          "utf8",
        ).catch(() => undefined);
        if (!sameKitFile(current, file.contents))
          stale.push(display(config.root, file.path));
      }
      return stale.length === 0
        ? { code: 0, output: "SQL kit files are up to date." }
        : {
            code: 1,
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
          ? module.render(config.claims, await layout(config, args))
          : module.sql,
      };
    }
    case undefined:
      return { code: 2, error: SQL_HELP };
    default:
      return {
        code: 2,
        error: `Unknown sql action "${action}".\n\n${SQL_HELP}`,
      };
  }
}
