import type { ResolvedConfig } from "../../config/index.ts";
import type { CliEnv } from "../env.ts";

/**
 * A credential and where it came from, as the user would write it:
 * `--db-url-stdin`, `$DATABASE_URL`, `source.dbUrl`.
 */
export interface Credential {
  readonly value: string;
  readonly from: string;
}

/** The first source that has a value, in order. */
function first(
  sources: readonly (readonly [from: string, value: string | undefined])[],
): Credential | undefined {
  for (const [from, value] of sources) {
    if (value !== undefined && value !== "") {
      return { value, from };
    }
  }

  return undefined;
}

/**
 * The Supabase access token: `source.accessToken`, then
 * `$SUPABASE_ACCESS_TOKEN`.
 */
export function accessToken(
  config: ResolvedConfig,
  env: CliEnv,
): Credential | undefined {
  return first([
    ["database.source.accessToken", config.source.accessToken],
    ["$SUPABASE_ACCESS_TOKEN", env.SUPABASE_ACCESS_TOKEN],
  ]);
}

/**
 * A connection string given by the user: `--db-url-stdin`, `source.dbUrl`,
 * `$DATABASE_URL`, then `$SUPABASE_DB_URL`.
 */
export function databaseUrlCredential(
  config: ResolvedConfig,
  env: CliEnv,
  fromStdin?: string,
): Credential | undefined {
  return first([
    ["--db-url-stdin", fromStdin],
    ["database.source.dbUrl", config.source.dbUrl],
    ["$DATABASE_URL", env.DATABASE_URL],
    ["$SUPABASE_DB_URL", env.SUPABASE_DB_URL],
  ]);
}
