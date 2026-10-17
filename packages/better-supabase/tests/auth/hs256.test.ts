import { describe, expect, it } from "vitest";

import { isSharedSecretToken, verifyHs256 } from "../../src/auth/hs256.ts";
import { toBase64Url } from "../../src/core/base64.ts";
import { signTestJwt } from "../../src/testing/jwt.ts";

const SECRET = "lite-secret-0123456789abcdef0123456789";
const NOW = Math.floor(Date.now() / 1000);

async function hmac(header: object, payload: object): Promise<string> {
  const head = toBase64Url(JSON.stringify(header));
  const body = toBase64Url(JSON.stringify(payload));

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`${head}.${body}`),
  );

  return `${head}.${body}.${toBase64Url(new Uint8Array(signature))}`;
}

describe("verifyHs256", () => {
  it("returns the claims and the user of a valid token", async () => {
    const token = await signTestJwt(SECRET, {
      sub: "u1",
      email: "a@acme.test",
      app_metadata: { plan: "pro" },
      user_metadata: { name: "A" },
    });

    const result = await verifyHs256(token, SECRET, {
      now: NOW,
      audience: "authenticated",
    });

    expect(result).toMatchObject({
      ok: true,
      claims: { sub: "u1", role: "authenticated" },
      user: {
        id: "u1",
        role: "authenticated",
        email: "a@acme.test",
        appMetadata: { plan: "pro" },
        userMetadata: { name: "A" },
      },
    });
  });

  it.each([
    [
      "a token from another secret",
      () => signTestJwt(`${SECRET}x`, { sub: "u1" }),
      {},
      "does not match the JWT secret",
    ],
    [
      "an expired token",
      () => signTestJwt(SECRET, { sub: "u1", expiresIn: -1 }),
      {},
      "expired",
    ],
    [
      "a token before nbf",
      () => hmac({ alg: "HS256" }, { sub: "u1", nbf: NOW + 60 }),
      {},
      "not valid yet",
    ],
    [
      "another audience",
      () => signTestJwt(SECRET, { sub: "u1" }),
      { audience: ["api"] },
      "audience",
    ],
    [
      "another issuer",
      () => hmac({ alg: "HS256" }, { sub: "u1", iss: "a" }),
      { issuer: "b" },
      "issuer",
    ],
    [
      "a token without sub",
      () => hmac({ alg: "HS256" }, { role: "anon" }),
      {},
      "no sub claim",
    ],
    [
      "a payload that is not an object",
      () => hmac({ alg: "HS256" }, []),
      {},
      "not a JSON object",
    ],
    [
      "another algorithm",
      () => hmac({ alg: "HS512" }, { sub: "u1" }),
      {},
      "not signed with HS256",
    ],
    ["a token with two parts", () => Promise.resolve("a.b"), {}, "not a JWT"],
    [
      "a signature that is not base64url",
      async () =>
        `${(await signTestJwt(SECRET, { sub: "u1" })).split(".").slice(0, 2).join(".")}.%%%`,
      {},
      "not base64url",
    ],
  ])("rejects %s", async (_name, token, options, message) => {
    const result = await verifyHs256(await token(), SECRET, {
      now: NOW,
      ...options,
    });

    expect(result.ok).toBe(false);
    expect(!result.ok && result.message).toContain(message);
  });

  it("accepts a matching issuer and an audience list", async () => {
    const token = await hmac(
      { alg: "HS256" },
      { sub: "u1", iss: "lite", aud: ["authenticated", "api"] },
    );

    const result = await verifyHs256(token, SECRET, {
      now: NOW,
      issuer: ["lite"],
      audience: "api",
    });

    expect(result.ok).toBe(true);
  });
});

describe("isSharedSecretToken", () => {
  it("matches HS256 tokens without a kid", async () => {
    expect(isSharedSecretToken(await signTestJwt(SECRET, { sub: "u1" }))).toBe(
      true,
    );
    expect(
      isSharedSecretToken(
        await hmac({ alg: "HS256", kid: "k1" }, { sub: "u1" }),
      ),
    ).toBe(false);
    expect(isSharedSecretToken(await hmac({ alg: "ES256" }, {}))).toBe(false);
    expect(isSharedSecretToken("not-a-jwt")).toBe(false);
  });
});
