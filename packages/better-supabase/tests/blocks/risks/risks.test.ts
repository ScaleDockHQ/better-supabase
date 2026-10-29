import { describe, expect, it } from "vitest";

import { createRisks } from "../../../src/blocks/risks/index.ts";

const MATRIX = {
  id: "m1",
  organizationId: "org",
  key: "default",
  name: "Default",
  likelihoodLevels: [{ value: 1, label: "Rare" }],
  impactLevels: [{ value: 1, label: "Minor" }],
  bands: [{ key: "low", label: "Low", min: 1, max: 4 }],
  scoring: "product",
  isDefault: true,
};

const RISK = {
  id: "r1",
  organizationId: "org",
  matrixId: "m1",
  number: "RSK-0001",
  title: "Supplier outage",
  status: "identified",
  createdAt: "2026-10-29T00:00:00Z",
  updatedAt: "2026-10-29T00:00:00Z",
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

describe("createRisks", () => {
  it("creates, assesses and reads a heatmap", async () => {
    const transport = fakeTransport({
      list_risk_matrices: [MATRIX],
      create_risk: RISK,
      assess_risk: { ...RISK, status: "assessed", residualBand: "low" },
      get_risk: { ...RISK, assessments: [] },
      list_risks: [RISK],
      risk_heatmap: {
        matrix: MATRIX,
        cells: [{ likelihood: 1, impact: 1, count: 1, riskIds: ["r1"] }],
      },
      notify_due_risk_reviews: 1,
    });

    const client = createRisks({ transport, schema: "app" });

    expect(await client.matrices("org").orThrow()).toHaveLength(1);
    expect((await client.create("org", { title: "Supplier outage" }).orThrow()).number).toBe("RSK-0001");
    expect(
      (await client.assess("r1", {
        inherentLikelihood: 1,
        inherentImpact: 1,
        residualLikelihood: 1,
        residualImpact: 1,
      }).orThrow()).status,
    ).toBe("assessed");
    expect((await client.get("r1").orThrow()).assessments).toEqual([]);
    expect(await client.list("org").orThrow()).toHaveLength(1);
    expect((await client.heatmap("org").orThrow()).cells[0]?.count).toBe(1);
    expect(await client.notifyDueReviews().orThrow()).toBe(1);
  });
});
