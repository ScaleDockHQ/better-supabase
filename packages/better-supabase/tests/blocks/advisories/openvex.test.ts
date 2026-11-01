import { describe, expect, it } from "vitest";

import {
  OPENVEX_CONTEXT,
  renderOpenVex,
} from "../../../src/blocks/advisories/openvex.ts";

describe("renderOpenVex", () => {
  it("fills defaults", () => {
    const doc = renderOpenVex({
      author: "Acme",
      product: { key: "my app" },
      statements: [{ vulnId: "CVE-1", status: "affected", version: "1 2" }],
    });

    expect(doc["@context"]).toBe(OPENVEX_CONTEXT);
    expect(String(doc["@id"])).toMatch(/^urn:uuid:/u);
    expect(doc["version"]).toBe(1);
    expect(doc).not.toHaveProperty("role");
    expect(doc["statements"]).toEqual([
      {
        vulnerability: { name: "CVE-1" },
        products: [{ "@id": "pkg:generic/my%20app@1%202" }],
        status: "affected",
      },
    ]);
  });

  it("renders every optional field", () => {
    const stamp = Temporal.Instant.from("2026-01-01T00:00:00Z");

    const doc = renderOpenVex({
      id: "https://x.test/vex",
      author: "Acme",
      role: "Security",
      timestamp: stamp,
      version: 3,
      product: { key: "app", purl: "pkg:npm/app" },
      statements: [
        {
          vulnId: "CVE-1",
          status: "not_affected",
          justification: "component_not_present",
          impactStatement: "none",
          actionStatement: "none",
          timestamp: stamp,
          version: "2",
        },
        { vulnId: "CVE-2", status: "fixed" },
        { vulnId: "CVE-3", status: "fixed", version: "3" },
      ],
    });

    expect(doc).toMatchObject({ role: "Security", version: 3 });

    const statements = doc["statements"] as Record<string, unknown>[];

    expect(statements[0]).toMatchObject({
      justification: "component_not_present",
      impact_statement: "none",
      action_statement: "none",
      products: [{ "@id": "pkg:npm/app@2" }],
    });
    expect(statements[1]?.["products"]).toEqual([{ "@id": "pkg:npm/app" }]);
  });

  it("keeps a purl that carries its own version", () => {
    const doc = renderOpenVex({
      author: "A",
      product: { key: "app", purl: "pkg:npm/app@1" },
      statements: [{ vulnId: "CVE-1", status: "fixed", version: "9" }],
    });

    expect(
      (doc["statements"] as { products: unknown[] }[])[0]?.products,
    ).toEqual([{ "@id": "pkg:npm/app@1" }]);
  });
});
