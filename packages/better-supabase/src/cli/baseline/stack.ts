import type { CliEnv } from "../env.ts";
import type { ExecResult, RunProcess } from "../exec.ts";
import type { PgTool } from "./pg-tools.ts";

import { CliError } from "../core/errors.ts";
import { PROCESS_ENV } from "../env.ts";
import { runProcess, supabaseCli } from "../exec.ts";
import { parseStackStatus } from "../stack-status.ts";
import { missingTool, pgTool } from "./pg-tools.ts";

/**
 * What `baseline` needs from the outside: the CLI, the Postgres tools and a
 * log.
 */
export interface BaselineContext {
  readonly root: string;
  readonly env: CliEnv;
  readonly log: (line: string) => void;
  readonly supabase: (
    args: readonly string[],
    cwd: string,
    env: CliEnv,
  ) => Promise<ExecResult>;
  readonly run: RunProcess;
}

export function baselineContext(
  root: string,
  env: CliEnv,
  log: (line: string) => void = () => {},
): BaselineContext {
  return {
    root,
    env,
    log,
    supabase: (args, cwd, cliEnv) => supabaseCli(args, cwd, cliEnv),
    run: runProcess,
  };
}

/** The same environment with more variables for the processes the CLI starts. */
function withEnv(env: CliEnv, extra: Readonly<Record<string, string>>): CliEnv {
  return { ...env, [PROCESS_ENV]: { ...env[PROCESS_ENV], ...extra } };
}

/**
 * The switches that start a stack with an empty database: the Supabase CLI
 * reads `[db.migrations] enabled` and `[db.seed] enabled` from the environment
 * too, so no config file changes.
 */
export const EMPTY_START_ENV: Readonly<Record<string, string>> = {
  SUPABASE_DB_MIGRATIONS_ENABLED: "false",
  SUPABASE_DB_SEED_ENABLED: "false",
};

export const MIGRATIONS_ONLY_ENV: Readonly<Record<string, string>> = {
  SUPABASE_DB_SEED_ENABLED: "false",
};

export interface StackInfo {
  readonly id: string;
  readonly dbUrl: string;
  readonly apiUrl: string | undefined;
  readonly serviceKey: string | undefined;
}

export interface ScratchStack extends StackInfo {
  readonly destroy: () => Promise<void>;
}

function text(value: unknown): string | undefined {
  return typeof value === "string" && value !== "" ? value : undefined;
}

/**
 * The ids, URLs and keys of a running stack (`--stack <name>`, or this
 * checkout's).
 */
export async function stackInfo(
  ctx: BaselineContext,
  name?: string,
): Promise<StackInfo> {
  const named = name === undefined ? [] : ["--stack", name];

  const result = await ctx.supabase(
    ["status", ...named, "--output-format", "json"],
    ctx.root,
    ctx.env,
  );

  const status =
    result.code === 0 ? parseStackStatus(result.stdout) : undefined;

  const values: Record<string, unknown> =
    typeof status?.["env"] === "object" && status["env"] !== null
      ? { ...status["env"] }
      : {};

  const identity: Record<string, unknown> =
    typeof status?.["identity"] === "object" && status["identity"] !== null
      ? { ...status["identity"] }
      : {};

  const dbUrl = text(values["DB_URL"]);
  const id = text(identity["id"]);

  if (dbUrl === undefined || id === undefined) {
    throw new CliError(
      "supabase_cli_failed",
      `supabase status found no running stack${name === undefined ? "" : ` named ${name}`}: ${(result.stderr || result.stdout).trim()}`,
    );
  }

  return {
    id,
    dbUrl,
    apiUrl: text(values["API_URL"]),
    serviceKey: text(values["SERVICE_ROLE_KEY"]) ?? text(values["SECRET_KEY"]),
  };
}

/** Starts a throwaway native stack; `destroy` removes it with its data. */
export async function startScratch(
  ctx: BaselineContext,
  name: string,
  extra: Readonly<Record<string, string>>,
): Promise<ScratchStack> {
  const env = withEnv(ctx.env, extra);

  const started = await ctx.supabase(
    [
      "start",
      "--stack",
      name,
      "--runtime",
      "native",
      "--exclude",
      "studio,functions,analytics,mail",
      "--yes",
    ],
    ctx.root,
    env,
  );

  if (started.code !== 0) {
    throw new CliError(
      "supabase_cli_failed",
      `supabase start --stack ${name} failed: ${(started.stderr || started.stdout).trim()}`,
    );
  }

  const info = await stackInfo(ctx, name);

  return {
    ...info,
    destroy: async () => {
      await ctx.supabase(
        ["stack", "destroy", "--stack", info.id, "--yes"],
        ctx.root,
        ctx.env,
      );
    },
  };
}

/** Runs a Postgres client tool and throws with its output on a failure. */
export async function runPg(
  ctx: BaselineContext,
  tool: PgTool,
  args: readonly string[],
): Promise<string> {
  const result = await ctx.run(pgTool(tool, ctx.env), args, ctx.root, ctx.env);

  if (result.code === 127) {
    throw missingTool(tool, result.stderr);
  }

  if (result.code !== 0) {
    throw new CliError(
      "failed",
      `${tool} failed: ${(result.stderr || result.stdout).trim().split("\n").slice(-3).join(" ")}`,
    );
  }

  return result.stdout;
}

/**
 * The same database as the stack's superuser, which can write the platform
 * schemas' tables.
 */
function superuserUrl(url: string): string {
  const parsed = new URL(url);
  parsed.username = "supabase_admin";

  return parsed.toString();
}

/** Runs SQL files in order inside one transaction, so a failure keeps none. */
export async function getSql(
  ctx: BaselineContext,
  url: string,
  files: readonly string[],
): Promise<void> {
  await runPg(ctx, "psql", [
    "--no-psqlrc",
    "--quiet",
    "--single-transaction",
    "-v",
    "ON_ERROR_STOP=1",
    ...files.flatMap((file) => ["-f", file]),
    superuserUrl(url),
  ]);
}

/** Collects the milliseconds each step took. */
export function stepTimer(): {
  readonly timings: Record<string, number>;
  readonly step: <T>(label: string, run: () => Promise<T>) => Promise<T>;
} {
  const timings: Record<string, number> = {};

  return {
    timings,
    step: async (label, run) => {
      const start = performance.now();

      try {
        return await run();
      } finally {
        timings[label] = Math.round(
          (timings[label] ?? 0) + performance.now() - start,
        );
      }
    },
  };
}

export async function cliVersion(ctx: BaselineContext): Promise<string> {
  const result = await ctx.supabase(["--version"], ctx.root, ctx.env);

  return result.stdout.trim().split("\n").at(-1)?.trim() ?? "unknown";
}
