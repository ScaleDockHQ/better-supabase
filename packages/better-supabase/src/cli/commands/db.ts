import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

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
import { DB_URL_STDIN_ARG } from "./source-args.ts";

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

type DbQueryFlags = CliOptions<typeof ARGS & typeof DB_URL_STDIN_ARG> & {
  readonly _: readonly string[];
};

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

  const url = await databaseUrl(config, env, dbUrl);

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
  args: { ...ARGS, ...DB_URL_STDIN_ARG },
  run: async (args, { config, env, io, log, requireConsent }) => {
    const dbUrl = await stdinDatabaseUrl(args["db-url-stdin"], io);

    return log.progress("Running the SQL files", () =>
      runDbQuery(config, args, env, connect, dbUrl, requireConsent),
    );
  },
});
