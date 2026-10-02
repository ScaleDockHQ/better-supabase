import { createEnv } from "@t3-oss/env-core";
import * as v from "valibot";

import { CliError } from "./errors.ts";

/** The environment variables the CLI reads, validated once per run. */
export interface CliEnv {
  /** Postgres connection string for gen, introspect, doctor and seed. */
  readonly DATABASE_URL?: string | undefined;
  /** Personal access token for reading a hosted project. */
  readonly SUPABASE_ACCESS_TOKEN?: string | undefined;
  /** Management API base URL; defaults to https://api.supabase.com. */
  readonly SUPABASE_API_URL?: string | undefined;
  /** The Supabase CLI to run instead of `supabase` on the PATH. */
  readonly SUPABASE_BIN?: string | undefined;
  /** Home directory for `skills install --global`. */
  readonly HOME?: string | undefined;
  /** Set in CI; prompts never run there. */
  readonly CI?: string | undefined;
}

const optionalString = v.optional(v.string());
const optionalUrl = v.optional(
  v.pipe(v.string(), v.url("must be a URL, e.g. postgresql://user@host/db")),
);

/** Parses the variables the CLI reads; an invalid value is a `env_invalid` usage error. */
export function parseEnv(
  env: Readonly<Record<string, string | undefined>>,
): CliEnv {
  return createEnv({
    server: {
      DATABASE_URL: optionalUrl,
      SUPABASE_ACCESS_TOKEN: optionalString,
      SUPABASE_API_URL: optionalUrl,
      SUPABASE_BIN: optionalString,
      HOME: optionalString,
      CI: optionalString,
    },
    runtimeEnv: env,
    isServer: true,
    emptyStringAsUndefined: true,
    onValidationError: (issues) => {
      const lines = issues.map(
        (issue) =>
          `${issue.path?.map((key) => String(typeof key === "object" ? key.key : key)).join(".") ?? "env"}: ${issue.message}`,
      );
      throw new CliError(
        "env_invalid",
        `Invalid environment variable:\n${lines.map((line) => `  ${line}`).join("\n")}`,
        { issues: lines },
      );
    },
  });
}
