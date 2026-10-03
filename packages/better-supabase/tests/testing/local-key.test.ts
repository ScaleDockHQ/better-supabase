import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { resolveAuth } from "../../src/auth/resolve.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { asUser } from "../../src/testing/as-user.ts";
import { type SigningJwk, signTestJwtWithKey } from "../../src/testing/jwt.ts";
import { localSigningKey } from "../../src/testing/local-key.ts";
import { schema } from "../fixtures/generated-camel.ts";

const USER = "11111111-1111-4111-8111-111111111111";
const env = {
  url: "http://127.0.0.1:54321",
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL("http://127.0.0.1:54321/auth/v1/.well-known/jwks.json"),
};

async function signingKey(): Promise<SigningJwk> {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const jwk = await crypto.subtle.exportKey("jwk", pair.privateKey);
  return { ...jwk, kid: "local-test", alg: "ES256", use: "sig" };
}

async function project(key: SigningJwk): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), "bs-local-key-"));
  await mkdir(join(root, "supabase"));
  await writeFile(
    join(root, "supabase", "config.toml"),
    '[auth]\nsigning_keys_path = "./keys/local.json"\n',
  );
  await mkdir(join(root, "supabase", "keys"));
  await writeFile(
    join(root, "supabase", "keys", "local.json"),
    JSON.stringify([key]),
  );
  return root;
}

describe("local ES256 signing", () => {
  it("signs tokens the JWKS verifies", async () => {
    const key = await signingKey();
    const { d: _private, key_ops: _ops, ...publicKey } = key;
    const token = await signTestJwtWithKey(key, { sub: USER, tenant_id: "o1" });
    const { auth } = await resolveAuth(
      new Request("https://api.test/", {
        headers: { authorization: `Bearer ${token}` },
      }),
      { env, jwks: { keys: [publicKey] } },
    );
    expect(auth).toMatchObject({
      kind: "user",
      user: { id: USER },
      claims: { tenant_id: "o1" },
    });
  });

  it("finds the key through signing_keys_path", async () => {
    const key = await signingKey();
    const root = await project(key);
    const cwd = process.cwd();
    process.chdir(join(root, "supabase"));
    try {
      expect((await localSigningKey()).kid).toBe("local-test");
    } finally {
      process.chdir(cwd);
    }
  });

  it("says how to create a key when there is none", async () => {
    await expect(
      localSigningKey(join(tmpdir(), "missing.json")),
    ).rejects.toThrow(/better-supabase keys/);
  });
});

describe("asUser", () => {
  const betterSupabase = defineSupabase(schema);

  it("signs ES256 by default", async () => {
    const key = await signingKey();
    const user = await asUser(
      betterSupabase,
      { sub: USER },
      { publishableKey: "sb_publishable_test", signingKey: key },
    );
    const header: unknown = JSON.parse(atob(user.token.split(".")[0] ?? ""));
    expect(header).toMatchObject({ alg: "ES256", kid: "local-test" });
  });

  it("refuses HS256 for a hosted project", async () => {
    await expect(
      asUser(
        betterSupabase,
        { sub: USER },
        {
          url: "https://abcdefghijklmnopqrst.supabase.co",
          publishableKey: "sb_publishable_test",
          alg: "HS256",
        },
      ),
    ).rejects.toThrow(/only for a local stack/);
  });
});
