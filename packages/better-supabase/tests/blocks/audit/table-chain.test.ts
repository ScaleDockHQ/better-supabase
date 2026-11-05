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
