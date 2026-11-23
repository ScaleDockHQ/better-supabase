import { mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliOptions } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";

import { defineCliCommand } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import { commandMeta } from "../core/manifest.ts";
import { rowsDir } from "../rows/dir.ts";
import { planRows } from "../rows/plan.ts";
import { DeclaredRowsError } from "../rows/read.ts";
import { migrationsDir } from "../sql-layout.ts";

const ARGS = {
  check: {
    type: "boolean",
    description:
      "Change nothing and exit 1 when a rows file has no data migration with its current hash",
  },
  "dry-run": {
    type: "boolean",
    description: "Print the migrations it would write, and write nothing",
  },
} as const;

export type RowsFlags = CliOptions<typeof ARGS>;

async function readSql(folder: string): Promise<ReadonlyMap<string, string>> {
  const names = (await readdir(folder).catch((): string[] => []))
    .filter((file) => file.endsWith(".sql"))
    .toSorted();

  return new Map(
    await Promise.all(
      names.map(
        async (file) =>
          [file, await readFile(resolve(folder, file), "utf-8")] as const,
      ),
    ),
  );
}

/**
 * Writes a data migration for each rows file that changed since its last
 * migration (ADR 1198).
 */
async function runRows(
  config: ResolvedConfig,
  args: RowsFlags,
  now: () => Date = () => new Date(),
): Promise<CommandResult> {
  const rows = rowsDir(config);
  const migrations = migrationsDir(config);

  const files = new Map(
    [...(await readSql(resolve(config.root, rows)))].map(([file, text]) => [
      file.replace(/\.sql$/, ""),
      text,
    ]),
  );

  if (files.size === 0) {
    return {
      code: 0,
      output: `${rows} has no rows files, so there is nothing to sync.`,
      data: { migrations: [], current: [], review: [] },
    };
  }

  const plan = await planRows(
    files,
    await readSql(resolve(config.root, migrations)),
    now(),
  ).catch((error: unknown) => {
    if (error instanceof DeclaredRowsError) {
      throw new CliError("invalid_input", error.message);
    }

    throw error;
  });

  const data = {
    migrations: plan.migrations.map((each) => each.file),
    current: plan.current,
    review: plan.review,
  };

  const pending = plan.migrations.map(
    (each) => `${each.source}.sql needs ${migrations}/${each.file}`,
  );

  if (args.check === true) {
    return plan.migrations.length === 0
      ? {
          code: 0,
          output: `Every rows file in ${rows} has its data migration.`,
          data,
        }
      : {
          code: 1,
          errorCode: "check_failed",
          error: `${pending.join("; ")}. Run \`better-supabase db rows\`.`,
          data,
        };
  }

  if (args["dry-run"] !== true) {
    await mkdir(resolve(config.root, migrations), { recursive: true });

    for (const each of plan.migrations) {
      await writeFile(resolve(config.root, migrations, each.file), each.text);
    }
  }

  const written = plan.migrations.map((each) => `${migrations}/${each.file}`);

  return {
    code: 0,
    output: [
      written.length === 0
        ? "Every rows file already has its data migration."
        : `${args["dry-run"] === true ? "Would write" : "Wrote"} ${written.join(", ")}.`,
      ...plan.review.map((line) => `review: ${line}`),
    ].join("\n"),
    data,
  };
}

export const dbRowsCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("db rows"),
  args: ARGS,
  run: (args, { config }) => runRows(config, args),
});
