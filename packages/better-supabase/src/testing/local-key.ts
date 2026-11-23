import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";

import type { SigningJwk, TestJwtClaims } from "./jwt.ts";

import { signTestJwtWithKey } from "./jwt.ts";

/** `signing_keys_path` in `config.toml`, or in `config.json` and `config.jsonc`. */
const SIGNING_KEYS_PATH = /^\s*"?signing_keys_path"?\s*[=:]\s*"([^"]+)"/m;

/** The files the Supabase CLI reads its config from (3.2.0 reads all three). */
const CONFIG_FILES = ["config.json", "config.jsonc", "config.toml"] as const;

/**
 * `signing_keys_path` from the project config (`config.toml`, `config.json` or
 * `config.jsonc`), else `supabase/signing_keys.json`, in `from` or a parent.
 */
async function findSigningKeys(from: string): Promise<string | undefined> {
  for (let dir = resolve(from); ; dir = dirname(dir)) {
    const supabase = join(dir, "supabase");

    const file = CONFIG_FILES.map((name) => join(supabase, name)).find(
      (candidate) => existsSync(candidate),
    );

    if (file !== undefined) {
      const configured = SIGNING_KEYS_PATH.exec(
        await readFile(file, "utf-8"),
      )?.[1];

      const path = resolve(supabase, configured ?? "signing_keys.json");

      if (existsSync(path)) {
        return path;
      }
    }

    if (dirname(dir) === dir) {
      return undefined;
    }
  }
}

const isSigningKey = (value: unknown): value is SigningJwk =>
  typeof value === "object" &&
  value !== null &&
  "kid" in value &&
  typeof value.kid === "string" &&
  "d" in value &&
  typeof value.d === "string";

/**
 * The key the local stack signs with: the first entry of the file
 * `better-supabase dev keys` wrote. `path` defaults to
 * `$SUPABASE_SIGNING_KEYS_PATH`, then `signing_keys_path` from the nearest
 * project config.
 */
export async function localSigningKey(path?: string): Promise<SigningJwk> {
  const file =
    path ??
    process.env["SUPABASE_SIGNING_KEYS_PATH"] ??
    (await findSigningKeys(process.cwd()));

  if (!file || !existsSync(file)) {
    throw new TypeError(
      'No local signing key. Run `better-supabase dev keys`, set `signing_keys_path` in supabase/config.toml and restart the stack, or pass { alg: "HS256" } to sign with the local JWT secret.',
    );
  }

  const keys: unknown = JSON.parse(await readFile(file, "utf-8"));
  const first: unknown = Array.isArray(keys) ? keys[0] : undefined;

  if (!isSigningKey(first)) {
    throw new TypeError(`${file} has no private ES256 key first.`);
  }

  return first;
}

/**
 * Signs a token with the local stack's ES256 key (see `localSigningKey`).
 * Test-only.
 */
export async function signLocalJwt(
  claims: TestJwtClaims,
  path?: string,
): Promise<string> {
  return signTestJwtWithKey(await localSigningKey(path), claims);
}
