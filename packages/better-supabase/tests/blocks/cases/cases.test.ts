import { describe, expect, it } from "vitest";

import { createCases } from "../../../src/blocks/cases/index.ts";

const KIND = {
  id: "k1",
  organizationId: "org",
  key: "nonconformity",
  name: "Nonconformity",
  prefix: "NC",
  requiresRootCause: true,
  requiresActions: true,
  requiresEffectiveness: false,
  createdAt: "2026-10-29T00:00:00Z",
  updatedAt: "2026-10-29T00:00:00Z",
};

const CASE = {
  id: "c1",
  organizationId: "org",
  kindId: "k1",
  number: "NC-2026-0001",
  title: "Missing inspection",
  detectedAt: "2026-10-29T00:00:00Z",
  status: "open",
  createdAt: "2026-10-29T00:00:00Z",
  updatedAt: "2026-10-29T00:00:00Z",
  actions: [],
  blockers: ["CASE_ACTIONS_REQUIRED"],
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

describe("createCases", () => {
  it("saves a kind and opens a case", async () => {
    const transport = fakeTransport({
      save_case_kind: KIND,
      list_case_kinds: [KIND],
      open_case: CASE,
      get_case: CASE,
      list_cases: [CASE],
      case_close_blockers: ["CASE_ACTIONS_REQUIRED"],
      close_case: { ...CASE, status: "closed" },
    });

    const client = createCases({ transport, schema: "app" });

    expect((await client.saveKind("org", KIND).orThrow()).key).toBe(
      "nonconformity",
    );
    expect(await client.kinds("org").orThrow()).toHaveLength(1);
    expect((await client.open("org", "nonconformity", { title: "Missing inspection" }).orThrow()).number).toBe("NC-2026-0001");
    expect((await client.get("c1").orThrow()).blockers).toEqual([
      "CASE_ACTIONS_REQUIRED",
    ]);
    expect(await client.list("org").orThrow()).toHaveLength(1);
    expect(await client.closeBlockers("c1").orThrow()).toEqual([
      "CASE_ACTIONS_REQUIRED",
    ]);
    expect((await client.close("c1").orThrow()).status).toBe("closed");
  });

  it("rejects a malformed case", async () => {
    const transport = fakeTransport({ open_case: { ...CASE, status: "unknown" } });
    const client = createCases({ transport, schema: "app" });

    const result = await client.open("org", "nonconformity", {
      title: "Missing inspection",
    });

    expect(result.ok).toBe(false);
  });

  it("checks the manifest and the input schema", async () => {
    const { casesBlock } = await import(
      "../../../src/blocks/cases/manifest.ts"
    );

    const { caseInputSchema } = await import(
      "../../../src/blocks/cases/schemas.ts"
    );

    expect(casesBlock.name).toBe("cases");

    expect(
      (await caseInputSchema["~standard"].validate({ title: "Missing inspection" }))
        .issues,
    ).toBeUndefined();
  });
});
