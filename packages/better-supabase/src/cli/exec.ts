import { channel } from "node:diagnostics_channel";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { x } from "tinyexec";

import type { CliEnv } from "./env.ts";

import { CliError, errorText } from "./core/errors.ts";
import { EXEC_CHANNEL, type ExecEvent } from "./core/trace.ts";
import { PROCESS_ENV } from "./env.ts";
import { findUp } from "./supabase-toml.ts";

export interface ExecResult {
  readonly code: number;
  readonly stdout: string;
  readonly stderr: string;
}

export interface ExecOptions {
  /** Stops the process when aborted, so Ctrl-C ends a running `supabase` call. */
  readonly signal?: AbortSignal | undefined;
}

const NOT_FOUND = 127;

const execChannel = channel(EXEC_CHANNEL);

async function exec(
  command: string,
  args: readonly string[],
  cwd: string,
  env: CliEnv,
  options: ExecOptions,
): Promise<ExecResult> {
  const childEnv = env[PROCESS_ENV];
  const start = performance.now();

  const publish = (result: ExecResult): ExecResult => {
    if (execChannel.hasSubscribers) {
      execChannel.publish({
        command,
        args,
        cwd,
        code: result.code,
        milliseconds: Math.round(performance.now() - start),
      } satisfies ExecEvent);
    }

    return result;
  };

  try {
    const result = await x(command, [...args], {
      nodeOptions: {
        cwd,
        stdio: ["ignore", "pipe", "pipe"],
        ...(childEnv ? { env: { ...childEnv } } : {}),
      },
      ...(options.signal ? { signal: options.signal } : {}),
      throwOnError: false,
    });

    return publish({
      code: result.exitCode ?? 1,
      stdout: result.stdout,
      stderr: result.stderr,
    });
  } catch (error) {
    return publish({
      code: NOT_FOUND,
      stdout: "",
      stderr: errorText(error),
    });
  }
}

/** `node_modules/.bin/supabase` in `cwd` or a parent, when the project installs the CLI. */
function localSupabase(cwd: string): string | undefined {
  const bin = join(
    "node_modules",
    ".bin",
    process.platform === "win32" ? "supabase.cmd" : "supabase",
  );

  const dir = findUp(cwd, (candidate) => existsSync(join(candidate, bin)));

  return dir === undefined ? undefined : join(dir, bin);
}

/**
 * Runs the Supabase CLI: `$SUPABASE_BIN`, then the project's
 * `node_modules/.bin/supabase`, then `supabase` on the PATH. It never
 * downloads one; without any it fails with `supabase_cli_missing`.
 */
export async function supabaseCli(
  args: readonly string[],
  cwd: string,
  env: CliEnv,
  options: ExecOptions = {},
): Promise<ExecResult> {
  const command = env.SUPABASE_BIN ?? localSupabase(cwd) ?? "supabase";
  const result = await exec(command, args, cwd, env, options);

  if (result.code === NOT_FOUND && options.signal?.aborted !== true) {
    throw new CliError(
      "supabase_cli_missing",
      `Could not run the Supabase CLI (${command}): ${result.stderr || "not found"}. Install it in the project (pnpm add -D supabase) or set $SUPABASE_BIN.`,
      { suggestion: "pnpm add -D supabase" },
    );
  }

  return result;
}
