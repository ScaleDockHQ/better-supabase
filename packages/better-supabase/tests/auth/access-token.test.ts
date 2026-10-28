import { describe, expect, it, vi } from "vitest";

import type { Jwk } from "../../src/core/jws.ts";

import {
  accessTokenResolver,
  isAccessTokenJwt,
} from "../../src/auth/access-token.ts";
import { resolveAuth } from "../../src/auth/resolve.ts";
import { dbError } from "../../src/core/errors.ts";
import {
  generateSigningKey,
  importSigningKey,
  signCompact,
} from "../../src/core/jws.ts";
import { err, ok } from "../../src/core/result.ts";

const ISSUER = "https://auth.example.com";
const AUDIENCE = "https://api.example.com";
const NOW = 1_800_000_000;

async function issuer() {
  const key = await generateSigningKey("ES256");
  const signing = await importSigningKey(key.privateKey);
  const jwks = { keys: [{ ...key.publicKey, kid: key.kid }] };

  const sign = (
    claims: Record<string, unknown> = {},
    header: Record<string, unknown> = {},
  ) =>
    signCompact(
      signing,
      "ES256",
      { alg: "ES256", kid: key.kid, typ: "at+jwt", ...header },
      {
        iss: ISSUER,
        aud: AUDIENCE,
        sub: "user-1",
        client_id: "client-1",
        scope: "contacts:read",
        jti: "jti-1",
        iat: NOW - 10,
        exp: NOW + 600,
        ...claims,
      },
    );

  return { jwks, sign, kid: key.kid, publicKey: key.publicKey };
}

const request = (token: string, scheme = "Bearer") =>
  new Request("https://api.example.com/contacts", {
    headers: { authorization: `${scheme} ${token}` },
  });

const now = () => NOW * 1000;

