import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/blocks/field-encryption/index.ts";

import { createFieldEncryption } from "../../../src/blocks/field-encryption/index.ts";

function fakeTransport(results: Readonly<Record<string, unknown>>) {
  const calls: [string, Readonly<Record<string, unknown>>][] = [];

  const transport: BlockTransport = {
    call(_schema, fn, args) {
      calls.push([fn, { ...args }]);

      return Promise.resolve(results[fn] ?? null);
    },
  };

  return { calls, transport };
}

describe("createFieldEncryption", () => {
  it("reads each owner's key dates and encrypted columns, never key material", async () => {
    const { calls, transport } = fakeTransport({
      field_key_status: [
        {
          owner: "tenant:org_1",
          has_key: true,
          has_lookup_key: false,
          key_created_at: "2026-11-01T10:00:00Z",
          key_rotated_at: "2026-11-12T10:00:00Z",
          lookup_key_created_at: null,
          columns: [{ table: "client_notes", column: "diagnosis" }],
          fields: 2,
        },
        { owner: "user:u1", has_key: false, has_lookup_key: false },
      ],
    });

    const [tenant, user] = await createFieldEncryption({ transport })
      .keyStatus()
      .orThrow();

    expect(calls).toEqual([["field_key_status", {}]]);
    expect(tenant?.keyRotatedAt?.toString()).toBe("2026-11-12T10:00:00Z");
    expect(tenant).toMatchObject({
      owner: "tenant:org_1",
      hasKey: true,
      lookupKeyCreatedAt: undefined,
      columns: [{ table: "client_notes", column: "diagnosis" }],
      fields: 2,
    });
    expect(user).toEqual({
      owner: "user:u1",
      hasKey: false,
      hasLookupKey: false,
      keyCreatedAt: undefined,
      keyRotatedAt: undefined,
      lookupKeyCreatedAt: undefined,
      columns: [],
      fields: 0,
    });
  });

  it("rotates a key and returns how many rows it encrypted again", async () => {
    const { calls, transport } = fakeTransport({
      rotate_field_key: {
        owner: "tenant:org_1",
        values: 7,
        rotated_at: "2026-11-13T09:00:00Z",
      },
    });

    const rotation = await createFieldEncryption({ transport })
      .rotateKey("tenant:org_1")
      .orThrow();

    expect(calls).toEqual([["rotate_field_key", { owner: "tenant:org_1" }]]);
    expect(rotation.values).toBe(7);
    expect(rotation.rotatedAt.toString()).toBe("2026-11-13T09:00:00Z");
  });
});
