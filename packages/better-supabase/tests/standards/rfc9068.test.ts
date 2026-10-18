import { describe, expect, it } from "vitest";

import type { Jwks } from "../../src/core/jws.ts";

import { accessTokenResolver } from "../../src/auth/access-token.ts";
import { toBase64Url } from "../../src/core/base64.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

const ISSUER = "https://as.example.com";
const AUDIENCE = "https://rs.example.com";
const NOW = 1_800_000_000;
const now = () => NOW * 1000;

const segment = (value: unknown): string => toBase64Url(JSON.stringify(value));

// RFC 9068 section 2.1: RS256 is the algorithm every resource server must accept.
async function rs256Issuer() {
  const pair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );

  const publicJwk = await crypto.subtle.exportKey("jwk", pair.publicKey);

  const jwks: Jwks = {
    keys: [
      {
        kty: "RSA",
        n: publicJwk.n ?? "",
        e: publicJwk.e ?? "",
        kid: "k1",
        alg: "RS256",
      },
    ],
  };

  const sign = async (
    claims: Record<string, unknown> = {},
    header: Record<string, unknown> = {},
  ): Promise<string> => {
    const input = `${segment({ alg: "RS256", kid: "k1", typ: "at+jwt", ...header })}.${segment(
      {
        iss: ISSUER,
        aud: AUDIENCE,
        sub: "5ba552d67",
        client_id: "s6BhdRkqt3",
        scope: "openid profile reademail",
        jti: "dbe39bf3a3ba4238a513f51d6e1691c4",
        iat: NOW - 10,
        exp: NOW + 3600,
        ...claims,
      },
    )}`;

    const signature = await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      pair.privateKey,
      new TextEncoder().encode(input),
    );

    return `${input}.${toBase64Url(new Uint8Array(signature))}`;
  };

  return { jwks, sign };
}

const bearer = (token: string) =>
  new Request(`${AUDIENCE}/messages`, {
    headers: { authorization: `Bearer ${token}` },
  });

describe(`JWT access tokens (RFC 9068, ${SPEC_PINS.rfc9068})`, () => {
  it("accepts an RS256 token with the section 2.2 claims and keeps them", async () => {
    const { jwks, sign } = await rs256Issuer();

    const resolver = accessTokenResolver({
      jwks,
      issuer: ISSUER,
      audience: AUDIENCE,
      now,
    });

    expect(await resolver.resolve(bearer(await sign()))).toMatchObject({
      kind: "user",
      source: "oauth",
      user: { id: "5ba552d67" },
      claims: { client_id: "s6BhdRkqt3", scope: "openid profile reademail" },
    });
  });

  it("claims only tokens typed at+jwt (section 2.1)", async () => {
    const { jwks, sign } = await rs256Issuer();

    const resolver = accessTokenResolver({
      jwks,
      issuer: ISSUER,
      audience: AUDIENCE,
      now,
    });

    expect(
      await resolver.resolve(bearer(await sign({}, { typ: "JWT" }))),
    ).toBeUndefined();
    expect(
      await resolver.resolve(
        bearer(await sign({}, { typ: "application/at+jwt" })),
      ),
    ).toMatchObject({ kind: "user" });
  });

  it.each([
    ["iss", { iss: "https://other-as.example.com" }, "ACCESS_TOKEN_ISSUER"],
    ["aud", { aud: "https://other-rs.example.com" }, "ACCESS_TOKEN_AUDIENCE"],
    ["exp", { exp: NOW - 3600 }, "ACCESS_TOKEN_EXPIRED"],
    ["sub", { sub: undefined }, "ACCESS_TOKEN_INVALID"],
    ["client_id", { client_id: undefined }, "ACCESS_TOKEN_INVALID"],
    ["jti", { jti: undefined }, "ACCESS_TOKEN_INVALID"],
    ["iat", { iat: undefined }, "ACCESS_TOKEN_INVALID"],
  ])(
    "rejects a token failing the section 4 %s check",
    async (_claim, claims, code) => {
      const { jwks, sign } = await rs256Issuer();

      const resolver = accessTokenResolver({
        jwks,
        issuer: ISSUER,
        audience: AUDIENCE,
        now,
      });

      expect(await resolver.resolve(bearer(await sign(claims)))).toMatchObject({
        kind: "invalid",
        error: { code },
      });
    },
  );

  it("rejects alg none (section 4)", async () => {
    const { jwks } = await rs256Issuer();

    const resolver = accessTokenResolver({
      jwks,
      issuer: ISSUER,
      audience: AUDIENCE,
      now,
    });

    const token = `${segment({ alg: "none", typ: "at+jwt" })}.${segment({
      iss: ISSUER,
      aud: AUDIENCE,
      sub: "u",
      client_id: "c",
      jti: "j",
      iat: NOW,
      exp: NOW + 60,
    })}.`;

    expect(await resolver.resolve(bearer(token))).toMatchObject({
      kind: "invalid",
      error: { code: "ACCESS_TOKEN_INVALID" },
    });
  });
});
