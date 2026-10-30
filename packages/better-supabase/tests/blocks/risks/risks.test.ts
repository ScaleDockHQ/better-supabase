import * as v from "valibot";
import { describe, expect, it } from "vitest";

import {
  createRisks,
  riskAssessmentInputSchema,
  riskInputSchema,
  riskMatrixInputSchema,
  risksBlock,
} from "../../../src/blocks/risks/index.ts";
import { DEFAULT_RISK_MATRIX } from "../../../src/sql/modules/risks-sql.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-29T10:00:00Z";
const ID = "00000000-0000-4000-8000-000000000001";

const MATRIX = {
  id: "m1",
  organizationId: "org-1",
  key: "default",
  name: "Default 5x5",
  likelihoodLevels: DEFAULT_RISK_MATRIX.likelihoodLevels,
  impactLevels: DEFAULT_RISK_MATRIX.impactLevels,
  bands: DEFAULT_RISK_MATRIX.bands,
  scoring: "product",
  isDefault: true,
  createdAt: AT,
  updatedAt: AT,
};

const RISK = {
  id: "r1",
  organizationId: "org-1",
  number: "RSK-0001",
  matrixId: "m1",
  title: "Supplier fails",
  description: "The only supplier stops",
  category: "operational",
  cause: "Single source",
  consequence: "Line stops",
  ownerId: "u1",
  status: "treating",
  treatment: "mitigate",
  reviewIntervalMonths: 6,
  nextReviewOn: "2027-04-29",
  reviewedAt: AT,
  inherent: { likelihood: 4, impact: 5, score: 20, band: "critical" },
  residual: { likelihood: 2, impact: 3, score: "6", band: "medium" },
  currentAssessmentId: "a1",
  closedAt: null,
  archivedAt: null,
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
  fields: { site: "north" },
};

const BARE_RISK = {
  id: "r2",
  organizationId: "org-1",
  number: "RSK-0002",
  matrixId: "m1",
  title: "Flood",
  category: "environment",
  status: "identified",
  inherent: null,
  residual: null,
  createdAt: AT,
  updatedAt: AT,
  fields: { site: "south" },
};

const ASSESSMENT = {
  id: "a1",
  organizationId: "org-1",
  riskId: "r1",
  inherent: RISK.inherent,
  residual: RISK.residual,
  rationale: "Two suppliers",
  versionId: "v1",
  assessedBy: "u1",
  assessedAt: AT,
};

