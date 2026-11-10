import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliOptions } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type { CliEnv } from "../env.ts";

import {
  accessMatrix,
  accessMatrixTests,
  readSecurityCatalog,
  verifyCatalog,
  verifyQuery,
} from "../../create/lite/index.ts";
import { databaseUrl, stdinDatabaseUrl } from "../config.ts";
import { defineCliCommand } from "../core/command.ts";
import { CliError, errorText } from "../core/errors.ts";
import { commandMeta } from "../core/manifest.ts";
import { connect } from "../db.ts";
import { DB_URL_STDIN_ARG, STACK_ARG } from "./source-args.ts";

const ARGS = {
  "write-tests": {
    type: "boolean",
    description:
      "Write the access matrix as one pgTAP file per persona (ADR 0105) to --dir",
  },
  dir: {
    type: "string",
    description:
      "Folder of the pgTAP files (default supabase/tests/database), relative to the project",
    valueHint: "path",
  },
} as const;

export type VerifyFlags = CliOptions<
  typeof ARGS & typeof DB_URL_STDIN_ARG & typeof STACK_ARG
>;

export interface VerifyDeps {
  readonly open: typeof connect;
}

/**
 * Reads the security facts of the database (row level security, grants,
 * policies, `search_path` of definer functions), reports what `verifyCatalog`
 * finds, and with `--write-tests` writes the access matrix as pgTAP files.
 * Exits 1 on an error finding. It only reads the database.
 */
export async function runVerify(
  config: ResolvedConfig,
  args: VerifyFlags,
  env: CliEnv,
  deps: Partial<VerifyDeps> = {},
  dbUrl?: string,
): Promise<CommandResult> {
  const open = deps.open ?? connect;

  const url = await databaseUrl(
    config,
    env,
    dbUrl,
    args.stack ?? env.BETTER_SUPABASE_STACK,
  );

  const { client, close } = await open(url);

  try {
    const { rows } = await client.query(verifyQuery(config.schemas));

    const catalog = readSecurityCatalog(rows);
    const issues = verifyCatalog(catalog);
    const errors = issues.filter((entry) => entry.severity === "error");
    const written: string[] = [];

    if (args["write-tests"] === true) {
      const directory = args.dir ?? "supabase/tests/database";

      for (const file of accessMatrixTests(accessMatrix(catalog), {
        directory,
      })) {
        const target = join(config.root, file.path);
        await mkdir(dirname(target), { recursive: true });
        await writeFile(target, file.contents);
        written.push(file.path);
      }
    }

    const lines = [
      ...issues.map(
        (entry) => `${entry.severity} ${entry.code}: ${entry.message}`,
      ),
      issues.length === 0
        ? `No findings in ${String(catalog.tables.length)} tables and ${String(catalog.functions.length)} functions.`
        : `${String(errors.length)} error${errors.length === 1 ? "" : "s"}, ${String(issues.length - errors.length)} other finding${issues.length - errors.length === 1 ? "" : "s"}.`,
      ...(written.length === 0
        ? []
        : [
            `Wrote ${String(written.length)} pgTAP file${written.length === 1 ? "" : "s"}: ${written.join(", ")}. Memberships belong to your app: add the member personas' setup SQL before you rely on them.`,
          ]),
    ];

    const data = {
      tables: catalog.tables.length,
      functions: catalog.functions.length,
      issues: issues.map(({ code, severity, table, message }) => ({
        code,
        severity,
        table,
        message,
      })),
      written,
    };

    return errors.length > 0
      ? { code: 1, errorCode: "failed", error: lines.join("\n"), data }
      : { code: 0, output: lines.join("\n"), data };
  } catch (cause) {
    if (cause instanceof CliError) {
      throw cause;
    }

    return {
      code: 1,
      errorCode: "failed",
      error: `db verify failed: ${errorText(cause)}`,
    };
  } finally {
    await close();
  }
}

export const dbVerifyCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("db verify"),
  args: { ...ARGS, ...DB_URL_STDIN_ARG, ...STACK_ARG },
  run: async (args, { config, env, io }) =>
    runVerify(
      config,
      args,
      env,
      { open: connect },
      await stdinDatabaseUrl(args["db-url-stdin"], io),
    ),
});
