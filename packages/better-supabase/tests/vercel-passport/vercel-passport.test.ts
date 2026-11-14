import { beforeEach, describe, expect, it, vi } from "vitest";

import type { VerifyPassportOptions } from "../../src/vercel-passport/vercel-passport.ts";

import { clearJwksCache } from "../../src/core/jwks-cache.ts";
import {
  PASSPORT_HEADER,
  PASSPORT_ISSUER,
  PASSPORT_JWKS_URL,
  verifyPassport,
} from "../../src/vercel-passport/vercel-passport.ts";

const NOW = 1_800_000_000;
const encoder = new TextEncoder();

const b64 = (value: string | Uint8Array): string =>
  Buffer.from(value).toString("base64url");

async function rsaKey(kid: string) {
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

  const sign = async (
    claims: Record<string, unknown>,
    header: Record<string, unknown> = {},
  ): Promise<string> => {
    const head = b64(JSON.stringify({ alg: "RS256", kid, ...header }));
    const body = b64(JSON.stringify(claims));

    const signature = await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      pair.privateKey,
      encoder.encode(`${head}.${body}`),
    );

    return `${head}.${body}.${b64(new Uint8Array(signature))}`;
  };

  return {
    sign,
    publicJwk: {
      kty: "RSA",
      n: jwk.n ?? "",
      e: jwk.e ?? "",
      kid,
      alg: "RS256",
      use: "sig",
    },
  };
}

const key = await rsaKey("k1");
const rotated = await rsaKey("k2");

const claims = (extra: Record<string, unknown> = {}) => ({
  typ: "passport",
  iss: `${PASSPORT_ISSUER}/acme`,
  sub: "owner:acme:connector:okta:principal:u-1",
  aud: "https://vercel.com/acme/app/production",
  owner: "acme",
  owner_id: "team_1",
  project: "app",
  project_id: "prj_1",
  environment: "production",
  connector_id: "okta",
  external_iss: "https://acme.okta.com",
  external_sub: "u-1",
  email: "ada@acme.test",
  iat: NOW - 10,
  exp: NOW + 600,
  ...extra,
});

function jwksServer(keys: readonly object[]) {
  let served = keys;

  const fetch = vi.fn<typeof globalThis.fetch>(async () =>
    Response.json({ keys: served }),
  );

  return {
    fetch,
    serve: (next: readonly object[]) => {
      served = next;
    },
  };
}

const withHeader = (token: string, name = PASSPORT_HEADER) =>
  new Request("https://app.test/api/me", { headers: { [name]: token } });

const withBearer = (token: string) =>
  withHeader(`Bearer ${token}`, "authorization");

function optionsFor(
  extra: Partial<VerifyPassportOptions<unknown>> = {},
): VerifyPassportOptions<unknown> {
  return {
    projectId: "prj_1",
    environment: "production",
    fetch: jwksServer([key.publicJwk]).fetch,
    now: () => NOW * 1000,
    ...extra,
  };
}

beforeEach(() => {
  clearJwksCache();
});

