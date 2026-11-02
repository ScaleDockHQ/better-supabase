import { describe, expect, it } from "vitest";

import { damUsageRightsToOdrl } from "../../src/blocks/dam/odrl.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

describe(`ODRL ${SPEC_PINS.odrl}`, () => {
  it("writes a Set with the ODRL JSON-LD context and core permission terms", () => {
    const policy = damUsageRightsToOdrl(
      [
        {
          id: "r",
          organizationId: "o",
          nodeId: "n",
          licensee: "acme",
          startsOn: Temporal.PlainDate.from("2026-01-01"),
          status: "active",
          createdAt: Temporal.Instant.from("2026-01-01T00:00:00Z"),
        },
      ],
      { assigner: "https://a.example", target: "https://a.example/f" },
    );

    expect(policy["@context"]).toBe("http://www.w3.org/ns/odrl.jsonld");
    expect(policy.type).toBe("Set");
    expect(Object.keys(policy.permission[0] ?? {}).toSorted()).toEqual([
      "action",
      "assignee",
      "assigner",
      "constraint",
      "target",
    ]);
    expect(policy.permission[0]?.constraint[0]?.operator).toBe("gteq");
  });
});
