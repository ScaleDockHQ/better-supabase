import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { ConsentRequest } from "../core/agent.ts";
import type { AnyCommand, CliOptions } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type { CliEnv } from "../env.ts";

import { databaseUrl, stdinDatabaseUrl } from "../config.ts";
import { databaseHost, isLocalDatabaseUrl } from "../core/agent.ts";
import { defineCliCommand } from "../core/command.ts";
import { CliError, errorText } from "../core/errors.ts";
import { display } from "../core/io.ts";
import { commandMeta } from "../core/manifest.ts";
import { connect } from "../db.ts";
import { supabaseCli } from "../exec.ts";
import {
  type InStackDiffOptions,
  inStackDiff,
  isShadowFailure,
  MIGRATION_HEADER,
  migrationFiles,
  migrationVersion,
} from "../in-stack-diff.ts";
import {
  declarativeSchemasDir,
  readSupabaseToml,
  schemaPaths,
  sqlWorkflow,
} from "../supabase-toml.ts";
import { DB_URL_STDIN_ARG, STACK_ARG } from "./source-args.ts";

const ARGS = {
  file: {
    type: "positional",
    required: true,
    variadic: true,
    description: "SQL files, run in the order given",
  },
  "single-transaction": {
    type: "boolean",
    description: "Wrap every file in one transaction, so a failure keeps none",
  },
} as const;

type DbQueryFlags = CliOptions<
  typeof ARGS & typeof DB_URL_STDIN_ARG & typeof STACK_ARG
> & { readonly _: readonly string[] };

/** Runs each file as one multi-statement script and reports the files it ran. */
export async function runDbQuery(
  config: ResolvedConfig,
  args: DbQueryFlags,
  env: CliEnv,
  open: typeof connect = connect,
  dbUrl?: string,
  requireConsent: (request: ConsentRequest) => void = () => {},
): Promise<CommandResult> {
  const files = [...args._];

  if (files.length === 0) {
    throw new CliError("usage", "Pass at least one SQL file.", {
      flag: "file",
    });
  }

  const scripts: { name: string; sql: string }[] = [];

  for (const file of files) {
    const path = resolve(config.root, file);

    try {
      scripts.push({
        name: display(config.root, path),
        sql: await readFile(path, "utf-8"),
      });
    } catch (cause) {
      throw new CliError(
        "invalid_input",
        `Could not read ${file}: ${errorText(cause)}.`,
      );
    }
  }

  const url = await databaseUrl(
    config,
    env,
    dbUrl,
    args.stack ?? env.BSB_STACK,
  );

  if (!isLocalDatabaseUrl(url)) {
    requireConsent({
      effect: "database-write",
      detail: `db query runs ${String(files.length)} file(s) against ${databaseHost(url)}`,
    });
  }

  const single = args["single-transaction"] === true;
  const { client, close } = await open(url);
  const ran: string[] = [];

  try {
    if (single) {
      await client.query("begin");
    }

    for (const script of scripts) {
      try {
        await client.query(script.sql);
        ran.push(script.name);
      } catch (cause) {
        if (single) {
          await client.query("rollback");
        }

        return {
          code: 1,
          errorCode: "failed",
          error: `${script.name}: ${errorText(cause)}${single ? " (nothing was kept)" : ""}`,
          data: { ran, failed: script.name },
        };
      }
    }

    if (single) {
      await client.query("commit");
    }
  } finally {
    await close();
  }

  return {
    code: 0,
    output: ran.map((name) => `Ran ${name}`).join("\n"),
    data: { ran, singleTransaction: single },
  };
}

export const dbQueryCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("db query"),
  args: { ...ARGS, ...DB_URL_STDIN_ARG, ...STACK_ARG },
  run: async (args, { config, env, io, log, requireConsent }) => {
    const dbUrl = await stdinDatabaseUrl(args["db-url-stdin"], io);

    return log.progress("Running the SQL files", () =>
      runDbQuery(config, args, env, connect, dbUrl, requireConsent),
    );
  },
});

const DIFF_ARGS = {
  file: {
    type: "string",
    alias: "f",
    description:
      "Save the diff as supabase/migrations/<timestamp>_<name>.sql instead of printing it",
    valueHint: "name",
  },
  "in-stack": {
    type: "boolean",
    description:
      "Diff inside the running stack with pg-delta, without the Supabase CLI's shadow database",
  },
} as const;

type DbDiffFlags = CliOptions<typeof DIFF_ARGS & typeof STACK_ARG>;

