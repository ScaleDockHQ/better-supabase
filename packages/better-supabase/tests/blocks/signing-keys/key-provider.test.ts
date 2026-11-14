import { describe, expect, it } from "vitest";

import type { KeyProvider } from "../../../src/blocks/signing-keys/index.ts";

import {
  keyProviderOf,
  vaultKeyProvider,
  vercelKmsKeyProvider,
  verifyCompact,
} from "../../../src/blocks/signing-keys/index.ts";
import {
  FakeKmsError,
  fakeKms,
  signingKeysStore,
} from "../../fixtures/signing-keys.ts";

const OWNER = { type: "organization", id: "o1" };
const DATA = new Uint8Array([1, 2, 3]);

describe("vercelKmsKeyProvider", () => {
  it("picks the issuer per owner and passes token, region and baseUrl", async () => {
    const fake = await fakeKms();

    const provider = vercelKmsKeyProvider(fake.kms, {
      issuer: (owner) => `iss_${owner.id}`,
      token: () => Promise.resolve("oidc"),
      region: "fra1",
      baseUrl: "https://kms.test/v1",
    });

    expect(provider).toMatchObject({ apiVersion: 1, name: "vercel-kms" });
    expect("noteExp" in provider).toBe(false);
    await provider.sign({ owner: OWNER, data: DATA }).orThrow();
    await provider
      .sign({ owner: { type: "app", id: "a2" }, data: DATA })
      .orThrow();

    expect(fake.calls).toEqual([
      {
        issuerId: "iss_o1",
        token: "oidc",
        region: "fra1",
        baseUrl: "https://kms.test/v1",
        message: DATA,
      },
      {
        issuerId: "iss_a2",
        token: "oidc",
        region: "fra1",
        baseUrl: "https://kms.test/v1",
        message: DATA,
      },
    ]);
  });

  it("leaves out the options the app does not set and ignores create", async () => {
    const fake = await fakeKms();
    const provider = vercelKmsKeyProvider(fake.kms, { issuer: "iss_1" });

    await provider
      .sign({ owner: OWNER, data: DATA, create: "Ed25519" })
      .orThrow();

    expect(fake.calls).toEqual([{ issuerId: "iss_1", message: DATA }]);
  });

  it("signs a JWT with ttl null, so KMS adds no exp", async () => {
    const fake = await fakeKms();

    const provider = vercelKmsKeyProvider(fake.kms, {
      issuer: "iss_1",
      token: "oidc",
    });

    const signed = await provider
      .signJwt({
        owner: OWNER,
        claims: { sub: "u1" },
        header: { typ: "JWT", cty: "x" },
      })
      .orThrow();

    expect(fake.calls).toEqual([
      {
        issuerId: "iss_1",
        token: "oidc",
        claims: { sub: "u1" },
        headers: { typ: "JWT", cty: "x" },
        ttl: null,
      },
    ]);
    expect(signed).toMatchObject({ kid: fake.kid, alg: "EdDSA" });

    const verified = await verifyCompact(signed.token, fake.jwks);
    expect(verified.payload).toEqual({ sub: "u1" });
    expect(verified.header).toMatchObject({ typ: "JWT", cty: "x" });
  });

  it.each(["EdDSA", "Ed25519", "ES256", "PS256", "RS256"])(
    "maps the KMS algorithm %s to the JWS alg",
    async (algorithm) => {
      const fake = await fakeKms(algorithm);
      const provider = vercelKmsKeyProvider(fake.kms, { issuer: "iss_1" });

      const signed = await provider
        .sign({ owner: OWNER, data: DATA })
        .orThrow();

      expect(signed).toMatchObject({ kid: fake.kid, alg: algorithm });
    },
  );

  it.each(["es256", "HS256", ""])(
    "refuses the KMS algorithm %j with SIGNING_ALG_UNSUPPORTED",
    async (algorithm) => {
      const fake = await fakeKms(algorithm);
      const provider = vercelKmsKeyProvider(fake.kms, { issuer: "iss_1" });

      for (const result of [
        await provider.sign({ owner: OWNER, data: DATA }),
        await provider.signJwt({ owner: OWNER, claims: {}, header: {} }),
      ]) {
        expect(result.ok).toBe(false);
        expect(!result.ok && result.error).toMatchObject({
          kind: "unexpected",
          hint: "SIGNING_ALG_UNSUPPORTED",
        });
      }
    },
  );

  it.each([
    [404, { kind: "not_found", hint: "SIGNING_KEY_MISSING" }],
    [401, { kind: "forbidden" }],
    [403, { kind: "forbidden" }],
    [429, { kind: "rate_limited" }],
    [500, { kind: "network" }],
    [400, { kind: "network" }],
  ] as const)(
    "maps a KMS %i to a DbError without throwing",
    async (status, expected) => {
      const fake = await fakeKms();
      fake.fail(new FakeKmsError(status, "issuer_error"));
      const provider = vercelKmsKeyProvider(fake.kms, { issuer: "iss_1" });

      for (const result of [
        await provider.sign({ owner: OWNER, data: DATA }),
        await provider.signJwt({ owner: OWNER, claims: {}, header: {} }),
      ]) {
        expect(!result.ok && result.error).toMatchObject({
          ...expected,
          code: "issuer_error",
        });
      }
    },
  );

  it("carries retryAfter on a 429 and maps a failed fetch to network", async () => {
    const fake = await fakeKms();
    fake.fail(new FakeKmsError(429, "rate_limited", { retryAfter: 30 }));
    const provider = vercelKmsKeyProvider(fake.kms, { issuer: "iss_1" });
    const limited = await provider.sign({ owner: OWNER, data: DATA });
    expect(!limited.ok && limited.error).toMatchObject({ retryAfter: 30 });

    fake.fail(new TypeError("fetch failed"));
    const down = await provider.sign({ owner: OWNER, data: DATA });
    expect(!down.ok && down.error.kind).toBe("network");

    const failingToken = vercelKmsKeyProvider(fake.kms, {
      issuer: "iss_1",
      token: () => {
        throw new Error("no OIDC token");
      },
    });

    const noToken = await failingToken.sign({ owner: OWNER, data: DATA });
    expect(!noToken.ok && noToken.error.kind).toBe("network");
  });

  it("never receives private key material", async () => {
    const fake = await fakeKms();
    const provider = vercelKmsKeyProvider(fake.kms, { issuer: "iss_1" });
    await provider
      .sign({ owner: OWNER, data: DATA, create: "ES256" })
      .orThrow();

    await provider
      .signJwt({ owner: OWNER, claims: { sub: "u1" }, header: { typ: "JWT" } })
      .orThrow();

    const sent = JSON.stringify(fake.calls);
    expect(sent).not.toMatch(/"d"|private|jwk/i);
    expect(Object.keys(fake.calls[0] ?? {}).toSorted()).toEqual([
      "issuerId",
      "message",
    ]);
  });
});

