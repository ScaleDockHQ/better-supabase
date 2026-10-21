import { readdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { ModuleExtension, ModuleFile } from "../../sql/index.ts";
import type { CommandResult } from "../core/io.ts";
import type { SqlFlags } from "./args.ts";

import { moduleSchemaExtensions, renderModules } from "../../sql/index.ts";
import { applyPlan, changeLines } from "../core/files.ts";
import { migrationsDir, sqlPlan } from "../sql-layout.ts";
import { readSupabaseToml, sqlWorkflow } from "../supabase-toml.ts";
import { layoutFor } from "./providers.ts";

/** The clock the migration stamps read, injected so tests pin it. */
export type Now = () => Date;

/** `YYYYMMDDHHMMSS` in UTC, the Supabase CLI's migration prefix. */
export const migrationStamp = (now: Date): string =>
  now.toISOString().replaceAll(/[-:T]/g, "").slice(0, 14);

/**
 * A stamp for `now`, or one second after the newest migration when that one has
 * the same stamp or a later one: the Supabase CLI keys migrations by stamp, and
 * the data has to run after the schema.
 */
export function stampAfter(migrations: readonly string[], now: Date): string {
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

const EXTENSIONS_SUFFIX = "_better_supabase_extensions.sql";

const MIGRATION_EXTENSION =
  /^\s*create\s+extension\s+(?:if\s+not\s+exists\s+)?"?([a-z_][a-z0-9_]*)"?/gim;

async function unmigratedExtensions(
  config: ResolvedConfig,
  files: readonly ModuleFile[],
): Promise<{ dir: string; existing: string[]; missing: ModuleExtension[] }> {
  const dir = migrationsDir(config);

  const existing: string[] = await readdir(resolve(config.root, dir)).catch(
    () => [],
  );

  const created = new Set<string>();

  for (const name of existing) {
    if (!name.endsWith(".sql") || name.endsWith(DATA_SUFFIX)) {
      continue;
    }

    const text = await readFile(resolve(config.root, dir, name), "utf-8");

    for (const match of text.matchAll(MIGRATION_EXTENSION)) {
      created.add(match[1]!.toLowerCase());
    }
  }

  return {
    dir,
    existing,
    missing: moduleSchemaExtensions(files).filter(
      (extension) => !created.has(extension.name),
    ),
  };
}

export async function writeExtensionsMigration(
  config: ResolvedConfig,
  files: readonly ModuleFile[],
  dryRun: boolean,
  now: Now,
): Promise<string[]> {
  const { dir, existing, missing } = await unmigratedExtensions(config, files);

  if (missing.length === 0) {
    return [];
  }

  const path = `${dir}/${stampAfter(existing, new Date(now().getTime() - 1000))}${EXTENSIONS_SUFFIX}`;

  const applied = await applyPlan(
    sqlPlan(config, {
      regenerate: "better-supabase sql sync",
      files: [
        {
          path,
          contents: `-- better-supabase sql: the extensions of ${missing.map((extension) => extension.name).join(", ")}, created before the schema migration that needs them.\n\n${missing.map((extension) => extension.statement).join("\n")}\n`,
        },
      ],
    }),
    { "dry-run": dryRun },
  );

  return [
    ...changeLines(applied),
    ...(dryRun
      ? []
      : [
          "It creates the extensions the module schemas need, so create the schema migration after it.",
        ]),
  ];
}

export const DATA_NEXT =
  "The better-supabase-data files hold rows and settings a schema diff skips: after the schema migration, run `better-supabase sql data`.";

const DATA_SUFFIX = "_better_supabase_module_data.sql";

/**
 * Writes the data files of `blocks` into one migration, meant to run after the
 * schema migration that creates their tables. Every statement is idempotent, so
 * the migration carries all of them, not only the changes.
 */
export async function dataMigration(
  config: ResolvedConfig,
  args: SqlFlags,
  now: Now,
): Promise<CommandResult> {
  if (config.blockNames.length === 0) {
    return {
      code: 0,
      output: "blocks is empty; nothing to write.",
      data: { wrote: false },
    };
  }

  if (
    sqlWorkflow(config, await readSupabaseToml(config.root)) === "migrations"
  ) {
    return {
      code: 0,
      output:
        "sql.workflow is 'migrations', so `better-supabase sql sync` already writes the rows into the module migration; nothing to write.",
      data: { wrote: false },
    };
  }

  const rendered = renderModules(
    config.blockNames,
    await layoutFor(config, args, config.blockNames),
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
    (await readFile(resolve(config.root, dir, latest), "utf-8")) === contents
  ) {
    return {
      code: 0,
      output: `${dir}/${latest} already has these rows; nothing to write.`,
      data: { file: `${dir}/${latest}`, wrote: false },
    };
  }

  const path = `${dir}/${stampAfter(existing, now())}${DATA_SUFFIX}`;

  const applied = await applyPlan(
    sqlPlan(config, {
      regenerate: "better-supabase sql data",
      files: [{ path, contents }],
    }),
    { "dry-run": args["dry-run"] },
  );

  return {
    code: 0,
    output: changeLines(applied).join("\n"),
    data: {
      file: path,
      wrote: applied.mode === "write",
      files: applied.changes,
    },
  };
}
