import { resolveAuth } from "better-supabase/server";
import {
  createTestSigner,
  signTestJwt,
  signTestJwtWithKey,
  type SigningJwk,
} from "better-supabase/testing";
import { mkdtemp, readFile, rm, writeFile, mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";

import { run } from "../../src/run.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

const decode = (part: string): Record<string, unknown> =>
  JSON.parse(
    new TextDecoder().decode(
      Uint8Array.from(
        atob(part.replaceAll("-", "+").replaceAll("_", "/")),
        (c) => c.charCodeAt(0),
      ),
    ),
  ) as Record<string, unknown>;
const bytes = (part: string) =>
  atob(part.replaceAll("-", "+").replaceAll("_", "/")).length;

const dir = await mkdtemp(join(tmpdir(), "bs-es256-"));
afterAll(() => rm(dir, { recursive: true, force: true }));

describe("RFC 7518 ES256 (section 3.4) and RFC 7517 JSON Web Keys", () => {
  it("better-supabase keys writes a P-256 private JWK for ES256 with a kid", async () => {
    await mkdir(join(dir, "supabase"), { recursive: true });
    await writeFile(join(dir, "supabase/config.toml"), "[auth]\n");
    await writeFile(join(dir, "package.json"), "{}");
    expect((await run(["keys", "--cwd", dir])).code).toBe(0);
    const [key] = JSON.parse(
      await readFile(join(dir, "supabase/signing_keys.json"), "utf8"),
    ) as SigningJwk[];
    expect(key).toMatchObject({
      kty: "EC",
      crv: "P-256",
      alg: "ES256",
      use: "sig",
    });
    expect(key!.kid).toMatch(/\S/);
    for (const coordinate of ["x", "y", "d"] as const)
      expect(bytes(String(key![coordinate]))).toBe(32);

    const token = await signTestJwtWithKey(key!, { sub: "u1" });
    const [header, , signature] = token.split(".");
    expect(decode(header!)).toEqual({
      alg: "ES256",
      typ: "JWT",
      kid: key!.kid,
    });
    expect(bytes(signature!)).toBe(64);
  });

  it("signatures are the 64-byte R || S concatenation, not DER (section 3.4)", async () => {
    const signer = await createTestSigner();
    const [header, , signature] = (await signer.sign({ sub: "u1" })).split(".");
    expect(decode(header!)).toMatchObject({
      alg: "ES256",
      kid: (signer.jwks.keys[0] as JsonWebKey & { kid: string }).kid,
    });
    expect(bytes(signature!)).toBe(64);
  });

  it("the published JWKS holds only public members", async () => {
    const signer = await createTestSigner();
    for (const key of signer.jwks.keys) {
      expect(key).toMatchObject({
        kty: "EC",
        crv: "P-256",
        alg: "ES256",
        use: "sig",
      });
      expect(key).not.toHaveProperty("d");
    }
  });

  it("verifies ES256 tokens through JWKS and rejects HS256 tokens there", async () => {
    const signer = await createTestSigner();
    const request = (token: string) =>
      new Request("https://api.test/", {
        headers: { authorization: `Bearer ${token}` },
      });
    const good = await resolveAuth(request(await signer.sign({ sub: "u1" })), {
      env,
      jwks: signer.jwks as never,
    });
    expect(good.auth.kind).toBe("user");
    const hs256 = await signTestJwt(
      "super-secret-jwt-token-with-at-least-32-characters",
      { sub: "u1" },
    );
    expect(decode(hs256.split(".")[0]!)).toMatchObject({ alg: "HS256" });
    const rejected = await resolveAuth(request(hs256), {
      env,
      jwks: signer.jwks as never,
    });
    expect(rejected.auth).toMatchObject({
      kind: "invalid",
      error: { status: 401 },
    });
  });

  it("rejects a token whose ES256 signature was made by another key", async () => {
    const [mine, theirs] = [await createTestSigner(), await createTestSigner()];
    const forged = await theirs.sign({ sub: "u1" });
    const [, body, signature] = forged.split(".");
    const header = btoa(
      JSON.stringify({
        alg: "ES256",
        typ: "JWT",
        kid: (mine.jwks.keys[0] as JsonWebKey & { kid: string }).kid,
      }),
    ).replaceAll("=", "");
    const { auth } = await resolveAuth(
      new Request("https://api.test/", {
        headers: { authorization: `Bearer ${header}.${body}.${signature}` },
      }),
      { env, jwks: mine.jwks as never },
    );
    expect(auth.kind).toBe("invalid");
  });
});