export interface DbDiffDeps {
  readonly supabase: (
    args: readonly string[],
    root: string,
    env: CliEnv,
  ) => Promise<{
    readonly code: number;
    readonly stdout: string;
    readonly stderr: string;
  }>;
  readonly inStackDiff: (options: InStackDiffOptions) => Promise<string>;
  readonly now: () => Date;
  readonly log: (line: string) => void;
}

const DEFAULT_DIFF_DEPS: DbDiffDeps = {
  supabase: (args, root, env) => supabaseCli(args, root, env),
  inStackDiff,
  now: () => new Date(),
  log: () => {},
};

/**
 * The Supabase CLI's diff for the workflow. pg-delta's `declarative sync`
 * always writes a migration, so printing a diff under pg-delta runs in the
 * stack.
 */
function cliDiffCommand(
  workflow: "pg-delta" | "migra",
  name: string | undefined,
): readonly string[] | undefined {
  switch (workflow) {
    case "pg-delta": {
      return name === undefined
        ? undefined
        : ["db", "schema", "declarative", "sync", "--no-apply", "-f", name];
    }

    case "migra": {
      return name === undefined ? ["db", "diff"] : ["db", "diff", "-f", name];
    }

    default: {
      const unreachable: never = workflow;

      return unreachable;
    }
  }
}

/**
 * Turns the declarative schema into a migration with the Supabase CLI's command
 * for the project's workflow. When the CLI can't start its shadow database (no
 * shared memory segment left), or with `--in-stack`, it diffs inside the
 * running stack instead.
 */
export async function runDbDiff(
  config: ResolvedConfig,
  args: DbDiffFlags,
  env: CliEnv,
  deps: DbDiffDeps = DEFAULT_DIFF_DEPS,
): Promise<CommandResult> {
  const name = args.file;

  if (name !== undefined && !/^[\w-]+$/u.test(name)) {
    throw new CliError(
      "invalid_value",
      `--file "${name}" must be letters, digits, dashes or underscores.`,
      { flag: "--file" },
    );
  }

  const toml = await readSupabaseToml(config.root);
  const workflow = sqlWorkflow(config, toml);

  if (workflow === "migrations") {
    throw new CliError(
      "usage",
      "db diff turns declarative schema files into a migration, and this project writes migrations directly (sql.workflow = migrations).",
    );
  }

  let fellBack = false;
  const command = cliDiffCommand(workflow, name);

  if (args["in-stack"] !== true && command !== undefined) {
    const result = await deps.supabase(command, config.root, env);

    if (result.code === 0) {
      return {
        code: 0,
        output: result.stdout.trim() || "No schema changes.",
        data: { engine: "supabase", command: ["supabase", ...command] },
      };
    }

    const output = `${result.stderr}\n${result.stdout}`;

    if (!isShadowFailure(output)) {
      return {
        code: 1,
        errorCode: "supabase_cli_failed",
        error: `supabase ${command.join(" ")} failed: ${output.trim()}`,
        data: { engine: "supabase", command: ["supabase", ...command] },
      };
    }

    fellBack = true;
    deps.log(
      "The Supabase CLI could not start its shadow database (no shared memory segment left), so db diff diffs inside the running stack. better-supabase stack prune frees segments.",
    );
  }

  const url = await databaseUrl(
    config,
    env,
    undefined,
    args.stack ?? env.BSB_STACK,
  );

  if (!isLocalDatabaseUrl(url)) {
    throw new CliError(
      "usage",
      `db diff --in-stack works on a local stack, and the database is ${databaseHost(url)}.`,
    );
  }

  const dir = toml?.dir ?? "supabase";

  const sql = await deps.inStackDiff({
    url,
    root: config.root,
    env,
    files: (await schemaPaths(config.root, toml, workflow)).files,
    schemasDir: declarativeSchemasDir(toml, workflow),
    migrations: await migrationFiles(config.root, dir),
    log: deps.log,
  });

  const data = { engine: "in-stack", fellBack, changes: sql !== "" };

  if (sql === "") {
    return { code: 0, output: "No schema changes.", data };
  }

  if (name === undefined) {
    return { code: 0, output: sql, data };
  }

  const path = join(
    config.root,
    dir,
    "migrations",
    `${migrationVersion(deps.now())}_${name}.sql`,
  );

  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${MIGRATION_HEADER}\n${sql}\n`);

  return {
    code: 0,
    output: `Wrote ${display(config.root, path)}. Review it before you apply it.`,
    data: { ...data, file: display(config.root, path) },
  };
}

export const dbDiffCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("db diff"),
  args: { ...DIFF_ARGS, ...STACK_ARG },
  run: (args, { config, env, log }) =>
    log.progress("Diffing the schema files", () =>
      runDbDiff(config, args, env, { ...DEFAULT_DIFF_DEPS, log: log.info }),
    ),
});
