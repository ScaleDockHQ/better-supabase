import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";

import {
  type SigningJwk,
  signTestJwtWithKey,
  type TestJwtClaims,
} from "./jwt.ts";

const SIGNING_KEYS_PATH = /^\s*signing_keys_path\s*=\s*"([^"]+)"/m;

/** `supabase/config.toml`'s `signing_keys_path`, else `supabase/signing_keys.json`, in `from` or a parent. */
async function findSigningKeys(from: string): Promise<string | undefined> {
  for (let dir = resolve(from); ; dir = dirname(dir)) {
    const supabase = join(dir, "supabase");
    const toml = join(supabase, "config.toml");
    if (existsSync(toml)) {
      const configured = SIGNING_KEYS_PATH.exec(
        await readFile(toml, "utf8"),
      )?.[1];
      const path = resolve(supabase, configured ?? "signing_keys.json");
      if (existsSync(path)) return path;
    }
    if (dirname(dir) === dir) return undefined;
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
 * `better-supabase keys` wrote. `path` defaults to `$SUPABASE_SIGNING_KEYS_PATH`,
 * then `signing_keys_path` from the nearest `supabase/config.toml`.
 */
export async function localSigningKey(path?: string): Promise<SigningJwk> {
  const file =
    path ??
    process.env["SUPABASE_SIGNING_KEYS_PATH"] ??
    (await findSigningKeys(process.cwd()));
  if (!file || !existsSync(file)) {
    throw new TypeError(
      'No local signing key. Run `better-supabase keys`, set `signing_keys_path` in supabase/config.toml and restart the stack, or pass { alg: "HS256" } to sign with the local JWT secret.',
    );
  }
  const keys: unknown = JSON.parse(await readFile(file, "utf8"));
  const first: unknown = Array.isArray(keys) ? keys[0] : undefined;
  if (!isSigningKey(first))
    throw new TypeError(`${file} has no private ES256 key first.`);
  return first;
}

/** Signs a token with the local stack's ES256 key (see `localSigningKey`). Test-only. */
export async function signLocalJwt(
  claims: TestJwtClaims,
  path?: string,
): Promise<string> {
  return signTestJwtWithKey(await localSigningKey(path), claims);
}
