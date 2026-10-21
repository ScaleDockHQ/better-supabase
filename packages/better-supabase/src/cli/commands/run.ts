import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliOptions } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type { CliLog } from "../core/log.ts";
import type { CliEnv } from "../env.ts";
import type { InheritedOptions } from "../exec.ts";

import { defineCliCommand } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import { commandMeta } from "../core/manifest.ts";
import { PROCESS_ENV } from "../env.ts";
import { spawnInherited } from "../exec.ts";
import { staleVariables } from "../stack-env.ts";
import { readStackEnv } from "./env.ts";

const ARGS = {
  prefix: {
    type: "string",
    description:
      'Browser variable prefix: next, vite, expo, nuxt, astro, sveltekit, a literal prefix, or "none". Defaults to env.prefix, then one detected from your framework',
    valueHint: "prefix",
  },
  "status-file": {
    type: "string",
    description: "Read `supabase status -o json` output from a file",
    valueHint: "file",
  },
} as const;

export type RunFlags = CliOptions<typeof ARGS>;

export type Spawn = (
  command: string,
  args: readonly string[],
  options: InheritedOptions,
) => Promise<number>;

export interface RunContext {
  /** Where the command runs. */
  readonly cwd: string;
  readonly env: CliEnv;
  readonly log: CliLog;
  readonly signal?: AbortSignal | undefined;
  readonly spawn?: Spawn;
}

/**
 * Runs a command with the stack's variables set. They override the shell, and
 * frameworks never override a variable that is already set, so they win over
 * `.env.local` too.
 */
export async function runWithStackEnv(
  config: ResolvedConfig,
  args: RunFlags,
  { cwd, env, log, signal, spawn = spawnInherited }: RunContext,
): Promise<CommandResult> {
  const [command, ...rest] = args._ ?? [];

  if (command === undefined) {
    throw new CliError(
      "usage",
      "Name the command to run after --, e.g. better-supabase run -- next dev.",
      { suggestion: "better-supabase run -- next dev" },
    );
  }

  const { values } = await readStackEnv(config, args, env, signal);
  const shell = env[PROCESS_ENV] ?? {};
  const stale = staleVariables(shell, values);

  for (const variable of stale) {
    log.warn(`${variable.message} run uses the stack's value.`);
  }

  const code = await spawn(command, rest, {
    cwd,
    env: { ...shell, ...values },
  });

  return {
    code,
    data: {
      command: [command, ...rest],
      keys: Object.keys(values),
      warnings: stale.map(({ message }) => message),
      stale: stale.map(({ variable, shell: from, stack }) => ({
        variable,
        shell: from,
        stack,
      })),
    },
  };
}

export const runCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("run"),
  args: ARGS,
  run: (args, { config, cwd, env, log, signal }) =>
    runWithStackEnv(config, args, { cwd, env, log, signal }),
});
