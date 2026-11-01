import { describe, expect, it } from "vitest";

import type { DamUsageRight } from "../../../src/blocks/dam/dam.ts";

import {
  damUsageRightsToOdrl,
  ODRL_CONTEXT,
} from "../../../src/blocks/dam/odrl.ts";

const right = (patch: Partial<DamUsageRight>): DamUsageRight => ({
  id: "r-1",
  organizationId: "o",
  nodeId: "n",
  licensee: "https://partner.example/acme",
  startsOn: Temporal.PlainDate.from("2026-01-01"),
  status: "active",
  createdAt: Temporal.Instant.from("2026-01-01T00:00:00Z"),
  ...patch,
});

describe("damUsageRightsToOdrl", () => {
  it("writes one permission per active right with its constraints", () => {
    const policy = damUsageRightsToOdrl(
      [
        right({
          expiresOn: Temporal.PlainDate.from("2026-12-31"),
          territory: "NL",
          channel: "web",
        }),
        right({ id: "r-2", status: "upcoming" }),
        right({
          id: "r-3",
          revokedAt: Temporal.Instant.from("2026-02-01T00:00:00Z"),
        }),
      ],
      {
        assigner: "https://brand.example",
        target: "https://cdn.example/a.jpg",
      },
    );

    expect(policy["@context"]).toBe(ODRL_CONTEXT);
    expect(policy.type).toBe("Set");
    expect(policy.uid).toBe("urn:uuid:r-1");
    expect(policy.permission).toHaveLength(1);
    expect(policy.permission[0]?.constraint).toEqual([
      {
        leftOperand: "dateTime",
        operator: "gteq",
        rightOperand: { "@value": "2026-01-01", "@type": "xsd:date" },
      },
      {
        leftOperand: "dateTime",
        operator: "lteq",
        rightOperand: { "@value": "2026-12-31", "@type": "xsd:date" },
      },
      { leftOperand: "spatial", operator: "eq", rightOperand: "NL" },
      { leftOperand: "purpose", operator: "eq", rightOperand: "web" },
    ]);
  });

  it("writes an empty set for no active rights and maps the assignee", () => {
    const none = damUsageRightsToOdrl([], {
      assigner: "a",
      target: "t",
      uid: "urn:x",
    });

    const mapped = damUsageRightsToOdrl([right({ licensee: "acme" })], {
      assigner: "a",
      target: "t",
      assignee: (name) => `https://licensees.example/${name}`,
      action: "distribute",
    });

    expect(none.permission).toEqual([]);
    expect(mapped.permission[0]).toMatchObject({
      assignee: "https://licensees.example/acme",
      action: "distribute",
    });
  });
});
