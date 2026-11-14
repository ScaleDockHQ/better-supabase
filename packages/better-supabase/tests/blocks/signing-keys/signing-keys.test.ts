import { describe, expect, it } from "vitest";

import type { KeyProvider } from "../../../src/blocks/signing-keys/index.ts";

import {
  createSigningKeys,
  jwksOf,
  jwtType,
  PLATFORM_OWNER,
  vaultKeyProvider,
  vercelKmsKeyProvider,
  verifyCompact,
} from "../../../src/blocks/signing-keys/index.ts";
import { fromBase64 } from "../../../src/core/base64.ts";
import { AsyncResult } from "../../../src/core/result.ts";
import {
  fakeKms,
  signingKeysStore as store,
} from "../../fixtures/signing-keys.ts";

const OWNER = { type: "organization", id: "o1" };

describe("signing-keys block", () => {
  it("creates a key, keeps the private JWK out of the result and publishes the public one", async () => {
    const t = store();
    const keys = createSigningKeys({ transport: t });
    const created = await keys.create({ owner: OWNER }).orThrow();
    expect(created.alg).toBe("Ed25519");
    expect(created.publicKey).not.toHaveProperty("d");
    expect(JSON.parse(t.rows[0]!.privateJwk)).toHaveProperty("d");
    const jwks = await keys.jwks({ owner: OWNER }).orThrow();
    expect(jwks.keys.map((key) => key.kid)).toEqual([created.kid]);
  });

  it("signs a JWT that verifies against the JWKS and notes its exp once per hour", async () => {
    const t = store();
    const keys = createSigningKeys({ transport: t });
    const signer = keys.signer({ owner: OWNER, create: "Ed25519" });
    const exp = 1_900_000_000;
    const token = await signer.signJwt({ sub: "u1", exp }).orThrow();
    await signer.signJwt({ sub: "u2", exp: exp + 60 }).orThrow();
    const jwks = jwksOf(await keys.jwks({ owner: OWNER }).orThrow());
    const verified = await verifyCompact(token, jwks);
    expect(verified.header).toMatchObject({ alg: "EdDSA", typ: "JWT" });
    expect(verified.payload).toMatchObject({ sub: "u1" });
    const notes = t.calls.filter(([fn]) => fn === "note_signing_key_exp");
    expect(notes).toHaveLength(1);
    expect(notes[0]![1]["exp"]).toBe(
      Temporal.Instant.fromEpochMilliseconds(
        Math.ceil(exp / 3600) * 3600 * 1000,
      ).toString(),
    );
  });

  it("signs a custom typ that verifyCompact then requires", async () => {
    const t = store();
    const keys = createSigningKeys({ transport: t });
    const signer = keys.signer({ owner: OWNER, create: "Ed25519" });
    const typ = jwtType("invite");
    expect(typ).toBe("vnd.invite+jwt");
    const token = await signer.signJwt({ sub: "u1" }, { typ }).orThrow();
    const jwks = jwksOf(await keys.jwks({ owner: OWNER }).orThrow());
    expect((await verifyCompact(token, jwks, { typ })).header).toMatchObject({
      typ,
    });
    await expect(
      verifyCompact(token, jwks, { typ: jwtType("other") }),
    ).rejects.toMatchObject({ code: "JWS_TYP" });
  });

  it("refuses a typ that is not a JWT media type and a bad type name", async () => {
    const keys = createSigningKeys({ transport: store() });
    const signer = keys.signer({ owner: OWNER, create: "Ed25519" });
    const result = await signer.signJwt({ sub: "u1" }, { typ: "invite" });
    expect(result.ok).toBe(false);
    expect(() => jwtType("Bad Name")).toThrow(TypeError);
    expect(PLATFORM_OWNER).toEqual({ type: "platform", id: "default" });
  });

  it("rotates with the active key's type and keeps the retired kid published", async () => {
    const t = store();
    const keys = createSigningKeys({ transport: t, ed25519Alg: "Ed25519" });
    const first = await keys.create({ owner: OWNER, alg: "ES256" }).orThrow();
    const second = await keys.rotate({ owner: OWNER }).orThrow();
    expect(second).toMatchObject({ alg: "ES256", retired: first.kid });

    const signed = await keys
      .signer({ owner: OWNER })
      .sign(new Uint8Array([1, 2, 3]))
      .orThrow();

    expect(signed).toMatchObject({ kid: second.kid, alg: "ES256" });
    expect(signed.signature).toHaveLength(64);
    const jwks = await keys.jwks({ owner: OWNER }).orThrow();
    expect(jwks.keys.map((key) => key.kid)).toEqual([first.kid, second.kid]);
  });

  it("fails with SIGNING_KEY_MISSING when the owner has no key", async () => {
    const result = await createSigningKeys({ transport: store() })
      .signer({ owner: OWNER })
      .sign(new Uint8Array([1]));

    expect(result.ok).toBe(false);
    expect(!result.ok && result.error.hint).toBe("SIGNING_KEY_MISSING");
  });

  it("serves the JWKS with a JWK Set content type and a cache lifetime", async () => {
    const t = store();
    const keys = createSigningKeys({ transport: t });
    await keys.create({ owner: OWNER }).orThrow();
    const response = await keys.jwksResponse({ owner: OWNER, maxAge: 60 });
    expect(response.headers.get("content-type")).toBe(
      "application/jwk-set+json",
    );
    expect(response.headers.get("cache-control")).toBe("public, max-age=60");
    expect(await response.json()).toMatchObject({ keys: [{ use: "sig" }] });
  });

  it("passes a grace period to the JWKS and the purge as an interval", async () => {
    const t = store();
    const keys = createSigningKeys({ transport: t });
    await keys
      .purge({ grace: Temporal.Duration.from({ minutes: 10 }) })
      .orThrow();
    await keys.jwks({ owner: OWNER }).orThrow();
    expect(t.calls).toEqual([
      ["purge_signing_keys", { grace: "600 seconds" }],
      [
        "signing_jwks",
        { owner_type: "organization", owner_id: "o1", grace: null },
      ],
    ]);
  });

  it("retires and removes keys, and drops them from the signer cache", async () => {
    const t = store();
    const keys = createSigningKeys({ transport: t });
    const signer = keys.signer({ owner: OWNER, create: "Ed25519" });
    const first = await signer.sign(new Uint8Array([1])).orThrow();
    await signer.sign(new Uint8Array([2])).orThrow();
    expect(t.calls.filter(([fn]) => fn === "signing_key")).toHaveLength(2);
    expect(await keys.retire(first.kid).orThrow()).toBe(true);
    expect(await keys.retire(first.kid).orThrow()).toBe(false);
    const next = await signer.sign(new Uint8Array([3])).orThrow();
    expect(next.kid).not.toBe(first.kid);
    expect(await keys.remove(OWNER).orThrow()).toBe(0);
  });

  it("rotates an owner without a key to Ed25519, and to the type it is given", async () => {
    const keys = createSigningKeys({ transport: store() });
    expect((await keys.rotate({ owner: OWNER }).orThrow()).alg).toBe("Ed25519");
    expect(
      (await keys.rotate({ owner: OWNER, alg: "ES256" }).orThrow()).alg,
    ).toBe("ES256");
  });

  it("refuses a stored key that is not a JWK", async () => {
    const t = store();
    t.rows.push({
      owner: "organization:o1",
      kid: "k1",
      alg: "Ed25519",
      publicJwk: {},
      privateJwk: "[]",
      state: "active",
    });

    const result = await createSigningKeys({ transport: t })
      .signer({ owner: OWNER })
      .signJwt({ sub: "u1" });

    expect(result.ok).toBe(false);
  });

  it("answers 503 problem details when the key set can't be read", async () => {
    const keys = createSigningKeys({
      transport: { call: () => Promise.reject(new Error("down")) },
    });

    const response = await keys.jwksResponse({ owner: OWNER });
    expect(response.status).toBe(503);
    expect(response.headers.get("content-type")).toBe(
      "application/problem+json",
    );
  });
});

