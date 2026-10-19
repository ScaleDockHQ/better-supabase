import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";

import { defineCliCommand } from "../core/command.ts";
import { applyPlan, changeLines } from "../core/files.ts";
import { display } from "../core/io.ts";
import { commandMeta } from "../core/manifest.ts";
import { supabaseDir } from "../supabase-toml.ts";

const ARGS = {
  out: {
    type: "string",
    description: "Defaults to keys.output, then supabase/signing_keys.json",
    valueHint: "file",
  },
  rotate: {
    type: "boolean",
    description:
      "Put a new key first (it signs) and keep the old ones (they still verify)",
  },
  force: { type: "boolean", description: "Replace the file" },
  "dry-run": {
    type: "boolean",
    description: "Print what would change and write nothing",
  },
} as const;

export type KeysArgs = CliArgs<typeof ARGS>;

interface SigningKey {
  readonly kty: "EC";
  readonly kid: string;
  readonly use: "sig";
  readonly key_ops: readonly string[];
  readonly alg: "ES256";
  readonly ext: true;
  readonly crv: string;
  readonly x: string;
  readonly y: string;
  readonly d: string;
}

async function createSigningKey(): Promise<SigningKey> {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );

  const jwk = await crypto.subtle.exportKey("jwk", pair.privateKey);

  return {
    kty: "EC",
    kid: crypto.randomUUID(),
    use: "sig",
    key_ops: ["sign", "verify"],
    alg: "ES256",
    ext: true,
    crv: jwk.crv!,
    x: jwk.x!,
    y: jwk.y!,
    d: jwk.d!,
  };
}

export async function runKeys(
  config: ResolvedConfig,
  args: KeysArgs,
): Promise<CommandResult> {
  const dir = supabaseDir(config.root);
  const out = args.out ?? config.keys.output ?? `${dir}/signing_keys.json`;
  const path = resolve(config.root, out);
  const rotate = args.rotate === true;
  const exists = existsSync(path);

  if (exists && !rotate && args.force !== true) {
    return {
      code: 1,
      error: `${display(config.root, out)} exists. Use --rotate to add a key or --force to replace it.`,
    };
  }

  // SAFETY: the keys file is a JSON list that this command writes.
  const previous: unknown[] =
    exists && rotate
      ? (JSON.parse(await readFile(path, "utf-8")) as unknown[])
      : [];

  if (!Array.isArray(previous)) {
    return {
      code: 1,
      errorCode: "invalid_input",
      error: `${display(config.root, out)} is not a JSON array of keys.`,
    };
  }

  const key = await createSigningKey();

  const applied = await applyPlan(
    {
      // The supabase folder can sit above the package in a monorepo.
      root:
        args.out === undefined && config.keys.output === undefined
          ? resolve(config.root, dir, "..")
          : config.root,
      base: config.root,
      regenerate: "better-supabase keys --rotate",
      files: [
        {
          path,
          contents: `${JSON.stringify([key, ...previous], null, 2)}\n`,
          mode: 0o600,
          secret: true,
          note: `key ${key.kid}${previous.length > 0 ? `, ${previous.length} older key${previous.length === 1 ? "" : "s"} kept for verification` : ""}`,
        },
      ],
    },
    { "dry-run": args["dry-run"] },
  );

  const lines = changeLines(applied);

  const toml = resolve(config.root, dir, "config.toml");

  const configured =
    existsSync(toml) &&
    /^\s*signing_keys_path\s*=/m.test(await readFile(toml, "utf-8"));

  if (!configured) {
    const relativeToSupabase = out.startsWith(`${dir}/`)
      ? `./${out.slice(dir.length + 1)}`
      : out;

    lines.push(
      "",
      `Add it to ${dir}/config.toml and restart the stack:`,
      "  [auth]",
      `  signing_keys_path = "${relativeToSupabase}"`,
    );
  }

  const gitignored = [
    resolve(config.root, ".gitignore"),
    resolve(config.root, dir, ".gitignore"),
  ];

  let ignored = false;

  for (const file of gitignored) {
    if (
      existsSync(file) &&
      (await readFile(file, "utf-8")).includes("signing_keys")
    ) {
      ignored = true;
    }
  }

  if (!ignored) {
    lines.push(
      "",
      `Warning: add ${out} to .gitignore; it holds a private key.`,
    );
  }

  return {
    code: 0,
    output: lines.join("\n"),
    data: {
      file: display(config.root, out),
      files: applied.changes,
      kid: key.kid,
      kept: previous.length,
      configured,
      gitignored: ignored,
    },
  };
}

export const keysCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("keys"),
  args: ARGS,
  run: (args, { config }) => runKeys(config, args),
});
