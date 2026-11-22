import { describe, expect, it } from "vitest";

import type { ChainProof } from "../../../src/blocks/audit/index.ts";

import {
  createChain,
  evidenceBundle,
  verifyChainProof,
  verifyEvidenceBundle,
} from "../../../src/blocks/audit/index.ts";
import {
  generateSigningKey,
  importSigningKey,
  signCompact,
} from "../../../src/core/jws.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const encoder = new TextEncoder();

const hex = (bytes: ArrayBuffer): string =>
  [...new Uint8Array(bytes)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");

async function link(
  hashed: string,
  seq: number,
  prev: string | undefined,
): Promise<ChainProof["entries"][number]> {
  const prior = prev?.match(/../gu)?.map((pair) => Number.parseInt(pair, 16));

  const material = new Uint8Array([
    ...(prior ?? []),
    ...encoder.encode(hashed),
  ]);

  return {
    seq,
    prevHash: prev,
    rowHash: hex(await crypto.subtle.digest("SHA-256", material)),
    entry: { seq },
    hashed,
  };
}

async function signedProof() {
  const first = await link('{"body": "a", "chain_seq": 1}', 1, undefined);
  const second = await link('{"body": "b", "chain_seq": 2}', 2, first.rowHash);
  const key = await generateSigningKey("ES256");

  const signature = await signCompact(
    await importSigningKey(key.privateKey),
    "ES256",
    { alg: "ES256", kid: key.kid },
    { seq: 2, hash: second.rowHash },
  );

  const proof: ChainProof = {
    table: "public.facts",
    tenant: undefined,
    entries: [first, second],
    checkpoint: { seq: 2, hash: second.rowHash, keyId: key.kid, signature },
  };

  return { proof, jwks: { keys: [{ ...key.publicKey, kid: key.kid }] } };
}

describe("verifyChainProof", () => {
  it("accepts a signed proof and refuses a changed row, link or signature", async () => {
    const { proof, jwks } = await signedProof();

    expect(await verifyChainProof(proof, jwks)).toEqual({
      valid: true,
      signed: true,
      checked: 2,
    });

    const [first, second] = proof.entries;

    expect(
      await verifyChainProof(
        {
          ...proof,
          entries: [
            { ...first!, hashed: '{"body": "x", "chain_seq": 1}' },
            second!,
          ],
        },
        jwks,
      ),
    ).toMatchObject({ valid: false, reason: "hash", seq: 1 });

    expect(
      await verifyChainProof(
        { ...proof, entries: [first!, { ...second!, prevHash: "00" }] },
        jwks,
      ),
    ).toMatchObject({ valid: false, reason: "link", seq: 2 });

    const other = await generateSigningKey("ES256");

    expect(
      await verifyChainProof(proof, {
        keys: [{ ...other.publicKey, kid: other.kid }],
      }),
    ).toMatchObject({ valid: false, reason: "signature" });

    expect(
      await verifyChainProof({ ...proof, checkpoint: undefined }, jwks, {
        requireSigned: true,
      }),
    ).toMatchObject({ valid: false, reason: "unsigned" });
  });
});

describe("createChain", () => {
  it("passes the table and tenant column to every call", async () => {
    const calls: [string, Record<string, unknown>][] = [];

    const chain = createChain({
      table: "public.facts",
      tenantColumn: "organization_id",
      transport: {
        call(_schema, fn, args) {
          calls.push([fn, { ...args }]);

          return Promise.resolve(
            fn === "chain_heads"
              ? [{ tenant: "org-1", seq: 2, hash: "ab" }]
              : { valid: true, checked: 0, seq: null, hash: null },
          );
        },
      },
    });

    expect(await chain.heads().orThrow()).toEqual([
      { tenant: "org-1", seq: 2, hash: "ab" },
    ]);
    await chain.verify({ tenant: "org-1" }).orThrow();
    expect(calls[1]).toEqual([
      "verify_chain",
      {
        target: "public.facts",
        tenant_column: "organization_id",
        tenant: "org-1",
      },
    ]);
  });
});

describe("evidence bundles", () => {
  it("seals proofs and refuses a changed bundle", async () => {
    const { proof, jwks } = await signedProof();

    const bundle = await evidenceBundle({
      subject: { type: "filing", id: "f-1" },
      proofs: [proof],
      sections: { shipments: [] },
      generatedAt: "2026-11-05T12:00:00Z",
    });

    expect(await verifyEvidenceBundle(bundle, jwks)).toEqual({
      valid: true,
      proofs: 1,
    });

    expect(
      await verifyEvidenceBundle(
        { ...bundle, sections: { shipments: ["extra"] } },
        jwks,
      ),
    ).toEqual({ valid: false, reason: "bundle" });
  });
});

describe("createChain checkpoints and proofs", () => {
  const token = (header: unknown) =>
    `${btoa(JSON.stringify(header)).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "")}.e30.sig`;

  function chainWith(
    replies: Record<string, (args: Record<string, unknown>) => unknown>,
    signer?: {
      signJwt: (
        claims: Readonly<Record<string, unknown>>,
      ) => AsyncResult<string>;
    },
  ) {
    const calls: [string, Record<string, unknown>][] = [];

    const chain = createChain({
      table: "public.facts",
      issuer: "https://app.test",
      ...(signer === undefined ? {} : { signer }),
      transport: {
        call(_schema, fn, args) {
          calls.push([fn, { ...args }]);

          return Promise.resolve(replies[fn]?.({ ...args }));
        },
      },
    });

    return { chain, calls };
  }

  it("signs every head and records it with the key id of the token", async () => {
    const claims: Readonly<Record<string, unknown>>[] = [];

    const tokens = [
      token({ alg: "ES256", kid: "k1" }),
      "%%%.e30.sig",
      token({ alg: "ES256" }),
    ];

    const { chain, calls } = chainWith(
      {
        chain_heads: () => [
          { tenant: "org-1", seq: 2, hash: "ab" },
          { tenant: null, seq: 5, hash: "cd" },
          { tenant: "org-2", seq: 1, hash: "ef" },
        ],
        record_chain_checkpoint: (args) => ({
          id: `cp-${String(args["seq"])}`,
          tenant: args["tenant"] ?? null,
          seq: args["seq"],
          hash: args["hash"],
          keyId: args["key_id"],
          signature: args["signature"],
        }),
      },
      {
        signJwt: (input) => {
          claims.push(input);

          return AsyncResult.ok(tokens[claims.length - 1] ?? "");
        },
      },
    );

    const made = await chain.checkpoint().orThrow();

    expect(made.map((each) => [each.id, each.keyId])).toEqual([
      ["cp-2", "k1"],
      ["cp-5", ""],
      ["cp-1", ""],
    ]);
    expect(claims[0]).toMatchObject({
      iss: "https://app.test",
      sub: "org-1",
      table: "public.facts",
      seq: 2,
      hash: "ab",
    });
    expect(claims[1]?.["sub"]).toBe("");
    expect(calls[1]?.[1]).toMatchObject({ target: "public.facts", seq: 2 });
  });

  it("needs a signer to checkpoint", async () => {
    const { chain } = chainWith({});
    const result = await chain.checkpoint();

    expect(!result.ok && result.error.hint).toBe("AUDIT_CHAIN_SIGNER");
  });

  it("lists checkpoints, reads a broken verdict and reads proofs", async () => {
    const { chain, calls } = chainWith({
      list_chain_checkpoints: () => [
        {
          id: "cp-1",
          tenant: null,
          seq: 1,
          hash: "ab",
          keyId: "k1",
          signature: "s",
        },
      ],
      verify_chain: () => ({
        valid: false,
        checked: 3,
        seq: null,
        reason: "link",
      }),
      chain_heads: () => null,
      chain_proof: (args) => ({
        table: "public.facts",
        tenant: null,
        entries: [
          {
            seq: 1,
            prevHash: null,
            rowHash: "ab",
            entry: { seq: 1 },
            hashed: "{}",
          },
        ],
        checkpoint:
          args["seq"] === 1
            ? { seq: 1, hash: "ab", keyId: "k1", signature: "s" }
            : null,
      }),
    });

    expect(
      await chain.checkpoints({ tenant: "org-1", limit: 5 }).orThrow(),
    ).toHaveLength(1);
    await chain.checkpoints().orThrow();
    expect(await chain.verify().orThrow()).toEqual({
      valid: false,
      checked: 3,
      seq: 0,
      reason: "link",
    });
    expect(await chain.heads().orThrow()).toEqual([]);

    const signed = await chain.proof({ seq: 1 }).orThrow();
    const unsigned = await chain.proof({ seq: 2, tenant: "org-1" }).orThrow();

    expect(signed.checkpoint).toEqual({
      seq: 1,
      hash: "ab",
      keyId: "k1",
      signature: "s",
    });
    expect(signed.entries[0]?.prevHash).toBeUndefined();
    expect(unsigned.checkpoint).toBeUndefined();
    expect(calls[0]).toEqual([
      "list_chain_checkpoints",
      { target: "public.facts", tenant: "org-1", max_rows: 5 },
    ]);
    expect(calls[1]?.[1]).toMatchObject({ max_rows: 100 });
  });
});

describe("verifyChainProof edges", () => {
  it("refuses an empty proof, a gap and a checkpoint that names another row", async () => {
    const { proof, jwks } = await signedProof();
    const [first, second] = proof.entries;

    expect(await verifyChainProof({ ...proof, entries: [] }, jwks)).toEqual({
      valid: false,
      reason: "empty",
    });
    expect(
      await verifyChainProof(
        { ...proof, entries: [first!, { ...second!, seq: 3 }] },
        jwks,
      ),
    ).toMatchObject({ valid: false, reason: "gap", seq: 3 });
    expect(
      await verifyChainProof(
        { ...proof, checkpoint: { ...proof.checkpoint!, seq: 1 } },
        jwks,
      ),
    ).toMatchObject({ valid: false, reason: "checkpoint" });
    expect(
      await verifyChainProof({ ...proof, checkpoint: undefined }, jwks),
    ).toEqual({ valid: true, signed: false, checked: 2 });
  });

  it("refuses a signature over another hash", async () => {
    const { proof, jwks } = await signedProof();
    const key = await generateSigningKey("ES256");

    const signature = await signCompact(
      await importSigningKey(key.privateKey),
      "ES256",
      { alg: "ES256", kid: key.kid },
      { seq: 2, hash: "00" },
    );

    expect(
      await verifyChainProof(
        { ...proof, checkpoint: { ...proof.checkpoint!, signature } },
        { keys: [...jwks.keys, { ...key.publicKey, kid: key.kid }] },
      ),
    ).toMatchObject({ valid: false, reason: "signature", seq: 2 });
  });
});
