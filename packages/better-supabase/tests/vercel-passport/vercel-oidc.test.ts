import { beforeEach, describe, expect, it } from "vitest";

import { clearJwksCache } from "../../src/core/jwks-cache.ts";
import {
  VERCEL_OIDC_ISSUER,
  vercelOidcResolver,
} from "../../src/vercel-passport/vercel-oidc.ts";

const NOW = 1_800_000_000;
const encoder = new TextEncoder();

const b64 = (value: string | Uint8Array): string =>
  Buffer.from(value).toString("base64url");

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

const jwk = await crypto.subtle.exportKey("jwk", pair.publicKey);

const jwks = {
  keys: [
    {
      kty: "RSA",
      n: jwk.n ?? "",
      e: jwk.e ?? "",
      kid: "k1",
      alg: "RS256",
      use: "sig",
    },
  ],
};

async function sign(claims: Record<string, unknown>): Promise<string> {
  const head = b64(JSON.stringify({ alg: "RS256", kid: "k1" }));
  const body = b64(JSON.stringify(claims));

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    pair.privateKey,
    encoder.encode(`${head}.${body}`),
  );

  return `${head}.${body}.${b64(new Uint8Array(signature))}`;
}

const claims = (extra: Record<string, unknown> = {}) => ({
  iss: `${VERCEL_OIDC_ISSUER}/acme`,
  sub: "owner:acme:project:app:environment:production",
  aud: "https://vercel.com/acme",
  owner_id: "team_1",
  project_id: "prj_1",
  environment: "production",
  iat: NOW - 10,
  exp: NOW + 600,
  ...extra,
});

const resolver = (
  extra: Partial<Parameters<typeof vercelOidcResolver>[0]> = {},
) =>
  vercelOidcResolver({
    projectId: "prj_1",
    environment: "production",
    jwks,
    now: () => NOW * 1000,
    map: (verified) => ({
      name: `deploy:${verified.project_id}`,
      scopes: ["orders.read"],
      organizationId: "org_1",
    }),
    ...extra,
  });

const request = (token?: string, headers: Record<string, string> = {}) =>
  new Request("https://api.test/x", {
    headers: token ? { authorization: `Bearer ${token}`, ...headers } : headers,
  });

describe("vercelOidcResolver", () => {
  beforeEach(() => {
    clearJwksCache();
  });

  it("resolves a verified deployment token to the mapped service account", async () => {
    const state = await resolver().resolve(request(await sign(claims())));

    expect(state).toMatchObject({
      kind: "apiKey",
      keyId: "owner:acme:project:app:environment:production",
      name: "deploy:prj_1",
      organizationId: "org_1",
      scopes: ["orders.read"],
      claims: {
        role: "authenticated",
        api_key: { scopes: ["orders.read"], organization_id: "org_1" },
        vercel_oidc: { project_id: "prj_1", environment: "production" },
      },
    });
  });

  it("falls through for requests without a Vercel token", async () => {
    const other = await sign(claims({ iss: "https://elsewhere.test" }));

    expect(await resolver().resolve(request())).toBeUndefined();
    expect(await resolver().resolve(request(other))).toBeUndefined();
    expect(await resolver().resolve(request("not-a-jwt"))).toBeUndefined();
  });

  it.each([
    ["another project", { project_id: "prj_2" }],
    ["another environment", { environment: "preview" }],
    ["another team", { owner_id: "team_2" }],
    ["an expired token", { exp: NOW - 100 }],
    ["a token not valid yet", { nbf: NOW + 600 }],
  ])("rejects %s", async (_name, extra) => {
    const state = await resolver({ ownerId: "team_1" }).resolve(
      request(await sign(claims(extra))),
    );

    expect(state).toMatchObject({
      kind: "invalid",
      error: { kind: "unauthorized", hint: "VERCEL_OIDC_CLAIMS" },
    });
  });

  it("rejects another audience", async () => {
    const state = await resolver({
      audience: "https://vercel.com/other",
    }).resolve(request(await sign(claims())));

    expect(state).toMatchObject({ kind: "invalid" });
  });

  it("rejects a token signed with another key", async () => {
    const other = await crypto.subtle.generateKey(
      {
        name: "RSASSA-PKCS1-v1_5",
        modulusLength: 2048,
        publicExponent: new Uint8Array([1, 0, 1]),
        hash: "SHA-256",
      },
      true,
      ["sign", "verify"],
    );

    const head = b64(JSON.stringify({ alg: "RS256", kid: "k1" }));
    const body = b64(JSON.stringify(claims()));

    const signature = await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      other.privateKey,
      encoder.encode(`${head}.${body}`),
    );

    const state = await resolver().resolve(
      request(`${head}.${body}.${b64(new Uint8Array(signature))}`),
    );

    expect(state).toMatchObject({ kind: "invalid" });
  });

  it("refuses a deployment that map leaves out", async () => {
    const state = await resolver({ map: () => undefined }).resolve(
      request(await sign(claims())),
    );

    expect(state).toMatchObject({
      kind: "invalid",
      error: { hint: "VERCEL_OIDC_UNMAPPED" },
    });
  });

  it("reports a throwing map as unexpected", async () => {
    const state = await resolver({
      map: () => {
        throw new Error("boom");
      },
    }).resolve(request(await sign(claims())));

    expect(state).toMatchObject({
      kind: "invalid",
      error: { kind: "unexpected", hint: "VERCEL_OIDC_MAP" },
    });
  });

  it("reads another header", async () => {
    const token = await sign(claims());

    const state = await resolver({ header: "x-vercel-oidc-token" }).resolve(
      request(undefined, { "x-vercel-oidc-token": token }),
    );

    expect(state).toMatchObject({ kind: "apiKey" });
  });

  it("needs an owner or audience for any project", async () => {
    const state = await resolver({ projectId: "*" }).resolve(
      request(await sign(claims())),
    );

    expect(state).toMatchObject({
      kind: "invalid",
      error: { hint: "VERCEL_OIDC_OPTIONS" },
    });
  });
});