describe("vaultKeyProvider", () => {
  it("signs with the stored key and notes an exp", async () => {
    const t = signingKeysStore();
    const provider = vaultKeyProvider({ transport: t });
    expect(provider).toMatchObject({ apiVersion: 1, name: "vault" });

    const signed = await provider
      .sign({ owner: OWNER, data: DATA, create: "ES256" })
      .orThrow();

    expect(signed).toMatchObject({ kid: t.rows[0]!.kid, alg: "ES256" });

    expect(
      await provider
        .noteExp?.({
          kid: signed.kid,
          exp: Temporal.Instant.fromEpochMilliseconds(0),
        })
        .orThrow(),
    ).toBe(true);
    expect(t.calls.map(([fn]) => fn)).toEqual([
      "signing_key",
      "add_signing_key",
      "signing_key",
      "note_signing_key_exp",
    ]);
  });
});

describe("keyProviderOf", () => {
  it("returns a provider of API 1 and refuses another version", async () => {
    const provider = vercelKmsKeyProvider((await fakeKms()).kms, {
      issuer: "iss_1",
    });

    expect(keyProviderOf(provider)).toBe(provider);
    // SAFETY: simulates a provider built for a newer contract.
    const newer = { ...provider, apiVersion: 2 } as unknown as KeyProvider;
    expect(() => keyProviderOf(newer)).toThrow(/key provider API 2/);
  });
});
