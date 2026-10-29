import { describe, expect, it } from "vitest";

import { createQualifications } from "../../../src/blocks/qualifications/index.ts";

const TYPE = {
  id: "t1",
  organizationId: "org",
  key: "forklift",
  name: "Forklift licence",
  holderTypes: ["member"],
  evidenceRequired: false,
  createdAt: "2026-10-29T00:00:00Z",
  updatedAt: "2026-10-29T00:00:00Z",
};

const HOLDING = {
  id: "q1",
  organizationId: "org",
  typeId: "t1",
  holderType: "member",
  holderId: "u1",
  grantedOn: "2026-10-29",
  source: "manual",
};

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, unknown][] = [];

  return {
    calls,
    call(schema: string, fn: string, args?: unknown) {
      expect(schema).toBe("app");
      calls.push([fn, args]);

      return Promise.resolve(results[fn]);
    },
  };
}

describe("createQualifications", () => {
  it("saves a type, grants and lists gaps", async () => {
    const transport = fakeTransport({
      save_qualification_type: TYPE,
      list_qualification_types: [TYPE],
      grant_qualification: HOLDING,
      qualifications_of: [{ ...HOLDING, status: "valid" }],
      qualification_gaps: [
        {
          holderType: "member",
          holderId: "u2",
          typeKey: "forklift",
          typeName: "Forklift licence",
          status: "missing",
        },
      ],
      notify_expiring_qualifications: 1,
    });

    const client = createQualifications({ transport, schema: "app" });

    expect((await client.saveType("org", TYPE).orThrow()).key).toBe("forklift");
    expect(await client.types("org").orThrow()).toHaveLength(1);
    expect(
      (await client.grant("org", {
        typeKey: "forklift",
        holderType: "member",
        holderId: "u1",
      }).orThrow()).holderId,
    ).toBe("u1");
    expect((await client.of("member", "u1").orThrow())[0]?.status).toBe("valid");
    expect((await client.gaps("org").orThrow())[0]?.status).toBe("missing");
    expect(await client.notifyExpiring().orThrow()).toBe(1);
  });

  it("rejects a malformed holding", async () => {
    const transport = fakeTransport({
      grant_qualification: { ...HOLDING, grantedOn: "not-a-date" },
    });

    const client = createQualifications({ transport, schema: "app" });

    const result = await client.grant("org", {
      typeKey: "forklift",
      holderType: "member",
      holderId: "u1",
    });

    expect(result.ok).toBe(false);
  });
});
