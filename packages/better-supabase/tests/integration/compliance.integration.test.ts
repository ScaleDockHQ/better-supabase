import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";

import { createAcknowledgements } from "../../src/blocks/acknowledgements/index.ts";
import { createCompliance } from "../../src/blocks/compliance/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { upgradePlan } from "../../src/sql/upgrade.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "versions",
  "acknowledgements",
  "compliance",
];

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

const today = (): Temporal.PlainDate => Temporal.Now.plainDateISO("UTC");

describe.skipIf(!live)("compliance", () => {
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
      const acks = createAcknowledgements({ transport: sqlTransport(s.sql) });

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
      ).toBe("CONTROL_FORBIDDEN");
      expect(
        await controls
          .addEvidence(access.id, { attachmentId: crypto.randomUUID() })
          .then(hint),
      ).toBe("CONTROL_INVALID");

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

      const record = { type: "compliance_policy", id: policy.id };

      await s.as(analyst);
      expect(await acks.acknowledge(record).then(hint)).toBe(
        "ACKNOWLEDGEMENT_NO_VERSION",
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
        (await acks.mine(org).orThrow()).map((item) => item.record.id),
      ).toEqual([policy.id]);

      const acknowledged = await acks.acknowledge(record).orThrow();

      expect(acknowledged.versionId).toBe(published.versionId);
      expect(await acks.mine(org).orThrow()).toEqual([]);

      await s.as(owner);
      await controls
        .publishPolicy(policy.id, { body: "Use company devices only." }, "v2")
        .orThrow();
      const roster = await acks.status(record).orThrow();
      expect(roster.versionId).not.toBe(published.versionId);
      expect(roster.acknowledged).toBe(0);
      expect(roster.pending.map((member) => member.userId).toSorted()).toEqual(
        [analyst.id, owner.id].toSorted(),
      );

      const archived = await controls.archivePolicy(policy.id).orThrow();
      expect(archived.archivedAt).toBeDefined();
      expect(
        await controls.publishPolicy(policy.id, { body: "Again" }).then(hint),
      ).toBe("COMPLIANCE_POLICY_ARCHIVED");
      await s.as(analyst);
      expect(await acks.acknowledge(record).then(hint)).toBe(
        "ACKNOWLEDGEMENT_NOT_ASSIGNED",
      );

      await s.asRole(outsider);
      expect(await controls.controls(org).orThrow()).toEqual([]);
      expect(await controls.posture(org).orThrow()).toEqual([]);

      await s.service();

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where type like any (array['control%', 'compliance_policy.%', 'evidence_task.%', 'acknowledgement.%'])",
      );

      expect(new Set(events.map((row) => row.type))).toEqual(
        new Set([
          "control.created",
          "control.evidence_added",
          "evidence_task.missed",
          "compliance_policy.published",
          "acknowledgement.created",
        ]),
      );
    } finally {
      await s.close();
    }
  });

  it("upgrades version 1 policy acknowledgements onto the acknowledgements block", async () => {
    const s = await BlockSession.open(pool);

    try {
      const tenant = crypto.randomUUID();
      const policy = crypto.randomUUID();
      const archived = crypto.randomUUID();
      const version = crypto.randomUUID();
      const user = await s.user("member");

      await s.client.query(
        `create schema compliance_up;
create table compliance_up.versions (id uuid primary key);
create table compliance_up.policies (
  id uuid primary key,
  tenant_id uuid not null,
  requires_acknowledgement boolean not null,
  archived_at timestamptz
);
create table compliance_up.policy_acknowledgements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  policy_id uuid not null,
  version_id uuid not null,
  user_id uuid not null,
  acknowledged_at timestamptz not null
);
create function compliance_up.acknowledge_compliance_policy(policy_id uuid) returns jsonb
language sql as $$ select '{}'::jsonb $$;
insert into compliance_up.versions values ('$version');
insert into compliance_up.policies values
  ('$policy', '$tenant', true, null),
  ('$archived', '$tenant', true, now());
insert into compliance_up.policy_acknowledgements (tenant_id, policy_id, version_id, user_id, acknowledged_at)
values ('$tenant', '$policy', '$version', '$user', '2026-01-02T03:04:05Z');`
          .replaceAll("$version", version)
          .replaceAll("$policy", policy)
          .replaceAll("$archived", archived)
          .replaceAll("$tenant", tenant)
          .replaceAll("$user", user.id),
      );

      const [plan] = upgradePlan([{ module: "compliance", version: 1 }], {
        modules: {
          compliance: { schema: "compliance_up" },
          acknowledgements: { schema: "compliance_up" },
          versions: { schema: "compliance_up" },
        },
      });

      for (const step of [...plan!.steps, ...plan!.steps]) {
        await s.client.query(step.sql);
      }

      expect(
        await s.rows(
          `select tenant_id::text, subject_type, subject_id, version_id::text, user_id::text,
             acknowledged_at = '2026-01-02T03:04:05Z'::timestamptz as kept_at
           from compliance_up.acknowledgements`,
        ),
      ).toEqual([
        {
          tenant_id: tenant,
          subject_type: "compliance_policy",
          subject_id: policy,
          version_id: version,
          user_id: user.id,
          kept_at: true,
        },
      ]);
      expect(
        await s.rows(
          `select subject_id, principal_type, principal_id
           from compliance_up.acknowledgement_assignments`,
        ),
      ).toEqual([
        { subject_id: policy, principal_type: "role", principal_id: "*" },
      ]);
      expect(
        await s.rows(
          `select to_regclass('compliance_up.policy_acknowledgements')::text as old_table,
             to_regprocedure('compliance_up.acknowledge_compliance_policy(uuid)')::text as old_function`,
        ),
      ).toEqual([{ old_table: null, old_function: null }]);
    } finally {
      await s.close();
    }
  });
});
