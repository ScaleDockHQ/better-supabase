import { existsSync, readdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import type { CliEnv } from "../env.ts";

import { CliError } from "../core/errors.ts";

export type PgTool = "pg_dump" | "psql";

const PLATFORM: Readonly<Record<string, string>> = {
  "darwin-arm64": "darwin-arm64",
  "darwin-x64": "darwin-x64",
  "linux-arm64": "linux-arm64",
  "linux-x64": "linux-x64",
};

function compareVersions(a: string, b: string): number {
  return a.localeCompare(b, undefined, { numeric: true });
}

/**
 * The Postgres client tools the native stack engine downloads
 * (`~/.supabase/cache/stack/slim-services/postgres/<version>/<platform>/bin`),
 * the newest first. They match the server the stack runs, which `pg_dump`
 * requires. `$BETTER_SUPABASE_PG_BIN` names another folder and wins.
 */
function pgBinFolders(env: CliEnv, home: string = homedir()): string[] {
  const named = env.BETTER_SUPABASE_PG_BIN;

  if (named !== undefined && named !== "") {
    return [named];
  }

  const platform = PLATFORM[`${process.platform}-${process.arch}`];

  const root = join(
    home,
    ".supabase",
    "cache",
    "stack",
    "slim-services",
    "postgres",
  );

  if (platform === undefined || !existsSync(root)) {
    return [];
  }

  return readdirSync(root)
    .toSorted(compareVersions)
    .toReversed()
    .map((version) => join(root, version, platform, "bin"))
    .filter((folder) => existsSync(folder));
}

/**
 * The path of a client tool, or the bare name for the PATH when the cache has
 * none.
 */
export function pgTool(tool: PgTool, env: CliEnv, home?: string): string {
  const folder = pgBinFolders(env, home).find((candidate) =>
    existsSync(join(candidate, tool)),
  );

  return folder === undefined ? tool : join(folder, tool);
}

/** Throws unless the tool answers `--version`. */
export function missingTool(tool: PgTool, output: string): CliError {
  return new CliError(
    "dependency_missing",
    `baseline needs ${tool}, and it could not run: ${output}. Start a stack with --runtime native once (it downloads the Postgres tools), or put the Postgres client tools on the PATH or in $BETTER_SUPABASE_PG_BIN.`,
  );
}
