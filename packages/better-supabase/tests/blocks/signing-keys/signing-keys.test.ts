import { describe, expect, it } from "vitest";

import {
  createSigningKeys,
  jwksOf,
  verifyCompact,
} from "../../../src/blocks/signing-keys/index.ts";

interface Row {
  owner: string;
  kid: string;
  alg: string;
  publicJwk: Record<string, unknown>;
  privateJwk: string;
  state: "active" | "retired";
}

/** The signing-keys module in memory. */
function store() {
  const rows: Row[] = [];
  const calls: [string, Record<string, unknown>][] = [];

  const owner = (args: Record<string, unknown>) =>
    `${String(args["owner_type"])}:${String(args["owner_id"])}`;

  const fns: Record<string, (args: Record<string, unknown>) => unknown> = {
    add_signing_key(args) {
      const previous = rows.find(
        (row) => row.owner === owner(args) && row.state === "active",
      );

      if (previous) {
        previous.state = "retired";
      }

      rows.push({
        owner: owner(args),
        kid: String(args["kid"]),
        alg: String(args["alg"]),
        // SAFETY: the client sends the public JWK as an object.
        publicJwk: args["public_jwk"] as Record<string, unknown>,
        privateJwk: String(args["private_jwk"]),
        state: "active",
      });

      return {
        kid: args["kid"],
        alg: args["alg"],
        retired: previous?.kid ?? null,
      };
    },
    signing_key(args) {
      const row = rows.find(
        (item) => item.owner === owner(args) && item.state === "active",
      );

      return row
        ? { kid: row.kid, alg: row.alg, privateKey: row.privateJwk }
        : null;
    },
    signing_jwks(args) {
      return {
        keys: rows
          .filter((row) => row.owner === owner(args))
          .map((row) => ({ ...row.publicJwk, kid: row.kid, use: "sig" })),
      };
    },
    note_signing_key_exp: (args) => rows.some((row) => row.kid === args["kid"]),
    retire_signing_key(args) {
      const row = rows.find(
        (item) => item.kid === args["kid"] && item.state === "active",
      );

      if (row) {
        row.state = "retired";
      }

      return row !== undefined;
    },
    delete_signing_keys: () => 0,
    purge_signing_keys: () => 0,
  };

  return {
    rows,
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);
      const handler = fns[fn];

      if (!handler) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(handler(args));
    },
  };
}

const OWNER = { type: "organization", id: "o1" };

describe("signing-keys block", () => {
  it("creates a key, keeps the private JWK out of the result and publishes the public one", async () => {
    const t = store();
    const keys = createSigningKeys({ transport: t });
    const created = await keys.create(OWNER).orThrow();
    expect(created.alg).toBe("Ed25519");
    expect(created.publicKey).not.toHaveProperty("d");
    expect(JSON.parse(t.rows[0]!.privateJwk)).toHaveProperty("d");
    const jwks = await keys.jwks(OWNER).orThrow();
    expect(jwks.keys.map((key) => key.kid)).toEqual([created.kid]);
  });

  it("signs a JWT that verifies against the JWKS and notes its exp once per hour", async () => {
    const t = store();
    const keys = createSigningKeys({ transport: t });
    const signer = keys.signer(OWNER, { create: "Ed25519" });
    const exp = 1_900_000_000;
    const token = await signer.signJwt({ sub: "u1", exp }).orThrow();
    await signer.signJwt({ sub: "u2", exp: exp + 60 }).orThrow();
    const jwks = jwksOf(await keys.jwks(OWNER).orThrow());
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

  it("rotates with the active key's type and keeps the retired kid published", async () => {
    const t = store();
    const keys = createSigningKeys({ transport: t, ed25519Alg: "Ed25519" });
    const first = await keys.create(OWNER, "ES256").orThrow();
    const second = await keys.rotate(OWNER).orThrow();
    expect(second).toMatchObject({ alg: "ES256", retired: first.kid });

    const signed = await keys
      .signer(OWNER)
      .sign(new Uint8Array([1, 2, 3]))
      .orThrow();

    expect(signed).toMatchObject({ kid: second.kid, alg: "ES256" });
    expect(signed.signature).toHaveLength(64);
    const jwks = await keys.jwks(OWNER).orThrow();
    expect(jwks.keys.map((key) => key.kid)).toEqual([first.kid, second.kid]);
  });

  it("fails with SIGNING_KEY_MISSING when the owner has no key", async () => {
    const result = await createSigningKeys({ transport: store() })
      .signer(OWNER)
      .sign(new Uint8Array([1]));

    expect(result.ok).toBe(false);
    expect(!result.ok && result.error.hint).toBe("SIGNING_KEY_MISSING");
  });

  it("serves the JWKS with a JWK Set content type and a cache lifetime", async () => {
    const t = store();
    const keys = createSigningKeys({ transport: t });
    await keys.create(OWNER).orThrow();
    const response = await keys.jwksResponse(OWNER, { maxAge: 60 });
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
    await keys.jwks(OWNER).orThrow();
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
    const signer = keys.signer(OWNER, { create: "Ed25519" });
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
    expect((await keys.rotate(OWNER).orThrow()).alg).toBe("Ed25519");
    expect((await keys.rotate(OWNER, "ES256").orThrow()).alg).toBe("ES256");
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
      .signer(OWNER)
      .signJwt({ sub: "u1" });

    expect(result.ok).toBe(false);
  });

  it("answers 503 problem details when the key set can't be read", async () => {
    const keys = createSigningKeys({
      transport: { call: () => Promise.reject(new Error("down")) },
    });

    const response = await keys.jwksResponse(OWNER);
    expect(response.status).toBe(503);
    expect(response.headers.get("content-type")).toBe(
      "application/problem+json",
    );
  });
});
