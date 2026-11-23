import { readdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { BlockSqlExtension, BlockSqlFile } from "../../sql/index.ts";
import type { CommandResult } from "../core/io.ts";
import type { SqlFlags } from "./args.ts";

import {
  moduleSchemaExtensions,
  splitStatements,
  SQL_MODULES,
} from "../../sql/index.ts";
import { changeLines } from "../core/files.ts";
import { migrationsDir } from "../sql-layout.ts";
import { readSupabaseConfig, sqlWorkflow } from "../supabase-config.ts";
import { hasMigrationSuffix } from "./migration-names.ts";
import { writeMigration } from "./migration-write.ts";
import { layoutFor } from "./providers.ts";
import { renderBlocksCached } from "./render-cache.ts";

/** The clock the migration stamps read, injected so tests pin it. */
export type Now = () => Date;

const EXTENSIONS_SUFFIX = "_better_supabase_extensions.sql";

const MIGRATION_EXTENSION =
  /^\s*create\s+extension\s+(?:if\s+not\s+exists\s+)?"?([a-z_][a-z0-9_]*)"?/gim;

async function unmigratedExtensions(
  config: ResolvedConfig,
  files: readonly BlockSqlFile[],
): Promise<{ dir: string; existing: string[]; missing: BlockSqlExtension[] }> {
  const dir = migrationsDir(config);

  const existing: string[] = await readdir(resolve(config.root, dir)).catch(
    () => [],
  );

  const created = new Set<string>();

  for (const name of existing) {
    if (!name.endsWith(".sql") || hasMigrationSuffix(name, DATA_SUFFIX)) {
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
  files: readonly BlockSqlFile[],
  dryRun: boolean,
  now: Now,
): Promise<string[]> {
  const { dir, missing } = await unmigratedExtensions(config, files);

  if (missing.length === 0) {
    return [];
  }

  const contents = `-- better-supabase sql: the extensions of ${missing.map((extension) => extension.name).join(", ")}, created before the schema migration that needs them.\n\n${missing.map((extension) => extension.statement).join("\n")}\n`;

  const { applied } = await writeMigration(config, {
    dir,
    now: () => new Date(now().getTime() - 1000),
    suffix: EXTENSIONS_SUFFIX,
    contents,
    regenerate: "better-supabase upgrade",
    flags: { "dry-run": dryRun },
  });

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
  "The better-supabase-data files hold rows and settings a schema diff skips: after the schema migration, run `better-supabase add --adopt`.";

const DATA_SUFFIX = "_better_supabase_module_data.sql";

const LOCK_TIMEOUT = "set lock_timeout = '5s';";

/** A statement without comments and extra whitespace, the key it is compared by. */
const normalized = (statement: string): string =>
  statement.replaceAll(/\s+/g, " ").trim().replace(/;$/, "");

/** The statements of a migration, comments and the lock timeout left out. */
const migrationStatements = (sql: string): Set<string> =>
  new Set(
    splitStatements(sql)
      .map((statement) => normalized(statement.text))
      .filter((text) => text !== normalized(LOCK_TIMEOUT)),
  );

/**
 * Whether an upgrade step since the version an earlier data migration recorded
 * for the file's instance asks for its data file to run again.
 */
function rerunsData(
  file: BlockSqlFile,
  migrated: ReadonlySet<string>,
): boolean {
  const row = new RegExp(
    `\\binsert into better_supabase\\.blocks \\(name, (?:block, )?version, mode\\) values \\('${file.instance ?? file.module}', (?:'[^']*', )?(\\d+),`,
    "u",
  );

  const versions = [...migrated].flatMap((statement) => {
    const match = row.exec(statement);

    return match ? [Number(match[1])] : [];
  });

  if (versions.length === 0) {
    return false;
  }

  const adopted = Math.max(...versions);

  return (SQL_MODULES[file.module]?.upgrades ?? []).some(
    (step) => step.data === true && step.from >= adopted,
  );
}

/** One module's data statements that no data migration holds yet. */
interface PendingData {
  readonly module: string;
  readonly statements: readonly string[];
}

/**
 * Compares the data files against the statements of the data migrations already
 * in the migrations folder, so a statement is never written twice and a changed
 * statement is written once more.
 */
function pendingData(
  files: readonly BlockSqlFile[],
  migrated: ReadonlySet<string>,
): PendingData[] {
  const seen = new Set(migrated);

  return files.flatMap((file): PendingData[] => {
    const rerun = rerunsData(file, migrated);

    const statements = splitStatements(file.contents)
      .map((statement) => statement.text)
      .filter((text) => {
        const key = normalized(text);

        if (
          key === normalized(LOCK_TIMEOUT) ||
          (seen.has(key) && !(rerun && migrated.has(key)))
        ) {
          return false;
        }

        seen.add(key);

        return true;
      });

    return statements.length === 0 ? [] : [{ module: file.module, statements }];
  });
}

/**
 * Writes the data files of `blocks` into one migration, meant to run after the
 * schema migration that creates their tables. It carries only the statements no
 * earlier data migration holds, so a sync after a block upgrade writes the
 * change and nothing else. Every statement is idempotent either way.
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
    sqlWorkflow(config, await readSupabaseConfig(config.root)) === "migrations"
  ) {
    return {
      code: 0,
      output:
        "database.sql.workflow is 'migrations', so `better-supabase upgrade` already writes the rows into the module migration; nothing to write.",
      data: { wrote: false },
    };
  }

  const rendered = await renderBlocksCached(
    config,
    config.blockNames,
    await layoutFor(config, args, config.blockNames),
  );

  const { missing } = await unmigratedExtensions(config, rendered);

  if (missing.length > 0) {
    return {
      code: 1,
      error: [
        `No migration before the data migration creates ${missing.map((extension) => extension.name).join(", ")}, and the schema migration needs ${missing.length === 1 ? "it" : "them"} while it applies.`,
        "Run `better-supabase upgrade` to write the extensions migration, then create the schema migration again after it.",
      ].join("\n"),
    };
  }

  const files = rendered.filter((file) => file.kind === "data");
  const dir = migrationsDir(config);

  const existing: string[] = await readdir(resolve(config.root, dir)).catch(
    () => [],
  );

  const dataMigrations = existing
    .toSorted()
    .filter((name) => hasMigrationSuffix(name, DATA_SUFFIX));

  const latest = dataMigrations.at(-1);
  const migrated = new Set<string>();

  for (const name of dataMigrations) {
    for (const statement of migrationStatements(
      await readFile(resolve(config.root, dir, name), "utf-8"),
    )) {
      migrated.add(statement);
    }
  }

  const pending = pendingData(files, migrated);

  if (pending.length === 0) {
    return {
      code: 0,
      output:
        latest === undefined
          ? "The blocks have no rows or settings to write."
          : `${dir}/${latest} already has these rows; nothing to write.`,
      data: {
        ...(latest === undefined ? {} : { file: `${dir}/${latest}` }),
        wrote: false,
      },
    };
  }

  const count = pending.reduce(
    (total, part) => total + part.statements.length,
    0,
  );

  if (args.check === true) {
    return {
      code: 1,
      error: `${String(count)} data statement${count === 1 ? "" : "s"} of ${pending.map((part) => part.module).join(", ")} ${count === 1 ? "is" : "are"} in no data migration. Run \`better-supabase add --adopt\` after the schema migration.`,
      data: { wrote: false, pending: count },
    };
  }

  const contents = `-- better-supabase add --adopt: the rows and settings of ${pending.map((part) => part.module).join(", ")} that no data migration holds yet.\n\n${LOCK_TIMEOUT}\n\n${pending.map((part) => `-- ${part.module}\n${part.statements.map((statement) => `${statement};`).join("\n\n")}`).join("\n\n")}\n`;

  const { path, applied } = await writeMigration(config, {
    dir,
    now,
    suffix: DATA_SUFFIX,
    contents,
    regenerate: "better-supabase add --adopt",
    flags: { "dry-run": args["dry-run"] },
  });

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
