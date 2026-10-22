import { describe, expect, it } from "vitest";

import {
  createLeadScoring,
  leadRuleFields,
  leadScoringBlock,
} from "../../../src/blocks/lead-scoring/index.ts";
import { fakeTransport } from "../inbox/fixtures.ts";

const AT = "2026-01-01T00:00:00Z";

const SCORE = {
  id: "s1",
  organizationId: "org",
  modelId: "m1",
  modelKey: "lead",
  modelName: "Lead",
  modelVersion: 1,
  subjectType: "person",
  subjectId: "p1",
  score: 10,
  band: "warm",
  breakdown: { rules: [], metrics: [] },
  current: true,
  computedAt: AT,
  changed: true,
};

describe("createLeadScoring", () => {
  it("scores a record and reads its lead fields", async () => {
    const { transport, call } = fakeTransport({
      score_lead: SCORE,
      lead_fields: { mail: { sent: 1 }, segments: ["s1"] },
    });

    const leads = createLeadScoring({ transport, tenant: "org" });
    const person = { type: "person", id: "p1" };

    expect(await leads.score(person).orThrow()).toMatchObject({
      score: 10,
      band: "warm",
      changed: true,
    });
    expect(call).toHaveBeenLastCalledWith("better_supabase", "score_lead", {
      tenant: "org",
      subject_type: "person",
      subject_id: "p1",
    });
    expect(await leads.fields(person).orThrow()).toEqual({
      mail: { sent: 1 },
      segments: ["s1"],
    });
  });

  it("returns null fields for a missing record", async () => {
    const { transport } = fakeTransport({ lead_fields: null });

    expect(
      await createLeadScoring({ transport, tenant: "org" })
        .fields({ type: "person", id: "p9" })
        .orThrow(),
    ).toBeNull();
  });

  it("scores the due records as the service role", async () => {
    const service = fakeTransport({ score_leads_due: 3 });

    const leads = createLeadScoring({
      transport: fakeTransport({}).transport,
      service: service.transport,
    });

    expect(await leads.scoreDue({ limit: 5 }).orThrow()).toBe(3);
    expect(service.call).toHaveBeenLastCalledWith(
      "better_supabase",
      "score_leads_due",
      { max_count: 5 },
    );

    const empty = fakeTransport({ score_leads_due: null });

    expect(
      await createLeadScoring({ transport: empty.transport })
        .scoreDue()
        .orThrow(),
    ).toBe(0);
    expect(empty.call).toHaveBeenLastCalledWith(
      "better_supabase",
      "score_leads_due",
      { max_count: 100 },
    );
  });

  it("needs a tenant to score", async () => {
    const { transport } = fakeTransport({});

    const result = await createLeadScoring({ transport }).score({
      type: "person",
      id: "p1",
    });

    expect(result.ok).toBe(false);
  });

  it("declares the rule fields and the manifest", () => {
    const fields = leadRuleFields("person");

    expect(JSON.stringify(fields)).toContain("mail.sent");
    expect(JSON.stringify(fields)).toContain("enrichment.status");
    expect(leadScoringBlock.name).toBe("lead-scoring");
  });
});