describe("verifyPassport", () => {
  it("verifies the Passport header and returns the claims", async () => {
    const server = jwksServer([key.publicJwk]);
    const token = await key.sign(claims());

    const result = await verifyPassport(
      withHeader(token),
      optionsFor({ fetch: server.fetch }),
    );

    expect(result).toMatchObject({
      ok: true,
      data: {
        claims: { sub: claims().sub, external_sub: "u-1", owner: "acme" },
        user: undefined,
      },
    });
    expect(String(server.fetch.mock.calls[0]?.[0])).toBe(PASSPORT_JWKS_URL);
  });

  it("reads a forwarded bearer token, and only the source asked for", async () => {
    const token = await key.sign(claims());

    expect((await verifyPassport(withBearer(token), optionsFor())).ok).toBe(
      true,
    );
    expect(
      (
        await verifyPassport(
          withBearer(token),
          optionsFor({ headers: "bearer" }),
        )
      ).ok,
    ).toBe(true);
    expect(
      await verifyPassport(
        withBearer(token),
        optionsFor({ headers: "passport" }),
      ),
    ).toMatchObject({
      ok: false,
      error: { kind: "unauthorized", code: "MISSING_CREDENTIALS" },
    });
    expect(
      await verifyPassport(
        withHeader(token),
        optionsFor({ headers: "bearer" }),
      ),
    ).toMatchObject({ ok: false, error: { code: "MISSING_CREDENTIALS" } });
  });

  it("prefers the Passport header over another bearer token", async () => {
    const token = await key.sign(claims());

    const request = new Request("https://app.test/", {
      headers: {
        [PASSPORT_HEADER]: token,
        authorization: "Bearer a-supabase-token",
      },
    });

    expect((await verifyPassport(request, optionsFor())).ok).toBe(true);
  });

  it("answers MISSING_CREDENTIALS without a token", async () => {
    expect(
      await verifyPassport(new Request("https://app.test/"), optionsFor()),
    ).toMatchObject({
      ok: false,
      error: { kind: "unauthorized", code: "MISSING_CREDENTIALS", status: 401 },
    });
  });

  it("refuses a token signed by another key or with another alg", async () => {
    const foreign = await rsaKey("k1");

    expect(
      await verifyPassport(
        withHeader(await foreign.sign(claims())),
        optionsFor(),
      ),
    ).toMatchObject({
      ok: false,
      error: { kind: "unauthorized", hint: "PASSPORT_TOKEN" },
    });

    expect(
      await verifyPassport(
        withHeader(await key.sign(claims(), { alg: "PS256" })),
        optionsFor(),
      ),
    ).toMatchObject({ ok: false, error: { hint: "PASSPORT_TOKEN" } });

    expect(
      await verifyPassport(withHeader("not.a.jwt"), optionsFor()),
    ).toMatchObject({ ok: false, error: { hint: "PASSPORT_TOKEN" } });
  });

  it.each([
    ["a wrong typ", { typ: "access" }],
    ["no typ", { typ: undefined }],
    ["another issuer", { iss: "https://oidc.vercel.com/acme" }],
    [
      "an issuer that only starts like Passport's",
      { iss: `${PASSPORT_ISSUER}.evil` },
    ],
    ["no issuer", { iss: undefined }],
    ["no sub", { sub: undefined }],
    ["an empty sub", { sub: "" }],
    ["no owner", { owner: undefined }],
    ["no connector_id", { connector_id: undefined }],
    ["no external_sub", { external_sub: undefined }],
    ["no exp", { exp: undefined }],
    ["an expired exp", { exp: NOW - 31 }],
    ["an nbf in the future", { nbf: NOW + 31 }],
    ["an nbf that is not a number", { nbf: "soon" }],
  ])("refuses a token with %s", async (_, extra) => {
    const token = await key.sign(claims(extra));

    expect(await verifyPassport(withHeader(token), optionsFor())).toMatchObject(
      { ok: false, error: { kind: "unauthorized", hint: "PASSPORT_CLAIMS" } },
    );
  });

  it("accepts the bare issuer and exp or nbf inside the leeway", async () => {
    const token = await key.sign(
      claims({ iss: PASSPORT_ISSUER, exp: NOW - 20, nbf: NOW + 20 }),
    );

    expect((await verifyPassport(withHeader(token), optionsFor())).ok).toBe(
      true,
    );
    expect(
      (await verifyPassport(withHeader(token), optionsFor({ leeway: 0 }))).ok,
    ).toBe(false);
  });

  it("matches the project against one id, a list or *", async () => {
    const token = await key.sign(claims());

    const verify = (extra: Partial<VerifyPassportOptions<unknown>>) =>
      verifyPassport(withHeader(token), optionsFor(extra));

    expect((await verify({ projectId: ["prj_0", "prj_1"] })).ok).toBe(true);
    expect((await verify({ projectId: "*", ownerId: "team_1" })).ok).toBe(true);
    expect(await verify({ projectId: "prj_2" })).toMatchObject({
      ok: false,
      error: { hint: "PASSPORT_CLAIMS" },
    });
    expect(await verify({ projectId: ["prj_2"] })).toMatchObject({
      ok: false,
      error: { hint: "PASSPORT_CLAIMS" },
    });
  });

  it("matches the environment against one name, a list or *, and any by default", async () => {
    const token = await key.sign(claims({ environment: "preview" }));

    const verify = (extra: Partial<VerifyPassportOptions<unknown>>) =>
      verifyPassport(withHeader(token), optionsFor(extra));

    expect((await verify({ environment: "production" })).ok).toBe(false);
    expect((await verify({ environment: ["production", "preview"] })).ok).toBe(
      true,
    );
    expect((await verify({ environment: "*" })).ok).toBe(true);

    const { environment: _, ...withoutEnvironment } = optionsFor();
    expect(
      (await verifyPassport(withHeader(token), withoutEnvironment)).ok,
    ).toBe(true);
  });

  it("checks the owner and the audience", async () => {
    const token = await key.sign(claims());

    const listed = await key.sign(
      claims({ aud: ["https://a.test", "https://b.test"] }),
    );

    const verify = (
      jwt: string,
      extra: Partial<VerifyPassportOptions<unknown>>,
    ) => verifyPassport(withHeader(jwt), optionsFor(extra));

    expect((await verify(token, { ownerId: "team_1" })).ok).toBe(true);
    expect((await verify(token, { ownerId: "team_2" })).ok).toBe(false);
    expect(
      (
        await verify(token, {
          audience: "https://vercel.com/acme/app/production",
        })
      ).ok,
    ).toBe(true);
    expect((await verify(token, { audience: "https://other.test" })).ok).toBe(
      false,
    );
    expect((await verify(listed, { audience: ["https://b.test"] })).ok).toBe(
      true,
    );
    expect(await verify(listed, { audience: "https://c.test" })).toMatchObject({
      ok: false,
      error: { hint: "PASSPORT_CLAIMS" },
    });
  });

  it("needs a projectId, and an owner or audience with *", async () => {
    const token = await key.sign(claims());

    for (const extra of [
      { projectId: "" },
      { projectId: [] },
      { projectId: "*" },
      { projectId: "*", audience: [] },
    ]) {
      expect(
        await verifyPassport(withHeader(token), optionsFor(extra)),
      ).toMatchObject({
        ok: false,
        error: { kind: "unexpected", hint: "PASSPORT_OPTIONS" },
      });
    }

    expect(
      (
        await verifyPassport(
          withHeader(token),
          optionsFor({ projectId: "*", audience: claims().aud }),
        )
      ).ok,
    ).toBe(true);
  });

  it("refetches the key set once for an unknown kid", async () => {
    const server = jwksServer([key.publicJwk]);
    const options = optionsFor({ fetch: server.fetch });

    expect(
      (await verifyPassport(withHeader(await key.sign(claims())), options)).ok,
    ).toBe(true);

    server.serve([key.publicJwk, rotated.publicJwk]);

    const later = optionsFor({
      fetch: server.fetch,
      now: () => (NOW + 60) * 1000,
    });

    expect(
      (await verifyPassport(withHeader(await rotated.sign(claims())), later))
        .ok,
    ).toBe(true);
    expect(server.fetch).toHaveBeenCalledTimes(2);
  });

  it("passes a failed key set fetch through", async () => {
    const down = vi.fn<typeof globalThis.fetch>(
      async () => new Response("", { status: 503 }),
    );

    expect(
      await verifyPassport(
        withHeader(await key.sign(claims())),
        optionsFor({ fetch: down }),
      ),
    ).toMatchObject({
      ok: false,
      error: { kind: "network", code: "JWKS_FETCH_FAILED" },
    });
  });

  it("verifies with inline keys and a shared store", async () => {
    const token = await key.sign(claims());
    const unused = vi.fn<typeof globalThis.fetch>();

    expect(
      (
        await verifyPassport(
          withHeader(token),
          optionsFor({ jwks: { keys: [key.publicJwk] }, fetch: unused }),
        )
      ).ok,
    ).toBe(true);

    const store = {
      get: vi.fn(async () => ({
        keys: { keys: [key.publicJwk] },
        at: NOW * 1000 - 1000,
      })),
      set: vi.fn(async () => undefined),
    };

    expect(
      (
        await verifyPassport(
          withHeader(token),
          optionsFor({ store, fetch: unused }),
        )
      ).ok,
    ).toBe(true);
    expect(unused).not.toHaveBeenCalled();
    expect(store.get).toHaveBeenCalledWith(
      `better-supabase:jwks:${PASSPORT_JWKS_URL}`,
    );
  });

  it("calls resolveUser with the issuer, subject and claims", async () => {
    const token = await key.sign(claims());

    const resolveUser = vi.fn(
      async ({ claims: verified }: { claims: { external_sub?: string } }) =>
        verified.external_sub === "u-1" ? { id: "profile-1" } : undefined,
    );

    const result = await verifyPassport(withHeader(token), {
      ...optionsFor(),
      resolveUser,
    });

    expect(result).toMatchObject({
      ok: true,
      data: { user: { id: "profile-1" } },
    });
    expect(resolveUser).toHaveBeenCalledWith({
      iss: `${PASSPORT_ISSUER}/acme`,
      sub: claims().sub,
      claims: expect.objectContaining({ connector_id: "okta" }),
    });
  });

  it("keeps an unknown user as undefined", async () => {
    const result = await verifyPassport(withHeader(await key.sign(claims())), {
      ...optionsFor(),
      resolveUser: () => undefined,
    });

    expect(result).toMatchObject({ ok: true, data: { user: undefined } });
  });

  it("turns a throwing resolveUser into an unexpected error", async () => {
    const result = await verifyPassport(withHeader(await key.sign(claims())), {
      ...optionsFor(),
      resolveUser: () => {
        throw new Error("profiles table is gone");
      },
    });

    expect(result).toMatchObject({
      ok: false,
      error: {
        kind: "unexpected",
        hint: "PASSPORT_RESOLVE_USER",
        message: "resolveUser failed: profiles table is gone",
      },
    });
  });

  it("throws only through orThrow", async () => {
    await expect(
      verifyPassport(new Request("https://app.test/"), optionsFor()).orThrow(),
    ).rejects.toMatchObject({ error: { code: "MISSING_CREDENTIALS" } });
  });
});
