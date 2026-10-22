import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";

import { createCompliance } from "../../src/blocks/compliance/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "versions",
  "compliance",
];

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

const today = (): Temporal.PlainDate => Temporal.Now.plainDateISO("UTC");

describe.skipIf(!live)("controls", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("rolls evidence and recurring tasks up into a framework posture", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const analyst = await s.user("analyst");
      const outsider = await s.user("outsider");
      await s.install(MODULES);
      const org = await s.organization(owner, { member: analyst });
      const controls = createCompliance({ transport: sqlTransport(s.sql) });

      await s.as(owner);

      const soc2 = await controls
        .saveFramework(org, { key: "soc2", name: "SOC 2", version: "2017" })
        .orThrow();

      const again = await controls
        .saveFramework(org, { key: "soc2", name: "SOC 2 Type II" })
        .orThrow();

      expect(again).toMatchObject({ id: soc2.id, name: "SOC 2 Type II" });

      const access = await controls
        .saveControl({
          frameworkId: soc2.id,
          code: "CC6.1",
          title: "Logical access",
          ownerId: analyst.id,
        })
        .orThrow();

      const monitoring = await controls
        .saveControl({
          frameworkId: soc2.id,
          code: "CC7.2",
          title: "Monitoring",
        })
        .orThrow();

      await controls
        .saveControl({
          frameworkId: soc2.id,
          code: "A1.1",
          title: "Capacity",
          applicable: false,
        })
        .orThrow();
      expect(access.status).toBe("not_started");

      const task = await controls
        .saveEvidenceTask(monitoring.id, {
          title: "Review alerts",
          intervalDays: 30,
          dueOn: today().subtract({ days: 1 }),
          assigneeId: analyst.id,
        })
        .orThrow();

      expect(task).toMatchObject({ overdue: true, active: true });

      expect(await controls.posture(org).orThrow()).toEqual([
        expect.objectContaining({
          frameworkId: soc2.id,
          total: 3,
          passing: 0,
          failing: 1,
          notStarted: 1,
          notApplicable: 1,
          overdueTasks: 1,
        }),
      ]);

      await s.service();
      expect(await controls.notifyOverdue().orThrow()).toBe(1);
      expect(await controls.notifyOverdue().orThrow()).toBe(0);

      const notices = await s.rows<{ user_id: string }>(
        `select r.user_id::text as user_id from better_supabase.notification_recipients r
         join better_supabase.notification_events e on e.id = r.event_id
         where e.type = 'evidence_task.missed'`,
      );

      expect(notices.map((row) => row.user_id)).toEqual([analyst.id]);

      await s.as(analyst);
      expect(
        await controls
          .saveControl({ frameworkId: soc2.id, code: "X", title: "Sneaky" })
          .then(hint),
      ).toBe("CONTROLS_FORBIDDEN");
      expect(
        await controls
          .addEvidence(access.id, { attachmentId: crypto.randomUUID() })
          .then(hint),
      ).toBe("CONTROLS_INVALID");

      const evidence = await controls
        .addEvidence(access.id, {
          note: "Quarterly access review",
          validUntil: today().add({ days: 90 }),
        })
        .orThrow();

      expect(evidence).toMatchObject({
        controlId: access.id,
        collectedBy: analyst.id,
        valid: true,
      });
      await controls
        .addEvidence(monitoring.id, {
          note: "Alerts reviewed",
          evidenceTaskId: task.id,
        })
        .orThrow();

      const detail = await controls.getControl(monitoring.id).orThrow();
      expect(detail.status).toBe("passing");
      expect(detail.tasks[0]?.dueOn.toString()).toBe(
        today().add({ days: 30 }).toString(),
      );
      expect((await controls.posture(org, soc2.id).orThrow())[0]).toMatchObject(
        { passing: 2, failing: 0, overdueTasks: 0 },
      );

      await s.as(owner);

      const policy = await controls
        .savePolicy(org, { key: "acceptable-use", title: "Acceptable use" })
        .orThrow();

      await s.as(analyst);
      expect(await controls.acknowledgePolicy(policy.id).then(hint)).toBe(
        "POLICY_NOT_PUBLISHED",
      );

      await s.as(owner);

      const published = await controls
        .publishPolicy(
          policy.id,
          { body: "Use company devices for work." },
          "v1",
        )
        .orThrow();

      expect(published).toMatchObject({ versionNumber: 1, memberCount: 2 });

      await s.as(analyst);
      expect(
        (await controls.policies(org, { pendingOnly: true }).orThrow()).map(
          (item) => item.id,
        ),
      ).toEqual([policy.id]);

      const acknowledged = await controls
        .acknowledgePolicy(policy.id)
        .orThrow();

      expect(acknowledged.acknowledgedAt).toBeDefined();
      expect(
        await controls.policies(org, { pendingOnly: true }).orThrow(),
      ).toEqual([]);

      await s.as(owner);
      await controls
        .publishPolicy(policy.id, { body: "Use company devices only." }, "v2")
        .orThrow();
      const roster = await controls.acknowledgements(policy.id).orThrow();
      expect(roster.versionNumber).toBe(2);
      expect(
        roster.members.every((member) => member.acknowledgedAt === undefined),
      ).toBe(true);

      const archived = await controls.archivePolicy(policy.id).orThrow();
      expect(archived.archivedAt).toBeDefined();
      expect(
        await controls.publishPolicy(policy.id, { body: "Again" }).then(hint),
      ).toBe("POLICY_ARCHIVED");
      await s.as(analyst);
      expect(await controls.acknowledgePolicy(policy.id).then(hint)).toBe(
        "POLICY_NOT_PUBLISHED",
      );

      await s.asRole(outsider);
      expect(await controls.controls(org).orThrow()).toEqual([]);
      expect(await controls.posture(org).orThrow()).toEqual([]);

      await s.service();

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where type like any (array['control%', 'policy.%', 'evidence_task.%'])",
      );

      expect(new Set(events.map((row) => row.type))).toEqual(
        new Set([
          "control.saved",
          "control.evidence_added",
          "evidence_task.missed",
          "policy.published",
          "policy.acknowledged",
        ]),
      );
    } finally {
      await s.close();
    }
  });
});