/** A provider that records its calls and signs nothing real. */
function recordingProvider(withNoteExp: boolean) {
  const calls: [string, unknown][] = [];

  const provider: KeyProvider = {
    apiVersion: 1,
    name: "recording",
    sign: (input) => {
      calls.push(["sign", input]);

      return AsyncResult.ok({
        kid: "k1",
        alg: "ES256",
        signature: new Uint8Array([1]),
      });
    },
    signJwt: (input) => {
      calls.push(["signJwt", input]);

      return AsyncResult.ok({ token: "a.b.c", kid: "k1", alg: "ES256" });
    },
    ...(withNoteExp
      ? {
          noteExp: (input: { kid: string; exp: Temporal.Instant }) => {
            calls.push(["noteExp", input]);

            return AsyncResult.ok(true);
          },
        }
      : {}),
  };

  return { provider, calls };
}

describe("signing-keys with a key provider", () => {
  it("keeps the Vault path's SQL calls, their order and the header", async () => {
    const t = store();

    const signer = createSigningKeys({ transport: t }).signer({
      owner: OWNER,
      create: "Ed25519",
    });

    const token = await signer
      .signJwt({ sub: "u1", exp: 1_900_000_000 }, { cty: "x" })
      .orThrow();

    expect(t.calls.map(([fn]) => fn)).toEqual([
      "signing_key",
      "add_signing_key",
      "signing_key",
      "note_signing_key_exp",
    ]);
    expect(
      new TextDecoder().decode(fromBase64(token.split(".")[0] ?? "")),
    ).toBe(
      JSON.stringify({
        alg: "EdDSA",
        kid: t.rows[0]!.kid,
        typ: "JWT",
        cty: "x",
      }),
    );
  });

  it("signs through the provider, with typ, create and the claims", async () => {
    const t = store();
    const { provider, calls } = recordingProvider(true);

    const signer = createSigningKeys({ transport: t, keys: provider }).signer({
      owner: OWNER,
      create: "ES256",
    });

    expect(await signer.signJwt({ sub: "u1" }).orThrow()).toBe("a.b.c");
    expect(
      (await signer.sign(new Uint8Array([9])).orThrow()).signature,
    ).toEqual(new Uint8Array([1]));
    expect(calls).toEqual([
      [
        "signJwt",
        {
          owner: OWNER,
          claims: { sub: "u1" },
          header: { typ: "JWT" },
          create: "ES256",
        },
      ],
      ["sign", { owner: OWNER, data: new Uint8Array([9]), create: "ES256" }],
    ]);
    expect(t.calls).toEqual([]);
  });

  it("notes the exp through the provider once per hour, and not at all without noteExp", async () => {
    const exp = 1_900_000_000;
    const noting = recordingProvider(true);

    const signer = createSigningKeys({
      transport: store(),
      keys: noting.provider,
    }).signer({ owner: OWNER });

    await signer.signJwt({ exp }).orThrow();
    await signer.signJwt({ exp: exp + 60 }).orThrow();
    expect(noting.calls.filter(([name]) => name === "noteExp")).toEqual([
      [
        "noteExp",
        {
          kid: "k1",
          exp: Temporal.Instant.fromEpochMilliseconds(
            Math.ceil(exp / 3600) * 3600 * 1000,
          ),
        },
      ],
    ]);

    const t = store();
    const plain = recordingProvider(false);

    await createSigningKeys({ transport: t, keys: plain.provider })
      .signer({ owner: OWNER })
      .signJwt({ exp })
      .orThrow();

    expect(plain.calls.map(([name]) => name)).toEqual(["signJwt"]);
    expect(t.calls).toEqual([]);
  });

  it("refuses a bad typ before the provider is called", async () => {
    const { provider, calls } = recordingProvider(true);

    const result = await createSigningKeys({
      transport: store(),
      keys: provider,
    })
      .signer({ owner: OWNER })
      .signJwt({ sub: "u1" }, { typ: "invite" });

    expect(!result.ok && result.error.hint).toBe("SIGNING_TYP_INVALID");
    expect(calls).toEqual([]);
  });

  it("signs with Vercel KMS and leaves the Vault keys alone", async () => {
    const t = store();
    const fake = await fakeKms();

    const keys = createSigningKeys({
      transport: t,
      keys: vercelKmsKeyProvider(fake.kms, { issuer: "iss_1" }),
    });

    const signer = keys.signer({ owner: OWNER, create: "Ed25519" });

    const token = await signer
      .signJwt({ sub: "u1", exp: 1_900_000_000 })
      .orThrow();

    const verified = await verifyCompact(token, fake.jwks, { typ: "JWT" });
    expect(verified.header).toMatchObject({ kid: fake.kid, alg: "EdDSA" });
    expect(t.calls).toEqual([]);

    await keys.create({ owner: OWNER }).orThrow();
    expect(t.calls.map(([fn]) => fn)).toEqual(["add_signing_key"]);
  });

  it("clears the cache of a Vault provider the app passes", async () => {
    const t = store();

    const keys = createSigningKeys({
      transport: t,
      keys: vaultKeyProvider({ transport: t }),
    });

    const signer = keys.signer({ owner: OWNER, create: "Ed25519" });
    const first = await signer.sign(new Uint8Array([1])).orThrow();
    await keys.rotate({ owner: OWNER }).orThrow();
    const next = await signer.sign(new Uint8Array([2])).orThrow();
    expect(next.kid).not.toBe(first.kid);
  });

  it("refuses a provider built for another apiVersion", () => {
    expect(() =>
      createSigningKeys({
        transport: store(),
        // SAFETY: simulates a provider built for a newer contract.
        keys: { ...recordingProvider(false).provider, apiVersion: 2 as never },
      }),
    ).toThrow(TypeError);
  });
});
