import { describe, expect, it } from "vitest";

import { renderOpenVex } from "../../src/blocks/advisories/index.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

describe("renderOpenVex", () => {
  it("writes an OpenVEX 0.2.0 document with one statement per entry", () => {
    const document = renderOpenVex({
      id: "https://example.com/vex/1",
      author: "Acme Security",
      timestamp: Temporal.Instant.from("2026-01-01T00:00:00Z"),
      product: { key: "acme-app" },
      statements: [
        {
          vulnId: "CVE-2026-0001",
          version: "1.2.0",
          status: "not_affected",
          justification: "vulnerable_code_not_in_execute_path",
          impactStatement: "The code is never called.",
        },
        {
          vulnId: "CVE-2026-0002",
          status: "affected",
          actionStatement: "Upgrade to 1.3.0.",
        },
      ],
    });

    expect(document["@context"]).toBe("https://openvex.dev/ns/v0.2.0");
    expect(document["@id"]).toBe("https://example.com/vex/1");
    expect(document["author"]).toBe("Acme Security");
    expect(document["version"]).toBe(1);

    const statements = document["statements"] as readonly Record<
      string,
      unknown
    >[];

    expect(statements).toHaveLength(2);
    expect(statements[0]).toMatchObject({
      vulnerability: { name: "CVE-2026-0001" },
      status: "not_affected",
      justification: "vulnerable_code_not_in_execute_path",
      impact_statement: "The code is never called.",
      products: [{ "@id": "pkg:generic/acme-app@1.2.0" }],
    });
    expect(statements[1]).toMatchObject({
      status: "affected",
      action_statement: "Upgrade to 1.3.0.",
      products: [{ "@id": "pkg:generic/acme-app" }],
    });
  });

  it("uses the product's package URL when it has one", () => {
    const document = renderOpenVex({
      author: "Acme",
      product: { key: "acme-app", purl: "pkg:npm/acme-app" },
      statements: [
        { vulnId: "CVE-2026-0003", version: "2.0.0", status: "fixed" },
      ],
    });

    const [statement] = document["statements"] as readonly Record<
      string,
      unknown
    >[];

    expect(statement?.["products"]).toEqual([
      { "@id": "pkg:npm/acme-app@2.0.0" },
    ]);
    expect(String(document["@id"])).toMatch(/^urn:uuid:/u);
  });
});

describe("openvex spec pin", () => {
  it("names the version the code follows", () => {
    expect(SPEC_PINS.openvex).toBe("0.2.0");
  });
});
