import type { CliEnv } from "./env.ts";
import type { ExecOptions } from "./exec.ts";

import { CliError } from "./core/errors.ts";
import { supabaseCli } from "./exec.ts";

export interface StackStatus {
  readonly [key: string]: unknown;
}

export type StackStatusResult =
  | { readonly ok: true; readonly status: StackStatus }
  | { readonly ok: false; readonly code: number };

/** Parses the JSON object `supabase status` prints after any progress lines. */
export function parseStackStatus(stdout: string): StackStatus | undefined {
  const start = stdout.indexOf("{");

  if (start === -1) {
    return undefined;
  }

  const parsed: unknown = JSON.parse(stdout.slice(start));

  return typeof parsed === "object" && parsed !== null && !Array.isArray(parsed)
    ? { ...parsed }
    : undefined;
}

/**
 * The local stack's URLs and keys from `supabase status`. The stack engine
 * (`[experimental] stack`) rejects `-o json` and prints the same keys with
 * `--env`. `stack` asks for a named stack (`supabase status --stack <name>`).
 */
export async function readStackStatus(
  root: string,
  env: CliEnv,
  options: ExecOptions & { readonly stack?: string } = {},
): Promise<StackStatusResult> {
  const named = options.stack === undefined ? [] : ["--stack", options.stack];

  let result = await supabaseCli(
    ["status", ...named, "-o", "json"],
    root,
    env,
    options,
  );

  if (result.code !== 0) {
    const engine = await supabaseCli(
      ["status", ...named, "--env", "--output-format", "json"],
      root,
      env,
      options,
    );

    if (engine.code === 0) {
      result = engine;
    }
  }

  if (result.code !== 0) {
    return { ok: false, code: result.code };
  }

  const status = parseStackStatus(result.stdout);

  if (!status) {
    throw new CliError(
      "supabase_cli_failed",
      "supabase status printed no JSON.",
    );
  }

  return { ok: true, status };
}
