import { describe, expect, it } from "vitest";

import {
  appraisalCycleInputSchema,
  appraisalReviewInputSchema,
  appraisalsBlock,
  createAppraisals,
} from "../../../src/blocks/appraisals/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-29T10:00:00Z";

const CYCLE = {
  id: "c1",
  organizationId: "org-1",
  name: "H2 2026",
  startsOn: "2026-07-01",
  endsOn: "2026-12-31",
  program: "appraisal",
  status: "open",
  openedAt: AT,
  createdAt: AT,
  appraisalsCreated: 2,
};

const APPRAISAL = {
  id: "a1",
  organizationId: "org-1",
  cycleId: "c1",
  subjectUserId: "u1",
  managerId: "u2",
  status: "reviewed",
  rating: "3.50",
  calibratedRating: 4,
  approvalId: "r1",
  signedOffAt: AT,
  signedOffBy: "u3",
  reviews: [
    {
      id: "v1",
      reviewerId: "u1",
      kind: "self",
      rating: 3,
      comments: "Fine",
      submissionId: "s1",
      submittedAt: AT,
    },
    { id: "v2", reviewerId: "u2", kind: "manager" },
  ],
  calibrations: [
    {
      id: "k1",
      fromRating: "3.50",
      toRating: 4,
      reason: "Cross-team impact",
      calibratedBy: "u3",
      calibratedAt: AT,
    },
    { id: "k2", toRating: 5, reason: "Again", calibratedAt: AT },
  ],
  goalIds: ["g1"],
  createdAt: AT,
};

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createAppraisals", () => {
  it("creates, opens, lists and closes cycles", async () => {
    const t = fieldsTransport({
      create_appraisal_cycle: () => ({ ...CYCLE, status: "draft" }),
      open_appraisal_cycle: () => CYCLE,
      close_appraisal_cycle: () => ({ ...CYCLE, closedAt: AT }),
      list_appraisal_cycles: () => [CYCLE, { ...CYCLE, program: undefined }],
    });

    const appraisals = createAppraisals({ transport: t, tenant: "org-1" });

    const created = await appraisals
      .createCycle({
        name: "H2 2026",
        startsOn: "2026-07-01",
        endsOn: "2026-12-31",
        program: "appraisal",
      })
      .orThrow();

    const opened = await appraisals
      .openCycle("c1", [
        { subjectUserId: "u1", managerId: "u2", peerIds: ["u4"] },
        { subjectUserId: "u5" },
      ])
      .orThrow();

    const closed = await appraisals.closeCycle("c1").orThrow();
    const listed = await appraisals.listCycles().orThrow();

    expect(created.status).toBe("draft");
    expect(opened).toMatchObject({
      appraisalsCreated: 2,
      program: "appraisal",
    });
    expect(opened.openedAt?.toString()).toBe(AT);
    expect(closed.closedAt?.toString()).toBe(AT);
    expect(listed[1]?.program).toBeUndefined();
    expect(t.calls[1]).toEqual([
      "open_appraisal_cycle",
      {
        cycle_id: "c1",
        assignments: [
          { subjectUserId: "u1", managerId: "u2", peerIds: ["u4"] },
          { subjectUserId: "u5" },
        ],
      },
    ]);
  });

  it("submits reviews, calibrates, signs off and reads appraisals", async () => {
    const t = fieldsTransport({
      submit_appraisal_review: () => APPRAISAL,
      calibrate_appraisal: () => APPRAISAL,
      set_appraisal_goals: () => APPRAISAL,
      sign_off_appraisal: () => ({ ...APPRAISAL, status: "awaiting_signoff" }),
      get_appraisal: () => APPRAISAL,
      list_appraisals: () => [APPRAISAL],
    });

    const appraisals = createAppraisals({ transport: t, tenant: "org-1" });

    const submitted = await appraisals
      .submitReview("v1", { rating: 3, comments: "Fine", submissionId: "s1" })
      .orThrow();

    await appraisals.calibrate("a1", 4, "Cross-team impact").orThrow();
    await appraisals.setGoals("a1", ["g1"]).orThrow();
    const signed = await appraisals.signOff("a1").orThrow();
    const one = await appraisals.getAppraisal("a1").orThrow();

    const listed = await appraisals
      .listAppraisals({ cycleId: "c1", mine: true })
      .orThrow();

    const all = await appraisals.listAppraisals().orThrow();

    expect(submitted).toMatchObject({
      rating: "3.50",
      calibratedRating: 4,
      approvalId: "r1",
      goalIds: ["g1"],
      signedOffBy: "u3",
    });
    expect(submitted.reviews[0]).toMatchObject({ kind: "self", rating: 3 });
    expect(submitted.reviews[1]?.rating).toBeUndefined();
    expect(submitted.calibrations[0]?.fromRating).toBe("3.50");
    expect(submitted.calibrations[1]?.fromRating).toBeUndefined();
    expect(signed.status).toBe("awaiting_signoff");
    expect(one.id).toBe("a1");
    expect(listed).toHaveLength(1);
    expect(all).toHaveLength(1);
    expect(t.calls[0]).toEqual([
      "submit_appraisal_review",
      {
        review_id: "v1",
        input: { rating: 3, comments: "Fine", submissionId: "s1" },
      },
    ]);
    expect(t.calls).toContainEqual([
      "list_appraisals",
      { tenant: "org-1", filters: { cycleId: "c1", mine: true } },
    ]);
  });

  it("reads a bare appraisal and rejects an unknown status", async () => {
    const t = fieldsTransport({
      get_appraisal: () => ({
        id: "a1",
        organizationId: "org-1",
        cycleId: "c1",
        subjectUserId: "u1",
        status: "pending",
        createdAt: AT,
      }),
      sign_off_appraisal: () => ({ ...APPRAISAL, status: "lost" }),
    });

    const appraisals = createAppraisals({ transport: t, tenant: "org-1" });

    const bare = await appraisals.getAppraisal("a1").orThrow();

    expect(bare.reviews).toEqual([]);
    expect(bare.goalIds).toEqual([]);
    await expect(appraisals.signOff("a1").orThrow()).rejects.toThrow(/./);
  });

  it("has a manifest and input schemas with the SQL bounds", () => {
    expect(appraisalsBlock.name).toBe("appraisals");
    expect(
      validate(appraisalCycleInputSchema, {
        name: "H2",
        startsOn: "2026-07-01",
        endsOn: "2026-12-31",
      }).issues,
    ).toBeUndefined();
    expect(
      validate(appraisalCycleInputSchema, {
        name: "",
        startsOn: "2026-07-01",
        endsOn: "2026-12-31",
      }).issues,
    ).toBeDefined();
    expect(
      validate(appraisalReviewInputSchema, { rating: 5 }).issues,
    ).toBeUndefined();
    expect(
      validate(appraisalReviewInputSchema, { rating: 9 }).issues,
    ).toBeDefined();
  });
});