describe("accessTokenResolver", () => {
  it("resolves an RFC 9068 token to a user with client_id and scope", async () => {
    const { jwks, sign } = await issuer();

    const resolver = accessTokenResolver({
      jwks,
      issuer: ISSUER,
      audience: AUDIENCE,
      now,
    });

    const token = await sign({ tenant: "org-1" });

    const state = await resolver.resolve(request(token));

    expect(state).toMatchObject({
      kind: "user",
      source: "oauth",
      token,
      expiresAt: NOW + 600,
      user: { id: "user-1", role: "authenticated" },
      claims: {
        sub: "user-1",
        client_id: "client-1",
        scope: "contacts:read",
        role: "authenticated",
        tenant: "org-1",
      },
    });
  });

  it("lets other tokens fall through", async () => {
    const { jwks, sign } = await issuer();

    const resolver = accessTokenResolver({
      jwks,
      issuer: ISSUER,
      audience: AUDIENCE,
      now,
    });

    const supabaseToken = await sign({}, { typ: "JWT" });

    expect(await resolver.resolve(request(supabaseToken))).toBeUndefined();
    expect(
      await resolver.resolve(request(await sign(), "DPoP")),
    ).toBeUndefined();
    expect(
      await resolver.resolve(new Request("https://api.example.com")),
    ).toBeUndefined();
    expect(
      isAccessTokenJwt(await sign({}, { typ: "application/AT+JWT" })),
    ).toBe(true);
  });

  it.each([
    [{ iss: "https://evil.example.com" }, "ACCESS_TOKEN_ISSUER"],
    [{ aud: "https://other.example.com" }, "ACCESS_TOKEN_AUDIENCE"],
    [{ exp: NOW - 60 }, "ACCESS_TOKEN_EXPIRED"],
    [{ exp: undefined }, "ACCESS_TOKEN_INVALID"],
    [{ iat: NOW + 600 }, "ACCESS_TOKEN_INVALID"],
    [{ nbf: NOW + 600 }, "ACCESS_TOKEN_INVALID"],
    [{ client_id: undefined }, "ACCESS_TOKEN_INVALID"],
    [{ jti: undefined }, "ACCESS_TOKEN_INVALID"],
    [{ sub: "" }, "ACCESS_TOKEN_INVALID"],
    [{ scope: ["a"] }, "ACCESS_TOKEN_INVALID"],
    [{ role: "service_role" }, "ACCESS_TOKEN_ROLE"],
    [{ cnf: { jkt: "x" } }, "ACCESS_TOKEN_BOUND"],
  ])("fails closed on %o", async (claims, code) => {
    const { jwks, sign } = await issuer();

    const resolver = accessTokenResolver({
      jwks,
      issuer: ISSUER,
      audience: AUDIENCE,
      now,
    });

    expect(await resolver.resolve(request(await sign(claims)))).toMatchObject({
      kind: "invalid",
      reason: "token",
      error: { kind: "unauthorized", code },
    });
  });

  it("accepts an audience list and allows clock skew", async () => {
    const { jwks, sign } = await issuer();

    const resolver = accessTokenResolver({
      jwks,
      issuer: ISSUER,
      audience: AUDIENCE,
      now,
    });

    const token = await sign({ aud: ["x", AUDIENCE], exp: NOW - 10 });

    expect(await resolver.resolve(request(token))).toMatchObject({
      kind: "user",
    });
  });

  it("refuses a token signed by another key", async () => {
    const { jwks } = await issuer();
    const other = await issuer();

    const resolver = accessTokenResolver({
      jwks,
      issuer: ISSUER,
      audience: AUDIENCE,
      now,
    });

    expect(await resolver.resolve(request(await other.sign()))).toMatchObject({
      kind: "invalid",
      error: { code: "ACCESS_TOKEN_INVALID" },
    });
  });

  it("refetches a JWKS URL once for an unknown kid", async () => {
    const first = await issuer();
    const rotated = await issuer();
    let served: { keys: Jwk[] } = first.jwks;
    const fetch = vi.fn(async () => Response.json(served));

    const resolver = accessTokenResolver({
      jwks: new URL("https://auth.example.com/jwks"),
      issuer: ISSUER,
      audience: AUDIENCE,
      fetch,
      now,
      cache: { refetchSeconds: 0 },
    });

    expect(await resolver.resolve(request(await first.sign()))).toMatchObject({
      kind: "user",
    });
    served = rotated.jwks;
    expect(
      await resolver.resolve(request(await rotated.sign({ jti: "jti-2" }))),
    ).toMatchObject({ kind: "user" });
    expect(fetch).toHaveBeenCalledTimes(2);
  });

  it("checks the revocation list by jti and grant", async () => {
    const { jwks, sign } = await issuer();

    const isRevoked = vi.fn((jti: string, grant: string | undefined) =>
      Promise.resolve(ok(jti === "revoked" || grant === "grant-revoked")),
    );

    const resolver = accessTokenResolver({
      jwks,
      issuer: ISSUER,
      audience: AUDIENCE,
      now,
      revocation: { isRevoked },
    });

    const token = await sign({ grant_id: "grant-1" });

    expect(await resolver.resolve(request(token))).toMatchObject({
      kind: "user",
    });
    expect(isRevoked).toHaveBeenLastCalledWith("jti-1", "grant-1");
    expect(
      await resolver.resolve(request(await sign({ jti: "revoked" }))),
    ).toMatchObject({ error: { code: "ACCESS_TOKEN_REVOKED" } });
    expect(
      await resolver.resolve(
        request(await sign({ grant_id: "grant-revoked" })),
      ),
    ).toMatchObject({ error: { code: "ACCESS_TOKEN_REVOKED" } });
  });

  it("fails closed when the revocation list can't be read", async () => {
    const { jwks, sign } = await issuer();

    const resolver = accessTokenResolver({
      jwks,
      issuer: ISSUER,
      audience: AUDIENCE,
      now,
      revocation: {
        isRevoked: () => Promise.resolve(err(dbError("network", "down"))),
      },
    });

    expect(await resolver.resolve(request(await sign()))).toMatchObject({
      kind: "invalid",
      error: { kind: "network", code: "ACCESS_TOKEN_REVOCATION_UNAVAILABLE" },
    });
  });

  it("keeps the token's claims over the claims hook", async () => {
    const { jwks, sign } = await issuer();

    const resolver = accessTokenResolver({
      jwks,
      issuer: ISSUER,
      audience: AUDIENCE,
      now,
      claims: () => ({ sub: "someone-else", tenant_id: "org-9", scope: "*" }),
    });

    expect(await resolver.resolve(request(await sign()))).toMatchObject({
      claims: { sub: "user-1", scope: "contacts:read", tenant_id: "org-9" },
    });
  });

  it("runs before the Supabase check in resolveAuth", async () => {
    const { jwks, sign } = await issuer();

    const resolution = await resolveAuth(request(await sign()), {
      env: {
        url: "https://project.supabase.co",
        publishableKey: "sb_publishable_x",
        jwksUrl: new URL(
          "https://project.supabase.co/auth/v1/.well-known/jwks.json",
        ),
        jwks: { keys: [] },
      },
      resolvers: [
        accessTokenResolver({ jwks, issuer: ISSUER, audience: AUDIENCE, now }),
      ],
    });

    expect(resolution.auth).toMatchObject({ kind: "user", source: "oauth" });
    expect(resolution.cookies).toEqual([]);
  });

  it("ignores bearer values that are not a JWS with a JSON header", async () => {
    const { jwks } = await issuer();

    const resolver = accessTokenResolver({
      jwks,
      issuer: ISSUER,
      audience: AUDIENCE,
      now,
    });

    expect(await resolver.resolve(request("abc.def"))).toBeUndefined();
    expect(await resolver.resolve(request("e30x.e30.sig"))).toBeUndefined();
  });

  it("verifies the token again on every request", async () => {
    const { jwks, sign } = await issuer();
    let current = now();

    const resolver = accessTokenResolver({
      jwks,
      issuer: ISSUER,
      audience: AUDIENCE,
      now: () => current,
    });

    const token = await sign();
    const first = await resolver.resolve(request(token));
    expect(await resolver.resolve(request(token))).toEqual(first);

    current += 2 * 3600 * 1000;
    expect(await resolver.resolve(request(token))).toMatchObject({
      kind: "invalid",
    });
  });

  it("fails closed when the key set can't be loaded", async () => {
    const { sign } = await issuer();

    const resolver = accessTokenResolver({
      jwks: async () => {
        throw new Error("offline");
      },
      issuer: ISSUER,
      audience: AUDIENCE,
      now,
    });

    expect(await resolver.resolve(request(await sign()))).toMatchObject({
      kind: "invalid",
      error: { code: "JWKS_FETCH_FAILED" },
    });
  });

  it("requires an issuer and an audience", () => {
    expect(() =>
      accessTokenResolver({
        jwks: { keys: [] },
        issuer: [],
        audience: AUDIENCE,
      }),
    ).toThrow(TypeError);
    expect(() =>
      accessTokenResolver({ jwks: { keys: [] }, issuer: ISSUER, audience: [] }),
    ).toThrow(TypeError);
  });
});
