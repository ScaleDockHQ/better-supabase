import { readdir, readFile, rm, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { ConsentRequest } from "../core/agent.ts";
import type { AnyCommand, CliOptions } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type { CliEnv } from "../env.ts";
import type { ExecResult } from "../exec.ts";

import { defineCliCommand } from "../core/command.ts";
import { CliError, errorText } from "../core/errors.ts";
import { commandMeta } from "../core/manifest.ts";
import { supabaseCli } from "../exec.ts";
import { requirePgDelta } from "../pg-delta-only.ts";
import { migrationsDir } from "../sql-layout.ts";
import { migrationStamp, stampAfter } from "../sql/migration-names.ts";
import { readSupabaseConfig, sqlWorkflow } from "../supabase-config.ts";

const EXTENSIONS = "better_supabase_extensions";

const ARGS = {
  name: {
    type: "string",
    description: "Name of the new baseline migration (default init)",
    valueHint: "name",
  },
  keep: {
    type: "string",
    description:
      "Comma-separated names of data migrations to carry over, such as reference_data,billing_plans; the files of each name merge in order",
    valueHint: "names",
  },
  schemas: {
    type: "string",
    description:
      "Comma-separated schemas the baseline covers (default: the config's schemas)",
    valueHint: "list",
  },
  "dry-run": {
    type: "boolean",
    description: "Print what would be removed and kept, and change nothing",
  },
} as const;

export type SquashFlags = CliOptions<typeof ARGS>;

export interface SquashDeps {
  /** Runs the Supabase CLI; injected so tests need no CLI. */
  readonly supabase: (
    args: readonly string[],
    cwd: string,
    env: CliEnv,
  ) => Promise<ExecResult>;
  readonly now: () => Date;
  readonly requireConsent: (request: ConsentRequest) => void;
}

const DEFAULT_DEPS: SquashDeps = {
  supabase: (args, cwd, env) => supabaseCli(args, cwd, env),
  now: () => new Date(),
  requireConsent: () => {},
};

/** The migration's name without its `<stamp>_` prefix and `.sql` suffix. */
const migrationName = (file: string): string =>
  file.replace(/^\d{14}_?/, "").replace(/\.sql$/, "");

const NO_TRANSACTION = /^--\s*pg-delta:\s*transaction=false\s*$/m;

/**
 * Whether `file` is the migration `wanted` names: the same name, with the
 * content hash `migrationFile` adds, or with the `_1`, `_2` suffix pg-delta
 * gives each file of a multi-file migration.
 */
const isMigrationNamed = (file: string, wanted: string): boolean => {
  const name = migrationName(file).replace(/_(?:v2-)?[0-9a-f]{8}$/, "");

  return name === wanted || new RegExp(`^${wanted}_\\d+$`).test(name);
};

/**
 * The parts of one migration in order (`_2` before `_10`), joined into one
 * text. A `-- pg-delta: transaction=false` marker only holds for the whole
 * file, so parts that disagree about it can't be joined.
 */
function joinParts(wanted: string, parts: readonly string[]): string {
  const outside = parts.filter((part) => NO_TRANSACTION.test(part)).length;

  if (outside !== 0 && outside !== parts.length) {
    throw new CliError(
      "usage",
      `${wanted} has files with and without \`-- pg-delta: transaction=false\`, and squash would join them into one file. Make them agree, or leave ${wanted} out of --keep.`,
      { flag: "--keep" },
    );
  }

  return outside === 0
    ? parts.join("\n")
    : `-- pg-delta: transaction=false\n${parts
        .map((part) => part.replace(NO_TRANSACTION, "").trim())
        .join("\n")}`;
}

/** The names `--keep` lists, trimmed and without empties. */
function keepNames(flag: string | undefined): string[] {
  return (flag ?? "")
    .split(",")
    .map((name) => name.trim())
    .filter((name) => name.length > 0);
}

/**
 * Replaces the migrations with one baseline of the declarative schema files
 * (`supabase db schema declarative sync --no-apply`), and carries over the
 * module extensions migration and the data migrations `--keep` names, which a
 * schema diff never writes. The old files are restored when the baseline fails.
 * Run it for a deliberate squash that a database reset follows.
 */
export async function runSquash(
  config: ResolvedConfig,
  args: SquashFlags,
  env: CliEnv,
  deps: Partial<SquashDeps> = {},
): Promise<CommandResult> {
  const { supabase, now, requireConsent } = { ...DEFAULT_DEPS, ...deps };
  const dir = migrationsDir(config);
  requirePgDelta(
    "db squash (it plans the baseline with `supabase db schema declarative sync --strict-coverage`)",
    sqlWorkflow(config, await readSupabaseConfig(config.root)),
  );

  const folder = resolve(config.root, dir);
  const name = args.name ?? "init";
  const keep = keepNames(args.keep);
  const schemas = args.schemas ?? config.schemas.join(",");

  if (!/^[a-z0-9_]+$/i.test(name)) {
    throw new CliError(
      "invalid_value",
      `--name takes letters, digits and underscores, got "${name}".`,
      { flag: "--name" },
    );
  }

  const files = (await readdir(folder).catch((): string[] => []))
    .filter((file) => file.endsWith(".sql"))
    .toSorted();

  if (files.length === 0) {
    throw new CliError("not_found", `${dir} has no migrations to squash.`);
  }

  const texts = new Map<string, string>();

  for (const file of files) {
    texts.set(file, await readFile(resolve(folder, file), "utf-8"));
  }

  const carried = new Map<string, string>();

  for (const wanted of [EXTENSIONS, ...keep]) {
    const parts = files
      .filter((file) => isMigrationNamed(file, wanted))
      .toSorted((a, b) => a.localeCompare(b, "en", { numeric: true }))
      .map((file) => texts.get(file) ?? "");

    if (parts.length === 0) {
      if (wanted === EXTENSIONS) {
        continue;
      }

      throw new CliError(
        "not_found",
        `--keep names ${wanted}, but ${dir} has no migration with that name.`,
        { flag: "--keep" },
      );
    }

    carried.set(wanted, joinParts(wanted, parts));
  }

  const summary = {
    removed: files.length,
    kept: [...carried.keys()],
    baseline: name,
    schemas,
  };

  if (args["dry-run"] === true) {
    return {
      code: 0,
      output: `Would replace ${String(files.length)} migrations in ${dir} with ${name} and carry over ${carried.size === 0 ? "nothing" : [...carried.keys()].join(", ")}.`,
      data: { ...summary, dryRun: true },
    };
  }

  requireConsent({
    effect: "overwrite",
    detail: `db squash deletes the ${String(files.length)} migrations in ${dir} and writes one baseline; reset the database afterwards`,
  });

  const restore = async (): Promise<void> => {
    for (const file of await readdir(folder).catch((): string[] => [])) {
      if (file.endsWith(".sql")) {
        await rm(resolve(folder, file));
      }
    }

    for (const [file, text] of texts) {
      await writeFile(resolve(folder, file), text);
    }
  };

  try {
    for (const file of files) {
      await rm(resolve(folder, file));
    }

    // The baseline gets a stamp from the CLI's own clock, so the extensions go
    // a few seconds before it and the data after it.
    const start = now();
    const extensions = carried.get(EXTENSIONS);

    if (extensions !== undefined) {
      await writeFile(
        resolve(
          folder,
          `${migrationStamp(new Date(start.getTime() - 2000))}_${EXTENSIONS}.sql`,
        ),
        extensions,
      );
    }

    const synced = await supabase(
      [
        "db",
        "schema",
        "declarative",
        "sync",
        "--no-apply",
        "--strict-coverage",
        "--name",
        name,
        "-s",
        schemas,
      ],
      config.root,
      env,
    );

    if (synced.code !== 0) {
      throw new CliError(
        "supabase_cli_failed",
        `supabase db schema declarative sync failed (${String(synced.code)}): ${synced.stderr.trim() || synced.stdout.trim()}`,
      );
    }

    for (const [wanted, text] of carried) {
      if (wanted === EXTENSIONS) {
        continue;
      }

      // After every migration in the folder, the baseline and the data files
      // written so far included, so no two share a stamp.
      const stamp = stampAfter(await readdir(folder), start);

      await writeFile(resolve(folder, `${stamp}_${wanted}.sql`), text);
    }
  } catch (cause) {
    await restore();

    if (cause instanceof CliError) {
      throw cause;
    }

    return {
      code: 1,
      errorCode: "failed",
      error: `db squash failed and restored the migrations: ${errorText(cause)}`,
    };
  }

  return {
    code: 0,
    output: `Replaced ${String(files.length)} migrations in ${dir} with ${name}${carried.size === 0 ? "" : ` and carried over ${[...carried.keys()].join(", ")}`}. Reset the database to apply it.`,
    data: { ...summary, dryRun: false },
  };
}

export const dbSquashCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("db squash"),
  args: ARGS,
  run: (args, { config, env, requireConsent }) =>
    runSquash(config, args, env, { requireConsent }),
});
