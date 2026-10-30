import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";

import { createCompliance } from "../../src/blocks/compliance/index.ts";
import { createRisks } from "../../src/blocks/risks/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "versions",
  "relations",
  "compliance",
  "risks",
];

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("risks", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("scores risks on the matrix, links barriers and reports due reviews", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const analyst = await s.user("analyst");
      await s.install(MODULES);
      const org = await s.organization(owner, { member: analyst });
      const transport = sqlTransport(s.sql);
      const risks = createRisks({ transport, tenant: org });

      await s.as(owner);

      const [matrix] = await risks.matrices().orThrow();

      expect(matrix).toMatchObject({ isDefault: true, scoring: "product" });
      expect(matrix?.likelihoodLevels).toHaveLength(5);

      const levels = [1, 2, 3].map((value) => ({ value, label: `L${value}` }));

      const site = {
        key: "site",
        name: "Site",
        likelihoodLevels: levels,
        impactLevels: levels,
        bands: [
          { key: "low", label: "Low", min: 1, max: 3 },
          { key: "high", label: "High", min: 4, max: 9 },
        ],
      };

      expect(await risks.saveMatrix(site).orThrow()).toMatchObject({
        key: "site",
        isDefault: false,
      });
      expect(await risks.saveMatrix(site).then(hint)).toBe(
        "RISK_MATRIX_INVALID",
      );

      expect(
        await risks.create({ title: "Spill", category: "nope" }).then(hint),
      ).toBe("RISK_CATEGORY_UNKNOWN");

      const spill = await risks
        .create({
          title: "Solvent spill",
          category: "environment",
          ownerId: owner.id,
          reviewIntervalMonths: 6,
        })
        .orThrow();

      expect(spill).toMatchObject({
        status: "identified",
        matrixId: matrix?.id,
      });
      expect(spill.number).toMatch(/\d/);

      expect(
        await risks
          .assess(spill.id, {
            inherent: { likelihood: 6, impact: 1 },
            residual: { likelihood: 1, impact: 1 },
          })
          .then(hint),
      ).toBe("RISK_LEVEL_OUT_OF_RANGE");

      const assessed = await risks
        .assess(spill.id, {
          inherent: { likelihood: 4, impact: 5 },
          residual: { likelihood: 2, impact: 3 },
          rationale: "Bunded storage",
        })
        .orThrow();

      expect(assessed).toMatchObject({
        status: "assessed",
        inherent: { score: 20, band: "critical" },
        residual: { score: 6, band: "medium" },
      });

      const heatmap = await risks.heatmap().orThrow();

      expect(heatmap.cells).toHaveLength(25);
      expect(
        heatmap.cells.filter((cell) => cell.count > 0).map((cell) => cell),
      ).toEqual([
        expect.objectContaining({
          likelihood: 2,
          impact: 3,
          count: 1,
          riskIds: [spill.id],
        }),
      ]);

      const compliance = createCompliance({ transport });

      const soc2 = await compliance
        .saveFramework(org, { key: "iso14001", name: "ISO 14001" })
        .orThrow();

      const control = await compliance
        .saveControl({ frameworkId: soc2.id, code: "8.2", title: "Bunding" })
        .orThrow();

      await s.value(
        "better_supabase.link($1::uuid, 'mitigated_by', 'risk', $2::text, 'control', $3::text, null)",
        [org, spill.id, control.id],
      );

      const detail = await risks.get(spill.id).orThrow();

      expect(detail.barriers).toEqual([
        expect.objectContaining({ type: "control", id: control.id }),
      ]);
      expect(detail.assessments).toHaveLength(1);
      expect(detail.assessments[0]?.versionId).toBeDefined();

      await s.as(analyst);
      expect(await risks.list().orThrow()).toHaveLength(1);
      expect(
        await risks.create({ title: "Sneaky", category: "quality" }).then(hint),
      ).toBe("RISK_FORBIDDEN");
      expect(await risks.setTreatment(spill.id, "accept").then(hint)).toBe(
        "RISK_FORBIDDEN",
      );

      await s.as(owner);

      const accepted = await risks
        .setTreatment(spill.id, "accept", "Within appetite")
        .orThrow();

      expect(accepted).toMatchObject({
        treatment: "accept",
        status: "accepted",
      });

      await s.service();
      await s.rows(
        "update better_supabase.risks set next_review_on = current_date - 1 where id = $1",
        [spill.id],
      );
      expect(await risks.notifyDueReviews().orThrow()).toBe(1);
      expect(await risks.notifyDueReviews().orThrow()).toBe(0);

      const notices = await s.rows<{ user_id: string }>(
        `select r.user_id::text as user_id from better_supabase.notification_recipients r
         join better_supabase.notification_events e on e.id = r.event_id
         where e.type = 'risk.review_date_reached'`,
      );

      expect(notices.map((row) => row.user_id)).toEqual([owner.id]);

      await s.as(owner);

      const reviewed = await risks.review(spill.id, "Still bunded").orThrow();

      expect(reviewed.reviewedAt).toBeDefined();
      expect(reviewed.nextReviewOn?.toString()).toBe(
        Temporal.Now.plainDateISO("UTC").add({ months: 6 }).toString(),
      );

      const closed = await risks.close(spill.id, "Solvent replaced").orThrow();

      expect(closed.status).toBe("closed");
      expect(
        await risks
          .assess(spill.id, {
            inherent: { likelihood: 1, impact: 1 },
            residual: { likelihood: 1, impact: 1 },
          })
          .then(hint),
      ).toBe("RISK_CLOSED");
      expect(await risks.list().orThrow()).toEqual([]);

      await s.service();

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where type like 'risk.%'",
      );

      expect(new Set(events.map((row) => row.type))).toEqual(
        new Set([
          "risk.created",
          "risk.assessed",
          "risk.treatment_changed",
          "risk.review_date_reached",
          "risk.reviewed",
          "risk.closed",
        ]),
      );
    } finally {
      await s.close();
    }
  });
});
