import { describe, expect, it } from "vitest";

import { createAuditChain } from "../../../src/blocks/audit/index.ts";
import { toBase64Url } from "../../../src/core/base64.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const head = { tenant: "org-1", seq: 3, hash: "ab", entryId: "7" };
const checkpoint = {
  ...head,
  id: "1",
  keyId: "k1",
  signature: "jws",
  createdAt: "2026-10-16T12:00:00Z",
};

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];
  return {
    calls,
    transport: {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([fn, { ...args }]);
        return Promise.resolve(results[fn]);
      },
    },
  };
}

const token = (header: object) =>
  `${toBase64Url(JSON.stringify(header))}.${toBase64Url("{}")}.sig`;

describe("createAuditChain", () => {
  it("reads a valid and a broken verdict", async () => {
    const valid = fakeTransport({
      verify_audit_chain: { valid: true, checked: 3, seq: 3, hash: "ab" },
    });
    const chain = createAuditChain({ transport: valid.transport });
    expect(
      await chain
        .verify({
          organizationId: "org-1",
          from: Temporal.Instant.from("2026-01-01T00:00:00Z"),
        })
        .orThrow(),
    ).toEqual({ valid: true, checked: 3, seq: 3, hash: "ab" });
    expect(valid.calls[0]).toEqual([
      "verify_audit_chain",
      { tenant: "org-1", from_at: "2026-01-01T00:00:00Z", to_at: undefined },
    ]);

    const empty = createAuditChain({
      transport: fakeTransport({
        verify_audit_chain: { valid: true, checked: 0, seq: null, hash: null },
      }).transport,
    });
    expect(await empty.verify().orThrow()).toEqual({
      valid: true,
      checked: 0,
      seq: undefined,
      hash: undefined,
    });

    const broken = createAuditChain({
      transport: fakeTransport({
        verify_audit_chain: { valid: false, checked: 1, seq: 4, reason: "gap" },
      }).transport,
    });
    expect(await broken.verify().orThrow()).toEqual({
      valid: false,
      checked: 1,
      seq: 4,
      brokenAt: undefined,
      reason: "gap",
    });
  });

  it("signs each head and records it with the key id", async () => {
    const { transport, calls } = fakeTransport({
      audit_chain_heads: [head, { ...head, tenant: null, seq: 1 }],
      record_audit_checkpoint: checkpoint,
      list_audit_checkpoints: [checkpoint],
    });
    const signed: Record<string, unknown>[] = [];
    const chain = createAuditChain({
      transport,
      issuer: "https://app.example",
      signer: {
        signJwt: (claims) => {
          signed.push({ ...claims });
          return AsyncResult.ok(
            signed.length === 1 ? token({ kid: "k1" }) : token({ alg: "x" }),
          );
        },
      },
    });
    const made = await chain.checkpoint().orThrow();
    expect(made).toHaveLength(2);
    expect(made[0]).toMatchObject({ organizationId: "org-1", keyId: "k1" });
    expect(made[0]?.createdAt.toString()).toBe("2026-10-16T12:00:00Z");
    expect(signed[0]).toMatchObject({
      iss: "https://app.example",
      sub: "org-1",
      seq: 3,
      hash: "ab",
      entry: "7",
    });
    expect(signed[1]).toMatchObject({ sub: "", seq: 1 });
    expect(calls.filter(([fn]) => fn === "record_audit_checkpoint")).toEqual([
      [
        "record_audit_checkpoint",
        {
          tenant: "org-1",
          seq: 3,
          hash: "ab",
          key_id: "k1",
          signature: token({ kid: "k1" }),
        },
      ],
      [
        "record_audit_checkpoint",
        {
          tenant: undefined,
          seq: 1,
          hash: "ab",
          key_id: "",
          signature: token({ alg: "x" }),
        },
      ],
    ]);
    expect(await chain.checkpoints({ limit: 5 }).orThrow()).toHaveLength(1);
    expect(calls.at(-1)).toEqual([
      "list_audit_checkpoints",
      { tenant: undefined, max_rows: 5 },
    ]);
  });

  it("fails checkpoint() without a signer and leaves out a missing issuer", async () => {
    const result = await createAuditChain({
      transport: fakeTransport({}).transport,
    }).checkpoint();
    expect(result.ok ? undefined : result.error).toMatchObject({
      kind: "invalid_request",
      hint: "AUDIT_CHAIN_SIGNER",
    });

    const signed: Record<string, unknown>[] = [];
    await createAuditChain({
      transport: fakeTransport({
        audit_chain_heads: [head],
        record_audit_checkpoint: checkpoint,
      }).transport,
      signer: {
        signJwt: (claims) => {
          signed.push({ ...claims });
          return AsyncResult.ok(token({ kid: "k1" }));
        },
      },
    })
      .checkpoint()
      .orThrow();
    expect(signed[0]).not.toHaveProperty("iss");
    expect(
      await createAuditChain({
        transport: fakeTransport({ list_audit_checkpoints: [] }).transport,
      })
        .checkpoints()
        .orThrow(),
    ).toEqual([]);
  });
});
