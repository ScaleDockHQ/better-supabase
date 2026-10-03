import { existsSync } from "node:fs";
import { chmod, mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs } from "../command.ts";
import type { CommandResult } from "../io.ts";

import { defineCliCommand } from "../command.ts";
import { display } from "../io.ts";

const ARGS = {
  out: {
    type: "string",
    description: "Defaults to supabase/signing_keys.json",
    valueHint: "file",
  },
  rotate: {
    type: "boolean",
    description:
      "Put a new key first (it signs) and keep the old ones (they still verify)",
  },
  force: { type: "boolean", description: "Replace the file" },
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
  const out = args.out ?? "supabase/signing_keys.json";
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
      ? (JSON.parse(await readFile(path, "utf8")) as unknown[])
      : [];
  if (!Array.isArray(previous)) {
    return {
      code: 1,
      error: `${display(config.root, out)} is not a JSON array of keys.`,
    };
  }
  const key = await createSigningKey();
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify([key, ...previous], null, 2)}\n`, {
    mode: 0o600,
  });
  await chmod(path, 0o600);

  const lines = [
    `Wrote ${display(config.root, out)} with key ${key.kid}${previous.length > 0 ? ` (${previous.length} older key${previous.length === 1 ? "" : "s"} kept for verification)` : ""}.`,
  ];
  const toml = resolve(config.root, "supabase/config.toml");
  const configured =
    existsSync(toml) &&
    /^\s*signing_keys_path\s*=/m.test(await readFile(toml, "utf8"));
  if (!configured) {
    const relativeToSupabase = out.startsWith("supabase/")
      ? `./${out.slice("supabase/".length)}`
      : out;
    lines.push(
      "",
      "Add it to supabase/config.toml and restart the stack:",
      "  [auth]",
      `  signing_keys_path = "${relativeToSupabase}"`,
    );
  }
  const gitignored = [
    resolve(config.root, ".gitignore"),
    resolve(config.root, "supabase/.gitignore"),
  ];
  let ignored = false;
  for (const file of gitignored) {
    if (
      existsSync(file) &&
      (await readFile(file, "utf8")).includes("signing_keys")
    )
      ignored = true;
  }
  if (!ignored)
    lines.push(
      "",
      `Warning: add ${out} to .gitignore; it holds a private key.`,
    );
  return { code: 0, output: lines.join("\n") };
}

export const keysCommand: AnyCommand = defineCliCommand({
  meta: {
    name: "keys",
    description:
      "Creates an ES256 signing key for the local stack, so local tokens verify through JWKS like hosted ones",
  },
  args: ARGS,
  run: (args, { config }) => runKeys(config, args),
});
