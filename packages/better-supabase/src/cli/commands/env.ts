import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs, CliOptions } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type { CliEnv } from "../env.ts";

import { defineCliCommand } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import {
  applyPlan,
  changeLines,
  type FilePlan,
  insideRoot,
  PLAN_ARGS,
  planResult,
} from "../core/files.ts";
import { display, readIfExists } from "../core/io.ts";
import { commandMeta } from "../core/manifest.ts";
import { detectProject, publicPrefix } from "../project/detect.ts";
import { prefixFromFlag, stackEnvValues } from "../stack-env.ts";
import {
  parseStackStatus,
  readStackStatus,
  type StackStatus,
} from "../stack-status.ts";

const ARGS = {
  write: {
    type: "string",
    alias: "out",
    description:
      "Env file to write, or - to print the variables. Defaults to env.output, then .env.local",
    valueHint: "file",
  },
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

const ENV_PLAN_ARGS = {
  "dry-run": PLAN_ARGS["dry-run"],
  check: PLAN_ARGS.check,
};

export type EnvArgs = CliArgs<
  typeof ARGS & Pick<typeof PLAN_ARGS, "dry-run" | "check">
>;

export type EnvFlags = CliOptions<
  typeof ARGS & Pick<typeof PLAN_ARGS, "dry-run" | "check">
>;

async function readStatus(
  config: ResolvedConfig,
  args: Pick<EnvFlags, "status-file">,
  env: CliEnv,
  signal?: AbortSignal,
): Promise<StackStatus> {
  const from = args["status-file"];

  if (from) {
    const status = parseStackStatus(
      await readFile(insideRoot(config.root, from, "--status-file"), "utf-8"),
    );

    if (!status) {
      throw new CliError(
        "invalid_input",
        `${from} holds no supabase status JSON.`,
      );
    }

    return status;
  }

  const result = await readStackStatus(config.root, env, { signal });

  if (!result.ok) {
    throw new CliError(
      "supabase_cli_failed",
      `supabase status failed (${result.code}). Is the local stack running (supabase start)?`,
      { suggestion: "supabase start" },
    );
  }

  return result.status;
}

/** The browser prefix: `--prefix`, then `env.prefix`, then the framework's. */
export async function browserPrefix(
  config: ResolvedConfig,
  flag: string | undefined,
): Promise<string> {
  const prefix = flag ?? config.env.prefix;

  return prefix === undefined
    ? publicPrefix(await detectProject(config.root))
    : prefixFromFlag(prefix);
}

export interface StackEnv {
  readonly status: StackStatus;
  readonly values: Readonly<Record<string, string>>;
}

/** The running stack's variables, as `env` writes them and `run` sets them. */
export async function readStackEnv(
  config: ResolvedConfig,
  args: Pick<EnvFlags, "prefix" | "status-file">,
  env: CliEnv,
  signal?: AbortSignal,
): Promise<StackEnv> {
  const status = await readStatus(config, args, env, signal);
  const prefix = await browserPrefix(config, args.prefix);

  const values = stackEnvValues(status, prefix);

  if (!values) {
    throw new CliError(
      "supabase_cli_failed",
      "supabase status has no API_URL or publishable key. Is the stack running?",
      { suggestion: "supabase start" },
    );
  }

  return { status, values };
}

/** Replaces `KEY=` lines in place and appends the rest under a header. */
export function mergeEnv(
  current: string,
  values: Readonly<Record<string, string>>,
): string {
  const pending = new Map(Object.entries(values));

  const lines =
    current.length > 0 ? current.replace(/\n$/, "").split("\n") : [];

  const merged = lines.map((line) => {
    const key = /^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=/.exec(
      line,
    )?.[1];

    if (!key || !pending.has(key)) {
      return line;
    }

    const value = pending.get(key)!;
    pending.delete(key);

    return `${key}=${value}`;
  });

  if (pending.size > 0) {
    if (merged.length > 0 && merged.at(-1) !== "") {
      merged.push("");
    }

    merged.push("# Local Supabase stack (better-supabase env)");

    for (const [key, value] of pending) {
      merged.push(`${key}=${value}`);
    }
  }

  return `${merged.join("\n")}\n`;
}

export async function runEnv(
  config: ResolvedConfig,
  args: EnvFlags,
  env: CliEnv,
  signal?: AbortSignal,
): Promise<CommandResult> {
  const status = await readStatus(config, args, env, signal);
  const prefix = await browserPrefix(config, args.prefix);

  const values = stackEnvValues(status, prefix);

  if (!values) {
    return {
      code: 1,
      error:
        "supabase status has no API_URL or publishable key. Is the stack running?",
    };
  }

  const write = args.write;

  if (write === "-") {
    return {
      code: 0,
      output: Object.entries(values)
        .map(([key, value]) => `${key}=${value}`)
        .join("\n"),
      data: { values },
    };
  }

  const out = write ?? config.env.output;
  const path = insideRoot(config.root, out, write ? "--write" : "env.output");
  const current = (await readIfExists(path)) ?? "";
  const file = display(config.root, out);

  const plan: FilePlan = {
    root: config.root,
    regenerate: "better-supabase env",
    files: [
      {
        path,
        contents: mergeEnv(current, values),
        mode: 0o600,
        secret: true,
        note: Object.keys(values).join(", "),
      },
    ],
  };

  const applied = await applyPlan(plan, args);

  if (applied.mode !== "write") {
    return planResult(plan, applied, {
      data: { file, keys: Object.keys(values) },
    });
  }

  const warnings: string[] = [];

  const publishable = status["PUBLISHABLE_KEY"];

  if (typeof publishable !== "string" || publishable.length === 0) {
    warnings.push(
      "This Supabase CLI prints only legacy JWT keys. Upgrade it to get sb_publishable_/sb_secret_ keys.",
    );
  }

  const gitignore = resolve(config.root, ".gitignore");

  const ignored =
    existsSync(gitignore) &&
    (await readFile(gitignore, "utf-8"))
      .split("\n")
      .some((line) =>
        [out, `/${out}`, ".env*", ".env*.local", "*.local"].includes(
          line.trim(),
        ),
      );

  if (!ignored) {
    warnings.push(`Add ${out} to .gitignore; it contains the secret key.`);
  }

  return {
    code: 0,
    output: [
      ...changeLines(applied),
      ...warnings.map((warning) => `Warning: ${warning}`),
    ].join("\n"),
    data: {
      file,
      files: applied.changes,
      keys: Object.keys(values),
      warnings,
    },
  };
}

export const envCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("env"),
  args: { ...ARGS, ...ENV_PLAN_ARGS },
  run: (args, { config, env, signal }) => runEnv(config, args, env, signal),
});
