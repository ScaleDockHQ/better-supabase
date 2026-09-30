import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { ParsedArgs } from "../args.ts";
import type { CommandResult } from "../io.ts";

import { flagBool, flagString } from "../args.ts";
import { supabaseCli } from "../exec.ts";
import { display, writeIfChanged } from "../io.ts";
import { detectProject, publicPrefix } from "../project.ts";

export const ENV_HELP = `Usage: better-supabase env [--out .env.local] [--prefix NEXT_PUBLIC_|none] [--print]

Writes the local stack's URL and keys (from \`supabase status\`) to an env file.
Other lines in the file are kept. Values are never printed unless --print is given.

Options
  --out <file>      Defaults to .env.local
  --prefix <p>      Prefix for browser variables. Detected from your framework; "none" for no prefix.
  --from <file>     Read \`supabase status -o json\` output from a file
  --print           Print the variables instead of writing them`;

interface Status {
  readonly [key: string]: unknown;
}

async function readStatus(
  config: ResolvedConfig,
  args: ParsedArgs,
  env: Readonly<Record<string, string | undefined>>,
): Promise<Status> {
  const from = flagString(args.flags, "from");
  if (from)
    // SAFETY: the file is the JSON output of supabase status.
    return JSON.parse(
      await readFile(resolve(config.root, from), "utf8"),
    ) as Status;
  const result = await supabaseCli(["status", "-o", "json"], config.root, env);
  if (result.code !== 0) {
    throw new Error(
      `supabase status failed (${result.code}). Is the local stack running (supabase start)?`,
    );
  }
  const start = result.stdout.indexOf("{");
  if (start === -1) throw new Error("supabase status printed no JSON.");
  // SAFETY: supabase status -o json prints a Status object.
  return JSON.parse(result.stdout.slice(start)) as Status;
}

const text = (status: Status, ...keys: string[]): string | undefined => {
  for (const key of keys) {
    const value = status[key];
    if (typeof value === "string" && value.length > 0) return value;
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
    if (!key || !pending.has(key)) return line;
    const value = pending.get(key)!;
    pending.delete(key);
    return `${key}=${value}`;
  });
  if (pending.size > 0) {
    if (merged.length > 0 && merged.at(-1) !== "") merged.push("");
    merged.push("# Local Supabase stack (better-supabase env)");
    for (const [key, value] of pending) merged.push(`${key}=${value}`);
  }
  return `${merged.join("\n")}\n`;
}

export async function runEnv(
  config: ResolvedConfig,
  args: ParsedArgs,
  env: Readonly<Record<string, string | undefined>>,
): Promise<CommandResult> {
  const status = await readStatus(config, args, env);
  const project = await detectProject(config.root);
  const prefixFlag = flagString(args.flags, "prefix");
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
  if (secretKey) values["SUPABASE_SECRET_KEY"] = secretKey;
  const dbUrl = text(status, "DB_URL");
  if (dbUrl) values["SUPABASE_DB_URL"] = dbUrl;
  const jwtSecret = text(status, "JWT_SECRET");
  if (jwtSecret) values["SUPABASE_JWT_SECRET"] = jwtSecret;

  if (flagBool(args.flags, "print")) {
    return {
      code: 0,
      output: Object.entries(values)
        .map(([key, value]) => `${key}=${value}`)
        .join("\n"),
    };
  }

  const out = flagString(args.flags, "out") ?? ".env.local";
  const path = resolve(config.root, out);
  const current = existsSync(path) ? await readFile(path, "utf8") : "";
  const wrote = await writeIfChanged(path, mergeEnv(current, values));
  const lines = [
    `${wrote ? "Wrote" : "Unchanged"} ${display(config.root, out)}: ${Object.keys(values).join(", ")}`,
  ];
  if (!text(status, "PUBLISHABLE_KEY")) {
    lines.push(
      "Warning: this Supabase CLI prints only legacy JWT keys. Upgrade it to get sb_publishable_/sb_secret_ keys.",
    );
  }
  const gitignore = resolve(config.root, ".gitignore");
  const ignored =
    existsSync(gitignore) &&
    (await readFile(gitignore, "utf8"))
      .split("\n")
      .some((line) =>
        [out, `/${out}`, ".env*", ".env*.local", "*.local"].includes(
          line.trim(),
        ),
      );
  if (!ignored)
    lines.push(
      `Warning: add ${out} to .gitignore; it contains the secret key.`,
    );
  return { code: 0, output: lines.join("\n") };
}