const Fields = v.object({ site: v.picklist(["north", "south"]) });

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createRisks", () => {
  it("saves and lists matrices", async () => {
    const t = fieldsTransport({
      save_risk_matrix: () => MATRIX,
      list_risk_matrices: () => [MATRIX],
    });

    const risks = createRisks({ transport: t, tenant: "org-1" });

    const saved = await risks
      .saveMatrix({
        key: "default",
        name: "Default 5x5",
        likelihoodLevels: DEFAULT_RISK_MATRIX.likelihoodLevels,
        impactLevels: DEFAULT_RISK_MATRIX.impactLevels,
        bands: DEFAULT_RISK_MATRIX.bands,
      })
      .orThrow();

    const listed = await risks.matrices().orThrow();

    expect(saved).toMatchObject({ key: "default", isDefault: true });
    expect(saved.bands.map((band) => band.key)).toEqual([
      "low",
      "medium",
      "high",
      "critical",
    ]);
    expect(listed).toHaveLength(1);
    expect(t.calls).toEqual([
      [
        "save_risk_matrix",
        {
          tenant: "org-1",
          key: "default",
          name: "Default 5x5",
          likelihood_levels: DEFAULT_RISK_MATRIX.likelihoodLevels,
          impact_levels: DEFAULT_RISK_MATRIX.impactLevels,
          bands: DEFAULT_RISK_MATRIX.bands,
          scoring: "product",
          is_default: false,
          matrix_id: null,
        },
      ],
      ["list_risk_matrices", { tenant: "org-1" }],
    ]);
  });

  it("creates and updates a risk with its extra fields and checks them", async () => {
    const t = fieldsTransport({
      create_risk: () => RISK,
      update_risk: () => BARE_RISK,
    });

    const risks = createRisks({
      transport: t,
      tenant: "org-1",
      fields: Fields,
    });

    const created = await risks
      .create({
        title: "Supplier fails",
        category: "operational",
        ownerId: "u1",
        reviewIntervalMonths: 6,
        fields: { site: "north" },
      })
      .orThrow();

    const updated = await risks.update("r2", { title: "Flood" }).orThrow();

    const refused = await risks.create({
      title: "Bad",
      category: "quality",
      // SAFETY: a value the schema refuses, to prove the client checks it.
      fields: { site: "east" } as unknown as { site: "north" },
    });

    expect(created.fields.site).toBe("north");
    expect(created.residual).toEqual({
      likelihood: 2,
      impact: 3,
      score: 6,
      band: "medium",
    });
    expect(created.nextReviewOn?.toString()).toBe("2027-04-29");
    expect(updated.inherent).toBeUndefined();
    expect(updated.description).toBeUndefined();
    expect(refused.ok ? undefined : refused.error.kind).toBe("validation");
    expect(t.calls).toEqual([
      [
        "create_risk",
        {
          tenant: "org-1",
          input: {
            title: "Supplier fails",
            category: "operational",
            ownerId: "u1",
            reviewIntervalMonths: 6,
            fields: { site: "north" },
          },
        },
      ],
      ["update_risk", { risk_id: "r2", changes: { title: "Flood" } }],
    ]);
  });

  it("assesses, treats, reviews and closes a risk", async () => {
    const t = fieldsTransport({
      assess_risk: () => RISK,
      set_risk_treatment: () => RISK,
      review_risk: () => RISK,
      close_risk: () => ({ ...RISK, status: "closed", closedAt: AT }),
    });

    const risks = createRisks({ transport: t, tenant: "org-1" });

    await risks
      .assess("r1", {
        inherent: { likelihood: 4, impact: 5 },
        residual: { likelihood: 2, impact: 3 },
        rationale: "Two suppliers",
      })
      .orThrow();
    await risks.setTreatment("r1", "accept").orThrow();
    await risks.review("r1", "Still fine").orThrow();
    const closed = await risks.close("r1", "Supplier replaced").orThrow();

    expect(closed.status).toBe("closed");
    expect(closed.closedAt?.toString()).toBe("2026-10-29T10:00:00Z");
    expect(t.calls).toEqual([
      [
        "assess_risk",
        {
          risk_id: "r1",
          inherent_likelihood: 4,
          inherent_impact: 5,
          residual_likelihood: 2,
          residual_impact: 3,
          rationale: "Two suppliers",
        },
      ],
      [
        "set_risk_treatment",
        { risk_id: "r1", treatment: "accept", note: null },
      ],
      ["review_risk", { risk_id: "r1", note: "Still fine" }],
      ["close_risk", { risk_id: "r1", reason: "Supplier replaced" }],
    ]);
  });

  it("reads a risk with its matrix, assessments, barriers and cases", async () => {
    const t = fieldsTransport({
      get_risk: () => ({
        ...RISK,
        matrix: MATRIX,
        assessments: [ASSESSMENT],
        barriers: [
          { linkId: "l1", type: "control", id: "c1", title: "Dual sourcing" },
        ],
        cases: [{ linkId: "l2", type: "case", id: "k1", title: null }],
      }),
    });

    const risks = createRisks({ transport: t, tenant: "org-1" });

    const detail = await risks.get("r1").orThrow();

    expect(detail.matrix.key).toBe("default");
    expect(detail.assessments[0]).toMatchObject({
      id: "a1",
      versionId: "v1",
      rationale: "Two suppliers",
    });
    expect(detail.barriers).toEqual([
      { linkId: "l1", type: "control", id: "c1", title: "Dual sourcing" },
    ]);
    expect(detail.cases).toEqual([{ linkId: "l2", type: "case", id: "k1" }]);
    expect(t.calls).toEqual([["get_risk", { risk_id: "r1" }]]);
  });

  it("lists risks, draws the heatmap and reports due reviews", async () => {
    const t = fieldsTransport({
      list_risks: () => [RISK, BARE_RISK],
      risk_heatmap: () => ({
        matrix: MATRIX,
        basis: "residual",
        cells: [
          {
            likelihood: 2,
            impact: 3,
            score: 6,
            band: "medium",
            count: 1,
            riskIds: ["r1"],
          },
        ],
      }),
      notify_due_risk_reviews: () => 2,
    });

    const risks = createRisks({ transport: t, tenant: "org-1" });

    const listed = await risks
      .list({ band: "medium", reviewDue: true })
      .orThrow();

    const map = await risks.heatmap({ basis: "inherent" }).orThrow();
    const due = await risks.notifyDueReviews().orThrow();

    expect(listed.map((risk) => risk.number)).toEqual(["RSK-0001", "RSK-0002"]);
    expect(map.cells[0]).toMatchObject({ count: 1, riskIds: ["r1"] });
    expect(due).toBe(2);
    expect(t.calls).toEqual([
      [
        "list_risks",
        { tenant: "org-1", filters: { band: "medium", reviewDue: true } },
      ],
      ["risk_heatmap", { tenant: "org-1", matrix_id: null, basis: "inherent" }],
      ["notify_due_risk_reviews", {}],
    ]);
  });

  it("rejects a malformed row", async () => {
    const t = fieldsTransport({
      create_risk: () => ({ ...RISK, status: "open" }),
    });

    const risks = createRisks({ transport: t, tenant: "org-1" });

    const result = await risks.create({ title: "A", category: "quality" });

    expect(result.ok).toBe(false);
  });

  it("runs the hooks", async () => {
    const seen: string[] = [];

    const risks = createRisks({
      transport: fieldsTransport({ notify_due_risk_reviews: () => 0 }),
      hooks: {
        notifyDueReviews: {
          after: () => {
            seen.push("notifyDueReviews");
          },
        },
      },
    });

    await risks.notifyDueReviews().orThrow();

    expect(seen).toEqual(["notifyDueReviews"]);
  });
});

describe("risks block", () => {
  it("names the block and validates the inputs", () => {
    expect(risksBlock.name).toBe("risks");
    expect(
      validate(riskInputSchema, { title: "A", category: "quality" }).issues,
    ).toBeUndefined();
    expect(
      validate(riskInputSchema, {
        title: "A",
        category: "quality",
        reviewIntervalMonths: 200,
      }).issues,
    ).toBeDefined();
    expect(
      validate(riskMatrixInputSchema, {
        key: "k",
        name: "K",
        likelihoodLevels: [],
        impactLevels: [],
        bands: [],
        matrixId: ID,
      }).issues,
    ).toBeUndefined();
    expect(
      validate(riskAssessmentInputSchema, {
        inherent: { likelihood: 1, impact: 1 },
        residual: { likelihood: 1, impact: 1 },
      }).issues,
    ).toBeUndefined();
  });
});
