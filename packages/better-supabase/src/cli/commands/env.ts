import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs, CliOptions } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type { CliEnv } from "../env.ts";

import { defineCliCommand } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import { insideRoot, writeLine } from "../core/files.ts";
import { display, readIfExists } from "../core/io.ts";
import { detectProject, publicPrefix } from "../project/detect.ts";
import {
  parseStackStatus,
  readStackStatus,
  type StackStatus,
} from "../stack-status.ts";

const ARGS = {
  out: {
    type: "string",
    description: "Env file to write. Defaults to env.output, then .env.local",
    valueHint: "file",
  },
  prefix: {
    type: "string",
    description:
      'Prefix for browser variables. Defaults to env.prefix, then one detected from your framework; "none" for no prefix',
    valueHint: "prefix",
  },
  from: {
    type: "string",
    description: "Read `supabase status -o json` output from a file",
    valueHint: "file",
  },
  print: {
    type: "boolean",
    description: "Print the variables instead of writing them",
  },
} as const;

export type EnvArgs = CliArgs<typeof ARGS>;

export type EnvFlags = CliOptions<typeof ARGS>;

async function readStatus(
  config: ResolvedConfig,
  args: EnvFlags,
  env: CliEnv,
  signal?: AbortSignal,
): Promise<StackStatus> {
  const from = args.from;

  if (from) {
    const status = parseStackStatus(
      await readFile(insideRoot(config.root, from, "--from"), "utf-8"),
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

const text = (status: StackStatus, ...keys: string[]): string | undefined => {
  for (const key of keys) {
    const value = status[key];

    if (typeof value === "string" && value.length > 0) {
      return value;
    }
  }

  return undefined;
};

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
  const project = await detectProject(config.root);
  const prefixFlag = args.prefix ?? config.env.prefix;

  const prefix =
    prefixFlag === undefined
      ? publicPrefix(project)
      : prefixFlag === "none"
        ? ""
        : prefixFlag;

  const url = text(status, "API_URL");
  const publishableKey = text(status, "PUBLISHABLE_KEY", "ANON_KEY");
  const secretKey = text(status, "SECRET_KEY", "SERVICE_ROLE_KEY");

  if (!url || !publishableKey) {
    return {
      code: 1,
      error:
        "supabase status has no API_URL or publishable key. Is the stack running?",
    };
  }

  const values: Record<string, string> = {
    [`${prefix}SUPABASE_URL`]: url,
    [`${prefix}SUPABASE_PUBLISHABLE_KEY`]: publishableKey,
  };

  if (secretKey) {
    values["SUPABASE_SECRET_KEY"] = secretKey;
  }

  const dbUrl = text(status, "DB_URL");

  if (dbUrl) {
    values["SUPABASE_DB_URL"] = dbUrl;
  }

  const jwtSecret = text(status, "JWT_SECRET");

  if (jwtSecret) {
    values["SUPABASE_JWT_SECRET"] = jwtSecret;
  }

  if (args.print === true) {
    return {
      code: 0,
      output: Object.entries(values)
        .map(([key, value]) => `${key}=${value}`)
        .join("\n"),
    };
  }

  const out = args.out ?? config.env.output;
  const path = insideRoot(config.root, out, args.out ? "--out" : "env.output");
  const current = (await readIfExists(path)) ?? "";

  const { line } = await writeLine(
    path,
    mergeEnv(current, values),
    display(config.root, out),
    `: ${Object.keys(values).join(", ")}`,
    { mode: 0o600 },
  );

  const lines = [line];

  if (!text(status, "PUBLISHABLE_KEY")) {
    lines.push(
      "Warning: this Supabase CLI prints only legacy JWT keys. Upgrade it to get sb_publishable_/sb_secret_ keys.",
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
    lines.push(
      `Warning: add ${out} to .gitignore; it contains the secret key.`,
    );
  }

  return { code: 0, output: lines.join("\n") };
}

export const envCommand: AnyCommand = defineCliCommand({
  meta: {
    name: "env",
    description:
      "Writes the local stack's URL and keys from `supabase status` to an env file, keeping its other lines",
  },
  args: ARGS,
  run: (args, { config, env, signal }) => runEnv(config, args, env, signal),
});
